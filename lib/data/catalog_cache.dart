/// Where the catalogue kept on the device lives (`CatalogSync`, docs/catalog-sync.md): a file on the
/// iPhone (`catalog_cache_io.dart`), IndexedDB on the web (`catalog_cache_web.dart`). Never
/// SharedPreferences: on the iPhone (NSUserDefaults) the catalogue is over the 4 MB iOS allows for all
/// of an app's preferences, and iOS then saved none of them; on the web, localStorage (5 MB per site,
/// shared with the save and the settings) refused it with `QuotaExceededError`, so every launch
/// downloaded the snapshot again.
library;

import 'catalog_cache_io.dart' if (dart.library.js_interop) 'catalog_cache_web.dart' as platform;
import 'local_store.dart';

abstract interface class CatalogCache {
  /// The stored catalogue (the JSON `CatalogSync` wrote), or null when there is none.
  Future<Map<String, dynamic>?> read();

  /// Stores [json] in place of what was there. Throws when it cannot be stored.
  Future<void> write(Map<String, dynamic> json);

  /// The cache of this platform: a file on the iPhone, IndexedDB on the web.
  static CatalogCache of(LocalStore store) => platform.catalogCacheFor(store);
}

/// The catalogue as one SharedPreferences value (`catalog`): where builds up to 127 kept it, read
/// once to move it out; on the web the fallback when IndexedDB cannot be opened.
class PrefsCatalogCache implements CatalogCache {
  PrefsCatalogCache(this.store);
  final LocalStore store;

  /// The SharedPreferences key (on the web, localStorage `flutter.catalog`).
  static const key = 'catalog';

  @override
  Future<Map<String, dynamic>?> read() async => store.getJson(key);

  @override
  Future<void> write(Map<String, dynamic> json) => store.setJson(key, json);
}
