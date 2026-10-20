# Send a photo puzzle

Status: planned for 2.1.0, not started. Picked by the owner on 2026-10-20.

## How to work on this task

- Branch: `2.1.0/photo-puzzle`, which starts with this brief. Work and push only there (`git push -u origin 2.1.0/photo-puzzle`). Never merge it into main or push to main: that is the owner's call. This overrides CLAUDE.md's "push to origin main" for this task.
- Check the branch out in its own worktree (`git worktree add <folder> 2.1.0/photo-puzzle`): another session may be using the main checkout.
- No TestFlight or App Store builds, no web deploys (`tools/dev/deploy-web.sh`), no installs on the owner's iPhone. Pushing the branch starts no CI (`.github/workflows/ci.yml` runs on main and pull requests only).
- Changes to the live backend count as deployments: ask the owner before creating the tables, the bucket, the `reports` column or the topic, and before deploying `api` or `delete-account`. Build and test the function locally (`npm test` in `functions/api`) until then. QA runs use the live backend, so the live checks and simulator suites wait for that go.
- Everything else in CLAUDE.md applies: the gates (`flutter analyze --fatal-infos --fatal-warnings`, `flutter test`), QA only through `tools/dev/qa-run.sh`, commits with the owner's git identity and explicit paths.

## Summary

A player turns one of their My Puzzles photos into a puzzle for someone else: they pick the board, optionally a line from a fixed list, and share a link. Whoever opens it, in the app or in the browser with no account, sees who sent it and plays that photo on that board with the normal rules and rewards. The sender gets an Inbox note (and, on iPhone, a notification) when each person finishes. The photo stays visible only to the people who opened the link, and the sender can stop sharing at any time.

## Why

- **The most personal reason to share Carden.** Play together shares a catalogue picture; this shares a photo of the family, the dog, the trip. Every link reaches someone new: a recipient without the app plays in the browser at once, then gets the app.
- **Timing.** 2.1.0 lands near Christmas, when a photo puzzle is a classic gift. In an Ipsos survey for Ravensburger (2018, US adults who puzzle), 69% see puzzling as a family tradition, 59% puzzle on vacation or over the holiday break and 76% puzzle more in winter ([Ipsos PDF](https://www.ipsos.com/sites/default/files/ct/news/documents/2019-01/ravensburger-2018-puzzle-survey-pr-01-03-2019.pdf)).
- **Competitors lead with it.** Magic Jigsaw Puzzles (4.7 stars from about 50,000 ratings) advertises "Create a puzzle with your own picture and share it with friends or with the Magic Jigsaw Puzzles community" ([AppGoblin](https://appgoblin.info/apps/439873467)).
- **Most of the plumbing exists.** Uploads (`UploadRepository`, bucket `user-uploads`), private files read through the signed-in client (`ImageFiles`, as for `private-packs`), the invite domain and its per-link page (`join.carden.page`, `functions/api/src/invite/page.js`), the fresh-install path of Play together (`DeepLinks.show`, `openInvite`), the Inbox and push of friend gifts (`/gift/send`), Report and Block (`player_safety.dart`).

What weakens it:

- Few players have uploaded their own photos to My Puzzles so far, so own-photo play is not pulling yet. Sending gives a reason to upload; recipients never upload.
- A shared photo is user content. Guideline 1.2 asks for filtering, reporting with timely responses, blocking and contact details, and the owner alone reviews reports, over the holidays too (see "Apple, privacy and review").
- The link preview must never show the photo, so it is a generic card, less inviting than Play together's per-game card.
- The survey is about physical puzzles, US only, 2018, sponsored by a puzzle maker. The competitor's feature includes a public community, which this plan does not build.
- Photos carry metadata today: `image_picker_ios` copies the source's metadata into the resized file (`FLTImagePickerMetaDataUtil imageFromImage:withMetaData:`), so location can stay in an upload when the picker passes it (unverified on a device). A copy must be cleaned before anyone else sees it: new work, not just a permission.

## What the player sees

### Sender

1. Library > My Puzzles > a photo's "..." (or hold it): **Play**, **Send as a puzzle**, then while shared **Share link again** and **Stop sharing** (red), then **Delete photo**. While shared, the action sheet's message reads "Shared · opened by 3 · finished by 1" and the tile carries a "Shared" chip (icon and word).
2. **Send as a puzzle** opens the board picker in send mode (route `/send/<photoId>`): title "Send as a puzzle", line "Choose the board they will play.", the real-aspect preview, mode and size chips with Painting and Expand, limited to what the sender has open (never giant sizes), Cards 4x4 chosen first. A row "Line" (value "None") opens an action sheet "Add a line": "Merry Christmas", "Happy holidays", "Happy New Year", "Happy birthday", "Thinking of you", "Thank you", "Congratulations", "Wish you were here", "No line". Footer: "Up to 10 people can open the link for 30 days." and the button **Send puzzle**.
3. A sheet "Making the link" / "This can take a few seconds." (the `runWithProgress` panel from `join_flow.dart`), then the share sheet with "A photo puzzle for you in Carden" (the line first when chosen: "Merry Christmas. A photo puzzle for you in Carden") and `https://join.carden.page/photo/<code>`. Web: the browser's share sheet, else the link is copied ("Link copied").
4. Shared: toast "Link shared". Dismissed: no toast; **Share link again** gives the same link from any of the sender's devices.
5. Refusals: daily limit "That's all your puzzles for today. More tomorrow."; unreadable photo "This photo cannot be sent. Try another one."; offline "No connection. Try again when you are back online."; a sender the owner stopped "Sending photos is off for your account. Contact us from Settings > Help."
6. Someone finishes: Inbox row "Rowan finished your puzzle", message "Rowan solved the photo you sent, on a Cards 4x4 board." with the button **Add Rowan as a friend** when Rowan is not in the sender's friends. iPhone notification (Settings > Notifications > Photo puzzles): "Rowan finished your puzzle" / "The photo you sent is solved."; its tap opens the message.
7. **Stop sharing** asks "Stop sharing this photo?" / "The people who have it can no longer open it. You keep the photo." / **Stop sharing** (red) / **Keep sharing**; then "Stopped sharing". **Delete photo** on a shared photo says "The photo and its puzzle are removed from your account and from the people you sent it to."
8. The completion card of the sender's own My Puzzles board gains a secondary **Send as a puzzle**. A sender who opens their own link gets "This is your own photo" and its board picker.

### Recipient

1. Messages shows the preview: a fixed card (never the photo), "Mia sent you a photo puzzle" ("A photo puzzle for you" when the name is refused), "Merry Christmas · Play it in Carden, on iPhone or in the browser".
2. App 2.1.0 or later: the link opens the app (universal link); "Opening the puzzle" / "This can take a few seconds."; then the intro sheet: Mia's avatar, "A photo puzzle from Mia", the line, "Cards 4x4 · 16 cards", "Mia sees when you finish.", **Play** and **Not now** (it waits in My Puzzles > From others).
3. The board: the photo shows whole, then the cards glide to their places (the usual deal preview; Reduce motion cross-fades). The top bar reads "From Mia". Shuffle, Peek, Hint and Magic as on any board; the pause sheet adds **Report photo**.
4. The finish: the usual completion card and rewards, plus "Mia will see that you finished." and, once Social is open and Mia is not a friend, **Add Mia as a friend** (the `/add-friend?code=` flow).
5. Later: My Puzzles has two segments (`AppSegmentedControl`), **Your photos** and **From others**. A tile shows the photo, "From Mia" and its stars once finished. Tap: a board in progress resumes; the first open plays Mia's board; after a finish the board picker opens with Mia's board chosen. Hold or "...": **Play**, **Report photo**, **Block Mia** (red, asks), **Remove** (red, asks "Remove this puzzle?" / "It leaves My Puzzles on every device. Mia is not told."). Empty: "No puzzles from others yet" / "Photo puzzles sent to you land here. Open a link someone sent you to add one."

| Situation | What happens |
| --- | --- |
| Fresh install (installed, never opened) | The same as above, the board before any welcome page. The welcome pages and guided start begin when the player leaves (Not now, or after the finish), as for a Play together invite. |
| No app, iPhone | The page at `join.carden.page/photo/<code>`: the card, "Mia sent you a photo puzzle", the line, the board, "Open it in the Carden app, or play it here in the browser.", **Open in Carden** (`carden://photo/<code>`), **Play in the browser**. After 2.5 s without the app: "If Carden did not open, play right here in the browser, or get the app and open the link again." and **Get Carden**. |
| Web, Android, computers | The page leads with **Play in the browser** (`https://play.carden.page/photo/<code>?play=1`): the web game makes a guest, then the same intro sheet and board. No push on the web; the Inbox note still reaches the sender. |
| Old build (2.0.x) | Builds 127 and later claim `join.carden.page`, so the link opens the app, which does not know the path and shows Home (read from code: `didPushRouteInformation` returns false, the router's `onException` goes to `/home`; check on a 2.0.0 install). "Update available" shows once 2.1.0 is in `releases`. Earlier builds see the page; Open in Carden lands on Home. |
| Expired, stopped, photo deleted, unknown, or blocked either way | Page (it cannot know who reads it, so blocks do not change it): "This puzzle is no longer available" / "Ask for a new link, or play a picture of your own." App, block included: "Puzzle not available" / "This link cannot be opened. Ask for a new one." / **Close**. Never says which. |
| Full (10 people) | "This link is full" / "10 people have opened it, the most one link allows. Ask for a new one." Someone who opened it before still gets in. |
| Offline | "No connection. Open the link again when you are back online." An opened puzzle plays from the cached photo; the finish note goes once online. |
| Stopped or deleted after opening | The tile leaves when the list next loads (launch, resume, pull down) and the cached copy is dropped. An open board can be finished; nobody is told. |
| Sensitive Content Warning or Communication Safety on (iPhone) | The intro sheet shows the photo blurred: "This photo may be sensitive." and **Show photo** (adults, one tap). Communication Safety (children): full-screen, plain words, a second "Are you sure?" step. **Block Mia** and **Remove** are offered. Nothing about the check leaves the device. |

## Rules and edge cases

- One link per send: 12 characters of the join-code alphabet (`ABCDEFGHJKMNPQRSTUVWXYZ23456789`, about 59 bits, so guessing is pointless). Up to 10 people, new people for 30 days; the puzzle then stays with those who opened it until the sender stops sharing, deletes the photo or the account, or they remove it.
- Limits: 20 links a day per sender (rolling 24 hours), 30 links opened a day per player, 5 finish notifications a day per sender (later notes arrive in the Inbox quietly, as `shouldPush` does for gifts).
- Anyone can send: guests and accounts, iPhone and web, except players the owner labelled `nophotos`. Sending never uses a photo slot (`Economy.freeMyPuzzles` counts `my_puzzles` rows only), and received puzzles do not count against it.
- Only the sender's own `my_puzzles` photos. Their title is never copied (a modified client can write any text into its own row); the recipient's title is "From <name>".
- Lines are keys from a fixed list, the same in the app (`PhotoLine`) and the function (`LINES`), checked equal by a test as gift `KINDS` are. An unknown key (a later build's) shows nothing. No free text anywhere.
- The board is the sender's choice of what they have open; giant sizes never (`isGiantPuzzleProvider` is false for player photos). The recipient plays it whatever their level, as a Play together guest does; replays follow the recipient's own unlocks.
- Rewards: as for a My Puzzles board of their own (`recordCompletion`: full coins, XP, piggy bank and level on the first finish, the replay share after). Quests and achievements count it as they count My Puzzles boards; Total Completion does not (`CompletionTotals` counts released packs only); the guided start counts it as a finished picture (`countedFinishes`). The sender earns nothing for a finish, so second accounts cannot farm it.
- The same link opened again opens the same puzzle and takes no new place; one account on several devices holds one place. A web guest and an app guest are two players and take two places.
- Names go through the name filter everywhere (page, push, Inbox, tiles): `shownName` on the server, `NameFilter.shown` in the app.
- Block (either way, existing `blocks` rows): no new opens, no finish notes, and existing puzzles between the two leave the blocker's list at once (app) and lose their access (server, on the `blocks` create event).
- Report: the photo leaves the reporter at once; the others who opened it keep it until the owner decides. The copy is held for the owner: if the sender stops sharing or deletes the photo meanwhile, it loses every reader but stays until the owner closes the report. The owner can remove it for everyone and stop the sender from sending.
- Stop sharing, deleting the photo or deleting the account removes access for everyone. Devices also drop their cached copy (`ImageFiles` keeps private files 30 days under their URL). Screenshots cannot be prevented; the copy never promises more than access.
- A guest who signs in to an existing account: received puzzles stay with the guest, as My Puzzles photos do today (`SaveMerge.mergeInto` moves the profile and progress only; read from `lib/state/merge_flow.dart`). Opening the link again on the account works while places last.
- The edge keeps a page 10 minutes (`s-maxage=600`), so a stopped link may still preview for that long; opening it is refused.
- Sending retries safely: the app makes the share id (`ID.unique()`) and sends it, so a retry after a lost answer gets the same link. Claims are idempotent by claim id, finishes by `finishedAt`.

## Data and backend

Everything is additive: new tables, a new bucket, a new topic, one optional column. No row, column or path a live build reads changes.

| Piece | Details |
| --- | --- |
| `photo_shares` (row security on, no table permissions; each row `read("user:<sender>")`; only `api` writes) | row id = share id (made by the app); `code` varchar 16, unique index `idx_code` (stored plain, as `coop_games.code`, not hashed like `pack_codes`: Share link again needs it on every device of the sender, and only the sender and the server read the row); `senderId` (idx), `myPuzzleId` (idx), `sourceFileId`, `fileId` (the copy) varchar 36; `grid` varchar 32 (path form); `painting` bool false; `line` varchar 32 ''; `maxClaims` int 10; `claims` int 0; `finished` int 0; `expiresAt` datetime; `status` varchar 16 `open` (or `stopped`); `held` bool false (a report is open); `isTest` bool false |
| `photo_claims` (row security on, no table permissions; each row `read("user:<recipient>")`; only `api` writes) | row id = first 32 hex of sha256(`<shareId>:<recipientId>`), as `claimId` in `code.js`; `shareId`, `senderId`, `recipientId` (each indexed), `fileId`; `grid`, `painting`, `line` (copied); `senderName` (through the name filter), `senderAvatar` varchar 64; `finishedAt` datetime (optional); `isTest` |
| Bucket `shared-photos` | File security on, no bucket permissions, JPEG only, at most 5 MB. Each copy is readable only by its claimants (`read("user:<id>")`), never `any` or `users`; only `api` writes. Antivirus if the plan offers it (unverified on Cloud). |
| `reports.shareId` | varchar 36, optional, default ''. Builds in use never write it. |
| Inbox notes | Existing `messages` columns: `userId` = sender, `fromUserId`/`fromName`/`fromAvatar` = the recipient, `ctaLabel`/`ctaLink` (`/add-friend?code=<id>`), `expiresAt` 30 days, row `read("user:<sender>")`. Every build with the Inbox shows such a row (no reward: `_GiftCard` stays hidden). |
| Messaging topic `photos-off` | Like `gifts-off`: a target whose player turned Photo puzzles off. Builds before 2.1.0 never join it and get every finish push. |
| User label `nophotos` | Set by `tools/dev/reports.py --ban`; `/photo/send` refuses such a sender. |

The copy: `/photo/send` reads the original (`getFileDownload` on `user-uploads`), decodes it with the code the invite cards use (`decode` in `src/invite/raster.js`: PNG via zlib, JPEG via jpeg-js), applies the EXIF orientation itself (jpeg-js exposes `exifBuffer` but does not rotate), scales to at most 1600 px and encodes with `encodeJpeg` (`src/invite/jpeg.js`) in a worker thread like `invite/worker.js`. The result carries no metadata at all (no location, camera or time) and no bytes of the original file. Other formats answer `photo`. Coverage of every PNG kind by `decodePng` is unverified.

### Routes on `api` (`functions/api/src/photo/`: `rules.js` without a database, `share.js`, `copy.js`, `worker.js`, `page.js`)

| Route | Body | Does | Answers |
| --- | --- | --- | --- |
| `POST /photo/send` | `shareId, myPuzzleId, grid, painting, line` | the photo is the caller's (`my_puzzles.userId`), the board (`validGrid` in `coop/rules.js`, 9-200 cards), the line key, no `nophotos` label, under 20 links in 24 h; makes the copy with no permissions, then the share row; a share id already used by this caller answers that share | `{ok, shareId, code, url, expiresAt, maxClaims}` or `{ok:false, error: photo, board, line, limit, unavailable, signin, server}` |
| `POST /photo/claim` | `code` | finds the share; refuses `stopped`, `expired` (no claim yet), `own`, `unavailable` (a block either way), `limit`; creates the claim, recounts (the claims count settles a race for the last place, as `/code/redeem` does: `full`), adds `read("user:<caller>")` to the copy, updates `claims` | `{ok, repeat, puzzle: {shareId, fileId, grid, painting, line, senderId, senderName, senderAvatar, sentAt}}` or `{ok:false, error: invalid, unavailable, full, own, limit, signin, server}` |
| `POST /photo/finish` | `shareId` | the caller's claim, first finish only: `finishedAt`, `finished + 1`; when the share is open and nobody blocked the other, the Inbox note and a push (without `photos-off` targets, at most 5 a day per sender; `cleanupPushLog` already removes `/inbox?message=` pushes after a day) | `{ok, notified, pushed}` or `{ok, already: true}` |
| `POST /photo/stop` | `shareId` or `myPuzzleId` | the caller's shares: `stopped`, claims deleted, copy deleted (permissions emptied instead while `held`) | `{ok, stopped}` |
| `POST /photo/remove` | `shareId` | the caller's claim deleted, their read removed | `{ok}` |
| `POST /photo/report` | `shareId, reason` | the caller's claim: a `reports` row (`reporterId`, `reportedId` = sender, `reportedName`, `reason` `photo`/`other`, `shareId`), share `held`, the caller's read and claim removed; optionally an Inbox note and push to the owner's player (function variable, decision 11) | `{ok}` |
| `GET /photo/<code>` on `join.carden.page` | | the page (below) | HTML |

Every player route answers 401 without `x-appwrite-user-id` (checked in `router.test.mjs`, as for the others). No new scopes: `api` already has rows, files, users, messages, subscribers and targets.

**Link, page and association file.** The shared link is `https://join.carden.page/photo/<code>` (decision 1). `main.js` routes a GET on that path to `photo/page.js` before `isInviteRequest` (which today sends any GET on the domain to the invite page, whose `codeOfPath` does not match it and redirects to the site). The page reads two rows (the share by `code`, the sender's `displayName`) and shows only: the sender's filtered name, the line, the board in words, a fixed card `https://play.carden.page/photo-card.jpg` (1200 x 630, drawn once by `tools/brand/invite_card.py`, no photo), the buttons and script of `invite/page.js`, `noindex`, `s-maxage=600`. Never a file id, a share id or a Storage URL (a test reads the HTML for them). `ASSOCIATION` in `invite/page.js` gains `{ '/': '/photo/*' }`. `web/.well-known/apple-app-site-association` gains `/photo/*` with `exclude: true`, so Play in the browser stays in the browser and builds from 2.0.0 never open on Home from it.

**Integrity sweep** (`src/sweep/run.js`, rules in `rules.js`, hourly over the last two hours, full at 04:00 UTC). The `user-uploads` rules stay as they are: originals keep `read(user) delete(user)` of the owner, and the copies are in another bucket, so `fileVerdict` never "repairs" a grant. New section 6:

| What | Rule | Action |
| --- | --- | --- |
| `photo_shares` open | its `my_puzzles` row or original file is gone, or the sender is gone | stop (claims deleted, copy deleted unless `held`) |
| `photo_claims` | share gone or stopped, or the recipient gone | delete |
| `shared-photos` files | no share row an hour after creation, or share stopped and not held | delete |
| `shared-photos` files | share stopped but held: any reader; share open: readers other than its claimants | permissions emptied (held) or set to exactly the claimants (open) |
| names | `photo_claims.senderName` refused by the name filter | `Player` |

The `blocks` create event already reaches `api` (`event()` in `main.js`); once `sweepNewRow` finds the row is its owner's, `photo/share.js` removes claims and reads between the two players both ways.

**Account deletion.** `src/account.js` and its twin `functions/delete-account/src/main.js` (kept equal by `twins.test.mjs`; redeploy both): the player's shares go with their copies and claims (a `deletePhotoShares` like `deleteCoop`); `PAIR_TABLES` gains `photo_claims: ['senderId', 'recipientId']`; the finish notes go already (`messages` by `userId` and `fromUserId`); photo reports go with `reports` both ways.

**QA purge and tools.** `tools/dev/cjw_admin.py`: `PLAYER_TABLES` += `photo_shares`, `photo_claims`; `PAIR_TABLES['photo_claims'] = ('senderId', 'recipientId')`; `HOST_TABLES['photo_shares'] = 'senderId'`; a `SHARED_BUCKET`. `tools/dev/purge_test_players.py` backs up and deletes a player's copies with their shares (as it does photos). `isTest` is set from the caller's profile, as gifts do. `tools/dev/reports.py`: shows `shareId`; `--photo ROWID` saves the held copy to `secrets/reports/` (git-ignored) to look at; `--remove ROWID` stops the share for everyone; `--ban USERID` adds the label `nophotos`; `--close` releases the hold.

**Order (server before build).** 1. Tables, column, bucket, topic (additive). 2. `api` and `delete-account` deployed, then `node tools/dev/api_check.mjs` and `security_check.mjs`. 3. Site deploy with `photo-card.jpg` and the association change (it may be step 4's web deploy; until the card is there the page uses the site's `invite-card.jpg`). 4. The 2.1.0 build, with the web deploy from the same commit. After step 2, builds 127 to 2.0.x open photo links on Home, but no real link exists before 2.1.0.

## App changes

| File | Change |
| --- | --- |
| `lib/core/app_links.dart` | `case 'photo' when rest.length == 1` and a valid code: action `/photo/<CODE>`; `normalisePhotoCode`, `AppLink.photoUrl(code)`. |
| `lib/features/links/deep_links.dart` | `/photo/` handled like `/join/`: onboarding is not set, `_onPage` only when onboarded, then `openPhotoPuzzle`. `linkTarget` already gives `photo` (no code). |
| `lib/router.dart` | `initialLocation` treats `/photo/` like `/join/` (a new web visitor starts on the welcome pages beneath the puzzle); the redirect skips boards with `?photo=1`, as `CoopRoutes.isCoop` does (else the board route would set onboarded); route `/send/:puzzleId`. |
| `lib/core/appwrite.dart`, `lib/core/image_files.dart` | `photoShares`, `photoClaims`, `sharedPhotosBucket`; the bucket joins `_privateBuckets`; `ImageFiles.forget(url)` drops the disk cache and the web `RecentPictures` entry. |
| `lib/data/photo_puzzles.dart` (new) | `PhotoPuzzleRepository`: the six calls (`createExecution` on `api`, as `coop_repository.dart`), received claims through `listRowsPage`, open shares through `listAllRows` (no fixed `Query.limit`, `test/pagination_test.dart`). |
| `lib/state/photo_puzzles.dart` (new) | `PhotoShare`, `ReceivedPuzzle` (`toPuzzle()`), `PhotoLine`, refusals; `receivedPuzzlesProvider` (`PagedNotifier`), `sentSharesProvider`; filters blocked senders; forgets copies of claims that vanished; on start and resume sends `/photo/finish` for claims whose progress row is completed but `finishedAt` is empty (no queue in preferences). |
| `lib/features/photo/` (new) | `send_flow.dart` (`sendPhotoPuzzle`, `sharePhotoLink`: progress, share_plus as in `share_invite.dart`, copy fallback, toasts), `open_flow.dart` (`openPhotoPuzzle`: waits for the guest, progress, refusal alerts, intro sheet, board `/game/<shareId>/<grid>?photo=1`), `intro_sheet.dart` (with the blurred state), `received_grid.dart`, `photo_alerts.dart`. |
| `lib/models/models.dart` | `Puzzle.received(...)` with pack id `from-others`; `Puzzle.isPlayerPhoto` (`my-puzzles` or `from-others`); `ReportReason.photo`. |
| `lib/state/social.dart` | `resolvedPuzzleProvider` also resolves received ids; `PlayerSafety.reportPhoto`; `block()` also refreshes received puzzles. |
| `lib/features/coop/join_flow.dart`, `lib/state/giant.dart` | `canPlayTogether` and `isGiantPuzzleProvider` use `isPlayerPhoto`. |
| `lib/features/profile/my_puzzles_screen.dart` | Segments, the new actions and "Shared" chip, header line "Only you and the people you send a photo to can see it. Tap to play, hold for more.", empty states, the shared-photo delete copy, `/photo/stop` before `UploadRepository.delete`. |
| `lib/features/gallery/library_screen.dart` | `_MyPuzzlesTile` line "Your photos and ones sent to you" (one line). |
| `lib/features/game/difficulty_screen.dart` | A `send` mode: title and line, Line row, **Send puzzle**; no rewards line, in-progress card or Discard. |
| `lib/features/game/game_screen.dart` | Received boards: title "From <name>", **Report photo** in `_PauseSheet`, `/photo/finish` after `recordCompletion`, the completion line and Add as a friend; **Send as a puzzle** on own photo boards; `_boardProps` pack `from-others`. |
| `lib/features/social/player_safety.dart` | A photo variant of the report sheet ("Report this photo", reasons "Inappropriate photo" and "Something else", "Also block Mia"); the block alert adds "Their photo puzzles go too." |
| `lib/features/notifications/notification_prompt.dart`, `lib/state/push.dart`, `lib/features/profile/settings_screen.dart` | `NotificationKind.photos` ("Photo puzzles", "When someone finishes a puzzle you sent"), on by default; `PushTopics.photosOff`, `wanted(gifts:, messages:, photos:)`, subscriber prefix `p`, the target kept while any push kind is on; `pushKindOf` gives `photo` for `from=photo`. |
| `lib/core/sensitive_content.dart` (new), `ios/Runner/AppDelegate.swift`, `ios/Runner/Runner.entitlements` | Channel `cjw/sensitive` (`policy`, `isSensitive`) over `SCSensitivityAnalyzer` behind `#available(iOS 17, *)` (the app targets iOS 15); entitlement `com.apple.developer.sensitivecontentanalysis.client` = [`analysis`]; off on the web. |
| `lib/core/analytics.dart`, `lib/app.dart`, `lib/state/account_deletion.dart` | Screen `send_photo`; events (below); finishes flushed on resume; providers dropped on deletion. |
| `web/index.html`, `web/.well-known/apple-app-site-association`, `web/photo-card.jpg` | The iPhone card also for `/photo/<code>` without `?play=1`; the exclude; the fixed card. |

## Apple, privacy and review

**Guideline 1.2** ("A method for filtering objectionable material from being posted", report with "timely responses", block, "Published contact information"):

| Requirement | This plan |
| --- | --- |
| Filtering | No posting: no feed, no search, no strangers; links reach only people the sender chose, at most 10 each, 20 links a day; the owner can stop a sender (`nophotos`). SensitiveContentAnalysis blurs for recipients who turned it on and checks a child sender's photo before sending. Whether App Review accepts this for private sharing is unverified (decision 3). |
| Report and timely response | Report photo in the board's pause sheet and on the tile (Block and Remove also on a blurred intro sheet); gone for the reporter at once; the copy is held for the owner (`reports.py --photo`); the owner reviews within 24 hours and can remove the photo for everyone. |
| Block | Existing Block; also removes that sender's puzzles both ways and refuses new ones. |
| Contact | Settings > Help > Contact support, as today. |

**SensitiveContentAnalysis** (Apple's docs, read 2026-10-20). Can: check an image on the device (iOS 17+, macOS 14, visionOS 2) for nudity, and from iOS 27 name the kind (`detectedTypes`: `sexuallyExplicit`, `goreOrViolence`); per the enum cases' own pages, `.simpleInterventions` means Sensitive Content Warning (adults: a brief inline blur, sending unchecked is allowed) and `.descriptiveInterventions` means Communication Safety (children: full screen, plain words, check before sending too); the `analysisPolicy` page lists the two the other way round, so test both. Cannot: detect anything while `analysisPolicy` is `.disabled` (no setting on, the per-app switch off, or no entitlement), which is most players; work on the web or Android; serve moderation: "don't transmit any information off the person's device about whether the Sensitive Content Analysis framework identified an image or video as containing sensitive content" (no analytics, no auto-report, no server flag). Needs the entitlement in the signature (a capability on the App ID, so the App Store profile "CJW AppStore cardjigsawworld" is remade, apple-release skill), the license agreement's section for it, and Apple's test profile and QR image to test (simulator support unverified).

**Universal links.** No new domain or entitlement for the link (`applinks:join.carden.page` since build 127); only the association files change (above). Apple's CDN caches them up to a day: deploy before the build. No new permission prompt either: photos still come from the system picker (`image_picker`), and SensitiveContentAnalysis asks nothing.

**Review notes** (`store/metadata/en-US/review_notes.txt`): PLAY TOGETHER's "My Puzzles photos cannot be shared." becomes "My Puzzles photos cannot be played together."; new section: "PHOTO PUZZLES: A player's own photos in My Puzzles can be sent as a puzzle by link (join.carden.page/photo/...), to at most 10 people within 30 days. The only text is a line picked from a fixed list and the sender's display name. The recipient sees who sent it first; every received puzzle has Report (sent to us, gone for the reporter at once) and Block (all of that sender's puzzles go, no new ones). We review photo reports within 24 hours and can remove a photo for everyone and stop a player from sending. Photos are re-encoded without location or camera data. With Sensitive Content Warning or Communication Safety on, received photos are checked on the device and blurred." To test: two devices, or the iPhone plus Safari on a Mac.

**Privacy policy** (`docs/privacy-policy.md`): the photos row ("never shown to other players") becomes: private unless sent as a puzzle, when a copy without location or camera details is shown to the people who open the link until sharing stops; a new row for photo puzzles (who sent which copy to whom, board, line, opened and finished, the finish note with the finisher's name and avatar); "What other players can see" gains both sides; reports cover photos and keep a reported copy until closed; account deletion lists photo puzzles sent and received; notifications gain the fifth kind; usage data lists the new events; Security mentions per-recipient file permissions; Children keeps the catalogue claim and adds that player photos can be reported and blocked. `docs/terms-of-use.md` gets "Photo puzzles": your own photos or ones you may share, nothing sexual, violent, hateful or private to someone else, and what we may do. **App Privacy answers**: no new type expected (Photos or Videos already App Functionality; lines and report reasons come from lists); the owner re-checks in App Store Connect. **Age rating**: Apple's "User-generated content" capability ("the broad distribution of content created by users") may become yes (links to at most 10 chosen people are arguably not broad); it sits under 4+ in Apple's table either way; Social media stays no (no feed); Messaging and chat stays no (no player-written text, as for gifts).

**Analytics** (`lib/core/analytics.dart`, `docs/analytics.md`): `photo_puzzle_sent` (`mode`, `board`, `cards`, `painting`, `expand`, `line` key or `none`), `photo_puzzle_shared` (`via` sheet/copy, `again`), `photo_puzzle_opened` (`freshInstall`, `platform`, `repeat`, `cards`), `photo_puzzle_refused` (`reason`), `photo_puzzle_stopped` (`links`), `photo_puzzle_removed`, `photo_puzzle_reported` (`block`); `push_opened` kind `photo`; `notification_prompt_allowed` gains `photos`; `push_permission` `from` gains `settings_photos`; board events carry pack `from-others`. Never a code, share, file or player id, and never a SensitiveContentAnalysis result.

## Accessibility

- **Reduce motion**: the deal preview cross-fades as today; the sheets are `showAppSheet`; the blurred photo switches to clear at once (no animated unblur).
- **Increase contrast**: tiles use `Brand.scrim(contrast:)` and `context.colors` like My Puzzles tiles; the "Shared" chip is the dark glass of the tile's "..." button with white text; the page keeps its light and dark tokens.
- **Differentiate without colour**: "Shared" is an icon and a word; finished tiles show `Stars`; the segments are words.
- **Text size up to Largest**: the send mode and the intro sheet (a `SheetScrollBody`, buttons in its footer) without layout errors on the SE frame (design QA harness); tile titles one line with an ellipsis; the notification sheet with five rows.
- **VoiceOver**: tiles read "Photo puzzle from Mia, Merry Christmas, finished, 3 stars"; custom actions Report photo, Block Mia, Remove (own photos: Send as a puzzle, Stop sharing); the blurred state reads "Photo hidden. It may be sensitive." with a Show photo button; the progress panel is a live region (`CoopProgressPanel`).

## QA

- **Flutter unit** (`flutter test`): `test/photo_puzzles_test.dart` (lines equal the function's `LINES`, codes, refusal copy, blocked senders filtered, vanished claims forgotten, finish flush); `test/deep_links_test.dart` (`/photo/<code>` in every form; `ASSOCIATION` opens it; the web file excludes it; a fresh install opens the board without onboarding); `test/private_uploads_test.dart` (uploads still owner-only; the app never writes to `shared-photos`; `ImageFiles` treats it as private); `test/notifications_test.dart` and `test/friend_gifts_test.dart` (fifth kind, topics); `test/analytics_test.dart` (no ids); widget tests of the send mode and intro sheet at Largest on the SE frame, both themes and Increase contrast; a first-steps test (a photo board before the welcome pages counts once).
- **Function** (`cd functions/api && npm test`): `test/photo.test.mjs` (codes, limits, expiry, full race, own, blocked; the copy drops a fixture JPEG's GPS and applies orientation 6; the page has no file id, URL or photo and filters the name; `ASSOCIATION`); `sweep.test.mjs` (section 6); `router.test.mjs` (401s); `twins.test.mjs`.
- **Live** (QA players): `node tools/dev/api_check.mjs` (every photo route and the page as Messages, WhatsApp and Safari read it); `node tools/dev/security_check.mjs` (a copy unreadable without a claim, after stop, after a block; a wrong code; the sweep repairing an extra reader).
- **Simulators** (always `tools/dev/qa-run.sh drive --driver=test_driver/integration_test.dart --target=...`): `photo_receive_test.dart` (a fresh install gets the link as iOS hands a universal link, like `invite_link_test.dart`; the sender is a new `tools/dev/photo_qa.py`, modelled on `gift_qa.py`, which uploads a catalogue picture's bytes as the integration suites do and calls the real routes; finish, then the sender's note; refusals); `photo_send_test.dart` (send mode, share text through the share recorder as `coop_host_test.dart` does, Share link again, Stop sharing, delete); `photo_pair_test.dart` on two simulators (`CJW_PHOTO_ROLE=sender|recipient`, link handed over through `coop_bot.mjs`'s `/relay`; start the second run after the first build). Web: `tools/dev/qa-run.sh run -d web-server --web-port 8137` and a headless browser on `/photo/<code>?play=1`. The finish push: a variant of `tools/dev/notification_check.sh`. SensitiveContentAnalysis: Apple's test profile and QR image on a device (owner's call).
- **Screenshots to look at**: the photo menu; send mode (light, dark, Largest on SE) with a line; the share text; the page in the simulator's Safari (and its source: no photo); Opening the puzzle; the intro sheet; the deal preview and the board with "From Mia"; the pause sheet; the completion card; From others (finished, unfinished, empty); the sender's Inbox note and the push banner; each refusal; Report (tile gone), Block (all gone), Stop sharing (gone after resume, photo not loadable); the fresh install's welcome pages after the board; the web board; the blurred state.

## Docs to update

New `docs/photo-puzzles.md` (the feature, like `docs/multiplayer.md`) and its line in CLAUDE.md (code map, tables, bucket, and the private-photos rule: originals stay owner-only; copies live in `shared-photos`, readable by the people who opened the link, written only by `api`). Also `docs/deep-links.md`, `docs/functions.md`, `docs/notifications.md`, `docs/friend-gifts.md` (shared push plumbing), `docs/multiplayer.md`, `docs/analytics.md`, `docs/privacy-policy.md`, `docs/terms-of-use.md`, `docs/web.md`, `docs/first-steps.md`, `docs/economy.md` (rewards and limits), `docs/release-checklist.md` (the photo page uses `GET_CARDEN`; the new capability), `store/metadata/en-US/review_notes.txt`, `.claude/skills/apple-release/SKILL.md` (SensitiveContentAnalysis and the profile), and the docstrings of `tools/dev/reports.py`, `cjw_admin.py` and `purge_test_players.py`.

## Open decisions for the owner

1. **Link address**: (a) `join.carden.page/photo/<code>`: no new domain or entitlement, old builds from 127 open on Home; (b) a new domain such as `photo.carden.page/<code>`: old builds see the page and can play in the browser, but it needs a proxy rule and `applinks:` in 2.1.0. Recommend (a).
2. **People and time per link**: (a) 10 people, 30 days; (b) 1 person, 7 days; (c) no limits. Recommend (a): a family group chat, still not a public post.
3. **Filtering for Guideline 1.2**: (A) the limits, report and block, owner review within 24 hours, SensitiveContentAnalysis for those who turned it on; (B) A plus a bundled on-device nudity classifier on every sender's device (app size, licence, false positives); (C) the owner approves every photo before its link works (slow, misses Christmas). Recommend A, with B ready if App Review asks.
4. **SensitiveContentAnalysis in 2.1.0**: (a) yes; (b) later. Recommend (a), shipped early in the cycle: the new capability can hold the build for a real review.
5. **Notification setting**: (a) a new "Photo puzzles" switch, on by default; (b) under Gifts from friends. Recommend (a): a player who mutes gifts may still want to know their family finished.
6. **Lines**: (a) the eight above; (b) none. Recommend (a), wording yours.
7. **Who can send**: (a) everyone, 20 links a day; (b) VIP only; (c) 3 a day free, 20 with VIP. Recommend (a): each link reaches someone new.
8. **Board choice**: (a) the sender picks, Cards 4x4 first; (b) the recipient picks. Recommend (a): the board is part of the gift.
9. **Rewards**: (a) the recipient earns as on a My Puzzles board, the sender nothing; (b) nobody earns. Recommend (a).
10. **Where received puzzles live**: (a) My Puzzles > From others; (b) also a Home card while new. Recommend (a) now, (b) later.
11. **Owner alert for photo reports**: (a) an Inbox note and push to the owner's own player (its id only in a function variable); (b) `reports.py` only. Recommend (a): it makes the 24-hour promise realistic.

## Effort and risks

| Part | Estimate |
| --- | --- |
| Backend: tables, bucket, routes, copy, page, sweep, deletion twins, tools, function tests | 3 to 4 days |
| App: links, open flow, intro sheet, send mode, My Puzzles, game screen, report and block, notifications, SensitiveContentAnalysis channel | 5 to 7 days |
| QA: suites (pair and web), push check, screenshots | 2 to 3 days |
| Docs, policy, terms, review notes, store answers | 1 day |

| Risk | Mitigation |
| --- | --- |
| App Review finds the filtering too weak (1.2) | Clear review notes; option B prepared; report and removal shown working |
| A new capability holds the build; Apple slows before Christmas (unverified for 2026) | First 2.1.0 build early; aim for approval by early December |
| Old builds open links on Home | "Update available"; most recipients are new people on 2.1.0 |
| Owner's report load over the holidays | Owner alert (decision 11), held copies, `nophotos` |
| A link posted publicly | 10 places, 30 days, Stop sharing |
| Orientation or metadata bugs in the copy | Fixture tests (GPS, orientation 1-8), visual QA on a portrait camera photo |
| Storage and bandwidth | Copies up to about 1 MB, deleted with their share; tiles use previews |
| The generic preview draws fewer taps | The sender's name and line in the preview; measured by `photo_puzzle_opened` |

## Not in this task

- Play together on a received photo: `/coop/create` refuses private pictures today; later it could take a share and grant `read("team:<game>")` on the copy, with the generic card as the invite's preview.
- A Home card or Library dot for a new received puzzle.
- Moving My Puzzles photos and received puzzles on a guest-to-account merge (an existing gap).
- A bundled classifier for every sender (decision 3, B).
- Sending a catalogue picture as a puzzle; free text, voice or reactions (never: no player-written text).
- A list of who opened each link; web push; Android.
- Picking up the link after an App Store install (it would need the clipboard or an attribution SDK: neither fits the owner rules); the page says to open the link again.
- Christmas promotion: a store slide, an In-App Event, an Inbox message to everyone (store-screenshots and inbox-messages skills).
