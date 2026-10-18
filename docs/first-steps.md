# First steps (the guided start)

Owner, 2026-10-16: testers found the app "too much, too crowded" after the welcome pages, and said
they did not know what to do and that it felt like a chore. The guided start plays first and lets
the rest of the app arrive one piece at a time.

Code: `lib/state/first_steps.dart` (state, rules), `lib/features/home/guided_start.dart` (cards,
alert, tips), the coach in `lib/features/game/game_screen.dart` (`_Coach`), tabs in
`lib/features/home/home_shell.dart` and `lib/widgets/glass.dart` (`GlassTabItem.locked`).

## Who gets it

A player who finishes onboarding on this device (`SettingsNotifier.setOnboarded` calls
`FirstSteps.markNewPlayer`): the welcome pages, a first link or a sign-in. Players who started
before 2026-10-16 have no `firstSteps` record and see the whole app as before. A returning account
on a new device is guided too, but its level opens almost everything at once, and nothing is
announced to a player far past it. Deleting an account removes the record, so the fresh start is
guided again.

## The path

1. **Welcome pages, then straight into a first board.** "Start playing" (or Skip) goes to Home and
   pushes the first board over it: Pink Sands Beach (`firstBoardPuzzle`, free starter pack Tropical
   Beaches) on nine cards (Cards 3x3, `?first=1`). The picture loads while the welcome pages are
   open (`firstBoardPrefetchProvider`). The tap ends the welcome for good (`onboarded` is saved before
   the wait for a slow catalogue, with a spinner on the button): a player who closes the app before
   the board is dealt starts on Home next time, with the first picture on top (owner, TestFlight
   2026-10-18). The welcome pages come back only after Delete account. The buttons under the pages
   follow the swipe to the last page: "Continue" cross-fades into "Start playing" and Skip fades out
   with it, its space kept (a short cross-fade with Reduce motion). It was chosen by scoring every picture of the six starter
   packs for how clearly its nine cards differ in colour and detail; a picture of similar cards
   (rocks, bamboo, night sky) is hard on a first board.
2. **One hint per step on the first board** (until `tutorialSeen`), where the tools will be (the
   tool bar stays laid out but hidden, so the board keeps its size), once the board has shown its picture and dealt
   the cards (docs/giant-boards.md, "The picture before the deal"): "Tap a card to pick it up",
   then the picked card's place is outlined (`GameController.guide`, free, not a Hint) with "Now
   tap the outlined spot", then "It locked in place..." (or "They joined..."). No title or step
   count, only the line (owner), two lines at most (`BoardCoach.lineFor`). The next move ends the hints, the tools fade in, and a toast says
   "Fewer moves earn more stars. Take your time." The close button ends them at once. They never
   come back.
3. **The finish**: its way out is **Home** (the board was opened over it).
4. **A calm Home**: until the daily puzzle opens, the **next step** takes the top of Home as a
   large picture (`NextStepCard(heroHeight:)`; `nextStepProvider`: the first picture, then the next
   picture of the first pack, then "Try Squares" once Squares open, then "Find a pack you like");
   afterwards today's picture is on top and the next step is a card under it. Until the Library
   opens, that suggested picture (and a board in progress, under Continue) is the only thing to play.
   At the end, the rest of Home is **blurred** under "More opens as you play", which lists what opens
   next with how many more pictures each needs ("2 more pictures") and has **Unlock anyway**.
5. **What counts** (`countedFinishesProvider`; owner, 2026-10-16): of the pictures finished after
   onboarding and before the player first reaches Home (the first board, and any played on with Next
   puzzle), only the first counts; from the moment Home is on screen (`FirstSteps.homeAt`, set by
   `HomeShell`), every picture counts. A returning account's pictures from before onboarding here all
   count. Levels do not count.
6. **Everything opens by pictures counted** ([`Reveal`]):

   | Pictures | What opens |
   | --- | --- |
   | 3 | the Library tab (and the pack rows on Home), Quick play |
   | 5 | the daily puzzle (Home's picture of the day, the daily months on Home and in the Library, the Daily chip), the guest "Save your progress" card |
   | 10 | the daily gift (streak card, Home dot) |
   | 15 | the Lucky Wheel, the level card |
   | 20 | the Quests tab (daily and weekly quests); store offers (VIP banner, break offers) |
   | 25 | achievements on Profile (and its dot) |
   | 30 | the piggy bank |
   | 35 | live events (Home's shelf, the Quests section, event packs in the Library) |
   | 50 | the Social tab (league, friends, inbox) |

   The Library also opens by itself when the first pack has nothing left to play
   (`firstPackDoneProvider`): a player who plays all of it with Next puzzle before ever reaching Home
   has one picture counted and would otherwise be left with only Unlock anyway (owner, 2026-10-17).

   Store > Earn for free > **Play a puzzle** closes the Store and starts Quick play once Quick play
   is open; before that it opens the picture Home suggests (the next step), or Home itself when the
   first board is under way and Continue leads back to it (`playFromStore`, owner, 2026-10-17).

   Nothing is announced when something opens: no "Just opened" card, and no level intro sheets
   ("Squares are open") for guided players (`pendingUnlockIntroProvider`).
7. **Quests and achievements count only after they open** (`countsFromProvider`): pictures finished
   before the moment they opened (by playing: the picture that opened them; by Unlock anyway: that
   moment) do not count, so they never open full of rewards. States such as the level, the streak or
   the coins held stay what they are.
8. **Locked places say how many pictures are left**: locked tabs are drawn faded with a small lock
   and keep their place in the bar; a tap shows "Quests open after 19 more pictures" with **Unlock
   anyway** or Not now. A tab that opened by playing carries a dot until it is visited. Profile shows
   achievements, and Quests shows live events, as one locked card with Unlock anyway: under the
   section's own header, a one-line title ("Opens after 24 more pictures", `Reveal.opensAfter`) and
   a one-line description (`Reveal.blurb`).
9. **Every Unlock anyway asks first**: "Are you sure?" says it opens by itself after N more pictures
   and that waiting keeps the start calm, one new thing at a time, with quests and achievements
   counting from the moment they open (Keep waiting / Unlock ...). On Home, with more than one thing
   to come, a sheet first lists them with a check each, only the nearest picked; picking all of them
   unlocks everything.
10. **Tips at the moment they matter**, each once: the Library's "Start with the free packs...", the
    board picker's "Pick a shape and a size...", and "Stuck? Hint shows where one card belongs" after
    six moves in a row without a lock or join.

    **Short** (owner, TestFlight 2026-10-18): every hint and tip card fits two lines on a 390 pt
    iPhone at the default text size; a locked card, and each entry of Home's "More opens as you
    play", has a one-line title and a one-line description. `test/hint_lines_test.dart` lays each one
    out at its real width (in San Francisco on a Mac, calibrated against the owner's screenshots) and
    checks Large and Largest text for overflow. New copy there must pass it.
11. The board picker opens one step up from nine cards (**Relaxed**, 4x4) until the player picks a board.

Settings > Gameplay > **Guided start** (shown to guided players) turns it off (everything open)
or back on (what the player reached stays open).

## Tests

- `test/first_steps_test.dart`: the rules (who is guided, what counts, the schedule, quests and
  achievements from their opening, Unlock anyway, tab dots).
- `test/guided_home_layout_test.dart`: the guided Home at SE, Pro and website sizes, both themes,
  text 100% and 200%, before and after the first picture, without layout errors.
- `test/hint_lines_test.dart`: hints two lines, locked cards one line each, at 390 pt.
- `test/welcome_once_test.dart`: Skip, close the app while the first board loads, open it again:
  Home; the buttons under the pages follow the swipe.
- `integration_test/first_steps_test.dart`: the whole path on the simulator with a QA guest
  (screenshots `fs_*`). Every other suite starts past the first steps (`FirstSteps.skipFor`).
- `integration_test/welcome_relaunch_test.dart`: Skip, then a real relaunch on the simulator's own
  preferences (two runs, the second without uninstalling).

Research behind it: Unity's FTUE tips (core loop first, unlock gradually), Supersonic on teasing
features and holding offers back in the first session, and the case against forced click-through
tutorials (contextual hints instead).
