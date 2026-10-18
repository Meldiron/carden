// A new player's first board and the save sync (TestFlight feedback AL2POUherU5EVWc4K0Q1iYU, owner
// 2026-10-18): a fresh guest plays the guided first board and lands on Home; the "Synced from
// another device" alert must not appear for this device's own play, on Home, after a resume or after
// a restart of the sync.
//
//   tools/dev/qa-run.sh drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/first_board_sync_test.dart -d <simulator>
import 'package:carden/app.dart';
import 'package:carden/core/sfx.dart';
import 'package:carden/data/local_store.dart';
import 'package:carden/data/sync/device_copy.dart';
import 'package:carden/features/game/board_widget.dart';
import 'package:carden/features/game/game_screen.dart';
import 'package:carden/state/settings.dart';
import 'package:carden/state/sync.dart';
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

  ProviderContainer container(WidgetTester tester) => ProviderScope.containerOf(tester.element(find.byType(CardenApp)));
  BoardWidget board(WidgetTester tester) => tester.widget<BoardWidget>(find.byType(BoardWidget).first);

  Offset onScreen(WidgetTester tester, int slot) {
    final w = board(tester);
    final rect = tester.getRect(find.byType(BoardWidget).first);
    return rect.topLeft + w.state.board.tiling.cellCenter(slot, Size(w.width, w.height));
  }

  Future<void> solve(WidgetTester tester) async {
    for (var guard = 0; guard < 80; guard++) {
      final b = board(tester).state.board;
      if (b.isSolved) return;
      final slot = List.generate(b.cells, (i) => i).firstWhere((i) => !b.isLocked(i));
      await tester.tapAt(onScreen(tester, slot));
      await settle(tester, 350);
      await tester.tapAt(onScreen(tester, b.homeOf(slot)));
      await settle(tester, 600);
    }
  }

  bool alert() => find.text('Synced from another device').evaluate().isNotEmpty;

  testWidgets('a fresh guest finishes the first board: no "Synced from another device"', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    // The iPhone's own store for the sync's copy of the rows: a file per player (main.dart).
    final rows = await openSyncRows(store);
    Sfx.instance.soundEnabled = false;
    Sfx.instance.musicEnabled = false;
    await tester.pumpWidget(ProviderScope(overrides: [localStoreProvider.overrideWithValue(store), syncRowsProvider.overrideWithValue(rows)], child: const CardenApp()));
    await settle(tester, 1500);
    await tapText(tester, 'Continue');
    await tapText(tester, 'Continue');
    await tapText(tester, 'Start playing', ms: 3000);
    await settle(tester, 3000);
    expect(find.byType(GameScreen), findsOneWidget, reason: 'the welcome pages lead into the first board');
    final c = container(tester);

    await solve(tester);
    await settle(tester, 4000);
    await tester.tap(find.byKey(const ValueKey('completion-back')).first, warnIfMissed: false);
    await settle(tester, 6000);
    expect(find.byType(GameScreen), findsNothing);
    await shot(tester, 'fbs_01_home');
    debugPrint('SYNCPROBE home notice=${c.read(syncNoticeProvider)} alert=${alert()}');
    expect(alert(), isFalse, reason: "this device's own first board is not news from another device");

    // Back from the background: a read of the save, still nothing to tell.
    final sync = c.read(syncProvider.notifier);
    sync.onPause();
    await settle(tester, 500);
    sync.onResume();
    await sync.sync();
    await settle(tester, 4000);
    await shot(tester, 'fbs_02_after_resume');
    debugPrint('SYNCPROBE resume notice=${c.read(syncNoticeProvider)} alert=${alert()}');
    expect(alert(), isFalse);
    expect(c.read(syncProvider).pending, 0, reason: 'everything sent');

    // The copy of the rows is a file, not a SharedPreferences value (NSUserDefaults stops at 4 MB).
    final me = c.read(syncProvider).userId!;
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
    expect(store.getJson('sync.v1.$me.rows'), isNull);
    final copy = rows.read(me)!;
    final solved = (copy['progress'] as Map).values.where((r) => (r as Map)['completed'] == true);
    debugPrint('SYNCPROBE device copy: ${rows.runtimeType}, ${(copy['progress'] as Map).length} rows, coins ${(copy['profile'] as Map)['coins']}');
    expect(rows.runtimeType.toString(), 'FileSyncRows');
    expect(solved, hasLength(1));
  });
}
