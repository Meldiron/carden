// Report and block on the real app (live Appwrite backend, guideline 1.2), the links Apple asks
// for (privacy policy, terms of use), and account deletion taking the reports and blocks along.
// A new player reports the league's top player (the row is private: the player cannot read it
// back), blocks them (gone from the leaderboard, Unblock in their page's menu), unblocks them in Settings >
// Blocked players, blocks again and deletes the account. The run prints QA_SAFETY_USER <id>; the
// host then checks that no report or block of that id is left (see the end of this file).
//
// Run: tools/dev/qa-run.sh drive --driver=test_driver/integration_test.dart \
//        --target=integration_test/player_safety_test.dart -d <simulator>
import 'package:appwrite/appwrite.dart';
import 'package:carden/app.dart';
import 'package:carden/core/appwrite.dart';
import 'package:carden/core/sfx.dart';
import 'package:carden/data/local_store.dart';
import 'package:carden/features/onboarding/onboarding_screen.dart';
import 'package:carden/features/social/player_screen.dart';
import 'package:carden/router.dart';
import 'package:carden/widgets/icons.dart';
import 'package:carden/state/auth.dart';
import 'package:carden/state/first_steps.dart';
import 'package:carden/state/rewards.dart';
import 'package:carden/state/settings.dart';
import 'package:carden/state/social.dart';
import 'package:carden/state/unlocks.dart';
import 'package:flutter/cupertino.dart';
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

  ProviderContainer container(WidgetTester tester) => ProviderScope.containerOf(tester.element(find.byType(CardenApp)));

  Future<List<String>> leaderboardIds(WidgetTester tester) async {
    final c = container(tester);
    c.invalidate(leaderboardProvider);
    return [for (final p in (await c.read(leaderboardProvider.future)).items) p.id];
  }

  testWidgets('report, block, unblock, and deletion takes them along', (tester) async {
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
    await settle(tester, 4000);
    final c = container(tester);
    final router = c.read(routerProvider);
    final me = c.read(currentUserIdProvider)!;
    final leaders = (await c.read(leaderboardProvider.future)).items;
    final target = leaders.firstWhere((p) => p.id != me);
    debugPrint('QA_SAFETY_USER $me reports and blocks ${target.id}');

    // ---- Report: a reason, then a private row the player cannot read back.
    router.push('/player/${target.id}');
    await settle(tester, 3500);
    // Report and block live in the bar's "..." menu (an action sheet: Report, Block, Cancel).
    await tapKey(tester, 'player-more', ms: 800);
    await shot(tester, 'ps_01_player_actions');
    await tapKey(tester, 'player-report');
    expect(find.text('Report ${target.displayName}'), findsOneWidget);
    await shot(tester, 'ps_02_report_reasons');
    await tapKey(tester, 'report-name', ms: 600);
    await tapKey(tester, 'report-send', ms: 2500);
    expect(find.text('Report sent. Thank you.'), findsOneWidget);
    var readable = 0;
    try {
      readable = (await TablesDB(c.read(appwriteClientProvider)).listRows(databaseId: AppwriteConfig.databaseId, tableId: AppwriteConfig.reports)).rows.length;
    } on AppwriteException catch (e) {
      debugPrint('QA_SAFETY reports not listable: ${e.code}');
    }
    expect(readable, 0, reason: 'a report is read by the developer only');

    // ---- Block: confirmed, gone from the leaderboard, Unblock in their page's menu.
    await tapKey(tester, 'player-more', ms: 800);
    await tapKey(tester, 'player-block');
    expect(find.text('Block ${target.displayName}?'), findsOneWidget);
    await shot(tester, 'ps_03_block_alert');
    await tapText(tester, 'Block', last: true, ms: 3000);
    // The profile closes after a block (TestFlight feedback, 2026-10-18); opened again, it says Blocked.
    expect(find.byType(PlayerScreen), findsNothing);
    router.push('/player/${target.id}');
    await settle(tester, 3500);
    expect(find.byKey(const ValueKey('player-blocked')), findsOneWidget);
    await tapKey(tester, 'player-more', ms: 800);
    expect(find.byKey(const ValueKey('player-unblock')), findsOneWidget);
    await shot(tester, 'ps_04_blocked');
    await tapText(tester, 'Cancel', last: true, ms: 800);
    expect(await leaderboardIds(tester), isNot(contains(target.id)));
    router.go('/social');
    await settle(tester, 3500);
    await shot(tester, 'ps_05_leaderboard_without_them');

    // ---- Settings > Blocked players > Unblock: back on the leaderboard.
    router.go('/profile/settings');
    await settle(tester, 2500);
    final settings = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first;
    await tester.dragUntilVisible(find.byKey(const ValueKey('settings-blocked')), settings, const Offset(0, -250));
    await settle(tester, 800);
    await tapKey(tester, 'settings-blocked', ms: 2500);
    expect(find.byKey(ValueKey('unblock-${target.id}')), findsOneWidget);
    await shot(tester, 'ps_06_blocked_players');
    await tapKey(tester, 'unblock-${target.id}', ms: 3000);
    expect(find.byKey(const ValueKey('blocked-empty')), findsOneWidget);
    rootNavigatorKey.currentState!.pop();
    await settle(tester, 1000);
    expect(await leaderboardIds(tester), contains(target.id));

    // ---- Settings > About: Support, Privacy policy and Terms of use; no pack code row on iPhone.
    expect(find.byKey(const ValueKey('settings-redeem-pack-code')), findsNothing);
    await tester.dragUntilVisible(find.byKey(const ValueKey('settings-terms')), settings, const Offset(0, -250));
    await settle(tester, 800);
    expect(find.byKey(const ValueKey('settings-privacy')), findsOneWidget);
    await shot(tester, 'ps_07_settings_about');

    // ---- The store links both where VIP is sold.
    router.push('/store?vip=1');
    await settle(tester, 3000);
    await tester.drag(find.byType(ListView).last, const Offset(0, -3000));
    await settle(tester, 1500);
    expect(find.byKey(const ValueKey('store-terms')), findsOneWidget);
    expect(find.byKey(const ValueKey('store-privacy')), findsOneWidget);
    await shot(tester, 'ps_08_store_links');
    router.pop();
    await settle(tester, 1200);

    // ---- Block again, then delete the account: the function removes the report and the block.
    await c.read(playerSafetyProvider).block(target);
    expect((await c.read(blockedPlayersProvider.future)).map((b) => b.playerId), [target.id]);
    router.go('/profile');
    await settle(tester, 2500);
    // Profile > Settings (the gear) > Account.
    await tester.tap(find.byIcon(AppIcons.gearAltFill).first, warnIfMissed: false);
    await settle(tester, 2000);
    final settingsList = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).last;
    final accountRow = find.textContaining(RegExp('Manage account|Sign in or create account'));
    await tester.dragUntilVisible(accountRow, settingsList, const Offset(0, -250));
    await settle(tester, 800);
    await tester.tap(accountRow.first, warnIfMissed: false);
    await settle(tester, 2500);
    final accountList = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).last;
    await tester.dragUntilVisible(find.byKey(const ValueKey('account-delete')), accountList, const Offset(0, -300));
    await settle(tester, 1000);
    await tester.tap(find.byKey(const ValueKey('account-delete')), warnIfMissed: false);
    await settle(tester, 2500);
    await tester.tap(find.byKey(const ValueKey('account-delete-continue')), warnIfMissed: false);
    await settle(tester, 1500);
    await tapText(tester, 'Delete account', last: true, ms: 500);
    for (var i = 0; i < 40 && find.byType(OnboardingScreen).evaluate().isEmpty; i++) {
      await settle(tester, 500);
    }
    expect(find.byType(OnboardingScreen), findsOneWidget, reason: 'the account is gone');
    debugPrint('QA_SAFETY_DELETED $me');
  }, timeout: const Timeout(Duration(minutes: 8)));
}

// Host check after the run (the app cannot read reports):
//   python3 tools/dev/reports.py --player <target id>   no row by QA_SAFETY_USER's id is left
