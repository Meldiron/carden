import 'package:carden/data/local_store.dart';
import 'package:carden/game/board.dart';
import 'package:carden/models/models.dart';
import 'package:carden/state/catalog.dart';
import 'package:carden/state/first_steps.dart';
import 'package:carden/state/achievements.dart';
import 'package:carden/state/profile.dart';
import 'package:carden/state/progress.dart';
import 'package:carden/state/rewards.dart';
import 'package:carden/state/social.dart';
import 'package:carden/state/settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The guided start (owner, 2026-10-16; lib/state/first_steps.dart, docs/first-steps.md).
void main() {
  /// XP that reaches [level] on the level curve.
  int xpFor(int level) {
    var xp = 0;
    for (var l = 1; l < level; l++) {
      xp += Profile.xpForLevel(l);
    }
    return xp;
  }

  Future<ProviderContainer> container({Map<String, Object> prefs = const {}, int solved = 0, int level = 1}) async {
    SharedPreferences.setMockInitialValues(prefs);
    final store = await LocalStore.open();
    final c = ProviderContainer(overrides: [
      localStoreProvider.overrideWithValue(store),
      countedSolvesProvider.overrideWith((ref) => solved),
      // A first pack with a picture left (an empty or finished one opens the Library by itself).
      allPuzzlesProvider.overrideWith((ref) async => [_unsolved]),
      profileProvider.overrideWith(() => _Profile(xpFor(level))),
    ]);
    addTearDown(c.dispose);
    await c.read(profileProvider.future);
    return c;
  }

  const guided = {'firstSteps': '{"guided":true}'};
  // A guided player who reached Home before the pictures in these tests: every picture counts.
  const home = {'firstSteps': '{"guided":true,"startedAt":"2026-10-01T00:00:00Z","homeAt":"2026-10-01T00:00:01Z"}'};

  test('players who started before have no record and see everything', () async {
    final c = await container();
    expect(c.read(firstStepsProvider).calm, isFalse);
    expect(c.read(revealsProvider), Reveal.values.toSet());
    expect(c.read(nextStepProvider), isNull);
    expect(c.read(upcomingRevealsProvider), isEmpty);
  });

  test('onboarding marks a new player once, and a device that already chose keeps its choice', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    await FirstSteps.markNewPlayer(store);
    expect(FirstSteps.fromJson(store.getJson(FirstSteps.storeKey)).calm, isTrue);
    await store.setJson(FirstSteps.storeKey, const FirstSteps(guided: true, showEverything: true).toJson());
    await FirstSteps.markNewPlayer(store);
    expect(FirstSteps.fromJson(store.getJson(FirstSteps.storeKey)).calm, isFalse, reason: 'Unlock anyway is not undone by signing in later');
    await FirstSteps.skipFor(store);
    final skipped = FirstSteps.fromJson(store.getJson(FirstSteps.storeKey));
    expect((skipped.guided, skipped.firstBoard, store.tutorialSeen), (false, false, true));
  });

  test('the record survives a round trip', () {
    final at = DateTime.utc(2026, 10, 17, 9);
    final s = FirstSteps(guided: true, showEverything: true, everythingAt: at, firstBoard: false, tips: const {'stuck', 'tab:quests'}, early: {'social': at});
    final back = FirstSteps.fromJson(s.toJson());
    expect((back.guided, back.showEverything, back.firstBoard, back.everythingAt), (true, true, false, at));
    expect(back.tips, {'stuck', 'tab:quests'});
    expect(back.early, {'social': at});
    expect(FirstSteps.fromJson(const {'guided': true, 'early': ['quests']}).early.keys, ['quests'], reason: 'the first record kept names only');
  });

  test('the owner\'s schedule: each thing opens after a number of pictures solved', () {
    expect({for (final r in Reveal.values) r.name: r.solves}, {
      'library': 3,
      'quickPlay': 3,
      'daily': 5,
      'saveProgress': 5,
      'streak': 10,
      'wheel': 15,
      'quests': 20,
      'promos': 20,
      'achievements': 25,
      'piggy': 30,
      'liveEvents': 35,
      'social': 50,
    });
  });

  test('a new player starts with only the basics; Home and the tabs grow with pictures solved', () async {
    Future<Set<Reveal>> at(int solved) async => (await container(prefs: guided, solved: solved)).read(revealsProvider);
    expect(await at(0), isEmpty);
    expect(await at(1), isEmpty);
    expect(await at(2), isEmpty, reason: 'until the Library opens, Home suggests the only picture to play');
    expect(await at(3), {Reveal.library, Reveal.quickPlay});
    expect(await at(5), {Reveal.library, Reveal.quickPlay, Reveal.daily, Reveal.saveProgress});
    expect((await at(10)).contains(Reveal.streak), isTrue);
    expect((await at(19)).containsAll({Reveal.wheel}) && !(await at(19)).contains(Reveal.quests), isTrue);
    expect((await at(49)).contains(Reveal.social), isFalse);
    expect(await at(50), Reveal.values.toSet());
    // The level does not count: a level-12 player with 3 pictures still waits for the daily puzzle.
    expect((await container(prefs: guided, solved: 3, level: 12)).read(revealsProvider).contains(Reveal.daily), isFalse);
  });

  test('Unlock anyway opens one tab or section, or everything from Home', () async {
    final c = await container(prefs: guided);
    c.read(firstStepsProvider.notifier).openEarly(Reveal.social);
    expect(c.read(revealsProvider), {Reveal.social});
    expect(c.read(newTabsProvider), isEmpty, reason: 'opened by the player: no "new" dot');
    expect(c.read(upcomingRevealsProvider).contains(Reveal.social), isFalse);
    c.read(firstStepsProvider.notifier).showEverything();
    expect(c.read(revealsProvider), Reveal.values.toSet());
    expect(c.read(upcomingRevealsProvider), isEmpty);
  });

  test('a tab that opens by playing keeps a dot until it is visited', () async {
    final c = await container(prefs: guided, solved: 20);
    expect(c.read(newTabsProvider), {Reveal.library.tab, Reveal.quests.tab}, reason: 'neither was visited yet');
    c.read(firstStepsProvider.notifier).sawTip('tab:quests');
    expect(c.read(newTabsProvider), {Reveal.library.tab});
  });

  test('the list of what is to come shows the nearest first', () async {
    final c = await container(prefs: guided, solved: 1);
    expect(c.read(upcomingRevealsProvider).take(4), [Reveal.library, Reveal.daily, Reveal.streak, Reveal.wheel]);
  });

  test('alerts and the list say when each thing opens', () {
    // How many more, from what the player has (owner: "2 more pictures").
    expect(Reveal.quests.opensTitle(1), 'Quests open after 19 more pictures');
    expect(Reveal.social.opensTitle(0), 'Social opens after 50 more pictures');
    expect(Reveal.daily.opensTitle(4), 'Daily puzzle opens after 1 more picture');
    expect(Reveal.liveEvents.more(30), '5 more pictures');
    expect(Reveal.library.opensTitle(1), 'Library opens after 2 more pictures');
    // A locked card sits under its section's header: its title says only when (one line).
    expect(Reveal.achievements.opensAfter(1), 'Opens after 24 more pictures');
    expect(Reveal.liveEvents.opensAfter(34), 'Opens after 1 more picture');
    expect([for (final r in Reveal.values) if (r.listed) r.name], ['library', 'daily', 'streak', 'wheel', 'quests', 'achievements', 'piggy', 'liveEvents', 'social']);
  });

  group('quests and achievements count only after they open', () {
    final start = DateTime(2026, 10, 12, 8); // a Monday
    PuzzleProgress solved(int i, {int stars = 3}) => PuzzleProgress.fromRow('r$i', {
          'userId': 'u',
          'puzzleId': 'p$i',
          'gridSize': 9,
          'completed': true,
          'stars': stars,
          'completedAt': start.add(Duration(minutes: 10 * i)).toIso8601String(),
        });
    Map<String, PuzzleProgress> rows(int n) => {for (var i = 1; i <= n; i++) 'p$i': solved(i)};

    Future<ProviderContainer> with_(Map<String, PuzzleProgress> progress, {Map<String, Object> prefs = home}) async {
      SharedPreferences.setMockInitialValues(prefs);
      final store = await LocalStore.open();
      final c = ProviderContainer(overrides: [
        localStoreProvider.overrideWithValue(store),
        progressProvider.overrideWith(() => _Rows(progress)),
        profileProvider.overrideWith(() => _Profile(0)),
        friendsProvider.overrideWith((ref) async => const []),
        allPuzzlesProvider.overrideWith((ref) async => [_unsolved]),
      ]);
      addTearDown(c.dispose);
      await c.read(progressProvider.future);
      await c.read(profileProvider.future);
      return c;
    }

    test('after onboarding only the first picture counts until Home is reached, then every one', () async {
      final started = start.subtract(const Duration(minutes: 1)).toUtc().toIso8601String();
      // The first board and two more from its finish, Home not reached yet: one counts.
      final before = await with_(rows(3), prefs: {'firstSteps': '{"guided":true,"startedAt":"$started"}'});
      expect(before.read(countedSolvesProvider), 1);
      expect(before.read(solvedCountProvider), 3);
      // Home reached after those three, then two more: 1 + 2.
      final homeAt = start.add(const Duration(minutes: 35)).toUtc().toIso8601String();
      final after = await with_(rows(5), prefs: {'firstSteps': '{"guided":true,"startedAt":"$started","homeAt":"$homeAt"}'});
      expect(after.read(countedSolvesProvider), 3);
      // A returning account: everything finished before onboarding here counts.
      final late = start.add(const Duration(hours: 6)).toUtc().toIso8601String();
      final back = await with_(rows(30), prefs: {'firstSteps': '{"guided":true,"startedAt":"$late"}'});
      expect(back.read(countedSolvesProvider), 30);
      expect(back.read(revealsProvider).contains(Reveal.piggy), isTrue);
    });

    test('Settings > Guided start back on keeps what the player reached, with no "new" dots', () async {
      // The real count, not an override: setGuided once read countedSolvesProvider, which watches
      // firstStepsProvider, a circular dependency that threw in debug builds.
      final c = await with_(rows(22), prefs: {'firstSteps': '{"guided":true,"showEverything":true,"startedAt":"2026-10-01T00:00:00Z","homeAt":"2026-10-01T00:00:01Z"}'});
      expect(c.read(countedSolvesProvider), 22);
      c.read(firstStepsProvider.notifier).setGuided(true);
      expect(c.read(firstStepsProvider).calm, isTrue);
      expect(c.read(revealsProvider).containsAll({Reveal.daily, Reveal.streak, Reveal.wheel, Reveal.quests}), isTrue);
      expect(c.read(revealsProvider).contains(Reveal.achievements), isFalse);
      expect(c.read(newTabsProvider), isEmpty);
    });

    test('reaching Home starts the count once', () async {
      final c = await with_(rows(1), prefs: {'firstSteps': '{"guided":true}'});
      c.read(firstStepsProvider.notifier).arrivedHome();
      final at = c.read(firstStepsProvider).homeAt;
      expect(at, isNotNull);
      c.read(firstStepsProvider.notifier).arrivedHome();
      expect(c.read(firstStepsProvider).homeAt, at);
    });

    test('a player without the guided start counts everything', () async {
      final c = await with_(rows(3), prefs: const {});
      expect(c.read(countsFromProvider(Reveal.quests)).millisecondsSinceEpoch, 0);
      expect(c.read(achievementsProvider).firstWhere((a) => a.family.id == 'solver').progress, 3);
    });

    test('while locked nothing counts; opened by playing, from the picture that opened it', () async {
      final locked = await with_(rows(19));
      expect(locked.read(countsFromProvider(Reveal.quests)).year, 9999);
      final open = await with_(rows(24));
      expect(open.read(countsFromProvider(Reveal.quests)), solved(20).completedAt);
      // Four pictures after the 20th: "Solve 3 puzzles" today is ready, from those four only.
      final q = Goals.daily(rows(24).values, start.add(const Duration(hours: 5)), since: open.read(countsFromProvider(Reveal.quests)));
      expect(q.firstWhere((g) => g.title == 'Solve 3 puzzles').progress, 4);
      // Achievements are still locked at 24: their solver count is 0, not 24.
      expect(open.read(achievementsProvider).firstWhere((a) => a.family.id == 'solver').progress, 0);
    });

    test('achievements opened at 25 count the pictures after the 25th, and stars from those only', () async {
      final c = await with_(rows(28));
      final solver = c.read(achievementsProvider).firstWhere((a) => a.family.id == 'solver');
      expect(solver.progress, 3);
      expect(c.read(achievementsProvider).firstWhere((a) => a.family.id == 'starhoarder').progress, 9);
    });

    test('Unlock anyway counts from that moment', () async {
      final c = await with_(rows(2));
      c.read(firstStepsProvider.notifier).openEarly(Reveal.quests);
      final from = c.read(countsFromProvider(Reveal.quests));
      expect(DateTime.now().difference(from).inSeconds, lessThan(5));
      expect(c.read(achievementsProvider).firstWhere((a) => a.family.id == 'solver').progress, 0, reason: 'achievements are still locked');
    });
  });

  group('the first pack played through before Home', () {
    final start = DateTime(2026, 10, 12, 8);
    final pack = [for (var i = 1; i <= 24; i++) Puzzle.fromRow(i == 1 ? firstBoardPuzzle : 'tb-$i', {'packId': firstBoardPack, 'title': 'Beach $i', 'sortOrder': i})];
    final other = Puzzle.fromRow('other-1', {'packId': 'wild-nature', 'title': 'Other', 'sortOrder': 1});
    PuzzleProgress solved(Puzzle z, int i) => PuzzleProgress.fromRow('r$i', {
          'userId': 'u',
          'puzzleId': z.id,
          'gridSize': 9,
          'completed': true,
          'stars': 3,
          'completedAt': start.add(Duration(minutes: 5 * i)).toIso8601String(),
        });

    Future<ProviderContainer> after(int finished) async {
      // Onboarding just before the first picture; Home reached only after all of them.
      final prefs = {'firstSteps': '{"guided":true,"startedAt":"${start.toUtc().toIso8601String()}","homeAt":"${start.add(const Duration(hours: 5)).toUtc().toIso8601String()}"}'};
      SharedPreferences.setMockInitialValues(prefs);
      final store = await LocalStore.open();
      final c = ProviderContainer(overrides: [
        localStoreProvider.overrideWithValue(store),
        progressProvider.overrideWith(() => _Rows({for (var i = 0; i < finished; i++) pack[i].id: solved(pack[i], i + 1)})),
        profileProvider.overrideWith(() => _Profile(xpFor(4))),
        allPuzzlesProvider.overrideWith((ref) async => [...pack, other]),
        packsProvider.overrideWith((ref) async => const <Pack>[]),
      ]);
      addTearDown(c.dispose);
      await c.read(progressProvider.future);
      await c.read(allPuzzlesProvider.future);
      await c.read(profileProvider.future);
      return c;
    }

    test('one picture counts, but with nothing left in the pack the Library opens by itself', () async {
      final c = await after(24);
      expect(c.read(countedSolvesProvider), 1);
      expect(c.read(firstPackDoneProvider), isTrue);
      expect(c.read(revealsProvider), {Reveal.library}, reason: 'only the Library: Quick play and the rest keep their counts');
      expect(c.read(newTabsProvider), {Reveal.library.tab}, reason: 'the Library tab gets its dot');
      expect(c.read(nextStepProvider)?.route, '/library', reason: 'Home points to the Library, which is open');
    });

    test('with a picture left in the pack, it is still the next step and the Library waits', () async {
      final c = await after(23);
      expect(c.read(firstPackDoneProvider), isFalse);
      expect(c.read(revealsProvider).contains(Reveal.library), isFalse);
      expect(c.read(nextStepProvider)?.puzzle?.id, pack.last.id);
    });
  });

  test('the first board is nine cards on Cards, the smallest board', () {
    expect(firstBoardSpec.cells, 9);
    expect(BoardCode.toPath(firstBoardSpec.fullCode), 'cards-3x3');
    final back = BoardSpec.fromCode(BoardCode.fromPath('cards-3x3'));
    expect((back.mode, back.cols, back.rows), (firstBoardSpec.mode, 3, 3));
  });
}

final _unsolved = Puzzle.fromRow('tb-left', {'packId': firstBoardPack, 'title': 'Left to play', 'sortOrder': 99});

class _Rows extends ProgressNotifier {
  _Rows(this.rows);
  final Map<String, PuzzleProgress> rows;
  @override
  Future<Map<String, PuzzleProgress>> build() async => rows;
}

class _Profile extends ProfileNotifier {
  _Profile(this.xp);
  final int xp;

  @override
  Future<Profile> build() async => Profile.guest('u1').copyWith(xp: xp);
}
