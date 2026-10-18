---
name: inbox-messages
description: Send, list, expire or delete messages in Carden players' inboxes (Social > Inbox) to one player, players with an Appwrite label (early, girlfriend, ...) or everyone, with an optional gift and a button that opens a place in the app; manage player labels. Use for any request to message players, send a gift or apology, announce something in the app, label players, or look at what a player received.
---

# Inbox messages

Social > Inbox shows messages from Carden (owner, 2026-10-16). Only the owner sends them, through
`tools/dev/inbox.py`; players cannot write. Never send a message on your own initiative: every
send needs the owner's request, and every `--all` or `--label` send needs the owner's explicit go
for that exact text and audience.

## Audiences (row-level permissions)

Every message row names who may read it, and Appwrite returns each player only the rows they may
read; the app does not filter by player.

| Flag | Row permission | Rows |
| --- | --- | --- |
| `--to <userId>` (repeatable), `--name "..."`, `--qa` | `read("user:<id>")` | one per player, `userId` set |
| `--label early` (repeatable: `--label early --label girlfriend` = either) | `read("label:early")` | one shared row, `userId` empty |
| `--all` | `read("users")` | one shared row; players who join later see it too |

Labels are Appwrite user labels (letters and digits, up to 36). Give or take them with
`python3 tools/dev/inbox.py labels <userId> --add early --yes` (`--remove early`; without flags it
shows them). A label message reaches whoever carries the label when they open the inbox, so
labelling a player later still shows them the message (until it expires). Each player's opened,
claimed and deleted state is their own, also for shared rows.

## How it works

- Table `messages` (database `cjw`): `userId` (empty on shared rows), `subject` (120), `body` (text),
  `sentAt` (shown from then on, so a future time schedules it), `expiresAt` (optional; the message
  leaves the inbox after it), `rewardCoins`, `rewardTickets`, `rewardHints`, `rewardPeeks`,
  `rewardMagics` (0 = none), `ctaLabel` (40), `ctaLink` (300). Row permissions only (see
  Audiences), no table permissions, so the audience can read and nobody can change a gift.
- What the player did lives in their profile: `profiles.inbox` holds `seen:<id>`, `claimed:<id>`
  and `deleted:<id>`, written by `SyncOp.inbox` (lib/data/sync/ops.dart). A gift is paid once per
  message on every device (ledger reason `inbox:<id>`).
- **Notification**: players who turned on Settings > Messages from Carden (or Allow in the
  notification question; off by default, it can carry offers) have their iPhone's push target in the
  Appwrite Messaging topic `carden-messages`. A send pushes the message to its audience's subscribed
  devices: everyone (`--all`) through the topic, one player or a label to only their subscribed
  targets. Title = subject, text = the body cut near 178 characters, the tap opens the message
  (`/inbox?message=<id>&from=carden`). It prints `pushed to N device(s)`, the dry run how many it would
  reach. `--no-push` sends the message without it; `push <messageId> --yes` sends it later. A message
  shown later (`--at`) is pushed then; builds before 2.0.0 (128) never get one. Details:
  docs/notifications.md.
- The app reads the rows it may read on launch, on resume and when the inbox is pulled down
  (lib/state/inbox.dart). An unopened message puts a dot on the Social tab and on the Inbox
  segment, also while they are shown, until it is opened. A gift card in the message explains
  the gift and holds **Claim** (then "Claimed"); **Close** closes it. Players can delete messages.
- Friend gifts (docs/friend-gifts.md) are messages too: rows the server (`/gift/send` on function `api`) writes for the
  friend, with `fromUserId`, `fromName` and `fromAvatar` and a 24-hour `expiresAt`; `list --to`
  shows them with the others. Never send a gift "from" a player with this tool.
- Deleting an account deletes its own messages (`/account/delete` on function `api`, `PLAYER_TABLES` in
  tools/dev/cjw_admin.py); QA purges remove them too. Shared rows (labels, everyone) stay until
  you delete or expire them.

## Commands

```
python3 tools/dev/inbox.py send --to <userId> --subject "..." --body "..." [gift] [button] [--expires 7d] [--at ISO] [--yes]
python3 tools/dev/inbox.py send --name "Brave Otter" ...   one player by display name
python3 tools/dev/inbox.py send --label early ...          players with the label (one shared row)
python3 tools/dev/inbox.py send --all ...                  every player, now and later (one shared row)
python3 tools/dev/inbox.py send --qa ...                   the newest QA guest (to check a message)
python3 tools/dev/inbox.py send ... --no-push              the inbox only, no notification
python3 tools/dev/inbox.py push <messageId> [--yes]        the notification for a message sent with --no-push (or again)
python3 tools/dev/inbox.py list                            every message and its audience
python3 tools/dev/inbox.py list --to <userId>              what that player sees, with its state (seen, claimed, deleted, expired)
python3 tools/dev/inbox.py labels <userId> [--add L] [--remove L] --yes   a player's labels
python3 tools/dev/inbox.py expire <messageId> --yes        ends a message now
python3 tools/dev/inbox.py delete <messageId> [...] --yes  removes rows
```

Without `--yes` every command is a dry run that prints what it would do. The push goes through the
Appwrite CLI signed in as the owner (`appwrite login`; the API keys in secrets/ have no messaging
scopes): without it a send still writes the message and says the push was not sent. Gift flags: `--coins`,
`--tickets`, `--hints`, `--peeks`, `--magics`; above 10,000 coins, 30 tickets or hints, 50 Peeks
or 20 Magic it refuses unless `--force`. Find a player's user id with `tools/dev/purge_test_players.py
audit` (QA players), the Appwrite console (Auth), a report or feedback row, or `--name`.

## The button (CTA)

`--cta-link` takes any link the app opens (`AppLink.parse`), as a path, `carden://...` or
`https://play.carden.page/...`; `--cta-label` names it (default "Open"). Useful ones:

| Link | Opens |
| --- | --- |
| `/feedback` | Send feedback sheet |
| `/library/pack/<packId>` | a pack |
| `/play/<puzzleId>` | a picture's difficulty screen |
| `/daily` | today's daily puzzle |
| `/events` | Quests (and live events) |
| `/store`, `/vip` | the Store, or its VIP plans |
| `/wheel`, `/gift`, `/piggy` | Lucky Wheel, daily gift, piggy bank |
| `/social?tab=friends`, `/inbox` | Social tabs |
| `/profile/settings`, `/my-puzzles`, `/account` | settings, My Puzzles, sign in |

A new screen needs its link added in `lib/core/app_links.dart` first (docs/deep-links.md).

## Writing them

Follow docs/copy-guide.md: calm, warm, short. The subject says what it is in a few words ("A
thank-you gift", "New pack: Owls at Night"); the body is two or three plain sentences, no hype, no
exclamation marks, no emojis; a gift is named in the body when there is one ("Here are 500 coins
for your next pack."). CTA labels start with a verb and name the place ("Open the pack", "Send
feedback"). Use `--expires` for anything tied to a date (an event, a sale) and leave it off for a
personal note.

## Checking a message on a device

Run a QA build (`tools/dev/qa-run.sh run -d <simulator or chrome>`), then
`python3 tools/dev/inbox.py send --qa --subject ... --yes`, pull down the inbox (or bring the app to
the front) and open it. For the notification, turn on Settings > Messages from Carden in that run
first (allow notifications), put the game in the background, then send: Apple's sandbox delivers to
a simulator on Apple silicon and the send prints `pushed to 1 device(s)`. The QA purge at the end removes the guest and its own messages; delete any
label or everyone messages made for the check. `integration_test/inbox_test.dart` plays the whole
path, including a label the guest carries and one it does not.
