// Home's streak card numbers its dots by the streak (owner, 2026-10-18: on day 8 the card showed dots
// 1 to 7 with dot 1 current, so the streak looked reset). The second week is Day 8 to 14, the third
// Day 15 to 21, and VoiceOver reads each dot as its day. A missed day starts again at Day 1.
import 'package:appwrite/models.dart' as models;
import 'package:carden/core/theme/app_theme.dart';
import 'package:carden/data/local_store.dart';
import 'package:carden/features/home/home_screen.dart';
import 'package:carden/models/models.dart';
import 'package:carden/state/auth.dart';
import 'package:carden/state/catalog.dart';
import 'package:carden/state/profile.dart';
import 'package:carden/state/progress.dart';
import 'package:carden/state/settings.dart';
import 'package:carden/state/unlocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoAuth extends AuthNotifier {
  @override
  Future<models.User?> build() async => null;
}

Map<String, dynamic> _patch = const {};

class _Profile extends ProfileNotifier {
  @override
  Future<Profile> build() async {
    final g = Profile.guest('local');
    return Profile.fromRow(g.id, {...g.toData(), ..._patch});
  }
}

Pack _pack(String id, {String category = 'Nature', int sortOrder = 0}) =>
    Pack.fromRow(id, {'name': 'Pack $id', 'category': category, 'sortOrder': sortOrder, 'imageCount': 4});

List<Puzzle> _pictures(String packId, int n) => [
      for (var i = 1; i <= n; i++) Puzzle.fromRow('$packId-$i', {'packId': packId, 'title': 'Picture $i', 'sortOrder': i}),
    ];

class _Rows extends ProgressNotifier {
  @override
  Future<Map<String, PuzzleProgress>> build() async => const {};
}

void main() {
  final now = DateTime.now();
  String ago(int days) => now.subtract(Duration(days: days)).toUtc().toIso8601String();
  final today = now.toUtc().toIso8601String();
  final packs = [_pack('daily-2026-10', category: 'Daily', sortOrder: -1), for (var i = 1; i <= 4; i++) _pack('lib$i', sortOrder: 10 - i)];
  final pictures = [for (final p in packs) ..._pictures(p.id, 4)];

  // State: profile columns, the title, the first dot's day, and the dots VoiceOver names with a state.
  final states = <String, (Map<String, dynamic>, String, int, List<String>)>{
    'day 7 to claim': ({'streak': 6, 'lastDailyClaim': ago(1)}, '6-day streak', 1, ['Day 1, claimed', 'Day 6, claimed', 'Day 7, today']),
    'day 7 claimed': ({'streak': 7, 'lastDailyClaim': today}, '7-day streak', 1, ['Day 1, claimed', 'Day 7, claimed']),
    'day 8 to claim': ({'streak': 7, 'lastDailyClaim': ago(1)}, '7-day streak', 8, ['Day 8, today', 'Day 9']),
    'day 8 claimed': ({'streak': 8, 'lastDailyClaim': today}, '8-day streak', 8, ['Day 8, claimed', 'Day 9, tomorrow', 'Day 10']),
    'day 14 claimed': ({'streak': 14, 'lastDailyClaim': today}, '14-day streak', 8, ['Day 8, claimed', 'Day 14, claimed']),
    'day 15 to claim': ({'streak': 14, 'lastDailyClaim': ago(1)}, '14-day streak', 15, ['Day 15, today', 'Day 21']),
    'day 365 to claim': ({'streak': 364, 'lastDailyClaim': ago(1)}, '364-day streak', 365, ['Day 365, today', 'Day 371']),
    'a missed day starts again': ({'streak': 9, 'lastDailyClaim': ago(5)}, 'Streak ended', 1, ['Day 1, today', 'Day 2']),
  };

  for (final s in states.entries) {
    testWidgets('Home streak card: ${s.key}', (tester) async {
      final (patch, title, first, spoken) = s.value;
      _patch = {...patch, 'longestStreak': patch['streak']};
      final semantics = tester.ensureSemantics();
      tester.view.physicalSize = const Size(402, 874);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final store = await LocalStore.open();
      final router = GoRouter(initialLocation: '/home', routes: [GoRoute(path: '/home', builder: (_, _) => const HomeScreen())]);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          localStoreProvider.overrideWithValue(store),
          authProvider.overrideWith(_NoAuth.new),
          profileProvider.overrideWith(_Profile.new),
          progressProvider.overrideWith(_Rows.new),
          packsProvider.overrideWith((ref) async => packs),
          allPuzzlesProvider.overrideWith((ref) async => pictures),
          eventsProvider.overrideWith((ref) async => const <GameEvent>[]),
          pendingUnlockIntroProvider.overrideWithValue(null),
        ],
        child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
      ));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text(title), 200, scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(find.text(title), findsOneWidget);
      for (var day = first; day < first + 7; day++) {
        expect(find.text('$day'), findsWidgets, reason: 'dot $day of the week from $first');
      }
      for (final label in spoken) {
        expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
      }
      if (first > 1) expect(find.bySemanticsLabel(RegExp(r'^Day 1(,|$)')), findsNothing, reason: 'a running streak never shows Day 1 again');
      semantics.dispose();
    });
  }
}
