// TestFlight round of 2026-10-17 on the real app (live Appwrite, a QA guest), each on the screen a
// player reaches:
// - the picture before the deal: today's picture from Home, a skip by tap, Next puzzle after a
//   finished picture, Shuffle and restart with Reduce motion (a cross-fade), a giant board, and
//   the first board's hint waiting for it (AKtE1E-lERXyUZ3g4Ue5pDY);
// - a tap ends Peek at once, on a normal and a giant board (ADJsOor69XyF3s1tp-JZVIg);
// - the Shuffle button's room, also at the SE width with the largest text (AL571Rq1g06fKufTh_hmiu8);
// - Pause > "Discard and pick a board", its question and the board picker it opens (AP6yq6rDwy9Zl9nXhIjMssg);
// - Home's Today card after today's picture: "New picture in ...", no Tomorrow row (AH-5v3J6G0HqYK59cqF-hdA);
// - the inbox message sheet: Carden's gift and a friend's, light, dark, Increase contrast and the
//   largest text (AAl47uUaSl5TvZdzL9aXdgY).
//
//   tools/dev/qa-run.sh drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/board_start_test.dart -d <simulator>
import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:carden/app.dart';
import 'package:carden/core/appwrite.dart';
import 'package:carden/core/sfx.dart';
import 'package:carden/data/local_store.dart';
import 'package:carden/data/repositories.dart';
import 'package:carden/features/game/board_widget.dart';
import 'package:carden/game/game_controller.dart';
import 'package:carden/router.dart';
import 'package:carden/state/auth.dart';
import 'package:carden/state/catalog.dart';
import 'package:carden/state/first_steps.dart';
import 'package:carden/state/giant.dart';
import 'package:carden/state/inbox.dart';
import 'package:carden/state/profile.dart';
import 'package:carden/state/rewards.dart' show OpenFeatures;
import 'package:carden/state/settings.dart';
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

/// A friend's gift (function `send-gift` writes them so), kept on this device only.
final _friendGift = InboxMessage(
  id: 'qa-friend-gift',
  subject: 'Ava sent you a gift',
  body: 'Ava sent you 1 ticket. Claim it within 24 hours.',
  sentAt: DateTime.now().subtract(const Duration(hours: 2)),
  expiresAt: DateTime.now().add(const Duration(hours: 22)),
  tickets: 1,
  fromUserId: 'qa-friend',
  fromName: 'Ava',
  fromAvatar: 'fox',
);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  Future<void> shot(WidgetTester tester, String name, {int wait = 400}) async {
    if (wait > 0) await settle(tester, wait);
    await binding.takeScreenshot(name);
  }

  Future<void> tapText(WidgetTester tester, String text, {int ms = 1200}) async {
    final f = find.text(text);
    expect(f, findsWidgets, reason: 'expected "$text" on screen');
    await tester.tap(f.first, warnIfMissed: false);
    await settle(tester, ms);
  }

  ProviderContainer container(WidgetTester tester) => ProviderScope.containerOf(tester.element(find.byType(CardenApp)));
  bool boardOn() => find.byType(BoardWidget).evaluate().isNotEmpty;
  BoardWidget board(WidgetTester tester) => tester.widget<BoardWidget>(find.byType(BoardWidget).first);
  GameState state(WidgetTester tester) => board(tester).state;
  Rect boardRect(WidgetTester tester) => tester.getRect(find.byType(BoardWidget).first);
  Offset onScreen(WidgetTester tester, int slot) {
    final w = board(tester);
    final z = w.zoom;
    final p = w.state.board.tiling.cellCenter(slot, Size(w.width, w.height));
    return boardRect(tester).topLeft + (z == null ? p : z.toViewport(p));
  }

  /// Waits (in short steps, so the first frame of a board is caught) until a board shows.
  Future<void> waitForBoard(WidgetTester tester, {bool fresh = false}) async {
    final before = fresh && boardOn() ? state(tester) : null;
    for (var i = 0; i < 400; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (boardOn() && !identical(state(tester).board, before?.board) && (before == null || state(tester).previewing)) return;
    }
    fail('no board');
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

  /// The difficulty screen of [id], then [size] on [mode] (Cards when null), then Play.
  Future<void> play(WidgetTester tester, String id, String size, {String? mode}) async {
    container(tester).read(routerProvider).push('/play/$id');
    await settle(tester, 5000);
    if (mode != null) await tapText(tester, mode, ms: 800);
    await tester.dragUntilVisible(find.text(size), find.byType(Scrollable).first, const Offset(0, -200));
    await tapText(tester, size, ms: 800);
    await tester.tap(find.byKey(const ValueKey('play-board')), warnIfMissed: false);
  }

  /// Captures the picture before the deal: on the first frame, while it shows, while the cards
  /// glide, and dealt.
  Future<void> preview(WidgetTester tester, String prefix, {bool skip = false}) async {
    expect(state(tester).previewing, isTrue, reason: 'a board dealt here opens on its picture');
    final b = state(tester).board;
    final far = List.generate(b.cells, (i) => i).where((i) => !b.isLocked(i)).last;
    await shot(tester, '${prefix}a_picture', wait: 0);
    if (skip) {
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tapAt(boardRect(tester).center);
      await tester.pump(const Duration(milliseconds: 16));
      expect(state(tester).previewing, isFalse, reason: 'a tap deals at once');
      expect(state(tester).selected, isNull, reason: 'the tap did not pick a card');
    } else {
      final end = DateTime.now().add(const Duration(seconds: 3));
      while (state(tester).previewing && DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 30));
      }
      expect(state(tester).previewing, isFalse, reason: 'then deals by itself');
    }
    final card = find.byKey(ValueKey('card-${state(tester).cardKeys?[b.slots[far]] ?? b.slots[far]}'));
    final start = tester.getTopLeft(card);
    await tester.pump(const Duration(milliseconds: 380));
    await shot(tester, '${prefix}b_dealing', wait: 0);
    final mid = tester.getTopLeft(card);
    await settle(tester, 1600);
    final end = tester.getTopLeft(card);
    debugPrint('QA_DEAL $prefix start $start mid $mid end $end');
    expect((end - start).distance, greaterThan(1), reason: 'the card left its place for its dealt one');
    expect(state(tester).moves, 0, reason: 'not a move');
    expect(state(tester).peeked, isFalse, reason: 'not a Peek');
    await shot(tester, '${prefix}c_dealt', wait: 0);
  }

  /// Peek, then a tap: the cards fly back at once.
  Future<void> peekAndTap(WidgetTester tester, String prefix) async {
    await tester.tap(find.byKey(const ValueKey('booster-peek')), warnIfMissed: false);
    await settle(tester, 1100);
    expect(state(tester).peeking, isTrue);
    await shot(tester, '${prefix}a_peek', wait: 0);
    await tester.tapAt(boardRect(tester).center);
    await tester.pump(const Duration(milliseconds: 16));
    expect(state(tester).peeking, isFalse, reason: 'a tap ends Peek at once');
    await tester.pump(const Duration(milliseconds: 220));
    await shot(tester, '${prefix}b_flying_back', wait: 0);
    await settle(tester, 1200);
    expect(state(tester).selected, isNull, reason: 'the tap did not pick a card');
  }

  Future<void> pause(WidgetTester tester) async {
    await tester.tap(find.byIcon(CupertinoIcons.pause_fill), warnIfMissed: false);
    await settle(tester, 900);
  }

  void accessibility(WidgetTester tester, Accessibility a) => container(tester).read(settingsProvider.notifier).setAccessibility(a);

  testWidgets('the picture before the deal, Peek, Shuffle, Discard, Today card, inbox', (tester) async {
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
        // The real inbox (the launch message to every player) and a friend's gift on this device.
        inboxMessagesProvider.overrideWith((ref) async {
          final userId = ref.watch(currentUserIdProvider);
          if (userId == null) return const [];
          final rows = await listAllRows(ref.read(tablesProvider), AppwriteConfig.messages, [
            Query.lessThanEqual('sentAt', DateTime.now().toUtc().toIso8601String()),
            Query.orderDesc('sentAt'),
          ]);
          return [_friendGift, for (final models.Row r in rows) InboxMessage.fromRow(r.$id, r.data)];
        }),
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

    // ---- Today's picture from Home: the picture first, then the deal.
    await shot(tester, 'bs_00_home');
    final daily = c.read(dailyPuzzleProvider)!;
    await play(tester, daily.id, 'Cozy');
    await waitForBoard(tester);
    await preview(tester, 'bs_01_');

    // ---- A tap during Peek ends it at once (the owner's case: Peek felt long).
    await peekAndTap(tester, 'bs_02_');

    // ---- The Shuffle button has room for its name.
    final shuffle = tester.getRect(find.byKey(const ValueKey('booster-shuffle')));
    final label = tester.getRect(find.descendant(of: find.byKey(const ValueKey('booster-shuffle')), matching: find.text('Shuffle')));
    debugPrint('QA_SHUFFLE button $shuffle label $label');
    await shot(tester, 'bs_03_toolbar');

    // ---- Pause > Discard and pick a board (after a move): asks, then the board picker with every
    // mode and size.
    final slot = List.generate(state(tester).board.cells, (i) => i).firstWhere((i) => !state(tester).board.isLocked(i));
    await tester.tapAt(onScreen(tester, slot));
    await settle(tester, 300);
    await tester.tapAt(onScreen(tester, state(tester).board.homeOf(slot)));
    await settle(tester, 600);
    await pause(tester);
    expect(find.text('Discard and pick a board'), findsOneWidget);
    await shot(tester, 'bs_04_pause');
    await tapText(tester, 'Discard and pick a board', ms: 900);
    expect(find.text('Discard progress?'), findsOneWidget);
    await shot(tester, 'bs_05_discard_alert');
    await tapText(tester, 'Discard', ms: 1500);
    expect(find.byKey(const ValueKey('discard-progress')), findsNothing, reason: 'nothing in progress: every mode and size free');
    expect(find.text('Progress discarded. Pick any mode or board.'), findsOneWidget);
    await shot(tester, 'bs_06_picker_after_discard', wait: 0);

    // ---- Again, skipped by a tap; solved; Home's Today card says when the new picture comes.
    await tapText(tester, 'Cozy', ms: 800);
    await tester.tap(find.byKey(const ValueKey('play-board')), warnIfMissed: false);
    await waitForBoard(tester);
    await preview(tester, 'bs_07_', skip: true);
    await solve(tester);
    await settle(tester, 3000);
    expect(find.text('Picture complete'), findsOneWidget);
    router.go('/home');
    await settle(tester, 2500);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 600));
    await settle(tester, 1200);
    expect(find.textContaining('New picture in'), findsOneWidget);
    expect(find.text("Tomorrow's daily puzzle"), findsNothing);
    await shot(tester, 'bs_08_home_today_solved');

    // ---- A pack picture, finished, then Next puzzle: the next picture shows before its deal.
    final packs = await c.read(packsProvider.future);
    final all = await c.read(allPuzzlesProvider.future);
    final pack = packs.firstWhere((p) => p.isFree && !p.isDaily && !p.hasWindow && !isGiantPack(p) && all.where((z) => z.packId == p.id).length > 2);
    final pictures = all.where((p) => p.packId == pack.id).toList()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    await play(tester, pictures.first.id, 'Cozy');
    await waitForBoard(tester);
    await settle(tester, 3000);
    await solve(tester);
    await settle(tester, 3000);
    expect(find.text('Next puzzle'), findsOneWidget);
    await shot(tester, 'bs_09_finished');
    await tester.tap(find.text('Next puzzle').last, warnIfMissed: false);
    await waitForBoard(tester, fresh: true);
    await preview(tester, 'bs_10_next_');

    // ---- Shuffle and restart with Reduce motion: the picture fades into the deal.
    accessibility(tester, const Accessibility(reduceMotion: true));
    await settle(tester, 600);
    final loose = List.generate(state(tester).board.cells, (i) => i).where((i) => !state(tester).board.isLocked(i)).toList();
    await tester.tapAt(onScreen(tester, loose.first));
    await settle(tester, 300);
    await tester.tapAt(onScreen(tester, loose.last));
    await settle(tester, 700);
    await pause(tester);
    await tapText(tester, 'Shuffle and restart', ms: 900);
    if (find.text('Shuffle and restart?').evaluate().isNotEmpty) {
      await tester.tap(find.text('Shuffle').last, warnIfMissed: false);
    }
    for (var i = 0; i < 20 && !state(tester).previewing; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(state(tester).previewing, isTrue, reason: 'a new deal opens on the picture too');
    await shot(tester, 'bs_11_reduced_picture', wait: 0);
    while (state(tester).previewing) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    await tester.pump(const Duration(milliseconds: 200));
    await shot(tester, 'bs_11_reduced_fading', wait: 0);
    await settle(tester, 1500);
    await shot(tester, 'bs_11_reduced_dealt', wait: 0);
    accessibility(tester, const Accessibility());
    await pause(tester);
    await tapText(tester, 'Save & quit', ms: 2500);

    // ---- The SE width with the largest text: the toolbar keeps its labels whole and nothing
    // overflows (a layout error fails the run). The screen keeps showing the full-size frame once the
    // window is made smaller, so the look is checked in the design QA harness ("emulate": "se").
    tester.view.physicalSize = Size(375 * tester.view.devicePixelRatio, 667 * tester.view.devicePixelRatio);
    accessibility(tester, const Accessibility(textSize: TextSize.largest));
    await settle(tester, 800);
    router.push('/game/${pictures[1].id}/cards-3x3t0');
    await waitForBoard(tester);
    await settle(tester, 3500);
    final seShuffle = tester.getRect(find.byKey(const ValueKey('booster-shuffle')));
    final seLabel = tester.getRect(find.descendant(of: find.byKey(const ValueKey('booster-shuffle')), matching: find.text('Shuffle')));
    debugPrint('QA_SHUFFLE_SE button $seShuffle label $seLabel');
    expect(seLabel.width, lessThanOrEqualTo(seShuffle.width), reason: 'the name fits its button');
    await pause(tester);
    expect(find.text('Discard and pick a board'), findsOneWidget);
    await tapText(tester, 'Resume', ms: 600);
    await pause(tester);
    await tapText(tester, 'Save & quit', ms: 2500);
    tester.view.resetPhysicalSize();
    accessibility(tester, const Accessibility());
    await settle(tester, 800);

    // ---- A giant board: a shorter picture, then the deal; a tap ends Peek there too.
    final giant = packs.firstWhere(isGiantPack);
    final profile = c.read(profileProvider.notifier);
    await profile.addTickets(giant.priceTickets, reason: 'qa:giant');
    await settle(tester, 800);
    expect(await profile.unlockPack(giant), isTrue);
    final giantPictures = all.where((p) => p.packId == giant.id).toList();
    await play(tester, giantPictures.first.id, 'Large');
    await waitForBoard(tester);
    await preview(tester, 'bs_14_giant_');
    await peekAndTap(tester, 'bs_15_giant_');
    await pause(tester);
    await tapText(tester, 'Save & quit', ms: 2500);

    // ---- The first board's hint waits for the deal.
    store.tutorialSeen = false;
    c.invalidate(settingsProvider);
    await settle(tester, 600);
    router.push('/game/${pictures[2].id}/cards-3x3t0');
    await waitForBoard(tester);
    expect(find.byKey(const ValueKey('coach')), findsNothing, reason: 'the picture first');
    await shot(tester, 'bs_16_first_board_picture', wait: 0);
    await settle(tester, 3000);
    expect(find.byKey(const ValueKey('coach')), findsOneWidget, reason: 'then the first hint');
    await shot(tester, 'bs_17_first_board_hint', wait: 0);
    await tester.tap(find.byKey(const ValueKey('coach-close')), warnIfMissed: false);
    await settle(tester, 800);
    await pause(tester);
    await tapText(tester, 'Save & quit', ms: 2500);

    // ---- Social > Inbox: Carden's gift, claimed; a friend's gift.
    router.go('/social');
    await settle(tester, 2500);
    await tapText(tester, 'Inbox', ms: 2500);
    for (var i = 0; i < 10 && find.text('Celebrating Carden 2.0').evaluate().isEmpty; i++) {
      await settle(tester, 1000);
    }
    await shot(tester, 'bs_20_inbox');
    await tapText(tester, 'Celebrating Carden 2.0', ms: 1500);
    expect(find.byKey(const ValueKey('message-claim')), findsOneWidget);
    await shot(tester, 'bs_21_message');
    await tester.tap(find.byKey(const ValueKey('message-claim')), warnIfMissed: false);
    await settle(tester, 2500);
    expect(find.byKey(const ValueKey('message-claimed')), findsOneWidget);
    await shot(tester, 'bs_22_message_claimed');
    await tester.drag(find.byKey(const ValueKey('sheet-grabber')), const Offset(0, 500)); // closes the sheet
    await settle(tester, 1200);
    await tapText(tester, 'Ava sent you a gift', ms: 1500);
    expect(find.byKey(const ValueKey('message-gift-avatar')), findsOneWidget);
    await shot(tester, 'bs_23_friend_gift');
    await tester.drag(find.byKey(const ValueKey('sheet-grabber')), const Offset(0, 500)); // closes the sheet
    await settle(tester, 1200);

    // Dark, Increase contrast, the largest text.
    final settings = c.read(settingsProvider.notifier);
    Future<void> openBoth(String name) async {
      await tapText(tester, 'Celebrating Carden 2.0', ms: 1500);
      await shot(tester, '${name}_carden');
      await tester.drag(find.byKey(const ValueKey('sheet-grabber')), const Offset(0, 500)); // closes the sheet
      await settle(tester, 1200);
      await tapText(tester, 'Ava sent you a gift', ms: 1500);
      await shot(tester, '${name}_friend');
      await tester.drag(find.byKey(const ValueKey('sheet-grabber')), const Offset(0, 500)); // closes the sheet
      await settle(tester, 1200);
    }

    settings.setThemeMode(ThemeMode.dark);
    await settle(tester, 800);
    await openBoth('bs_24_dark');
    accessibility(tester, const Accessibility(increaseContrast: true));
    await settle(tester, 800);
    await openBoth('bs_25_dark_contrast');
    settings.setThemeMode(ThemeMode.light);
    await settle(tester, 800);
    await openBoth('bs_26_light_contrast');
    accessibility(tester, const Accessibility(textSize: TextSize.largest));
    await settle(tester, 800);
    await openBoth('bs_27_largest');
    accessibility(tester, const Accessibility());
    settings.setThemeMode(ThemeMode.system);
    await settle(tester, 600);
  });
}
