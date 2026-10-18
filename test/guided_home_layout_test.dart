// The guided start's Home (lib/state/first_steps.dart) at the iPhone SE, a Pro and a website window,
// in both themes, at the default and the Largest text size (200%): it renders and scrolls to the end
// without a layout error, before the first picture and after it. Also Profile's locked achievements.
import 'dart:async';

import 'package:appwrite/models.dart' as models;
import 'package:carden/core/theme/app_theme.dart';
import 'package:carden/data/local_store.dart';
import 'package:carden/features/home/home_screen.dart';
import 'package:carden/features/home/guided_start.dart';
import 'package:carden/models/models.dart';
import 'package:carden/state/auth.dart';
import 'package:carden/state/catalog.dart';
import 'package:carden/state/first_steps.dart';
import 'package:carden/state/profile.dart';
import 'package:carden/state/progress.dart';
import 'package:carden/state/settings.dart';
import 'package:carden/state/unlocks.dart';
import 'package:carden/widgets/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

Pack _pack(String id, {String category = 'Nature', int sortOrder = 0}) => Pack.fromRow(id, {'name': 'Pack $id', 'category': category, 'sortOrder': sortOrder, 'imageCount': 4, 'isFree': true});

List<Puzzle> _pictures(String packId, int n) => [
      for (var i = 1; i <= n; i++) Puzzle.fromRow(i == 1 && packId == firstBoardPack ? firstBoardPuzzle : '$packId-$i', {'packId': packId, 'title': 'Picture $i', 'sortOrder': i}),
    ];

class _NoAuth extends AuthNotifier {
  @override
  Future<models.User?> build() async => null;
}

class _Profile extends ProfileNotifier {
  @override
  Future<Profile> build() async => Profile.guest('local');
}

class _Rows extends ProgressNotifier {
  _Rows(this.rows);
  final Map<String, PuzzleProgress> rows;
  @override
  Future<Map<String, PuzzleProgress>> build() async => rows;
}

void main() {
  final packs = [_pack(firstBoardPack), for (var i = 1; i <= 6; i++) _pack('lib$i', sortOrder: i)];
  final pictures = [for (final p in packs) ..._pictures(p.id, 4)];
  final now = DateTime.now().toIso8601String();
  final states = <String, Map<String, PuzzleProgress>>{
    'before the first picture': const {},
    'after the first picture': {
      firstBoardPuzzle: PuzzleProgress.fromRow('r1', {'userId': 'u', 'puzzleId': firstBoardPuzzle, 'gridSize': 9, 'completed': true, 'stars': 3, 'completedAt': now}),
    },
  };
  for (final size in const [Size(375, 667), Size(402, 874), Size(1280, 800)]) {
    for (final dark in [false, true]) {
      for (final scale in const [1.0, 2.0]) {
        for (final s in states.entries) {
          for (final page in const ['/home']) {
            testWidgets('guided $page ${size.width.toInt()}x${size.height.toInt()} ${dark ? 'dark' : 'light'} text ${scale}x: ${s.key}', (tester) async {
              final errors = <String>{};
              final previous = FlutterError.onError;
              FlutterError.onError = (d) {
                final where = RegExp(r'lib/[a-z_/]+\.dart:\d+').firstMatch(d.toString())?.group(0) ?? '?';
                errors.add('${d.exceptionAsString().split('\n').first} @ $where');
              };
              tester.view.physicalSize = size;
              tester.view.devicePixelRatio = 1;
              addTearDown(tester.view.reset);
              SharedPreferences.setMockInitialValues({'firstSteps': '{"guided":true}'});
              final store = await LocalStore.open();
              final router = GoRouter(initialLocation: page, routes: [GoRoute(path: '/home', builder: (_, _) => const HomeScreen())]);
              await tester.pumpWidget(ProviderScope(
                overrides: [
                  localStoreProvider.overrideWithValue(store),
                  authProvider.overrideWith(_NoAuth.new),
                  profileProvider.overrideWith(_Profile.new),
                  progressProvider.overrideWith(() => _Rows(s.value)),
                  packsProvider.overrideWith((ref) async => packs),
                  allPuzzlesProvider.overrideWith((ref) async => pictures),
                  eventsProvider.overrideWith((ref) async => const <GameEvent>[]),
                  pendingUnlockIntroProvider.overrideWithValue(null),
                ],
                child: MediaQuery(
                  data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
                  child: MaterialApp.router(theme: dark ? AppTheme.dark() : AppTheme.light(), routerConfig: router),
                ),
              ));
              await tester.pumpAndSettle();
              final seen = <String>{};
              for (var i = 0; i < 12; i++) {
                for (final k in const ['next-step-first', 'next-step-pack', 'more-to-come']) {
                  if (find.byKey(ValueKey(k)).evaluate().isNotEmpty) seen.add(k);
                }
                await tester.drag(find.byType(CustomScrollView).first, const Offset(0, -500));
                await tester.pumpAndSettle();
              }
              FlutterError.onError = previous;
              expect(seen.contains('more-to-come'), isTrue, reason: 'what is still to come, blurred, with Unlock anyway');
              expect(seen.contains(s.value.isEmpty ? 'next-step-first' : 'next-step-pack'), isTrue);
              expect(find.text('Today').evaluate().length, find.descendant(of: find.byKey(const ValueKey('more-to-come')), matching: find.text('Today')).evaluate().length,
                  reason: 'the daily puzzle opens after 5 pictures: only its blurred look under More opens as you play');
              expect(find.text('Featured packs'), findsNothing, reason: 'packs join Home after 2 pictures');
              expect(errors, isEmpty);
            });
          }
        }
      }
    }
  }

  for (final scale in const [1.0, 2.0]) {
    testWidgets('Profile\'s locked achievements at the SE width, text ${scale}x', (tester) async {
      final errors = <String>[];
      final previous = FlutterError.onError;
      FlutterError.onError = (d) => errors.add(d.exceptionAsString().split('\n').first);
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({'firstSteps': '{"guided":true}'});
      final store = await LocalStore.open();
      await tester.pumpWidget(ProviderScope(
        overrides: [localStoreProvider.overrideWithValue(store), profileProvider.overrideWith(_Profile.new), progressProvider.overrideWith(() => _Rows(const {})), allPuzzlesProvider.overrideWith((ref) async => pictures)],
        child: MediaQuery(
          data: MediaQueryData(size: const Size(375, 667), textScaler: TextScaler.linear(scale)),
          child: MaterialApp(theme: AppTheme.light(), home: const Scaffold(body: SingleChildScrollView(padding: EdgeInsets.all(20), child: LockedSectionCard(reveal: Reveal.achievements)))),
        ),
      ));
      await tester.pumpAndSettle();
      final title = find.text('Opens after 25 more pictures').evaluate().length;
      final c = ProviderScope.containerOf(tester.element(find.byType(LockedSectionCard)));
      // Unlock anyway asks first, saying what waiting gives.
      await tester.tap(find.text('Unlock anyway'));
      await tester.pumpAndSettle();
      final asked = find.text('Are you sure?').evaluate().length;
      final waitFirst = c.read(revealsProvider).contains(Reveal.achievements);
      await tester.tap(find.text('Unlock Achievements'));
      await tester.pumpAndSettle();
      FlutterError.onError = previous;
      expect(title, 1);
      expect(asked, 1);
      expect(waitFirst, isFalse, reason: 'nothing opens before the player says yes');
      expect(c.read(revealsProvider).contains(Reveal.achievements), isTrue, reason: 'Unlock anyway opens it');
      expect(errors, isEmpty);
    });
  }

  testWidgets('while the catalogue loads, the top of the guided Home shows the loading frame', (tester) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({'firstSteps': '{"guided":true}'});
    final store = await LocalStore.open();
    final never = Completer<List<Puzzle>>();
    final router = GoRouter(initialLocation: '/home', routes: [GoRoute(path: '/home', builder: (_, _) => const HomeScreen())]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        authProvider.overrideWith(_NoAuth.new),
        profileProvider.overrideWith(_Profile.new),
        progressProvider.overrideWith(() => _Rows(const {})),
        packsProvider.overrideWith((ref) async => packs),
        allPuzzlesProvider.overrideWith((ref) => never.future),
        eventsProvider.overrideWith((ref) async => const <GameEvent>[]),
        pendingUnlockIntroProvider.overrideWithValue(null),
      ],
      child: MaterialApp.router(theme: AppTheme.dark(), routerConfig: router),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    final more = tester.getTopLeft(find.byKey(const ValueKey('more-to-come'))).dy;
    final loader = find.byType(Loader).evaluate().map((e) => tester.getTopLeft(find.byWidget(e.widget)).dy).where((y) => y < more);
    expect(loader, isNotEmpty, reason: 'the loading frame sits above "More opens as you play", where the picture will be');
    expect(find.descendant(of: find.byKey(const ValueKey('more-to-come')), matching: find.byType(Loader)), findsNothing, reason: 'no spinner under the blur');
    never.complete(pictures);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('next-step-first')), findsOneWidget, reason: 'then the first picture takes its place');
  });
}
