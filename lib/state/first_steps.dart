import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/analytics.dart';
import '../data/local_store.dart';
import '../game/board.dart';
import '../game/image_loader.dart';
import '../models/models.dart';
import 'catalog.dart';
import 'profile.dart';
import 'progress.dart';
import 'rewards.dart';
import 'settings.dart';
import 'unlocks.dart';

/// A new player's first steps (owner, 2026-10-16; docs/first-steps.md): the welcome pages end on
/// a first board with a hint for each step, Home starts with three things and grows as they play
/// ([Reveal]), locked tabs say when they open, and tips come at the moment they matter. "Unlock
/// anyway" opens one thing (a tab) or everything (Home) at once; Settings > Guided start turns it
/// back on. Players who started before this have no record here and see the whole app.
@immutable
class FirstSteps {
  const FirstSteps({this.guided = false, this.startedAt, this.homeAt, this.showEverything = false, this.everythingAt, this.firstBoard = true, this.tips = const {}, this.early = const {}});

  /// This device started as a new player: the guided start applies (set when onboarding ends).
  final bool guided;

  /// When onboarding ended: pictures finished before it (a returning account's) all count.
  final DateTime? startedAt;

  /// When the player first reached Home. Until then only one picture counts (the first board),
  /// however many they play from its finish; from then on every picture counts (owner, 2026-10-16).
  final DateTime? homeAt;

  /// "Unlock anyway" on Home, or Settings > Guided start off: everything is open.
  final bool showEverything;

  /// When [showEverything] was chosen: quests and achievements count from then.
  final DateTime? everythingAt;

  /// The welcome pages end on a first board (integration suites of the whole app turn it off).
  final bool firstBoard;

  /// One-time tips already shown (`tab:<name>` for a tab's "new" dot, `stuck`, `tip:library`, ...).
  final Set<String> tips;

  /// [Reveal]s opened early with "Unlock anyway" (a locked tab or section), and when.
  final Map<String, DateTime> early;

  bool get calm => guided && !showEverything;

  static const storeKey = 'firstSteps';

  factory FirstSteps.fromJson(Map<String, dynamic>? j) => FirstSteps(
        guided: j?['guided'] == true,
        startedAt: DateTime.tryParse('${j?['startedAt'] ?? ''}'),
        homeAt: DateTime.tryParse('${j?['homeAt'] ?? ''}'),
        showEverything: j?['showEverything'] == true,
        firstBoard: j?['firstBoard'] != false,
        everythingAt: DateTime.tryParse('${j?['everythingAt'] ?? ''}'),
        tips: {for (final t in (j?['tips'] as List?) ?? const []) '$t'},
        early: switch (j?['early']) {
          final Map<String, dynamic> m => {for (final e in m.entries) e.key: DateTime.tryParse('${e.value}') ?? _epoch},
          final List<dynamic> l => {for (final t in l) '$t': _epoch},
          _ => const {},
        },
      );

  Map<String, dynamic> toJson() => {
        'guided': guided,
        if (startedAt != null) 'startedAt': startedAt!.toUtc().toIso8601String(),
        if (homeAt != null) 'homeAt': homeAt!.toUtc().toIso8601String(),
        'showEverything': showEverything,
        if (everythingAt != null) 'everythingAt': everythingAt!.toUtc().toIso8601String(),
        'firstBoard': firstBoard,
        'tips': tips.toList()..sort(),
        'early': {for (final e in early.entries) e.key: e.value.toUtc().toIso8601String()},
      };

  FirstSteps copyWith({bool? guided, DateTime? homeAt, bool? showEverything, DateTime? everythingAt, bool clearEverythingAt = false, bool? firstBoard, Set<String>? tips, Map<String, DateTime>? early}) => FirstSteps(
        guided: guided ?? this.guided,
        startedAt: startedAt,
        homeAt: homeAt ?? this.homeAt,
        showEverything: showEverything ?? this.showEverything,
        everythingAt: clearEverythingAt ? null : everythingAt ?? this.everythingAt,
        firstBoard: firstBoard ?? this.firstBoard,
        tips: tips ?? this.tips,
        early: early ?? this.early,
      );

  /// Onboarding ended on this device (the welcome pages, a first link, a sign-in): a player with no
  /// record yet gets the guided start. Called by `SettingsNotifier.setOnboarded`.
  static Future<void> markNewPlayer(LocalStore store) async {
    if (store.getJson(storeKey) != null) return;
    await store.setJson(storeKey, FirstSteps(guided: true, startedAt: DateTime.now()).toJson());
  }

  /// Integration suites that test the whole app start as a player who is past the first steps: no
  /// first board, no hints, every tab and section open.
  static Future<void> skipFor(LocalStore store) async {
    store.tutorialSeen = true;
    await store.setJson(storeKey, const FirstSteps(firstBoard: false).toJson());
  }
}

class FirstStepsNotifier extends Notifier<FirstSteps> {
  LocalStore get _s => ref.read(localStoreProvider);

  @override
  FirstSteps build() => FirstSteps.fromJson(ref.watch(localStoreProvider).getJson(FirstSteps.storeKey));

  void _save(FirstSteps v) {
    _s.setJson(FirstSteps.storeKey, v.toJson());
    state = v;
  }

  /// Reads the record again (after `markNewPlayer` wrote it).
  void reload() => state = FirstSteps.fromJson(_s.getJson(FirstSteps.storeKey));

  /// Home is on screen: from now on every picture counts (once).
  void arrivedHome() {
    if (!state.guided || state.homeAt != null) return;
    _save(state.copyWith(homeAt: DateTime.now()));
  }

  /// "Unlock anyway" on Home: everything opens now.
  void showEverything() => _save(state.copyWith(showEverything: true, everythingAt: DateTime.now()));

  /// "Unlock anyway" on a locked tab or section: [r] opens now (no "new" dot for a tab).
  void openEarly(Reveal r) => _save(state.copyWith(early: {...state.early, r.name: DateTime.now()}, tips: {...state.tips, if (r.tab != null) 'tab:${r.name}'}));

  /// Settings > Guided start. Turning it on keeps what the player has reached open, with no
  /// "new" dots for tabs they had.
  void setGuided(bool on) {
    AppAnalytics.event('settings_changed', {'setting': 'guided_start', 'value': on});
    // Counted from the rows, not through countedSolvesProvider: that provider watches this one, and
    // reading it from here is a circular dependency (debug builds throw).
    final solved = countedFinishes(state, ref.read(progressProvider).value ?? const {}).length;
    final reached = [for (final r in Reveal.values) if (solved >= r.solves && r.tab != null) r];
    _save(state.copyWith(
      guided: on || state.guided,
      showEverything: !on,
      everythingAt: on ? null : DateTime.now(),
      clearEverythingAt: on,
      early: on ? const {} : state.early,
      tips: on ? {...state.tips, for (final r in reached) 'tab:${r.name}'} : state.tips,
    ));
  }

  void sawTip(String key) {
    if (state.tips.contains(key)) return;
    _save(state.copyWith(tips: {...state.tips, key}));
  }
}

final firstStepsProvider = NotifierProvider<FirstStepsNotifier, FirstSteps>(FirstStepsNotifier.new);

final _epoch = DateTime.fromMillisecondsSinceEpoch(0);

/// What the guided start keeps back until the player is ready for it, in the order it opens, by
/// pictures solved (owner, 2026-10-16: Library and Quick play 3, daily 5, daily gift 10, Lucky Wheel 15, Quests 20,
/// achievements 25, piggy bank 30, live events 35, Social 50). Before the Library opens, the only
/// picture to play is the one Home suggests.
enum Reveal {
  library(solves: 3, label: 'Library', tab: 1, blurb: 'Every pack to play, with free ones to start.'),
  quickPlay(solves: 3, label: 'Quick play'),
  daily(solves: 5, label: 'Daily puzzle', blurb: 'A new picture every day, with a bonus.'),
  saveProgress(solves: 5, label: 'Save your progress'),
  streak(solves: 10, label: 'Daily gift', blurb: 'A gift each day, bigger with your streak.'),
  wheel(solves: 15, label: 'Lucky Wheel', blurb: 'Spin for coins, tickets and hints.'),
  quests(solves: 20, label: 'Quests', plural: true, tab: 2, blurb: 'Daily and weekly tasks for coins and tickets.'),
  promos(solves: 20, label: 'Store offers', plural: true),
  achievements(solves: 25, label: 'Achievements', plural: true, blurb: 'Lifetime milestones, each with a reward.'),
  piggy(solves: 30, label: 'Piggy bank', blurb: 'Saves a few coins from every picture.'),
  liveEvents(solves: 35, label: 'Live events', plural: true, blurb: 'World-day packs, each open for a week.'),
  social(solves: 50, label: 'Social', tab: 3, blurb: 'A weekly league, friends and messages.');

  const Reveal({required this.solves, required this.label, this.plural = false, this.blurb = '', this.tab});

  /// Pictures solved it waits for.
  final int solves;
  final String label;
  final bool plural;

  /// What it is, in one line (the Home list of what is to come, a locked card, the locked tab's
  /// alert): one line at the default text size on a 390 pt iPhone (owner, TestFlight 2026-10-18;
  /// test/hint_lines_test.dart).
  final String blurb;

  /// Its tab in the tab bar (Library 1, Quests 2, Social 3), when it is one.
  final int? tab;

  /// Listed under "More opens as you play".
  bool get listed => blurb.isNotEmpty;

  /// Pictures still to solve, for a player who has [counted] (at least 1 while it is locked).
  int left(int counted) => solves - counted < 1 ? 1 : solves - counted;

  /// "2 more pictures", "1 more picture": the chips and alerts (owner, 2026-10-16).
  String more(int counted) => left(counted) == 1 ? '1 more picture' : '${left(counted)} more pictures';

  /// "Quests open after 19 more pictures", "Social opens after 49 more pictures": a locked tab's alert.
  String opensTitle(int counted) => '$label ${plural ? 'open' : 'opens'} after ${more(counted)}';

  /// "Opens after 24 more pictures": a locked card's title, under the section's own header
  /// (Achievements, Live events), so it stays one line.
  String opensAfter(int counted) => 'Opens after ${more(counted)}';
}

/// Pictures the player has finished (local progress, so a first solve counts at once).
final solvedCountProvider = Provider<int>((ref) {
  final rows = ref.watch(progressProvider).value ?? const <String, PuzzleProgress>{};
  return rows.values.where((p) => p.completed).length;
});

/// The finishes that count toward what opens, oldest first (owner, 2026-10-16): every picture a
/// returning account finished before onboarding here; of the pictures played after onboarding and
/// before the player first reached Home (the first board, and any played on from its finish), only
/// the first; every picture from reaching Home on. All of them for a player without the guided start.
final countedFinishesProvider = Provider<List<DateTime>>((ref) => countedFinishes(ref.watch(firstStepsProvider), ref.watch(progressProvider).value ?? const {}));

List<DateTime> countedFinishes(FirstSteps steps, Map<String, PuzzleProgress> rows) {
  final all = [for (final p in rows.values) if (p.completed) p.completedAt ?? _epoch]..sort();
  if (!steps.guided) return all;
  final start = steps.startedAt ?? _epoch, home = steps.homeAt;
  return [
    ...all.where((t) => t.isBefore(start)),
    ...all.where((t) => !t.isBefore(start) && (home == null || t.isBefore(home))).take(1),
    if (home != null) ...all.where((t) => !t.isBefore(home) && !t.isBefore(start)),
  ];
}

/// How many pictures count toward what opens ([countedFinishesProvider]).
final countedSolvesProvider = Provider<int>((ref) => ref.watch(countedFinishesProvider).length);

/// Is [r] open? Always, unless the guided start applies and the player has not reached it.
bool revealOpen(Reveal r, {required FirstSteps steps, required int solved}) => !steps.calm || steps.early.containsKey(r.name) || solved >= r.solves;

final revealsProvider = Provider<Set<Reveal>>((ref) {
  final steps = ref.watch(firstStepsProvider);
  final solved = ref.watch(countedSolvesProvider);
  final packDone = steps.calm && ref.watch(firstPackDoneProvider);
  return {for (final r in Reveal.values) if (revealOpen(r, steps: steps, solved: solved) || (r == Reveal.library && packDone)) r};
});

/// The first pack has no picture left to suggest: every one finished (owner, 2026-10-17: a player
/// who plays the whole pack with Next puzzle before ever reaching Home has 1 picture counted and
/// nothing left to play). The Library then opens by itself, so the guided start never leaves a
/// player with only Unlock anyway. Also when the pack is missing from the catalogue.
final firstPackDoneProvider = Provider<bool>((ref) {
  final puzzles = ref.watch(allPuzzlesProvider).value;
  if (puzzles == null) return false;
  final rows = ref.watch(progressProvider).value ?? const <String, PuzzleProgress>{};
  return puzzles.where((z) => z.packId == firstBoardPack).every((z) => rows[z.id]?.completed == true);
});

/// When [r] started to count for this player: quests and achievements count only pictures finished
/// after it (owner, 2026-10-16), so nothing piles up while they are locked. The start of time for a
/// player without the guided start; the far future while [r] is locked; otherwise the earliest of
/// Unlock anyway (for [r] or for everything) and the finish of the picture that opened it.
final countsFromProvider = Provider.family<DateTime, Reveal>((ref, r) {
  final steps = ref.watch(firstStepsProvider);
  if (!steps.guided) return _epoch;
  final finished = ref.watch(countedFinishesProvider);
  final from = [
    ?steps.early[r.name],
    if (steps.showEverything) steps.everythingAt ?? _epoch,
    if (finished.length >= r.solves && r.solves > 0) finished[r.solves - 1],
  ];
  if (from.isEmpty) return DateTime(9999);
  return from.reduce((a, b) => a.isBefore(b) ? a : b);
});

/// What is still to come, in the order it opens ("More opens as you play" on Home).
final upcomingRevealsProvider = Provider<List<Reveal>>((ref) {
  final open = ref.watch(revealsProvider);
  return [for (final r in Reveal.values) if (!open.contains(r) && r.listed) r];
});

/// A tab that opened by playing and has not been visited: it carries a dot until then.
final newTabsProvider = Provider<Set<int>>((ref) {
  final steps = ref.watch(firstStepsProvider);
  if (!steps.calm) return const {};
  final open = ref.watch(revealsProvider);
  return {for (final r in Reveal.values) if (r.tab != null && open.contains(r) && !steps.tips.contains('tab:${r.name}')) r.tab!};
});

/// The first board: Pink Sands Beach from the free starter pack Tropical Beaches, else the pack's
/// first picture, else today's picture; a 3x3 Cards board. Picked for being easy on nine cards:
/// of the six starter packs' pictures it is among the few whose nine cards all differ clearly in
/// colour and detail (sky, palm, sea, path), and it is calm.
const firstBoardPuzzle = 'p-83816959304c';
const firstBoardPack = 'pack-tropical-beaches';

typedef FirstBoard = ({Puzzle puzzle, String route});

final firstBoardProvider = Provider<FirstBoard?>((ref) {
  final puzzles = ref.watch(allPuzzlesProvider).value;
  if (puzzles == null) return null;
  final starter = puzzles.where((z) => z.packId == firstBoardPack).toList()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  final pick = starter.where((z) => z.id == firstBoardPuzzle).firstOrNull ?? starter.firstOrNull ?? ref.watch(dailyPuzzleProvider);
  if (pick == null) return null;
  return (puzzle: pick, route: '/game/${pick.id}/${BoardCode.toPath(firstBoardSpec.fullCode)}?first=1');
});

/// Nine cards: the smallest board of the ladder.
const firstBoardSpec = BoardSpec(GameMode.cards, 3, 3, 'Cozy');

/// Decodes the first board's picture while the welcome pages are open, so the board is dealt at
/// once (the decode is kept for the session by [puzzleImageProvider]).
final firstBoardPrefetchProvider = Provider.autoDispose<void>((ref) {
  final first = ref.watch(firstBoardProvider);
  if (first != null) ref.watch(puzzleImageProvider(first.puzzle.imageUrl));
});

/// Should the welcome pages lead into the first board? Only for a new player on this device.
bool wantsFirstBoard(Ref ref) {
  final steps = ref.read(firstStepsProvider);
  return steps.guided && steps.firstBoard && ref.read(solvedCountProvider) == 0 && (ref.read(profileProvider).value?.level ?? 1) <= 1;
}

/// The one suggestion on the guided Home: the next small thing worth doing.
@immutable
class NextStep {
  const NextStep({required this.key, required this.label, required this.title, required this.subtitle, required this.route, this.puzzle});
  final String key;

  /// The small line above the title ("Start here", "Next in Wild Nature").
  final String label;
  final String title;
  final String subtitle;
  final String route;

  /// Its picture, shown on the card.
  final Puzzle? puzzle;
}

final nextStepProvider = Provider<NextStep?>((ref) {
  final steps = ref.watch(firstStepsProvider);
  if (!steps.calm) return null;
  final solved = ref.watch(solvedCountProvider);
  final progress = ref.watch(progressProvider).value ?? const <String, PuzzleProgress>{};
  final puzzles = ref.watch(allPuzzlesProvider).value ?? const <Puzzle>[];
  if (solved == 0) {
    final first = ref.watch(firstBoardProvider);
    // A first board already started shows as Continue.
    if (first == null || progress[first.puzzle.id]?.inProgress == true) return null;
    return NextStep(key: 'first', label: 'Start here', title: 'Your first picture', subtitle: 'Nine cards and no clock. A minute or two.', route: first.route, puzzle: first.puzzle);
  }
  final pack = puzzles.where((z) => z.packId == firstBoardPack).toList()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  final packName = ref.watch(packsProvider).value?.where((p) => p.id == firstBoardPack).firstOrNull?.name ?? 'your first pack';
  final done = pack.where((z) => progress[z.id]?.completed == true).length;
  final next = pack.where((z) => progress[z.id]?.completed != true && progress[z.id]?.inProgress != true).firstOrNull;
  final features = ref.watch(openFeaturesProvider);
  final squaresUsed = (ref.watch(profileProvider).value?.solvedByMode[GameMode.squares.code] ?? 0) > 0;
  if (next != null && features.open.contains(Unlock.squares) && !squaresUsed) {
    return NextStep(key: 'squares', label: 'New for you', title: 'Try Squares', subtitle: 'The same pictures cut into even squares, for a little more reward.', route: '/play/${next.id}', puzzle: next);
  }
  if (next != null && done < 5) {
    return NextStep(key: 'pack', label: 'Next in $packName', title: next.title, subtitle: '$done of ${pack.length} done in your first pack. Free to play.', route: '/play/${next.id}', puzzle: next);
  }
  return const NextStep(key: 'library', label: 'When you are ready', title: 'Find a pack you like', subtitle: 'Free packs to start, and many more that open with coins.', route: '/library');
});
