#!/usr/bin/env python3
"""Messages to players: Social > Inbox (owner, 2026-10-16). Skill: .claude/skills/inbox-messages.

A message is a row of the `messages` table that only its audience can read (row-level permissions):
one player (`user:<id>`, a row each), everyone with a label (`label:early`, one shared row), or
every player (`users`, one shared row, which players who join later see too). What each player did
with it (opened, claimed, deleted) lives in their `profiles.inbox` list, so a gift cannot be edited
and is paid once per player. Nothing is written without --yes.

Players who turned on Settings > Messages from Carden (or Allow in the notification question) get a
notification on their iPhone too: their push target is in the Appwrite Messaging topic
`carden-messages` (lib/state/push.dart, docs/notifications.md). A send pushes to the subscribed
devices of its audience (everyone: the topic; one player or a label: only their subscribed targets)
and says how many; --no-push leaves the notification out. Its tap opens the message.

  python3 tools/dev/inbox.py send --to <userId> --subject "..." --body "..." [options] [--yes]
  python3 tools/dev/inbox.py send --name "Brave Otter" ...      one player by display name
  python3 tools/dev/inbox.py send --label early [--label girlfriend] ...   players with any of these labels
  python3 tools/dev/inbox.py send --all ...                     every player, now and later
  python3 tools/dev/inbox.py send --qa ...                      the newest QA guest (for checking)
      --coins N --tickets N --hints N --peeks N --magics N      a gift (optional)
      --cta-label "Open the pack" --cta-link /library/pack/pack-owls
      --expires 7d | 48h | 2026-12-31T23:59:00Z               leaves the inbox after this
      --at 2026-12-24T08:00:00Z                               shown from this time (default now; the push waits for it)
      --no-push                                               no notification, only the inbox
  python3 tools/dev/inbox.py list                              every message and its audience
  python3 tools/dev/inbox.py list --to <userId>                 what that player sees, and its state
  python3 tools/dev/inbox.py labels <userId> [--add early] [--remove early] [--yes]   a player's labels
  python3 tools/dev/inbox.py expire <messageId> [--yes]        ends a message now
  python3 tools/dev/inbox.py delete <messageId> [<messageId> ...] [--yes]   removes rows
  python3 tools/dev/inbox.py push <messageId> [--yes]          the notification for a message sent with --no-push

Uses secrets/appwrite-users-key.txt (rows read/write, users read). The push goes through the Appwrite
CLI signed in as the owner (`appwrite login`; the keys in secrets/ have no messaging scopes), from a
temporary folder with the project's appwrite.config.json. Key values are never printed.
"""
import argparse
import datetime as dt
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import uuid

sys.path.insert(0, os.path.dirname(__file__))
import cjw_admin as aw  # noqa: E402

TABLE = 'messages'
ROWS = f'/tablesdb/{aw.DB}/tables/{TABLE}/rows'
PROFILES = f'/tablesdb/{aw.DB}/tables/profiles/rows'

# Links the app opens (AppLink.parse): a path, carden://<path> or https://play.carden.page/<path>.
LINK = re.compile(
    r'^(?:(?:carden|cardjigsaw)://|https://play\.carden\.page)?/?'
    r'(library(?:/pack/[\w.-]+)?|pack/[\w.-]+|play/[\w.-]+|picture/[\w.-]+|events|quests|social|leaderboard|friends|inbox|messages|'
    r'feedback|profile(?:/(?:settings|my-puzzles|account))?|settings|my-puzzles|account|store|shop|vip|wheel|lucky-wheel|daily|today|'
    r'quick|quick-play|gift|daily-gift|piggy|piggy-bank|player/[\w.-]+|add-friend)(?:\?[\w=&.%-]*)?$')

# The Messaging topic of Settings > Messages from Carden (PushTopics.messages in lib/state/push.dart).
TOPIC = 'carden-messages'

# A gift bigger than these needs --force (a typo should not hand out a fortune).
LIMITS = {'coins': 10000, 'tickets': 30, 'hints': 30, 'peeks': 50, 'magics': 20}


def utc(s):
    m = re.fullmatch(r'(\d+)([dh])', s or '')
    if m:
        n, unit = int(m.group(1)), m.group(2)
        return dt.datetime.now(dt.timezone.utc) + (dt.timedelta(days=n) if unit == 'd' else dt.timedelta(hours=n))
    t = dt.datetime.fromisoformat(s.replace('Z', '+00:00'))
    return t if t.tzinfo else t.replace(tzinfo=dt.timezone.utc)


def iso(t):
    # Milliseconds, so messages sent one after another keep their order.
    u = t.astimezone(dt.timezone.utc)
    return u.strftime('%Y-%m-%dT%H:%M:%S.') + f'{u.microsecond // 1000:03d}+00:00'


LABEL = re.compile(r'^[A-Za-z0-9]{1,36}$')


def audience(c, a):
    """Who reads the row(s): a list of (userId or '', [permissions])."""
    if a.label:
        bad = [x for x in a.label if not LABEL.match(x)]
        if bad:
            raise SystemExit(f'labels are letters and digits only (up to 36): {bad}')
        return [('', [f'read("label:{x}")' for x in dict.fromkeys(a.label)])]
    if a.all:
        return [('', ['read("users")'])]
    return [(uid, [f'read("user:{uid}")']) for uid in recipients(c, a)]


def recipients(c, a):
    if a.to:
        return list(dict.fromkeys(a.to))
    rows = c.list_all(PROFILES, 'rows', [aw.q('select', values=['$id', 'displayName', 'isTest', '$createdAt'])])
    if a.name:
        hits = [r['$id'] for r in rows if (r.get('displayName') or '').strip().lower() == a.name.strip().lower()]
        if len(hits) != 1:
            raise SystemExit(f'{len(hits)} players are called {a.name!r}; use --to <userId>')
        return hits
    if a.qa:
        qa = sorted((r for r in rows if r.get('isTest')), key=lambda r: r['$createdAt'])
        if not qa:
            raise SystemExit('no QA player right now (start one with tools/dev/qa-run.sh)')
        return [qa[-1]['$id']]
    raise SystemExit('who to? --to, --name, --qa, --label or --all')


def cmd_send(c, a):
    if len(a.subject) > 120:
        raise SystemExit('subject: at most 120 characters')
    body = open(a.body_file).read().strip() if a.body_file else (a.body or '').strip()
    if not body:
        raise SystemExit('--body or --body-file is required')
    if len(body) > 4000:
        raise SystemExit('body: at most 4000 characters')
    if a.cta_link and not LINK.match(a.cta_link):
        raise SystemExit(f'--cta-link {a.cta_link!r} is not a link the app opens (see the skill for the list)')
    if a.cta_label and len(a.cta_label) > 40:
        raise SystemExit('--cta-label: at most 40 characters')
    if a.cta_label and not a.cta_link:
        raise SystemExit('--cta-label needs --cta-link')
    gift = {k: getattr(a, k) or 0 for k in LIMITS}
    over = [f'{k} {v} > {LIMITS[k]}' for k, v in gift.items() if v > LIMITS[k]]
    if over and not a.force:
        raise SystemExit('a big gift: ' + ', '.join(over) + ' (pass --force if you mean it)')
    sent = utc(a.at) if a.at else dt.datetime.now(dt.timezone.utc)
    expires = utc(a.expires) if a.expires else None
    if expires and expires <= sent:
        raise SystemExit('--expires must be after the message is shown')
    rows = audience(c, a)
    data = {
        'subject': a.subject.strip(),
        'body': body,
        'sentAt': iso(sent),
        'expiresAt': iso(expires) if expires else None,
        'rewardCoins': gift['coins'], 'rewardTickets': gift['tickets'], 'rewardHints': gift['hints'],
        'rewardPeeks': gift['peeks'], 'rewardMagics': gift['magics'],
        'ctaLabel': a.cta_label or ((a.cta_link and 'Open') or None),
        'ctaLink': a.cta_link or None,
    }
    gift_text = ', '.join(f'{v} {k}' for k, v in gift.items() if v) or 'no gift'
    who = (f'players with label {" or ".join(a.label)}' if a.label else 'every player' if a.all else f'{len(rows)} player(s)')
    print(f'{who}; "{data["subject"]}" ({gift_text}); shown {data["sentAt"]}'
          + (f', expires {data["expiresAt"]}' if expires else '') + (f'; button {data["ctaLabel"]!r} -> {data["ctaLink"]}' if a.cta_link else ''))
    if not a.yes:
        if a.no_push:
            print('push: none (--no-push)')
        else:
            push_preview(c, [(uid, [readers_of(p) for p in perms]) for uid, perms in rows])
        print('dry run: add --yes to send')
        return
    made = []
    for i, (uid, perms) in enumerate(rows, 1):
        row_id = uuid.uuid4().hex[:20]
        c.call('POST', ROWS, body={'rowId': row_id, 'data': {'userId': uid, **data}, 'permissions': perms})
        made.append({'$id': row_id, '$permissions': perms, **data})
        if len(rows) <= 10:
            print(f'  {row_id} -> {uid or ", ".join(perms)}')
        elif i % 100 == 0:
            print(f'  {i}/{len(rows)}')
    print(f'sent {len(rows)} row(s)')
    if a.no_push:
        print('push: none (--no-push)')
        return
    push_rows(c, made)


# Push ------------------------------------------------------------------------------------------

class PushError(Exception):
    pass


class Messaging:
    """Appwrite Messaging through the Appwrite CLI (signed in as the owner)."""

    def __init__(self):
        if not shutil.which('appwrite'):
            raise PushError('the Appwrite CLI is not installed')
        self.dir = tempfile.mkdtemp(prefix='cjw-inbox-')
        with open(os.path.join(self.dir, 'appwrite.config.json'), 'w') as f:
            json.dump({'projectId': aw.PROJECT, 'endpoint': aw.ENDPOINT}, f)

    def close(self):
        shutil.rmtree(self.dir, ignore_errors=True)

    def cli(self, *args):
        r = subprocess.run(['appwrite', *args, '--raw'], cwd=self.dir, capture_output=True, text=True, timeout=180)
        if r.returncode != 0:
            raise PushError(' '.join((r.stderr or r.stdout).split())[:300] or f'appwrite {args[0]} failed')
        try:
            return json.loads(r.stdout or '{}')
        except json.JSONDecodeError:
            raise PushError(f'appwrite {args[0]}: no JSON answer (signed in? `appwrite login`)') from None

    def topic_devices(self):
        return int(self.cli('messaging', 'get-topic', '--topic-id', TOPIC).get('pushTotal') or 0)

    def subscribed_targets(self, user_ids):
        """The push targets of these players that are in the topic (every page)."""
        out, ids = [], list(dict.fromkeys(user_ids))
        for i in range(0, len(ids), 100):
            cursor = None
            while True:
                args = ['messaging', 'list-subscribers', '--topic-id', TOPIC,
                        '--queries', aw.q('equal', 'userId', ids[i:i + 100]), '--queries', aw.q('limit', values=[100])]
                if cursor:
                    args += ['--queries', aw.q('cursorAfter', values=[cursor])]
                page = self.cli(*args).get('subscribers') or []
                out += [s['targetId'] for s in page if s.get('providerType', 'push') == 'push']
                if len(page) < 100:
                    break
                cursor = page[-1]['$id']
        return list(dict.fromkeys(out))

    def push(self, title, body, link, targets=None, topic=None, at=None):
        args = ['messaging', 'create-push', '--message-id', uuid.uuid4().hex[:20], '--title', title, '--body', body,
                '--data', json.dumps({'link': link}), '--sound', 'default']
        if topic:
            args += ['--topics', topic]
        for t in targets or []:
            args += ['--targets', t]
        if at:
            args += ['--scheduled-at', at]
        return self.cli(*args)


def readers_of(permission):
    m = re.fullmatch(r'read\("([^"]+)"\)', permission)
    return m.group(1) if m else permission


def label_users(c, labels):
    """Every player carrying any of these labels."""
    out = []
    for label in labels:
        out += [u['$id'] for u in c.list_all('/users', 'users', [aw.q('contains', 'labels', [label])])]
    return list(dict.fromkeys(out))


def audience_of(c, who):
    """What a row's readers mean for a push: ('topic', None) for everyone, ('users', [ids]) otherwise."""
    if 'users' in who or 'any' in who:
        return 'topic', None
    users = [w[5:] for w in who if w.startswith('user:')]
    labels = [w[6:] for w in who if w.startswith('label:')]
    return 'users', list(dict.fromkeys(users + (label_users(c, labels) if labels else [])))


def push_text(body, limit=178):
    """The notification's text: the message in one paragraph, cut at a word near [limit] (iOS shows
    about four lines; the whole message is one tap away)."""
    text = ' '.join(body.split())
    if len(text) <= limit:
        return text
    cut = text[:limit - 1]
    if ' ' in cut:
        cut = cut[:cut.rfind(' ')]
    return cut.rstrip(' ,.;:') + '\u2026'


def message_link(row_id):
    # `from=carden` tells the app it is a message from Carden, not a friend's gift (pushKindOf).
    return f'/inbox?message={row_id}&from=carden'


def push_preview(c, rows):
    """Dry run: how many devices a send would reach."""
    try:
        m = Messaging()
    except PushError as e:
        print(f'push: unknown ({e})')
        return
    try:
        total = 0
        for _, who in rows:
            kind, users = audience_of(c, who)
            total += m.topic_devices() if kind == 'topic' else len(m.subscribed_targets(users)) if users else 0
        print(f'push: {total} device(s) with Messages from Carden on')
    except PushError as e:
        print(f'push: unknown ({e})')
    finally:
        m.close()


def push_rows(c, rows):
    """The notification for each written row, to the subscribed devices of its audience."""
    try:
        m = Messaging()
    except PushError as e:
        print(f'push: not sent ({e}); the message is in the inbox. Later: inbox.py push <messageId> --yes')
        return
    now = dt.datetime.now(dt.timezone.utc)
    devices, at = 0, None
    try:
        for row in rows:
            if row.get('expiresAt') and utc(row['expiresAt']) <= now:
                print(f'  {row["$id"]}: expired, no push')
                continue
            sent = utc(row['sentAt'])
            at = iso(sent) if sent > now + dt.timedelta(minutes=1) else None
            kind, users = audience_of(c, [readers_of(p) for p in row.get('$permissions') or []])
            title, body, link = row['subject'], push_text(row['body']), message_link(row['$id'])
            if kind == 'topic':
                n = m.topic_devices()
                if n:
                    m.push(title, body, link, topic=TOPIC, at=at)
                devices += n
                continue
            targets = m.subscribed_targets(users) if users else []
            for i in range(0, len(targets), 100):
                m.push(title, body, link, targets=targets[i:i + 100], at=at)
            devices += len(targets)
        print(f'pushed to {devices} device(s)' + (f', delivered at {at}' if at else ''))
    except PushError as e:
        print(f'push: failed ({e}); the message is in the inbox. Again: inbox.py push <messageId> --yes')
    finally:
        m.close()


def cmd_push(c, a):
    row = c.call('GET', f'{ROWS}/{a.id}')
    if row.get('fromUserId'):
        raise SystemExit('a friend\'s gift: the server pushed it (or chose not to)')
    print(f'{a.id}: "{row["subject"]}" to {", ".join(readers(row))}')
    if not a.yes:
        push_preview(c, [(row.get('userId') or '', readers(row))])
        print('dry run: add --yes to push')
        return
    push_rows(c, [row])


def readers(row):
    """The audience a row names, from its read permissions."""
    out = []
    for p in row.get('$permissions') or []:
        m = re.fullmatch(r'read\("([^"]+)"\)', p)
        if m:
            out.append(m.group(1))
    return out


def user_labels(c, uid):
    try:
        return c.call('GET', f'/users/{uid}').get('labels') or []
    except aw.AppwriteError:
        return []


def cmd_list(c, a):
    every = c.list_all(ROWS, 'rows', [aw.q('orderDesc', 'sentAt')])
    if not (a.to or a.name or a.qa):
        print(f'{len(every)} message(s)')
        for r in every:
            print(f'  {r["$id"]}  {r["sentAt"][:16]}  {r["subject"]!r}  to {", ".join(readers(r))}' + (f'  (expires {r["expiresAt"][:16]})' if r.get('expiresAt') else ''))
        return
    for uid in recipients(c, a):
        try:
            state = set(c.call('GET', f'{PROFILES}/{uid}').get('inbox') or [])
        except aw.AppwriteError:
            state = set()
        mine = {f'user:{uid}', 'users', 'any', *[f'label:{x}' for x in user_labels(c, uid)]}
        rows = [r for r in every if mine & set(readers(r))]
        print(f'{uid} (labels: {", ".join(user_labels(c, uid)) or "none"}): {len(rows)} message(s)')
        now = dt.datetime.now(dt.timezone.utc)
        for r in rows:
            flags = [s for s in ('seen', 'claimed', 'deleted') if f'{s}:{r["$id"]}' in state]
            exp = r.get('expiresAt')
            if exp and utc(exp) <= now:
                flags.append('expired')
            gift = ', '.join(f'{r[k]} {k[6:].lower()}' for k in ('rewardCoins', 'rewardTickets', 'rewardHints', 'rewardPeeks', 'rewardMagics') if r.get(k))
            print(f'  {r["$id"]}  {r["sentAt"][:16]}  {r["subject"]!r}' + (f'  [{gift}]' if gift else '') + (f'  ({", ".join(flags)})' if flags else ''))


def cmd_expire(c, a):
    row = c.call('GET', f'{ROWS}/{a.id}')
    print(f'{a.id}: "{row["subject"]}" to {", ".join(readers(row))}')
    if not a.yes:
        print('dry run: add --yes to end it now')
        return
    c.call('PATCH', f'{ROWS}/{a.id}', body={'data': {'expiresAt': iso(dt.datetime.now(dt.timezone.utc))}})
    print('expired')


def cmd_delete(c, a):
    for rid in a.ids:
        row = c.call('GET', f'{ROWS}/{rid}')
        print(f'{rid}: "{row["subject"]}" to {", ".join(readers(row))}')
        if a.yes:
            c.call('DELETE', f'{ROWS}/{rid}')
            print('  deleted')
    if not a.yes:
        print('dry run: add --yes to delete')


def cmd_labels(c, a):
    now = user_labels(c, a.user)
    want = [x for x in now if x not in (a.remove or [])] + [x for x in (a.add or []) if x not in now]
    bad = [x for x in want if not LABEL.match(x)]
    if bad:
        raise SystemExit(f'labels are letters and digits only (up to 36): {bad}')
    print(f'{a.user}: {", ".join(now) or "no labels"}' + (f' -> {", ".join(want) or "no labels"}' if want != now else ''))
    if want == now:
        return
    if not a.yes:
        print('dry run: add --yes to change them')
        return
    c.call('PUT', f'/users/{a.user}/labels', body={'labels': want})
    print('labels updated')


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest='cmd', required=True)
    for name in ('send', 'list'):
        s = sub.add_parser(name)
        s.add_argument('--to', action='append', help='a player user id (repeatable)')
        s.add_argument('--name', help='one player by display name')
        s.add_argument('--qa', action='store_true', help='the newest QA guest')
        s.add_argument('--all', action='store_true', help='every player, including those who join later (one shared row)')
        s.add_argument('--label', action='append', help='players with this Appwrite label (repeatable; one shared row)')
        if name == 'send':
            s.add_argument('--subject', required=True)
            s.add_argument('--body')
            s.add_argument('--body-file')
            for k in LIMITS:
                s.add_argument(f'--{k}', type=int, default=0)
            s.add_argument('--cta-label')
            s.add_argument('--cta-link')
            s.add_argument('--expires')
            s.add_argument('--at')
            s.add_argument('--force', action='store_true')
            s.add_argument('--no-push', action='store_true', help='no notification, only the inbox')
            s.add_argument('--yes', action='store_true')
    s = sub.add_parser('expire')
    s.add_argument('id')
    s.add_argument('--yes', action='store_true')
    s = sub.add_parser('delete')
    s.add_argument('ids', nargs='+')
    s.add_argument('--yes', action='store_true')
    s = sub.add_parser('push')
    s.add_argument('id')
    s.add_argument('--yes', action='store_true')
    s = sub.add_parser('labels')
    s.add_argument('user')
    s.add_argument('--add', action='append')
    s.add_argument('--remove', action='append')
    s.add_argument('--yes', action='store_true')
    a = p.parse_args()
    c = aw.Client()
    {'send': cmd_send, 'list': cmd_list, 'expire': cmd_expire, 'delete': cmd_delete, 'labels': cmd_labels, 'push': cmd_push}[a.cmd](c, a)


if __name__ == '__main__':
    main()
