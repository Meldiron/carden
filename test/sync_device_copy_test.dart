// The save sync's copy of the rows on the iPhone is a file per player, never NSUserDefaults (which iOS
// stops storing past 4 MB for the whole app; TestFlight feedback 2026-10-18). A copy left in
// SharedPreferences by a build up to 127 moves to the file once; an older build installed again finds
// nothing there and reads the server, quietly; its queued ops stay in SharedPreferences.
import 'dart:convert';
import 'dart:io';

import 'package:carden/data/local_store.dart';
import 'package:carden/data/sync/device_copy.dart';
import 'package:carden/data/sync/device_copy_file.dart';
import 'package:carden/state/sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_sync.dart';

Map<String, dynamic> _copy(int coins, {Map<String, dynamic> progress = const {}}) => {
      'profile': {'userId': 'u1', 'coins': coins},
      'progress': progress,
      'cursor': null,
      'synced': true,
    };

void main() {
  late Directory dir;
  late LocalStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = await LocalStore.open();
    dir = Directory.systemTemp.createTempSync('cjw-sync-rows');
    addTearDown(() => dir.deleteSync(recursive: true));
  });

  File fileOf(String userId) => File('${dir.path}/$userId.rows.json');

  test('a copy is a file of its own, read back as written, the newest last', () async {
    final rows = FileSyncRows(store, dir);
    for (var c = 501; c <= 520; c++) {
      rows.write('u1', _copy(c));
    }
    // Before it is on disk the newest copy handed over is what a read finds.
    expect(rows.read('u1')!['profile']['coins'], 520);
    await rows.idle();
    expect(jsonDecode(fileOf('u1').readAsStringSync())['profile']['coins'], 520);
    expect(FileSyncRows(store, dir).read('u1')!['profile']['coins'], 520, reason: 'a new start reads the file');
    expect(store.getJson(syncRowsKey('u1')), isNull, reason: 'nothing in SharedPreferences');
    expect(dir.listSync().where((f) => f.path.endsWith('.part')), isEmpty);
  });

  test("a build up to 127's copy in SharedPreferences moves to the file once", () async {
    await store.setJson(syncRowsKey('u1'), _copy(517, progress: {'p-pink': {'completed': true}}));
    final rows = FileSyncRows(store, dir);
    final read = rows.read('u1')!;
    expect(read['profile']['coins'], 517);
    expect(store.getJson(syncRowsKey('u1')), isNull, reason: 'out of SharedPreferences at once');
    await rows.idle();
    expect(jsonDecode(fileOf('u1').readAsStringSync())['progress']['p-pink']['completed'], isTrue);

    // An older build installed again writes SharedPreferences: that copy is the newer one.
    await store.setJson(syncRowsKey('u1'), _copy(600));
    final again = FileSyncRows(store, dir);
    expect(again.read('u1')!['profile']['coins'], 600);
    await again.idle();
    expect(jsonDecode(fileOf('u1').readAsStringSync())['profile']['coins'], 600);
  });

  test('a copy is removed with its account', () async {
    final rows = FileSyncRows(store, dir);
    rows.write('u1', _copy(500));
    await rows.remove('u1');
    expect(fileOf('u1').existsSync(), isFalse);
    expect(rows.read('u1'), isNull);
  });

  test('a heavy player\'s copy stays out of SharedPreferences through the sync', () async {
    final server = FakeServer();
    final prefs = FakePrefs();
    final rows = FileSyncRows(LocalStore(prefs), dir);
    final phone = await Device(server, testUser('heavy'), prefs: prefs, overrides: [syncRowsProvider.overrideWithValue(rows)]).open();
    for (var i = 0; i < 40; i++) {
      phone.progress.complete('pic$i', gridSize: 16, mode: 'cards', moves: 20, seconds: 60, hints: 0, stars: 3, session: 's$i', resumed: false);
    }
    await phone.settle();
    await rows.idle();
    phone.close();
    expect(prefs.values.keys.where((k) => k.endsWith('.rows')), isEmpty);
    expect((jsonDecode(fileOf('heavy').readAsStringSync())['progress'] as Map).length, 40);
    // A start reads the copy from the file, and nothing is news.
    final again = await Device(server, testUser('heavy'), prefs: prefs, overrides: [syncRowsProvider.overrideWithValue(FileSyncRows(LocalStore(prefs), dir))]).open();
    addTearDown(again.close);
    expect(again.rows.length, 40);
    await again.resume();
    expect(again.container.read(syncNoticeProvider).isEmpty, isTrue);
  });
}
