# Friend gifts

Owner decisions (2026-10-17): on a friend's profile a player sends that friend a gift of **1 ticket or
150 coins**, the sender's choice. It costs the sender nothing. **One gift per friend per day**, and (security
review, 2026-10-17) **at most 20 gifts a day** to all friends together. The friend gets an Inbox message ("Anna sent you a gift") with the gift and a Claim button, and on
iPhone a notification at the same moment whose tap opens that message. The gift **expires 24 hours after
it was sent**; after that it is gone and cannot be claimed. Web players get the message and the Inbox
dot, no notification.

## The flow

1. Player > **Send a gift** (`SendGiftButton`, `lib/features/social/friend_gifts.dart`), shown on the
   profile of a player in the viewer's friends list (not blocked). An action sheet offers "1 ticket"
   and "150 coins" with their icons; the choice goes to the function, and a toast says what happened
   ("Gift sent to Anna", "You already sent Anna a gift today"). Once today's gift is sent the button
   reads "Next gift tomorrow".
2. The server (`/gift/send` on the `api` function) checks and writes everything (below) and sends the push.
3. The friend sees the message in Social > Inbox (the Social tab and the Inbox segment get the dot). Its
   gift card names the friend ("A gift from Anna", with their avatar) and holds **Claim**: the Inbox's
   own claim (`SyncOp.inbox`, `profiles.inbox`, ledger reason `inbox:<id>`), so a gift is paid once on
   every device.
4. At `expiresAt` the message leaves the inbox, also while it is on screen (`inboxProvider` sets a
   timer for the next expiry); a Claim tapped after it refuses with "This gift has expired".
5. The tapped notification opens `/inbox?message=<id>` (`AppLink.parse`, docs/deep-links.md): Social >
   Inbox with the message open. A notification that arrives while the game is open shows no banner (as
   the reminders); the inbox reloads and a toast names the gift.

## The server: `/gift/send`

`functions/api/src/gift/send.js` and `gift.js` in the `api` function (docs/functions.md; execute `users`,
guests too). Builds up to 124 call the function `send-gift` at `POST /send`: the same code, frozen,
deployed for them (scopes `rows.read`, `rows.write`, `messages.read`, `messages.write`).

`POST /gift/send { friendId, kind: 'tickets' | 'coins', utcOffset }`, the caller from
`x-appwrite-user-id`. In order:

1. The caller has the friend in their friends list (a `friends` row `userId = caller`, `friendId =
   friend`). Friend lists are one-way in Carden: the friend does not need to have added the sender.
2. Neither player blocked the other (`blocks`, both directions), and the friend's profile exists.
   Otherwise `unavailable` (the app says "This gift could not be sent", never who blocked whom).
3. The gift row: `gifts/<md5(sender:friend:day)>`. Creating it twice fails, so a second gift the same
   day answers `already`, whatever device or tap sent it.
4. The message: a `messages` row readable only by the friend (`read(user:<friend>)`), `sentAt` now,
   `expiresAt` 24 hours later, `rewardTickets: 1` or `rewardCoins: 150`, `fromUserId`, `fromName` (the
   sender's name through the name filter) and `fromAvatar`. If it cannot be written, the gift row is
   taken back so the sender can try again.
5. The push, only when the friend has the sender in their friends list too and has had at most 5
   gifts in the last 24 hours (`shouldPush`; later gifts land in the inbox quietly, `pushed: false`):
   Appwrite Messaging `createPush` to the friend's push targets, without those that turned gift
   notifications off while keeping Messages from Carden on (topic `gifts-off`, `giftRecipients`;
   docs/notifications.md),
   title "Anna sent you a gift", body "1 ticket is waiting in your inbox." (or "150 coins are
   waiting..."), data `{ link: '/inbox?message=<id>' }`, sound default. A friend with no device
   registered (web, notifications off) simply gets no push; the inbox has the gift either way.
6. Answers `{ ok: true, kind, amount, friendName, day, messageId, pushed }` (`pushed`: Appwrite
   accepted the push) or `{ ok: false, error }` with `not-friend`, `unavailable`, `already`, `limit`
   (20 sent today; the app says "That's all your gifts for today. More tomorrow."), `kind`, `signin` or
   `server`. The daily limit is checked before the gift row is made.

The amounts live in `KINDS` (`functions/api/src/gift/gift.js`, and the frozen `functions/send-gift/src/gift.js`);
the app shows the same (`GiftKind`, `lib/state/friend_gifts.dart`; `test/friend_gifts_test.dart` checks all three agree).

**The day.** The limit counts the sender's own calendar day: the app sends its offset from UTC
(`DateTime.timeZoneOffset`), the function keeps it within real time zones (UTC-12 to UTC+14, whole
quarter hours) and takes the date there. The app reads the same row id to show "Next gift tomorrow"
(`giftSentProvider`), and the answer turns at the player's midnight. A player who changes the
device's time zone can send at most one extra gift in that day.

**Names.** The push is drawn by iOS, not the app, so the function filters the sender's name with a copy
of `NameFilter` (`shownName` in `gift.js`; `test/friend_gifts_test.dart` fails when the word lists
differ): offensive names, and since 2026-10-17 names with a link, an @handle, an e-mail address or a
domain (`isContact`, the `TLDS` list), show as "Player". The app shows `fromName` through `NameFilter`
again.

**The push log.** Appwrite keeps every push it sends (title, body, recipient) in Messaging's log. Each
send deletes gift pushes older than a day from it (`cleanupPushLog`), so it never holds a gift for long.

**QA.** A gift between QA players (or to or from one) carries `gifts.isTest`. The purge tool and
account deletion remove gifts in both directions and the messages a player sent as gifts
(`PAIR_TABLES` in `tools/dev/cjw_admin.py`, `functions/api/src/account.js` and its twin `functions/delete-account`).

## Tables

- `gifts` (2026-10-17): `senderId`, `recipientId`, `day` (the sender's `YYYY-MM-DD`), `kind`, `amount`,
  `messageId`, `sentAt`, `isTest`. Row id `md5("<sender>:<recipient>:<day>")`. Row permissions only:
  the sender reads their own rows; only the function writes. Indexes `idx_sender_day`, `idx_recipient`.
- `messages` gained `fromUserId`, `fromName`, `fromAvatar` (optional, empty for messages from Carden;
  index `idx_from`). Builds before friend gifts show such a message as one from Carden ("A gift from
  Carden" on the card) and claim it the same way.

## Push (iPhone)

No third-party SDK: Apple's push service through Appwrite Messaging.

- **Providers** (Appwrite Messaging, set up 2026-10-17): `apns` sends through Apple's production
  service (TestFlight and App Store builds), `apns-sandbox` through the development one (simulators,
  debug builds and device builds signed for development). Both use the APNs key `2QJPJFW8JW` (team
  `C24QP73SQM`, topic `com.matejbaco.cardjigsawworld`). The key is also the Sign in with Apple key.
- **App ID**: Push Notifications is on for `com.matejbaco.cardjigsawworld`. The App Store profile used
  by CI ("CJW AppStore cardjigsawworld") was made again after it and carries `aps-environment =
  production`.
- **Entitlement**: `Runner.entitlements` has `aps-environment = $(APS_ENVIRONMENT)`; the Runner target
  sets `APS_ENVIRONMENT` to `development` for Debug and Profile and `production` for Release, so the CI
  archive (Release, signed by hand with the App Store profile) matches its profile.
- **Which provider**: `GiftPush.environment` (`ios/Runner/AppDelegate.swift`) reads `aps-environment`
  from the app's embedded provisioning profile (`development` on the simulator; App Store and
  TestFlight builds have no embedded profile and use production), and `PushProviders.forEnvironment`
  picks the provider. A token only works with the service of its build.
- **Registration** (`PushRegistration`, `lib/state/push.dart`): once iOS allows notifications and
  Settings > Gifts from friends or Messages from Carden is on (docs/notifications.md: the target then
  joins the topics those switches ask for), the app asks iOS for the device token
  (`registerForRemoteNotifications`, channel `cjw/push`) and registers it with
  `account.createPushTarget(identifier: token, providerId)`. Appwrite ties the target to the session:
  one per session and provider (a new token updates it), and it is deleted with the session. So a
  sign-in, a switch to another account or a guest save merged into an account (each a new session)
  registers again, as does a token change; a 409 (the token belongs to an earlier session of the same
  player) updates that target. A token can belong to one Appwrite user at a time.
- **Permission**: one for every kind of notification, asked by the notification question after the
  second finished picture (docs/notifications.md; since 2026-10-18 it replaced the gift question "Know
  when a gift arrives?" after a first friend or gift, whose moments now only register a player iOS
  already allows). Settings > Gifts from friends turns it off and on: off deletes the target, or, while
  Messages from Carden is on, puts it in the topic `gifts-off`.
- **Taps**: `DailyReminders` stays the notification delegate; remote notifications go to `GiftPush`,
  which hands the link to Dart (`open`, or the link that launched the app on `ready`), and
  `DeepLinks.show` opens it.

## Checking it

- `node --test functions/api/test/gift.test.mjs`: gifts, day, row id, copy, names. Live: `node tools/dev/api_check.mjs`.
- `test/friend_gifts_test.dart`: the app agrees with the function; push registration follows sign-ins,
  updates on a conflict, stops when switched off. `test/inbox_test.dart`: gifts leave on time, the
  friend's name. `test/deep_links_test.dart`: `/inbox?message=` in every form, and the sheet it opens.
- `integration_test/friend_gifts_test.dart` (through `tools/dev/qa-run.sh drive`): Player > Send a gift,
  the action sheet, "Next gift tomorrow", the server refusing a second gift, the friend's gift in the
  inbox, its link opening the message, Claim. The friend comes from `tools/dev/gift_qa.py` (a QA player
  in the same run, acting through the real server (`/gift/send` on `api`) with its own session; `end` before the purge).
- `tools/dev/notification_check.sh <simulator>`: the parts Flutter cannot drive, on a real push. A fresh
  QA install turns on Settings > Gifts from friends, taps Allow on the iOS prompt and goes to the
  background; a QA friend sends a ticket; the banner shows; its tap opens the message; Claim. It adds a
  temporary UI test target (`tools/dev/notification_check/`), puts the Xcode project back and purges
  the run. Simulators on Apple silicon get real pushes from Apple's sandbox service.
- First run (2026-10-17, iPhone 17 Pro simulator, iOS 26.5): the push target registered with
  `apns-sandbox`, Appwrite reported the push `sent` (delivered 1), the banner "Carol QA sent you a
  gift / 1 ticket is waiting in your inbox." showed over the Home Screen, and its tap opened the
  message, whose Claim added the ticket. The production provider (`apns`) is first used by a
  TestFlight build.

## Known limits

- Gifts cost nothing, so several accounts could send one player a gift each every day. The daily limit
  per friend is the only cap (owner's choice).
- A token whose earlier session this device lost (a reinstall with the same token) stays with that
  session until it ends; until then this player gets no pushes on this device.
- No web push. Android builds have no registration.
