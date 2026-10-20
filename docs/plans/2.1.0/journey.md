# Journey: one tap to the next level

Status: planned for 2.1.0, not started. Picked by the owner on 2026-10-20.

## How to work on this task

- Branch: `2.1.0/journey`, which starts with this brief. Work and push only there (`git push -u origin 2.1.0/journey`). Never merge it
  into main or push to main: that is the owner's call. This overrides CLAUDE.md's "push to origin main" for this task.
- Check the branch out in its own worktree (`git worktree add <folder> 2.1.0/journey`): another session may be using the main checkout.
- No TestFlight or App Store builds, no web deploys (`tools/dev/deploy-web.sh`), no installs on the owner's iPhone. Pushing the branch
  starts no CI (`.github/workflows/ci.yml` runs on main and pull requests only).
- Changes to the live backend count as deployments: ask the owner before adding the two `profiles` columns below. QA runs use the live
  backend, so the integration suites that need those columns wait for that go; unit tests do not.
- Everything else in CLAUDE.md applies: the gates (`flutter analyze --fatal-infos --fatal-warnings`, `flutter test`), QA only through
  `tools/dev/qa-run.sh`, commits with the owner's git identity and explicit paths.

## Summary

Home's top card plays the next picture of one endless path, "Stage 38", with the picture, shape and board size already chosen, so a session starts
with one tap. Boards grow gently, a lighter stage comes now and then, and every 10th stage gives a small fixed gift. The Library stays for players who
like to choose, and the Journey keeps for good what first steps do today: one suggested picture on Home. The plan says "stage" because "level" is
already the XP level (Open decision 1).

## Why

- Jigsolitaire, the game closest to Carden's mechanic (cards join into groups and lock in place), is level-based, with a Daily Challenge, a Master
  Challenge and a Collection; reviews mention level 1,325; 4.8 stars from about 75,000 ratings; no in-app purchases, "Contains Advertising", and
  reviews ask for an ad-free option: https://apps.apple.com/us/app/id6741408932
- Its developer announced it was the No. 1 free game in the US on the App Store and Google Play on 15 December 2025:
  https://www.appbank.net/2025/12/15/game/2886555.php
- Gamigion estimates about 30 million downloads in under two months after a May 2025 soft launch, about 2.3 million daily players, and revenue almost
  all from ads between levels (third-party estimates): https://www.gamigion.com/the-new-ua-playbook-grabbing-downloads-by-combining-genres/
- Cardscapes: "each completed level reveals a picture", "no timers, no move limits, no penalties", 4.8 stars: https://apps.apple.com/app/id6756808809
- docs/research-card-jigsaw-and-image-apis.md: image repetition before level 100 to 250 is a recurring complaint, 2 to 5 minute sessions are praised,
  auto-advance and a finished picture that vanishes at once are complaints. So stages never repeat a picture while new ones are open, last 1 to 5
  minutes and never auto-advance.
- Testers found Home crowded and a chore on 2026-10-16 (docs/first-steps.md). First steps answered with one suggested picture on Home; the Journey
  keeps that shape after the start.

What weakens it:
- The owner passed on a "journey map" idea on 2026-10-13 (pre-launch, while picking small items). This plan has no map.
- Nothing is tested with Carden's own players yet (2.0.0 is in App Review); the competitor figures are store pages and third-party estimates.
- Jigsolitaire earns from ads between levels. Carden has only house ads (docs/house-ads.md), so its case is engagement, pack unlocks and VIP.
- Carden's identity is a library of packs, and a top card that chooses for the player moves the Library one step back.
- A stage deals its board at once, where Quick play was built the other way on purpose ("Quick play never starts a game by itself", `quickPlayRoute`
  in lib/state/quick_play.dart).

## What the player sees

### Home

The Journey card takes the top at the size of today's `_DailyHero` (220 pt on a phone). Under it: Continue (the board closest to done, not the
Journey's), today's picture as a compact row, the streak, then Home as now. Quick play leaves Home (Open decision 4).

| State | Card (draft copy) | Tap |
| --- | --- | --- |
| Loading | a quiet frame with a spinner, no title or button (as `_HeroPlaceholder`) | nothing |
| Catalogue failed | "Your next stage could not load" / "Check your connection and try again." / Try again | reloads |
| Empty catalogue | "Your Journey has no pictures yet." / "Pull down to load them again." | nothing |
| Guided Stage 1 | chip "Start here"; "Your first picture"; "Nine cards and no clock. A minute or two." (today's copy) | the first board |
| Next stage | the picture; chip "Stage 38" (`AppIcons.flag`); its title; "Squares · 5x5". A gift stage adds a chip "Gift" (`AppIcons.gift`) and "· Gift: 1 Hint"; the first stage in a new shape a chip "New for you" | deals the board, no picker |
| In progress | chip "Stage 38"; title; "Squares · 5x5 · 12 of 25 locked" | resumes the board |
| No new pictures | the offered pack's cover; chip "Stage 141"; "New pictures for your Journey"; "Every picture open to you is solved." | the pack sheet |
| Replay stage | chip "Stage 142 · Replay"; title; "Solved · 2 stars"; under it "New pictures: unlock a pack" | the replay; the line opens the sheet |

Today's row: thumbnail, "Today" (accent caption), title, "+50 bonus today" (`Amount`), or once solved "Solved · 3 stars" and when the next picture
comes (`NewPictureIn`).

The pack sheet (`showAppSheet`; content in `SheetScrollBody`, buttons in its footer, no close button): "Stage 141"; "Every picture open to you is
solved. Unlock a pack for new stages, or replay one you know."; the pack's cover, name and "24 pictures"; footer "Unlock for [coin] 2,400"
(`BigButton.cost`), "Choose another pack" (Library), "Replay a picture". Unlock asks with the pack page's own alert ("Unlock Foxes?" / "This costs
2,400 coins. You have 3,100." / "Pay 2,400 coins"); short of coins, the pack page's toast and the Store, as now.

### A stage and its finish

- The board is dealt like any other: the whole picture first, then the deal (Reduce motion cross-fades). Pause works as now; on a stage, the "Discard
  and pick a board" alert adds "Stage 38 counts on a 5x5 or bigger board."
- Finish card (`_CompletionOverlay`): "Stage 38 complete" instead of "Picture complete"; title, stats and the pack line ("3 of 24 solved · Wild
  Nature") as now; a gift stage adds a tinted line "Gift: 1 Hint" (gift icon), other stages "Next gift at stage 40"; level-up and quest lines as now.
  Buttons: Replay and Next stage, then Home. The picture stays until the player taps. Next stage with no new picture opens the pack sheet.

### First steps

- Stage 1 of a guided player is the first board (Pink Sands Beach, Cards 3x3, `firstBoardProvider`), opened by the welcome pages as now; its finish
  offers Next stage and Home.
- The Journey card replaces `NextStepCard` (hero and small card): the guided Home shows the next stage, Continue, then "More opens as you play"
  blurred, as now. The Journey is never locked. "Try Squares" becomes the first Squares stage with "New for you"; nothing is announced (owner rule).
- What opens still counts pictures (`countedFinishesProvider`), not stages: stages played from the first board's finish before Home count as one
  picture (the 2026-10-16 rule, unchanged).
- Store > Earn for free > Play a puzzle (`playFromStore`) opens the next stage.

### Free, VIP, web, offline

- Free: the six starter packs (about 140 pictures, docs/economy.md), bought packs and kept formerly free packs (`keptFreePack`). VIP: every library
  pack. The same gifts for both. When VIP ends, a stage in a pack no longer open is dropped; a board in progress stays under Continue solving.
- Web: the same flows; wide windows put the Journey card where today's picture is now, with Continue, today's row and the streak beside it. Coins and
  tickets unlock packs; VIP shows the existing `purchasesOnIphoneMessage`.
- Offline: picks come from the synced catalogue and progress, and the pick and the finish are queued ops. A picture that cannot load shows the game's
  own "Picture did not load".

## Rules and edge cases

**A stage.** Stage N is the player's Nth Journey finish: `profiles.journeyDone` counts them, the next stage is `journeyDone + 1`. When a stage opens
(the card, Next stage, `/journey`, Store's Play a puzzle, the first board being dealt) its pick is pinned on the profile (`journeyNext`: stage,
picture, board, Painting, replay, time), so every device shows the same stage and a catalogue change cannot swap a started picture. A pin holds while
its stage is `journeyDone + 1`, its picture is in the catalogue and its pack is open. A finish of the pinned picture after the pin counts when the
board is at least the stage's size (side squared, `BoardSpec.sizeCells`, as size quests count; any shape); a smaller board is a normal finish and
drops the pin.

**Which picture** (Option (a) of Open decision 2):
1. Pool: library packs open to the player (`ProfileNotifier.isUnlocked`), without Daily months, event packs (`hasWindow`), hidden packs, Giant packs
   (`isGiantPack`) and My Puzzles. Candidates: no finish, no board in progress.
2. Stages 2 to 10 of a guided player: a fixed opening of nine starter pictures with clear, different cards, picked the way the first board was (Open
   decision 10).
3. Otherwise packs take turns in catalogue order (`sortOrder`, then id, as `packRowsProvider` sorts): the first pack after the last pin's pack that
   has a candidate, pictures in the pack's order. Same inputs, same pick on every device.
4. No candidate: the "No new pictures" state, offering the first locked library pack in catalogue order the player can pay for now (else the first
   locked one). An unlock from the sheet pins the next stage in that pack. "Replay a picture" pins a replay (short of 3 stars first, then any: Quick
   play's improve and any tiers); while nothing new is open, each stage after a replay is a replay.

**Which board.** Square boards, no Expand; the player's own `LastBoard` is never changed.

| Stages | Usual size |
| --- | --- |
| 1 to 3 | 3x3 |
| 4 to 20 | 4x4, or the player's usual size when bigger (`PlayHabits.cells`, at most 6x6) |
| 21 on | 5x5, or the player's usual size when bigger (at most 6x6) |

| Place in each ten | Board |
| --- | --- |
| 1, 2, 5, 6, 9 | the player's shape (`PlayHabits.mode`, Cards for a new player), usual size |
| 3, 7 | the next other open shape in turn (the player's own when none), usual size |
| 4 | one size smaller: the lighter stage |
| 8 | one size bigger |
| 10 | usual size, Painting once open; the gift |

Every 50th stage is one size bigger, with the bigger gift. Triangles go one size smaller (about 2N² pieces, docs/boards.md); Hexagons have no 3x3
(`BoardSpec.nearest` gives the 4x4 honeycomb). Never beyond what the player can play: `LevelRewards.maxTierIndex(level)` or a bought size
(`ProfileNotifier.hasTier`), shapes in `OpenFeatures.modes`, Painting only with `OpenFeatures.painting`, no giant boards (Open decision 8).

**Gifts** (Open decision 5): fixed, never random, the same for everyone; worth from docs/economy.md section 4.

| Stage, in each run of 50 | Gift | Worth |
| --- | --- | --- |
| 10th and 30th (10, 30, 60, 80, ...) | 1 Hint | 150 coins |
| 20th and 40th (20, 40, 70, 90, ...) | 3 Peeks | 30 coins |
| 50th (50, 100, ...) | 300 coins and 1 Magic | 600 coins |

- Per 50 stages: 300 coins, 2 Hints, 6 Peeks, 1 Magic, about 960 coins of value. No tickets: they stay a login currency, the same for everyone
  whatever they play (docs/economy.md section 4).
- The model's regular player (5x5, 115 s a board, about 219 boards a week, `test/economy_test.dart`): with every board a stage, +1,300 coins a week,
  from about 2,530 to 2,710 coins an hour (+7%); casual and heavy players move about as much. Inside the test's 10% band, so pack prices stay.
- Paid once, with the finish: the stage op is built against the fresh profile row and skipped when `journeyDone` is already at or past the stage; the
  stage reached is the row's count plus one and its gift comes from the same table (`JourneyGifts`), as `_solve` pays level rewards from the server's
  XP. `appliedOps` stops a lost answer from applying twice. Ledger lines `journey:<stage>` for coins and Hints (Peeks and Magic leave none, as
  elsewhere).

**What counts.** Apart from `journeyDone` and the gift, a stage's finish is an ordinary finish written once by the usual `win` and `solve` ops: quests
(`progress.finishes`), achievements (`AchievementFacts`), pack progress, `PlayHabits`, first-steps counts, Total Completion, the piggy bank and the
review prompt see it as today. The stage op is no quest: it leaves `claimedGoals` and `questsCompleted` alone (`questClaims` reads only `goal:`
lines). Replay on the finish card is not a stage. The Journey's changes of shape and size will sometimes finish a daily quest (see Risks).

**Resume.** A stage's board saves like any board, and finishing it anywhere (Continue solving, the pack page, an older build) counts: on start and
resume `JourneyNotifier.selfHeal` treats a finish of the pinned picture after the pin, on a big enough board or without recorded values
(`BoardFinish.known` false), as the stage; the guard keeps it to once.

**Play together.** Allowed on a stage, as on any public pack's board (`canPlayTogether`). Only the host's Journey moves; guests get the co-op reward
only (`recordCoopReward`, docs/multiplayer.md). The host's Next stage hands the next stage to the game (`coop.nextBoard(puzzleId:, grid:, layout:)`),
possibly in another shape and size (unverified that guests follow a change of shape: test it).

**Break offers** (Open decision 6). Next stage calls `maybeShowInterstitial` as Next puzzle does (`HouseAdPolicy`, none for VIP, held until
`Reveal.promos`), except right after a gift stage: that finish counts toward the cadence and no card shows. With 2-minute stages the 3-minute rule
shows a break about every other stage, as Next puzzle does today.

**Two devices, older builds, merges.** Two devices on one stage: the first finish to reach the server counts, the other is a normal finish without the
gift, and "Synced from another device" says "A Journey stage finished on both devices, counted once"; another device's stages show as "Journey: stage
42". Older builds ignore both columns and never write them; they can finish a stage's board as an ordinary one, and `selfHeal` counts it on the next
2.1.0 start. `/journey` on an older build is no link (`AppLink.parse` returns null), so `onException` lands on Home (traced in code, unverified on a
device). A sign-in merge (`mergeProfile`): both columns follow the chosen save, as coins and XP do.

## Data and backend

| Column | Type | Default | Holds |
| --- | --- | --- | --- |
| `profiles.journeyDone` | integer 0 to 1,000,000, optional | 0 | stages finished |
| `profiles.journeyNext` | string 400, optional | none | the pinned next stage, JSON `{stage, puzzle, board, painting, replay, at}` |

- Server before build: add both with the Appwrite CLI (as `profiles.piggyLevel` was) before the first TestFlight build or web deploy that writes them;
  a write naming an unknown column is refused (the reason `writeWithoutUnknown` exists in lib/data/repositories.dart; it covers progress only). Do
  not wrap the stage op in it: a gift written without its count could be paid twice.
- Ops (lib/data/sync/ops.dart): `journeyPick` (puts `journeyNext` unless `journeyDone` already reached the stage) and `journeyStage` (guarded as
  above), both `needsFresh`, plus `SkipReason.journeyDone`. Never rename a stored kind.
- No new table, function, index or permission, no `api` deploy. Profiles keep `read(any) update(user) delete(user)`: the columns are public like
  `level` and hold nothing personal; the trust model is that of quests and level rewards.
- Integrity sweep: no change (it checks ownership, ids and names, not profile values). Account deletion (`/account/delete` on `api`) and
  `tools/dev/purge_test_players.py` remove the whole profile row: no change.
- No new reads (the Journey works from `catalogProvider`, `progressProvider` and the profile; `test/pagination_test.dart`) and nothing new in
  SharedPreferences.

## App changes

- `lib/state/journey.dart` (new): `JourneyPick` (JSON), `JourneyOrder` (pool, opening, turns, replays, offered pack), `JourneyCurve`, `JourneyGifts`;
  providers `journeyProvider` (the card's state, rebuilt only when catalogue, progress or profile change: 8k+ pictures) and
  `journeyStageOfProvider(puzzleId)`; `JourneyNotifier` (`open`, `finish`, `selfHeal`).
- `lib/models/models.dart`: `Profile.journeyDone`, `Profile.journeyNext` (`fromRow`, `toData`, `copyWith`).
- `lib/data/sync/ops.dart`: the ops and skip reason; `lib/data/sync/notice.dart` and `lib/features/sync/sync_host.dart`: the notice field, its line
  and `skipText`.
- `lib/state/profile.dart`: `pickJourneyStage`, `finishJourneyStage` (returns the gift). `lib/state/merge.dart`: the columns follow the chosen save.
- `lib/features/home/journey_card.dart` (new): `JourneyCard` (hero, compact) and `JourneyPackSheet`.
- `lib/features/home/home_screen.dart`: the card on top in both layouts, today's picture as a row, `_QuickPlayCard` off Home, `_ResumeCard` without
  the Journey's board.
- `lib/features/home/guided_start.dart`, `lib/state/first_steps.dart`: `NextStepCard` and `nextStepProvider` leave Home; `firstBoardProvider`,
  `Reveal` and `countedFinishesProvider` stay. Keep `Reveal.quickPlay` (its name is stored in `firstSteps.early`); it stops gating Home.
- `lib/features/game/game_screen.dart`: pin the first board as Stage 1; `_onWin` sends the stage op for the pinned picture; `_CompletionOverlay` gets
  the stage, gift and Next stage; `onNext` picks the next stage (or the sheet) and, for a host, hands it to the game; the Discard alert's sentence;
  `_boardProps()` adds `journey`.
- `lib/features/ads/house_ads.dart`: `maybeShowInterstitial(..., hold: true)` after a gift stage.
- `lib/features/gallery/pack_screen.dart`: move `unlock()` (ask, pay, toast, Store when short) into a shared `unlockPackFlow` for the sheet.
- `lib/core/app_links.dart` (`/journey`, an action), `lib/features/links/deep_links.dart` (Home beneath, then the board or the sheet),
  `web/.well-known/apple-app-site-association` (`/journey`).
- `lib/features/store/store_screen.dart`: `playFromStore` opens the next stage; with Quick play folded in, `/quick` too. `lib/state/quick_play.dart`
  and Another picture stay for old `?from=quick` links.

## Apple, privacy and review

- No new capability, entitlement, Info.plist key, permission prompt or product. Universal links need only the association file, deployed with the site
  (`tools/dev/deploy-web.sh`; Apple's CDN can take a day).
- App Store Connect: a 2.1.0 version once 2.0.0 is released (an approved version takes no more builds), full review.
  `store/metadata/en-US/release_notes.txt` draft: "The Journey: one tap plays your next picture, on a board chosen for you, with a gift every 10
  stages. The Library is still there when you like to choose."
- `store/metadata/en-US/review_notes.txt` draft: "New in 2.1.0: the Journey. Home's top card plays the next picture on a board chosen for the player,
  and every 10th stage gives a fixed gift (a Hint, Peeks, or coins and Magic). Nothing is random or sold; no permissions, purchases or data types are
  new." Fixed gifts need no odds (guideline 3.1.1 covers random items for sale).
- docs/privacy-policy.md: "Journey stage" in the Profile row of the data table, "a Journey stage finished" in the usage data row. App Privacy answers:
  no change (Gameplay Content and Product Interaction cover both).
- Analytics (no change to lib/core/analytics.dart; rows in docs/analytics.md; no ids but catalogue ids):

| Event | Props | When |
| --- | --- | --- |
| `journey_opened` | `from` (`home`, `link`, `store`, `finish`), `stage`, `state` (`new`, `resume`, `replay`, `pack_offer`) | the card, `/journey`, Play a puzzle, Next stage |
| `journey_stage_completed` | `stage`, `mode`, `board`, `cards`, `painting`, `stars`, `replay`, `gift` | the stage op is queued |
| `journey_gift_received` | `stage`, `coins`, `hints`, `peeks`, `magics` (zeros left out) | a gift stage |
| `journey_pack_offer_shown` | `stage`, `pack`, `currency`, `price` | the pack sheet opens |
| `journey_replay_chosen` | `stage` | Replay a picture |
| existing events | `journey` (stage, else 0) on `puzzle_started`, `puzzle_completed`, `puzzle_restarted`, `puzzle_discarded`; `from` (`pack`, `journey`) on `pack_unlocked`; `to: journey` on `link_opened` | as now |

## Accessibility

- Reduce motion: nothing new moves; the deal, stars and confetti follow `A11y.reduceMotionOf` as now; no extra confetti.
- Increase contrast: the hero's scrim is `Brand.scrim(contrast: A11y.increaseContrastOf(context))` like `_DailyHero`; colours only from
  `context.colors` and `context.accent`.
- Differentiate without colour: every state has words ("Continue", "Replay", "Gift", "12 of 25 locked").
- Text size: at Large and Largest the hero grows with the text (as `_QuickTile` scales), the title stays one line, the board line wraps, the sheet
  scrolls; no layout errors on the SE frame (design QA harness, scene pref `accessibility`).
- VoiceOver: the card is one button, "Stage 38, Harbour at dawn, Squares 5x5, gift at this stage", hint "Plays the next stage"; in progress "Stage 38,
  continue, 12 of 25 cards locked"; the gift line is read with the results.
- Haptics: `Haptics.light` on the card; a gift stage ends the finish card on the success touch, as a finished pack does.

## QA

Unit tests:
- `test/journey_test.dart` (new): pool and exclusions (formerly free packs only when kept, VIP), opening, turns, same inputs same pick, pin validity
  (stage, picture gone, pack closed, smaller finish), replays and the offered pack, each row of the curve with its caps (level, bought sizes, shapes,
  Painting, Triangles, Hexagons 3x3, the 50th), gifts (no tickets), "a 5x5 or bigger board".
- `test/sync_test.dart`: two devices on one stage (one count, one gift, the notice line), a lost answer, offline stages in order, a stale pick.
  `test/merge_test.dart`: the columns follow the chosen save.
- `test/economy_test.dart`: the gifts in `_regularPlayerSteadyState()` (and the model in docs/economy.md); `REGULAR_COINS_PER_HOUR` stays inside its
  band.
- Updated: `test/first_steps_test.dart` (Stage 1 is the first board; stages are not pictures counted), `test/guided_home_layout_test.dart` and
  `test/home_phone_layout_test.dart` (every card state at SE, Pro and web sizes, both themes, 100% and 200% text), `test/hint_lines_test.dart`,
  `test/house_ads_test.dart` (no break after a gift), `test/coop_guest_rewards_test.dart` (a guest's Journey never moves), `test/deep_links_test.dart`
  (`_links`, the association file), `test/quick_play_test.dart` (if folded in).

Integration, each as `tools/dev/qa-run.sh drive --driver=test_driver/integration_test.dart --target=<suite> -d CDD7317C-19D6-486D-B258-8AB8A607297D`
(a muted QA guest, purged afterwards):
- `integration_test/journey_test.dart` (new; `FirstSteps.skipFor`, cards through `GameState.cardKeys`): Stage 1 from Home, "Stage 1 complete", Next
  stage, leave mid-way, Home in progress, Continue, finish; a seeded jump to Stage 9 (the test puts `journeyDone`), then Stage 10 with its gift line and stock, and no break after
  it; `xcrun simctl openurl booted 'carden://journey'`; a provider override with one small pool, then the pack sheet, Unlock and a stage in that pack;
  Replay a picture.
- `integration_test/first_steps_test.dart`: welcome, first board (Stage 1), Next stage, Home with the next stage on top and "More opens as you play"
  under it (`fs_*`).
- `deal_next_test.dart` (the picture before the deal after Next stage), `sync_devices_test.dart` (the laptop finishes a stage, the iPhone moves on;
  both on one stage count once), `coop_host_test.dart` with `node tools/dev/coop_bot.mjs &` (the host's Next stage reaches the guest),
  `deep_links_test.dart` (`/journey`).
- Web: `tools/dev/qa-run.sh run -d web-server --web-port 8137` with a headless browser: phone and wide layouts, a stage, the pack sheet.

Screenshots to look at (`screenshots/journey_*.png`): Home at Stage 1 for a new player and at a later stage for a player from before; the guided Home
after the first board; a stage in progress on Home; "Stage 1 complete" and the Stage 10 finish with its gift; the pack sheet with and without enough
coins; a replay stage; Largest text on the SE frame; VoiceOver labels (a semantics dump); the web wide layout.

## Docs to update

`docs/journey.md` (new, the feature as built), docs/first-steps.md, docs/economy.md (gifts, model), docs/sync.md (columns, ops), docs/house-ads.md,
docs/analytics.md, docs/deep-links.md, docs/copy-guide.md (Journey, stage, "Next stage"), docs/boards.md (pointer to the curve), docs/multiplayer.md,
docs/privacy-policy.md, CLAUDE.md (code map, Home's top card), README.md (feature table), and the store copy above (apple-release skill).

## Open decisions for the owner

1. **The word.** (a) "Stage 38" (recommended: "Level 12" is already the XP level on Home's level card, the finish card and the league); (b) "Level
   38", renaming the XP level everywhere (older builds keep "Level"); (c) both "Level".
2. **Which pictures.** (a) free and owned packs, then a pack to unlock or replays (recommended: gives nothing away, the model holds); (b) a tour of 1
   or 2 pictures from each locked pack. Against (b) in the code: `keptFreePack` opens a whole formerly free pack (45 of them) for good after any
   progress row, on 2.0.0 too, so a tour must skip those; "Packs in progress" lists only open packs (`homePackRows`), so a toured pack shows as
   started only in the Library's Started filter; a locked pack page keeps the toured picture locked.
3. **Home's top.** (a) the Journey card, today's picture as a row under it (recommended); (b) today's picture until it is solved, then the Journey;
   (c) today's picture on top, the Journey under it.
4. **Quick play.** (a) fold it in: off Home, `/quick` and Play a puzzle open the next stage (recommended: one way to play now); (b) keep its card
   under the Journey; (c) move it to the Library.
5. **Gifts.** (a) the table above, no tickets (recommended, at most about +7% coins); (b) coins only, 100 every 10th and 500 every 50th (+15 to 22%);
   (c) (a) plus 1 ticket every 50th (+4 to 8 tickets a week, growing with play time).
6. **Break offers.** (a) as Next puzzle, none right after a gift stage (recommended); (b) only every 3rd stage; (c) none.
7. **Players from before 2.1.0.** (a) Stage 1 for everyone, the usual size following theirs from stage 4 (recommended); (b) the plain curve; (c) start
   the count at the pictures already solved (no back gifts).
8. **Giant boards and live events.** (a) neither in 2.1.0 (recommended); (b) a Giant stage every 50th for owners of a Giant pack; (c) a live event
   picture now and then.
9. **A switch.** (a) none (recommended: the Library is one tab away); (b) Settings > Gameplay > "Journey on Home".
10. **The opening.** (a) nine hand-picked starter pictures for stages 2 to 10 (recommended); (b) plain turns.
11. **Changing a stage.** (a) the board may change and counts at the stage's size or bigger, no picture swap (recommended); (b) also "Another
    picture"; (c) any board counts (3x3 boards would bring gifts about three times as fast).

## Effort and risks

Effort (estimate, unverified, agent days): state, ops and unit tests 2; Home card, finish card and sheet 2; first steps, Store, links, Quick play 1;
integration suites, screenshots and web 2; docs 0.5. About 8 days, then a TestFlight round.

Risks:
- Home is the most seen screen: every first-steps test and layout (SE at 200%) must pass again.
- Three counts sit close: stages, the XP level and first steps' pictures. The copy must keep them apart.
- Economy: at most about +7% coins and more boosters in stock; booster bundle sales may dip.
- Quests: the Journey's changes of shape and size finish some shape and size quests in ordinary play. Earnings stay (the model counts all daily
  quests done), but the 2026-10-15 rule that ordinary play finishes only "Solve 3 puzzles" gets weaker.
- The catalogue changes while content repair runs: pins keep started stages steady; QA on a fixed pool.
- A heavy free player reaches the pack offer within a few hours (about 140 starter pictures), with the coins for a pack by then (docs/economy.md
  section 6).
- A new version gets a full App Review; nothing in it needs a new permission.
- The owner passed on a journey map before, and testers may prefer today's picture on top: a TestFlight feedback round before submitting.

## Not in this task (follow-ups)

- A Journey map or path screen.
- The widget, the "One last game?" quick action (`_setUpQuickActions` in lib/app.dart, today's puzzle now) and daily reminders opening `/journey`
  (the reminder picture is its own task, on branch `2.1.0/reminder-picture`).
- A "Journey stage" leaderboard in Game Center, once both ship (Game Center is its own task, on branch `2.1.0/game-center`).
- Giant, live event and daily stages; the Library tour (Open decision 2b) as a later test, measured with `journey_pack_offer_shown` and
  `pack_unlocked`.
- Journey achievements (Stage 100, 500), a stage on player pages or in the league.
- Gift amounts from the server (in the app they need a build, as level rewards do); "Another picture" for a stage.
- App Store screenshots and the homepage showing the Journey (store-screenshots skill).
