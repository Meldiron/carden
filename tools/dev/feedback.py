#!/usr/bin/env python3
"""Player feedback (Settings > Send feedback in the app, table `feedback`): read and resolve it.

    python3 tools/dev/feedback.py                            newest first, with the player's current name
    python3 tools/dev/feedback.py --open                     only the ones not resolved yet
    python3 tools/dev/feedback.py --player ID                everything one player sent
    python3 tools/dev/feedback.py --resolve ROWID --note "..."  mark a message handled (what was done)
    python3 tools/dev/feedback.py --reopen ROWID             mark it open again

Feedback is kept for good (owner, 2026-10-19): resolving sets `status` to `resolved` with
`resolvedAt` and the `resolution` note, and never deletes the row. Rows from builds before the
status columns read as open. Feedback has no reply channel: the sheet tells players to use Contact
support (contact@almostapps.eu) for an answer; a thank-you goes to their Inbox
(tools/dev/inbox.py). Messages are deleted only with the player's account (`/account/delete` on
function `api`) and with QA players (tools/dev/purge_test_players.py).
Key: secrets/appwrite-users-key.txt (rows read/write); values are never printed.
"""
import argparse
import datetime
import sys
import textwrap

import cjw_admin as aw


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--player', help='only messages from this user id')
    ap.add_argument('--open', action='store_true', help='only messages not resolved yet')
    ap.add_argument('--resolve', metavar='ROWID', help='mark this feedback row resolved')
    ap.add_argument('--note', help='with --resolve: what was done (up to 500 characters)')
    ap.add_argument('--reopen', metavar='ROWID', help='mark this feedback row open again')
    args = ap.parse_args()
    c = aw.Client()
    if args.resolve:
        now = datetime.datetime.now(datetime.timezone.utc).isoformat(timespec='milliseconds')
        c.update_row('feedback', args.resolve, {'status': 'resolved', 'resolvedAt': now, 'resolution': (args.note or '')[:500] or None})
        print(f'resolved {args.resolve}')
        return
    if args.reopen:
        c.update_row('feedback', args.reopen, {'status': 'open', 'resolvedAt': None, 'resolution': None})
        print(f'reopened {args.reopen}')
        return
    queries = [aw.q('orderDesc', '$createdAt')]
    if args.player:
        queries.append(aw.q('equal', 'userId', [args.player]))
    rows = c.rows('feedback', queries)
    if args.open:
        rows = [r for r in rows if r.get('status') != 'resolved']
    if not rows:
        print('no feedback')
        return
    names = {}
    for r in rows:
        pid = r.get('userId')
        if pid not in names:
            try:
                profile = c.row('profiles', pid) or {}
                names[pid] = profile.get('displayName', '(no profile)') + (' [QA]' if profile.get('isTest') else '')
            except aw.AppwriteError:
                names[pid] = '(no profile)'
    for r in rows:
        resolved = r.get('status') == 'resolved'
        state = f"resolved {(r.get('resolvedAt') or '')[:10]}" if resolved else 'open'
        print(f"{r['$createdAt'][:16]}  {r['$id']}  [{state}]  {names[r.get('userId')]!r} ({r.get('userId')})  {r.get('platform') or '?'} {r.get('appVersion') or ''}")
        print(textwrap.indent(r.get('message', ''), '    '))
        if resolved and r.get('resolution'):
            print(textwrap.indent('-> ' + r['resolution'], '    '))
        print()


if __name__ == '__main__':
    sys.exit(main())
