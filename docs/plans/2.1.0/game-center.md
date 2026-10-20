# Join Apple's Games app (Game Center)

Status: planned for 2.1.0, not started. Picked by the owner on 2026-10-20.

## How to work on this task

- Branch: `2.1.0/game-center`, which starts with this brief. Work and push only there
  (`git push -u origin 2.1.0/game-center`). Never merge it into main or push to main: that is the owner's call. This
  overrides CLAUDE.md's "push to origin main" for this task.
- Check the branch out in its own worktree (`git worktree add <folder> 2.1.0/game-center`): another session may be using
  the main checkout.
- No TestFlight or App Store builds, no web deploys (`tools/dev/deploy-web.sh`, which also carries the association file
  change below), no installs on the owner's iPhone. Pushing the branch starts no CI (`.github/workflows/ci.yml` runs on
  main and pull requests only). The device and TestFlight checks in QA wait for a build the owner asks for.
- Changes on Apple's side and on the live backend count as deployments: ask the owner before adding the Game Center
  capability to the App ID (it invalidates the current App Store profile until it is recreated), before creating any
  Game Center component in App Store Connect (ids and points are permanent once live), and before any `api` change
  (decision 5). Until then, work against the fake native side and `asc_publish.py gamecenter --dry-run`.
- Everything else in CLAUDE.md applies: the gates (`flutter analyze --fatal-infos --fatal-warnings`, `flutter test`), QA
  only through `tools/dev/qa-run.sh`, commits with the owner's git identity and explicit paths.

## Summary

On iPhone, Carden signs players in to Game Center without asking, once their first picture is done. Carden's own
achievements appear in Apple's Games app, three leaderboards (Total XP, Pictures This Week, Fastest 4x4) let friends
compare, and a Fastest 4x4 challenge lets a player race friends for a day, three days or a week. On iOS 26 and later
the Games app's Play buttons open the daily puzzle, a 4x4 board or the board in progress. Nothing about Game Center
reaches our backend.

## Why

- Apple promotes games that use it: "games that include Game Center features and In-App Events are prominently
  displayed across the Games app"; signing the player in "lets your game appear in social recommendations on the Home
  and Friends tabs, as well as in a new Top Played chart"; with leaderboards "players are automatically notified when
  a friend beats their score". The Games app is pre-installed on iOS 26, iPadOS 26 and macOS 26
  ([Apple Games app for developers](https://developer.apple.com/games-app/)).
- Challenges come almost free with a leaderboard: players "can invite their Game Center friends and anyone from their
  contacts", and challenges are "promoted throughout the Games app and other places around the OS"
  ([Creating engaging challenges from leaderboards](https://developer.apple.com/documentation/gamekit/creating-engaging-challenges-from-leaderboards),
  [WWDC25 214](https://developer.apple.com/videos/play/wwdc2025/214/)).
- Carden is half there: its primary category is Games (`store/metadata/en-US/categories.json`), which gives it a page in
  the Games app ([WWDC25 215](https://developer.apple.com/videos/play/wwdc2025/215/)), and 14 In-App Events went to
  review with 2.0.0. Game Center is the other half.
- What weakens it: no traffic numbers for small games; Top Played ranks by playtime, so Carden will not chart early;
  recommendations need Game Center friends who play. Challenges suit one fixed level everyone plays (short, 1 to 5
  minutes: [HIG](https://developer.apple.com/design/human-interface-guidelines/game-center)); Carden deals every board
  at random from different pictures, so a time race is noisy. And developers report that on iOS 26, starting Game
  Center for a player who is not signed in shows Apple's full-screen sign-in by itself
  ([forum thread 797602](https://developer.apple.com/forums/thread/797602); the handler bug with it is reported fixed
  in 26.2; whether the sign-in still appears is unverified). The start rules below keep that to one calm moment.

## What the player sees

Starting Game Center (iPhone only):

1. A new player: nothing on the welcome pages or the first board. The first time Home is on screen after the first
   board (`FirstSteps.homeAt` set) at a calm moment (`NotificationPromptHost.calmAt`, never with the notification
   question), Carden starts Game Center. A signed-in player sees Apple's short welcome banner at the top.
2. A player from 2.0.0: the same, at the first calm moment on a tab's page after the update.
3. After a sign-in, every launch starts Game Center at once. After a connection error: again at the next calm moment.
4. Not signed in: on iOS 15 to 25 GameKit hands Carden a sign-in screen, which Carden keeps and never shows by itself.
   On iOS 26 and 27 Apple may show its own (above). A cancel is recorded and Carden never starts Game Center by itself
   again; Settings offers it.
5. A Games app activity opened Carden (`GKGameActivity.hasPendingGameActivities`, checked before starting): Game
   Center starts at once, whatever the rules above.

Settings > Account > **Game Center** (a `_NavRow` in `settings_screen.dart`, iPhone only):

| State | Subtitle | Tap |
| --- | --- | --- |
| Signed in | "Achievements and leaderboards" | Apple's Game Center (`GKAccessPoint.shared.trigger(state:)`; the Game Overlay on iOS 26+) |
| Can sign in, or not started | "Sign in to keep achievements and leaderboards" | Apple's sign-in (or the start); on success achievements catch up quietly |
| Signed out, GameKit will not ask (after cancels) | "Not signed in" | Alert "Not signed in to Game Center" / "Sign in to Game Center in the Settings app, then come back to Carden." / Close |
| Restricted (Screen Time, a child account, Lockdown Mode) | "Not available on this iPhone" | Nothing |
| No connection | "Could not reach Game Center" | Tries again (unverified that a second handler retries) |
| Checking | "Checking…" | Nothing |

- Profile > Achievements: the section header gets "Game Center" (`SectionHeader.action`) while signed in; it opens Game
  Center on its achievements. No floating access point anywhere (HIG: not during play).
- A step becoming reached (Carden's "ready" state) shows Game Center's own banner, one at a time; Carden's dot and Claim
  stay. Catch-up (a first sign-in, a merged guest save, another device's play) shows none.
- Board picker (`difficulty_screen.dart`), iOS 26+, Cards 4x4 chosen, a challenge running
  (`GKChallengeDefinition.hasActiveChallenges`): one line under the sizes, "Challenge on: this board's time counts".
- Finish card of a board that counts for Fastest 4x4 (iOS 26+, signed in): a text button "Challenge a friend" opens
  Apple's challenge sheet (`GKAccessPoint.shared.trigger(challengeDefinitionID:)`).

Activities (iOS 26+, the Games app's Play buttons), each shown through `DeepLinks.show`:

| Activity | Opens | Leaderboard tied to it | Achievements tied to it |
| --- | --- | --- | --- |
| Daily Puzzle (`carden.act.today`): "A new picture every day, with a bonus." | `/daily` | Pictures This Week | Daily Devotee |
| Fastest 4x4 (`carden.act.fast4`): "A 4x4 Cards board against the clock, without Hints, Magic or Peek." | `/quick?grid=cards-4x4t2`: Quick play's picture, Cards 4x4 chosen | Fastest 4x4, so its challenge too | Quick Hands |
| Quick Play (`carden.act.play`): "The board closest to done, or a new picture." | `/continue`: Home's Continue, else `/quick` | Total XP | every other family |

- Like any link: over Home on a cold start, over the screen on show otherwise; a closed pack shows its pack. While the
  guided start keeps something back, the activity still opens it, as the widget and In-App Events do.
- A fresh install opened by an activity skips the welcome pages, as for any link, but plays the first board first,
  with a toast "First a nine-card picture, then your challenge" ("then the daily puzzle", "then a new picture"); the
  finish card's Home opens the activity's target (HIG: onboarding before a challenge).
- iOS 15 to 25: sign-in, achievements, leaderboards, the dashboard; no activities, challenges or challenge buttons.
  Apple's web invite page sends them to our fallback `https://play.carden.page/activity?a=<id>&c=<code>`, which
  2.1.0 and the web game read into the same screens (2.0.0 opens Home).
- Web and Android: nothing changes. QA runs (`CJW_QA`): Game Center never starts (no banner in screenshots, no test
  scores); `--dart-define=CJW_GC=true` allows it for a deliberate check, as `CJW_ANALYTICS` does.

## Rules and edge cases

Achievements:

- One per step of `achievementFamilies` (`lib/state/achievements.dart`): 52 steps of 23 families, without "VIP member"
  (decision 4; it stays in the app). Id `carden.ach.<family>.<step>`; title the family's in Title Case with a Roman
  numeral from step 2 ("Solver III", "On a Roll"); pre-earned description `family.describe(threshold)` ("Solve 50
  puzzles"), earned the same in the past tense ("Solved 50 puzzles"); two lines at most each (HIG). Catalogue order.
- Points (Apple: 100 achievements, 100 points each and 1,000 in all at most; fixed once live): 5-step families 5, 10,
  20, 30, 40; 3-step 5, 15, 30; 2-step 10, 20; single steps 10. 840 points, leaving 160 and 48 achievements.
- Reached means what Carden shows, from `achievementsProvider` (it already applies the guided start,
  `countsFromProvider(Reveal.achievements)`): step i is 100% when `i < claimedSteps` or `progress >= threshold`; the
  first step not reached reports its percentage. Nothing is reported while `Reveal.achievements` is closed (25
  pictures or Unlock anyway); the Games app shows the achievements locked meanwhile.
- Only increases are reported, against what `GKAchievement.loadAchievements()` returns after each sign-in (no local
  copy). One `GKAchievement.report` call per change.
- Banners (`showsCompletionBanner`): off for the first comparison after a sign-in, off when two or more steps are
  reached at once, off under Carden's Reduce motion; on for one new step during play.
- A Carden account switch keeps the iPhone's Game Center player: steps of either account stay reached. Delete account
  does not touch Game Center (Apple's data; the privacy policy says so).

Leaderboards (the one challenge is on Fastest 4x4: Apple advises against challenges on lifetime totals):

| Id and name | Kind | Score | Sent |
| --- | --- | --- | --- |
| `carden.lb.xp` Total XP: "All the XP you have earned. The same order as Carden's league." | classic, high to low, best score, integer, suffix " XP" | `Profile.xp` | when XP rises (a finish, a Play together guest reward) |
| `carden.lb.week` Pictures This Week: "Pictures finished this week. Starts again every Monday at 00:00 UTC." (default leaderboard) | recurring from a Monday 00:00 UTC (e.g. 2026-10-26), 7 days, every 7 days; high to low, best score, suffix " picture" / " pictures" | pictures with a finish (`PuzzleProgress.finishes`) since the occurrence's `startDate`, each once (the count `Goals.weekly` makes) | after each finish on this iPhone |
| `carden.lb.fast4` Fastest 4x4: "Your best time on a 4x4 Cards board, without Hints, Magic or Peek." | classic, low to high, best score, `ELAPSED_TIME_SECOND`, range 1 to 86,400 | the board's seconds (`GameState.elapsed`; unverified that the format takes whole seconds) | after every finish that counts |

- Fastest 4x4 counts a board that is Cards 4 by 4 (square, not Expand), not Painting, without Hint or Magic
  (`hintsUsed == 0`; Magic adds to it), without Peek (`peeked`), not shared (`widget.coopId`), finished on this iPhone.
  A resumed board counts: its time runs only while the board is in view.
- Scores go only at a finish, never at launch (Apple: no submissions during startup); a player who signs in later
  appears from their next finish.
- Challenge `carden.ch.fast4` "Fastest 4x4" ("Finish a 4x4 Cards board in the best time. No Hints, Magic or Peek."):
  repeatable (1, 3 or unlimited tries), 1 day, 3 days or 1 week. Each counting 4x4 finish during a challenge is a try
  (Apple's rule), hence "Challenge on"; a board left or discarded sends nothing. Apple's pages disagree on whether a
  repeatable challenge needs a recurring leaderboard; WWDC25 214's example is a classic one, like this.
- Game Center's week starts at one moment everywhere (UTC); the weekly quests use the local Monday, so the two counts
  can differ near Monday. Play together: a guest's board counts for XP only, as in Carden; a host's board counts,
  except for Fastest 4x4.
- Offline: GameKit keeps and retries scores; achievements are compared again at the next sign-in or finish.
  `isMultiplayerGamingRestricted` hides "Challenge a friend"; `isUnderage` and `isPersonalizedCommunicationRestricted`
  change nothing (no chat, no mature content). Macs and Apple Vision Pro run the same app (unverified: one check each).
- Game Center identifiers stay on the iPhone: never in Appwrite, analytics or logs (guideline 4.5.3: never relate
  Player IDs to other data; 4.5.5: never show them). Carden shows no Game Center name either.

## Data and backend

- Appwrite: nothing new. No table, column, index, function or permission changes; builds in players' hands are untouched.
- Device: a small LocalStore record `gameCenter` (`{started, signedIn, declinedAt}`), not a big value.
- Site: `web/.well-known/apple-app-site-association` gains `/activity` and `/continue`; deploy it before the first 2.1.0
  build (Apple's CDN can take a day). Builds before 2.1.0 open Home for both (`onException`).

Play together as a Games app multiplayer activity (research for decision 5):

- Possible: party codes work "with either GameKit multiplayer technologies or any alternative multiplayer solution",
  and `GKGameActivity.start(definition:partyCode:)` takes our own code
  ([Creating activities for your game](https://developer.apple.com/documentation/gamekit/creating-activities-for-your-game)).
- The catch: a party code is two equal halves joined by a dash, digits only or letters from
  `GKGameActivity.validPartyCodeAlphabet`: 20 characters, `23456789CFGHJMPQRVWX` (read from GameKit on macOS 27; iOS
  unverified). Join codes use 31 (`CODE_ALPHABET`, `functions/api/src/coop/rules.js`), so `K7QH-2MXP` fails.
- The 20 are a subset of the 31, so the fix is compatible: `api` makes new codes from the 20 with a new constant
  (`CODE_ALPHABET` stays, or `normaliseCode` refuses running games' codes); every build reads them
  (`AppLink.normaliseJoinCode`); `coop-game` stays. Server first.
- The rest: activity `carden.act.together` (2 to 5 players) started with the host's code (`2MP4-9CMF`), a guest's
  activity opening `/join/<code>`; a game begun in the Games app arrives with Apple's code and no picture (the first
  player picks one, `/coop/create` takes the code, the others wait); the HIG asks for the code shown and a way to type
  one. Two devices with two Apple Accounts to test.

## App changes

Native: `ios/Runner/GameCenter.swift` (new; in the Runner target of `project.pbxproj` like `SceneDelegate.swift`),
registered in `AppDelegate.didInitializeImplicitFlutterEngine` as plugin "GameCenter" (the `AppReview` and `GiftPush`
pattern). Channel `cjw/gamecenter`:

| Call | Does |
| --- | --- |
| `pending` | iOS 26+: `GKGameActivity.hasPendingGameActivities`; false below |
| `start` | sets `GKLocalPlayer.local.authenticateHandler` once per launch; keeps a sign-in view controller unshown; after sign-in `GKLocalPlayer.local.register(listener)` |
| `signIn` | presents the kept view controller from the foreground scene's root view controller (as `AppReview` finds the scene) |
| `open` | `GKAccessPoint.shared.trigger(state: .dashboard / .achievements)` (iOS 14+; `GKGameCenterViewController` is deprecated in 26) |
| `achievements`, `report` | `GKAchievement.loadAchievements()`; `GKAchievement.report` with `percentComplete` and `showsCompletionBanner` |
| `submit`, `occurrence` | `GKLeaderboard.submitScore(_:context:player:leaderboardIDs:)` (context 0); `loadLeaderboards(IDs:)` for the week's `startDate` and `duration` |
| `challengeActive`, `challenge` | iOS 26+: `GKChallengeDefinition.all` and `hasActiveChallenges`; `trigger(challengeDefinitionID:)` |
| `ready` | Dart listens; returns an activity that came first |
| to Dart: `state`, `activity` | `state`: signedIn, canSignIn, signedOut, restricted, offline, unavailable, with the `GKError` code, the restriction flags and `os26`. `activity`: id, properties, party code; Dart answers true for a known id, and that answer goes to the `GKGameActivityListener` completion (held until `ready` on a cold start) |

- `GKError`: `cancelled`, `userDenied` → signedOut (declined); `notAuthenticated` with a view controller → canSignIn;
  `parentalControlsBlocked`, `underage`, `notAuthorized`, `lockdownMode` → restricted; `communicationsFailure`,
  `connectionTimeout` → offline; `gameUnrecognized`, `notSupported`, `apiNotAvailable`, `appUnlisted` → unavailable.
- `ios/Runner/Runner.entitlements`: `com.apple.developer.game-center` true. `Info.plist`: nothing (no
  `NSGKFriendListUsageDescription` unless friends are read; never `UIRequiredDeviceCapabilities` gamekit).
- Unverified: how Apple's start-activity launch passes `FlutterSceneDelegate` with `FlutterDeepLinkingEnabled`
  (GameKit should take it and call the listener); check the router shows nothing for it.
- A plugin instead? `games_services` (5.3.0) wraps Game Center and Google Play Games: Google's games SDK in the Android
  build (against "Appwrite and Apple only"; which SDK is unverified), and no iOS 26 activities or challenges mentioned.
  A small channel is the house style (`cjw/review`, `cjw/push`) and adds nothing to Android or the web.

Dart:

- `lib/core/game_center.dart`: `GameCenterChannel` (like `PushChannel`); `lib/core/platform.dart`: `supportsGameCenter`
  (iOS app only) and `PlatformCaps.gameCenter`.
- `lib/state/game_center.dart`: `gameCenterProvider` (state, start rules, the record; `QaRun.enabled` without `CJW_GC`
  never starts), `GameCenterIds` (ids, points, activities), pure `gameCenterReports(statuses)` and `countsForFast4`,
  the reporter (listens to `achievementsProvider`, `profileProvider` XP, `progressProvider`; baseline at sign-in).
  `lib/state/rewards.dart`: a public `picturesFinishedSince(rows, start)` beside `_finishedIn`.
- `lib/app.dart`: `GameCenterHost` in the host chain (first start, pending activity, activities to
  `deepLinksProvider`), sharing the calm-moment check with `NotificationPromptHost`.
- `lib/core/app_links.dart`, `lib/features/links/deep_links.dart`: `/activity?a=&c=` (an id to its link, a `together`
  code to `/join/<code>`, unknown to Home); `/quick?grid=` (old builds ignore the query); `/continue` (`_closestToDone`,
  `_lockedShare`, `_gridCode` move from `home_screen.dart` to a provider); the fresh-install hold.
- `settings_screen.dart` (row in `group('Account', ...)`), `profile_screen.dart` (header action),
  `difficulty_screen.dart` ("Challenge on"), `game_screen.dart` (`_onWin` hands Fastest 4x4 over, "Challenge a
  friend", the first board's toast), `lib/widgets/icons.dart` (Apple's Game Center glyph, decision 8).

Tools:

- `tools/store/gamecenter_spec_test.dart` (outside `test/`, like `tools/dev/twins_report_test.dart`) writes
  `store/metadata/gamecenter/achievements.json` from `achievementFamilies` and `GameCenterIds`; the leaderboard,
  challenge and activity JSON files are kept by hand.
- `tools/store/gamecenter_art_test.dart`: each step's `AvatarCircle` with its tier ring and number (no two alike, HIG),
  centred for the circle mask, 1024 px (Material icon font via `FontLoader`, as `test/hint_lines_test.dart` loads fonts).
  `tools/brand/gamecenter_art.py`: 3840x2160 challenge and activity art (key content inside 2930x1534) and 1024 px
  leaderboard art (inside 1024x624) from `assets/welcome/` (PD/CC0) in the invite card's style; all in
  `store/gamecenter/`.
- `tools/store/asc_publish.py gamecenter [--dry-run]`, idempotent: `gameCenterDetails`, the 2.1.0
  `gameCenterAppVersions`, achievements, leaderboards, challenge, activities (versions, localizations, images,
  fallback URL, associations). `submit` also adds the `gameCenterAchievementVersion`, `gameCenterLeaderboardVersion`,
  `gameCenterChallengeVersion` and `gameCenterActivityVersion` items and refuses while one is missing.

## Apple, privacy and review

1. App ID: add the Game Center capability (check `bundleIdCapabilities` first; the local copy of the App Store profile,
   from 2026-10-11, has no `com.apple.developer.game-center`). "CJW AppStore cardjigsawworld" then turns invalid:
   recreate it under the same name (apple-release skill, "expected 2 profiles"); the widget's App ID stays. Refresh the
   local team profile before `tools/dev/device.sh`. CI (`macos-26`, Xcode latest-stable) has the iOS 26 SDK.
2. App Store Connect: Game Center on for 2.1.0; 52 achievements, 3 leaderboards, 1 challenge, 3 activities (limits: 100
   achievements, 100 leaderboards without sets, 20 challenges, 20 activities; ids up to 100 characters, permanent;
   achievement images 1024x1024, challenge and activity images 3840x2160 RGB without transparency); en-GB like the
   listing (unverified what other locales show). Apple's API guide says a single-player activity must be tied to a
   leaderboard, hence one each.
3. Review: first-time components go "in the same submission as your app version" (59 of the 200 allowed); one
   rejected component holds the rest. After 2.1.0 is live, set the challenges' minimum version to 2.1.0. Before
   release, Delete Test Data on the leaderboards (TestFlight plays on Apple's production servers).
4. `review_notes.txt`, a GAME CENTER part: Game Center starts after the first picture and the app never shows the
   sign-in itself (Settings > Account > Game Center); achievements mirror Profile's (guided start: after 25 pictures,
   or Guided start off); what each leaderboard counts; the challenge and activities in the Games app (iOS 26); no Game
   Center data reaches our server. A new entitlement can make Apple hold a TestFlight build: say so in
   `testflight_build_notes.txt`.
5. `docs/privacy-policy.md`, a "Game Center" section: "If you are signed in to Game Center on iPhone, Carden reports
   your achievements, total XP, pictures finished this week and best 4x4 time to Apple's Game Center. Apple shows them
   to you and, as your Game Center settings allow, to other players. We do not receive your Game Center identity, and
   nothing about Game Center is sent to our backend. Apple's privacy policy applies; deleting your Carden account does
   not remove them." Plus a line under "What other players can see", and whether Game Center was started on this
   iPhone under "Stored on the device only".
6. App Privacy answers: unchanged. Apple: "You are not responsible for disclosing data collected by Apple"
   ([App privacy details](https://developer.apple.com/app-store/app-privacy-details/)); Carden collects none of it.
7. Analytics (`AppAnalytics.event`, rows in `docs/analytics.md`; never Game Center ids, names or party codes):

| Event | Props | When |
| --- | --- | --- |
| `game_center_started` | `result` (`signed_in`, `signed_out`, `restricted`, `offline`, `unavailable`), `first`, `os26` | GameKit's first answer in a launch |
| `game_center_sign_in` | `result` (`signed_in`, `cancelled`, `failed`) | The sign-in from Settings |
| `game_center_opened` | `from` (`settings`, `profile`), `to` (`dashboard`, `achievements`) | Game Center opened from Carden |
| `game_center_activity` | `activity` (`today`, `fast4`, `play`), `cold`, `handled`, `via` (`games_app`, `fallback`) | An activity or its fallback link opened Carden |
| `game_center_challenge` | `from` (`finish`) | "Challenge a friend" |

## Accessibility

- Carden's parts (the row, the header action, "Challenge on", "Challenge a friend", the toast): colours from
  `context.colors` and `context.accent` (Increase contrast palettes), states in words and never by colour alone, no
  layout errors at Largest on the SE frame (design QA harness); "Challenge on" fits at 390 pt and joins
  `test/hint_lines_test.dart`. VoiceOver reads the row as label, subtitle and button.
- Reduce motion (Carden's): no Game Center completion banners, since they slide in. Apple's welcome banner, sign-in and
  Game Overlay follow iOS's own settings (Reduce Motion, Dynamic Type, VoiceOver), not Carden's switches.
- Achievement images: content centred in the circle, tiers told apart by ring and number (not colour), the glyph at 3:1
  contrast or more on its disc.

## QA

- Unit (`flutter test`), `test/game_center_test.dart`: ids unique, at most 100 characters; points within Apple's
  limits; `store/metadata/gamecenter/achievements.json` equal to `GameCenterIds` (as `test/economy_test.dart` keeps
  `GRANTS` equal); `gameCenterReports` (claimed floors, percentages, nothing before `Reveal.achievements`, the guided
  count); the banner rule; the week (UTC start, a picture once, other devices' rows); each Fastest 4x4 exclusion; start
  rules (`homeAt` and calm, after a sign-in, declined, offline, pending activity, never in QA, web or Android).
  `test/deep_links_test.dart`: `/activity` (ids, unknown, a party code), `/quick?grid=`, `/continue`, the
  association file.
- Integration: `tools/dev/qa-run.sh drive --driver=test_driver/integration_test.dart
  --target=integration_test/game_center_test.dart -d <pro>` with `CJW_GC=true` and a fake native side
  (`setMockMethodCallHandler` on `cjw/gamecenter`): the row in each state (light, dark, Largest), each activity warm and
  cold, a fresh install held through the first board, "Challenge on", and a 4x4 finish that submits (Painting: none).
- Simulator, real GameKit (once): nothing shows before the start; what `start` shows without a Game Center account.
  Developers report a broken Game Overlay on iOS 26 simulators ("Could not create endpoint for service name:
  com.apple.GameOverlayUI.dashboard-service"), so sign-in, dashboard and banners need a device.
- Device: Apple's Game Progress Manager (Xcode > Debug > GameKit > Manage Game Progress; iOS 18.4+ device, GameKit debug
  mode in the scheme, a `.gamekit` bundle pulled from App Store Connect and not committed) checks achievements, scores
  and each activity's deep link, cold and warm, without live data.
- Owner on TestFlight (two Apple Accounts; iOS Settings > Developer > Notify About Score Submissions):
  1. Fresh install, signed in: no banner on the welcome pages or the first board; the banner on Home after it.
  2. Fresh install, signed out: nothing before Home; note what iOS 26 or 27 shows; cancel and relaunch: nothing.
  3. An account with many achievements: a quiet catch-up; Game Center shows what Profile shows.
  4. One new step: one banner; with Reduce motion, none. Leaderboards fill; a Painting or Hint board adds no time.
  5. A challenge to the second account: Play opens the 4x4 picker with "Challenge on"; tries count.
  6. Each activity, cold and warm; a fresh install from a challenge plays the first board first.
  7. Game Center signed out, Screen Time, airplane mode; an iOS 18 device if at hand; a Mac.
- Builds, TestFlight and the submission only when the owner asks.

## Docs to update

- New `docs/game-center.md` (how it works, ids and points, rules, setup, testing), linked from CLAUDE.md (docs index,
  code map, the `CJW_GC` flag, the components in its App Store section).
- `docs/deep-links.md` (`/activity`, `/continue`, `/quick?grid=`, the fresh-install exception), `docs/analytics.md`,
  `docs/privacy-policy.md` (and its date), `docs/first-steps.md`, `docs/accessibility.md` (banners), `docs/native-ui.md`
  (the row, Apple's artwork and terms, no access point), `docs/release-checklist.md` and the apple-release skill
  (capability and profile, components with the version, test data, permanent ids), `tools/store/README.md`.
- `store/metadata/en-US/review_notes.txt`, `release_notes.txt` (2.1.0), `testflight_build_notes.txt`; with decision 5,
  `docs/multiplayer.md` and `docs/functions.md`.

## Open decisions for the owner

1. When Game Center first starts: (a) at launch for everyone (Apple's advice, the most Top Played time); (b) at the
   first calm Home, after the first board for new players; (c) only from Settings. Recommend (b), then every launch.
2. Leaderboards: (a) Total XP, Pictures This Week, Fastest 4x4; (b) only XP and the week, no challenge; (c) a fastest
   time per board size. Recommend (a).
3. The challenge: (a) Cards 4x4 without Hints, Magic or Peek, with "Challenge on" and "Challenge a friend"; (b) 3x3
   (too short, too random); (c) 5x5 (3 to 6 minutes, Apple's upper bound). Recommend (a).
4. Achievements: (a) the 52 steps without VIP, points as above (fixed once live); (b) with "VIP member" (rewards a
   purchase, reads as an ad); (c) one per family. Recommend (a).
5. Play together as a multiplayer activity: (a) in 2.1.0; (b) Apple-safe join codes on the server now, the activity
   later; (c) never. Recommend (b): it needs a lobby, code entry and two-device QA.
6. A fresh install opened by an activity: (a) the first board first (HIG); (b) straight there. Recommend (a).
7. Banners for new steps: (a) Game Center's, one at a time, none in catch-up or under Reduce motion; (b) never.
   Recommend (a).
8. The row's icon: (a) Apple's Game Center artwork in `icons.dart` (the HIG asks for it); (b) an AppIcons glyph.
   Recommend (a).
9. Configuration: (a) JSON in `store/metadata/gamecenter/` and `asc_publish.py gamecenter`; (b) an Xcode GameKit bundle
   pushed from Xcode (Apple's way, but Xcode's window). Recommend (a).
10. Id prefix, permanent: (a) `carden.`; (b) the bundle id; (c) `cjw.`. Recommend (a).

## Effort and risks

Effort, agent days plus the owner's device rounds: native 1; Dart state, host and links 1.5; screens 1; tests 1; App
Store Connect tooling 1.5; art 1; device QA and docs 1.5. About 8 to 9 days; decision 5 (a) adds 3 to 4.

- iOS 26 may show Apple's sign-in by itself at the first start: limited to one calm moment, never onboarding; check
  on 26.x and 27 first.
- The first Game Center review carries 59 components; one rejection holds them all; ids and points cannot change once
  live (archive only). The App ID change invalidates the App Store profile until it is recreated (known fix).
- Unverified: the elapsed-time unit, the start-activity launch under Flutter's scene delegate, the
  leaderboard-per-activity rule, Mac and Vision Pro.
- Fastest 4x4 is noisy (random pictures and deals), slow boards can be dropped, and a time race is new in a calm game
  (it stays opt-in). The gain is uncertain (no numbers, playtime charts, friends needed). Old builds: no risk.

## Not in this task (follow-ups)

- A daily challenge: one board and deal for everyone, a daily recurring leaderboard and a non-repeatable challenge
  (Apple's mini crossword example). Not picked; it would make challenges fair.
- Play together as a multiplayer activity with party codes (decision 5).
- More leaderboards (fastest per size or shape, a leaderboard set); achievements for new features.
- If the Journey ships too (branch `2.1.0/journey`): a "Journey stage" leaderboard (classic, high to low, the stage
  count), which works with random deals and suits a challenge-free friends race; Journey achievements.
- Game Center friends in Social (needs `NSGKFriendListUsageDescription` and a privacy review).
- In-App Events whose links open an activity; other languages; reporting from a server (ruled out by guideline 4.5.3).
