import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/appwrite.dart';
import '../data/catalog_cache.dart';
import '../data/local_store.dart';
import '../data/repositories.dart';

/// Catalogue rows (packs, puzzles, events) as maps with `$id`, keyed by table id.
typedef CatalogTables = Map<String, List<Map<String, dynamic>>>;

/// The catalogue kept on the device: snapshot + delta sync, so a launch reads a handful of rows
/// instead of the whole catalogue (each row returned is a billed database read).
///
/// The base comes from the daily snapshot file (`functions/catalog-snapshot`), on first launch and
/// every [rebaseEvery]; without a snapshot, from the tables. Every sync then reads the rows updated
/// since the newest one it has, per table. Deleted puzzles are caught per pack: the content tool
/// updates a pack's row whenever it removes or replaces puzzles, so every pack whose `$updatedAt`
/// moved has its puzzles read again whole. Packs and events are never deleted by the content tool;
/// rows deleted by hand disappear with the next base.
///
/// The copy lives in [CatalogCache]: a file on the iPhone, IndexedDB on the web. Never
/// SharedPreferences: it is too large for iOS's preferences and the web's localStorage.
class CatalogSync {
  CatalogSync(this._store, this._source, {DateTime Function()? clock, CatalogCache? cache})
      : _clock = clock ?? DateTime.now,
        _cache = cache ?? CatalogCache.of(_store);
  final LocalStore _store;
  final CatalogSource _source;
  final DateTime Function() _clock;
  final CatalogCache _cache;

  static const tables = [AppwriteConfig.packs, AppwriteConfig.puzzles, AppwriteConfig.events];
  static const cacheKey = PrefsCatalogCache.key;
  static const _legacyCacheKeys = ['packs', 'puzzles', 'puzzleCatalog'];
  static const _version = 1;
  static const rebaseEvery = Duration(days: 7);

  /// Rows written just before the newest one are read again, in case concurrent writes landed out of order.
  static const overlap = Duration(seconds: 10);

  /// Columns the app never reads: Appwrite internals and the content tool's original picture addresses.
  static const _drop = {r'$permissions', r'$sequence', r'$tableId', r'$databaseId', r'$createdAt', 'sourceUrl', 'coverSourceUrl'};

  /// Pack rows keep `$createdAt`: the Library marks packs added in the last week as New.
  static const _keepCreatedAt = {AppwriteConfig.packs};

  /// The catalogue on the device, for when the server cannot be reached.
  Future<CatalogTables?> cached() async => _CatalogState.fromJson(await _read())?.tables;

  Future<Map<String, dynamic>?> _read() async {
    try {
      return await _cache.read();
    } catch (e) {
      debugPrint('catalogue cache not read: $e');
      return null;
    }
  }

  /// Brings the device copy in step with the server and returns it.
  Future<CatalogTables> sync() async {
    final now = _clock();
    var state = _CatalogState.fromJson(await _read());
    var dirty = false;
    if (state == null || now.difference(state.baseAt).abs() > rebaseEvery) {
      state = await _base(now);
      dirty = true;
    }

    final current = state;
    final fresh = await Future.wait([
      for (final t in tables) _source.rowsSince(t, (current.watermarks[t] ?? DateTime.utc(1970)).subtract(overlap).toUtc().toIso8601String()),
    ]);
    final incoming = {for (var i = 0; i < tables.length; i++) tables[i]: [for (final r in fresh[i]) _clean(r, tables[i])]};

    final packs = state.rows[AppwriteConfig.packs]!;
    final changedPacks = {
      for (final p in incoming[AppwriteConfig.packs]!)
        if (packs[p[r'$id']]?[r'$updatedAt'] != p[r'$updatedAt']) '${p[r'$id']}',
    };
    if (changedPacks.isNotEmpty) {
      state.rows[AppwriteConfig.puzzles]!.removeWhere((_, r) => changedPacks.contains(r['packId']));
      incoming[AppwriteConfig.puzzles]!.addAll([for (final r in await _source.puzzleRowsOfPacks(changedPacks.toList())) _clean(r, AppwriteConfig.puzzles)]);
      dirty = true;
    }

    for (final t in tables) {
      final rows = state.rows[t]!;
      for (final r in incoming[t]!) {
        final id = '${r[r'$id']}';
        if (rows[id] != null && jsonEncode(rows[id]) == jsonEncode(r)) continue;
        rows[id] = r;
        dirty = true;
      }
      final watermark = _latest(incoming[t]!, state.watermarks[t]);
      if (watermark != state.watermarks[t]) {
        state.watermarks[t] = watermark;
        dirty = true;
      }
    }

    if (dirty) {
      try {
        for (final key in _legacyCacheKeys) {
          await _store.remove(key);
        }
        await _cache.write(state.toJson(_version));
      } catch (e) {
        debugPrint('catalogue cache not saved: $e');
      }
    }
    return state.tables;
  }

  /// A fresh base: the newest snapshot, or every row when there is none (or it cannot be used).
  Future<_CatalogState> _base(DateTime now) async {
    Map<String, dynamic>? snap;
    try {
      snap = await _source.snapshot();
    } catch (e) {
      debugPrint('catalogue snapshot unavailable: $e');
    }
    final snapTables = snap?['v'] == 1 ? snap!['tables'] : null;
    if (snapTables is Map && tables.every((t) => snapTables[t] is Map)) {
      return _CatalogState(
        baseAt: now,
        watermarks: {for (final t in tables) t: DateTime.tryParse('${snapTables[t]['watermark']}')},
        rows: {for (final t in tables) t: _byId([for (final r in (snapTables[t]['rows'] as List).whereType<Map>()) _clean(Map<String, dynamic>.from(r), t)])},
      );
    }
    final full = await Future.wait([for (final t in tables) _source.rows(t)]);
    return _CatalogState(
      baseAt: now,
      watermarks: {for (var i = 0; i < tables.length; i++) tables[i]: _latest(full[i], null)},
      rows: {for (var i = 0; i < tables.length; i++) tables[i]: _byId([for (final r in full[i]) _clean(r, tables[i])])},
    );
  }

  static Map<String, dynamic> _clean(Map<String, dynamic> row, String table) => {
        for (final e in row.entries)
          if (!_drop.contains(e.key) || (e.key == r'$createdAt' && _keepCreatedAt.contains(table))) e.key: e.value,
      };

  static Map<String, Map<String, dynamic>> _byId(List<Map<String, dynamic>> rows) => {for (final r in rows) '${r[r'$id']}': r};

  static DateTime? _latest(Iterable<Map<String, dynamic>> rows, DateTime? start) {
    var latest = start;
    for (final r in rows) {
      final t = DateTime.tryParse('${r[r'$updatedAt']}');
      if (t != null && (latest == null || t.isAfter(latest))) latest = t;
    }
    return latest;
  }
}

class _CatalogState {
  _CatalogState({required this.baseAt, required this.watermarks, required this.rows});
  final DateTime baseAt;
  final Map<String, DateTime?> watermarks;
  final Map<String, Map<String, Map<String, dynamic>>> rows;

  CatalogTables get tables => {for (final e in rows.entries) e.key: e.value.values.toList()};

  static _CatalogState? fromJson(Map<String, dynamic>? j) {
    final baseAt = DateTime.tryParse('${j?['baseAt']}');
    final t = j?['tables'];
    if (j == null || j['v'] != CatalogSync._version || baseAt == null || t is! Map || !CatalogSync.tables.every((id) => t[id] is Map)) return null;
    return _CatalogState(
      baseAt: baseAt,
      watermarks: {for (final id in CatalogSync.tables) id: DateTime.tryParse('${t[id]['watermark']}')},
      rows: {for (final id in CatalogSync.tables) id: CatalogSync._byId([for (final r in (t[id]['rows'] as List? ?? const []).whereType<Map>()) Map<String, dynamic>.from(r)])},
    );
  }

  Map<String, dynamic> toJson(int version) => {
        'v': version,
        'baseAt': baseAt.toIso8601String(),
        'tables': {
          for (final e in rows.entries) e.key: {'watermark': watermarks[e.key]?.toUtc().toIso8601String(), 'rows': e.value.values.toList()},
        },
      };
}
