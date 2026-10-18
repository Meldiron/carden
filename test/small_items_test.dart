// Unit and widget tests for the small items of 2026-10-14: picture search, the New badge and
// filter, Lucky Wheel odds, the reminder offer, tomorrow's preview and the build version.
import 'package:carden/core/theme/app_theme.dart';
import 'package:carden/data/local_store.dart';
import 'package:carden/features/daily/wheel_screen.dart';
import 'package:carden/features/gallery/library_screen.dart';
import 'package:carden/features/gallery/pack_progress.dart';
import 'package:carden/features/home/new_picture_in.dart';
import 'package:carden/features/profile/settings_screen.dart';
import 'package:carden/models/models.dart';
import 'package:carden/state/catalog_sync.dart';
import 'package:carden/state/profile.dart';
import 'package:carden/widgets/icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'catalog_sync_test.dart' show FakeCatalog;

final _now = DateTime(2026, 10, 20, 15);

Pack _pack(String id, {String category = 'Nature', String name = '', DateTime? created, DateTime? startAt}) => Pack.fromRow(id, {
      'name': name.isEmpty ? id : name,
      'category': category,
      if (created != null) r'$createdAt': created.toUtc().toIso8601String(),
      if (startAt != null) 'startAt': startAt.toUtc().toIso8601String(),
    });

Puzzle _pic(String id, String packId, String title, {int order = 0, String? date}) =>
    Puzzle.fromRow(id, {'packId': packId, 'title': title, 'sortOrder': order, 'date': ?date});

void main() {
  group('New packs', () {
    test('a library pack is New for seven days after it was added', () {
      final p = _pack('giant', created: DateTime(2026, 10, 14, 9));
      expect(p.isNewAt(DateTime(2026, 10, 14, 10)), isTrue);
      expect(p.isNewAt(DateTime(2026, 10, 21, 8)), isTrue);
      expect(p.isNewAt(DateTime(2026, 10, 21, 10)), isFalse);
    });

    test('the launch catalogue, daily months, event packs and rows without a date are never New', () {
      expect(_pack('launch', created: DateTime.utc(2026, 10, 13, 14, 45)).isNewAt(DateTime(2026, 10, 14, 9)), isFalse);
      expect(_pack('tonight', created: DateTime.utc(2026, 10, 13, 22, 30)).isNewAt(DateTime(2026, 10, 14, 9)), isTrue);
      expect(_pack('daily-2026-11', category: 'Daily', created: DateTime(2026, 10, 15)).isNewAt(DateTime(2026, 10, 16)), isFalse);
      expect(_pack('evpack-x', category: 'Event', created: DateTime(2026, 10, 15), startAt: DateTime(2026, 10, 15)).isNewAt(DateTime(2026, 10, 16)), isFalse);
      expect(_pack('old').isNewAt(DateTime(2026, 10, 16)), isFalse);
    });

    test('the New chip shows only while a pack is new, and filters to new library packs', () {
      final fresh = _pack('giant', created: DateTime(2026, 10, 18));
      final old = _pack('old', created: DateTime(2026, 10, 12));
      expect(libraryChips([fresh, old], showUnlocked: true, now: _now), contains(LibraryFilter.fresh));
      expect(libraryChips([old], showUnlocked: true, now: _now), isNot(contains(LibraryFilter.fresh)));
      final shown = libraryPacks([fresh, old], filter: LibraryFilter.fresh, progress: const <String, PackProgress>{}, isUnlocked: (_) => true, now: _now);
      expect(shown.map((p) => p.id), ['giant']);
    });

    test('pack rows keep \$createdAt through the catalogue sync, other tables drop it', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await LocalStore.open();
      final server = FakeCatalog();
      server.put('packs', 'giant', {'name': 'Giant', r'$createdAt': '2026-10-14T08:00:00.000+00:00'});
      server.put('puzzles', 'z1', {'packId': 'giant', 'title': 'A', r'$createdAt': '2026-10-14T08:00:00.000+00:00'});
      final tables = await CatalogSync(store, server, clock: () => DateTime.utc(2026, 10, 14, 12)).sync();
      expect(tables['packs']!.single[r'$createdAt'], '2026-10-14T08:00:00.000+00:00');
      expect(tables['puzzles']!.single.containsKey(r'$createdAt'), isFalse);
      expect(Pack.fromRow('giant', tables['packs']!.single).createdAt!.isAtSameMomentAs(DateTime.utc(2026, 10, 14, 8)), isTrue);
    });
  });

  group('Picture search', () {
    final flowers = _pack('flowers', name: 'Flowers');
    final daily = _pack('daily-2026-10', category: 'Daily');
    final pictures = [
      _pic('f1', 'flowers', 'Red tulips', order: 1),
      _pic('f2', 'flowers', 'Tulip field at dawn', order: 2),
      _pic('f3', 'flowers', 'Kraków market roses', order: 3),
      _pic('f4', 'flowers', 'Bowl of petals', order: 4),
      _pic('d20', 'daily-2026-10', 'Tulip vase', order: 20, date: '2026-10-20'),
      _pic('d21', 'daily-2026-10', 'Tulip bouquet', order: 21, date: '2026-10-21'),
      _pic('x1', 'hidden', 'Tulip hidden pack'),
    ];

    test('matches every word of the title, ignoring case and accents', () {
      final r = libraryPictures(pictures, packs: [flowers, daily], query: 'krakow ROSES', now: _now);
      expect(r.pictures.map((p) => p.id), ['f3']);
    });

    test('words match from their start, never inside another word', () {
      expect(libraryPictures(pictures, packs: [flowers], query: 'owl', now: _now).total, 0);
      expect(libraryPictures(pictures, packs: [flowers], query: 'bow', now: _now).pictures.map((p) => p.id), ['f4']);
      expect(libraryPictures(pictures, packs: [flowers], query: 'ros krak', now: _now).pictures.map((p) => p.id), ['f3']);
    });

    test('titles that start with the query come first; future daily days and other packs stay out', () {
      final r = libraryPictures(pictures, packs: [flowers, daily], query: 'tulip', now: _now);
      expect(r.pictures.map((p) => p.id), ['f2', 'd20', 'f1']);
      expect(r.total, 3);
    });

    test('only the packs of the current view are searched, and a limit keeps the list short', () {
      expect(libraryPictures(pictures, packs: [daily], query: 'tulip', now: _now).pictures.map((p) => p.id), ['d20']);
      final many = [for (var i = 0; i < 60; i++) _pic('m$i', 'flowers', 'Rose $i', order: i)];
      final r = libraryPictures(many, packs: [flowers], query: 'rose', now: _now, limit: 40);
      expect(r.pictures, hasLength(40));
      expect(r.total, 60);
      expect(libraryPictures(many, packs: [flowers], query: '  ', now: _now).total, 0);
    });
  });

  group('Lucky Wheel odds', () {
    test('the listed odds are the spin weights and add up to 100%', () {
      final odds = wheelOdds();
      final total = wheelSegments.fold<double>(0, (s, e) => s + e.weight);
      expect(odds, hasLength(wheelSegments.length));
      for (final o in odds) {
        expect((o.percent - o.segment.weight / total * 100).abs(), lessThanOrEqualTo(0.05 + 1e-9), reason: o.segment.label);
      }
      expect(odds.fold<double>(0, (s, o) => s + o.percent), closeTo(100, 1e-9));
      expect(odds.firstWhere((o) => o.segment.jackpot).percent, 1);
      expect(formatOdds(22.7), '22.7%');
      expect(formatOdds(23), '23%');
      expect(formatOdds(1), '1%');
    });

    test('the odds sheet lists the most likely prize first (112)', () {
      final odds = wheelOdds();
      for (var i = 1; i < odds.length; i++) {
        expect(odds[i].percent, lessThanOrEqualTo(odds[i - 1].percent));
      }
      expect([for (final o in odds) '${o.segment.amount} ${o.segment.name ?? 'coins'} ${formatOdds(o.percent)}'], [
        '100 coins 23%',
        '250 coins 23%',
        '5 Peeks 18%',
        '10 Peeks 14%',
        '1 Magic 10%',
        '3 Hints 9%',
        '3 Magic 2%',
        '1000 coins 1%',
      ]);
    });

    test('the prize table the owner approved (2026-10-15): a 1,000-coin jackpot at exactly 1%, 3 Magic more likely', () {
      List<int> amounts(Currency kind) => [for (final s in wheelSegments) if (s.kind == kind) s.amount];
      expect(amounts(Currency.peeks), [5, 10]);
      expect(amounts(Currency.magics), [1, 3]);
      expect(amounts(Currency.hints), [3]);
      expect(amounts(Currency.coins), [100, 250, 1000]);
      expect(amounts(Currency.tickets), isEmpty, reason: 'the wheel never pays for itself');
      final total = wheelSegments.fold<double>(0, (s, e) => s + e.weight);
      double chance(WheelSegment s) => s.weight / total;
      final jackpot = wheelSegments.where((s) => s.jackpot).single;
      expect(jackpot.amount, 1000);
      expect(chance(jackpot), closeTo(0.01, 1e-12));
      final threeMagic = wheelSegments.firstWhere((s) => s.kind == Currency.magics && s.amount == 3);
      expect(chance(threeMagic), greaterThan(chance(jackpot)));
      final coins = wheelSegments.where((s) => s.kind == Currency.coins).fold<double>(0, (v, s) => v + chance(s) * s.amount);
      expect(coins, closeTo(90.5, 0.01), reason: 'about 90 coins a spin (docs/economy.md)');
      final value = wheelSegments.fold<double>(0, (s, e) => s + e.weight * e.coinValue) / total;
      expect(value, inInclusiveRange(195, 210), reason: 'about 200 coins a spin, boosters at their price');
      expect([for (final s in wheelSegments) s.name], [null, 'Peeks', null, 'Hints', 'Peeks', 'Magic', null, 'Magic']);
    });

    test('a ×5 spin (owner, 2026-10-17): five tickets, the same odds, every prize five times', () {
      expect(Economy.wheelBigSpin, 5);
      final jackpot = wheelSegments.where((s) => s.jackpot).single;
      expect(jackpot.amountFor(Economy.wheelBigSpin), 5000);
      expect([for (final s in wheelSegments) s.amountFor(5)], [for (final s in wheelSegments) s.amount * 5]);
      expect([for (final s in wheelSegments) s.amountFor(1)], [for (final s in wheelSegments) s.amount]);
      // The value per ticket does not change: five times the prize for five times the price.
      final total = wheelSegments.fold<double>(0, (s, e) => s + e.weight);
      double perTicket(int times) => wheelSegments.fold<double>(0, (s, e) => s + e.weight * e.amountFor(times)) / total / (times * Economy.wheelSpinTickets);
      expect(perTicket(5), closeTo(perTicket(1), 1e-9));
    });

    test('the spin draws each slice in proportion to its weight', () {
      final counts = List.filled(wheelSegments.length, 0);
      const steps = 20000;
      for (var i = 0; i < steps; i++) {
        counts[wheelPick((i + 0.5) / steps)]++;
      }
      final total = wheelSegments.fold<double>(0, (s, e) => s + e.weight);
      for (var i = 0; i < wheelSegments.length; i++) {
        expect(counts[i], closeTo(wheelSegments[i].weight / total * steps, 1), reason: wheelSegments[i].label);
      }
      expect(wheelPick(0), 0);
      expect(wheelPick(0.9999999), wheelSegments.length - 1);
    });
  });

  // Home's Today card, once today's picture is solved (owner, 2026-10-17: it replaced the
  // "Tomorrow's daily puzzle" row).
  testWidgets('the Today card says when the new picture comes', (tester) async {
    var now = DateTime(2026, 10, 20, 18, 48);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: Scaffold(body: NewPictureIn(style: const TextStyle(), clock: () => now))));
    expect(find.text('New picture in 5h 12m'), findsOneWidget);
    now = DateTime(2026, 10, 20, 23, 59, 30);
    await tester.pump(const Duration(seconds: 31));
    expect(find.text('New picture in 1m'), findsOneWidget, reason: 'read again every 30 seconds');
  });

  test('Settings shows the build version and number', () {
    expect(formatAppVersion('1.7.0', '115'), '1.7.0 (115)');
    expect(formatAppVersion('1.7.0', ''), '1.7.0');
    expect(appStoreReviewUrl.toString(), 'https://apps.apple.com/app/id6821644423?action=write-review');
  });
}
