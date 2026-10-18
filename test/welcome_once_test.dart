// The welcome pages, once (owner, TestFlight 2026-10-18: "When I skip first onboarding slides, it
// keeps showing again and again every time I open app"). Skip ends them for good at the tap, even
// while the first board's picture is still on its way, and the next launch with what was saved starts
// on Home. Also: the buttons under the pages follow the swipe to the last page.
import 'dart:async';

import 'package:appwrite/models.dart' as models;
import 'package:carden/core/theme/app_theme.dart';
import 'package:carden/data/local_store.dart';
import 'package:carden/features/home/home_screen.dart';
import 'package:carden/features/onboarding/onboarding_screen.dart';
import 'package:carden/models/models.dart';
import 'package:carden/router.dart';
import 'package:carden/state/auth.dart';
import 'package:carden/state/catalog.dart';
import 'package:carden/state/first_steps.dart';
import 'package:carden/state/profile.dart';
import 'package:carden/state/progress.dart';
import 'package:carden/state/settings.dart';
import 'package:carden/state/unlocks.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoAuth extends AuthNotifier {
  @override
  Future<models.User?> build() async => null;
}

class _GuestProfile extends ProfileNotifier {
  @override
  Future<Profile> build() async => Profile.guest('local');
}

class _NoRows extends ProgressNotifier {
  @override
  Future<Map<String, PuzzleProgress>> build() async => const {};
}

/// The app as `main()` starts it, on [store], with the catalogue arriving when [catalogue] completes.
Future<void> _launch(WidgetTester tester, LocalStore store, Future<List<Puzzle>> catalogue) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      localStoreProvider.overrideWithValue(store),
      authProvider.overrideWith(_NoAuth.new),
      profileProvider.overrideWith(_GuestProfile.new),
      progressProvider.overrideWith(_NoRows.new),
      packsProvider.overrideWith((ref) async => const <Pack>[]),
      allPuzzlesProvider.overrideWith((ref) => catalogue),
      eventsProvider.overrideWith((ref) async => const <GameEvent>[]),
      pendingUnlockIntroProvider.overrideWithValue(null),
    ],
    child: Consumer(builder: (context, ref, _) => MaterialApp.router(theme: AppTheme.dark(), routerConfig: ref.watch(routerProvider))),
  ));
  await tester.pump(const Duration(milliseconds: 500));
}

/// What is on disk when the app is closed: a new launch reads only this.
Future<LocalStore> _relaunchStore() async {
  final prefs = await SharedPreferences.getInstance();
  final saved = <String, Object>{for (final k in prefs.getKeys()) k: prefs.get(k)!};
  SharedPreferences.setMockInitialValues(saved);
  return LocalStore.open();
}

double _opacityOf(WidgetTester tester, Finder f) => tester.widget<Opacity>(find.ancestor(of: f, matching: find.byType(Opacity)).first).opacity;

void main() {
  testWidgets('Skip, close the app while the first board loads, open it again: Home, not the welcome pages', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final first = await LocalStore.open();
    // A slow first launch: the catalogue (and with it the first board) is still on its way.
    final catalogue = Completer<List<Puzzle>>();
    await _launch(tester, first, catalogue.future);
    expect(find.byType(OnboardingScreen), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('welcome-skip')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(first.onboarded, isTrue, reason: 'saved at the tap, before the wait for the first board');
    expect(find.byType(CupertinoActivityIndicator), findsOneWidget, reason: 'the button says it is on its way');
    expect(first.getJson(FirstSteps.storeKey)?['guided'], isTrue, reason: 'the guided start is recorded too');

    // The player closes the app now.
    catalogue.complete(const <Puzzle>[]);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    final second = await _relaunchStore();
    expect(second.onboarded, isTrue);
    await _launch(tester, second, Future.value(const <Puzzle>[]));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(OnboardingScreen), findsNothing, reason: 'the welcome pages never come back');
    expect(find.byType(HomeScreen), findsOneWidget);

    // And once more, from Home.
    await tester.pumpWidget(const SizedBox());
    final third = await _relaunchStore();
    await _launch(tester, third, Future.value(const <Puzzle>[]));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(OnboardingScreen), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('the buttons under the pages follow the swipe to the last page', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    await _launch(tester, store, Future.value(const <Puzzle>[]));
    final pages = tester.widget<PageView>(find.byType(PageView)).controller!;
    final width = tester.getSize(find.byType(PageView)).width;
    final skip = find.byKey(const ValueKey('welcome-skip'));

    // Page 2: Continue and Skip, nothing of Start playing.
    pages.jumpTo(width);
    await tester.pump();
    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('Start playing'), findsNothing);
    expect(_opacityOf(tester, skip), 1);

    // Halfway to the last page: the labels cross-fade and Skip is on its way out.
    pages.jumpTo(width * 1.5);
    await tester.pump();
    final out = _opacityOf(tester, find.text('Continue')), into = _opacityOf(tester, find.text('Start playing')), leaving = _opacityOf(tester, skip);
    expect(out, inExclusiveRange(0, 1));
    expect(into, inExclusiveRange(0, 1));
    expect(leaving, inExclusiveRange(0, 1));

    // Further on, further along.
    pages.jumpTo(width * 1.8);
    await tester.pump();
    expect(_opacityOf(tester, find.text('Start playing')), greaterThan(into));
    expect(_opacityOf(tester, skip), lessThan(leaving));

    // The last page: Start playing, and Skip gone but its room kept (the button does not move).
    final buttonTop = tester.getTopLeft(find.byKey(const ValueKey('welcome-next'))).dy;
    pages.jumpTo(width * 2);
    await tester.pump();
    expect(find.text('Continue'), findsNothing);
    expect(find.text('Start playing'), findsOneWidget);
    expect(_opacityOf(tester, skip), 0);
    expect(tester.getTopLeft(find.byKey(const ValueKey('welcome-next'))).dy, buttonTop);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
