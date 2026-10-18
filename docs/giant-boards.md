# Giant boards

Pictures of a pack with category `Giant` deal only four giant sizes (Large, Huge, Giant, Colossal).
Like every board they are square (owner, 2026-10-17; `docs/boards.md`): in Cards 10x10, 12x12,
14x14 and 17x17 (100 to 289 cards); Squares 13x13 to 22x22, Triangles 10x10 to 18x18 (a column is
one up and one down triangle) and Hexagons 13x13 to 23x23, the sizes nearest the counts those shapes
had (`BoardSpec.squareGiantTiers`). The
picture is centre-cropped to the board; Expand, where the picture's shape asks for it, deals the
picture-shaped giant sizes of before (`BoardSpec.giantTiers`). The pictures are hosted at up to
4096 px on the long side and decoded at full size, so the board can be zoomed in and stay sharp.
This page records how other big-board jigsaw apps help players on a phone and what Carden does on
a giant board.

Giant boards open at level 10 (`Unlock.giant`). Before that a Giant pack's page shows the gate
(`GiantGateCard`, `lib/features/gallery/giant_gate.dart`): the way to level 10, and two ways in side
by side, "At level 10" for the pack's usual price or "Now" for that price plus 1 ticket for every
level to go (`Economy.giantEarlyFee`). Opening now buys the pack and records `early:giant` in
`profiles.unlockedTiers`, which `OpenFeatures.forPlayer` reads, so giant boards stay open on every
device. The Library card says "Opens at level 10", and a picture of the pack (a tile, a search
result, a link, the difficulty screen's locked button) leads to the gate.

## What other games do (research, October 2026)

| App | What it offers for big puzzles | Source |
|---|---|---|
| Jigsaw Puzzle by MobilityWare | Edges-only view and a piece tray, hints, image preview | [App Store](https://apps.apple.com/app/id1603688971) |
| Jigsaw Puzzle⁺ | Zoom and pan, show all pieces or edge pieces only, tray on or off | [App Store](https://apps.apple.com/app/id1571760112) |
| Jigsaw Explorer (web) | Show only edge pieces, autosave of progress | [Educators Technology](https://www.educatorstechnology.com/2023/03/jigsaw-explorer-free-online-jigsaw.html) |
| Jigsaw Puzzle HD | Zoom and pan; a guided mode that sorts pieces by colour and edge | [App Store](https://apps.apple.com/app/id6453471674) |
| Jigsawscapes / desktop puzzles | Sort by shape and colour, "arrange at edge", magnifying glass, ghost image | [App Store](https://apps.apple.com/app/id435749624), [Jigsaws Galore](https://lutris.net/games/jigsaws-galore/) |
| PuzzleTouch | Double tap on the table to zoom in and out, performance work for big puzzles | [Microsoft Store](https://microsoft.com/nl-be/p/puzzletouch/9wzdncrfj45p) |
| Magic Jigsaw Puzzles | Up to 1,200 pieces, several puzzles in progress, preview | [App Store](https://apps.apple.com/us/app/magic-jigsaw-puzzles-games-hd/id439873467) |
| Jigsaw Puzzle ++ | Players like working on a zoomed-in quarter of the puzzle (sight issues) | [review summary](https://mwm.ai/apps/jigsaw-puzzle/1477002422) |

What reviews complain about on big boards ([Justuseapp](https://justuseapp.com/en/app/796882776/jigsaw-puzzles-epic/reviews),
[App Store 1000 Jigsaw Puzzles](https://apps.apple.com/app/id571230079), [MobilityWare reviews](https://justuseapp.com/en/app/495583717/jigsaw-puzzle/reviews)):
pieces too small; the board growing or shrinking on its own when touched; zoom that does not work;
a preview too small to read; and finding the last unplaced pieces once the board is nearly full.

## What a giant board does here

The swap board has no free table and no tray (every card is always on the board), so the tools
are the ones that make sense for it.

### No zones (owner, 2026-10-14)

Giant boards were dealt by zone for a day (each card shuffled inside an area of about a normal
board). The owner removed it: the player can zoom in as far as they like and Gather the cards for
the view, so zones only added lines and rules. A giant board is shuffled across the whole board like
any other (`Board.shuffled`: no card in place, no pair joined).

### Finding a card's place

- **Locate** (owner, 2026-10-14; always on since build 117, no switch): tap a card on a zoomed board
  and the overview map shows where it belongs: a ring there and a line from the card, for as long as
  the card is selected. It only uses the map when the map is on (it never opens a hidden map). The
  first zoom with the map on says so once ("Tap a card to see its place on the map").
- **Gather** (in the bar at every zoom, the whole board included): every card that belongs in the
  view comes into it. Each card in view that belongs elsewhere trades places with one that belongs
  here, chosen so the card leaving lands as close to its own place as it can. Cards in place, joined
  groups and trades that would put a card straight into its place are left alone: Gather sorts, it
  never solves, so the last card or two may stay just outside the view (nor puts a card on a twin's
  place, `docs/twins.md`). Gather only gathers (owner,
  2026-10-17): the button is dimmed while the view has nothing to bring in (`canGather`, worked out
  150 ms after the view settles and after every change on the board, about 0.1 to 0.25 ms on the
  biggest boards; never per frame). It is not a move. Its toast ("12 cards gathered") has an
  **Undo** that takes the gather back while nothing else has changed; that is the only Undo left in
  the game. (`gatherInto` in `lib/game/gather.dart`.)
- **Shuffle** (owner, 2026-10-17: the round button left of the tools on every board, free, where Undo
  was): the loose cards trade places at random, so the board can be read afresh; on a giant board only
  the ones in view (the whole board when not zoomed in). Cards in place and joined groups (also ones
  not yet in place) stay exactly where they are; every loose card moves, none lands in its place (or
  a twin's, `docs/twins.md`) and, where another order allows, no pair is joined (or looks joined). Not a move. "Nothing left to shuffle" when no card can
  move. (`shuffleLoose` and `shuffleInView` in `lib/game/gather.dart`.)
- **Magic** puts a card and its neighbours in place (owner, 2026-10-17): the selected card (with
  nothing selected, the card a Hint shows, else any card not in place), then each card whose place
  borders its place, each with its group. Up to 5 of the 9 cards on a 3x3. One move per card it
  sends; it plays a plain lock, never the "×2 DOUBLE LOCK", and does not count for the "Lock N cards
  in one move" quests.
- **Peek** (10 coins on every board; owner, 2026-10-14: no free Peek on giant boards): every card not in place flies to its place,
  the picture shows (3.2 s on a giant board, 2.4 s elsewhere) and the cards fly back, each a little
  later than the last, so the picture builds itself in a ripple. A tap anywhere while the picture
  shows sends the cards back at once (owner, 2026-10-17). Using it still counts against the
  "without Peek" quest (a fallback for level 1 players).
- **The picture before the deal** (owner, 2026-10-17; every board dealt on the device, not a resumed
  board or a shared one): the board opens on the whole picture, every card in its place, for 1.3 s
  (1 s on a giant board), then the cards glide to where they were dealt in a sweep from the top left
  corner (about 1 s). A tap deals at once. It is free, not a move and not a Peek, and the clock starts
  after it (`GameState.previewing`, `GameController.startPreview`). Shuffle and restart and Replay
  open on it too. Integration suites that play a board the moment it shows turn it off
  (`GameScreen.dealPreview = false`).
  Its time counts only while the player can see the board (owner, TestFlight 2026-10-18: after Next
  puzzle a slow picture went from the blurred placeholder straight to dealt cards): the app in front,
  the game page on top with its fade-in done, nothing over it (`_inView` in `game_screen.dart`). iOS keeps
  drawing an app that is not in front (the screenshot editor and TestFlight's feedback sheet, Control
  Center, a call), so a picture that arrived then used to show to nobody. Now the picture waits
  (`GameController.holdPreview`), the clock with it, and shows whole for the full time once the board
  is in view again. Tests: `test/deal_preview_screen_test.dart`; QA: `integration_test/deal_next_test.dart`
  (Next puzzle on a daily month with the picture 0 to 6 s late, `debugPictureDelay`).

### The other tools

- **Pinch to zoom, two fingers to move; one finger plays as usual.** Tap-tap and drag work at
  every zoom, and a selected card stays selected while zooming and panning. The zoom changes only
  when the player asks (no automatic zoom: a top complaint elsewhere).
- **No double tap** (owner, build 117; it was there before, after PuzzleTouch): two quick taps on a
  card select and deselect it like on any board. The zoom-in button goes in a step, the whole-board
  button back out.
- **A zoom limit per board** (`BoardZoom.fitCell`): a card reaches about 96 pt on screen at most,
  so the 100-card board stops near 2.5x and the 300-card board at 4x. Never so close that only two
  cards show.
- **Overview map** while zoomed in: the whole board in miniature in the corner, cards in place
  bright and the rest darker (so the unfinished areas are easy to find, the "last pieces" problem),
  the view outlined, the selected card marked. Tap or drag on it to move the view. A button in the
  bar hides it (remembered).
- **A pointer to the selected card** when it is out of view: a round cobalt arrow on the edge of
  the view, turned towards the card; tap it to go back.
- **Auto-pan**: drag a card to the edge of the view and hold it there, the board slides under it,
  so one drag can cross the board.
- **Resume on the same view**: the zoom and the part of the picture in view are saved per board on
  the device (`GiantViews`) and restored when the board is continued; finishing the board forgets it.
- **Thin frames on giant boards**: the board is scaled as a whole, so gutters, frames and outlines
  are kept thin for the close view and outlines thin out in steps as the zoom grows (at 4x a
  normal frame took a third of every card).
- **Milestones**: a calm toast when the frame is complete and at halfway, once each per board.
- An Edges switch (fade every card whose place is not on the outline) was tried and removed by the
  owner on 2026-10-14.

Code: Gather in `lib/game/gather.dart`; `BoardZoom`, the board's gestures and Peek's flight in
`lib/features/game/board_widget.dart`; the bar (Gather, map, zoom), the map with Locate, the pointer
and the milestones in `lib/features/game/giant_board.dart`; the saved views, the map switch and the
Locate tip in `lib/state/giant.dart`. Tests: `test/gather_test.dart`, `test/giant_ux_test.dart`.
QA: `integration_test/giant_ux_test.dart` and `integration_test/giant_tools_test.dart` play the real
Giant pack.
