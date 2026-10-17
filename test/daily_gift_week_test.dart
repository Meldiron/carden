// The daily gift's week is numbered by the streak (owner, 2026-10-18: on day 8 the gift showed Day 1 to 7
// again, so the streak looked reset). The second week is Day 8 to 14, the third Day 15 to 21; the gifts
// still go round in sevens, and a missed day starts again at Day 1.
import 'package:carden/models/models.dart';
import 'package:carden/state/daily_gift.dart';
import 'package:carden/state/profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  List<int> days(GiftWeek w) => [for (var i = 0; i < 7; i++) w.dayAt(i)];

  group('before today\'s claim', () {
    test('a new player starts on Day 1', () {
      final w = GiftWeek.of(streak: 0, claimedToday: false);
      expect(days(w), [1, 2, 3, 4, 5, 6, 7]);
      expect((w.today, w.todayIndex, w.claimed, w.nextIndex), (1, 0, 0, 0));
    });
    test('day 7 is the last of the first week', () {
      final w = GiftWeek.of(streak: 6, claimedToday: false);
      expect(days(w), [1, 2, 3, 4, 5, 6, 7]);
      expect((w.today, w.todayIndex, w.claimed), (7, 6, 6));
    });
    test('day 8 opens the second week as Day 8 to 14', () {
      final w = GiftWeek.of(streak: 7, claimedToday: false);
      expect(days(w), [8, 9, 10, 11, 12, 13, 14]);
      expect((w.today, w.todayIndex, w.claimed, w.nextIndex), (8, 0, 0, 0));
    });
    test('day 14 and day 15', () {
      expect(GiftWeek.of(streak: 13, claimedToday: false).today, 14);
      expect(days(GiftWeek.of(streak: 13, claimedToday: false)).first, 8);
      final w = GiftWeek.of(streak: 14, claimedToday: false);
      expect(days(w), [15, 16, 17, 18, 19, 20, 21]);
      expect(w.today, 15);
    });
  });

  group('after today\'s claim', () {
    test('day 7 claimed: the first week is full and tomorrow starts the next', () {
      final w = GiftWeek.of(streak: 7, claimedToday: true);
      expect(days(w), [1, 2, 3, 4, 5, 6, 7]);
      expect((w.today, w.claimed, w.nextIndex), (7, 7, null));
    });
    test('day 8 claimed: Day 8 ticked, Day 9 next', () {
      final w = GiftWeek.of(streak: 8, claimedToday: true);
      expect(days(w), [8, 9, 10, 11, 12, 13, 14]);
      expect((w.today, w.todayIndex, w.claimed, w.nextIndex), (8, 0, 1, 1));
    });
    test('day 14 claimed, day 15 claimed', () {
      final a = GiftWeek.of(streak: 14, claimedToday: true);
      expect((a.firstDay, a.today, a.claimed, a.nextIndex), (8, 14, 7, null));
      final b = GiftWeek.of(streak: 15, claimedToday: true);
      expect((b.firstDay, b.today, b.claimed, b.nextIndex), (15, 15, 1, 1));
    });
    test('an odd stored streak of 0 still shows the claim as Day 1', () {
      final w = GiftWeek.of(streak: 0, claimedToday: true);
      expect((w.firstDay, w.today, w.claimed), (1, 1, 1));
    });
  });

  test('the gifts go round in sevens: day 8 pays day 1\'s gift, day 14 day 7\'s', () {
    for (var day = 1; day <= 60; day++) {
      expect(GiftWeek.rewardIndex(day), (day - 1) % 7);
    }
    expect(Economy.dailyRewards[GiftWeek.rewardIndex(8)], Economy.dailyRewards[0]);
    expect(Economy.dailyRewards[GiftWeek.rewardIndex(14)], Economy.dailyRewards[6]);
    // Every row of a week pays the gift of its place in the seven, as the claim does (ProfileNotifier.claimDaily).
    for (final streak in [0, 3, 7, 13, 14, 29, 364]) {
      final w = GiftWeek.of(streak: streak, claimedToday: false);
      for (var i = 0; i < 7; i++) {
        expect(GiftWeek.rewardIndex(w.dayAt(i)), i);
      }
      expect(GiftWeek.rewardIndex(w.today), (streak + 1 - 1) % 7, reason: 'what the next claim pays');
    }
  });

  group('from a stored profile', () {
    final now = DateTime.now();
    Profile profile(int streak, DateTime? last) {
      final g = Profile.guest('local');
      return Profile.fromRow(g.id, {...g.toData(), 'streak': streak, 'longestStreak': streak, 'lastDailyClaim': last?.toUtc().toIso8601String()});
    }

    test('a streak of 7 claimed yesterday: today is Day 8', () {
      final w = GiftWeek.forProfile(profile(7, now.subtract(const Duration(days: 1))));
      expect((w.firstDay, w.today, w.claimedToday), (8, 8, false));
    });
    test('a streak of 8 claimed today: Day 8 claimed', () {
      final w = GiftWeek.forProfile(profile(8, now));
      expect((w.firstDay, w.today, w.claimedToday, w.claimed), (8, 8, true, 1));
    });
    test('a broken streak starts again at Day 1', () {
      final w = GiftWeek.forProfile(profile(20, now.subtract(const Duration(days: 3))));
      expect((w.firstDay, w.today, w.claimed), (1, 1, 0));
    });
    test('a player who never claimed starts at Day 1', () {
      final w = GiftWeek.forProfile(profile(0, null));
      expect((w.firstDay, w.today), (1, 1));
    });
  });
}
