// The Daily gift sheet (107 B, 001 B, 100 A) at phone sizes (SE and Pro Max), in both themes, at the
// default and the largest text size the app allows (1.35), in the states a player meets: day 1, mid-week,
// day 7, claimed today, and a lost streak that can be restored with today's claim, plus the later weeks
// (day 8 lists Day 8 to 14, day 15 Day 15 to 21: the streak never looks reset, owner 2026-10-18). It
// renders without a layout error, lists the whole week, marks today, and the claim stays reachable.
import 'package:carden/core/a11y.dart';
import 'package:carden/core/theme/app_theme.dart';
import 'package:carden/data/local_store.dart';
import 'package:carden/features/daily/daily_reward_sheet.dart';
import 'package:carden/models/models.dart';
import 'package:carden/state/profile.dart';
import 'package:carden/state/settings.dart';
import 'package:carden/widgets/ui.dart';
import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _patch = const {};

class _Profile extends ProfileNotifier {
  @override
  Future<Profile> build() async {
    final g = Profile.guest('local');
    return Profile.fromRow(g.id, {...g.toData(), ..._patch});
  }
}

void main() {
  final now = DateTime.now();
  String ago(int days) => now.subtract(Duration(days: days)).toUtc().toIso8601String();
  // State: profile columns, the claim button's label (null: claimed today), the tag on today's row, the
  // week's first day.
  final states = <String, (Map<String, dynamic>, String?, String, int)>{
    'new player, day 1': (const {}, 'Claim day 1 gift', 'Today', 1),
    'mid-week, day 4': ({'streak': 3, 'longestStreak': 3, 'lastDailyClaim': ago(1)}, 'Claim day 4 gift', 'Today', 1),
    'day 7': ({'streak': 6, 'longestStreak': 6, 'lastDailyClaim': ago(1)}, 'Claim day 7 gift', 'Today', 1),
    'claimed today': ({'streak': 4, 'longestStreak': 4, 'lastDailyClaim': now.toUtc().toIso8601String()}, null, 'Claimed', 1),
    'missed days, restore offered': ({'streak': 6, 'longestStreak': 6, 'lastDailyClaim': ago(3), 'tickets': 8}, 'Claim day 1 gift', 'Today', 1),
    'second week, day 8': ({'streak': 7, 'longestStreak': 7, 'lastDailyClaim': ago(1)}, 'Claim day 8 gift', 'Today', 8),
    'day 8 claimed today': ({'streak': 8, 'longestStreak': 8, 'lastDailyClaim': now.toUtc().toIso8601String()}, null, 'Claimed', 8),
    'day 14': ({'streak': 13, 'longestStreak': 13, 'lastDailyClaim': ago(1)}, 'Claim day 14 gift', 'Today', 8),
    'third week, day 15': ({'streak': 14, 'longestStreak': 14, 'lastDailyClaim': ago(1)}, 'Claim day 15 gift', 'Today', 15),
    'long streak, day 365': ({'streak': 364, 'longestStreak': 364, 'lastDailyClaim': ago(1)}, 'Claim day 365 gift', 'Today', 365),
  };
  for (final size in const [Size(375, 667), Size(440, 956)]) {
    for (final dark in [false, true]) {
      for (final scale in const [1.0, 1.35]) {
        for (final s in states.entries) {
          testWidgets('Daily gift ${size.width.toInt()}x${size.height.toInt()} ${dark ? 'dark' : 'light'} text ${scale}x: ${s.key}', (tester) async {
            final (patch, claim, tag, first) = s.value;
            _patch = patch;
            final errors = <String>{};
            final previous = FlutterError.onError;
            FlutterError.onError = (d) {
              final where = RegExp(r'lib/[a-z_/]+\.dart:\d+').firstMatch(d.toString())?.group(0) ?? '?';
              errors.add('${d.exceptionAsString().split('\n').first} @ $where');
            };
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            SharedPreferences.setMockInitialValues({});
            final store = await LocalStore.open();
            late BuildContext host;
            await tester.pumpWidget(ProviderScope(
              overrides: [
                localStoreProvider.overrideWithValue(store),
                profileProvider.overrideWith(_Profile.new),
              ],
              child: MediaQuery(
                data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
                child: MaterialApp(
                  theme: dark ? AppTheme.dark() : AppTheme.light(),
                  home: Scaffold(
                    body: Builder(builder: (context) {
                      host = context;
                      return const SizedBox.expand();
                    }),
                  ),
                ),
              ),
            ));
            await tester.pumpAndSettle();
            showAppSheet(host, builder: (_) => const DailyRewardSheet());
            await tester.pumpAndSettle();
            FlutterError.onError = previous;
            expect(errors, isEmpty);

            final sheet = find.byType(DailyRewardSheet);
            for (var day = first; day < first + 7; day++) {
              expect(find.descendant(of: sheet, matching: find.text('Day $day')), findsOneWidget, reason: 'the whole week is listed, numbered by the streak');
            }
            if (first > 1) expect(find.descendant(of: sheet, matching: find.text('Day 1')), findsNothing, reason: 'a running streak never shows Day 1 again');
            expect(find.descendant(of: sheet, matching: find.text(tag)), findsOneWidget);
            if (claim == null) {
              expect(find.descendant(of: sheet, matching: find.text('Tomorrow')), findsOneWidget);
              expect(find.descendant(of: sheet, matching: find.text('Close')), findsOneWidget);
            } else {
              // The claim may sit below the fold at the largest text size; the sheet scrolls to it (100 A).
              final button = find.descendant(of: sheet, matching: find.text(claim));
              await tester.ensureVisible(button);
              await tester.pumpAndSettle();
              expect(tester.getRect(button).bottom, lessThanOrEqualTo(size.height), reason: 'the claim can be reached');
            }
            final restore = find.descendant(of: sheet, matching: find.text('Restore'));
            expect(restore, s.key.startsWith('missed') ? findsOneWidget : findsNothing);
          });
        }
      }
    }
  }

  // Claiming plays the finished board's confetti over the sheet (owner, 2026-10-17); Reduce motion
  // keeps it still.
  for (final reduceMotion in [false, true]) {
    testWidgets('a claimed gift ${reduceMotion ? 'with Reduce motion has no' : 'gets'} confetti', (tester) async {
      tester.view.physicalSize = const Size(402, 874);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final store = await LocalStore.open();
      late BuildContext host;
      await tester.pumpWidget(ProviderScope(
        overrides: [
          localStoreProvider.overrideWithValue(store),
          profileProvider.overrideWith(_Claims.new),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => A11y(prefs: Accessibility(reduceMotion: reduceMotion), child: child!),
          home: Scaffold(body: Builder(builder: (context) {
            host = context;
            return const SizedBox.expand();
          })),
        ),
      ));
      await tester.pumpAndSettle();
      showAppSheet(host, builder: (_) => const DailyRewardSheet());
      await tester.pumpAndSettle();
      expect(find.byType(ConfettiWidget), findsNothing);
      await tester.tap(find.text('Claim day 1 gift'));
      await tester.pump();
      await tester.pump();
      expect(find.byType(ConfettiWidget), reduceMotion ? findsNothing : findsOneWidget);
      // The burst clears itself away.
      await tester.pump(const Duration(seconds: 9));
      await tester.pump();
      expect(find.byType(ConfettiWidget), findsNothing);
    });
  }
}

class _Claims extends ProfileNotifier {
  @override
  Future<Profile> build() async => Profile.guest('local');

  @override
  Future<({int coins, int tickets, int hints, int day})?> claimDaily({bool restore = false}) async => (coins: 50, tickets: 0, hints: 0, day: 0);
}
