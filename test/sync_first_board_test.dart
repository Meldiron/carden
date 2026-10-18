// "Synced from another device: +17 coins, 1 picture solved" for a fresh guest on one iPhone
// (TestFlight feedback AL2POUherU5EVWc4K0Q1iYU, owner 2026-10-18). The guest's rows on the server
// show one device and one play-through: the first board, finished and paid once. Builds up to 127
// kept the catalogue (5.6 MB) in SharedPreferences, over the 4 MB iOS allows for an app's
// preferences, and iOS then stored none of the app's later writes: the sync's copy of the save on
// the device stayed as it was before the first board, and the next start compared the server with
// it. The first read after a start now tells only what another device or the server changed.
import 'package:carden/data/sync/changes.dart';
import 'package:carden/data/sync/notice.dart';
import 'package:carden/data/sync/ops.dart';
import 'package:carden/state/profile.dart';
import 'package:carden/state/sync.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_sync.dart';

/// Preferences as iOS kept them on disk: what was written up to [at], nothing after.
FakePrefs kept(Map<String, Object> at) => FakePrefs()..values.addAll(at);

/// The guided first board (Pink Sands Beach, 3x3) as the game saves it: a board per move, then the
/// win and the solve (+17 coins for three stars).
Future<String> playFirstBoard(Device d) async {
  final session = SyncOp.newId();
  for (var m = 1; m <= 5; m++) {
    d.progress.saveBoard('p-pink', gridSize: 9, mode: 'cards', layout: [m, 0, 2, 3, 4, 5, 6, 7, 8], moves: m, seconds: 8 * m, hints: 0, session: session, resumed: false);
    await d.settle();
  }
  d.progress.complete('p-pink', gridSize: 9, mode: 'cards', moves: 6, seconds: 46, hints: 0, stars: 3, session: session, resumed: false);
  await d.profile.recordCompletion(puzzleId: 'p-pink', cells: 9, stars: 3, firstTime: true);
  await d.settle();
  return session;
}

void main() {
  test('a fresh guest finishes the first board; a start that lost the device copy tells nothing', () async {
    final server = FakeServer();
    final guest = testUser('guest-simple');
    final phone = await Device(server, guest).open();
    // Written so far (the device's name, the guest's first profile row): on disk.
    final disk = Map<String, Object>.of(phone.prefs.values);
    await playFirstBoard(phone);
    expect(phone.sync.debugOps, isEmpty, reason: 'everything reached the server');
    final coins = 500 + Economy.completionCoins(9, 3);
    expect(server.profiles['guest-simple']!['coins'], coins);
    // Home, then a resume in the same run: nothing to tell.
    await phone.resume();
    expect(phone.container.read(syncNoticeProvider).isEmpty, isTrue);
    phone.close();

    // The next start finds only what was on disk: the save from before the first board.
    final again = await Device(server, guest, prefs: kept(disk)).open();
    addTearDown(again.close);
    await again.resume();
    expect(again.container.read(syncNoticeProvider).isEmpty, isTrue, reason: "this device's own first board is not news from another device");
    expect(again.me.coins, coins);
    expect(again.rows['p-pink']!.completed, isTrue);
  });

  test('what another device did meanwhile is still told on that start', () async {
    final server = FakeServer();
    final user = testUser('player-two');
    final phone = await Device(server, user).open();
    final disk = Map<String, Object>.of(phone.prefs.values);
    await playFirstBoard(phone);
    phone.close();

    // The laptop claims the daily gift and solves a picture.
    final laptop = await Device(server, user).open();
    addTearDown(laptop.close);
    await laptop.profile.claimDaily();
    laptop.progress.complete('pic9', gridSize: 16, mode: 'cards', moves: 20, seconds: 60, hints: 0, stars: 3, session: 'l1', resumed: false);
    await laptop.profile.recordCompletion(puzzleId: 'pic9', cells: 16, stars: 3, firstTime: true);
    await laptop.settle();

    final again = await Device(server, user, prefs: kept(disk)).open();
    addTearDown(again.close);
    await again.resume();
    final notice = again.container.read(syncNoticeProvider);
    expect(notice.dailyStreak, 1, reason: 'the laptop claimed the daily gift');
    expect(notice.solved, greaterThanOrEqualTo(1), reason: "the laptop's picture");
    expect(notice.coins, greaterThan(0));
  });

  test('a purchase added by the server while the app was closed is still told', () async {
    final server = FakeServer();
    final user = testUser('player-three');
    final phone = await Device(server, user).open();
    phone.close();
    server.profiles['player-three'] = server.write(server.profiles['player-three'], {'coins': 3500}, 'player-three');
    final again = await Device(server, user, prefs: phone.prefs).open();
    addTearDown(again.close);
    await again.resume();
    expect(again.container.read(syncNoticeProvider).coins, 3000);
  });

  test('which devices changed the save, from the op ids that arrived', () {
    const device = 'jgcy';
    final s1 = SyncSource.of(before: ['jgcy1'], after: ['jgcy1', 'jgcy2', 'jgcy3'], device: device);
    expect((s1.mine, s1.elsewhere, s1.thisDeviceOnly), (true, false, true));
    final s2 = SyncSource.of(before: ['jgcy1'], after: ['jgcy1', 'jgcy2', 'ab12x'], device: device);
    expect((s2.mine, s2.elsewhere, s2.thisDeviceOnly), (true, true, false));
    final s3 = SyncSource.of(before: ['jgcy1'], after: ['jgcy1'], device: device);
    expect((s3.mine, s3.elsewhere, s3.thisDeviceOnly), (false, false, false), reason: 'nothing arrived: a change made by the server');
  });

  test("the tidy-up keeps this device's newest op ids on the row", () async {
    final server = FakeServer();
    final phone = await Device(server, testUser('player-four')).open();
    addTearDown(phone.close);
    for (var i = 0; i < 30; i++) {
      await phone.profile.addCoins(1, reason: 'test');
      await phone.settle();
    }
    final ids = asStrings(server.profiles['player-four']!['appliedOps']);
    expect(ids.length, inInclusiveRange(SyncController.keepOwnIds, 20));
    expect(server.profiles['player-four']!['coins'], 530);
  });
}
