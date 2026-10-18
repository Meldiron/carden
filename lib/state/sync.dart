import 'dart:async';
import 'dart:math';

import 'package:appwrite/models.dart' as models;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/guest_names.dart';
import '../core/name_filter.dart';
import '../core/qa.dart';
import '../data/local_store.dart';
import '../data/repositories.dart' show deterministicId;
import '../data/sync/backend.dart';
import '../data/sync/changes.dart';
import '../data/sync/device_copy.dart';
import '../data/sync/notice.dart';
import '../data/sync/ops.dart';
import '../models/models.dart';
import 'auth.dart';
import 'rewards.dart';
import 'settings.dart';

/// The player's save as the screens see it: the rows the server last returned with this device's
/// unsent changes applied on top.
@immutable
class SyncState {
  const SyncState({this.userId, this.profile, this.progress = const {}, this.pending = 0, this.offline = false});

  /// Whose save this is ([SyncController.local] while offline without an account).
  final String? userId;
  final Profile? profile;
  final Map<String, PuzzleProgress> progress;

  /// Changes waiting for the server.
  final int pending;

  /// The last request got no answer.
  final bool offline;
}

/// A board in progress on another device met an unsent board of the same picture on this one.
class BoardConflict {
  const BoardConflict({required this.puzzleId, required this.device, required this.other});
  final String puzzleId;
  final PuzzleProgress device;
  final PuzzleProgress other;
}

enum BoardChoice { device, other }

/// The board of a picture changed because of another device (an open game reloads it).
class BoardUpdate {
  const BoardUpdate({required this.puzzleId, required this.before, required this.after, this.chosen = false});
  final String puzzleId;
  final PuzzleProgress? before;
  final PuzzleProgress after;

  /// The player picked the other device's board in a [BoardConflict].
  final bool chosen;

  /// The other device went on with the board this device had saved.
  bool get continued => before != null && before!.session.isNotEmpty && before!.session == after.session;
}

class _Account {
  _Account(this.userId);
  final String userId;

  /// The last profile row the server returned (null before the first answer).
  Map<String, dynamic>? profile;

  /// The last progress rows the server returned, by puzzle id.
  final Map<String, Map<String, dynamic>> progress = {};
  final List<SyncOp> ops = [];

  /// Newest `$updatedAt` among the progress rows (the next fetch reads from there).
  String? cursor;

  /// When this run last read every row ([SyncController._fetch]), and when it last read or wrote
  /// each picture's row: a board is saved against a row that recent, or the save is read first.
  DateTime? fetchedAt;
  final Map<String, DateTime> readAt = {};

  /// Ops the server refused although the session holds (a row another player made at the row's id;
  /// security review 2026-10-17), by op id, with when. They stay queued, so the screens still show
  /// them, but the queue goes on without them; they are tried again on the next start, or an hour
  /// later on resume (the server's hourly sweep deletes such rows). Kept in memory only.
  final Map<String, DateTime> parked = {};

  /// The rows came from the server before, so a later fetch can tell what changed elsewhere.
  bool synced = false;

  /// Fetched in this run of the app.
  bool fetched = false;
  final ready = Completer<void>();

  bool get isLocal => userId == SyncController.local;
}

/// Keeps the save in step between this device and the server, and so with the player's other
/// devices (an iPhone and the web site on a laptop, say).
///
/// - Every change is an op ([SyncOp]) queued on the device and sent in order; the server applies
///   it with atomic operators against its own row, so changes from two devices add up.
/// - Unsent ops survive restarts; play without a connection is sent once the server answers.
/// - On start, on resume, on tab focus and after a sign-in the rows are fetched again; whatever
///   another device changed is shown once in a "Synced from another device" alert
///   ([syncNoticeProvider]), and a board in progress on both devices is the player's choice.
class SyncController extends Notifier<SyncState> {
  /// The save of a device that has never reached the server (no account yet).
  static const local = 'local';

  late LocalStore _store;

  /// The copy of the rows on the device (a file per player on the iPhone, [syncRowsProvider]).
  late SyncRows _rows;

  /// This device's name (`syncDevice`), the first four characters of its op ids and session ids.
  late String _device;
  _Account? _acct;
  models.User? _user;
  bool _foreground = true;
  bool _offline = false;
  int _backoff = 0;
  Timer? _retry;
  DateTime? _lastFetch;

  /// The op being sent right now (never folded into a newer one: its answer may still land).
  SyncOp? _inFlight;
  bool _wantFlush = false, _wantFetch = false, _wantFull = false, _wantSilent = false;
  Completer<void>? _done;
  final _boardUpdates = StreamController<BoardUpdate>.broadcast();

  /// Asks the player which board to keep; set by the app shell. Without it this device's is kept.
  Future<BoardChoice> Function(BoardConflict conflict)? resolver;

  SyncBackend get _backend => ref.read(syncBackendProvider);

  @override
  SyncState build() {
    _store = ref.read(localStoreProvider);
    _rows = ref.read(syncRowsProvider);
    var device = _store.getText('syncDevice');
    if (device == null || device.length != 4) _store.setText('syncDevice', device = SyncOp.newDevice());
    SyncOp.device = _device = device;
    ref.listen(authProvider, (_, next) {
      if (next.hasValue) Future.microtask(() => attach(next.value));
    });
    ref.onDispose(() {
      _retry?.cancel();
      _boardUpdates.close();
    });
    return const SyncState();
  }

  Stream<BoardUpdate> get boardUpdates => _boardUpdates.stream;

  /// Loads [user]'s save (or the device's own without an account) and starts syncing it. Completes
  /// once there is something to show: the copy stored on the device, or the server's answer.
  Future<void> attach(models.User? user) {
    _user = user ?? _user;
    final id = user?.$id ?? local;
    final current = _acct;
    if (current != null && current.userId == id) return current.ready.future;
    if (current != null) _saveRowsNow(current);
    final a = _load(id);
    // After a sign-in or sign-out the first read is quiet: the sign-in merge writes to the
    // account meanwhile, and the player knows they switched. On app start it tells.
    if (current != null) a.synced = false;
    // A device that started offline without an account kept its play on the device; the first
    // guest made for it takes that play over (a fresh save, so the changes apply as they are).
    if (!a.isLocal && user != null && user.email.isEmpty && user.phone.isEmpty && a.profile == null && a.ops.isEmpty) {
      final orphan = _load(local);
      if (orphan.ops.isNotEmpty) {
        a.ops.addAll(orphan.ops);
        _saveOps(a);
        _store.remove(_key(local, 'ops'));
        _rows.remove(local);
      }
    }
    _acct = a;
    _publish();
    if (a.isLocal || a.profile != null) a.ready.complete();
    if (!a.isLocal) unawaited(_kick(fetch: true, full: true));
    return a.ready.future;
  }

  /// Queues [op]: the screens show it at once, the server gets it as soon as it answers.
  void enqueue(SyncOp op) {
    final a = _acct;
    if (a == null) return;
    if (op.kind == OpKind.board) {
      // Only the newest board of a play-through matters (the totals are worked out per session).
      for (var i = a.ops.length - 1; i >= 0; i--) {
        final o = a.ops[i];
        if (o.target != OpTarget.progress || o.puzzleId != op.puzzleId) continue;
        if (o.kind == OpKind.board && o.args['session'] == op.args['session'] && o.tries == 0 && !identical(o, _inFlight)) a.ops.removeAt(i);
        break;
      }
    }
    a.ops.add(op);
    _saveOps(a);
    _publish();
    if (!a.isLocal) unawaited(_kick());
  }

  /// Sends what is queued. Completes when the queue is empty or the server stopped answering.
  Future<void> flush() => _kick();

  /// Reads the save from the server again (after sending what is queued). [silent] takes the
  /// server's rows without telling the player (a purchase made on this device, a merge).
  Future<void> sync({bool full = false, bool silent = false}) => _kick(fetch: true, full: full, silent: silent);

  /// The server is about to change the save itself (a purchase being added): reads during the
  /// next [quiet] take its changes in without the "Synced from another device" alert.
  void expectServerChange([Duration quiet = const Duration(seconds: 30)]) {
    final until = DateTime.now().add(quiet);
    if (_quietUntil == null || until.isAfter(_quietUntil!)) _quietUntil = until;
  }

  DateTime? _quietUntil;

  /// The app came back to the foreground (or the browser tab got the focus again).
  void onResume() {
    _foreground = true;
    final a = _acct;
    if (a == null) return;
    a.parked.removeWhere((_, at) => DateTime.now().difference(at) > parkedFor);
    if (a.isLocal) {
      unawaited(ref.read(authProvider.notifier).reconnect());
      return;
    }
    final recent = _lastFetch != null && DateTime.now().difference(_lastFetch!) < const Duration(seconds: 5);
    unawaited(recent && a.ops.isEmpty ? Future.value() : _kick(fetch: true));
  }

  /// The app went to the background (or the tab lost the focus): store the rows, try to send.
  void onPause() {
    _foreground = false;
    final a = _acct;
    if (a == null) return;
    _saveRowsNow(a);
    if (!a.isLocal && a.ops.isNotEmpty) unawaited(_kick());
  }

  // ---------------------------------------------------------------------------
  // Worker: one pass at a time, in order.
  // ---------------------------------------------------------------------------

  Future<void> _kick({bool fetch = false, bool full = false, bool silent = false}) {
    _wantFlush = true;
    if (fetch) _wantFetch = true;
    if (full) _wantFull = true;
    if (silent) _wantSilent = true;
    final running = _done;
    if (running != null) return running.future;
    final done = _done = Completer<void>();
    unawaited(_work(done));
    return done.future;
  }

  Future<void> _work(Completer<void> done) async {
    try {
      while (_wantFlush || _wantFetch) {
        final a = _acct;
        if (a == null || a.isLocal) break;
        final fetch = _wantFetch || !a.fetched, full = _wantFull || !a.fetched, silent = _wantSilent;
        _wantFlush = _wantFetch = _wantFull = _wantSilent = false;
        try {
          if (fetch) await _fetch(a, full: full, silent: silent);
          await _flush(a);
          _offline = false;
          _backoff = 0;
          _retry?.cancel();
        } catch (e) {
          final failure = classifyFailure(e);
          debugPrint('sync: ${failure.name}: $e');
          // The next pass does what this one could not (a read asked for, quietly or not).
          if (fetch) _wantFetch = true;
          if (full) _wantFull = true;
          if (silent) _wantSilent = true;
          _offline = true;
          if (_acct == a) _publish();
          if (failure == SyncFailure.auth) {
            // The session is gone: retrying cannot help until the sign-in is sorted out.
            unawaited(ref.read(authProvider.notifier).reconnect(force: true));
          } else {
            _scheduleRetry();
          }
          if (!a.ready.isCompleted) a.ready.complete();
          break;
        }
        if (!a.ready.isCompleted) a.ready.complete();
      }
    } finally {
      _wantFlush = false;
      _done = null;
      done.complete();
    }
  }

  void _scheduleRetry() {
    if (_retry?.isActive == true) return;
    const delays = [2, 5, 15, 30, 60];
    final wait = Duration(seconds: delays[min(_backoff, delays.length - 1)]);
    _backoff++;
    _retry = Timer(wait, () {
      if (_foreground) unawaited(_kick());
    });
  }

  /// Reads the rows again and works out what another device changed.
  Future<void> _fetch(_Account a, {required bool full, required bool silent}) async {
    var fresh = await _backend.getProfile(a.userId) ?? await _backend.createProfile(a.userId, _newProfile(a.userId));
    if (_qaGuest && fresh['isTest'] != true) fresh = await _backend.updateProfile(a.userId, {'isTest': true});
    final since = !full && a.cursor != null ? _before(a.cursor!) : null;
    final rows = await _backend.progressRows(a.userId, since: since);
    _lastFetch = a.fetchedAt = DateTime.now();
    final quiet = _quietUntil != null && DateTime.now().isBefore(_quietUntil!);
    final known = a.synced, tell = a.synced && !silent && !quiet;
    var notice = SyncNotice.empty;
    // The first read of a run compares the server with the copy stored on the device, which can lack
    // this device's own last writes (iOS stored none of the app's preferences while builds up to 127
    // kept the catalogue there: TestFlight feedback, 2026-10-18). What changed since is told only
    // when another device or the server did it.
    final restored = !a.fetched;

    // Profile ops the server already has: sent before, but the answer never came.
    final applied = asStrings(fresh['appliedOps']).toSet();
    var expected = a.profile;
    for (final op in [...a.ops]) {
      if (op.target != OpTarget.profile || !applied.contains(op.id)) continue;
      final plan = expected == null ? null : op.build(expected);
      if (expected != null && plan != null && plan.skipped == null) expected = applyChanges(expected, plan.changes);
      _finish(a, op, plan?.ledger ?? const [], fresh);
    }
    final source = SyncSource.of(before: asStrings(a.profile?['appliedOps']), after: applied, device: _device);
    if (tell && expected != null && !(restored && source.thisDeviceOnly)) notice += SyncNotice.profile(expected, fresh);
    a.profile = fresh;

    final before = <String, Map<String, dynamic>>{}, after = <String, Map<String, dynamic>>{};
    for (final r in rows) {
      final pid = r['puzzleId']?.toString();
      if (pid == null) continue;
      _advance(a, r['\$updatedAt']);
      final old = a.progress[pid];
      if (old != null && old['\$updatedAt'] == r['\$updatedAt']) continue;
      a.progress[pid] = r;
      if (_ownWrite(a, pid, old, r)) continue;
      before[pid] = old ?? const {};
      after[pid] = r;
    }

    final updates = <BoardUpdate>[];
    for (final pid in known ? after.keys : const <String>[]) {
      final r = after[pid]!;
      final remote = (r['layout'] ?? '').toString();
      final pending = a.ops.where((o) => o.kind == OpKind.board && o.puzzleId == pid).lastOrNull;
      final old = before[pid]!.isEmpty ? null : _parse(a.userId, pid, before[pid]!);
      if (remote.isEmpty) {
        // The board this device has (unsent, or the one it saved last) was finished on another
        // device: an open game of it closes. Its unsent saves change nothing when they are sent.
        final had = before[pid]!;
        final here = pending?.args['session'] ?? ((had['layout'] ?? '').toString().isNotEmpty ? had['session'] : null);
        if (boardFinished(r, here)) updates.add(BoardUpdate(puzzleId: pid, before: old, after: _parse(a.userId, pid, r)));
        continue;
      }
      if (pending == null) {
        updates.add(BoardUpdate(puzzleId: pid, before: old, after: _parse(a.userId, pid, r)));
        continue;
      }
      if (pending.args['layout'] == remote) continue;
      final conflict = BoardConflict(puzzleId: pid, device: _parse(a.userId, pid, _progressRow(a, pid)), other: _parse(a.userId, pid, r));
      final choice = await (resolver?.call(conflict) ?? Future.value(BoardChoice.device));
      if (choice == BoardChoice.other) {
        a.ops.removeWhere((o) => o.kind == OpKind.board && o.puzzleId == pid);
        _saveOps(a);
        updates.add(BoardUpdate(puzzleId: pid, before: conflict.device, after: conflict.other, chosen: true));
      } else {
        // The player kept this device's board: not news from the other device.
        after[pid] = {...r, 'layout': before[pid]!['layout']};
      }
    }
    if (tell) {
      // After a start, this device's own play-throughs (their session ids name the device) are not
      // news either, unless another device has been at work since (it may have finished one).
      final news = restored && !source.elsewhere ? {for (final e in after.entries) if (!_ownSession(e.value)) e.key: e.value} : after;
      notice += SyncNotice.progress(before, news);
    }

    a.synced = true;
    a.fetched = true;
    _saveRows(a);
    if (_acct == a) _publish();
    if (_acct == a) {
      for (final u in updates) {
        _boardUpdates.add(u);
      }
    }
    _tell(a, notice);
  }

  /// A play-through this device started (its session id begins with the device's name).
  bool _ownSession(Map<String, dynamic> row) => (row['session'] ?? '').toString().startsWith(_device);

  /// A changed row that is this device's own write (its answer was lost): the first unsent ops of
  /// the picture produce exactly it.
  bool _ownWrite(_Account a, String pid, Map<String, dynamic>? old, Map<String, dynamic> r) {
    var row = old ?? <String, dynamic>{};
    for (final o in a.ops) {
      if (o.target != OpTarget.progress || o.puzzleId != pid) continue;
      row = applyChanges(row, o.build(row).changes);
      if ((row['layout'] ?? '') == (r['layout'] ?? '') &&
          asInt(row['moves']) == asInt(r['moves']) &&
          (row['session'] ?? '') == (r['session'] ?? '') &&
          rowSolved(row) == rowSolved(r)) {
        return true;
      }
    }
    return false;
  }

  /// How long a row read or written by this device counts as the server's for a board save.
  /// Saves during play keep it fresh with their own answers, so only a save after a pause reads.
  @visibleForTesting
  static Duration boardFreshFor = const Duration(seconds: 30);

  bool _fresh(_Account a, String pid) {
    final now = DateTime.now();
    bool recent(DateTime? t) => t != null && now.difference(t) < boardFreshFor;
    return recent(a.fetchedAt) || recent(a.readAt[pid]);
  }

  /// This device's newest op ids the tidy-up leaves on the profile row.
  static const keepOwnIds = 10;

  /// How long a parked op waits before a resume tries it again.
  @visibleForTesting
  static Duration parkedFor = const Duration(hours: 1);

  Future<void> _flush(_Account a) async {
    var read = false;
    for (;;) {
      final op = a.ops.where((o) => !a.parked.containsKey(o.id)).firstOrNull;
      if (op == null) break;
      if (!read && op.kind == OpKind.board && !_fresh(a, op.puzzleId!)) {
        // A board saved after a while without hearing from the server (a tab left open, a
        // reconnect): another device may have gone on with it or finished it meanwhile. The read
        // decides first (a newer board, the player's choice, a finished play-through); one read
        // covers every row, so once per pass.
        read = true;
        await _fetch(a, full: false, silent: false);
        continue;
      }
      try {
        _inFlight = op;
        await _send(a, op);
      } catch (e) {
        final f = classifyFailure(e);
        if (f == SyncFailure.rejected || (f == SyncFailure.missing && op.target != OpTarget.profile)) {
          debugPrint('sync: dropped $op: $e');
          a.ops.remove(op);
          _saveOps(a);
          if (_acct == a) _publish();
          continue;
        }
        if (f == SyncFailure.missing) {
          // The profile row is gone (deleted elsewhere): start it again, then send.
          a.profile = await _backend.createProfile(a.userId, _newProfile(a.userId));
          continue;
        }
        if (f == SyncFailure.auth && op.target != OpTarget.profile && await _signedIn()) {
          // The session holds, so the row refused this player: another player made a row at its
          // id. Park the op (quietly; it stays on screen) and send the rest.
          debugPrint('sync: parked $op: $e');
          a.parked[op.id] = DateTime.now();
          if (_acct == a) _publish();
          continue;
        }
        op.tries++;
        _saveOps(a);
        rethrow;
      } finally {
        _inFlight = null;
      }
    }
    await _tidy(a);
  }

  Future<void> _send(_Account a, SyncOp op) async {
    switch (op.target) {
      case OpTarget.profile:
        final prev = a.profile;
        var row = prev;
        if (row == null || op.needsFresh || op.tries > 0) {
          final fresh = await _backend.getProfile(a.userId) ?? await _backend.createProfile(a.userId, _newProfile(a.userId));
          final landed = asStrings(fresh['appliedOps']).contains(op.id);
          if (prev != null && a.synced) {
            final plan = landed ? op.build(prev) : null;
            final expected = plan != null && plan.skipped == null ? applyChanges(prev, plan.changes) : prev;
            _tell(a, SyncNotice.profile(expected, fresh));
          }
          a.profile = row = fresh;
          if (landed) {
            _finish(a, op, prev == null ? const [] : op.build(prev).ledger, fresh);
            return;
          }
        }
        final plan = op.build(row);
        if (plan.skipped != null) {
          _tell(a, SyncNotice(skipped: [plan.skipped!]));
          _finish(a, op, const [], row);
          return;
        }
        if (plan.isEmpty) {
          _finish(a, op, const [], row);
          return;
        }
        final changes = <String, FieldChange>{...plan.changes, 'appliedOps': Append([op.id])};
        final expected = applyChanges(row, changes);
        final res = await _backend.updateProfile(a.userId, wireData(changes));
        if (a.synced) _tell(a, SyncNotice.profile(expected, res));
        a.profile = res;
        _finish(a, op, plan.ledger, res);
      case OpTarget.progress:
        final pid = op.puzzleId!;
        var row = a.progress[pid];
        if (op.needsFresh || (row == null && op.tries > 0)) {
          final fresh = await _backend.getProgress(a.userId, pid);
          if (fresh != null) {
            if (a.synced && row != null && row['\$updatedAt'] != fresh['\$updatedAt'] && !_ownWrite(a, pid, row, fresh)) {
              _tell(a, SyncNotice.progress({pid: row}, {pid: fresh}));
            }
            a.progress[pid] = row = fresh;
            a.readAt[pid] = DateTime.now();
          }
        }
        final plan = op.build(row ?? const {});
        if (plan.isEmpty) {
          // A board of a play-through already finished: nothing to write.
          _finish(a, op, const [], null);
          return;
        }
        if (op.kind == OpKind.win && plan.alreadySolved) _paysAsReplay(a, pid);
        final res = await _backend.upsertProgress(a.userId, pid, wireData(plan.changes));
        // The fetch cursor moves only with rows read from the server, or another device's rows
        // written before this one would be skipped by the next read.
        a.progress[pid] = res;
        a.readAt[pid] = DateTime.now();
        _finish(a, op, const [], null);
      case OpTarget.event:
        final eventId = op.args['eventId'] as String;
        if (op.tries > 0 && asStrings((await _backend.getEvent(a.userId, eventId))?['appliedOps']).contains(op.id)) {
          _finish(a, op, const [], null);
          return;
        }
        await _backend.upsertEvent(a.userId, eventId, wireData(op.build(const {}).changes));
        _finish(a, op, const [], null);
      case OpTarget.ledger:
        await _backend.createLedger(a.userId, op.args['rowId'] as String, {
          'amount': op.args['amount'],
          'currency': op.args['currency'],
          'reason': op.args['reason'],
          'balanceAfter': op.args['balanceAfter'],
        });
        _finish(a, op, const [], null);
    }
  }

  /// The picture had been solved on another device first: this solve pays as a replay.
  void _paysAsReplay(_Account a, String pid) {
    for (var i = 0; i < a.ops.length; i++) {
      final o = a.ops[i];
      if (o.kind == OpKind.solve && o.puzzleId == pid && o.args['first'] == true) {
        a.ops[i] = o.copyWith(args: {...o.args, 'first': false});
        _saveOps(a);
        return;
      }
    }
  }

  Future<bool> _signedIn() async {
    try {
      return await _backend.signedIn();
    } catch (_) {
      return false;
    }
  }

  /// Removes a confirmed op; its ledger rows are written next (with the server's balances).
  void _finish(_Account a, SyncOp op, List<LedgerLine> ledger, Map<String, dynamic>? row) {
    final i = a.ops.indexOf(op);
    if (i >= 0) a.ops.removeAt(i);
    if (ledger.isNotEmpty && row != null) {
      a.ops.insertAll(max(0, i), [
        for (var k = 0; k < ledger.length; k++)
          SyncOp.ledgerRow(rowId: '${op.id}-$k', line: ledger[k], balanceAfter: asInt(row[ledger[k].currency])),
      ]);
    }
    // Rows first: a start that finds the op gone must also find its effect in the stored rows.
    _saveRowsNow(a);
    _saveOps(a);
    if (_acct == a) _publish();
  }

  /// Housekeeping once the queue is empty: duplicates from two devices appending the same key,
  /// old op ids and quest keys, and the level column (a mirror of the XP).
  Future<void> _tidy(_Account a) async {
    final p = a.profile;
    if (p == null) return;
    final changes = <String, FieldChange>{};
    for (final k in const ['unlockedPacks', 'unlockedTiers', 'unlockedAvatars', 'claimedAchievements', 'claimedGoals']) {
      final list = asStrings(p[k]);
      if (dedupe(list).length != list.length) changes[k] = const Unique();
    }
    final now = DateTime.now().toUtc();
    // This device's ids once their ops are confirmed (none is queued any more), all but its newest
    // [keepOwnIds] (they show which device changed the save last, [SyncSource]), and any id older
    // than 30 days (a device that is gone). Another device's recent ids stay: it may still be
    // waiting for an answer.
    final ids = asStrings(p['appliedOps']);
    final queued = {for (final o in a.ops) o.id};
    final mine = [for (final id in ids) if (id.startsWith(SyncOp.device) && !queued.contains(id)) id]
      ..sort((x, y) => (SyncOp.idTime(x) ?? now).compareTo(SyncOp.idTime(y) ?? now));
    final stale = [for (final id in ids) if ((SyncOp.idTime(id) ?? now).isBefore(now.subtract(const Duration(days: 30)))) id];
    final drop = mine.length > 20 ? mine.sublist(0, mine.length - keepOwnIds) : const <String>[];
    if (drop.isNotEmpty || stale.isNotEmpty) changes['appliedOps'] = Remove(dedupe([...drop, ...stale]));
    if (!changes.containsKey('claimedGoals')) {
      final old = [for (final k in asStrings(p['claimedGoals'])) if (_questDay(k)?.isBefore(now.subtract(const Duration(days: 21))) ?? false) k];
      if (old.isNotEmpty) changes['claimedGoals'] = Remove(old);
    }
    final level = LevelRewards.levelForXp(asInt(p['xp']));
    if (asInt(p['level']) != level) changes['level'] = Put(level);
    if (changes.isEmpty) return;
    a.profile = await _backend.updateProfile(a.userId, wireData(changes));
    _saveRows(a);
    if (_acct == a) _publish();
  }

  static final _dayPattern = RegExp(r'(\d{4})-(\d{2})-(\d{2})');

  static DateTime? _questDay(String key) {
    final m = _dayPattern.firstMatch(key);
    return m == null ? null : DateTime.utc(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  }

  void _tell(_Account a, SyncNotice n) {
    if (n.isEmpty || _acct != a) return;
    ref.read(syncNoticeProvider.notifier).add(n);
  }

  // ---------------------------------------------------------------------------
  // Views
  // ---------------------------------------------------------------------------

  Map<String, dynamic>? _shownRow;
  Profile? _shown;
  final _parsed = Expando<PuzzleProgress>();
  Map<String, PuzzleProgress> _shownProgress = const {};
  final _pendingShown = <String, (Map<String, dynamic>, PuzzleProgress)>{};

  void _publish() {
    final a = _acct;
    if (a == null) return;
    final pending = <String>{for (final o in a.ops) if (o.target == OpTarget.progress) o.puzzleId!};
    final row = _profileRow(a);
    // The same Profile object while nothing in it changed, so a board save does not rebuild
    // every screen that shows coins or the level.
    if (_shown == null || _shown!.id != a.userId || !_sameValues(row, _shownRow)) {
      _shown = Profile.fromRow(a.userId, row);
      _shownRow = row;
    }
    // The same map (and the same row objects) while no picture changed, so a profile change does
    // not recompute everything that follows the progress.
    final progress = <String, PuzzleProgress>{
      for (final e in a.progress.entries)
        if (!pending.contains(e.key)) e.key: _parsed[e.value] ??= _parse(a.userId, e.key, e.value),
    };
    for (final pid in pending) {
      final row = _progressRow(a, pid);
      final prev = _pendingShown[pid];
      if (prev != null && prev.$2.userId == a.userId && _sameValues(prev.$1, row)) {
        progress[pid] = prev.$2;
      } else {
        final p = _parse(a.userId, pid, row);
        _pendingShown[pid] = (row, p);
        progress[pid] = p;
      }
    }
    _pendingShown.removeWhere((pid, _) => !pending.contains(pid));
    final unchanged = progress.length == _shownProgress.length && progress.entries.every((e) => identical(_shownProgress[e.key], e.value));
    if (!unchanged) _shownProgress = progress;
    state = SyncState(
      userId: a.userId,
      profile: _shown,
      progress: _shownProgress,
      pending: a.ops.where((o) => !a.parked.containsKey(o.id)).length,
      offline: _offline,
    );
  }

  Map<String, dynamic> _profileRow(_Account a) {
    var row = a.profile ?? {...Profile.guest(a.userId).toData(), '\$id': a.userId};
    for (final op in a.ops) {
      if (op.target != OpTarget.profile) continue;
      final plan = op.build(row);
      if (plan.skipped == null) row = applyChanges(row, plan.changes);
    }
    return row;
  }

  Map<String, dynamic> _progressRow(_Account a, String pid) {
    Map<String, dynamic> row = a.progress[pid] ?? {'userId': a.userId, 'puzzleId': pid};
    for (final op in a.ops) {
      if (op.target == OpTarget.progress && op.puzzleId == pid) row = applyChanges(row, op.build(row).changes);
    }
    return row;
  }

  PuzzleProgress _parse(String userId, String pid, Map<String, dynamic> row) =>
      PuzzleProgress.fromRow((row['\$id'] ?? deterministicId(userId, pid)).toString(), {'userId': userId, 'puzzleId': pid, ...row});

  // ---------------------------------------------------------------------------
  // Storage on the device
  // ---------------------------------------------------------------------------

  static String _key(String userId, String part) => 'sync.v1.$userId.$part';

  _Account _load(String userId) {
    final a = _Account(userId);
    for (final j in _store.getJsonList(_key(userId, 'ops')) ?? const []) {
      try {
        a.ops.add(SyncOp.fromJson(Map<String, dynamic>.from(j as Map)));
      } catch (e) {
        debugPrint('sync: unreadable op dropped: $e');
      }
    }
    final rows = _rows.read(userId);
    if (rows != null) {
      final p = rows['profile'];
      if (p is Map) a.profile = Map<String, dynamic>.from(p);
      final pr = rows['progress'];
      if (pr is Map) {
        for (final e in pr.entries) {
          a.progress[e.key.toString()] = Map<String, dynamic>.from(e.value as Map);
        }
      }
      a.cursor = rows['cursor'] as String?;
      a.synced = rows['synced'] == true;
      return a;
    }
    // Saves cached by versions before the sync: a starting point until the server answers (not
    // compared with it, since they may hold changes the server never got).
    final legacy = _store.getJson('profile');
    if (legacy != null && (legacy['id'] ?? local) == userId) {
      a.profile = {...legacy, '\$id': userId}..remove('id');
      for (final j in _store.getJsonList('progress') ?? const []) {
        final m = Map<String, dynamic>.from(j as Map);
        final pid = m['puzzleId']?.toString();
        if (pid != null && pid.isNotEmpty) a.progress[pid] = {...m, '\$id': m['id']}..remove('id');
      }
      _store.remove('profile');
      _store.remove('progress');
    }
    return a;
  }

  void _saveOps(_Account a) => _store.setJsonList(_key(a.userId, 'ops'), [for (final o in a.ops) o.toJson()]);

  void _saveRows(_Account a) => _saveRowsNow(a);

  void _saveRowsNow(_Account a) {
    if (a.profile == null && a.progress.isEmpty) return;
    _rows.write(a.userId, {'profile': a.profile, 'progress': a.progress, 'cursor': a.cursor, 'synced': a.synced});
  }

  void _advance(_Account a, dynamic updatedAt) {
    final t = updatedAt?.toString();
    if (t == null || t.isEmpty) return;
    final c = a.cursor;
    if (c == null || DateTime.parse(t).isAfter(DateTime.parse(c))) a.cursor = t;
  }

  /// A little before [cursor], so rows written in the same instant are not missed.
  static String _before(String cursor) => DateTime.parse(cursor).toUtc().subtract(const Duration(minutes: 2)).toIso8601String();

  bool get _qaGuest {
    final u = _user;
    return QaRun.enabled && u != null && u.email.isEmpty && u.phone.isEmpty;
  }

  Map<String, dynamic> _newProfile(String userId) {
    final u = _user;
    final name = u != null && u.$id == userId && u.name.isNotEmpty && !NameFilter.isRefused(u.name) ? u.name : GuestNames.next();
    return Profile.guest(userId).copyWith(displayName: name, isTest: _qaGuest).toData();
  }

  @visibleForTesting
  List<SyncOp> get debugOps => List.unmodifiable(_acct?.ops ?? const []);
}

bool _sameValues(dynamic a, dynamic b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (!b.containsKey(k) || !_sameValues(a[k], b[k])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_sameValues(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

final syncProvider = NotifierProvider<SyncController, SyncState>(SyncController.new);

/// Where the sync keeps its copy of the rows on the device: SharedPreferences unless `main` opens the
/// platform's store (a file per player on the iPhone, `openSyncRows`).
final syncRowsProvider = Provider<SyncRows>((ref) => PrefsSyncRows(ref.watch(localStoreProvider)));

/// What arrived from other devices and has not been shown yet.
class SyncNoticeNotifier extends Notifier<SyncNotice> {
  @override
  SyncNotice build() => SyncNotice.empty;

  void add(SyncNotice n) {
    if (!n.isEmpty) state = state + n;
  }

  /// The notice to show now; cleared.
  SyncNotice take() {
    final n = state;
    state = SyncNotice.empty;
    return n;
  }
}

final syncNoticeProvider = NotifierProvider<SyncNoticeNotifier, SyncNotice>(SyncNoticeNotifier.new);
