// Sheets on the real app (owner's TestFlight feedback, 2026-10-18; lib/widgets/sheets.dart): every
// sheet stops below the status bar with a strip of page above it, closes with a drag down once its
// content is at the top (no empty band pulled over the title), keeps its footer buttons pinned, and
// the message sheet has no delete or close buttons. Paths: Home > Unlock anyway (guided start),
// Profile > Statistics > See all, Settings > Image credits and licences, the Store, the Lucky Wheel,
// Account, Social > Inbox > a message, and the Store again with Reduce motion.
//
//   tools/dev/qa-run.sh drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/sheets_test.dart -d <simulator>
import 'package:carden/app.dart';
import 'package:carden/core/sfx.dart';
import 'package:carden/data/local_store.dart';
import 'package:carden/features/daily/wheel_screen.dart';
import 'package:carden/features/profile/account_screen.dart';
import 'package:carden/features/store/store_screen.dart';
import 'package:carden/router.dart';
import 'package:carden/state/first_steps.dart';
import 'package:carden/state/inbox.dart';
import 'package:carden/state/settings.dart';
import 'package:carden/widgets/glass.dart';
import 'package:carden/widgets/sheets.dart';
import 'package:carden/widgets/ui.dart';
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

  double statusBar(WidgetTester tester) => MediaQuery.of(tester.element(find.byType(CardenApp))).viewPadding.top;
  double screenHeight(WidgetTester tester) => MediaQuery.of(tester.element(find.byType(CardenApp))).size.height;

  /// Pulls [from] down by [first] (a screenshot of the sheet mid-drag), then by [rest], and lets go.
  Future<void> pullDown(WidgetTester tester, Offset from, {required String midShot, double first = 160, double rest = 260}) async {
    final g = await tester.startGesture(from);
    for (var i = 0; i < 8; i++) {
      await g.moveBy(Offset(0, first / 8));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await binding.takeScreenshot(midShot);
    for (var i = 0; i < 8; i++) {
      await g.moveBy(Offset(0, rest / 8));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await settle(tester, 1200);
  }

  testWidgets('sheets: height, drag to close at the top, pinned footer, no header buttons', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    // A player in the guided start, past the first board: Home's calm page with "Unlock anyway".
    store.tutorialSeen = true;
    await store.setJson(FirstSteps.storeKey, FirstSteps(guided: true, firstBoard: false, startedAt: DateTime.now()).toJson());
    Sfx.instance.soundEnabled = false;
    Sfx.instance.musicEnabled = false;
    await tester.pumpWidget(ProviderScope(overrides: [localStoreProvider.overrideWithValue(store)], child: const CardenApp()));
    await settle(tester, 1500);
    await tapText(tester, 'Continue');
    await tapText(tester, 'Continue');
    await tapText(tester, 'Start playing', ms: 5000);
    await settle(tester, 4000);
    final c = container(tester);
    final top = statusBar(tester);
    final gap = screenHeight(tester) * SheetMetrics.topGapRatio;
    debugPrint('SHEETS_QA status bar $top, sheet top ${gap.toStringAsFixed(1)}, height ${screenHeight(tester)}');

    // 1. Home > Unlock anyway: the picker stops below the status bar, its button stays pinned.
    await tester.scrollUntilVisible(find.byKey(const ValueKey('unlock-anyway')), 300, scrollable: find.byType(Scrollable).first);
    await settle(tester, 600);
    await tester.tap(find.byKey(const ValueKey('unlock-anyway')), warnIfMissed: false);
    await settle(tester, 1500);
    expect(find.byKey(const ValueKey('unlock-picker')), findsOneWidget);
    final sheetTop = tester.getRect(find.byType(GlassSheet)).top;
    debugPrint('SHEETS_QA unlock picker top $sheetTop');
    expect(sheetTop, greaterThanOrEqualTo(gap - 0.5), reason: 'a strip of Home stays above the sheet');
    final button = find.byKey(const ValueKey('unlock-picked')).hitTestable();
    expect(button, findsOneWidget, reason: 'the button is on screen before scrolling');
    final buttonAt = tester.getRect(button);
    await shot(tester, 'sh_01_unlock_picker');
    await tester.timedDrag(find.byKey(SheetScrollBody.scrollKey), const Offset(0, -400), const Duration(milliseconds: 700));
    await settle(tester, 800);
    expect(tester.getRect(find.byKey(const ValueKey('unlock-picked'))), buttonAt, reason: 'the button stayed pinned while the list scrolled');
    await shot(tester, 'sh_02_unlock_scrolled');
    // Down from the middle of the scrolled list: the list goes back to its top first, the sheet stays.
    await tester.timedDrag(find.byKey(SheetScrollBody.scrollKey), const Offset(0, 250), const Duration(milliseconds: 900));
    await settle(tester, 800);
    expect(find.byKey(const ValueKey('unlock-picker')), findsOneWidget, reason: 'still open: the list scrolled');
    await tester.timedDrag(find.byKey(SheetScrollBody.scrollKey), const Offset(0, 250), const Duration(milliseconds: 900));
    await settle(tester, 800);
    // At the top now: a pull moves the whole sheet and closes it.
    await pullDown(tester, tester.getCenter(find.text('Unlock early')), midShot: 'sh_03_unlock_dragging');
    expect(find.byKey(const ValueKey('unlock-picker')), findsNothing, reason: 'a drag down at the top closed the sheet');
    await shot(tester, 'sh_04_unlock_closed');

    // A tap on the strip above closes it too.
    await tester.tap(find.byKey(const ValueKey('unlock-anyway')), warnIfMissed: false);
    await settle(tester, 1500);
    expect(find.byKey(const ValueKey('unlock-picker')), findsOneWidget);
    await tester.tapAt(Offset(200, sheetTop - 8));
    await settle(tester, 1200);
    expect(find.byKey(const ValueKey('unlock-picker')), findsNothing, reason: 'a tap above the sheet closed it');

    // Everything open for the rest.
    c.read(firstStepsProvider.notifier).showEverything();
    await settle(tester, 1500);

    // 2. Profile > Statistics > See all.
    await tapText(tester, 'Profile', ms: 2500);
    final seeAll = find.descendant(of: find.widgetWithText(SectionHeader, 'Statistics'), matching: find.text('See all'));
    await tester.dragUntilVisible(seeAll, find.byType(CustomScrollView).last, const Offset(0, -200));
    await settle(tester, 800);
    await tester.tap(seeAll.first, warnIfMissed: false);
    await settle(tester, 1500);
    expect(find.byKey(const ValueKey('statistics-sheet')), findsOneWidget);
    final statsTop = tester.getRect(find.byType(GlassSheet)).top;
    final titleGap = tester.getRect(find.text('Statistics').last).top - statsTop;
    debugPrint('SHEETS_QA statistics top $statsTop, title ${titleGap.toStringAsFixed(1)} below it');
    expect(titleGap, lessThan(60), reason: 'no empty band above the title');
    await shot(tester, 'sh_05_statistics');
    await pullDown(tester, tester.getCenter(find.text('Everything you have played so far')), midShot: 'sh_06_statistics_dragging');
    expect(find.byKey(const ValueKey('statistics-sheet')), findsNothing, reason: 'a drag down at the top closed Statistics');

    // 3. Settings > Image credits and licences.
    c.read(routerProvider).go('/profile/settings');
    await settle(tester, 2000);
    await tester.scrollUntilVisible(find.text('Image credits and licences'), 300, scrollable: find.byType(Scrollable).first);
    await settle(tester, 600);
    await tapText(tester, 'Image credits and licences', ms: 2000);
    expect(find.byKey(const ValueKey('credits-sheet')), findsOneWidget);
    await shot(tester, 'sh_07_credits');
    await pullDown(tester, tester.getCenter(find.text('Image credits and licences').last), midShot: 'sh_08_credits_dragging');
    expect(find.byKey(const ValueKey('credits-sheet')), findsNothing, reason: 'a drag down at the top closed the credits');
    c.read(routerProvider).go('/home');
    await settle(tester, 1500);

    // 4. The Store (a full-height sheet): its list closes it from the top.
    c.read(routerProvider).push('/store');
    await settle(tester, 2500);
    expect(find.text('Coins'), findsWidgets);
    final coinsTop = tester.getRect(find.text('Coins').first).top;
    debugPrint('SHEETS_QA store "Coins" at $coinsTop');
    await shot(tester, 'sh_09_store');
    await pullDown(tester, tester.getCenter(find.text('Coins').first), midShot: 'sh_10_store_dragging', first: 160, rest: 420);
    expect(find.byType(StoreScreen), findsNothing, reason: 'a drag down at the top closed the Store');
    await shot(tester, 'sh_11_store_closed');

    // 5. The Lucky Wheel and Account: the same drag closes them.
    c.read(routerProvider).push('/wheel');
    await settle(tester, 2500);
    await shot(tester, 'sh_12_wheel');
    await pullDown(tester, Offset(200, screenHeight(tester) * 0.45), midShot: 'sh_13_wheel_dragging', first: 160, rest: 420);
    expect(find.byType(WheelScreen), findsNothing, reason: 'a drag down closed the Wheel');
    c.read(routerProvider).push('/account');
    await settle(tester, 2500);
    await shot(tester, 'sh_14_account');
    await pullDown(tester, Offset(200, screenHeight(tester) * 0.35), midShot: 'sh_15_account_dragging', first: 160, rest: 420);
    expect(find.byType(AccountScreen), findsNothing, reason: 'a drag down at the top closed Account');
    await settle(tester, 800);

    // 6. Social > Inbox > a message: no delete or close buttons; a drag down closes it.
    await tapText(tester, 'Social', ms: 2500);
    await tapText(tester, 'Inbox', ms: 2000);
    for (var i = 0; i < 10 && find.text('Celebrating Carden 2.0').evaluate().isEmpty; i++) {
      c.invalidate(inboxMessagesProvider);
      await settle(tester, 2000);
    }
    await shot(tester, 'sh_16_inbox');
    if (find.text('Celebrating Carden 2.0').evaluate().isNotEmpty) {
      await tapText(tester, 'Celebrating Carden 2.0', ms: 1500);
      expect(find.byKey(const ValueKey('message-delete')), findsNothing);
      expect(find.byKey(const ValueKey('message-close')), findsNothing);
      await shot(tester, 'sh_17_message');
      await pullDown(tester, tester.getCenter(find.text('Celebrating Carden 2.0').last), midShot: 'sh_18_message_dragging');
      expect(find.byType(GlassSheet), findsNothing, reason: 'a drag down closed the message');
    } else {
      debugPrint('SHEETS_QA no inbox message arrived; the message sheet was not opened');
    }

    // 7. Reduce motion: the Store fades in as a sheet below the status bar and still drags closed.
    final settings = c.read(settingsProvider.notifier);
    settings.setAccessibility(c.read(settingsProvider).accessibility.copyWith(reduceMotion: true));
    await settle(tester, 800);
    c.read(routerProvider).push('/store');
    await settle(tester, 2500);
    await shot(tester, 'sh_19_store_reduce_motion');
    await pullDown(tester, tester.getCenter(find.text('Coins').first), midShot: 'sh_20_store_reduce_motion_dragging', first: 160, rest: 420);
    expect(find.byType(StoreScreen), findsNothing, reason: 'Reduce motion: a drag down closed the Store');
    settings.setAccessibility(c.read(settingsProvider).accessibility.copyWith(reduceMotion: false));
    await settle(tester, 800);

    // 8. Dark (the owner's phone) with the largest text: the inbox row's corners, the message,
    //    Statistics, and Unlock early with its button pinned.
    settings.setThemeMode(ThemeMode.dark);
    settings.setAccessibility(c.read(settingsProvider).accessibility.copyWith(textSize: TextSize.largest));
    await settle(tester, 1500);
    await shot(tester, 'sh_21_inbox_dark');
    if (find.text('Celebrating Carden 2.0').evaluate().isNotEmpty) {
      await tapText(tester, 'Celebrating Carden 2.0', ms: 1500);
      await shot(tester, 'sh_22_message_dark');
      await tester.drag(find.byKey(const ValueKey('sheet-grabber')), const Offset(0, 500));
      await settle(tester, 1200);
      expect(find.byType(GlassSheet), findsNothing, reason: 'the grabber dragged the message closed');
    }
    // At the largest text the tab bar shows icons only: go by the router.
    c.read(routerProvider).go('/profile');
    await settle(tester, 2500);
    await tester.dragUntilVisible(seeAll, find.byType(CustomScrollView).last, const Offset(0, -200));
    await settle(tester, 800);
    await tester.tap(seeAll.first, warnIfMissed: false);
    await settle(tester, 1500);
    await shot(tester, 'sh_23_statistics_dark');
    await pullDown(tester, tester.getCenter(find.text('Statistics').last), midShot: 'sh_24_statistics_dark_dragging');
    expect(find.byKey(const ValueKey('statistics-sheet')), findsNothing);
    // The guided start again (its record, as a new player has it), so Home offers Unlock anyway.
    await store.setJson(FirstSteps.storeKey, FirstSteps(guided: true, firstBoard: false, startedAt: DateTime.now()).toJson());
    c.read(firstStepsProvider.notifier).reload();
    await settle(tester, 1200);
    c.read(routerProvider).go('/home');
    await settle(tester, 2500);
    await tester.scrollUntilVisible(find.byKey(const ValueKey('unlock-anyway')), 300, scrollable: find.byType(Scrollable).first);
    await settle(tester, 600);
    await tester.tap(find.byKey(const ValueKey('unlock-anyway')), warnIfMissed: false);
    await settle(tester, 1500);
    expect(find.byKey(const ValueKey('unlock-picked')).hitTestable(), findsOneWidget, reason: 'the button is pinned in view at the largest text');
    await shot(tester, 'sh_25_unlock_largest_dark');
    await tester.drag(find.byKey(const ValueKey('sheet-grabber')), const Offset(0, 600));
    await settle(tester, 1200);
    expect(find.byKey(const ValueKey('unlock-picker')), findsNothing);
    settings.setThemeMode(ThemeMode.system);
    settings.setAccessibility(const Accessibility());
    await settle(tester, 800);
  }, timeout: const Timeout(Duration(minutes: 10)));
}
