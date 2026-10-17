import 'dart:math';

import '../models/models.dart';

/// The seven days the daily gift shows at a time (Home's streak card and the Daily gift sheet),
/// numbered by the streak itself: the first week is Day 1 to 7, the second Day 8 to 14, the third
/// Day 15 to 21, so a long streak never looks as if it started again (owner, 2026-10-18: day 8 used
/// to show the ladder from Day 1).
///
/// The gifts still go round in sevens: day 8 pays day 1's gift, day 9 day 2's, and so on
/// ([Economy.dailyRewards] by [rewardIndex]). Only the numbering follows the streak. It is worked out
/// from the stored streak, so streaks from before this count the same way.
class GiftWeek {
  const GiftWeek._({required this.firstDay, required this.todayIndex, required this.claimed, required this.claimedToday});

  /// The week around today for a player whose running streak is [streak] (0 after a missed day: the
  /// next claim is Day 1 again). While today's gift is open ([claimedToday] false) the week is the one
  /// that holds the next claim, Day `streak + 1`; once it is claimed, the one that holds today's
  /// claim, Day [streak].
  factory GiftWeek.of({required int streak, required bool claimedToday}) {
    final s = max(0, streak);
    if (claimedToday) {
      // Today's claim was day `s` (at least 1, whatever an odd stored row says).
      final day = max(1, s);
      final idx = (day - 1) % 7;
      return GiftWeek._(firstDay: day - idx, todayIndex: idx, claimed: idx + 1, claimedToday: true);
    }
    final idx = s % 7;
    return GiftWeek._(firstDay: s - idx + 1, todayIndex: idx, claimed: idx, claimedToday: false);
  }

  /// The week a player sees now: [Profile.currentStreak] (0 once a day was missed) and whether today's
  /// gift is already claimed.
  factory GiftWeek.forProfile(Profile p) => GiftWeek.of(streak: p.currentStreak, claimedToday: !p.dailyAvailable);

  /// The streak day of the week's first row: 1, 8, 15, ...
  final int firstDay;

  /// Today's row (0-6): the gift a claim pays now, or the one claimed today.
  final int todayIndex;

  /// Rows of this week already claimed, today's included once it is (0-7).
  final int claimed;

  /// Whether today's gift is claimed.
  final bool claimedToday;

  /// The streak day shown on row [i] (0-6).
  int dayAt(int i) => firstDay + i;

  /// Today's streak day: the day "Claim day N gift" pays, or the day claimed today.
  int get today => dayAt(todayIndex);

  /// The row of the next gift still to claim in this week (today's, or tomorrow's once today's is
  /// claimed), or null when tomorrow starts the next week.
  int? get nextIndex {
    final i = claimedToday ? todayIndex + 1 : todayIndex;
    return i < 7 ? i : null;
  }

  /// Which of the seven gifts ([Economy.dailyRewards]) a streak day pays: day 1, 8, 15 ... the
  /// first, day 7, 14, 21 ... the seventh.
  static int rewardIndex(int day) => (max(1, day) - 1) % 7;
}
