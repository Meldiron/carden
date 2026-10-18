import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../local_store.dart';
import 'device_copy.dart';

/// Apps (the iPhone): a file per player.
Future<SyncRows> openSyncRows(LocalStore store) => FileSyncRows.open(store);

/// The copy as a file per player, `<Application Support>/sync/<userId>.rows.json` (the iPhone).
///
/// A copy found in SharedPreferences was written by a build up to 127 (this one moves it out at
/// once), so it is the newest there is: it moves to the file and leaves SharedPreferences. An older
/// build installed again finds no copy there and reads every row from the server, quietly, as on a
/// new device; its queued ops are where it left them.
class FileSyncRows implements SyncRows {
  FileSyncRows(this._store, this._dir);
  final LocalStore _store;
  final Directory _dir;

  /// The iPhone's: Application Support (kept, unlike Caches, which iOS may empty).
  static Future<FileSyncRows> open(LocalStore store) async => FileSyncRows(store, Directory('${(await getApplicationSupportDirectory()).path}/sync'));

  final _writers = <String, _FileWriter>{};

  File _file(String userId) => File('${_dir.path}/${Uri.encodeComponent(userId)}.rows.json');

  @override
  Map<String, dynamic>? read(String userId) {
    final old = _store.getJson(syncRowsKey(userId));
    if (old != null) {
      write(userId, old);
      _store.remove(syncRowsKey(userId));
      return old;
    }
    // Not stored yet: what was handed over last is the copy.
    final pending = _writers[userId]?.latest;
    try {
      final raw = pending ?? (_file(userId).existsSync() ? _file(userId).readAsStringSync() : null);
      final json = raw == null ? null : jsonDecode(raw);
      return json is Map<String, dynamic> ? json : null;
    } catch (e) {
      debugPrint('sync: device copy not read ($e)');
      return null;
    }
  }

  @override
  void write(String userId, Map<String, dynamic> rows) => (_writers[userId] ??= _FileWriter(_file(userId))).put(jsonEncode(rows));

  @override
  Future<void> remove(String userId) async {
    await _writers.remove(userId)?.idle();
    await _store.remove(syncRowsKey(userId));
    try {
      final file = _file(userId);
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('sync: device copy not removed ($e)');
    }
  }

  /// Every write handed over so far is on disk (tests).
  @visibleForTesting
  Future<void> idle() => Future.wait([for (final w in _writers.values) w.idle()]);
}

/// Writes one file in the background, one write at a time and only the newest content: a write
/// asked for while one runs replaces any other waiting. Each lands next to the file and is renamed
/// over it, so a start never reads half a copy.
class _FileWriter {
  _FileWriter(this.file);
  final File file;

  /// The newest content handed over (read back before it is on disk).
  String? latest;
  String? _next;
  Future<void>? _running;

  void put(String content) {
    latest = _next = content;
    _running ??= _drain();
  }

  Future<void> _drain() async {
    while (_next != null) {
      final content = _next!;
      _next = null;
      try {
        await file.parent.create(recursive: true);
        final part = File('${file.path}.part');
        await part.writeAsString(content, flush: true);
        await part.rename(file.path);
      } catch (e) {
        debugPrint('sync: device copy not stored ($e)');
      }
    }
    _running = null;
  }

  Future<void> idle() => _running ?? Future<void>.value();
}
