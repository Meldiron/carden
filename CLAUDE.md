# Carden — project instructions for Claude Code

Flutter card-swapping picture puzzle game (iOS first, web secondary, Android builds in CI only) with an
Appwrite backend. Owner: Matej Bačo (GitHub `Meldiron`). Read this file fully before any work; the
skills under `.claude/skills/` hold the detailed workflows.

**Name** (owner, 2026-10-15): the game is **Carden** ("Carden: Your calm picture puzzle"; App Store name
"Carden: Calm Picture Puzzle", the 30-character limit). It was Card Jigsaw World until build 118. Renamed: app
and Home Screen name, Flutter package `carden` (`CardenApp`), link scheme `carden://`, web address
https://play.carden.page (domain carden.page bought on Appwrite, 2026-10-16), repo `Meldiron/carden`, Appwrite
project/site/platform names, store copy. Kept on
purpose (old builds, Apple records, data): bundle id `com.matejbaco.cardjigsawworld`, the Services ID and product
ids, the Appwrite project/site/database ids (`card-jigsaw-world` site id, database `cjw`), the `CJW_` dart-defines,
the old scheme `cardjigsaw://` and the old addresses carden.appwrite.network and card-jigsaw-world.appwrite.network
(all still open the game; web guests keep their saves per address), and the local folder and
`~/.local/share/card-jigsaw-world`. The homepage (repo `Meldiron/carden-website`) is https://www.carden.page;
carden.page redirects there. Play together invites are https://join.carden.page/<code> (a domain of `api`, shared
from build 127; builds 124-126 share play.carden.page/join/<code>, which still works).

## Skills (load them when the task matches)

| Skill | Use for |
| --- | --- |
| `.claude/skills/testflight-feedback/` | Pulling TestFlight feedback, fixing it, QA, shipping a build, resolving items on Apple |
| `.claude/skills/apple-release/` | Any build, TestFlight push, version bump, App Store submission |
| `.claude/skills/pack-making/` | Picture packs: adding, repairing, auditing, sources, licences |
| `.claude/skills/giant-packs/` | Giant packs (category Giant, 100-300 card boards): sources, `giantcheck`, 4096 px hosting |
| `.claude/skills/inbox-messages/` | Messages to players (Social > Inbox): send with a gift and a button, list, expire, delete (`tools/dev/inbox.py`) |
| `.claude/skills/store-screenshots/` | App Store screenshots: captures, the glass slides (`tools/store/compose_glass.py`), copy and story, preview, upload |

## Owner rules (non-negotiable, learned from feedback)

- **Design**: no emojis anywhere, no vivid gradients, neutral professional look, colour comes from the
  photos. One accent: cobalt `Brand.accent` 0xFF2F4FBF (dark 0xFF7C9AFF) in `lib/core/theme/tokens.dart`.
  Icons only from `lib/widgets/icons.dart` (CoinIcon, TicketIcon = upright "pass" design, HintIcon,
  AppIcons). Native iOS 26 feel: glass bars/sheets (`lib/widgets/glass.dart`), every confirmation via
  `showAppAlert`, every sheet via `showAppSheet`, every menu of actions via `showAppActionSheet` and every
  toast via `showToast` (optional `action:` text button, then at least 4 s) in `lib/widgets/ui.dart`; switches are the glass `AppSegmentedControl`, round buttons over photos `PhotoButton`,
  the VIP card family is `lib/widgets/vip.dart`, and counts go through `formatCount` / `compactCount`
  (`lib/core/numbers.dart`). Costs on buttons use `BigButton.cost` / `CostLabel` (currency icon + amount);
  destructive actions are red and always ask first. Sheets (owner, 2026-10-18; `lib/widgets/sheets.dart`,
  docs/native-ui.md "Sheets") stop at `SheetMetrics.topGap` (8% of the screen; a tap above closes them) and close
  with a drag down at the top of their content (`SheetScrollController`): sheet content is a plain Column the sheet
  scrolls (`SheetScrollBody`, buttons that must stay in view in its `footer`), never a ListView in a fixed box; no
  close or delete buttons in a sheet header (delete from the row: swipe, asks first, VoiceOver action); full-height
  sheets use the router's `SheetPage` (tests `test/sheet_drag_test.dart`, QA `integration_test/sheets_test.dart`).
  A finished pack shows the one done badge
  `PackDoneBadges` (`lib/features/gallery/pack_progress.dart`: cobalt tick disc, gold star when perfect; no
  green); celebrations use `showConfettiBurst` (`lib/widgets/confetti.dart`), never with Reduce motion. See
  `docs/native-ui.md`.
  Haptics only through `Haptics` (`lib/core/haptics.dart`): selection, light, medium or success, never heavy; one
  gate (70 ms apart, 10 a second), tick runs of at most 5 (`Haptics.run`); Settings > Haptics turns them off, none
  on the web. Map in `docs/native-ui.md`, "Haptics".
- **Onboarding is instant** (owner, 2026-10-15): every picture the welcome pages show is bundled in
  `assets/welcome/` (PD/CC0 catalogue picks), never loaded from Storage.
- **Copy**: calm, precise, short; terms and CTA style in `docs/copy-guide.md`. The `/events` tab is
  called **Quests**: daily quests, weekly quests and the world-day "Live events" section.
- **QA is silent**: never start the app without `--dart-define=CJW_MUTE=true` (or `tools/dev/qa.sh`).
  The owner does not want to hear the game's music while you work.
- **QA players stay out of the league** (owner rule, 2026-10-13): every QA run plays a guest on the LIVE
  backend, so every run (flutter drive, flutter run on a simulator or Chrome, store screenshots) goes
  through `tools/dev/qa-run.sh <run|drive|test> ...` (or `tools/dev/qa.sh`), which passes `CJW_MUTE=true`,
  `CJW_QA=true` and a run id, then purges that run's test players. `CJW_QA` flags the guest
  (`profiles.isTest`, user prefs `qa`/`qaRun`); the league and its counts filter `isTest` on the server
  (a QA player sees only its own row). Integration tests refuse to start without the flag
  (`QaRun.requireForIntegrationRuns`, `test/qa_test_players_test.dart`). Leftovers:
  `python3 tools/dev/purge_test_players.py purge --apply` (dry run without `--apply`; `audit` explains
  every player; backups in `secrets/purged/`). Never purge by hand outside the tool.
- **QA the exact user path**: when fixing a reported problem, reproduce and verify the path the user
  described (e.g. Home > Continue > puzzle > pause menu), with a simulator screenshot you have looked
  at. Describing a fix on a screen the user never reaches is not a fix.
- **Pictures are self-hosted** (owner rule, 2026-10-13): every catalogue picture and cover is served
  from the Appwrite Storage bucket `puzzle-images` (`/view` for the game, `/preview?width=600` for tiles,
  `/preview?width=1080` for covers). Never write a third-party image URL to the database. The content
  tool hosts each pick on apply (`tools/content/cjw/host.py`); `tools/content/run.sh host` migrates
  anything left. The original address stays in `sourceUrl` (puzzles) / `coverSourceUrl` (packs, events).
- **The app talks only to Appwrite and Apple** (owner rule, 2026-10-13; analytics 2026-10-17): no
  third-party analytics, crash or ad SDKs, no CDNs. Usage analytics go only to Appwrite Analytics (property
  "Carden", tracking id 6ad3426500307dfae727) through `AppAnalytics` in `lib/core/analytics.dart`
  (`docs/analytics.md`): never from debug/profile builds or QA runs, off with Settings > Privacy > Share usage
  data; `--dart-define=CJW_ANALYTICS=true` only for a verification run. Pictures come from our Storage (above); the web build bundles CanvasKit
  (`--no-web-resources-cdn` in `tools/dev/deploy-web.sh`) and serves its default font from
  `web/fallback-fonts/` (`fontFallbackBaseUrl` in `web/flutter_bootstrap.js`). Apple traffic is
  StoreKit, Sign in with Apple, push notifications (APNs, friend gifts) and the widget/App Store system
  services. Check new dependencies for network use before adding them (share_plus: checked, no network of its
  own, mailto fallback off).
- **Builds only when the owner asks** (owner rule, 2026-10-13): never dispatch a TestFlight/App Store build
  (`gh workflow run`, `tools/dev/testflight.sh`, submissions) on your own initiative. Fix, QA, commit, push, then
  report that it is ready for a build. Same for installs on the owner's iPhone.
- **No single-page reads** (owner rule, 2026-10-13): never read a list with a fixed `Query.limit`.
  Data the app needs whole goes through `listAllRows` (cursor pagination over every page), counts
  through `countRows`, and lists people scroll (league, My Puzzles) through `listRowsPage` + a
  `PagedNotifier` (`lib/state/paged.dart`) that loads the next page near the end. Filter and sort on
  the server (`Query.equal`, `orderDesc`, `select`). `test/pagination_test.dart` fails on a fixed limit.
- **Every build also redeploys the web site** (`tools/dev/deploy-web.sh`) from the same commit.
- **Update prompt** (`docs/app-updates.md`): web and iPhone ask "Update available" when a newer build
  is out (looks every 5 min, Later = 1 hour, again after every reload/launch). Web compares its
  `CJW_WEB_BUILD` with the site's `app-version.json` (written by `deploy-web.sh`); iPhone compares its
  build number with table `releases` (`tools/dev/publish_release.py`, run by `testflight.sh` once
  Apple has the build out; after a hand-dispatched workflow run it yourself).
- **No big values in SharedPreferences** (2026-10-18): on the iPhone they are NSUserDefaults, and once an app's
  settings pass 4 MB iOS stores no further writes. Through build 127 the 5.6 MB catalogue sat there, so nothing
  else was saved: the welcome pages came back at every launch and the save sync showed this device's own play as
  "Synced from another device". Large or growing data goes in files (catalogue `Library/Caches/catalog.json`,
  `lib/data/catalog_cache_io.dart`; the sync's copy of the rows `Application Support/sync/<uid>.rows.json`,
  `lib/data/sync/device_copy*.dart`); small flags and the sync ops queue stay in preferences.
- **Versioning**: one version string per App Store cycle; TestFlight builds only bump the build number.
  Details in the apple-release skill. Never bump the version for a TestFlight cut.
- **Old builds stay in use** (lessons the owner collected, 2026-10-15): assume the client is outdated,
  the network unreliable and releases slow. Backend changes stay compatible with every build testers
  still have (add with defaults, never rename or remove what a live build reads; server before build).
  Server switches may only turn on or off what a reviewed build already contains; new features ship
  in a build and are described in the review notes. Details: "Old builds stay in use" and "What may
  change without a build" in the apple-release skill.
- **Resolve feedback** on Apple after fixing it (`asc_publish.py feedback --resolve`), so items are not
  fixed twice.
- **Subagents run on Opus** (`model: "opus"` on every Agent call).
- **Long multi-agent jobs**: watch the active account's 5-hour usage and pause everything when it
  passes the threshold the owner sets (default 50%): run `tools/dev/usage-watch.sh <LIMIT>` in the
  background; it exits when the limit is crossed, then stop the agents, push a checkpoint, tell the
  owner. If the owner asks to continue on the other account past a limit, `tools/dev/usage-relay.sh
  FIRST TARGET` switches with `cswap switch TARGET` when FIRST is crossed. Keep worker counts modest (4 to 5): many parallel downloads saturated the owner's internet.
- **Installing on the owner's iPhone: only when the owner asks** (owner rule, 2026-10-13; releases and
  feedback rounds do not install, TestFlight reaches the phone). When asked, `tools/dev/device.sh` works over Wi-Fi (the phone is paired;
  UDID 00008110-000024E63650401E). `--wipe` reinstalls fresh (onboarding), `--no-build` pushes the
  last build. Release builds keep sound; debug runs are muted.
- **Commits**: `git -c user.name="Matej Bačo" -c user.email="matej@appwrite.io" commit ...`, push to
  `origin main` (public repo `Meldiron/carden`). End messages with the Co-Authored-By
  trailer the harness gives you. Never `git add -A` while another agent works in the repo; add paths.

## Toolchain

- Flutter 3.47 at `~/flutter` (not on PATH): `export PATH="$HOME/flutter/bin:$PATH"`.
- Gates before any build: `flutter analyze --fatal-infos --fatal-warnings` and `flutter test`.
- Simulators: iPhone 17 Pro `CDD7317C-19D6-486D-B258-8AB8A607297D` (QA), iPhone 17 Pro Max
  `D03644FB-6169-4E87-8E0F-CCFC884FBE78` (App Store 6.9" screenshots).
- Screenshot QA: `tools/dev/qa.sh shots` = `tools/dev/qa-run.sh drive
  --driver=test_driver/integration_test.dart --target=integration_test/screenshots_test.dart -d <pro>`
  → `screenshots/*.png`. Any other suite: `tools/dev/qa-run.sh drive --driver=... --target=... -d <udid>`
  (never a bare `flutter drive`/`flutter run`; `QA_KEEP=1` keeps the run's players for inspection; it purges once
  on EXIT, HUP, INT and TERM, and a signal to qa-run.sh stops flutter too). Store captures: `test_driver/store_screenshots.dart` +
  `integration_test/store_screenshots_test.dart` → `store/raw/`. Extra suites:
  `integration_test/social_profile_test.dart`, `merge_sheet_test.dart`. QA runs send no analytics (`CJW_QA`); add
  `--dart-define=CJW_ANALYTICS=true` to a qa-run.sh run only to check that events arrive. Friend gifts:
  `tools/dev/gift_qa.py`, `integration_test/friend_gifts_test.dart`, `tools/dev/notification_check.sh <udid>`
  (a temporary UI-test target, never committed). Chrome is not installed on this Mac: web QA runs
  `-d web-server` and a headless browser. Parallel agents share the session scratchpad: unique file names.
  In an agent worktree `secrets/` already exists (the tracked issuer id): link the key files into it one by one, not
  the folder. `flutter drive` uninstalls the app at the end unless `--keep-app-running`; never keep a `simctl log
  stream` open during a drive (it kept drive from connecting); qa-run.sh deletes `build/flutter_driver_commands_*.log`
  (it reached 17 GB and filled the disk).
  Quirks: capture is in-app (host `simctl io screenshot` fires too late); uninstall the app before a
  second same-day run (`xcrun simctl uninstall <udid> com.matejbaco.cardjigsawworld`, the daily gift is
  otherwise already claimed); a stuck "Open in Carden?" prompt needs a simulator reboot; started
  puzzles resume directly, so tests needing the difficulty screen open an untouched picture.
- Board shape harness: `flutter test test/board_widget_test.dart` renders fused-group shapes for all
  modes to `build/board_shapes/`.
- Python helpers (store tooling, content): the venv and the content cache live in
  `~/.local/share/card-jigsaw-world/` (persistent, outside the iCloud-synced Desktop); `.venv` in the
  repo is a symlink to that venv, so `.venv/bin/python tools/store/asc_publish.py ...` works.
  `tools/content/.local-env` points the content tool at both. Recreate with `python3 -m venv
  ~/.local/share/card-jigsaw-world/venv && ... pip install -r tools/content/requirements.txt`.

## Code map

- `lib/game/`: `board.dart` (permutation board; the deal puts no playable card in place (pre-set pieces stay)
  and leaves no joined pair, except the 5x5 triangle board, which keeps one joined pair of halves on each side edge (`Tiling.unavoidableJoins`); a
  group a move lands on shifts whole when it has room, else breaks as before (`moveGroup`); square sizes in
  every mode, Cozy 3x3 to Master 7x7 (`BoardSpec.squareTiers` / `squareGiantTiers`), Triangles 4x4-7x7 with
  NxN = N columns of an up and a down triangle (`BoardSpec.squareDims`, shown via `BoardSpec.size`),
  Triangles from 3x3, Hexagons 4x4 to 7x7 (3x3 left out: every deal is solved in one move); pre-set pieces
  (owner, 2026-10-17): Triangles 3x3 and Hexagons 4x4 and 6x6 keep a full rectangle with their one-of-a-kind
  edge pieces (`Tiling.isPreset`) dealt in place, never picked, moved or counted (counts, progress and rewards
  use `playableCells` / `BoardSpec.progressOf`; Hexagons 4x4 always starts with one joined pair; tests
  `test/preset_pieces_test.dart`, `integration_test/preset_pieces_test.dart`); Expand lays a size out for the picture's
  shape (`BoardSpec.ladder` / `offersExpand`); the old picture-shaped ladder `BoardSpec.tiers` resumes old
  saves, matched by count and layout (`fromSaved(layout:)`); docs/boards.md), `twins.dart` (twin cards:
  `TwinFinder`, `Twins.settle`) and `twins_loader.dart` (`boardTwinsProvider`),
  `tiling.dart` (Grid/Triangle/Hex tilings, `fit`/`crop`, `boardAspect`, neighbours, vertex geometry),
  `modes.dart` (cards ×1.0, squares ×1.15, triangles ×1.35, hexagons ×1.5; route code
  `<mode>-CxRtT`, `?expand=1`), `gather.dart` (`gatherInto`, `canGather`, `shuffleLoose` / `shuffleInView`),
  `image_loader.dart`.
- `lib/features/game/`: `board_widget.dart` (one render path for all modes: unplaced pieces dimmed
  16%, joined groups fused with a cobalt outer outline, locked clusters fused without outline),
  `game_screen.dart` (HUD, toolbar Shuffle/Peek/Magic/Hint: Shuffle is free and not a move, Magic places a
  card and its picture neighbours, one move each, never a double lock; pause sheet with "Discard and pick a
  board", completion overlay with pack progress and "View picture"), `difficulty_screen.dart` (real-aspect
  preview of the part played, square sizes with the Expand switch, a plain Play / Continue button, Discard
  progress).
- A board dealt on the device opens on its whole picture first, then the cards glide to their dealt places
  (`GameState.previewing`; tap to skip; not a move, not a Peek; Reduce motion cross-fades); resumed and
  Play together boards skip it; integration suites set `GameScreen.dealPreview = false`. A tap ends Peek. Its time
  counts only while the board is in view (app in front, game page on top with its fade-in done, nothing over it:
  `_inView` in game_screen.dart, `GameController.holdPreview`); a picture that arrives while the app is away waits and
  shows whole for the full time on return (`test/deal_preview_screen_test.dart`; QA `integration_test/deal_next_test.dart`,
  Next puzzle with the picture 0-6 s late via `debugPictureDelay`).
- **Twin cards** (owner, 2026-10-17; `docs/twins.md`): cards that look the same are twins (CIEDE2000 per
  ~4 px box and outline strip: mean ≤ 1.0, 95% ≤ 1.8, max ≤ 3.0, specks ≤ 1.6 L or 3× grain; near black and
  near white differences count less, `TwinFinder.seen`, specks in the dark over 3x3 pixels, limit 3.4; on dark
  ground 1 to 8 pin-point specks a card are painted out before measuring (a starfield is not), and dark pairs get
  an edge test so silhouettes stay apart). A move that
  puts a loose card on a twin's place, or where a twin would join a neighbour, counts as placed or joined by
  an identity swap of two loose cards (`Twins.settle` in `GameController._apply`; `GameState.cardKeys` keeps
  each card's widget, `_TwinFade`). The deal, Shuffle and Gather avoid twin places and joins (a crowded twin
  class on a small triangle or honeycomb board may start one card locked). A fresh board waits for its twins
  (`useTwins`, `awaitsTwins`). Saves stay permutations. Integration suites find cards through
  `GameState.cardKeys`, never `ValueKey('card-N')` alone. Report: `tools/dev/twins_report_test.dart` +
  `tools/dev/twins_sheets.py`; QA: `integration_test/twins_test.dart`.
- `lib/state/catalog.dart`: `catalogProvider` is the catalogue (packs, puzzles, events; refresh by
  invalidating it); `packRowsProvider`, `allPuzzlesProvider` and `eventsProvider` read it.
  `packsProvider` is what screens see: `Pack.isReleasedAt` hides daily months until their first day and
  event packs until 3 days before they open (content is created up to a year ahead).
  Daily month packs are always named "<Month> <Year>": `finalize_pack` keeps it (`daily_month_label`), so never put
  `name`/`description` in a shared daily spec; the app shows that name for an empty or bare "Daily" (`Pack.nameFor`);
  repair with `tools/dev/fix_daily_pack_names.py` (all 24 months of 2023-2024 fixed 2026-10-18).
- **Catalogue sync** (`docs/catalog-sync.md`; the copy on the device: a file on the iPhone (until build 127
  SharedPreferences, moved once), IndexedDB on the web, `CatalogCache`): `lib/state/catalog_sync.dart` (`CatalogSync`, snapshot +
  delta sync). A launch reads only rows changed since the newest one on the device (about 30 reads); the
  base comes from the daily snapshot file (function `catalog-snapshot`) on first launch and weekly. Never
  read a whole catalogue table on launch (8k+ rows, each one a billed read). The content tool sets
  `packs.puzzlesUpdatedAt` whenever it changes a pack's puzzles (`finalize_pack`): that is how devices
  and the snapshot see removed puzzles. Its duplicate check uses `catalog.sync()`, not a full dump.
- **First steps** (owner, 2026-10-16; `docs/first-steps.md`): new players go from the welcome pages straight into a
  first board (Pink Sands Beach, 3x3) with one hint line per step, then a calm Home (the suggested picture on top, the
  only thing to play until the Library opens; the rest blurred under "More opens as you play"). Only the first picture
  counts until Home is first on screen, then every one (`countedFinishesProvider`). Everything opens by pictures
  counted (`Reveal` in `lib/state/first_steps.dart`): Library tab and Quick play 3, daily puzzle 5, daily gift 10, Lucky
  Wheel 15, Quests 20, achievements 25, piggy bank 30, live events 35, Social 50 (offers 20); nothing is announced.
  Quests and achievements count only pictures finished after they open (`countsFromProvider`). Locked tabs and
  sections say "N more pictures" and offer Unlock anyway, which always asks "Are you sure?" (Home's first lets the
  player pick what to unlock). Players from before have no record and see everything. Integration suites call
  `FirstSteps.skipFor(store)`; `integration_test/first_steps_test.dart` plays the path. Hints and tips fit 2 lines
  at 390 pt; locked cards and Home's list use a one-line title and description (`Reveal.opensAfter`,
  `Reveal.blurb`); `test/hint_lines_test.dart` enforces both. Skip and Start playing save `onboarded` at the tap;
  `integration_test/welcome_relaunch_test.dart` relaunches for real (`--keep-app-running`, see its header).
- `lib/state/`: `profile.dart` (`Economy` constants, VIP, piggy 5/picture up to 500, five upgrades of 100
  for 5,000 coins each up to 1,000: `profiles.piggyLevel`, `SyncOp.piggyUpgrade`; Lucky Wheel ×5 spin: 5
  tickets, prize ×5, same odds, `Economy.wheelBigSpin`), `rewards.dart` (level curve
  `LevelRewards.levelForXp`, level-up coins `LevelRewards.coinsForLevel`: 100 + 25 a level up to 300, 500
  every 10th level; daily 3 + 1 VIP / weekly 5 + 1 VIP quests), `achievements.dart`,
  `progress.dart`, `merge.dart` + `merge_flow.dart` (guest→account save merge), `auth.dart`, `social.dart`.
- **Save sync** (`docs/sync.md`): `lib/state/sync.dart` (`SyncController`: queued ops, fetch on start/resume/
  focus/sign-in, conflicts) + `lib/data/sync/` (`ops.dart` intents → atomic operators, `notice.dart`,
  `backend.dart`). Profile and progress changes go through `enqueue(SyncOp...)`; never write totals
  computed on the device. "Synced from another device" alert and "Two boards in progress" sheet live in
  `lib/features/sync/`. The alert reports only another device's or the server's changes (`SyncSource` in
  `notice.dart`: op ids name their device, each device keeps its newest 10 in `profiles.appliedOps`;
  `test/sync_first_board_test.dart`).
- `lib/features/ads/house_ads.dart`: house ads only (no ad network). Break offer every 3rd completion
  or when the last break is 3+ minutes old, closable after 5 s, rewarded 15 s; the offer CTA never
  skips the rewarded countdown.
- `lib/data/purchases.dart`: StoreKit products (coins_1000/3000/5500/12000, tickets_5/15, hints_5/15 =
  booster bundles of Peeks, Hints and Magic (15/10/5 and 50/30/15), vip_monthly/yearly), verified server-side by `/purchase/verify` on `api`. `PurchaseService` listens from
  launch, checks open transactions on resume and retries checks without an answer; `PurchaseFlow`
  (`lib/state/purchases.dart`) and `PurchaseHost` (`lib/features/store/purchase_host.dart`) show the tile
  spinner, the purchase sheet ("Adding 10 tickets" > "10 tickets added") and toasts. Flow: `docs/purchases.md`.
- `lib/widgets/adaptive.dart`: wide windows on the web (top bar from 900 px, centred pages, adaptive
  grids, shelves with arrows, sheets as centred panels); phones keep their layout. `docs/web.md`, "Layout".
- `lib/core/platform.dart`: web capability flags.
- **Play together** (co-op, owner 2026-10-17; `docs/multiplayer.md`): up to 5 players on one board. `lib/state/coop/`
  (`CoopLog`: changes as slots with the card expected before and after, applied in `$sequence` order, a change
  that no longer fits is skipped everywhere; `CoopController`/`coopProvider`; `CoopBridge`/`CoopBoardTarget`),
  `lib/data/coop_repository.dart`, `lib/features/coop/` (`CoopHost` in app.dart, `CoopPlayersChip` and the player
  list, alerts, `CoopGuestFinish`, `openInvite`, `startPlayTogether`, `shareInvite` via share_plus). Game screen
  route `?coop=<id>` (`&next=1`); `GameController.showShared` / `sharedCardKeys` (twin trades). Player colours
  `PlayerColors` in tokens.dart. Guest rewards via `SyncOp.coopReward` (coins, XP, level, piggy; only after a
  lock of their own; nothing to progress, quests, achievements, pack progress or first-steps counts). Return to
  game: `coop.active` in the local store. "Get Carden" is the public TestFlight link until launch
  (`AppLinks.getCarden`, `GET_CARDEN` in web/index.html; docs/release-checklist.md). QA: `node
  tools/dev/coop_bot.mjs &`, then `coop_live_test.dart` (guest), `coop_host_test.dart` (host) and
  `coop_pair_test.dart` (two simulators, `CJW_COOP_ROLE=host|guest`; start the guest after the host's build).
  Store capture `32_coop_board` (scripted stage backend). Live picks and drags (2026-10-17, build 126): one
  `coop_drags` row per player and game (made by `api` on /coop/create and /join; card, phase, x/y as board
  fractions), picks sent at once, drag positions 5 a second within Appwrite's 120 updates a minute per player
  (`lib/state/coop/coop_live.dart`); others see the card glide about 0.25-0.5 s behind the finger. Deploy `api`
  before a build that sends live rows, then `node tools/dev/api_check.mjs`. QA: `integration_test/coop_drag_test.dart`
  (the bot's `/pick`, `/drag`, `/live`, `/liverows`). First grab wins: a card or group another player picked or drags can't be grabbed
  here (`LiveClaim`, `CoopController.claims`, `BoardWidget.blocked` / `onDragRefused` / `onDragLost`; ties go to the
  earlier `$updatedAt`); the board follows a drag by card and never leaves one stuck; moved marks fade over 1.5 s
  with no initial and catch-ups add none. QA: `integration_test/coop_race_test.dart`, `coop_pair_test` (same-card
  grab), `coop_drag_test` steps 6b/6c.
- Analytics: `lib/core/analytics.dart` (`AppAnalytics.event` one-liners, `ScreenObserver` on the root and every
  tab navigator, screen names from route patterns, never ids). New features add their events there and in
  `docs/analytics.md`; the privacy policy's usage data section must match.
- Accessibility (`docs/accessibility.md`, owner 2026-10-16): Settings > Accessibility has Text size (Default /
  Large 150% / Largest 200%), Reduce motion, Increase contrast and Differentiate without colour, all off until the
  player turns them on (the iPhone's own switches do not). App code reads them only through `A11y`
  (`lib/core/a11y.dart`: `reduceMotionOf`, `increaseContrastOf`, `symbolsOf`, `motion`, `largeText`). New UI must
  keep them working: colours from `context.colors` / `context.accent` / `context.star` (Contrast palettes), no
  spin, zoom or slide without an `A11y.reduceMotionOf` fallback, a symbol or text beside any state shown by colour
  under `symbolsOf`, and no layout errors at Largest on the SE frame (design QA harness, scene pref
  `accessibility`). `test/accessibility_test.dart` checks defaults and Contrast ratios.
  `lib/core/sfx.dart`: `CJW_MUTE`. `lib/core/qa.dart`: `CJW_QA` / `CJW_QA_RUN` (test players).
- Daily gift week: `GiftWeek` (`lib/state/daily_gift.dart`) numbers the 7-day ladder by the streak (Day 8-14 in
  week two, Home dots and the sheet); the gifts still cycle `Economy.dailyRewards[(day-1)%7]`. QA:
  `integration_test/streak_week_test.dart`.
- Home Screen widget (`ios/DailyWidget`): today's picture from Storage `/preview?width=1080` (`/view` fallback), drawn
  at the widget's exact pixels (`DailyPicture.swift`; WidgetKit refuses an image over about 4.4 times the widget's
  pixel area and shows a grey placeholder: the grey square through build 126); the app asks for a reload on resume at
  most once an hour. Check: `tools/dev/widget_picture_check.sh <udid>`; put it on a simulator's Home Screen with
  `tools/dev/sim_home_widget.py add|restore <udid>`; its log: `xcrun simctl spawn <udid> log show --predicate
  'process == "DailyWidget"'`.
- Daily reminders: local iOS notifications, no server (friend-gift notifications are pushes, see Friend
  gifts). `lib/state/reminders.dart` (`planReminders`: one a
  day for a week at the Settings time, none on a day the daily gift is claimed; replanned on start, resume
  and background), `lib/core/reminders.dart` (channel `cjw/reminders`), native side `DailyReminders` in
  `ios/Runner/AppDelegate.swift`. Integration runs ask for provisional permission (no prompt to tap);
  `integration_test/quests_reminders_test.dart` checks a reminder really fires. `planEventReminders`
  (Settings > New events): the evening before an event opens, only for notes 5+ days out (lapsed players).
  They are promotional, so they are off until the player says yes (guideline 4.5.4).
- Notifications (owner, 2026-10-18; `docs/notifications.md`): one question after the 2nd finished picture, at a calm
  moment on a tab's page (`NotificationPrompt`, `NotificationPromptHost` in app.dart): a switch per kind, all on,
  Allow then iOS's real prompt, Not now asks nothing; asked once, never on the web, in QA runs or once iOS has
  answered. It replaced the reminder and gift questions. Settings > Notifications: Daily reminders, New events,
  Gifts from friends, Messages from Carden (event notes and messages off until the player says yes). Messages from
  Carden: the push target joins the Messaging topic `carden-messages`; `gifts-off` marks a target kept only for
  messages, which `/gift/send` leaves out (`api` and `send-gift` have the scopes `subscribers.read`, `targets.read`
  since 2026-10-18). `tools/dev/inbox.py` pushes every send to the audience's subscribed phones (`--no-push`,
  `push <id>`); the tap opens `/inbox?message=<id>&from=carden`. QA `integration_test/notification_prompt_test.dart`
  (reboot the simulator afterwards: an unanswered iOS prompt survives an uninstall).
- Painting and giant boards: `progress.painting`; `lib/state/giant.dart` (`isGiantPack`,
  `isGiantPuzzleProvider`: packs of category `Giant` get the Large/Huge/Giant/Colossal ladder only, square:
  Cards 10x10 to 17x17 (100-289 cards), Triangles 10x10 to 18x18), `puzzleImageFullProvider` (full-resolution decode), `BoardZoom` in
  `board_widget.dart` (pinch, two-finger pan, `fitCell` zoom limit, auto-pan; no double tap); the bar,
  overview map, off-screen pointer and milestones in `lib/features/game/giant_board.dart`; saved views and
  the map switch in `GiantViews` (`lib/state/giant.dart`). No zones and no Edges (owner removed both
  2026-10-14): Locate (tap a card, the map shows its place, only while the map is on; always on),
  Gather at any zoom (`lib/game/gather.dart`; dimmed while the view has nothing to bring in, `canGather`;
  its toast has the game's only Undo, while nothing else changed), Shuffle on a giant board deals only the
  loose cards in view, Magic puts the selected card and its neighbours in place, and Peek (10 coins on every board) flies
  the cards to their places and back. Design and research: `docs/giant-boards.md`. QA:
  `integration_test/giant_ux_test.dart` (real Giant pack, about 4 minutes) and `giant_tools_test.dart`.
- Progression: `lib/state/unlocks.dart` (`openFeaturesProvider`, intro bookkeeping) and `Unlocks` /
  `OpenFeatures` in `lib/state/rewards.dart`: Squares, Triangles, Hexagons, Painting and giant boards open at
  levels 2/4/6/8/10 or once used; `lib/features/game/unlock_intro.dart` (intro sheet, `UnlockIntroHost`).
  Giant boards can be opened early from a giant pack's gate: the pack's tickets plus `Economy.giantEarlyFee`
  (1 ticket per level to go), recorded as `early:giant` in `profiles.unlockedTiers`.
  Any quest not finished or claimed can be swapped for 1 ticket by swiping its row left (Dismissible like
  Friends, then the showAppAlert confirmation; VoiceOver action "Swap for 1 ticket"; `QuestSwap`, `Goal.swap`,
  `Goals._withSwaps`, `profiles.questSwaps` JSON text, `SyncOp.questSwap`; only that quest changes; older builds
  show the first quest; docs/economy.md "Swapping a quest"). A timed quest's target never goes below
  `Goals.fastFloor` (3x3 15 s ... 7x7 3:35).
  Quests: `Goals.daily` / `weekly` rotate by day and week and take `open`, `level`, `claimed` (and the
  daily puzzle); each quest comes from a different lane, chosen against the player's `PlayHabits`, so
  ordinary play finishes only "Solve 3 puzzles" and one board never finishes two (docs/economy.md, "Quests
  that do not overlap");
  `lib/features/events/quest_rewards.dart` (`questsFor`, `readyGoals`, `readyEventsProvider`, Claim all).
  Integration suites that play every shape override `openFeaturesProvider` and `pendingUnlockIntroProvider`.
- Deep links (`docs/deep-links.md`): `lib/core/app_links.dart` (`AppLink.parse`: one path set for the web
  address, `carden://` (and the first name's `cardjigsaw://`) and universal links; kinds page/overlay/action) and
  `lib/features/links/deep_links.dart` (`DeepLinks.show`: Home beneath overlays, sheets for `/redeem?code=` (web
  only), `/add-friend?code=`, `/gift`, `/piggy`; a picture in a pack the player has not opened shows the pack). iPhone
  links arrive in `CardJigsawApp.didPushRouteInformation`, a web visit's start address in `routerProvider`.
  Universal links (on from 2.0.0; Associated Domains on the App ID since 2026-10-16): `applinks:` for
  play.carden.page and both appwrite.network addresses in `Runner.entitlements` +
  `web/.well-known/apple-app-site-association` (keeps `/auth/*`, `/redeem*` and `/code*` in the browser). A new
  link goes into `AppLink.parse`, the association file, the doc and `test/deep_links_test.dart`;
  `applinks:join.carden.page` from build 127, its association file served by `functions/api/src/invite/page.js`. `/join/<code>`
  invites to a shared game (a fresh install goes straight to the board; onboarding begins after leaving);
  `/inbox?message=<id>` (also `/inbox/<id>`, `/messages/<id>`) opens one Inbox message (gift notifications).
- `lib/state/app_update.dart` + `lib/features/update/update_host.dart`: update prompt (above).
  Web-only page helpers (fetch past the cache, reload) in `lib/core/web_page.dart`; Safari trackpad
  pinch (gesture events) is turned into Flutter's ctrl+wheel zoom by a script in `web/index.html`.
- `lib/state/account_deletion.dart`, `lib/state/review_prompt.dart` (`ReviewRules`: App Store rating after a
  3-star solve or finished pack, 5+ solves, once per version and 120 days), `lib/core/app_review.dart`
  (channel `cjw/review`).
- Routes (`lib/router.dart`): /welcome /home /library /library/pack/:packId /events (Quests) /social
  /profile (+settings, account, my-puzzles) /play/:puzzleId (difficulty) /game/:puzzleId/:grid /store
  /wheel /account /auth/callback /player/:userId. One `GoRouter` for the app's life (it listens to
  `onboarded` instead of being rebuilt, so a link that finishes onboarding keeps its screen).

## Backend (Appwrite Cloud)

- Endpoint `https://fra.cloud.appwrite.io/v1`, project `6acb4de5003e38d5ebd9`, database `cjw`
  (tables profiles, packs, puzzles, progress, events, event_progress, friends, ledger, my_puzzles,
  purchases, meta, releases, reports, blocks, feedback, messages, gifts, coop_games, coop_moves, coop_drags, apple_notifications). Profiles are readable by anyone; `level` mirrors XP; aggregates `totalMoves`,
  `totalSeconds`, `solvedByMode`, `questsCompleted` and the "Total Completion" numbers
  (`picturesSolved`, `picturesPerfect`, `packsCompleted`, `packsPerfect`, kept in step by
  `ProfileNotifier.syncCompletion`, backfill `tools/dev/backfill_profile_stats.py`) are public.
  `profiles.piggyLevel` (0-5) and `profiles.questSwaps` (text) since 2026-10-17. `progress.finishes` (string 4000,
  optional): each finished board with its own values (`BoardFinish`, `lib/models/board_finish.dart`, docs/sync.md);
  quests and `PlayHabits` count it, never the row's board fields, which a replay overwrites; the app retries a
  write without it while the column is missing (`writeWithoutUnknown`).
  Achievements (`AchievementFacts`) also count `PuzzleProgress.finishes`; the finish list keeps, from any time, the boards
  they count a picture by; `achievementStatus` never takes back a claimed step. Analytics property "Carden"
  (6ad3426500307dfae727, domain carden.page): `appwrite analytics list-metrics --property-id
  6ad3426500307dfae727`. appwrite SDK 27.2.0 (28.0.0 breaks: Dart 3.10, plugin). Messaging push providers
  `apns` (production) and `apns-sandbox`, key 2QJPJFW8JW (APNs on since 2026-10-17); the App ID has Push
  Notifications and the CI profile "CJW AppStore cardjigsawworld" was remade with it; `aps-environment =
  $(APS_ENVIRONMENT)` (Debug/Profile development, Release production).
  `isTest` marks QA players (excluded from the league). `profiles.appliedOps` / `event_progress.appliedOps` (ids
  of applied sync ops, exactly-once retries) and `progress.session` (play-through id) belong to the save sync.
  `progress.painting` marks a Painting board (x1.25); `progress.par` / `peeked` / `bestLock` feed the quests. `purchases.ownership` / `purchases.appTransactionId`
  (index `idx_apptx`) track Family Sharing (VIP is family-shared since 2026-10-14, irreversible; at most 6
  game accounts per subscription).
- Report and block (guideline 1.2, owner 2026-10-15): Player > Report writes a `reports` row (reporterId,
  reportedId, reportedName, reason as text) with no permissions, so only the server reads it; read and close
  them with `tools/dev/reports.py` (look regularly: Apple wants timely responses). Player > Block writes a
  `blocks` row readable only by the blocker; blocked players are left out of their leaderboard (one
  `Query.notEqual('$id')` each) and their friendship ends; Settings > Blocked players unblocks. Both tables are
  deleted in both directions with an account (`/account/delete` on `api`, `PAIR_TABLES` in `tools/dev/cjw_admin.py`).
  `lib/state/social.dart` (`PlayerSafety`, `blockedPlayersProvider`), `lib/features/social/player_safety.dart`;
  a block closes the profile (`leaveBlockedProfile`, Social when nothing is below). Friends > Share opens the share
  sheet with the `/add-friend?code=` link (`lib/features/social/friend_invite.dart`; the web copies when it cannot share).
  Offensive names (owner, 2026-10-16): `lib/core/name_filter.dart` (`NameFilter`) refuses them where a name is
  chosen (name alert, sign-up, new profiles) and shows names that fail as "Player" (`Profile.fromRow`, friends,
  blocks, merge), so names set by older builds are covered on 2.0+; links, @handles, e-mail addresses and
  domains are refused too (`NameFilter.isRefused`), and the hourly sweep resets stored names that fail.
  `test/name_filter_test.dart`.
- Friend gifts (owner, 2026-10-17; `docs/friend-gifts.md`): Player > Send a gift (1 ticket or 150 coins, free,
  one per friend per sender's local day, 20 a day per sender; `/gift/send` on `api`, table `gifts`; a push only
  between mutual friends, at most 5 a day per recipient;
  `messages.fromUserId/fromName/fromAvatar`, 24 h `expiresAt`). Push: `GiftPush` (`cjw/push`,
  AppDelegate.swift) + `PushRegistration` (`lib/state/push.dart`) register the APNs token as an Appwrite push
  target (provider from the build's embedded profile); Settings > Gifts from friends; a tap opens
  `/inbox?message=<id>`. Permission comes from the notification question (Notifications, above), never at launch.
- Inbox (owner, 2026-10-16): Social > Inbox shows messages from the owner. Table `messages` (subject, body,
  `sentAt`, `expiresAt`, rewards, `ctaLabel`/`ctaLink` any app link), row-level permissions only: one player
  (`user:<id>`), an Appwrite label (`label:early`) or everyone (`users`); the app reads whatever it may read.
  Written only by `tools/dev/inbox.py` (skill `inbox-messages`, also player labels). Seen, claimed and deleted live
  in `profiles.inbox` through `SyncOp.inbox` (a gift is paid once per message and player). An unopened message dots
  the Social tab and the Inbox segment (tab dots stay on the tab being shown until resolved). `lib/state/inbox.dart`,
  `lib/features/social/inbox.dart`. A player's own rows are deleted with the account.
- Help (owner, 2026-10-15): Settings > Help > Contact support opens an email to contact@almostapps.eu with
  the version and player id below the message (copies the address when there is no mail app); Send
  feedback writes a `feedback` row (userId, message, appVersion, platform) with no permissions, so only the
  server reads it: `tools/dev/feedback.py` lists and closes them. Deleted with the account (`delete-account`)
  and with QA players. `lib/features/profile/help.dart`. Shake to send feedback (owner, 2026-10-18; iPhone only): a
  shake on any screen opens Send feedback over everything (`ShakeFeedbackHost`, `lib/core/shake.dart`, channel
  `cjw/shake`, `UIWindow.motionEnded` in AppDelegate.swift; the app delegate never gets shakes), Settings > Help switch,
  on by default. QA `integration_test/shake_feedback_test.dart`; shake a simulator with `xcrun simctl spawn <udid>
  notifyutil -p com.apple.UIKit.SimulatorShake`.
- Legal links: `AppLinks` in `lib/core/links.dart` (privacy policy = `docs/privacy-policy.md` on GitHub, the
  same URL as the listing; terms of use = `docs/terms-of-use.md` on GitHub, Carden's own terms on top of
  Apple's standard EULA, which applies, the URL the listing's description gives) in Settings > About, under
  the VIP plans in the store and on the sign-in screen. Keep `docs/privacy-policy.md` and
  `docs/terms-of-use.md` true to what the app does (`test/legal_links_test.dart`).
- Pack codes (`docs/pack-codes.md`): `packs.hidden` packs are listed only for players who own them;
  codes in the server-only `pack_codes` table (SHA-256 hashes) and `code_claims`; `/code/redeem` on `api`
  (redeemed on the web only: the Settings row and `/redeem?code=` links; the iPhone app has no code entry and a
  code link opens nothing there (owner, 2026-10-16; guideline 3.1.1)); private pack pictures in bucket `private-packs`, readable
  per claimant. Tools: `tools/dev/private_pack.py`, `tools/dev/pack_codes.py`. The Hidden Object Adventure
  test pack (`pack-hidden-object-test`) is unlicensed art for an internal test only: never make it public.
- Functions (`docs/functions.md`): the app calls one function, `api` (`AppwriteConfig.apiFunction`), by path:
  `/purchase/verify` (StoreKit 2 JWS verification, grants), `/account/delete` (the caller's rows, uploads and user;
  secret `APPLE_SIGNIN_KEY` = contents of `AuthKey_2QJPJFW8JW.p8` revokes Sign in with Apple; also reports, blocks,
  gifts both ways, messages sent as gifts, co-op moves and hosted games), `/code/redeem` (web), `/coop/<action>`
  (create/join/leave/remove/end/next; a team per game, seats in membership roles), `/gift/send`, `/health`. Its
  hourly schedule runs the co-op cleanup and the integrity sweep (`SWEEP_APPLY=true`: squatted or foreign-permission
  rows in progress/event_progress/friends/blocks, ghost profiles, orphan or public uploads, 500 photos per player,
  refused names; full pass daily 04:00 UTC; invite cards older than 10 days), and a `blocks` create event checks new rows at once;
  execute `any`, domains `cjw-api.fra.appwrite.run` and `join.carden.page` (invite pages only, edge-cached 10 min:
  title and tags name the host, picture, board and players; no ids). Invite cards (1200x630 JPEG, today's design
  with the real picture, shapes and count) are drawn in plain JS on `/coop/create` in a worker (`functions/api/src/invite/`:
  raster, jpeg, and `tiling.js`, a port of `lib/game/tiling.dart` to keep in step, checked by `test/invite.test.mjs`)
  into the public bucket `invite-cards` (keyed by picture, board, Painting and week); lettering atlas and
  `web/invite-card.jpg` from `tools/brand/invite_card.py`. Any `api` deploy must include this code; `/admin/sweep` and
  `/coop/cleanup` are for the owner's CLI and refuse callers without a user. Live checks: `node tools/dev/api_check.mjs`, `security_check.mjs`.
  Modules load lazily; a cold start is about 5 s, warm calls 0.1-0.5 s. Kept for builds up to 124 (retire only
  when no build that calls them can be used): `verify-purchase` (also Apple's App Store Server Notifications at
  `https://cjw-verify-purchase.fra.appwrite.run/notifications`; `APPLE_ENVIRONMENT=Production` since 2026-10-16,
  falling back to Sandbox; secret vars can only be updated with `secret: true`; Apple's App Store Server
  Notifications go to `https://cjw-api.fra.appwrite.run/purchase/notifications` since 2026-10-17 (`api` has
  execute `any`; a Sandbox TEST arrived `via api`), docs/functions.md "Apple's notifications"; both functions share the purchase and notification code and the server-only
  `apple_notifications` table, so each notification applies once), `delete-account`, `redeem-code`,
  `coop-game` (frozen) and `send-gift` (kept equal to api's gift code, limits included). `catalog-snapshot` stays
  separate (daily 03:00 UTC: catalogue file in bucket `catalog`, pointer row `meta/catalog`; see
  `docs/catalog-sync.md`; pack rows keep `$createdAt` for the New badge). `coop-cleanup` was deleted 2026-10-17. Deploy functions with the Appwrite CLI (`appwrite functions create-deployment --code functions/<name>`). There is no image proxy: pictures load straight from Storage on every platform.
- Site `card-jigsaw-world` (named Carden) → https://play.carden.page (proxy rule; web platform `carden-play`
  allows the origin), and the earlier addresses https://carden.appwrite.network and
  https://card-jigsaw-world.appwrite.network still serve it (static, fallback index.html),
  deployed by `tools/dev/deploy-web.sh` (chunked upload). `web/index.html` shows an invite card on iPhone/iPad
  for `/join/` (Open in Carden via carden.appwrite.network, or Play in the browser, which only then loads the
  game); og:image is `web/invite-card.jpg` (1200x630, `tools/brand/invite_card.py`). Web build hides purchases, gift codes,
  widgets. Apple sign-in on web (configured 2026-10-13): Services ID `com.matejbaco.cardjigsawworld.signin`,
  key `secrets/AuthKey_2QJPJFW8JW.p8`, team `C24QP73SQM`. **Web OAuth must use the token flow** (owner
  rule): full-page redirect to `/account/tokens/oauth2/apple` (the `createOAuth2Token` endpoint), then
  `account.createSession(userId, secret)` on `/auth/callback`, which stores the third-party-cookie
  fallback. Never `createOAuth2Session` (guarded by `test/web_oauth_flow_test.dart`).
- Player photos (My Puzzles, bucket `user-uploads`) are private: each file is `read(user:<owner>)` only, and
  the app fetches them through the signed-in client (`lib/core/image_files.dart`), never as a public URL.
  `test/private_uploads_test.dart` fails if an upload grants `Role.any()`.
- Auth: anonymous guests, email, native Sign in with Apple (`createIdTokenSession`, nonce flow; falls
  back to the existing account on 409). Google/Facebook intentionally removed.
- Appwrite MCP: pass `project_id` as the top-level call parameter, not inside `arguments`.

## App Store / TestFlight

- Bundle `com.matejbaco.cardjigsawworld` (widget `.DailyWidget`), team `C24QP73SQM`, app id
  `6821644423`, primary locale en-GB, iPhone only. Current cycle: version **2.0.0** (owner, 2026-10-16), the first
  App Store release; pubspec and the App Store version record say 2.0.0, and its first build gets a full Beta
  App Review again (1.7.0: build 103 passed it, later builds 108-120 were approved within minutes). Later builds
  of a version still get a beta review submission (the workflow files it), usually approved within minutes. Apple may still hold any build
  for a real review, most often one that adds a permission prompt or entitlement.
- Groups: "Internal testers" (all builds instantly), "Public testers"
  (https://testflight.apple.com/join/7nPCfg6A).
- Subscriptions: vip_monthly 6821645754 ($2.99), vip_yearly 6821646642 ($14.99), both 1-week trial;
  eight consumables (see `lib/data/purchases.dart`). Gift offer codes exist ("VIP Monthly gift", "VIP Yearly
  gift"); single-use codes can only be minted after the app is live (`tools/store/offer_codes.py`).
- `tools/store/asc_publish.py`: `audit`, `status`, `feedback [--resolve IDS --note TEXT]`,
  `testflight`, `release`, `submit`, metadata/screenshots/iap/subscriptions commands,
  `events --window N --primary N` (In-App Event drafts from `store/metadata/app_events.json`, made by
  `tools/store/make_app_events.py`: the next 10 events plus the next 5 major holidays, `"primary": true`; each
  publishes 3 days before it starts, the day the app lists its pack; never submits; Apple allows 15 approved /
  10 published), `platforms` (Mac and Vision Pro: TestFlight on;
  App Store availability is two manual ticks in Pricing and Availability). Win-back offers are recorded in
  `store/metadata/subscriptions/vip_*.json`; `subscriptions` creates them once Apple approves the plans. Docs:
  `tools/store/README.md`, `docs/release-flow.md`, `docs/release-checklist.md`.
- Project auth (2026-10-17): only email-password, anonymous, JWT and Apple are on; magic URL, email OTP, phone,
  invites and GraphQL are off (`docs/functions.md` "Project settings").
- The release workflow checks the archive's dSYMs (a warning if one is missing) and keeps them as a 90-day artifact
  (merged 2026-10-17).
- Not yet done (owner): an In-App Purchase key for the App Store Server API in Production (the App Store Connect key
  works in Sandbox only; `tools/dev/apple_notifications.py`), refreshing the local
  team profile in Xcode before the next `tools/dev/device.sh` (it lacks Push Notifications and Associated
  Domains), App Store submission (Paid Apps agreement, banking and tax active since 2026-10-14; the review draft
  holds 2.0.0 with build 128 and today's review notes (2026-10-18), the 8 products, both VIP plans and 15 In-App
  Events; after launch the Get Carden link moves from TestFlight to the App Store in `lib/core/links.dart`,
  `web/index.html`, `functions/api/src/invite/page.js` and the homepage's `src/config.ts`), restoring
  `secrets/appwrite-storage-key.txt` (the content tool falls back to the users key). The App Privacy answers
  (analytics, push token) were submitted by the owner on 2026-10-17; App Store availability on Apple silicon Macs
  and Apple Vision Pro was ticked by the owner on 2026-10-18; CI runs the `api` and `verify-purchase`
  function tests (`.github/workflows/ci.yml`).
- App Review screenshots for products are per product in `store/metadata/subscriptions/consumables.json`
  (`store/review/iap-review.png` top of the store; `iap-review-boosters.png` from `raw/35_store_boosters_light` via
  `tools/store/make_promo.py`); products sit in the review draft, so take them out and back in to upload
  (apple-release skill).
- **Changing what a purchase gives** (coins, tickets, hints, Peeks, Magic per product): three places must agree
  (`GRANTS` lives in both `functions/api/src/purchase.js` and `functions/verify-purchase/src/main.js`, kept equal by
  `test/economy_test.dart`; redeploy both): the server grant (then redeploy as in
  `docs/purchases.md`), `lib/data/purchases.dart` (what the store screen shows) and
  `store/metadata/subscriptions/consumables.json` (App Store names and descriptions, pushed with
  `asc_publish.py iap`). Product ids such as `coins_1000` cannot be renamed on Apple; keep them.
- **Pack prices** live in the `packs` rows (`priceCoins`, `priceTickets`, `isFree`). The policy and the
  earnings model behind it are in `docs/economy.md`; `tools/store/apply_pack_prices.py` applies it
  (dry run by default, `--apply` writes). The content tool creates new packs at 400 coins or 3 tickets
  and never touches existing prices, so re-run the script after every content session. Only six starter
  library packs are free (`STARTER_PACKS` in that script; owner, 2026-10-14); the script prices any other
  free library pack, and `lib/state/starter_packs.dart` keeps the 45 packs that were free until then open
  for players who had played them.

## Secrets

`secrets/` is git-ignored (only `app-store-connect-issuer-id.txt` is tracked): App Store Connect key
`AuthKey_9QC72A5QMN.p8`, Sign in with Apple key `AuthKey_2QJPJFW8JW.p8` (web browser sign-in, stored in
Appwrite's Apple provider), distribution `Certificates.p12` + password, Appwrite keys
(`appwrite-api-key.txt` rows/tables scopes, `appwrite-storage-key.txt` files/rows scopes for picture
hosting, `appwrite-sites-key.txt`, `appwrite-users-key.txt` users/rows/files scopes for the QA player
purge and stats backfills), `content-keys.env` (`PIXABAY_API_KEY`; the Openverse client id and secret
belong there too but are missing on this Mac, so Openverse runs anonymously at 190 requests a day). Never print or commit their
values. GitHub Actions has the signing secrets.

## Work that may be running in parallel

A picture-catalogue repair may be running in another session (Opus workers under the pack-making
skill, state in `tools/content/reports/state.json`, checkpoints pushed every 30 minutes). If it is:
do not edit `tools/content/**`, the pack-making skill or content docs, do not stop those agents, and
leave these five TestFlight feedback items open (they are the content work's):
AAX-tfwxcKgwk8WC7ZmPEIM, AFs4NDzzaDynNOI55qyTIkM, ANO-zfTaIYOjY-ueQhFp1QM, AEkB37H2zKX9inL57pfg2gE,
AOZ2T5f4FZgO6tNrSO3BovQ (picture quality). Every other open item, including pack prices and the
economy model, is app work.
Their checkpoints commit only their own paths. Content files change every few seconds while it runs,
so integrate remote commits with `git fetch origin main && git merge --no-edit origin/main`; never
`git pull --rebase`, `--autostash` or `git stash` (an autostash once hid the workers' changes), and
never `git checkout`/`restore` files under `tools/content`. `tools/dev/testflight.sh` refuses a dirty
tree, so dispatch the workflow directly as described in the testflight-feedback skill.

## Docs index

`docs/native-ui.md` (glass components), `docs/accessibility.md`, `docs/first-steps.md` (guided start), `docs/copy-guide.md`, `docs/sync.md` (save sync), `docs/catalog-sync.md`, `docs/deep-links.md`, `docs/house-ads.md`,
`docs/purchases.md`, `docs/web.md`, `docs/app-updates.md`, `docs/release-flow.md`, `docs/release-checklist.md`,
`docs/content-rules.md`, `docs/content-sources.md`, `docs/boards.md` (board sizes, Expand), `docs/twins.md`
(twin cards), `docs/analytics.md`, `docs/friend-gifts.md`, `docs/multiplayer.md` (Play together),
`docs/terms-of-use.md`, `docs/functions.md` (the `api` function, old functions, retirement rule, integrity
sweep), `store/README.md` (store assets),
`tools/store/README.md`, `README.md`.
