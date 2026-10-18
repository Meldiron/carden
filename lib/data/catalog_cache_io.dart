import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'catalog_cache.dart';
import 'local_store.dart';

/// Apps (the iPhone): a file of its own, never SharedPreferences.
CatalogCache catalogCacheFor(LocalStore store) => FileCatalogCache(store);

/// The catalogue as one JSON file, `catalog.json` in the app's cache folder (Library/Caches on the
/// iPhone: not backed up; if iOS clears it, the next launch downloads the snapshot again).
///
/// Builds up to 127 kept it in SharedPreferences, which is NSUserDefaults on the iPhone. The
/// catalogue (about 8,700 rows, 5.6 million characters, 11 MB as iOS stores it) is far over the 4 MB
/// iOS allows for an app's whole preferences ("Attempting to store >= 4194304 bytes of data in
/// CFPreferences/NSUserDefaults on this platform is invalid"), so iOS stopped saving the app's
/// preferences: the welcome pages, the guided start and the settings were forgotten at every launch
/// (TestFlight, 2026-10-18). A copy an earlier build left there moves here once and leaves
/// SharedPreferences, which gives the preferences back their room.
class FileCatalogCache implements CatalogCache {
  FileCatalogCache(this._store);
  final LocalStore _store;

  /// Where the file lives. Tests point it at a temporary folder (path_provider needs the platform).
  @visibleForTesting
  static Future<Directory> Function() directory = getApplicationCacheDirectory;

  static const fileName = 'catalog.json';

  late final _prefs = PrefsCatalogCache(_store);

  Future<File> _file() async => File('${(await directory()).path}/$fileName');

  @override
  Future<Map<String, dynamic>?> read() async {
    final file = await _file();
    if (await file.exists()) {
      await _dropPrefsCopy();
      try {
        final json = jsonDecode(await file.readAsString());
        return json is Map<String, dynamic> ? json : null;
      } catch (_) {
        return null;
      }
    }
    // The first launch of this build: what an earlier build kept in SharedPreferences moves over.
    final old = await _prefs.read();
    if (old == null) return null;
    try {
      await write(old);
    } catch (e) {
      debugPrint('catalogue cache: not moved to a file ($e)');
    }
    await _dropPrefsCopy();
    return old;
  }

  @override
  Future<void> write(Map<String, dynamic> json) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    // Written next to it and renamed over it, so a launch never reads half a catalogue.
    final part = File('${file.path}.${DateTime.now().microsecondsSinceEpoch}.part');
    await part.writeAsString(jsonEncode(json), flush: true);
    await part.rename(file.path);
    await _dropPrefsCopy();
  }

  /// A catalogue left in SharedPreferences goes, whatever happens to the file: while it is there,
  /// iOS saves none of the app's preferences.
  Future<void> _dropPrefsCopy() async {
    if (_store.getText(PrefsCatalogCache.key) != null) await _store.remove(PrefsCatalogCache.key);
  }
}
