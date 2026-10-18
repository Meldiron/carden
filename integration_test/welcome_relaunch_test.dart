// The welcome pages once, and the first steps' short hints (owner, TestFlight 2026-10-18). Two runs of
// the real app on the simulator's own preferences (no mock store): the first swipes through the
// welcome, skips it and starts the first board; the second, without uninstalling, is a real relaunch
// that must start past the welcome, and shows the hints and locked cards.
//
//   xcrun simctl uninstall <udid> com.matejbaco.cardjigsawworld
//   QA_KEEP=1 tools/dev/qa-run.sh drive --keep-app-running --driver=test_driver/integration_test.dart \
//     --target=integration_test/welcome_relaunch_test.dart -d <udid> --dart-define=CJW_RELAUNCH=skip
//   tools/dev/qa-run.sh drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/welcome_relaunch_test.dart -d <udid> --dart-define=CJW_RELAUNCH=check
//
// (`--keep-app-running` keeps the app installed: `flutter drive` otherwise uninstalls it, and its
// preferences with it. The second run marks the same guest with its own run id and purges it.)
//
// Screenshots `wr_*`. Builds up to 127 kept the catalogue (11 MB) in SharedPreferences, over the 4 MB
// iOS allows for an app's preferences, so on an iPhone none of them were saved and the welcome came
// back at every launch; the first run also checks that the catalogue stays out of them.
import 'package:carden/app.dart';
import 'package:carden/core/sfx.dart';
import 'package:carden/data/local_store.dart';
import 'package:carden/features/events/events_screen.dart';
import 'package:carden/features/game/board_widget.dart';
import 'package:carden/features/game/game_screen.dart';
import 'package:carden/features/home/home_screen.dart';
import 'package:carden/features/onboarding/onboarding_screen.dart';
import 'package:carden/router.dart';
import 'package:carden/state/catalog.dart';
import 'package:carden/state/first_steps.dart';
import 'package:carden/state/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _phase = String.fromEnvironment('CJW_RELAUNCH', defaultValue: 'skip');

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

  Future<void> shot(WidgetTester tester, String name, [int ms = 300]) async {
    await settle(tester, ms);
    await binding.takeScreenshot(name);
  }

  ProviderContainer container(WidgetTester tester) => ProviderScope.containerOf(tester.element(find.byType(CardenApp)));
  BoardWidget board(WidgetTester tester) => tester.widget<BoardWidget>(find.byType(BoardWidget).first);
  bool shown(String key) => find.byKey(ValueKey(key)).evaluate().isNotEmpty;

  Offset onScreen(WidgetTester tester, int slot) {
    final w = board(tester);
    final rect = tester.getRect(find.byType(BoardWidget).first);
    return rect.topLeft + w.state.board.tiling.cellCenter(slot, Size(w.width, w.height));
  }

  Future<void> tapTab(WidgetTester tester, String label) async {
    await tester.tap(find.text(label).last, warnIfMissed: false);
    await settle(tester, 1800);
  }

  testWidgets('welcome pages: skipped once, never again ($_phase)', (tester) async {
    Sfx.instance.soundEnabled = false;
    Sfx.instance.musicEnabled = false;
    // The real store, as main() opens it: what the first run saved is on disk for the second.
    final prefs = await SharedPreferences.getInstance();
    if (_phase == 'skip') await prefs.clear();
    final store = LocalStore(prefs);
    debugPrint('relaunch[$_phase]: onboarded=${prefs.getBool('onboarded')} catalog=${prefs.getString('catalog')?.length} keys=${prefs.getKeys()}');
    await tester.pumpWidget(ProviderScope(overrides: [localStoreProvider.overrideWithValue(store)], child: const CardenApp()));
    await settle(tester, 2500);
    final c = container(tester);

    if (_phase == 'skip') {
      expect(find.byType(OnboardingScreen), findsOneWidget, reason: 'a fresh install starts on the welcome pages');
      // The catalogue arrives and is kept on the device while the player reads page 1.
      await c.read(allPuzzlesProvider.future).timeout(const Duration(seconds: 60));
      await settle(tester, 3000);
      expect(prefs.getString('catalog'), isNull, reason: 'the catalogue is kept in a file, never in the preferences');
      await shot(tester, 'wr_01_welcome');

      // Page 2: the lock is for good.
      await tester.tap(find.text('Continue').first, warnIfMissed: false);
      await settle(tester, 1200);
      expect(find.textContaining('locks into the picture for good'), findsOneWidget);
      await shot(tester, 'wr_02_page2');

      // A finger halfway to the last page, then most of the way: the buttons follow it.
      final pager = find.byType(PageView);
      final width = tester.getSize(pager).width;
      final finger = await tester.startGesture(tester.getCenter(pager));
      await finger.moveBy(const Offset(-24, 0));
      await tester.pump();
      await finger.moveBy(Offset(-width * 0.5, 0));
      await shot(tester, 'wr_03_swipe_half');
      expect(find.text('Continue'), findsOneWidget);
      expect(find.text('Start playing'), findsOneWidget, reason: 'the labels cross-fade with the swipe');
      await finger.moveBy(Offset(-width * 0.25, 0));
      await shot(tester, 'wr_04_swipe_more');
      await finger.up();
      await settle(tester, 1200);
      expect(find.text('Continue'), findsNothing);
      await shot(tester, 'wr_05_last');

      // Back to page 1 and Skip, as the owner did.
      tester.widget<PageView>(pager).controller!.jumpToPage(0);
      await settle(tester, 800);
      await tester.tap(find.byKey(const ValueKey('welcome-skip')), warnIfMissed: false);
      expect(prefs.getBool('onboarded'), isTrue, reason: 'saved at the tap');
      await settle(tester, 6000);
      expect(find.byType(OnboardingScreen), findsNothing);
      expect(find.byType(GameScreen), findsOneWidget, reason: 'Skip leads into the first board too');
      await shot(tester, 'wr_06_first_board');

      // The first board's hints: pick, then place, then the lock.
      final b = board(tester).state.board;
      final slot = List.generate(b.cells, (i) => i).firstWhere((i) => !b.isLocked(i));
      await tester.tapAt(onScreen(tester, slot));
      await settle(tester, 800);
      expect(shown('coach-place'), isTrue);
      await shot(tester, 'wr_07_coach_place');
      await tester.tapAt(onScreen(tester, b.homeOf(slot)));
      await settle(tester, 900);
      expect(shown('coach-locked') || shown('coach-joined'), isTrue);
      await shot(tester, 'wr_08_coach_locked');
      debugPrint('relaunch[skip]: onboarded=${prefs.getBool('onboarded')} catalog=${prefs.getString('catalog')?.length} keys=${prefs.getKeys()}');
      // The player leaves the app here, the board half done. Time for the system to save.
      await settle(tester, 4000);
    } else {
      expect(prefs.getBool('onboarded'), isTrue, reason: 'the skip of the first run was kept on disk');
      expect(find.byType(OnboardingScreen), findsNothing, reason: 'a relaunch after Skip never shows the welcome again');
      expect(find.byType(HomeScreen), findsOneWidget, reason: 'Home, where the first board waits under Continue');
      await shot(tester, 'wr_10_relaunch_home', 2000);

      // Home's list of what is still to come.
      await tester.scrollUntilVisible(find.byKey(const ValueKey('unlock-anyway')), 300, scrollable: find.byType(Scrollable).first);
      await shot(tester, 'wr_11_more_to_come', 800);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000));
      await settle(tester, 600);

      // Profile: achievements locked, one line each.
      await tapTab(tester, 'Profile');
      await tester.scrollUntilVisible(find.byKey(const ValueKey('locked-achievements')), 300, scrollable: find.byType(Scrollable).first);
      await shot(tester, 'wr_12_locked_achievements', 800);

      // Quests opened early: live events locked.
      c.read(firstStepsProvider.notifier).openEarly(Reveal.quests);
      c.read(routerProvider).go('/events');
      await settle(tester, 2500);
      await tester.scrollUntilVisible(find.byKey(const ValueKey('locked-liveEvents')), 300, scrollable: find.descendant(of: find.byType(EventsScreen), matching: find.byType(Scrollable)).first);
      await shot(tester, 'wr_13_locked_live_events', 800);

      // The Library opened early: its tip.
      c.read(firstStepsProvider.notifier).openEarly(Reveal.library);
      c.read(routerProvider).go('/library');
      await settle(tester, 2500);
      expect(shown('tip-library'), isTrue);
      await shot(tester, 'wr_14_library_tip', 1500);

      // The board picker of a picture not yet played: its tip.
      final pick = c.read(allPuzzlesProvider).value!.firstWhere((z) => z.packId == firstBoardPack && z.id != firstBoardPuzzle);
      c.read(routerProvider).push('/play/${pick.id}');
      await settle(tester, 3000);
      expect(shown('tip-board'), isTrue);
      await shot(tester, 'wr_15_board_tip', 1500);
      expect(c.read(settingsProvider).onboarded, isTrue);
    }
  });
}
