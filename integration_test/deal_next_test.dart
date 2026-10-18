// The picture before the deal after Next puzzle (TestFlight, owner 2026-10-18): a finished picture,
// Next puzzle, and the next picture must show whole, then come apart and glide to its dealt places,
// however long the picture takes to arrive. Played on the real app (live Appwrite, a QA guest) on a
// past month of daily pictures (the owner's path), with the picture slowed down on purpose
// (`debugPictureDelay`) as a slow connection does: at once, 2.5 s and 6 s late, with the app making
// its own frames, Next tapped the moment the picture is complete, after the break offer, and with the
// app out of the front while the picture arrives (iOS keeps drawing it: the owner's screenshot and
// TestFlight feedback sheet). Also checks the haptics: the success touch and the stars on Picture
// complete, the deal's ticks and its landing (docs/native-ui.md, "Haptics").
//
//   tools/dev/qa-run.sh drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/deal_next_test.dart -d <simulator>
import 'package:carden/app.dart';
import 'package:carden/core/haptics.dart';
import 'package:carden/core/sfx.dart';
import 'package:carden/data/local_store.dart';
import 'package:carden/features/ads/house_ads.dart';
import 'package:carden/features/game/board_widget.dart';
import 'package:carden/game/game_controller.dart';
import 'package:carden/game/image_loader.dart';
import 'package:carden/router.dart';
import 'package:carden/state/catalog.dart';
import 'package:carden/state/first_steps.dart';
import 'package:carden/state/giant.dart';
import 'package:carden/state/profile.dart';
import 'package:carden/state/unlocks.dart';
import 'package:carden/state/rewards.dart' show OpenFeatures;
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

late LocalStore store;

/// What the haptics played (the simulator has none to feel).
final touches = <HapticKind>[];

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  Future<void> shot(String name) => binding.takeScreenshot(name);

  Future<void> tapText(WidgetTester tester, String text, {int ms = 1200}) async {
    final f = find.text(text);
    expect(f, findsWidgets, reason: 'expected "$text" on screen');
    await tester.tap(f.last, warnIfMissed: false);
    await settle(tester, ms);
  }

  ProviderContainer container(WidgetTester tester) => ProviderScope.containerOf(tester.element(find.byType(CardenApp)));
  // The screen on top: while Next puzzle's fade runs, the finished board is still underneath.
  bool boardOn() => find.byType(BoardWidget).evaluate().isNotEmpty;
  BoardWidget board(WidgetTester tester) => tester.widget<BoardWidget>(find.byType(BoardWidget).last);
  GameState state(WidgetTester tester) => board(tester).state;
  Rect boardRect(WidgetTester tester) => tester.getRect(find.byType(BoardWidget).last);
  Offset onScreen(WidgetTester tester, int slot) {
    final w = board(tester);
    return boardRect(tester).topLeft + w.state.board.tiling.cellCenter(slot, Size(w.width, w.height));
  }

  Future<void> solve(WidgetTester tester) async {
    for (var guard = 0; guard < 80; guard++) {
      if (!boardOn()) return;
      final b = state(tester).board;
      if (b.isSolved) return;
      final slot = List.generate(b.cells, (i) => i).firstWhere((i) => !b.isLocked(i));
      await tester.tapAt(onScreen(tester, slot));
      await settle(tester, 250);
      await tester.tapAt(onScreen(tester, b.homeOf(slot)));
      await settle(tester, 450);
    }
  }

  /// Next puzzle on a finished picture, the next picture [delay] late: the first frame its board
  /// shows must be the whole picture, then the cards leave it for their dealt places.
  Future<void> next(WidgetTester tester, String prefix, Duration delay, {bool live = false, bool breakOffer = false, bool away = false}) async {
    // [live]: the app makes its own frames, as on a phone (no pumps while the next board loads).
    Future<void> wait(int ms) => live ? Future<void>.delayed(Duration(milliseconds: ms)) : tester.pump(Duration(milliseconds: ms));
    expect(find.text('Next puzzle'), findsOneWidget);
    final finished = state(tester).board;
    if (breakOffer) {
      // The break offer between the boards, closed when it lets the player go (5 s).
      store.completionsSinceAd = HouseAdPolicy.everyNthCompletion;
      store.lifetimeCompletions = 50;
      store.lastInterstitialAt = null;
      store.lastRewardedAt = null;
    } else {
      // No break offer in between: this is about the next board.
      store.completionsSinceAd = 0;
      store.lastInterstitialAt = DateTime.now();
    }
    debugPictureDelay = delay;
    var tapped = DateTime.now();
    await tester.tap(find.text('Next puzzle').last, warnIfMissed: false);
    if (breakOffer) {
      for (var i = 0; i < 100 && find.text('Close').evaluate().isEmpty; i++) {
        await wait(100);
      }
      expect(find.byType(HouseAdScreen), findsOneWidget, reason: 'the break offer shows');
      await shot('${prefix}0_break');
      tapped = DateTime.now();
      await tester.tap(find.text('Close').last, warnIfMissed: false);
    }
    if (away) {
      // The owner's case: while "Dealing the cards" shows, a screenshot and TestFlight's feedback
      // sheet (or Control Center, a call) take the app out of the front; iOS keeps drawing it.
      await wait(600);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await wait(delay.inMilliseconds + 3000);
      expect(boardOn(), isTrue, reason: 'the picture arrived meanwhile');
      expect(state(tester).previewing, isTrue, reason: 'and waits for the player');
      expect(state(tester).elapsed, 0, reason: 'the clock too');
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      tapped = DateTime.now();
    }
    var loadingShot = false;
    for (var i = 0; i < 600; i++) {
      await wait(16);
      if (!loadingShot && find.text('Dealing the cards').evaluate().isNotEmpty && DateTime.now().difference(tapped) > const Duration(milliseconds: 600)) {
        loadingShot = true;
        await shot('${prefix}0_loading');
      }
      if (boardOn() && !identical(state(tester).board, finished)) break;
    }
    debugPictureDelay = Duration.zero;
    expect(boardOn() && !identical(state(tester).board, finished), isTrue, reason: 'the next board shows');
    final s = state(tester);
    debugPrint('QA_NEXT $prefix tapped at ${tapped.millisecondsSinceEpoch}, board at ${DateTime.now().millisecondsSinceEpoch}: first frame after ${DateTime.now().difference(tapped).inMilliseconds} ms: previewing ${s.previewing}, moves ${s.moves}');
    await shot('${prefix}a_picture');
    expect(s.previewing, isTrue, reason: 'the next picture shows whole before its deal');
    // The far card: from its own place to where it was dealt.
    final b = s.board;
    final far = List.generate(b.cells, (i) => i).where((i) => !b.isLocked(i) && b.slots[i] != i).last;
    // On the new board: the finished one may still be fading out underneath.
    final key = find.descendant(of: find.byType(BoardWidget).last, matching: find.byKey(ValueKey('card-${s.cardKeys?[b.slots[far]] ?? b.slots[far]}')));
    final start = tester.getTopLeft(key);
    final end = DateTime.now().add(const Duration(seconds: 4));
    // The deal's touch (docs/native-ui.md, "Haptics"): a few soft ticks as the cards leave the
    // picture, a light one as they land; nothing before.
    touches.clear();
    while (state(tester).previewing && DateTime.now().isBefore(end)) {
      await wait(30);
    }
    expect(state(tester).previewing, isFalse, reason: 'then deals by itself');
    expect(touches, isEmpty, reason: 'no touch while the picture shows');
    debugPrint('QA_NEXT $prefix dealt at ${DateTime.now().millisecondsSinceEpoch}');
    expect(state(tester).elapsed, 0, reason: 'the clock waited for the picture and its preview');
    await wait(380);
    final mid = tester.getTopLeft(key);
    await shot('${prefix}b_dealing');
    await settle(tester, 1600);
    final ticks = touches.where((k) => k == HapticKind.selection).length;
    debugPrint('QA_HAPTICS $prefix deal: $touches');
    expect(ticks, inInclusiveRange(1, HapticRun.maxTicks), reason: 'a handful of soft ticks');
    expect(touches.last, HapticKind.light, reason: 'and a light touch as the cards land');
    final dealt = tester.getTopLeft(key);
    debugPrint('QA_NEXT $prefix card start $start mid $mid end $dealt');
    expect((mid - start).distance, greaterThan(1), reason: 'on its way');
    expect((dealt - mid).distance, greaterThan(1), reason: 'not there at once: it glides');
    expect(state(tester).moves, 0, reason: 'the deal is not a move');
    await shot('${prefix}c_dealt');
  }

  testWidgets('Next puzzle: the picture first, then the deal, however slow the picture', (tester) async {
    SharedPreferences.setMockInitialValues({});
    store = await LocalStore.open();
    await FirstSteps.skipFor(store);
    Sfx.instance.soundEnabled = false;
    Sfx.instance.musicEnabled = false;
    Haptics.debugSink = touches.add;
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

    final packs = await c.read(packsProvider.future);
    final all = await c.read(allPuzzlesProvider.future);
    // The owner's path: a past month of daily pictures, played in order with Next puzzle.
    final pack = packs.firstWhere((p) => p.id == 'daily-2026-06', orElse: () => packs.firstWhere((p) => p.isFree && !isGiantPack(p) && all.where((z) => z.packId == p.id && !z.isLockedByDate).length > 6));
    final pictures = all.where((p) => p.packId == pack.id).toList()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    debugPrint('QA_NEXT pack ${pack.id}: ${pictures.length} pictures');
    if (!pack.isFree) {
      final profile = c.read(profileProvider.notifier);
      await profile.addCoins(pack.priceCoins, reason: 'qa:daily');
      await profile.addTickets(pack.priceTickets, reason: 'qa:daily');
      await settle(tester, 800);
      expect(await profile.unlockPack(pack), isTrue);
      await settle(tester, 800);
    }

    // The first picture from the board picker (its picture decoded there), solved.
    router.push('/play/${pictures.first.id}');
    await settle(tester, 5000);
    await tapText(tester, 'Cozy', ms: 800);
    await tester.tap(find.byKey(const ValueKey('play-board')), warnIfMissed: false);
    for (var i = 0; i < 400 && !boardOn(); i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await settle(tester, 3500);
    touches.clear();
    await solve(tester);
    await settle(tester, 3000);
    await shot('dn_00_finished');
    // Picture complete: the success touch, then a tick for each star as it pops in.
    debugPrint('QA_HAPTICS win: $touches');
    final win = touches.indexOf(HapticKind.success);
    expect(win, greaterThanOrEqualTo(0), reason: 'the success touch');
    expect(touches.skip(win + 1).where((k) => k == HapticKind.selection).length, greaterThanOrEqualTo(1), reason: 'the stars tick in');

    // Next puzzle: the picture as fast as the connection gives it, then 2.5 s and 6 s late.
    await next(tester, 'dn_01_', Duration.zero);
    await solve(tester);
    await settle(tester, 3000);
    await next(tester, 'dn_02_', const Duration(milliseconds: 2500));
    await solve(tester);
    await settle(tester, 3000);
    await next(tester, 'dn_03_', const Duration(seconds: 6));
    // The same with the app making its own frames, as on a phone.
    await solve(tester);
    await settle(tester, 3000);
    await next(tester, 'dn_04_', const Duration(milliseconds: 2500), live: true);
    await solve(tester);
    await settle(tester, 1000);
    await next(tester, 'dn_05_', Duration.zero, live: true);
    // Next the moment the picture is complete, the rewards still on their way.
    await solve(tester);
    for (var i = 0; i < 40 && find.text('Next puzzle').evaluate().isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    await next(tester, 'dn_06_', const Duration(milliseconds: 1500), live: true);
    // After the break offer.
    await solve(tester);
    await settle(tester, 2000);
    await next(tester, 'dn_07_', const Duration(milliseconds: 1500), live: true, breakOffer: true);
    // Away from the app while the picture arrives, back after it.
    await solve(tester);
    await settle(tester, 2000);
    await next(tester, 'dn_08_', const Duration(milliseconds: 2500), live: true, away: true);
  });
}
