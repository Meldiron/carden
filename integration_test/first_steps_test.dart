// A new player's first steps (owner, 2026-10-16), on the real app with a QA guest and no shortcuts:
// the welcome pages lead into a first board with a hint per step, the finish leads Home, Home starts
// calm (the next picture on top, the rest blurred) and grows with the second picture, locked tabs
// explain themselves and open with "Unlock anyway", Quests keeps live events locked, one-time tips
// show in the Library and on the board picker, and "Unlock anyway" on Home opens everything.
//
//   tools/dev/qa-run.sh drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/first_steps_test.dart -d <simulator>
import 'package:carden/app.dart';
import 'package:carden/core/sfx.dart';
import 'package:carden/data/local_store.dart';
import 'package:carden/features/game/board_widget.dart';
import 'package:carden/features/game/difficulty_screen.dart';
import 'package:carden/features/game/game_screen.dart';
import 'package:carden/game/board.dart';
import 'package:carden/state/first_steps.dart';
import 'package:carden/state/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> settle(WidgetTester tester, [int ms = 1500]) async {
  await tester.pump(const Duration(milliseconds: 50));
  final end = DateTime.now().add(Duration(milliseconds: ms));
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  Future<void> shot(WidgetTester tester, String name) async {
    await settle(tester, 400);
    await binding.takeScreenshot(name);
  }

  Future<void> tapText(WidgetTester tester, String text, {int ms = 1200}) async {
    final f = find.text(text);
    expect(f, findsWidgets, reason: 'expected "$text" on screen');
    await tester.tap(f.first, warnIfMissed: false);
    await settle(tester, ms);
  }

  Future<void> tapKey(WidgetTester tester, String key, {int ms = 1200}) async {
    final f = find.byKey(ValueKey(key));
    expect(f, findsWidgets, reason: 'expected $key on screen');
    await tester.tap(f.first, warnIfMissed: false);
    await settle(tester, ms);
  }

  Future<void> scrollTo(WidgetTester tester, Finder f) async {
    await tester.scrollUntilVisible(f, 300, scrollable: find.byType(Scrollable).first);
    await settle(tester, 600);
  }

  bool shown(String key) => find.byKey(ValueKey(key)).evaluate().isNotEmpty;

  ProviderContainer container(WidgetTester tester) => ProviderScope.containerOf(tester.element(find.byType(CardenApp)));
  BoardWidget board(WidgetTester tester) => tester.widget<BoardWidget>(find.byType(BoardWidget).first);

  Offset onScreen(WidgetTester tester, int slot) {
    final w = board(tester);
    final rect = tester.getRect(find.byType(BoardWidget).first);
    return rect.topLeft + w.state.board.tiling.cellCenter(slot, Size(w.width, w.height));
  }

  Future<void> move(WidgetTester tester, int from, int to) async {
    await tester.tapAt(onScreen(tester, from));
    await settle(tester, 350);
    await tester.tapAt(onScreen(tester, to));
    await settle(tester, 600);
  }

  /// Sends every misplaced card home, one tap-tap move at a time.
  Future<void> solve(WidgetTester tester) async {
    for (var guard = 0; guard < 80; guard++) {
      final b = board(tester).state.board;
      if (b.isSolved) return;
      final slot = List.generate(b.cells, (i) => i).firstWhere((i) => !b.isLocked(i));
      await move(tester, slot, b.homeOf(slot));
    }
  }

  /// A tab of the floating tab bar by its label (the tab bar is the last of the texts).
  Future<void> tapTab(WidgetTester tester, String label, {int ms = 1500}) async {
    await tester.tap(find.text(label).last, warnIfMissed: false);
    await settle(tester, ms);
  }

  testWidgets('first steps: first board, a calm Home that grows, locked tabs, Unlock anyway', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    Sfx.instance.soundEnabled = false;
    Sfx.instance.musicEnabled = false;
    await tester.pumpWidget(ProviderScope(overrides: [localStoreProvider.overrideWithValue(store)], child: const CardenApp()));
    await settle(tester, 1500);
    await tapText(tester, 'Continue');
    await tapText(tester, 'Continue');
    await shot(tester, 'fs_00_welcome_last');
    await tapText(tester, 'Start playing', ms: 3000);
    await settle(tester, 3000);
    final c = container(tester);
    expect(c.read(firstStepsProvider).calm, isTrue, reason: 'a new player gets the guided start');

    // 1. Straight into a first board: nine cards, the hint for step 1, no tools yet.
    expect(find.byType(GameScreen), findsOneWidget, reason: 'the welcome pages lead into a board, not Home');
    final spec = board(tester).state.board.spec;
    expect((spec.mode, spec.cells), (GameMode.cards, 9));
    expect(shown('coach-pick'), isTrue);
    await shot(tester, 'fs_01_first_board');

    // 2. Pick a card: its place is outlined.
    var b = board(tester).state.board;
    final slot = List.generate(b.cells, (i) => i).firstWhere((i) => !b.isLocked(i));
    await tester.tapAt(onScreen(tester, slot));
    await settle(tester, 700);
    expect(shown('coach-place'), isTrue);
    expect(board(tester).state.hintTarget, b.homeOf(slot), reason: 'the outline shows where the picked card belongs');
    await shot(tester, 'fs_02_place');

    // 3. Put it there: it locks, and the hint says so.
    await tester.tapAt(onScreen(tester, b.homeOf(slot)));
    await settle(tester, 900);
    expect(shown('coach-locked') || shown('coach-joined'), isTrue);
    await shot(tester, 'fs_03_locked');

    // 4. The next move ends the hints; the tools come in.
    b = board(tester).state.board;
    final next = List.generate(b.cells, (i) => i).firstWhere((i) => !b.isLocked(i));
    await move(tester, next, b.homeOf(next));
    await settle(tester, 600);
    expect(shown('coach'), isFalse);
    expect(c.read(settingsProvider).tutorialSeen, isTrue);
    await shot(tester, 'fs_04_tools');

    // 5. Finish: the way out is Home, but the player plays on with Next puzzle first. That second
    //    picture does not count: until Home is reached, only the first board does.
    await solve(tester);
    await settle(tester, 4000);
    expect(find.text('Home'), findsWidgets);
    await shot(tester, 'fs_05_complete');
    await tapText(tester, 'Next puzzle', ms: 6000);
    expect(find.byType(GameScreen), findsOneWidget);
    await solve(tester);
    await settle(tester, 4000);
    expect(c.read(solvedCountProvider), 2);
    expect(c.read(countedSolvesProvider), 1, reason: 'only the first board counts before Home');
    await tapKey(tester, 'completion-back', ms: 3500);
    expect(c.read(firstStepsProvider).homeAt, isNotNull, reason: 'Home reached: from now on every picture counts');
    expect(shown('unlock-try'), isFalse, reason: 'level 2 opened Squares, and nothing pops up about it');

    // 6. A calm Home: the next picture on top (the only thing to play), the rest blurred below; no
    //    Quick play, pack rows or daily puzzle; Library, Quests and Social locked.
    expect(find.byType(GameScreen), findsNothing);
    expect(find.textContaining('Just opened'), findsNothing);
    expect(find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('next-step-')), findsWidgets, reason: 'the suggested picture leads Home');
    expect(shown('home-quick-play'), isFalse);
    expect(find.text('Featured packs'), findsNothing);
    expect(shown('tab-lock-Library') && shown('tab-lock-Quests') && shown('tab-lock-Social'), isTrue);
    await shot(tester, 'fs_06_home');
    await scrollTo(tester, find.byKey(const ValueKey('more-to-come')));
    await tester.ensureVisible(find.byKey(const ValueKey('unlock-anyway')));
    await settle(tester, 600);
    expect(find.text('2 more pictures'), findsWidgets, reason: 'the Library chip says how many are left');
    await shot(tester, 'fs_07_more_to_come');
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000));
    await settle(tester, 800);

    // 7. A locked tab says how many pictures are left; Not now keeps it closed.
    await tapTab(tester, 'Quests', ms: 1200);
    expect(find.text('Quests open after 19 more pictures'), findsOneWidget);
    await shot(tester, 'fs_08_locked_tab');
    await tester.tap(find.text('Not now').last, warnIfMissed: false);
    await settle(tester, 1000);
    expect(shown('tab-lock-Quests'), isTrue);

    // 8. Unlock anyway asks first; Keep waiting keeps the Library closed.
    await tapTab(tester, 'Library', ms: 1200);
    expect(find.text('Library opens after 2 more pictures'), findsOneWidget);
    await tester.tap(find.text('Unlock anyway').last, warnIfMissed: false);
    await settle(tester, 1200);
    expect(find.text('Are you sure?'), findsOneWidget);
    await shot(tester, 'fs_08b_are_you_sure');
    await tester.tap(find.text('Keep waiting').last, warnIfMissed: false);
    await settle(tester, 1000);
    expect(shown('tab-lock-Library'), isTrue);

    // 9. Unlock anyway, then yes, opens Social only.
    await tapTab(tester, 'Social', ms: 1200);
    expect(find.text('Social opens after 49 more pictures'), findsOneWidget);
    await tester.tap(find.text('Unlock anyway').last, warnIfMissed: false);
    await settle(tester, 1200);
    await tester.tap(find.text('Unlock Social').last, warnIfMissed: false);
    await settle(tester, 2500);
    expect(shown('tab-lock-Social'), isFalse);
    expect(shown('tab-lock-Quests') && shown('tab-lock-Library'), isTrue);
    await shot(tester, 'fs_09_social_open');

    // 10. Quests opened early count from now: the pictures so far do not count; live events wait.
    await tapTab(tester, 'Quests', ms: 1200);
    await tester.tap(find.text('Unlock anyway').last, warnIfMissed: false);
    await settle(tester, 1200);
    await tester.tap(find.text('Unlock Quests').last, warnIfMissed: false);
    await settle(tester, 2500);
    expect(find.textContaining('0 of 10'), findsWidgets, reason: 'Solve 10 puzzles this week starts at 0');
    await shot(tester, 'fs_09b_quests_from_now');
    await scrollTo(tester, find.byKey(const ValueKey('locked-liveEvents')));
    expect(find.text('Opens after 34 more pictures'), findsOneWidget, reason: 'one line under the Live events header');

    // 11. Two more pictures, each from Home's suggestion, the board picker's tip the first time.
    Future<void> playSuggested(String name) async {
      await tapTab(tester, 'Home', ms: 2000);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000));
      await settle(tester, 800);
      final step = find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('next-step-'));
      expect(step, findsWidgets, reason: 'Home suggests the next picture');
      await tester.tap(step.first, warnIfMissed: false);
      await settle(tester, 3500);
      expect(find.byType(DifficultyScreen), findsOneWidget);
      if (name == 'second') {
        expect(shown('tip-board'), isTrue);
        await shot(tester, 'fs_11_board_tip');
      }
      await tester.tap(find.byKey(const ValueKey('play-board')), warnIfMissed: false);
      await settle(tester, 6000);
      expect(shown('coach'), isFalse, reason: 'the hints are for the first board only');
      await solve(tester);
      await settle(tester, 4000);
      await shot(tester, 'fs_12_${name}_complete');
      await tapKey(tester, 'completion-back', ms: 3500);
      expect(shown('unlock-try'), isFalse);
    }

    await playSuggested('second');
    expect(c.read(countedSolvesProvider), 2);
    expect(shown('tab-lock-Library'), isTrue, reason: 'two counted: the Library waits for the third');
    await playSuggested('third');

    // 12. Three counted: the Library opens (with a dot until visited), the packs join Home and
    //     Quick play is there; nothing is announced.
    expect(c.read(countedSolvesProvider), 3);
    expect(shown('tab-lock-Library'), isFalse);
    expect(c.read(newTabsProvider).contains(Reveal.library.tab), isTrue);
    expect(find.textContaining('Just opened'), findsNothing);
    expect(shown('home-quick-play'), isTrue);
    await shot(tester, 'fs_13_home_grows');
    await scrollTo(tester, find.text('Featured packs'));
    expect(find.text('Featured packs'), findsOneWidget);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000));
    await settle(tester, 800);
    await tapTab(tester, 'Library', ms: 2500);
    expect(shown('tip-library'), isTrue);
    expect(find.text('Daily'), findsNothing, reason: 'the Daily chip waits for 5 pictures');
    expect(c.read(newTabsProvider).contains(Reveal.library.tab), isFalse, reason: 'visited: the dot goes');
    await shot(tester, 'fs_10_library_tip');
    await tapKey(tester, 'tip-library-close', ms: 800);

    // 13. Unlock anyway on Home: a sheet with a check per thing, only the nearest picked; then the
    //     confirmation. First only the daily puzzle, then everything.
    await tapTab(tester, 'Home', ms: 2000);
    await scrollTo(tester, find.byKey(const ValueKey('unlock-anyway')));
    await tapKey(tester, 'unlock-anyway', ms: 1500);
    expect(shown('unlock-picker'), isTrue);
    expect(find.text('Unlock Daily puzzle'), findsOneWidget, reason: 'only the nearest is picked');
    await shot(tester, 'fs_15_unlock_picker');
    await tapKey(tester, 'unlock-picked', ms: 1500);
    expect(find.text('Are you sure?'), findsOneWidget);
    await shot(tester, 'fs_16_unlock_confirm');
    await tester.tap(find.text('Unlock Daily puzzle').last, warnIfMissed: false);
    await settle(tester, 2000);
    expect(c.read(revealsProvider).contains(Reveal.daily), isTrue);
    expect(c.read(revealsProvider).contains(Reveal.streak), isFalse);
    expect(c.read(firstStepsProvider).calm, isTrue);

    await scrollTo(tester, find.byKey(const ValueKey('unlock-anyway')));
    await tapKey(tester, 'unlock-anyway', ms: 1500);
    for (final r in c.read(upcomingRevealsProvider).skip(1)) {
      await tester.ensureVisible(find.byKey(ValueKey('unlock-pick-${r.name}')));
      await tapKey(tester, 'unlock-pick-${r.name}', ms: 300);
    }
    expect(find.text('Unlock everything'), findsOneWidget);
    await tapKey(tester, 'unlock-picked', ms: 1500);
    await tester.tap(find.text('Unlock everything').last, warnIfMissed: false);
    await settle(tester, 2000);
    expect(c.read(firstStepsProvider).calm, isFalse);
    expect(shown('more-to-come'), isFalse);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000));
    await settle(tester, 800);
    await shot(tester, 'fs_14_everything');
  });
}
