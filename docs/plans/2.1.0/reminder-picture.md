# Today's picture in the daily reminder

Status: planned for 2.1.0, not started. Picked by the owner on 2026-10-20.

## How to work on this task

- Branch: `2.1.0/reminder-picture`, which starts with this brief. Work and push only there
  (`git push -u origin 2.1.0/reminder-picture`). Never merge it into main or push to main: that is the owner's call. This
  overrides CLAUDE.md's "push to origin main" for this task.
- Check the branch out in its own worktree (`git worktree add <folder> 2.1.0/reminder-picture`): another session may be
  using the main checkout.
- No TestFlight or App Store builds, no web deploys (`tools/dev/deploy-web.sh`), no installs on the owner's iPhone. Pushing
  the branch starts no CI (`.github/workflows/ci.yml` runs on main and pull requests only). The device check in QA waits for
  a build the owner asks for.
- This task changes nothing on the live backend. If that changes, ask the owner first: live changes count as deployments.
- Everything else in CLAUDE.md applies: the gates (`flutter analyze --fatal-infos --fatal-warnings`, `flutter test`), QA only
  through `tools/dev/qa-run.sh`, commits with the owner's git identity and explicit paths.

## Summary

Daily reminders show the day's daily puzzle picture: a small square on the banner, on the Lock Screen and in
Notification Center, and the whole picture when the player presses and holds the notification. The New events note
(the evening before an event opens) shows the event's cover the same way. Text, time and tap stay as in 2.0.0, and a
reminder whose picture is not on the iPhone goes out with text only. iPhone only; nothing changes on the server.

## Why

- A reminder is the one moment Carden reaches a player outside the game, and it announces a picture. That picture is
  known a week ahead, is already in our Storage, and the Home Screen widget shows it from the same address. So the
  feature needs no permission, extension or backend work.
- Evidence: Airship, a push vendor, found that Android notifications with a picture had a 56% higher direct open rate
  on average (2016, nearly 5 million messages):
  https://www.airship.com/company/press-releases/data-finds-pictures-boost-direct-response-rates-for-push-notifications-56-p/
- What weakens it: it reaches only players who allowed notifications and turned on Daily reminders or New events, and
  both are off by default. The data is old, vendor-made and from Android, which shows a large picture in the shade.
  iOS shows a small square until the player presses and holds, so the effect is likely smaller. The text already names
  the picture. Hidden previews hide it, and Focus or Scheduled Summary can delay it. At our size we cannot run a fair
  test (decision 6).

## What the player sees

| Where | Daily reminder | New events note |
| --- | --- | --- |
| Banner (unlocked, game not in front) | Today's text (for example "Today's daily puzzle" and "<title> is ready, and so is your daily gift.") with a small square of the picture at the trailing edge | "<Event> opens tomorrow" and its line, with a square of the event's cover |
| Lock Screen, Notification Center | The same row with the square | The same |
| Press and hold (or pull the banner down) | The whole picture above the text | The whole cover |
| Tap | As today: the day's daily puzzle (`/play/<id>`), or Home on a day with no known picture | As today: the event's pack, or Quests |
| Game in front | Nothing, as today (`willPresent` passes no options) | The same |

The iOS 26 look (the size and place of the square, the height of the expanded picture) is unverified; see QA.

- **Picture missing** (not downloaded yet, failed, or refused by iOS): text only, as in 2.0.0. The next pass with the
  game in front adds it. **Offline**: reminders still come, since they are local, with the pictures fetched earlier.
- **Daily reminders off**: nothing is planned or downloaded for them. New events alone fetches only covers, and with
  both off the folder is deleted. **Web and Android**: nothing (`supportsNotifications` is false).
- **iOS Show Previews set to Never**: only the app icon and "Notification", with no text or picture (Apple's
  notification guidelines). **Provisional delivery** (as in QA runs): Notification Center only, with no banner; whether
  the square shows there is unverified.
- **Copy**: no new strings; next month's days get the named text instead of "A new picture is ready, and so is your
  daily gift." (decision 2). **Settings** (decided): no new switch. The picture is the day's own content and costs
  little, and iOS's Show Previews already hides it for anyone who wants that.

## Rules and edge cases

**How it works today (2.0.0).** `RemindersController.refresh` runs at start (post-frame in `_setUpReminders`), on
`resumed` and `paused` (`lib/app.dart`), and after every Settings change. It plans seven days at the reminder time
(`planReminders`) and event notes at least 5 days out (`planEventReminders`). `ReminderChannel.schedule` then replaces
every pending `cjw.reminder.*` request (`UNCalendarNotificationTrigger`, thread `daily`, the route in `userInfo`).
Today's reminder drops out once the daily gift is claimed or the daily puzzle is solved, and the next pass removes it.
A tap sends the route as `open` (or through `ready` at a cold start); `/play/` routes are pushed, others use `go`.

1. **Daily picture**: the daily puzzle dated that day (row `daily-YYYY-MM-DD`, pack `daily-YYYY-MM`) in the catalogue
   copy on the device, released or not (decision 2). **Event picture**: the pack's `coverUrl`, else the event row's.
2. **Our Storage only**: an address outside `https://fra.cloud.appwrite.io/v1/storage/buckets/puzzle-images/` gets no
   picture. That includes another host, `user-uploads` and `private-packs`.
3. **Downloads**: only with the game in front (start, resume, a Settings change, the catalogue's first load). Never in
   the pass made as it goes to the background, since iOS suspends the app seconds later. Two at a time, 20 s each,
   with no retry in the same pass.
4. **Plan first, picture later**: every pass schedules at once with the files already on the iPhone. When a download
   lands, it schedules again, and only the requests that changed are replaced.
5. **Files**: one per address in `Library/Caches/reminder-pictures/`, never in SharedPreferences. Each is written as
   `.part` and renamed when complete. A file is kept while a planned note uses it, and deleted by name (never by age)
   once none does.
6. **Checks**: HTTP 200, JPEG or PNG by the first bytes, and at most 5 MB. Apple allows JPEG, GIF or PNG images up to
   10 MB.
7. **Native**: copy the file first, because iOS moves the file it is given into its attachment store. The thumbnail
   is a centred square (decision 3). If iOS refuses the attachment, add the reminder again without it: Apple does not
   schedule a request whose attachment is corrupt, invalid or of an unsupported type.
8. **Unchanged requests stay**: when the signature in `userInfo` (`sig`: time, title, body, route, attached address)
   matches, nothing is copied or re-added. So leaving the game usually costs nothing.
9. **Replaced pictures and month ends**: a picture the content tool replaced has a new file id, and the next foreground
   pass swaps it. The next month comes from the device copy (content is made months ahead); a month not in the copy
   gets text only and opens Home.
10. **Day change while suspended**: the date-based catalogue providers stay on the old day, so a tap on the 1st of a
    month would show "Picture not available" (decision 7).
11. **Delivered reminders**: daily reminders delivered on earlier days are removed when the game plans (decision 5).
    Apple limits each app's attachment space but does not give the size.
12. **Updating from 2.0.0**: old pending requests have no signature, so the first pass replaces them all. A pass that
    ran before the catalogue loaded (its 15 s read timed out) plans again once it has.

## Data and backend

Nothing new on Appwrite: no table, column, function, bucket, permission or setting. Builds before 2.1.0 keep their
text-only reminders, and nothing they read changes.

- **Rows**: no new reads. The plan uses the device's catalogue copy. The snapshot and the delta read every row with no
  release filter, so future daily months and event packs are in it (`functions/catalog-snapshot/src/main.js`,
  `lib/state/catalog_sync.dart`).
- **Storage**: the public bucket `puzzle-images`, read with plain GETs and no session:

| Note | Address (decision 1a) | Same as |
| --- | --- | --- |
| Daily reminder | the puzzle's `imageUrl` (`/view`) as `/preview?project=<project>&width=1080&quality=90` | the Home Screen widget (`DailyPicture.previewURL`) |
| New events note | the pack's `coverUrl` as stored (`/preview?width=1080&quality=82`) | Library and Quests covers |

- **Format**: expected to be JPEG, since the hosted daily pictures are JPEGs at most 1200 px wide
  (`docs/content-rules.md`). It is unverified that Appwrite keeps the original's format when `output` is not given, so
  the first QA run checks `pictureType`. Never use `AppwriteConfig.filePreviewUrl`: it asks for `output=webp`, and iOS
  refuses WebP attachments.
- **Volume**: a few hundred KB a file (estimate; measure in QA). The first pass fetches up to 7 pictures and 6 covers,
  then about one a day. Both addresses already exist, so Storage makes no new resized copies.

## App changes

The download happens in Dart, so planning, fallbacks and cleanup stay in one tested place; Swift only attaches the file
it is given. No new dependency: `HttpFileService` from flutter_cache_manager (as in `ImageFiles._public`),
`path_provider`, and Apple's UserNotifications and ImageIO. The app still talks only to our Storage and to Apple.

- **`lib/state/catalog.dart`**: add `dailyPuzzlesAheadProvider`, the dated puzzles of every daily pack row that is not
  hidden, released or not (`retry: _followCatalog`). It is for reminders only; screens keep `allPuzzlesProvider`.
- **`lib/state/reminders.dart`**: `ReminderNote.picture` holds the address or null. `toJson({String? file})` adds
  `picture` and `file` (an absolute path, or empty). `planReminders` sets the picture from the day's `imageUrl`.
  `UpcomingEvent.cover` (from `upcomingEvents`: the pack cover, then the event cover) goes through `planEventReminders`.
- **`RemindersController.refresh({bool fetch = true})`**: plans and schedules with the files on disk. With `fetch`, it
  then runs one prefetch at a time for the missing addresses, schedules again when files land, and prunes. Passes run
  one at a time and never wait for a download. It reads `dailyPuzzlesAheadProvider`, plans again when the catalogue
  loads, and clears the folder when it cancels. A QA-only define, `CJW_QA_REMINDER_SOON` (read only when
  `QaRun.enabled`), puts today's reminder 2 minutes after the pass without saving the time.
- **`lib/data/reminder_pictures.dart`** (plus `_io.dart` and a no-op `_web.dart`, imported the way
  `lib/data/catalog_cache.dart` does): `ReminderPictures`. `addressFor` turns a `/view` into the widget's address and
  keeps a stored `/preview`. It also has `fileOf` (no network), `fetch`, `keepOnly` and `clear`. The folder and fetch
  can be injected for tests, like `FileCatalogCache.directory`.
- **`lib/core/reminders.dart`**: `listen` hands over a `ReminderTap` (route, id, picture) built from the new `open`
  map; a bare route string still works.
- **`lib/app.dart`**: `paused` calls `refresh(fetch: false)`, `reminder_opened` gains `kind` and `picture`, and the day
  refresh (decision 7) goes here. The `refresh()` overrides `_Reminders` (`test/notifications_test.dart`) and
  `_QuietReminders` (`integration_test/design_qa/harness_main.dart`) take the new parameter.
- **Swift**, all in `ios/Runner/AppDelegate.swift`, so `project.pbxproj` does not change. `DailyReminders.schedule`
  reads `picture` and `file` and skips a request whose `sig` is unchanged. It attaches through `ReminderAttachment`,
  and re-adds without the picture when `add` reports an error. It waits on a `DispatchGroup`, so `done` follows every
  `add` (QA reads `pending` right after). It also removes daily reminders delivered on earlier days (decision 5).
- **New `enum ReminderAttachment`**: it checks the size (`URLResourceValues.fileSize`) and the first bytes (JPEG
  `FF D8 FF`, PNG `89 50 4E 47`), and reads the pixel size with ImageIO, as `DailyPicture.pixelSize` does in the widget
  target (copy those ten lines). It copies the file to `tmp/reminder-<UUID>.jpg` or `.png`; with no type hint, iOS goes
  by the extension. It then builds `UNNotificationAttachment(identifier: "picture", url:, options:
  [UNNotificationAttachmentOptionsThumbnailClippingRectKey: rect.dictionaryRepresentation])` and deletes the copy if
  that fails. The rect is a centred square in Apple's unit rectangle: landscape `(x: (1 - h/w) / 2, y: 0, width: h/w,
  height: 1)`, portrait `(x: 0, y: (1 - w/h) / 2, width: 1, height: w/h)`.
- **`describe`** (`pending`, `delivered`) adds `picture`, `pictureType` and `pictureKey`. `picture` is true when the
  request has an attachment. It is unverified that iOS reports attachments on pending requests; if not, use a
  `userInfo` flag set after a successful add.
- **`didReceive` and `ready`**: `open` sends `{route, id, picture}`. `ios/DailyWidget` does not change.

## Apple, privacy and review

- **No new permission**, as expected: Apple's `UNNotificationAttachment` pages name none, and the picture is part of an
  alert the app may already show. No entitlement, capability, extension, Info.plist key or privacy manifest entry. No
  required-reason API: no file dates or disk space are read, and pruning goes by name.
- **App Review**: 2.1.0 is a new version and is reviewed anyway. Add under REMINDERS in
  `store/metadata/en-US/review_notes.txt`: "Daily reminders and New events notes are local notifications. From 2.1.0
  they carry the day's picture or the event's cover as an image attachment, downloaded ahead from our own Appwrite
  storage. No new permission." Guideline 4.5.4 (New events stays opt-in) and the App Privacy answers are unchanged.
- **`docs/privacy-policy.md`**: after "nothing about them is sent to us", add "To show the day's picture or the event's
  cover, the app downloads it ahead of time from our own storage, like any picture in the game." The usage-data row
  names "a notification opened (a gift or a message from Carden)". `reminder_opened` has been sent since 2.0.0, so add
  "a reminder" there.
- **Analytics**: no new event. `reminder_opened` keeps `daily` and gains `kind` (`daily` or `event`, from the id
  prefix `event-`) and `picture` (whether the tapped notification had one). Its row in `docs/analytics.md` changes;
  `lib/core/analytics.dart` does not.

## Accessibility

- VoiceOver reads the unchanged title and body. The body names the picture or the event, so the picture adds nothing
  that must be read (Apple's attachment API has no label to set). With previews hidden it reads "Notification".
- The picture is the plain photo: nothing is drawn into it (unlike the widget's fade), so no text or colour-only state.
- Notifications are system UI: iOS Dynamic Type, Reduce Motion and Increase Contrast apply to them; the game's own
  Settings > Accessibility does not, and need not. No screen in the game changes, so nothing new to check at Largest.

## QA

- **Unit, `test/reminders_test.dart`**: a day with a daily puzzle gets the widget's address. A day without one gets no
  picture, the generic text and Home (the test exists; its comment becomes "a month missing from the copy"). Next
  month's days, from an unreleased `daily-2026-11` pack, are named, routed to `/play/<id>` and get a picture. An
  `imageUrl` on another host, or in `private-packs` or `user-uploads`, gets none. Event pictures fall back from the
  pack cover to the event cover, then to none. The JSON test gains `picture` and `file`.
- **Unit, `test/reminder_pictures_test.dart`** (new): `addressFor` gives the exact string the widget builds; a fixed
  example keeps Dart and Swift in step. Only complete files count, and `.part` files are removed. It also covers the
  first-byte check, the 5 MB limit, `keepOnly` and `clear`.
- **Unit, `test/reminders_controller_test.dart`** (new; mock `cjw/reminders` as `test/notifications_test.dart` does): a
  foreground pass schedules without files, then with `file`, and `refresh(fetch: false)` never downloads. Overlapping
  passes keep their order, with one download per address. With both switches off, it cancels and empties the folder. A
  tap that arrives as a map, or as the old string, gets through.
- **Integration**, on the QA simulator, always through `tools/dev/qa-run.sh drive
  --driver=test_driver/integration_test.dart --target=<suite> -d CDD7317C-19D6-486D-B258-8AB8A607297D`. It sets
  `CJW_MUTE`, `CJW_QA` and a run id, and purges the run's players afterwards.
  - `integration_test/quests_reminders_test.dart`: after `qr_09`, poll `ReminderChannel.pending()` for up to 60 s
    until every `/play/` note has `picture: true` and `pictureType: public.jpeg`. Put a file that starts like a JPEG
    but is not one under tomorrow's name and run `refresh(fetch: false)`: tomorrow stays pending, with
    `picture: false`. After the 2-minute reminder fires, check `delivered.first['picture'] == true`.
  - `integration_test/account_review_test.dart`: the pending `event-` notes have `picture: true`. Event notes are
    planned 5 or more days ahead, so this data check is the only one they get; they share the attachment code.
  - These runs get provisional permission (`ReminderChannel.quietNow`), so reminders arrive quietly in Notification
    Center with no banner. Uninstall the app before a second run on the same day.
- **The look on the simulator**, with full permission (the agent looks at each screenshot): add a `--reminder` mode to
  `tools/dev/notification_check.sh` with a temporary `tools/dev/notification_check/ReminderPictureUITests.swift`. Its
  UI target exists only during the run and is never committed, and the build passes
  `--dart-define=CJW_QA_REMINDER_SOON=true`. The test opens `carden://settings`, turns on Daily reminders, taps Allow on
  iOS's prompt and presses Home. It then waits for the banner (`rp_01_banner`), presses and holds it
  (`rp_02_expanded`), and taps it (`rp_03_daily`, the daily puzzle's board picker). The simulator cannot show the Lock
  Screen (no supported command locks it), Scheduled Summary, Focus, StandBy or Apple Watch. Do not use `RunnerTests`:
  it is hosted by the app (`TEST_HOST`), so it would start a guest outside the QA rules.
- **On the owner's iPhone**, with a TestFlight build the owner asks for:
  1. Settings > Notifications: Daily reminders on, Reminder time 2 minutes from now; leave the game, lock the iPhone.
  2. The Lock Screen shows the reminder with a square of today's picture; press and hold it for the whole picture.
  3. Tap it: today's daily puzzle opens. Set the time again and stay on the Home Screen: the banner shows the square.
  4. iOS Settings > Notifications > Show Previews > Never: "Notification" only, no picture. Set both back afterwards.

## Docs to update

- `docs/notifications.md`: the kinds table's "What" column, "Checking it", and a new "Pictures" section (sources,
  folder, when downloads run, checks, clipping rect, signature, cleanup).
- `docs/analytics.md` (`reminder_opened`), `docs/privacy-policy.md` (the two lines above), and `docs/catalog-sync.md`
  under "Rules" (reminders read daily months before their release, so the copy must keep unreleased rows; it does).
- `CLAUDE.md`: the code map's "Daily reminders" paragraph (`ReminderPictures`, `Library/Caches/reminder-pictures`, the
  event cover).
- `store/metadata/en-US/release_notes.txt` (What's New for 2.1.0): "Daily reminders now show the day's picture, and New
  events notifications show the event's cover." Also `review_notes.txt` (above) and the build's
  `testflight_build_notes.txt`.
- The header comments of `integration_test/quests_reminders_test.dart` and `tools/dev/notification_check.sh`, and this
  file's status line once it ships.

## Open decisions for the owner

1. **Picture address and size.** (a) The widget's address for daily pictures and the stored cover for events: no new
   resized copies, sharp when expanded, expected to be JPEG (QA checks). (b) The same with `&output=jpg`: JPEG for
   certain, but Storage makes a new copy of each picture. (c) The `/view` original (at most 1200 px): a little sharper
   and already cached for the tap, but about twice the bytes (estimate). **Recommendation: (a)**, with (b) only if QA
   finds a file that is not JPEG.
2. **Days in next month.** (a) Take them from the device copy: the named text, the picture, and a tap to that day's
   puzzle (needs decision 7). (b) Do as 2.0.0 does for an unreleased month: no picture, the generic text, Home.
   **Recommendation: (a)**; otherwise every pass in a month's last six days plans some days without a picture.
3. **Thumbnail crop.** (a) A centred square. (b) A square around the part Apple's Vision framework finds most
   important, worked out on the iPhone: more code and more time per pass. (c) No rect, so iOS chooses (how is
   unverified). **Recommendation: (a).**
4. **Event note picture.** (a) The pack's cover, then the event's own. (b) The event's cover only. (c) None.
   **Recommendation: (a)**, because the pack is what the tap opens.
5. **Delivered daily reminders from earlier days.** (a) Remove them when the game plans: they say "Today's" for a day
   that has passed, and their pictures use iOS's attachment space. (b) Leave them, as in 2.0.0.
   **Recommendation: (a).**
6. **Measuring it.** (a) `kind` and `picture` on `reminder_opened`, with no holdout. (b) A holdout as well: one day in
   five without the picture, chosen by the day's key. (c) Nothing new. **Recommendation: (a)**; at our numbers a
   holdout gives some players a worse reminder for a result we could not trust.
7. **The day changes while the game is suspended.** (a) A small local-day provider, set at start and on each resume,
   that `packsProvider`, `publicPacksProvider` and `allPuzzlesProvider` watch, so they rebuild once a day. This fixes
   the tap, and probably Home's daily card after midnight, whose provider keeps the day it was built on (unverified).
   (b) On a reminder tap only, invalidate those providers before opening the route. (c) Nothing (only possible with
   2b). **Recommendation: (a).**

## Effort and risks

| Part | Estimate |
| --- | --- |
| Dart: planning, picture folder, controller, tap, day refresh | 1 day |
| Swift: attachment, clipping rect, fallback, signature, read-back | 0.5 day |
| Unit tests | 0.5 day |
| Integration suites, the UI check and its screenshots | 0.5 to 1 day |
| Docs, review notes, What's New | 0.25 day |
| Total | about 3 days |

- **A bad file makes iOS drop the whole reminder.** Covered by checks in Dart and Swift, a text-only re-add on any
  error, and a broken-file case in the integration suite.
- **Downloads cut short when the game leaves the front** are covered by `.part` files and the next foreground pass.
  **The day changing in the background**: without decision 7, a tap on the 1st of a month can show "Picture not
  available".
- **Unverified: the iOS 26 look and Apple's attachment space limit.** Covered by the UI check, the owner's iPhone,
  small files, removing old reminders and the text fallback. **No compatibility risk**: nothing changes on the server,
  and old builds are unaffected. Data use is about one picture a day.

## Not in this task

- Lock Screen widgets (the accessory families) and a Control Center control.
- Pictures in remote pushes (Gifts from friends, Messages from Carden). They need a Notification Service Extension: a
  new target and App ID with its own profile and network code, and more review attention.
- A notification content extension (a custom expanded view, for example with a Play button).
- `hiddenPreviewsBodyPlaceholder` on a notification category, so hidden previews say "Daily puzzle" instead of
  "Notification".
- A background refresh (BackgroundTasks) for players away longer than the planned week; a Vision crop (if decision 3
  picks the centre); a holdout (if decision 6 picks (a)); web and Android notifications.
