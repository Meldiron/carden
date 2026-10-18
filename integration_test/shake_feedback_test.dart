// Shake to send feedback (TestFlight feedback AD2vI9mqyY_OfTc3X7SyHJA, owner 2026-10-18) on the
// simulator: a fresh guest's first board, a real shake of the simulator, Send feedback over the board;
// with Settings > Help > Shake to send feedback off, a shake opens nothing.
//
//   tools/dev/qa-run.sh drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/shake_feedback_test.dart -d <simulator>
// When the app logs QA_SHAKE_NOW or QA_SHAKE_OFF_NOW, shake the simulator: Device > Shake, or
//   xcrun simctl spawn <simulator> notifyutil -p com.apple.UIKit.SimulatorShake
import 'package:carden/app.dart';
import 'package:carden/core/sfx.dart';
import 'package:carden/data/local_store.dart';
import 'package:carden/features/game/game_screen.dart';
import 'package:carden/features/profile/help.dart';
import 'package:carden/features/profile/shake_feedback.dart';
import 'package:carden/router.dart';
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

  bool feedbackOpen() => find.byType(FeedbackPanel).evaluate().isNotEmpty;

  testWidgets('a shake opens Send feedback over the board; with the switch off, nothing', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    Sfx.instance.soundEnabled = false;
    Sfx.instance.musicEnabled = false;
    await tester.pumpWidget(ProviderScope(overrides: [localStoreProvider.overrideWithValue(store)], child: const CardenApp()));
    await settle(tester, 1500);
    await tapText(tester, 'Continue');
    await tapText(tester, 'Continue');
    await tapText(tester, 'Start playing', ms: 3000);
    await settle(tester, 4000);
    expect(find.byType(GameScreen), findsOneWidget, reason: 'the first board');
    final c = ProviderScope.containerOf(tester.element(find.byType(CardenApp)));

    debugPrint('QA_SHAKE_NOW');
    for (var i = 0; i < 60 && !feedbackOpen(); i++) {
      await settle(tester, 1000);
    }
    expect(feedbackOpen(), isTrue, reason: 'a shake opens Send feedback over the game');
    expect(find.byType(GameScreen), findsOneWidget, reason: 'the board stays under the sheet');
    await settle(tester, 1500);
    await shot(tester, 'shake_01_feedback_over_board');
    debugPrint('QA_SHAKE_DONE');
    rootNavigatorKey.currentState!.pop();
    await settle(tester, 1500);
    expect(feedbackOpen(), isFalse);

    // Settings > Help > Shake to send feedback off: shakes open nothing.
    c.read(shakeFeedbackProvider.notifier).set(false);
    debugPrint('QA_SHAKE_OFF_NOW');
    await settle(tester, 25000);
    expect(feedbackOpen(), isFalse, reason: 'the switch is off');
    await shot(tester, 'shake_02_off_nothing');
    debugPrint('QA_SHAKE_OFF_DONE');
  }, timeout: const Timeout(Duration(minutes: 6)));
}
