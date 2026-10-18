import 'dart:async';
import 'dart:ui' as ui;

import 'package:appwrite/models.dart' as models;
import 'package:carden/core/theme/app_theme.dart';
import 'package:carden/data/local_store.dart';
import 'package:carden/features/game/board_widget.dart';
import 'package:carden/features/game/game_screen.dart';
import 'package:carden/game/game_controller.dart';
import 'package:carden/game/image_loader.dart';
import 'package:carden/game/twins.dart';
import 'package:carden/game/twins_loader.dart';
import 'package:carden/models/models.dart';
import 'package:carden/state/auth.dart';
import 'package:carden/state/catalog.dart';
import 'package:carden/state/profile.dart';
import 'package:carden/state/progress.dart';
import 'package:carden/state/settings.dart';
import 'package:carden/state/social.dart';
import 'package:carden/state/sync.dart';
import 'package:carden/state/unlocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoAuth extends AuthNotifier {
  @override
  Future<models.User?> build() async => null;
}

class _Guest extends ProfileNotifier {
  @override
  Future<Profile> build() async => Profile.guest('player1');
}

class _NoRows extends ProgressNotifier {
  @override
  Future<Map<String, PuzzleProgress>> build() async => const {};
}

class _NoSync extends SyncController {
  @override
  SyncState build() => const SyncState();

  @override
  Future<void> sync({bool full = false, bool silent = false}) async {}
}

/// The picture before the deal on the real game screen, with a picture that arrives late (Next
/// puzzle downloads the next picture; owner, TestFlight 2026-10-18: "it goes from blurhash loading
/// directly to pieces randomly shuffled"). The picture shows only to someone who can see it: while
/// the app is not in front (iOS keeps drawing an inactive app: the screenshot editor and TestFlight
/// feedback sheet, Control Center, a call) or something covers the board, the preview waits, and
/// it starts over, whole, once the board is in view again.
void main() {
  late Completer<ui.Image> picture;
  late ui.Image image;

  Future<void> pumpGame(WidgetTester tester) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    image = (await tester.runAsync(() => createTestImage(width: 300, height: 400)))!;
    picture = Completer<ui.Image>();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        authProvider.overrideWith(_NoAuth.new),
        profileProvider.overrideWith(_Guest.new),
        progressProvider.overrideWith(_NoRows.new),
        syncProvider.overrideWith(_NoSync.new),
        resolvedPuzzleProvider.overrideWith((ref, id) => Puzzle.custom(id: id, title: 'Late picture', imageUrl: 'test://late')),
        // The picture arrives when the test says so; its twins are measured at once.
        puzzleImageProvider.overrideWith((ref, url) => picture.future),
        boardTwinsProvider.overrideWith((ref, key) async => Twins.none),
        packsProvider.overrideWith((ref) async => const <Pack>[]),
        allPuzzlesProvider.overrideWith((ref) async => const <Puzzle>[]),
        eventsProvider.overrideWith((ref) async => const <GameEvent>[]),
        pendingUnlockIntroProvider.overrideWithValue(null),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: const GameScreen(puzzleId: 'p1', gridCode: 'cards-3x3t0')),
    ));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Dealing the cards'), findsOneWidget, reason: 'the picture is on its way');
  }

  GameState state(WidgetTester tester) => tester.widget<BoardWidget>(find.byType(BoardWidget)).state;

  Future<void> arrive(WidgetTester tester) async {
    picture.complete(image);
    // The decode, the twins (at once here) and the frames that put the board up.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  /// Leaves the board: the screen and its controller go, and their timers with them.
  Future<void> leave(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('a late picture shows whole for the full time, then the cards are dealt', (tester) async {
    await pumpGame(tester);
    await tester.pump(const Duration(seconds: 3));
    await arrive(tester);
    expect(state(tester).previewing, isTrue, reason: 'the whole picture first');
    await tester.pump(GameController.previewTime - const Duration(milliseconds: 150));
    expect(state(tester).previewing, isTrue, reason: 'for the full time, counted from when it shows');
    await tester.pump(const Duration(milliseconds: 300));
    expect(state(tester).previewing, isFalse, reason: 'then the deal');
    expect(state(tester).elapsed, 0, reason: 'the clock waited for the picture and the preview');
    await leave(tester);
  });

  testWidgets('a picture that arrives while the app is not in front waits for the player', (tester) async {
    await pumpGame(tester);
    // The owner took a screenshot of "Dealing the cards" and wrote feedback over the app.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump(const Duration(milliseconds: 500));
    await arrive(tester);
    await tester.pump(const Duration(seconds: 3));
    expect(state(tester).previewing, isTrue, reason: 'nobody has seen the picture yet');
    expect(state(tester).elapsed, 0, reason: 'nor played: the clock waits');
    // Back in the app: the picture, whole, for the full time; then the deal.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(GameController.previewTime - const Duration(milliseconds: 150));
    expect(state(tester).previewing, isTrue, reason: 'the full preview after coming back');
    await tester.pump(const Duration(milliseconds: 300));
    expect(state(tester).previewing, isFalse, reason: 'then the deal');
    await leave(tester);
  });

  testWidgets('leaving the app during the preview shows it again on return', (tester) async {
    await pumpGame(tester);
    await arrive(tester);
    await tester.pump(const Duration(milliseconds: 600));
    expect(state(tester).previewing, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump(const Duration(seconds: 2));
    expect(state(tester).previewing, isTrue, reason: 'held while the app is not in front');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(GameController.previewTime - const Duration(milliseconds: 150));
    expect(state(tester).previewing, isTrue, reason: 'whole again, for the full time');
    await tester.pump(const Duration(milliseconds: 300));
    expect(state(tester).previewing, isFalse);
    await leave(tester);
  });

  testWidgets('a sheet over the board holds the preview until it closes', (tester) async {
    await pumpGame(tester);
    // Something opens over the board while the picture is on its way (a sheet, an alert).
    final context = tester.element(find.byType(GameScreen));
    unawaited(showModalBottomSheet<void>(context: context, builder: (_) => const SizedBox(height: 200, child: Text('Over the board'))));
    await tester.pump(const Duration(milliseconds: 400));
    await arrive(tester);
    await tester.pump(const Duration(seconds: 3));
    expect(state(tester).previewing, isTrue, reason: 'the sheet hides the board');
    Navigator.of(tester.element(find.text('Over the board'))).pop();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(GameController.previewTime - const Duration(milliseconds: 150));
    expect(state(tester).previewing, isTrue, reason: 'the picture, whole, once the sheet is gone');
    await tester.pump(const Duration(milliseconds: 300));
    expect(state(tester).previewing, isFalse);
    await leave(tester);
  });
}
