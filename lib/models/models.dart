import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';

import '../core/dates.dart';
import '../core/name_filter.dart';
import '../state/rewards.dart';
import 'board_finish.dart';

export 'board_finish.dart';

int _i(dynamic v, [int d = 0]) => v is num ? v.toInt() : (v is String ? int.tryParse(v) ?? d : d);
String _s(dynamic v, [String d = '']) => v?.toString() ?? d;
bool _b(dynamic v, [bool d = false]) => v is bool ? v : d;
/// A list column without duplicates (two devices can append the same key before it is tidied).
List<String> _strings(dynamic v) => v is List ? {for (final e in v) e.toString()}.toList() : <String>[];
/// Parses a date-only value without shifting the day through time zones.
DateTime? _dateOnly(dynamic v) {
  if (v == null || v.toString().isEmpty) return null;
  final s = v.toString();
  final y = int.tryParse(s.substring(0, 4)), mo = int.tryParse(s.substring(5, 7)), da = int.tryParse(s.substring(8, 10));
  if (y == null || mo == null || da == null) return null;
  return DateTime(y, mo, da);
}

DateTime? _dt(dynamic v) => v == null || v.toString().isEmpty ? null : DateTime.tryParse(v.toString())?.toLocal();

Color colorFromHex(String? hex, [Color fallback = const Color(0xFF6C5CE7)]) {
  if (hex == null || hex.isEmpty) return fallback;
  var h = hex.replaceAll('#', '');
  if (h.length == 6) h = 'FF$h';
  final v = int.tryParse(h, radix: 16);
  return v == null ? fallback : Color(v);
}

/// Player profile – the economy lives here (coins, tickets, hints, Peeks and Magic in stock, piggy bank).
class Profile {
  Profile({
    required this.id,
    required this.userId,
    required this.displayName,
    required this.avatar,
    required this.coins,
    required this.tickets,
    required this.hints,
    required this.xp,
    required this.piggyCoins,
    this.piggyLevel = 0,
    required this.streak,
    required this.lastDailyClaim,
    required this.lastWheelSpin,
    required this.unlockedPacks,
    required this.puzzlesCompleted,
    required this.totalStars,
    this.country,
    bool isVip = false,
    this.vipExpiresAt,
    this.appleOriginalTransactionId,
    this.claimedGoals = const [],
    this.questSwaps = const {},
    this.adsToday = 0,
    this.adsDate,
    this.unlockedTiers = const [],
    this.unlockedAvatars = const [],
    this.longestStreak = 0,
    this.lastStreakRestore,
    this.peeks = 0,
    this.magics = 0,
    this.claimedAchievements = const [],
    this.inbox = const [],
    this.totalMoves = 0,
    this.totalSeconds = 0,
    this.solvedByMode = const {},
    this.questsCompleted = 0,
    this.picturesSolved = 0,
    this.picturesPerfect = 0,
    this.packsCompleted = 0,
    this.packsPerfect = 0,
    this.isTest = false,
  }) : vipFlag = isVip;

  final String id;
  final String userId;
  final String displayName;
  final String avatar;
  final int coins;
  final int tickets;
  final int hints;

  /// Peeks and Magic in stock (Lucky Wheel prizes), used before coins. Columns `peeks` and
  /// `magics` default to 0 on the server, so [toData] leaves them out.
  final int peeks;
  final int magics;
  final int xp;
  final int piggyCoins;

  /// Piggy bank upgrades bought (0-[maxPiggyLevel]): each holds [piggyStep] coins more. Column
  /// `piggyLevel` (default 0, since 2026-10-17); older builds ignore it and keep 500.
  final int piggyLevel;
  final int streak;
  final DateTime? lastDailyClaim;
  final DateTime? lastWheelSpin;
  final List<String> unlockedPacks;
  final int puzzlesCompleted;
  final int totalStars;
  final String? country;
  /// Manually set VIP flag (debug sandbox / console). Real subscriptions set
  /// [vipExpiresAt] through the server's purchase checks (docs/purchases.md).
  final bool vipFlag;
  final DateTime? vipExpiresAt;
  final String? appleOriginalTransactionId;

  /// VIP is active while the flag is set or the subscription has not expired.
  bool get isVip => vipFlag || (vipExpiresAt != null && vipExpiresAt!.isAfter(DateTime.now()));
  final List<String> claimedGoals;

  /// Quests swapped this day or week, by slot: the quests each slot has had, the one first dealt
  /// first (`QuestSwap`, column `questSwaps`, a JSON text since 2026-10-17; older builds ignore it).
  final Map<String, List<String>> questSwaps;
  final int adsToday;
  final DateTime? adsDate;
  /// Board tiers bought early, as `<mode>:<index>` (e.g. `cards:4`).
  final List<String> unlockedTiers;
  /// Avatar keys bought or earned (the four starter avatars are always free).
  final List<String> unlockedAvatars;
  final int longestStreak;
  final DateTime? lastStreakRestore;
  /// Achievement step keys whose reward was claimed, e.g. `solver:2`.
  final List<String> claimedAchievements;

  /// Inbox state, one entry per message and state: `seen:<id>`, `claimed:<id>`, `deleted:<id>`
  /// (the messages themselves are read-only rows of the `messages` table; lib/state/inbox.dart).
  final List<String> inbox;

  /// Public aggregates bumped on every solve so other players can see them
  /// (progress rows are owner-only): moves and seconds spent on boards that
  /// were finished, and finished boards per mode code (replays included).
  final int totalMoves;
  final int totalSeconds;
  final Map<String, int> solvedByMode;

  /// Quests claimed over the player's lifetime (daily and weekly, VIP ones included).
  final int questsCompleted;

  /// Public completion numbers for "Total Completion" on other players' profiles (progress rows
  /// are owner-only). Kept in step with the player's own progress and the catalogue by the app
  /// (see `CompletionTotals`): catalogue pictures solved and solved with three stars, packs with
  /// every picture solved and with three stars on every picture. My Puzzles photos never count.
  final int picturesSolved;
  final int picturesPerfect;
  final int packsCompleted;
  final int packsPerfect;

  /// A guest played by a QA run (`--dart-define=CJW_QA=true`): left out of the league and its
  /// counts, and deleted by `tools/dev/purge_test_players.py`.
  final bool isTest;

  /// Derived from [xp] with [LevelRewards.levelForXp]; the stored `level`
  /// column is only a mirror for queries and older clients.
  int get level => LevelRewards.levelForXp(xp);

  /// The piggy bank holds [basePiggyCapacity] coins, and [piggyStep] more for each upgrade, up to
  /// [maxPiggyLevel] upgrades: 500, 600, ... 1,000 (owner, 2026-10-17).
  static const basePiggyCapacity = 500;
  static const piggyStep = 100;
  static const maxPiggyLevel = 5;
  static int piggyCapacityAt(int level) => basePiggyCapacity + piggyStep * level.clamp(0, maxPiggyLevel);

  /// What this player's piggy bank holds.
  int get piggyCapacity => piggyCapacityAt(piggyLevel);

  static const adsPerDay = 3;

  /// Rewarded videos still available today.
  int get adsLeftToday {
    final now = DateTime.now();
    final sameDay = adsDate != null && adsDate!.year == now.year && adsDate!.month == now.month && adsDate!.day == now.day;
    return (adsPerDay - (sameDay ? adsToday : 0)).clamp(0, adsPerDay);
  }

  factory Profile.fromRow(String id, Map<String, dynamic> d) => Profile(
        id: id,
        userId: _s(d['userId']),
        // Names are filtered where they show (guideline 1.2), so names set before the filter are too.
        displayName: NameFilter.shown(_s(d['displayName'], 'Player')),
        avatar: _s(d['avatar'], 'fox'),
        coins: _i(d['coins']),
        tickets: _i(d['tickets']),
        hints: _i(d['hints']),
        xp: _i(d['xp']),
        piggyCoins: _i(d['piggyCoins']),
        piggyLevel: _i(d['piggyLevel']).clamp(0, maxPiggyLevel),
        streak: _i(d['streak']),
        lastDailyClaim: _dt(d['lastDailyClaim']),
        lastWheelSpin: _dt(d['lastWheelSpin']),
        unlockedPacks: _strings(d['unlockedPacks']),
        puzzlesCompleted: _i(d['puzzlesCompleted']),
        totalStars: _i(d['totalStars']),
        country: d['country']?.toString(),
        isVip: _b(d['isVip']),
        vipExpiresAt: _dt(d['vipExpiresAt']),
        appleOriginalTransactionId: d['appleOriginalTransactionId']?.toString(),
        claimedGoals: _strings(d['claimedGoals']),
        questSwaps: Goals.decodeSwaps(d['questSwaps']),
        adsToday: _i(d['adsToday']),
        adsDate: _dt(d['adsDate']),
        unlockedTiers: _strings(d['unlockedTiers']),
        unlockedAvatars: _strings(d['unlockedAvatars']),
        longestStreak: _i(d['longestStreak']),
        peeks: _i(d['peeks']),
        magics: _i(d['magics']),
        lastStreakRestore: _dt(d['lastStreakRestore']),
        claimedAchievements: _strings(d['claimedAchievements']),
        inbox: _strings(d['inbox']),
        totalMoves: _i(d['totalMoves']),
        totalSeconds: _i(d['totalSeconds']),
        solvedByMode: _modeCounts(d['solvedByMode']),
        questsCompleted: _i(d['questsCompleted']),
        picturesSolved: _i(d['picturesSolved']),
        picturesPerfect: _i(d['picturesPerfect']),
        packsCompleted: _i(d['packsCompleted']),
        packsPerfect: _i(d['packsPerfect']),
        isTest: _b(d['isTest']),
      );

  /// `{"cards":3,"hexagons":1}` stored as a short JSON string.
  static Map<String, int> _modeCounts(dynamic raw) {
    if (raw is Map) return {for (final e in raw.entries) e.key.toString(): _i(e.value)};
    final s = raw?.toString();
    if (s == null || s.isEmpty) return const {};
    try {
      final decoded = jsonDecode(s);
      if (decoded is Map) return {for (final e in decoded.entries) e.key.toString(): _i(e.value)};
    } catch (_) {}
    return const {};
  }

  factory Profile.guest(String userId) => Profile(
        id: userId,
        userId: userId,
        displayName: 'Player',
        avatar: 'fox',
        coins: 500,
        tickets: 3,
        hints: 3,
        xp: 0,
        piggyCoins: 0,
        streak: 0,
        lastDailyClaim: null,
        lastWheelSpin: null,
        unlockedPacks: const [],
        puzzlesCompleted: 0,
        totalStars: 0,
      );

  Map<String, dynamic> toData() => {
        'userId': userId,
        'displayName': displayName,
        'avatar': avatar,
        'coins': coins,
        'tickets': tickets,
        'hints': hints,
        'xp': xp,
        'level': level,
        'piggyCoins': piggyCoins,
        'piggyLevel': piggyLevel,
        'streak': streak,
        'lastDailyClaim': lastDailyClaim?.toUtc().toIso8601String(),
        'lastWheelSpin': lastWheelSpin?.toUtc().toIso8601String(),
        'unlockedPacks': unlockedPacks,
        'puzzlesCompleted': puzzlesCompleted,
        'totalStars': totalStars,
        'country': country,
        'isVip': vipFlag,
        'vipExpiresAt': vipExpiresAt?.toUtc().toIso8601String(),
        'appleOriginalTransactionId': appleOriginalTransactionId,
        'claimedGoals': claimedGoals,
        'questSwaps': questSwaps.isEmpty ? null : jsonEncode(questSwaps),
        'adsToday': adsToday,
        'adsDate': adsDate?.toUtc().toIso8601String(),
        'unlockedTiers': unlockedTiers,
        'unlockedAvatars': unlockedAvatars,
        'longestStreak': longestStreak,
        'lastStreakRestore': lastStreakRestore?.toUtc().toIso8601String(),
        'claimedAchievements': claimedAchievements,
        'inbox': inbox,
        'totalMoves': totalMoves,
        'totalSeconds': totalSeconds,
        'solvedByMode': solvedByMode.isEmpty ? null : jsonEncode(solvedByMode),
        'questsCompleted': questsCompleted,
        'picturesSolved': picturesSolved,
        'picturesPerfect': picturesPerfect,
        'packsCompleted': packsCompleted,
        'packsPerfect': packsPerfect,
        'isTest': isTest,
      };

  Profile copyWith({
    List<String>? inbox,
    String? displayName,
    String? avatar,
    int? coins,
    int? tickets,
    int? hints,
    int? peeks,
    int? magics,
    int? xp,
    int? piggyCoins,
    int? streak,
    DateTime? lastDailyClaim,
    DateTime? lastWheelSpin,
    List<String>? unlockedPacks,
    int? puzzlesCompleted,
    int? totalStars,
    String? id,
    String? userId,
    bool? isTest,
  }) =>
      Profile(
        id: id ?? this.id,
        userId: userId ?? this.userId,
        displayName: displayName ?? this.displayName,
        avatar: avatar ?? this.avatar,
        coins: coins ?? this.coins,
        tickets: tickets ?? this.tickets,
        hints: hints ?? this.hints,
        xp: xp ?? this.xp,
        piggyCoins: piggyCoins ?? this.piggyCoins,
        piggyLevel: piggyLevel,
        streak: streak ?? this.streak,
        lastDailyClaim: lastDailyClaim ?? this.lastDailyClaim,
        lastWheelSpin: lastWheelSpin ?? this.lastWheelSpin,
        unlockedPacks: unlockedPacks ?? this.unlockedPacks,
        puzzlesCompleted: puzzlesCompleted ?? this.puzzlesCompleted,
        totalStars: totalStars ?? this.totalStars,
        country: country,
        isVip: vipFlag,
        vipExpiresAt: vipExpiresAt,
        appleOriginalTransactionId: appleOriginalTransactionId,
        claimedGoals: claimedGoals,
        questSwaps: questSwaps,
        adsToday: adsToday,
        adsDate: adsDate,
        unlockedTiers: unlockedTiers,
        unlockedAvatars: unlockedAvatars,
        longestStreak: longestStreak,
        peeks: peeks ?? this.peeks,
        magics: magics ?? this.magics,
        lastStreakRestore: lastStreakRestore,
        claimedAchievements: claimedAchievements,
        inbox: inbox ?? this.inbox,
        totalMoves: totalMoves,
        totalSeconds: totalSeconds,
        solvedByMode: solvedByMode,
        questsCompleted: questsCompleted,
        picturesSolved: picturesSolved,
        picturesPerfect: picturesPerfect,
        packsCompleted: packsCompleted,
        packsPerfect: packsPerfect,
        isTest: isTest ?? this.isTest,
      );

  /// XP needed to go from [level] to the next one; grows gently.
  static int xpForLevel(int level) => 100 + (level - 1) * 60;
  int get xpIntoLevel => LevelRewards.xpIntoLevel(xp);
  double get levelProgress => xpIntoLevel / xpForLevel(level);

  bool get dailyAvailable {
    final last = lastDailyClaim;
    if (last == null) return true;
    final now = DateTime.now();
    return !(last.year == now.year && last.month == now.month && last.day == now.day);
  }

  /// Calendar days since the last daily gift (0 today, 1 yesterday), or null before the first one.
  int? get daysSinceDailyClaim {
    final last = lastDailyClaim;
    if (last == null) return null;
    final now = DateTime.now();
    return DateTime.utc(now.year, now.month, now.day).difference(DateTime.utc(last.year, last.month, last.day)).inDays;
  }

  /// The streak still counts: a gift was claimed today or yesterday. After a missed day the
  /// stored [streak] is the one that was lost, and the next claim starts again at day 1.
  bool get streakAlive => (daysSinceDailyClaim ?? 2) <= 1;

  /// The streak to show: 0 once a day was missed.
  int get currentStreak => streakAlive ? streak : 0;

  /// The day (0-6) of the 7-day round whose gift comes next: today's while [dailyAvailable],
  /// otherwise tomorrow's. It is what the next claim pays.
  int get nextGiftDay => currentStreak % 7;

  /// Gifts of the current 7-day round already claimed (0-7).
  int get giftsClaimedThisRound => dailyAvailable ? currentStreak % 7 : (currentStreak - 1) % 7 + 1;

  bool get wheelAvailable {
    final last = lastWheelSpin;
    if (last == null) return true;
    final now = DateTime.now();
    return !(last.year == now.year && last.month == now.month && last.day == now.day);
  }

  bool get piggyFull => piggyCoins >= piggyCapacity;
}

class Pack {
  Pack({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.coverUrl,
    required this.priceCoins,
    required this.priceTickets,
    required this.isFree,
    required this.isPremium,
    required this.isSeasonal,
    required this.eventId,
    required this.sortOrder,
    required this.imageCount,
    required this.accent,
    required this.emoji,
    this.startAt,
    this.endAt,
    this.blurhash,
    this.updatedAt,
    this.createdAt,
    this.hidden = false,
  });

  /// A hidden pack (`packs.hidden`) is opened with a pack code: the app shows it only to players
  /// who have it in their unlocked packs (see [visibleTo]). Hidden pack rows also carry a start
  /// date far in the future, so app versions from before hidden packs treat them as unreleased and
  /// never list them; this version ignores the dates of a hidden pack.
  final bool hidden;

  /// BlurHash of the cover, shown while the image loads.
  final String? blurhash;

  /// The row's `$updatedAt` (server time). The content tool updates the pack row whenever it adds,
  /// removes or replaces the pack's puzzles, so a change here means its puzzles changed too.
  final String? updatedAt;

  /// When the row was created (`$createdAt`), for the Library's New badge.
  final DateTime? createdAt;

  /// The launch catalogue was built from 2026-10-11 to 2026-10-13 (its last pack is from 14:45 UTC
  /// on the 13th); packs created before this are never New, or the whole Library would be New in
  /// the first week.
  static final newBaseline = DateTime.utc(2026, 10, 13, 18);

  /// How long a pack counts as New after it was added.
  static const newFor = Duration(days: 7);

  /// A library pack (not a daily month or an event pack) added in the last [newFor].
  bool isNewAt(DateTime now) {
    final at = createdAt;
    if (at == null || isDaily || hasWindow || at.isBefore(newBaseline)) return false;
    return now.difference(at) < newFor;
  }

  bool get isNew => isNewAt(DateTime.now());

  final String id;
  final String name;
  final String category;
  final String description;
  final String coverUrl;
  final int priceCoins;
  final int priceTickets;
  final bool isFree;
  final bool isPremium;
  final bool isSeasonal;
  final String? eventId;
  final int sortOrder;
  final int imageCount;
  final Color accent;
  final String emoji;

  bool get isDaily => category == 'Daily';

  /// Event packs carry a window; outside of it they cannot be played.
  final DateTime? startAt;
  final DateTime? endAt;
  bool get hasWindow => startAt != null || endAt != null;
  bool get isLive {
    final now = DateTime.now();
    if (startAt != null && now.isBefore(startAt!)) return false;
    if (endAt != null && now.isAfter(endAt!)) return false;
    return true;
  }

  bool get isUpcoming => startAt != null && DateTime.now().isBefore(startAt!);
  bool get isExpired => endAt != null && DateTime.now().isAfter(endAt!);

  /// How long before it opens an event (and its pack) shows up as "coming soon".
  static const soonWindow = Duration(days: 3);

  /// First day of a daily pack's month (local time), from its id `daily-YYYY-MM`.
  DateTime? get dailyMonth {
    if (!isDaily) return null;
    final m = RegExp(r'daily-(\d{4})-(\d{2})').firstMatch(id);
    if (m == null) return null;
    return DateTime(int.parse(m.group(1)!), int.parse(m.group(2)!));
  }

  /// Daily packs are identified by id `daily-YYYY-MM`; the current month is free.
  bool get isCurrentMonth {
    final month = dailyMonth;
    if (month == null) return false;
    final now = DateTime.now();
    return month.year == now.year && month.month == now.month;
  }

  /// Whether the app shows this pack at all at [now]. The catalogue holds daily months and event
  /// packs well ahead of time: a daily month appears on its first day, an event pack
  /// [soonWindow] before it opens. Ended event packs stay (players keep their progress).
  bool isReleasedAt(DateTime now) {
    final month = dailyMonth;
    if (month != null) return !now.isBefore(month);
    final start = startAt;
    if (start != null && now.isBefore(start)) return start.difference(now) <= soonWindow;
    return true;
  }

  bool get isReleased => isReleasedAt(DateTime.now());

  /// Whether a player who owns the packs in [owned] sees this pack at [now]: released, and not
  /// hidden unless a pack code put it in [owned].
  bool visibleTo(Set<String> owned, DateTime now) => hidden ? owned.contains(id) : isReleasedAt(now);

  static const _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

  /// Names that say nothing on their own. A daily month stored under one of them (24 months of 2023
  /// and 2024 were called "Daily" until 2026-10-18) shows its month instead.
  static const _bareNames = {'', 'daily', 'dailies', 'daily pack', 'daily puzzle', 'daily puzzles', 'daily picture', 'daily pictures', 'month', 'pack', 'untitled'};

  /// The name the app shows for a pack row: the stored [name], except that a daily month (category
  /// Daily, id `daily-YYYY-MM`) whose name is empty or a bare generic word shows "Month Year"
  /// ("October 2024"), as the content tool names them. Library, pack page, Home and the completion
  /// overlay all read [Pack.name], so they all show it.
  static String nameFor(String id, String category, String name) {
    if (category != 'Daily' || !_bareNames.contains(name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' '))) return name;
    final m = RegExp(r'^daily-(\d{4})-(\d{2})$').firstMatch(id);
    final month = m == null ? 0 : int.parse(m.group(2)!);
    if (month < 1 || month > 12) return name;
    return '${_months[month - 1]} ${m!.group(1)}';
  }

  factory Pack.fromRow(String id, Map<String, dynamic> d) => Pack(
        id: id,
        name: nameFor(id, _s(d['category'], 'general'), _s(d['name'])),
        category: _s(d['category'], 'general'),
        description: _s(d['description']),
        coverUrl: _s(d['coverUrl']),
        priceCoins: _i(d['priceCoins']),
        priceTickets: _i(d['priceTickets']),
        isFree: _b(d['isFree']),
        isPremium: _b(d['isPremium']),
        isSeasonal: _b(d['isSeasonal']),
        eventId: d['eventId']?.toString(),
        sortOrder: _i(d['sortOrder']),
        imageCount: _i(d['imageCount']),
        accent: colorFromHex(d['accent']?.toString()),
        emoji: _s(d['emoji'], ''),
        startAt: _b(d['hidden']) ? null : _dt(d['startAt']),
        endAt: _b(d['hidden']) ? null : _dt(d['endAt']),
        blurhash: d['blurhash']?.toString(),
        updatedAt: d[r'$updatedAt']?.toString(),
        createdAt: _dt(d[r'$createdAt']),
        hidden: _b(d['hidden']),
      );
}

class Puzzle {
  Puzzle({
    required this.id,
    required this.packId,
    required this.title,
    required this.imageUrl,
    required this.thumbUrl,
    required this.author,
    required this.source,
    required this.sortOrder,
    required this.accent,
    this.date,
    this.blurhash,
  });
  /// BlurHash of the picture, shown while the image loads.
  final String? blurhash;

  final String id;
  final String packId;
  final String title;
  final String imageUrl;
  final String thumbUrl;
  final String author;
  final String source;
  final int sortOrder;
  final Color accent;
  final DateTime? date;

  /// Daily puzzles unlock on their day (local time).
  bool get isLockedByDate {
    final d = date;
    if (d == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return DateTime(d.year, d.month, d.day).isAfter(today);
  }

  bool get isToday {
    final d = date;
    if (d == null) return false;
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  factory Puzzle.fromRow(String id, Map<String, dynamic> d) => Puzzle(
        id: id,
        packId: _s(d['packId']),
        title: _s(d['title'], 'Untitled'),
        imageUrl: _s(d['imageUrl']),
        thumbUrl: _s(d['thumbUrl']).isEmpty ? _s(d['imageUrl']) : _s(d['thumbUrl']),
        author: _s(d['author']),
        source: _s(d['source']),
        sortOrder: _i(d['sortOrder']),
        accent: colorFromHex(d['accent']?.toString()),
        date: _dateOnly(d['date']),
        blurhash: d['blurhash']?.toString(),
      );

  /// Builds a puzzle from a user upload stored in Appwrite Storage.
  factory Puzzle.custom({required String id, required String title, required String imageUrl}) => Puzzle(
        id: id,
        packId: 'my-puzzles',
        title: title,
        imageUrl: imageUrl,
        thumbUrl: imageUrl,
        author: 'You',
        source: 'My photos',
        sortOrder: 0,
        accent: const Color(0xFF6C5CE7),
      );
}

class PuzzleProgress {
  PuzzleProgress({
    required this.id,
    required this.userId,
    required this.puzzleId,
    required this.gridSize,
    required this.layout,
    required this.moves,
    required this.elapsedSeconds,
    required this.hintsUsed,
    required this.completed,
    required this.stars,
    required this.bestMoves,
    required this.bestSeconds,
    required this.completedAt,
    this.mode = 'cards',
    this.totalMoves = 0,
    this.totalSeconds = 0,
    this.totalHints = 0,
    this.session = '',
    this.painting = false,
    this.par = 0,
    this.peeked = false,
    this.bestLock = 0,
    this.finishLog = '',
  });

  final String id;
  final String userId;
  final String puzzleId;
  final int gridSize;
  /// Game mode code (`cards`, `squares`, `triangles`, `hexagons`).
  final String mode;
  final List<int>? layout;
  final int moves;
  final int elapsedSeconds;
  final int hintsUsed;
  final bool completed;
  final int stars;
  final int? bestMoves;
  final int? bestSeconds;
  final DateTime? completedAt;
  /// Lifetime totals across every session on this picture (replays included).
  /// Older rows have none of these; they fall back to the last session's numbers.
  final int totalMoves;
  final int totalSeconds;
  final int totalHints;

  /// The play-through the saved board belongs to (empty on rows from older versions and after a
  /// discard). Lifetime totals replace a session's earlier numbers and add up across sessions.
  final String session;

  /// Painting: the board in progress (or the last one finished) shows cards in black and white
  /// until they lock, and pays `Economy.paintingMultiplier` more. Rows from older versions: off.
  final bool painting;

  /// Par of the play-through on the row (the board in progress, or the last one finished):
  /// fewest moves its shuffle needed. 0 on rows from older versions (unknown).
  final int par;

  /// Peek was used in that play-through.
  final bool peeked;

  /// Most cards one move locked in that play-through (moves by Magic do not count).
  final int bestLock;

  /// The `finishes` column as stored: the picture's recent finished boards with their own values
  /// ([BoardFinish]). Empty on rows from older versions.
  final String finishLog;

  /// The picture's finished boards, oldest first, each with the mode, size, Painting, moves, time,
  /// Peek, longest lock and stars it was finished with. The quests read these, never the board
  /// fields above, which a replay in progress overwrites with its own board.
  late final List<BoardFinish> finishes = BoardFinish.ofRow(toData());

  factory PuzzleProgress.fromRow(String id, Map<String, dynamic> d) {
    List<int>? layout;
    final raw = d['layout']?.toString();
    if (raw != null && raw.isNotEmpty) {
      layout = raw.split(',').map((e) => int.tryParse(e.trim()) ?? 0).toList();
    }
    return PuzzleProgress(
      id: id,
      userId: _s(d['userId']),
      puzzleId: _s(d['puzzleId']),
      gridSize: _i(d['gridSize'], 4),
      layout: layout,
      moves: _i(d['moves']),
      elapsedSeconds: _i(d['elapsedSeconds']),
      hintsUsed: _i(d['hintsUsed']),
      // Solved stays solved: older versions wrote `completed: false` while a solved picture was
      // replayed, and only a finish ever sets the finish time.
      completed: _b(d['completed']) || _dt(d['completedAt']) != null,
      stars: _i(d['stars']),
      bestMoves: d['bestMoves'] == null ? null : _i(d['bestMoves']),
      bestSeconds: d['bestSeconds'] == null ? null : _i(d['bestSeconds']),
      completedAt: _dt(d['completedAt']),
      mode: _s(d['mode'], 'cards'),
      totalMoves: max(_i(d['totalMoves']), _i(d['moves'])),
      totalSeconds: max(_i(d['totalSeconds']), _i(d['elapsedSeconds'])),
      totalHints: max(_i(d['totalHints']), _i(d['hintsUsed'])),
      session: _s(d['session']),
      painting: _b(d['painting']),
      par: _i(d['par']),
      peeked: _b(d['peeked']),
      bestLock: _i(d['bestLock']),
      finishLog: _s(d['finishes']),
    );
  }

  /// Row data for caching and upserts (same keys as the Appwrite table).
  Map<String, dynamic> toData() => {
        'userId': userId,
        'puzzleId': puzzleId,
        'gridSize': gridSize,
        'layout': layout?.join(','),
        'moves': moves,
        'elapsedSeconds': elapsedSeconds,
        'hintsUsed': hintsUsed,
        'completed': completed,
        'stars': stars,
        'bestMoves': bestMoves,
        'bestSeconds': bestSeconds,
        'completedAt': completedAt?.toUtc().toIso8601String(),
        'mode': mode,
        'totalMoves': totalMoves,
        'totalSeconds': totalSeconds,
        'totalHints': totalHints,
        'session': session,
        'painting': painting,
        'par': par,
        'peeked': peeked,
        'bestLock': bestLock,
        if (finishLog.isNotEmpty) 'finishes': finishLog,
      };

  /// A board is saved (a first play or a replay of a solved picture).
  bool get inProgress => layout != null && layout!.isNotEmpty;
}

enum EventType { seasonal, social, weekly, daily }

class GameEvent {
  GameEvent({
    required this.id,
    required this.name,
    required this.description,
    required this.type,
    required this.startAt,
    required this.endAt,
    required this.goal,
    required this.rewardCoins,
    required this.rewardTickets,
    required this.coverUrl,
    required this.packId,
    required this.accent,
    required this.emoji,
  });

  final String id;
  final String name;
  final String description;
  final EventType type;
  final DateTime? startAt;
  final DateTime? endAt;
  final int goal;
  final int rewardCoins;
  final int rewardTickets;
  final String coverUrl;
  final String? packId;
  final Color accent;
  final String emoji;

  factory GameEvent.fromRow(String id, Map<String, dynamic> d) => GameEvent(
        id: id,
        name: _s(d['name']),
        description: _s(d['description']),
        type: EventType.values.firstWhere((e) => e.name == d['type'], orElse: () => EventType.seasonal),
        startAt: _dt(d['startAt']),
        endAt: _dt(d['endAt']),
        goal: _i(d['goal'], 10),
        rewardCoins: _i(d['rewardCoins']),
        rewardTickets: _i(d['rewardTickets']),
        coverUrl: _s(d['coverUrl']),
        packId: d['packId']?.toString(),
        accent: colorFromHex(d['accent']?.toString(), const Color(0xFFFF6B6B)),
        emoji: _s(d['emoji'], ''),
      );

  bool get isActive {
    final now = DateTime.now();
    if (startAt != null && now.isBefore(startAt!)) return false;
    if (endAt != null && now.isAfter(endAt!)) return false;
    return true;
  }

  Duration get timeLeft => endAt == null ? Duration.zero : endAt!.difference(DateTime.now());
  Duration get startsIn => startAt == null ? Duration.zero : startAt!.difference(DateTime.now());

  /// Shown in the events list up to [Pack.soonWindow] before it opens.
  bool get isUpcoming => startAt != null && DateTime.now().isBefore(startAt!) && startsIn <= Pack.soonWindow;
  bool get isOver => endAt != null && DateTime.now().isAfter(endAt!);
}

class EventProgress {
  EventProgress({required this.id, required this.eventId, required this.progress, required this.claimed});
  final String id;
  final String eventId;
  final int progress;
  final bool claimed;
  factory EventProgress.fromRow(String id, Map<String, dynamic> d) => EventProgress(
        id: id,
        eventId: _s(d['eventId']),
        progress: _i(d['progress']),
        claimed: _b(d['claimed']),
      );
}

class Friend {
  Friend({required this.id, required this.friendId, required this.name, required this.avatar});
  final String id;
  final String friendId;
  final String name;
  final String avatar;
  factory Friend.fromRow(String id, Map<String, dynamic> d) => Friend(
        id: id,
        friendId: _s(d['friendId']),
        name: NameFilter.shown(_s(d['friendName'], 'Friend')),
        avatar: _s(d['friendAvatar'], 'fox'),
      );
}

/// A player the signed-in player blocked (table `blocks`), with the name and avatar they had then.
class BlockedPlayer {
  BlockedPlayer({required this.id, required this.playerId, required this.name, required this.avatar});
  final String id;
  final String playerId;
  final String name;
  final String avatar;
  factory BlockedPlayer.fromRow(String id, Map<String, dynamic> d) => BlockedPlayer(
        id: id,
        playerId: _s(d['blockedId']),
        name: NameFilter.shown(_s(d['blockedName'], 'Player')),
        avatar: _s(d['blockedAvatar'], 'fox'),
      );
}

/// Why a player is reported (column `reports.reason`, free text on the server so a new reason never
/// breaks an older build).
enum ReportReason {
  name('name', 'Offensive name'),
  cheating('cheating', 'Cheating or unfair play'),
  other('other', 'Something else');

  const ReportReason(this.code, this.label);
  final String code;
  final String label;
}

class MyPuzzle {
  MyPuzzle({required this.id, required this.fileId, required this.title});
  final String id;
  final String fileId;
  final String title;
  factory MyPuzzle.fromRow(String id, Map<String, dynamic> d) =>
      MyPuzzle(id: id, fileId: _s(d['fileId']), title: myPhotoTitle(_s(d['title'], 'My photo')));
}

/// Title of a new My Puzzles photo: "Photo, 12 Oct" (the short date of lib/core/dates.dart).
String newMyPhotoTitle(DateTime at) => 'Photo, ${formatDate(at, year: false, short: true)}';

/// Older uploads were titled "My photo 12/10" (day/month, read as a date only by half the world):
/// shown as "Photo, 12 Oct". Any other title is the player's own and stays.
String myPhotoTitle(String stored) {
  final m = RegExp(r'^My photo (\d{1,2})/(\d{1,2})$').firstMatch(stored.trim());
  if (m == null) return stored;
  final day = int.parse(m.group(1)!), month = int.parse(m.group(2)!);
  if (day < 1 || day > 31 || month < 1 || month > 12) return stored;
  return 'Photo, ${formatDate(DateTime(2000, month, day), year: false, short: true)}';
}
