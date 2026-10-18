# Notifications

Owner, 2026-10-18 (TestFlight feedback): players are asked about notifications once, in the game's own
style first, with a switch for every kind; and messages from Carden (Social > Inbox) can arrive as
notifications too. iPhone only: the web has no notifications. Friend gifts are in
`docs/friend-gifts.md`; this page covers all four kinds, the question, the switches and the push
plumbing they share.

## The four kinds

| Kind (Settings > Notifications) | Line under it | What | Default | Where it comes from |
| --- | --- | --- | --- | --- |
| Daily reminders | One a day with the daily puzzle | the daily puzzle and gift, at the reminder time | off | local notification (`DailyReminders`, `lib/state/reminders.dart`) |
| New events | The evening before an event opens | a note before a world-day event opens, only for notes 5+ days out (lapsed players) | off (promotional) | local notification (`planEventReminders`) |
| Gifts from friends | When a friend sends you a gift | "Anna sent you a gift" | on | push from `/gift/send` on `api` |
| Messages from Carden | News, gifts and offers in your inbox | a message the owner sent with `tools/dev/inbox.py` | off (promotional) | push from `tools/dev/inbox.py` |

The labels and lines live in one place, `NotificationKind` (`lib/features/notifications/notification_prompt.dart`),
used by both the question and Settings. New events and Messages from Carden can promote events, packs and
offers, so they are off until the player turns them on (guideline 4.5.4): their own switch in Settings, or
Allow in the question, whose switches name them plainly. The four switches are independent: event notes
no longer need the daily reminders (before 2026-10-18 New events showed only under Daily reminders). The
reminder time applies to both local kinds; its row shows while either is on.

One iOS permission covers all four. When iOS stops allowing notifications (iOS Settings), the local
switches turn off on the next start or resume (`RemindersController.refresh`), so event notes need a new
yes; the push switches keep their value and show off until iOS allows notifications again.

## The question (`NotificationPrompt`)

`lib/features/notifications/notification_prompt.dart`. A sheet (`showAppSheet`, glass, not dismissible by a
swipe): a bell, "Turn on notifications?", "Choose what Carden may send you. You can change it any time in
Settings.", the four kinds with a switch each (all on), **Allow** and **Not now**.

- **When**: after the player's **second** finished picture (`NotificationPrompt.afterPictures`,
  `solvedCountProvider`). Not the third: the third opens the Library and Quick play (docs/first-steps.md),
  a moment with enough going on; nothing else happens at the second, and players who leave early mostly do
  so after a board or two, so the second reaches more of them while they have played one picture they chose
  (the first is the guided board). Players from before with more pictures are asked at their next calm moment.
- **Where**: `NotificationPromptHost` (registered with the other hosts in `lib/app.dart`) looks every 2 s
  while the question may be due. It shows it only at a calm moment: the top location is a tab's own page
  (`/home`, `/library`, `/events`, `/social`, `/profile`), the root navigator's top route is that page
  (no sheet, alert, action sheet or pageless route above it, transition finished), no unlock intro is
  waiting, the game has been in front for 5 s, and all of that held for three looks in a row (at least
  4 s). So it never lands on a game, its finish card or celebration, an unlock intro, another host's
  alert (update, sync, Play together) or any sheet, and a player still tapping their way somewhere is not
  interrupted; a moment that is not calm waits for the next. Its buttons answer only once the sheet has
  slid in, so a tap meant for the page below cannot answer it (the first QA run caught a tab tap landing
  on Not now when the sheet came two seconds after the board closed).
- **Never**: on the web; in QA runs (`CJW_QA`) unless a suite sets `NotificationPrompt.allowInQaRuns`; when
  iOS has already answered (then it records `decided` and the switches stay as they are: a player who
  allowed earlier keeps their settings; event notes and messages are never turned on silently); for a
  player who answered a question of an earlier build (`reminderOfferShown`, `giftNotificationsOffer`).
- **Allow**: writes the switches where Settings keeps them (`settings.reminders`, `eventReminders`,
  `giftNotifications`, `messageNotifications`), then asks iOS (`NotificationPermission.ask`: the real
  prompt, not the provisional one). Granted: the reminders are planned and the push target registered with
  its topics (written again after the answer, as the app's resume from the prompt may have planned first).
  Denied: the local switches follow iOS. With every switch off nothing is asked (recorded as `declined`).
  A toast says "Notifications on".
- **Not now**: nothing changes and iOS is not asked.
- **Once**: the answer is stored on the device (`notificationPrompt`: `allowed`, `declined`, `decided`).
- **Analytics**: `notification_prompt_shown` (`pictures`), `notification_prompt_allowed` (the four choices,
  `granted`), `notification_prompt_declined` (`allOff`); `push_permission` (`result`, `from`).

It replaced the two earlier questions, so a player gets one: the reminder question after a daily gift on the
second day ("Get a daily reminder?", Turn on) and the gift question after a first friend, sent gift or
claimed gift ("Know when a gift arrives?"). Those moments now only register a player whom iOS already
allows (`offerGiftNotifications`). No separate ask is left: the Settings switches ask iOS themselves when it
has never been asked, and lead to iOS Settings when it said no.

## Push (gifts and messages)

Apple's push service through Appwrite Messaging, no third-party SDK: providers `apns` (production:
TestFlight, App Store) and `apns-sandbox` (simulators, development builds), chosen from the build's
`aps-environment` (docs/friend-gifts.md, "Push").

`PushRegistration` (`lib/state/push.dart`) keeps one push target per session while iOS allows notifications
and **Gifts from friends or Messages from Carden** is on, and puts it in the topics those switches ask for
(`PushTopics.wanted`):

| Topic (Appwrite Messaging, `subscribe: users`) | A target is in it when | Used by |
| --- | --- | --- |
| `carden-messages` ("Messages from Carden") | Messages from Carden is on | `tools/dev/inbox.py` pushes a message to its subscribers |
| `gifts-off` ("Gift notifications off") | Messages from Carden is on and Gifts from friends is off (the target stays only for messages) | `/gift/send` leaves these targets out |

The app subscribes its own target (`Messaging.createSubscriber`, id `m<targetId>` / `g<targetId>`, so a
second try answers 409 and a switch turned off deletes it without a lookup) and stores what it did with the
target (`pushTarget` in the local store: user, target, topics), so a launch with nothing changed sends
nothing. A new session's target starts in no topic and joins again. Turning both switches off deletes the
target (and Appwrite its subscriptions). Builds before 2.0.0 (128) never subscribe: they get no message
notifications and every gift notification, as before.

Taps: a message push carries the link `/inbox?message=<id>&from=carden` (the app opens the message as for a
gift; `from=carden` is ignored by `AppLink.parse` and tells `pushKindOf` it is a message for `push_opened`
and the in-game toast's icon). A push that arrives while the game is open shows no banner: the inbox reloads
and a toast shows its title.

### The server

`/gift/send` (`giftRecipients` in `functions/api/src/gift/send.js`, and its twin `functions/send-gift`) reads
the `gifts-off` subscribers of the friend: none (the usual case) pushes to the user as before (`users`);
otherwise to the friend's push targets without those (`targets`), and nothing when none is left. It needs
the function scopes **`subscribers.read`** and **`targets.read`**; until they are given, reading the topic
fails and every target gets the gift push (the old behaviour), so the code is safe to deploy first.

The hourly run of `api` also deletes inbox pushes (gift and message links) older than a day from Messaging's
log (`cleanPushLog`), as each gift send already did.

Created on the live project (2026-10-18, additive): the topics `carden-messages` and `gifts-off`. Still to do
(owner, before the build that carries the Messages from Carden switch): give `api` and `send-gift` the scopes
`subscribers.read` and `targets.read` (`functions update` resets every setting it is not given: pass them
all, docs/functions.md), then deploy both functions and run `node tools/dev/api_check.mjs`.

### Sending: `tools/dev/inbox.py`

A send pushes after writing the rows (skill `.claude/skills/inbox-messages`):

- everyone (`--all`): one push to the topic `carden-messages`;
- one player (`--to`, `--name`, `--qa`) or a label (`--label`): only that audience's targets that are in the
  topic (`list-subscribers` by `userId`; a label's players through the Users API), up to 100 targets a push;
- title = subject, text = the message in one paragraph cut near 178 characters, sound default; a message
  shown later (`--at`) is pushed at that time (`scheduledAt`); an expired one is not pushed.

It prints how many devices it pushed to; the dry run says how many it would reach. `--no-push` leaves the
notification out; `inbox.py push <messageId> --yes` sends it later (or again after a failure). The push goes
through the Appwrite CLI signed in as the owner (the keys in `secrets/` have no messaging scopes).

## Checking it

- `test/notifications_test.dart`: when it is asked (second picture, once, earlier questions, iOS answered,
  web, QA), the calm pages, the host (Home after the second picture, never over a game or an alert, never
  again once answered), every switch on, Allow (the real prompt), Allow with iOS saying no, all off, Not now,
  Settings > Messages from Carden.
- `test/friend_gifts_test.dart`: the push registration and its topics.
- `functions/api`: `npm test` (`gift-send.test.mjs`: the gift push without the targets in `gifts-off`, and
  every target when the topic cannot be read; `router.test.mjs`: the hourly push log cleanup).
- `integration_test/notification_prompt_test.dart` (through `tools/dev/qa-run.sh drive`, a fresh install):
  two 3x3 boards, nothing after the first, the question on Home after the second, Allow, the real iOS
  prompt (the host takes that screenshot on `QA_MARK:system_prompt`: Flutter can neither see nor tap it;
  the prompt stays up after the run, even after an uninstall, so reboot the simulator before the next run).
  With `--dart-define=NOTIF_QA_QUIET=true` iOS allows quietly instead and the run goes on: Settings >
  Notifications, then on `QA_MARK:push:<userId>` the host sends that QA player a message with `inbox.py`,
  which arrives as a toast in the game, and its link opens it. First run 2026-10-18 (iPhone 17 Pro
  simulator, iOS 26.5): the question after the second picture, iOS's prompt after Allow, the target in
  `carden-messages`, `inbox.py` "pushed to 1 device(s)", Messaging status sent, delivered 1.
- A message push on a simulator: a QA run with Messages from Carden on, then `python3 tools/dev/inbox.py send
  --qa --subject ... --body ... --yes` (Apple's sandbox delivers to simulators on Apple silicon); delete it
  afterwards with `inbox.py delete <id> --yes`.
