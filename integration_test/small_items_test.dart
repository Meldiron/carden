// Small items of 2026-10-14 on the real app (live Appwrite backend): a second-day daily gift with no
// question after it (since 2026-10-18 the one notification question comes after the second picture:
// integration_test/notification_prompt_test.dart), tomorrow's blurred daily puzzle on Home, the Lucky Wheel
// odds, Library search over picture titles, the New filter, and Settings (Rate, version).
//
// Run: tools/dev/qa-run.sh drive --driver=test_driver/integration_test.dart \
//        --target=integration_test/small_items_test.dart -d <simulator>
//
// When no pack has been added since the launch catalogue, the test marks one library pack as
// New on this device only, so the badge and the filter can still be looked at
// (`si_08_new_filter_simulated`).
import 'package:carden/app.dart';
import 'package:carden/core/appwrite.dart';
import 'package:carden/core/sfx.dart';
import 'package:carden/data/local_store.dart';
import 'package:carden/features/game/board_widget.dart';
import 'package:carden/features/game/game_screen.dart';
import 'package:carden/models/models.dart';
import 'package:carden/state/catalog.dart';
import 'package:carden/state/first_steps.dart';
import 'package:carden/state/settings.dart';
import 'package:carden/state/rewards.dart';
import 'package:carden/state/unlocks.dart';
import 'package:flutter/cupertino.dart';
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

/// Whether the test had to mark a pack New itself (no real new pack in the catalogue).
var simulatedNew = false;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  // Boards here are played the moment they show: no picture before the deal (GameScreen.dealPreview).
  GameScreen.dealPreview = false;

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

  TextEditingController search(WidgetTester tester) => tester.widget<CupertinoSearchTextField>(find.byKey(const ValueKey('library-search'))).controller!;

  ProviderContainer container(WidgetTester tester) => ProviderScope.containerOf(tester.element(find.byType(CardenApp)));

  Future<void> solveBoard(WidgetTester tester) async {
    for (var guard = 0; guard < 80; guard++) {
      final bf = find.byType(BoardWidget);
      if (bf.evaluate().isEmpty) return;
      final board = tester.widget<BoardWidget>(bf.first).state.board;
      if (board.isSolved) return;
      final rect = tester.getRect(bf.first);
      Offset center(int slot) => rect.topLeft + board.tiling.cellCenter(slot, rect.size);
      final slot = List.generate(board.cells, (i) => i).firstWhere((i) => !board.isLocked(i));
      await tester.tapAt(center(slot));
      await settle(tester, 250);
      await tester.tapAt(center(board.homeOf(slot)));
      await settle(tester, 450);
    }
  }

  testWidgets('small items', (tester) async {
    // One daily gift claimed on an earlier day: today's claim is the second day.
    SharedPreferences.setMockInitialValues({'giftClaimDays': 1});
    final store = await LocalStore.open();
    await FirstSteps.skipFor(store); // the whole app; integration_test/first_steps_test.dart plays the first steps
    Sfx.instance.soundEnabled = false;
    Sfx.instance.musicEnabled = false;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        // Shapes and options open as levels rise (lib/state/unlocks.dart); these suites play every one, so all are open and no intro sheet interrupts them.
        openFeaturesProvider.overrideWithValue(OpenFeatures.all),
        pendingUnlockIntroProvider.overrideWithValue(null),
        packsProvider.overrideWith((ref) async {
          final rows = await ref.watch(packRowsProvider.future);
          final now = DateTime.now();
          final list = rows.where((p) => p.isReleasedAt(now)).toList();
          if (list.any((p) => p.isNewAt(now))) return list;
          // No real new pack yet: mark the first library pack New on this device only.
          final raw = (await ref.watch(catalogProvider.future))[AppwriteConfig.packs]!;
          final i = list.indexWhere((p) => !p.isDaily && !p.hasWindow);
          if (i < 0) return list;
          final row = raw.firstWhere((r) => r[r'$id'] == list[i].id);
          simulatedNew = true;
          return [...list]..[i] = Pack.fromRow(list[i].id, {...row, r'$createdAt': now.toUtc().toIso8601String()});
        }),
      ],
      child: const CardenApp(),
    ));
    await settle(tester, 1500);
    await tapText(tester, 'Continue');
    await tapText(tester, 'Continue');
    await tapText(tester, 'Start playing', ms: 5000);
    await settle(tester, 5000);

    // Daily gift on the second day: no reminder question after it any more.
    await tapText(tester, 'Claim', ms: 1500);
    await tester.tap(find.textContaining('Claim day'), warnIfMissed: false);
    await settle(tester, 1500);
    await tester.tapAt(const Offset(200, 60));
    await settle(tester, 2500);
    expect(find.text('Get a daily reminder?'), findsNothing);
    expect(container(tester).read(settingsProvider).reminders, isFalse);
    await shot(tester, 'si_01_after_daily_gift');

    // Today's daily puzzle, solved: Home's Today card says when the new picture comes.
    expect(find.textContaining('New picture in'), findsNothing);
    await tester.tap(find.textContaining('bonus today'), warnIfMissed: false);
    await settle(tester, 4000);
    await tester.dragUntilVisible(find.text('Cozy'), find.byType(Scrollable).first, const Offset(0, -200));
    await settle(tester, 600);
    await tapText(tester, 'Cozy');
    await tester.tap(find.byKey(const ValueKey('play-board')), warnIfMissed: false);
    await settle(tester, 6000);
    if (find.text('Got it').evaluate().isNotEmpty) await tapText(tester, 'Got it');
    await solveBoard(tester);
    await settle(tester, 3000);
    expect(find.text('Picture complete'), findsOneWidget);
    await tapText(tester, 'Back to pack', ms: 2500);
    await tapText(tester, 'Home', ms: 3000);
    expect(find.textContaining('New picture in'), findsOneWidget);
    expect(find.text("Tomorrow's daily puzzle"), findsNothing, reason: 'the row is gone (owner, 2026-10-17)');
    await shot(tester, 'si_03_home_new_picture');

    // Lucky Wheel odds.
    await tapText(tester, 'Lucky Wheel', ms: 1800);
    await shot(tester, 'si_04_wheel');
    await tapText(tester, 'See odds', ms: 1500);
    expect(find.text('Lucky Wheel odds'), findsOneWidget);
    // The 1,000-coin jackpot at 1%, 3 Magic at 2% (owner, 2026-10-15).
    expect(find.text('1%'), findsOneWidget);
    expect(find.text('2%'), findsOneWidget);
    expect(find.text('Peeks'), findsNWidgets(2));
    await shot(tester, 'si_05_wheel_odds');
    await tester.tapAt(const Offset(200, 60));
    await settle(tester, 900);
    await tester.tap(find.byIcon(CupertinoIcons.xmark).first, warnIfMissed: false);
    await settle(tester, 1200);

    // Library: search finds picture titles too.
    await tapText(tester, 'Library', ms: 3000);
    await tester.enterText(find.byKey(const ValueKey('library-search')), 'owl');
    await settle(tester, 1500);
    await shot(tester, 'si_06_search_packs');
    // The Pictures section follows the matching packs; slivers below the fold are not built yet.
    final libraryScroll = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first;
    await tester.dragUntilVisible(find.byKey(const ValueKey('library-pictures')), libraryScroll, const Offset(0, -300));
    await settle(tester, 800);
    expect(find.byKey(const ValueKey('library-pictures')), findsOneWidget);
    await shot(tester, 'si_06b_search_pictures');
    await tester.fling(libraryScroll, const Offset(0, 3000), 3000);
    await settle(tester, 1200);
    // The keyboard closes on scroll; set the query on the field itself.
    search(tester).text = 'great grey owl';
    await settle(tester, 1500);
    await shot(tester, 'si_06c_search_one_picture');
    final row = find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('library-picture-'));
    expect(row, findsWidgets);
    await tester.tap(row.first, warnIfMissed: false);
    await settle(tester, 4000);
    await shot(tester, 'si_07_search_opened');
    await tester.tap(find.byIcon(CupertinoIcons.back).first, warnIfMissed: false);
    await settle(tester, 1500);
    await tester.fling(libraryScroll, const Offset(0, 3000), 3000);
    await settle(tester, 1000);
    search(tester).text = '';
    await settle(tester, 1200);

    // New filter and badge.
    final newChip = find.byKey(const ValueKey('library-chip-New'));
    expect(newChip, findsOneWidget);
    await tester.tap(newChip, warnIfMissed: false);
    await settle(tester, 2500);
    expect(find.byKey(const ValueKey('pack-new')), findsWidgets);
    await shot(tester, simulatedNew ? 'si_08_new_filter_simulated' : 'si_08_new_filter');
    await tapText(tester, 'All', ms: 1200);

    // Settings: Rate and the real version.
    await tapText(tester, 'Profile', ms: 2500);
    await tester.tap(find.byIcon(CupertinoIcons.gear_alt_fill).first, warnIfMissed: false);
    await settle(tester, 1500);
    await tester.dragUntilVisible(find.byKey(const ValueKey('settings-version')), find.byType(Scrollable).first, const Offset(0, -300));
    await settle(tester, 1200);
    expect(find.text('Rate Carden'), findsOneWidget);
    expect(find.textContaining(RegExp(r'^\d+\.\d+\.\d+ \(\d+\)$')), findsOneWidget);
    expect(find.text('1.6.0 (9)'), findsNothing);
    await shot(tester, 'si_09_settings_about');
  }, timeout: const Timeout(Duration(minutes: 8)));
}
