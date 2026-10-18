// TestFlight feedback 2026-10-18: the notification question after the second finished picture (asked
// in the game first, a switch per kind, all on, then iOS's real prompt) and Settings > Messages from
// Carden, whose notification tools/dev/inbox.py sends (docs/notifications.md). Drives the real app on
// the live backend as a QA player, from a fresh install so iOS has never asked:
//
//   xcrun simctl uninstall <udid> com.matejbaco.cardjigsawworld
//   tools/dev/qa-run.sh drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/notification_prompt_test.dart -d <udid> [--dart-define=NOTIF_QA_QUIET=true]
//
// The host takes part, keyed on lines this test prints:
//   QA_MARK:system_prompt   iOS's own prompt is up (Flutter can neither see nor tap it): take
//       `xcrun simctl io <udid> screenshot screenshots/np_02_ios_prompt.png` within 25 s. The run then
//       ends with the prompt unanswered; it stays on the simulator (an uninstall does not close it), so
//       reboot the simulator before the next run.
//   QA_MARK:push:<userId>   with NOTIF_QA_QUIET (iOS allows quietly, no prompt): this player turned
//       Messages from Carden on; send it a message within 150 s with
//       `python3 tools/dev/inbox.py send --to <userId> --subject "QA: a message from Carden" --body ... --yes`
//       (it must print "pushed to 1 device(s)"). Its arrival shows a toast in the game.
import 'dart:async';
import 'dart:convert';

import 'package:carden/app.dart';
import 'package:carden/core/app_links.dart';
import 'package:carden/core/reminders.dart';
import 'package:carden/core/sfx.dart';
import 'package:carden/data/local_store.dart';
import 'package:carden/features/game/board_widget.dart';
import 'package:carden/features/game/difficulty_screen.dart';
import 'package:carden/features/game/game_screen.dart';
import 'package:carden/features/links/deep_links.dart';
import 'package:carden/features/notifications/notification_prompt.dart';
import 'package:carden/router.dart';
import 'package:carden/state/auth.dart';
import 'package:carden/state/first_steps.dart';
import 'package:carden/state/inbox.dart';
import 'package:carden/state/push.dart';
import 'package:carden/state/reminders.dart';
import 'package:carden/state/rewards.dart';
import 'package:carden/state/settings.dart';
import 'package:carden/state/unlocks.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ask iOS quietly (provisional: allowed without a prompt), so the run can go on to Settings and a push.
const _quiet = bool.fromEnvironment('NOTIF_QA_QUIET');
const _pushSubject = 'QA: a message from Carden';

Future<void> settle(WidgetTester tester, [int ms = 1500]) async {
  // The app has infinite animations (shimmer, pulses), so pump for a fixed time.
  await tester.pump(const Duration(milliseconds: 50));
  final end = DateTime.now().add(Duration(milliseconds: ms));
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  GameScreen.dealPreview = false;
  // This suite checks the question, which QA runs otherwise never see.
  NotificationPrompt.allowInQaRuns = true;
  ReminderChannel.quietInIntegrationRuns = _quiet;

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

  Future<bool> waitFor(WidgetTester tester, Finder f, {int seconds = 30}) async {
    for (var i = 0; i < seconds * 2; i++) {
      if (f.evaluate().isNotEmpty) return true;
      await settle(tester, 500);
    }
    return f.evaluate().isNotEmpty;
  }

  /// Sends every misplaced card home, one tap-tap move at a time.
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

  /// Home > Quick play > Cozy (3x3) > Play > solved > back to Home.
  Future<void> quickPlay(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('home-quick-play')), warnIfMissed: false);
    await settle(tester, 4000);
    expect(find.byType(DifficultyScreen), findsOneWidget);
    await tester.dragUntilVisible(find.text('Cozy'), find.byType(Scrollable).first, const Offset(0, -200));
    await settle(tester, 600);
    await tapText(tester, 'Cozy');
    await tester.tap(find.byKey(const ValueKey('play-board')), warnIfMissed: false);
    await settle(tester, 6000);
    if (find.text('Got it').evaluate().isNotEmpty) await tapText(tester, 'Got it');
    await solveBoard(tester);
    await settle(tester, 3000);
    expect(find.text('Picture complete'), findsOneWidget);
    // The question never shows over the finish card.
    expect(find.text('Turn on notifications?'), findsNothing);
    await tapText(tester, 'Back to pack', ms: 2500);
    await tapText(tester, 'Home', ms: 2500);
  }

  testWidgets('the notification question after the second picture, and messages from Carden', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    await FirstSteps.skipFor(store); // the whole app; integration_test/first_steps_test.dart plays the first steps
    Sfx.instance.soundEnabled = false;
    Sfx.instance.musicEnabled = false;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        openFeaturesProvider.overrideWithValue(OpenFeatures.all),
        pendingUnlockIntroProvider.overrideWithValue(null),
      ],
      child: const CardenApp(),
    ));
    await settle(tester, 1500);
    await tapText(tester, 'Continue');
    await tapText(tester, 'Continue');
    await tapText(tester, 'Start playing', ms: 5000);
    await settle(tester, 5000);
    final c = container(tester);
    expect(await ReminderChannel.status(), ReminderPermission.notDetermined, reason: 'a fresh install: iOS has never asked');

    // The first picture: not yet.
    await quickPlay(tester);
    await settle(tester, 9000);
    expect(find.text('Turn on notifications?'), findsNothing, reason: 'asked after the second picture');
    await shot(tester, 'np_00_home_after_first');

    // The second: back on Home, a calm moment, the question.
    await quickPlay(tester);
    final asked = await waitFor(tester, find.text('Turn on notifications?'), seconds: 25);
    if (!asked) {
      // What the host saw, for the log.
      Route<dynamic>? top;
      rootNavigatorKey.currentState?.popUntil((r) {
        top = r;
        return true;
      });
      debugPrint('QA_DIAG solved=${c.read(solvedCountProvider)} decision=${c.read(notificationPromptProvider)} '
          'path=${c.read(routerProvider).state.uri.path} top=${top.runtimeType} settings=${top?.settings.runtimeType} '
          'current=${top?.isCurrent} lifecycle=${WidgetsBinding.instance.lifecycleState} permission=${await ReminderChannel.status()} '
          'asked=${NotificationPrompt.askedBefore(store)} last look: ${NotificationPromptHost.debugLastLook}');
      await shot(tester, 'np_01_missing');
    }
    expect(asked, isTrue, reason: 'the question on Home after the second picture');
    await settle(tester, 1200);
    await shot(tester, 'np_01_prompt');
    for (final kind in ['daily', 'events', 'gifts', 'messages']) {
      final toggle = find.descendant(of: find.byKey(ValueKey('notification-prompt-$kind')), matching: find.byType(CupertinoSwitch));
      expect(tester.widget<CupertinoSwitch>(toggle).value, isTrue, reason: '$kind starts on');
    }

    await tester.tap(find.byKey(const ValueKey('notification-prompt-allow')), warnIfMissed: false);
    await settle(tester, 1500);
    expect(c.read(notificationPromptProvider), 'allowed');
    expect(c.read(eventRemindersProvider), isTrue);
    expect(c.read(messageNotificationsProvider), isTrue);
    expect(c.read(giftNotificationsProvider), isTrue);

    if (!_quiet) {
      // iOS's own prompt is up: the host takes the screenshot. The run ends with it unanswered.
      debugPrint('QA_MARK:system_prompt');
      await settle(tester, 25000);
      return;
    }

    // Quietly allowed: the reminders are planned and the iPhone is registered for messages.
    await settle(tester, 6000);
    expect(await ReminderChannel.status(), ReminderPermission.granted);
    expect(c.read(settingsProvider).reminders, isTrue);
    await shot(tester, 'np_02_allowed');
    final saved = store.getJson('pushTarget');
    debugPrint('QA_PUSH_TARGET ${jsonEncode(saved)}');
    expect(saved?['topics'], contains(PushTopics.messages), reason: 'the target is in the topic inbox.py pushes to');

    // Settings > Notifications: the four switches the question set.
    await tapText(tester, 'Profile', ms: 2500);
    await tester.tap(find.byIcon(CupertinoIcons.gear_alt_fill).first, warnIfMissed: false);
    await settle(tester, 2000);
    final messagesRow = find.byKey(const ValueKey('settings-message-notifications'));
    await tester.dragUntilVisible(messagesRow, find.byType(Scrollable).first, const Offset(0, -150));
    await Scrollable.ensureVisible(tester.element(find.byKey(const ValueKey('settings-reminders'))), alignment: 0.15);
    await settle(tester, 1200);
    await shot(tester, 'np_03_settings');
    for (final key in ['settings-reminders', 'settings-event-reminders', 'settings-gift-notifications', 'settings-message-notifications']) {
      final toggle = find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(CupertinoSwitch));
      expect(tester.widget<CupertinoSwitch>(toggle).value, isTrue, reason: '$key on');
    }
    await tester.tap(find.byIcon(CupertinoIcons.back).first, warnIfMissed: false);
    await settle(tester, 1500);
    await tapText(tester, 'Home', ms: 2000);

    // A message from Carden, pushed by the host: Apple's sandbox delivers it, and with the game open
    // it shows as a toast (no banner) and the inbox reloads.
    debugPrint('QA_MARK:push:${c.read(currentUserIdProvider)}');
    final toast = find.text(_pushSubject);
    expect(await waitFor(tester, toast, seconds: 150), isTrue, reason: 'the pushed message arrived');
    await binding.takeScreenshot('np_04_push_toast');
    await settle(tester, 3000);
    final messages = await c.read(inboxMessagesProvider.future);
    final m = messages.firstWhere((m) => m.subject == _pushSubject);
    // The tap on the notification opens its link.
    unawaited(c.read(deepLinksProvider).show(AppLink.parse(Uri.parse('/inbox?message=${m.id}&from=carden'))!));
    await settle(tester, 4000);
    await shot(tester, 'np_05_message');
    expect(find.text(_pushSubject), findsWidgets);
    debugPrint('QA_MESSAGE_ID ${m.id}');
  });
}
