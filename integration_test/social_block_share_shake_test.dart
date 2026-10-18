// TestFlight feedback 2026-10-18 on the real app (live Appwrite, a QA guest):
// - AJhAN2r4m1ttgfQ1iTQIYiU: blocking a player from their profile goes back to the list they came
//   from, with a "Blocked <name>" toast; Settings > Blocked players unblocks them again.
// - AD2vI9mqyY_OfTc3X7SyHJA: a shake of the iPhone on Home opens Send feedback.
// - ABL5vmG1UgNFRNAPJvaSmGY: Social > Friends > Share opens the iOS share sheet (last: it stays up).
//
// The friend to block comes from outside the app, a QA player in the same run (purged with it):
//   QA_KEEP=1 tools/dev/qa-run.sh drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/social_block_share_shake_test.dart -d <simulator>
//   python3 tools/dev/gift_qa.py befriend-run --run <that run id>     (makes "Carol QA", befriends the guest)
// When the app logs QA_SHAKE_NOW, shake the simulator (Device > Shake, or
//   xcrun simctl spawn <simulator> notifyutil -p com.apple.UIKit.SimulatorShake);
// when it logs QA_SHARE_UP, capture the share sheet from the host (xcrun simctl io <simulator> screenshot).
// Afterwards: gift_qa.py end, then purge_test_players.py purge --run <run id> --apply.
import 'package:carden/app.dart';
import 'package:carden/core/sfx.dart';
import 'package:carden/data/local_store.dart';
import 'package:carden/features/profile/help.dart';
import 'package:carden/features/social/player_safety.dart';
import 'package:carden/features/social/player_screen.dart';
import 'package:carden/features/social/social_screen.dart';
import 'package:carden/router.dart';
import 'package:carden/state/first_steps.dart';
import 'package:carden/state/rewards.dart';
import 'package:carden/state/settings.dart';
import 'package:carden/state/social.dart';
import 'package:carden/state/unlocks.dart';
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

  Future<void> tapText(WidgetTester tester, String text, {int ms = 1200, bool last = false}) async {
    final f = find.text(text);
    expect(f, findsWidgets, reason: 'expected "$text" on screen');
    await tester.tap(last ? f.last : f.first, warnIfMissed: false);
    await settle(tester, ms);
  }

  Future<void> tapKey(WidgetTester tester, String key, {int ms = 1200}) async {
    final f = find.byKey(ValueKey(key));
    expect(f, findsOneWidget, reason: 'expected $key on screen');
    await tester.tap(f, warnIfMissed: false);
    await settle(tester, ms);
  }

  testWidgets('block goes back to Friends, a shake opens feedback, Share opens the share sheet', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    await FirstSteps.skipFor(store);
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
    await settle(tester, 3000);
    final c = ProviderScope.containerOf(tester.element(find.byType(CardenApp)));
    final router = c.read(routerProvider);
    debugPrint('QA_WAITING_FOR_FRIEND');

    // ---- A friend from outside the app (gift_qa.py befriend-run), up to 4 minutes.
    var friend = '';
    for (var i = 0; i < 80 && friend.isEmpty; i++) {
      c.invalidate(friendsProvider);
      try {
        final list = await c.read(friendsProvider.future);
        if (list.isNotEmpty) friend = list.first.name;
      } catch (_) {}
      if (friend.isEmpty) await settle(tester, 3000);
    }
    expect(friend, isNotEmpty, reason: 'run gift_qa.py befriend-run for this run');
    debugPrint('QA_FRIEND $friend');

    // ---- Social > Friends > the friend's profile > ... > Block > Block: back on Friends.
    router.go('/social');
    await settle(tester, 2000);
    c.read(socialTabProvider.notifier).select(SocialTab.friends);
    c.invalidate(friendsProvider);
    await settle(tester, 2500);
    await shot(tester, 'ssb_01_friends');
    await tapText(tester, friend, ms: 3500);
    expect(find.byType(PlayerScreen), findsOneWidget);
    await tapKey(tester, 'player-more', ms: 800);
    await tapKey(tester, 'player-block');
    expect(find.text('Block $friend?'), findsOneWidget);
    await shot(tester, 'ssb_02_block_alert');
    await tapText(tester, 'Block', last: true, ms: 600);
    expect(find.text('Blocked $friend'), findsOneWidget, reason: 'the toast says so');
    await settle(tester, 1500);
    expect(find.byType(PlayerScreen), findsNothing, reason: 'the profile closed after the block');
    expect(router.state.uri.path, '/social');
    await shot(tester, 'ssb_03_back_on_friends');
    expect((await c.read(blockedPlayersProvider.future)).map((b) => b.name), contains(friend));

    // ---- Settings: the Help area has the shake switch, on by default.
    router.go('/profile/settings');
    await settle(tester, 2500);
    final settings = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first;
    await tester.dragUntilVisible(find.byKey(const ValueKey('settings-shake-feedback')), settings, const Offset(0, -250));
    await settle(tester, 800);
    await shot(tester, 'ssb_04_settings_help');

    // ---- Settings > Blocked players > Unblock: the QA friend leaves no block behind.
    showBlockedPlayersSheet(rootNavigatorKey.currentContext!);
    final unblock = find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('unblock-'));
    for (var i = 0; i < 20 && unblock.evaluate().isEmpty; i++) {
      await settle(tester, 500);
    }
    await shot(tester, 'ssb_03b_blocked_players');
    await tester.tap(unblock.first, warnIfMissed: false);
    await settle(tester, 3000);
    expect(find.byKey(const ValueKey('blocked-empty')), findsOneWidget);
    rootNavigatorKey.currentState!.pop();
    await settle(tester, 1000);

    // ---- Home, then a shake of the simulator from the host: Send feedback over Home.
    router.go('/home');
    await settle(tester, 2500);
    debugPrint('QA_SHAKE_NOW');
    for (var i = 0; i < 60 && find.byType(FeedbackPanel).evaluate().isEmpty; i++) {
      await settle(tester, 1000);
    }
    expect(find.byType(FeedbackPanel), findsOneWidget, reason: 'a shake opens Send feedback');
    await settle(tester, 1200);
    await shot(tester, 'ssb_05_shake_feedback');
    debugPrint('QA_SHAKE_DONE');
    rootNavigatorKey.currentState!.pop();
    await settle(tester, 1200);

    // ---- Social > Friends > Share: the iOS share sheet (native: captured from the host).
    router.go('/social');
    await settle(tester, 2000);
    c.read(socialTabProvider.notifier).select(SocialTab.friends);
    await settle(tester, 1500);
    expect(find.text('Share'), findsOneWidget);
    expect(find.text('Copy link'), findsNothing);
    await shot(tester, 'ssb_06_invite_share');
    await tapKey(tester, 'share-invite', ms: 3000);
    debugPrint('QA_SHARE_UP');
    await settle(tester, 15000);
  }, timeout: const Timeout(Duration(minutes: 10)));
}
