/// What arrived from another device, for the "Synced from another device" alert.
///
/// Built by comparing the rows this device last had with the rows the server has now, after this
/// device's own changes are accounted for, so only what happened elsewhere shows. Derived columns
/// (level mirror, public completion numbers, lifetime totals, `appliedOps`) never show.
library;

import 'dart:math';

import '../../models/models.dart';
import '../../state/rewards.dart';
import 'changes.dart';
import 'ops.dart';

class SyncNotice {
  const SyncNotice({
    this.coins = 0,
    this.tickets = 0,
    this.hints = 0,
    this.peeks = 0,
    this.magics = 0,
    this.level,
    this.solved = 0,
    this.betterStars = 0,
    this.boards = const [],
    this.packs = const [],
    this.avatars = 0,
    this.tiers = 0,
    this.quests = 0,
    this.swaps = 0,
    this.achievements = 0,
    this.dailyStreak,
    this.piggyCapacity,
    this.vipStarted = false,
    this.vipEnded = false,
    this.name,
    this.avatarChanged = false,
    this.skipped = const [],
  });

  static const empty = SyncNotice();

  /// Balance changes made elsewhere (Peeks and Magic: the boosters in stock).
  final int coins, tickets, hints, peeks, magics;

  /// The new level, when it went up.
  final int? level;

  /// Pictures solved for the first time, and pictures with more stars than before.
  final int solved, betterStars;

  /// Pictures whose board in progress came from another device.
  final List<String> boards;

  /// Pack ids unlocked elsewhere.
  final List<String> packs;
  final int avatars, tiers, quests, achievements;

  /// Quests swapped elsewhere.
  final int swaps;

  /// The streak after a daily gift claimed elsewhere.
  final int? dailyStreak;

  /// What the piggy bank holds after an upgrade bought elsewhere.
  final int? piggyCapacity;
  final bool vipStarted, vipEnded;

  /// New display name.
  final String? name;
  final bool avatarChanged;

  /// This device's actions that were dropped because another device had already done them.
  final List<SkipReason> skipped;

  bool get isEmpty =>
      coins == 0 &&
      tickets == 0 &&
      hints == 0 &&
      peeks == 0 &&
      magics == 0 &&
      level == null &&
      solved == 0 &&
      betterStars == 0 &&
      boards.isEmpty &&
      packs.isEmpty &&
      avatars == 0 &&
      tiers == 0 &&
      quests == 0 &&
      swaps == 0 &&
      achievements == 0 &&
      dailyStreak == null &&
      piggyCapacity == null &&
      !vipStarted &&
      !vipEnded &&
      name == null &&
      !avatarChanged &&
      skipped.isEmpty;

  SyncNotice operator +(SyncNotice o) => SyncNotice(
        coins: coins + o.coins,
        tickets: tickets + o.tickets,
        hints: hints + o.hints,
        peeks: peeks + o.peeks,
        magics: magics + o.magics,
        level: o.level ?? level,
        solved: solved + o.solved,
        betterStars: betterStars + o.betterStars,
        boards: dedupe([...boards, ...o.boards]),
        packs: dedupe([...packs, ...o.packs]),
        avatars: avatars + o.avatars,
        tiers: tiers + o.tiers,
        quests: quests + o.quests,
        swaps: swaps + o.swaps,
        achievements: achievements + o.achievements,
        dailyStreak: o.dailyStreak ?? dailyStreak,
        piggyCapacity: o.piggyCapacity ?? piggyCapacity,
        vipStarted: (vipStarted || o.vipStarted) && !o.vipEnded,
        vipEnded: (vipEnded || o.vipEnded) && !o.vipStarted,
        name: o.name ?? name,
        avatarChanged: avatarChanged || o.avatarChanged,
        skipped: [...skipped, ...o.skipped],
      );

  /// Differences between the profile row this device expected and the one the server has.
  factory SyncNotice.profile(Map<String, dynamic> before, Map<String, dynamic> after, {DateTime? now}) {
    List<String> added(String k) {
      final had = asStrings(before[k]).toSet();
      return dedupe([for (final v in asStrings(after[k])) if (!had.contains(v)) v]);
    }

    final l0 = LevelRewards.levelForXp(asInt(before['xp'])), l1 = LevelRewards.levelForXp(asInt(after['xp']));
    final d0 = rowDate(before['lastDailyClaim']), d1 = rowDate(after['lastDailyClaim']);
    final vip0 = _vip(before, now), vip1 = _vip(after, now);
    final name0 = (before['displayName'] ?? '').toString(), name1 = (after['displayName'] ?? '').toString();
    final piggy0 = asInt(before['piggyLevel']), piggy1 = asInt(after['piggyLevel']);
    return SyncNotice(
      coins: asInt(after['coins']) - asInt(before['coins']),
      tickets: asInt(after['tickets']) - asInt(before['tickets']),
      hints: asInt(after['hints']) - asInt(before['hints']),
      peeks: asInt(after['peeks']) - asInt(before['peeks']),
      magics: asInt(after['magics']) - asInt(before['magics']),
      level: l1 > l0 ? l1 : null,
      packs: added('unlockedPacks'),
      avatars: added('unlockedAvatars').length,
      tiers: added('unlockedTiers').length,
      quests: added('claimedGoals').where((k) => !k.endsWith(':vipbonus')).length,
      swaps: max(0, _swapCount(after['questSwaps']) - _swapCount(before['questSwaps'])),
      achievements: added('claimedAchievements').length,
      dailyStreak: d1 != null && (d0 == null || d1.isAfter(d0)) ? asInt(after['streak']) : null,
      piggyCapacity: piggy1 > piggy0 ? Profile.piggyCapacityAt(piggy1) : null,
      vipStarted: vip1 && !vip0,
      vipEnded: vip0 && !vip1,
      name: name1.isNotEmpty && name1 != name0 ? name1 : null,
      avatarChanged: after['avatar'] != null && before['avatar'] != null && after['avatar'] != before['avatar'],
    );
  }

  /// Differences between progress rows (by puzzle id) this device had and the server's.
  factory SyncNotice.progress(Map<String, Map<String, dynamic>> before, Map<String, Map<String, dynamic>> after) {
    var solved = 0, better = 0;
    final boards = <String>[];
    for (final e in after.entries) {
      final b = before[e.key] ?? const <String, dynamic>{}, a = e.value;
      final wasSolved = rowSolved(b), isSolved = rowSolved(a);
      if (isSolved && !wasSolved) {
        solved++;
      } else if (isSolved && asInt(a['stars']) > asInt(b['stars'])) {
        better++;
      }
      final layout = (a['layout'] ?? '').toString();
      if (layout.isNotEmpty && layout != (b['layout'] ?? '').toString()) boards.add(e.key);
    }
    return SyncNotice(solved: solved, betterStars: better, boards: boards);
  }

  /// Swaps made in the slots a `questSwaps` value holds (each slot lists its first quest too).
  static int _swapCount(dynamic raw) => Goals.decodeSwaps(raw).values.fold(0, (n, h) => n + h.length - 1);

  static bool _vip(Map<String, dynamic> row, DateTime? now) {
    if (row['isVip'] == true) return true;
    final until = rowDate(row['vipExpiresAt']);
    return until != null && until.isAfter(now ?? DateTime.now());
  }

  @override
  String toString() => 'SyncNotice(coins $coins, tickets $tickets, hints $hints, peeks $peeks, magics $magics, level $level, solved $solved, better $betterStars, '
      'boards $boards, packs $packs, quests $quests, achievements $achievements, daily $dailyStreak, skipped $skipped)';
}

/// Which devices changed the save between two reads of the profile row. Every profile op adds its id
/// to `appliedOps`, and an op id begins with the four characters naming its device (`SyncOp.device`;
/// each device keeps its newest ids there, `SyncController.keepOwnIds`). A server-side change (a
/// purchase added by the `api` function) leaves no id.
class SyncSource {
  const SyncSource({required this.mine, required this.elsewhere});

  factory SyncSource.of({required Iterable<String> before, required Iterable<String> after, required String device}) {
    final had = before.toSet();
    final arrived = [for (final id in after) if (!had.contains(id)) id];
    return SyncSource(mine: arrived.any((id) => id.startsWith(device)), elsewhere: arrived.any((id) => !id.startsWith(device)));
  }

  /// Ops of this device arrived.
  final bool mine;

  /// Ops of another device arrived.
  final bool elsewhere;

  /// Only this device's ops arrived: what changed is this device's own play.
  bool get thisDeviceOnly => mine && !elsewhere;
}
