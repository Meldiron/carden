// QA of the daily gift's week numbering (owner, 2026-10-18: on day 8 Home and the Daily gift sheet showed
// Day 1 to 7 again, so the streak looked reset). A fresh QA guest on the live backend gets a 7-day streak
// claimed yesterday (its own profile row, written with its own session), then: Home before the claim
// (7-day streak, dots 8 to 14, day 8 current), the sheet (Day 8 to 14, "Claim day 8 gift"), the claim,
// Home after it (8-day streak, day 8 ticked, day 9 next); then the 14 -> 15 boundary and a broken streak.
//   xcrun simctl uninstall <udid> com.matejbaco.cardjigsawworld
//   tools/dev/qa-run.sh drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/streak_week_test.dart -d <udid>
// Captures land in screenshots/streak_*.png.
import 'dart:async';

import 'package:carden/app.dart';
import 'package:carden/core/appwrite.dart';
import 'package:carden/core/sfx.dart';
import 'package:carden/data/local_store.dart';
import 'package:carden/features/daily/daily_reward_sheet.dart';
import 'package:carden/router.dart';
import 'package:carden/state/first_steps.dart';
import 'package:carden/state/profile.dart';
import 'package:carden/state/settings.dart';
import 'package:carden/state/sync.dart';
import 'package:carden/state/unlocks.dart';
import 'package:carden/state/rewards.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  Future<void> shot(WidgetTester tester, String name, {int ms = 600}) async {
    await settle(tester, ms);
    await binding.takeScreenshot('streak_$name');
  }

  Future<void> tapText(WidgetTester tester, String text, {int ms = 1200}) async {
    final f = find.text(text);
    expect(f, findsWidgets, reason: 'expected "$text" on screen');
    await tester.tap(f.first, warnIfMissed: false);
    await settle(tester, ms);
  }

  ProviderContainer container(WidgetTester tester) => ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));

  Future<void> closeSheets(WidgetTester tester) async {
    for (var i = 0; i < 3 && find.byType(DailyRewardSheet).evaluate().isNotEmpty; i++) {
      Navigator.of(tester.element(find.byType(DailyRewardSheet))).pop();
      await settle(tester, 1200);
    }
  }

  /// The guest's own profile row: a streak of [streak] whose last gift was claimed [daysAgo] days ago.
  Future<void> seed(WidgetTester tester, int streak, int daysAgo) async {
    final c = container(tester);
    final uid = c.read(profileProvider).value!.id;
    final at = DateTime.now().subtract(Duration(days: daysAgo));
    await c.read(tablesProvider).updateRow(
      databaseId: AppwriteConfig.databaseId,
      tableId: AppwriteConfig.profiles,
      rowId: uid,
      data: {'streak': streak, 'longestStreak': streak, 'lastDailyClaim': DateTime(at.year, at.month, at.day, 12).toUtc().toIso8601String()},
    );
    c.read(syncProvider.notifier).expectServerChange();
    await c.read(syncProvider.notifier).sync(silent: true);
    await settle(tester, 2500);
    expect(c.read(profileProvider).value!.streak, streak, reason: 'the seeded streak reached the app');
  }

  Future<void> homeCard(WidgetTester tester, String title) async {
    container(tester).read(routerProvider).go('/home');
    await settle(tester, 2000);
    final f = find.text(title);
    await tester.scrollUntilVisible(f, 250, scrollable: find.byType(Scrollable).first, maxScrolls: 40);
    await settle(tester, 500);
    unawaited(Scrollable.ensureVisible(tester.element(f), alignment: 0.3, duration: const Duration(milliseconds: 300)));
    await settle(tester, 1200);
  }

  void spoken(String label) => expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);

  testWidgets('Daily gift week numbered by the streak', (tester) async {
    final semantics = tester.ensureSemantics();
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
    await settle(tester, 6000); // catalogue and covers
    await closeSheets(tester); // a new guest may be offered the gift at once

    // ---- Day 8 of a running streak, before the claim.
    await seed(tester, 7, 1);
    await homeCard(tester, '7-day streak');
    expect(find.text('Claim today to keep it going'), findsOneWidget);
    spoken('Day 8, today');
    spoken('Day 14');
    expect(find.bySemanticsLabel('Day 1'), findsNothing, reason: 'the second week does not start at Day 1');
    await shot(tester, '01_home_day8_before');

    // ---- The sheet: Day 8 to 14, the claim names day 8.
    unawaited(showDailyRewardSheet(tester.element(find.text('7-day streak'))));
    await settle(tester, 1500);
    for (var day = 8; day <= 14; day++) {
      expect(find.descendant(of: find.byType(DailyRewardSheet), matching: find.text('Day $day')), findsOneWidget);
    }
    expect(find.text('Claim day 8 gift'), findsOneWidget);
    await shot(tester, '02_sheet_day8');
    await tapText(tester, 'Claim day 8 gift', ms: 5000);
    expect(find.text('Close'), findsOneWidget, reason: 'the gift was claimed');
    await shot(tester, '03_sheet_day8_claimed');
    await tapText(tester, 'Close', ms: 1500);
    if (find.text('Not now').evaluate().isNotEmpty) await tapText(tester, 'Not now');
    await closeSheets(tester);

    // ---- Home after the claim: 8-day streak, Day 8 ticked, Day 9 tomorrow.
    await homeCard(tester, '8-day streak');
    expect(find.text('Claimed · back tomorrow'), findsOneWidget);
    spoken('Day 8, claimed');
    spoken('Day 9, tomorrow');
    await shot(tester, '04_home_day8_after');

    // ---- The next boundary: a 14-day streak claimed yesterday makes today Day 15 (Day 15 to 21).
    await seed(tester, 14, 1);
    await homeCard(tester, '14-day streak');
    spoken('Day 15, today');
    spoken('Day 21');
    unawaited(showDailyRewardSheet(tester.element(find.text('14-day streak'))));
    await settle(tester, 1500);
    expect(find.text('Claim day 15 gift'), findsOneWidget);
    expect(find.descendant(of: find.byType(DailyRewardSheet), matching: find.text('Day 21')), findsOneWidget);
    await shot(tester, '05_sheet_day15');
    await closeSheets(tester);

    // ---- A streak broken five days ago starts again at Day 1.
    await seed(tester, 20, 5);
    await homeCard(tester, 'Streak ended');
    spoken('Day 1, today');
    await shot(tester, '06_home_broken');
    semantics.dispose();
  });
}
