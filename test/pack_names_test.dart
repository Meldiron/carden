// Daily month packs are named "<Month> <Year>" (owner, 2026-10-18: the 24 months of 2023 and 2024 were
// stored as "Daily", which the Library, the pack page, Home and the completion overlay showed). A daily
// month whose stored name is empty or a bare generic word shows its month; every other name is kept.
import 'package:carden/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Pack pack(String id, String category, Object? name) => Pack.fromRow(id, {'name': name, 'category': category});

  test('a daily month called "Daily" shows its month and year', () {
    expect(pack('daily-2024-10', 'Daily', 'Daily').name, 'October 2024');
    expect(pack('daily-2023-01', 'Daily', 'Daily').name, 'January 2023');
    expect(pack('daily-2024-12', 'Daily', ' daily ').name, 'December 2024');
    expect(pack('daily-2024-02', 'Daily', 'Daily puzzles').name, 'February 2024');
  });

  test('an empty or missing name shows the month too', () {
    expect(pack('daily-2025-06', 'Daily', '').name, 'June 2025');
    expect(pack('daily-2025-06', 'Daily', null).name, 'June 2025');
  });

  test('a real name is kept', () {
    expect(pack('daily-2026-10', 'Daily', 'October 2026').name, 'October 2026');
    expect(pack('daily-2026-10', 'Daily', 'Autumn days').name, 'Autumn days');
  });

  test('only daily months: other packs and odd ids keep their name', () {
    expect(pack('nature-1', 'Nature', 'Daily').name, 'Daily');
    expect(pack('evpack-halloween-2026', 'Event', '').name, '');
    expect(pack('daily-extra', 'Daily', 'Daily').name, 'Daily');
    expect(pack('daily-2024-13', 'Daily', 'Daily').name, 'Daily');
  });

  test('the month still reads from the id', () {
    final p = pack('daily-2024-10', 'Daily', 'Daily');
    expect(p.isDaily, isTrue);
    expect(p.dailyMonth, DateTime(2024, 10));
  });
}
