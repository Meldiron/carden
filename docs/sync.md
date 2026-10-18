# Save sync

Players use the same save on several devices (the iPhone app and the web site on a laptop, say),
sometimes without a connection. This is how the save stays correct (since 2026-10-13).

## Rules

1. **Send changes, not totals.** Every change to the save is a `SyncOp` (`lib/data/sync/ops.dart`):
   an intent such as "earn 300 coins", "claim quest X", "unlock pack Y for 400 coins", "save this
   board". When it is sent, the op becomes column changes against the row as the server has it:
   Appwrite's atomic operators (`increment`, `decrement` with a floor of 0, `arrayAppend`, …) for
   the profile, so two devices add up instead of overwriting each other.
2. **Queue what cannot be sent.** Ops are stored on the device (`sync.v1.<userId>.ops` in
   SharedPreferences / localStorage) and sent in order by `SyncController` (`lib/state/sync.dart`)
   as soon as the server answers: right away, on a retry timer (2 s to 60 s) while the app is in
   front, on resume and on the next start. The screens show the save with the queued ops applied.
   A device that starts offline keeps playing as the player it last saw (`AuthNotifier` remembers
   it); a device that never reached the server plays as `local`, and its first guest takes that
   play over.
3. **Reload on start, resume, tab focus and sign-in.** The rows are read again (progress
   incrementally from the newest `$updatedAt`). Whatever another device changed is shown once in
   the "Synced from another device" alert (`SyncHost`, never during a game). A purchase on this
   device and a sign-in merge are taken in silently, and so is this device's own play that the copy
   on the device missed (see "The first read after a start").
4. **Records only improve.** A win keeps the better stars, best moves and best time of the
   server's row and this play; a solved picture stays solved (board saves never touch
   `completed`, and a finish time counts as solved for rows older versions un-solved during a
   replay). Lifetime totals per picture are kept per play-through (`progress.session`), so sending
   the same save twice changes nothing.
5. **Something done twice counts once.** Guarded ops check the fresh row before they are sent: a
   quest, achievement, VIP bonus or daily gift already claimed elsewhere pays nothing; a pack, board
   size or avatar already unlocked elsewhere charges nothing; a piggy bank opened elsewhere pays
   only what is left. Level rewards follow the server's XP, so a level reached on two devices pays
   once; a first solve that turns out to be the second device's pays as a replay.
6. **Coins spent twice are not created.** When the other device spent the balance first, an unlock,
   streak restore or piggy bank opening made here is undone (it is not given away), and a Hint,
   Peek or Magic already used here charges what is left (never below zero). The alert says what
   was not done twice or was undone.
7. **The player picks when the game cannot.** Two different boards in progress for one picture
   (one of them unsent) ask "Two boards in progress" (`BoardChoiceSheet`). An open game whose
   board was continued on another device reloads it with a short "Board updated" alert; a
   different board there asks the same question. A board finished on another device stays
   finished (since 2026-10-15, after a tester's solved giant board came back from a laptop tab left
   open on it): a board save of a play-through the row shows as won (same `session`, no layout,
   solved) changes nothing, a board save after 30 seconds without reading or writing that row
   reads the save first, and an open game of that play-through closes with "Solved on another
   device" and saves nothing more. A new play-through (replay, restart) has its own session and
   saves as usual. Signing in from a guest to an existing account
   asks "Two saves found" when neither save clearly wins, and also when the save that would be
   dropped holds more Coins, Tickets or Hints (`decide` in `lib/state/merge.dart`).

## A row another player made first

Progress and event rows have predictable ids (md5 of player and picture or event), so another player
can create a row at that id before this player does (security review, 2026-10-17). Appwrite then
refuses this player's write with 401 while the session is fine. A 401 on a progress, event or ledger
write is checked against the session (`SyncBackend.signedIn`, `account.get`): when it holds, the op is
**parked** (`_Account.parked`, in memory): it stays queued, so the screens still show it and nothing
is lost, but the queue goes on without it and nothing is said to the player. It is sent again on the
next start, or on a resume an hour later (`SyncController.parkedFor`); the server's hourly sweep
deletes the other player's row meanwhile (docs/functions.md, "Integrity sweep"), so it lands then. A
401 without a session is still about the sign-in (the queue waits and the app signs in again). Friend
and block rows go under a unique id when their predictable one is taken (`SocialRepository._ownRow`)
and are found by their columns when removed.

## The first read after a start

The first read of a run compares the server with the copy of the save stored on the device
(`sync.v1.<userId>.rows`), and that copy can lack this device's own last writes. It did on iPhones
up to build 127: the catalogue (5.6 MB) was kept in SharedPreferences, over the 4 MB iOS allows for
an app's preferences ("Attempting to store >= 4194304 bytes of data in CFPreferences/NSUserDefaults
on this platform is invalid"), and iOS then stored none of the app's later writes. A fresh guest
finished the first board, the next start found the save from before it, and the alert said
"Synced from another device: +17 coins, 1 picture solved" (TestFlight feedback, 2026-10-18; from
the next build the catalogue is a file, docs/catalog-sync.md). The welcome pages coming back after Skip had
the same cause (`onboarded` was never stored).

Since then the copy of the rows is a file on the iPhone (next section), and that first read tells
only what another device or the server did (`SyncSource` in
`lib/data/sync/notice.dart`, `SyncController._fetch`):

- Profile: the op ids that arrived in `appliedOps` since the stored copy name their device (the
  first four characters). Only this device's ids: its own play, nothing to tell. Another device's
  ids: the differences are told as before. No ids at all but different values: a change the server
  made (a purchase added by `api`), told as before.
- Progress: a changed row of a play-through this device started (its `session` begins with the
  device's name) is not told either, unless another device's ids arrived too (it may have finished
  one of them). The rows themselves are always taken, and an open game still follows its board.

Later reads in the same run compare with rows this device read or wrote itself and are unchanged.
For this to work a device keeps its newest 10 op ids on the profile row when it tidies them
(`SyncController.keepOwnIds`, below).

## The copy on the device

Two things per player: the queue of unsent ops (`sync.v1.<userId>.ops`, SharedPreferences) and the
copy of the rows (`{profile, progress, cursor, synced}`, `SyncRows` in
`lib/data/sync/device_copy.dart`). The copy grows with every picture (about 0.8 KB a row in October
2026, the heaviest player 271 rows and 213 KB; a full finish log adds up to 4 KB a row, and one
character outside ASCII makes iOS store the whole string at 2 bytes a character), so a player with a
few thousand pictures would pass the 4 MB that NSUserDefaults allows an app. On the iPhone it is
therefore a file of its own, `<Application Support>/sync/<userId>.rows.json` (`FileSyncRows`, opened
in `main.dart`): written in the background, one write at a time and only the newest, next to the file
and renamed over it. A copy that a build up to 127 left in SharedPreferences (`sync.v1.<userId>.rows`)
moves to the file on the first start and leaves SharedPreferences; if an older build is installed
again it finds no copy there and reads every row from the server, quietly, and its queued ops are
where it left them (the queue stays in SharedPreferences: it is small). The web keeps the copy in
localStorage (`PrefsSyncRows`), as do the unit tests. Account deletion removes the file
(`AccountDeletion.startOver`).

## Exactly once

A request can reach the server and lose its answer. Every profile op appends its id to
`profiles.appliedOps` (event steps to `event_progress.appliedOps`); before an op is sent again (or
on the next fetch) the controller checks that list, so the op is never applied twice. Op ids start
with four characters naming the device (`syncDevice` in its storage): a device removes its own ids
once their ops are confirmed (when it holds more than 20; its newest 10 stay, so the row always shows
which device changed the save last), and any id older than 30 days goes.
Progress ops are idempotent by design (a win recognises its own write by play-through and finish
time). Ledger rows have fixed ids (`<op id>-<n>`). The stored rows are written before the confirmed
op is dropped, so a restart never mistakes this device's own play for another device's.

## Appwrite behaviour the code relies on

Checked against the live backend (Appwrite Cloud 2.4.0) on 2026-10-13 with a QA guest:

- `decrement` below its min and `increment` above its max leave the column unchanged (no error).
- A skipped column does not stop the other columns of the same update.
- `arrayAppend` keeps duplicates; `arrayUnique` and `arrayDiff` work as named. The controller
  tidies duplicates after a sync, and `Profile.fromRow` ignores them.
- `upsertRow` accepts operators, also when it creates the row.
- Passing a nested list to `arrayAppend` stores it and breaks later updates of the row: always pass
  a flat list of strings (`Append` in `lib/data/sync/changes.dart`).

## Columns

`profiles.appliedOps` and `event_progress.appliedOps` (string arrays, 32) and `progress.session`
(string 32), all optional, added 2026-10-13 (Appwrite CLI). Builds before the sync ignore them.

`progress.painting` (boolean, default false, optional), added 2026-10-14 (Appwrite CLI): the board
in progress (or the last one finished) is played in Painting. Board and win ops `Put` it with the
layout, so the flag always describes the saved board; ops queued by older builds carry no flag
and write `false`, and a sign-in merge takes it from the row whose board it keeps. Older builds
ignore it (and resume such a board in colour).

`progress.par` (integer 0-100000, default 0), `progress.peeked` (boolean, default false) and
`progress.bestLock` (integer 0-100000, default 0), all optional, added 2026-10-14 (Appwrite CLI):
the play-through's dealt par, whether Peek was used and the most cards one move of the player's
locked (Magic does not count). The quests read them ("Finish a 4x4 or bigger board at par", "Lock
5 cards in one move", and "Solve 2 pictures without Peek" for players with nothing else to do yet). Like `painting` they describe the board on the row: board and
win ops `Put` them, a discard clears them, ops queued by older builds write 0 / false, and a
sign-in merge takes them from the row whose board it keeps. A resumed board keeps its saved par
for the quests; the stars still use the par recomputed on resume.

`progress.finishes` (string 4000, optional, no default), added 2026-10-17 (Appwrite API): the picture's
finished boards, each with the values it was finished with, a JSON list (`BoardFinish`,
`lib/models/board_finish.dart`): `at` (UTC, to the millisecond), `mode`, `gridSize`, `painting`, `par`,
`moves`, `seconds`, `peeked`, `bestLock`, `stars`, `hints`. The board fields above belong to whatever board
is on the row, so a replay overwrote what the quests and achievements read about a finish (shape, size,
Painting, par, lock, time, Peek, hints); both now count these entries (docs/economy.md, "Quests that do not
overlap"; `AchievementFacts` in `lib/state/achievements.dart`: a picture counts once for a family when one
of its boards does what it asks, so a replay never moves an achievement back, and the progress shown never
falls below a step already claimed). A win `Put`s the log with its finish added, against the fresh row: one
entry per finish time (a win sent twice is one), the 8 days before the newest finish plus the newest one
before them (what the player usually plays looks before today or Monday), plus, from any time, the boards
the achievements count a picture by (the newest of each shape, the biggest, the newest without hints, quick,
at night, early); at most 16 entries in 4,000 characters, the oldest other entries going first. Rows from older builds have no log:
their last finish is on the board fields until a board is saved over them; a board op from this build
records it first (`BoardFinish.unrecorded`), and one saved by an older build leaves it a finish with no
values (`known: false`, a solve on its day and nothing more). An older build finishing after this one moves
`completedAt` past the log: the board fields hold that finish (`BoardFinish.ofRow`). A sign-in merge takes
the finishes of both rows. Older builds ignore the column and never clear it.

`profiles.piggyLevel` (integer 0-5, default 0, optional), added 2026-10-17 (Appwrite CLI): piggy bank
upgrades bought (`SyncOp.piggyUpgrade`, 5,000 coins each; the bank holds `500 + 100 x level`). The op
names the level it raises to and is built against the fresh row: a level already reached (bought on
another device) charges nothing (`SkipReason.piggyUpgraded`), coins spent elsewhere meanwhile undo it
(`notEnough`), and nothing goes past 5. Solve ops fill the piggy bank up to the row's own size
(`Inc(piggy, max: capacity)`), so an upgrade made on one device counts on every other. A sign-in merge
keeps the larger level of the two saves, like unlocks. Older builds ignore the column: they show and
fill a 500-coin bank (their solve op adds nothing past 500) and still open a bigger one in full.

`profiles.questSwaps` (text, optional, no default), added 2026-10-17 (Appwrite CLI): quests swapped for
a ticket, a JSON map of slot to the quests the slot has had this day or week (`Goals.decodeSwaps`,
docs/economy.md "Swapping a quest"). `SyncOp.questSwap` is built against the fresh row and `Put`s the
whole map: it names the number of swaps it saw in the slot, so a swap made meanwhile on another device
wins and this one charges nothing (`SkipReason.questSwapped`); a quest claimed in the slot meanwhile
skips it too (`questClaimed`). Two swaps of different slots on two devices within one round trip can
overwrite each other's entry (the Put is last-writer-wins, like other guarded ops; the ticket stays
spent). A sign-in merge takes the chosen save's map. Older builds ignore the column.

## Known limits

- A guarded op is checked and then written: two devices claiming the same quest within one round
  trip can both be paid. The window is a fraction of a second.
- A board saved within 30 seconds of this device's last read or write of the row is not read
  first: a board finished on another device in those seconds can still be written over by this
  one (two devices playing the same board at the same time).
- Two browser tabs of the web site share one queue in localStorage; if both queue changes while
  offline and one closes before the connection returns, its queue can be overwritten by the other.
- The web keeps the copy of the rows in localStorage (5 MB per site, shared with the queue and the
  settings): a player with several thousand pictures would fill it, and the copy would then not be
  stored (the next visit reads every row again, quietly). Move it to IndexedDB, as the catalogue,
  before that matters.
- After a start, a board this device started and another device continued without any profile op
  (board saves only) updates quietly: the alert has no "Board in progress" line for it (an open game
  still follows it). The first read cannot tell that save from this device's own lost one.
- Purchases (`/purchase/verify` on `api`, and `verify-purchase` for builds up to 124) add the grant
  with atomic increments (`Operator.increment`), so a change from the player's device in the same
  instant is kept.

## Tests

- `test/sync_test.dart`: two devices on an in-memory server (`test/support/fake_sync.dart`) that
  applies the operators as above: balances add up, unlocks are not lost, offline play survives a
  restart, double claims pay once, a lost answer is not applied twice, the notice, records, board
  conflicts, a board finished elsewhere staying finished, levels, the `local` hand-over, tidying, and a
  row another player made first (the op parked quietly, the rest sent, the save landing on the next
  start or a later resume, a 401 without a session still waiting; friend and block rows under a unique
  id).
- `test/sync_first_board_test.dart`: a fresh guest's first board, then a start whose stored copy
  lost it (no notice), another device's daily gift and picture on that start (told), a purchase the
  server added (told), `SyncSource`, and the newest own op ids kept on the row.
- `test/sync_device_copy_test.dart`: the copy as a file (newest last, read before it is on disk), a
  build-127 copy moving out of SharedPreferences, an older build's copy winning, removal, and a
  player's 40 pictures staying out of SharedPreferences through the sync.
- `integration_test/first_board_sync_test.dart`: a fresh QA guest plays the guided first board on
  the simulator to Home, then a resume: no "Synced from another device" (`fbs_*.png`), and the copy
  of the rows is a file.
- `integration_test/sync_devices_test.dart`: the app on the simulator is the iPhone, a second
  sync in the same process (own storage, same session) is the laptop, on the live backend:
  `tools/dev/qa-run.sh drive --driver=test_driver/integration_test.dart
  --target=integration_test/sync_devices_test.dart -d <udid>` → `screenshots/sync_*.png` (step 4:
  a board finished on the laptop closes on the iPhone, `sync_06_solved_elsewhere.png`).

## Adding a new kind of change

Add a factory and a `case` in `SyncOp` (never rename an existing kind: queued ops are stored by
name), call it from the notifier through `enqueue`, and add a line to `SyncNotice`/`syncNoticeLines`
if players should hear about it from another device. Never write absolute values computed from
the device's copy for anything another device can change.
