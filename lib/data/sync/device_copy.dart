import '../local_store.dart';
import 'device_copy_file.dart' if (dart.library.js_interop) 'device_copy_web.dart' as platform;

/// Where the save sync keeps its copy of the player's rows on the device (the profile row and every
/// progress row, `SyncController`): `{profile, progress, cursor, synced}` for one player.
///
/// The copy grows with every picture played (about 0.8 KB a picture, up to about 5 KB with a long
/// finish log), so on the iPhone it lives in a file of its own (`FileSyncRows`, device_copy_file.dart): SharedPreferences
/// is NSUserDefaults there, and iOS stores none of an app's preferences once they pass 4 MB (the
/// catalogue did that in builds up to 127, TestFlight feedback 2026-10-18). The queue of unsent ops
/// stays in SharedPreferences: it is small, and an older build installed over this one still finds it.
abstract interface class SyncRows {
  /// The copy stored for [userId], or null.
  Map<String, dynamic>? read(String userId);

  /// Stores [rows] for [userId] in place of what was there (in the background, newest last).
  void write(String userId, Map<String, dynamic> rows);

  /// Forgets [userId]'s copy (account deletion, a `local` save handed to a guest).
  Future<void> remove(String userId);
}

/// The SharedPreferences key a copy had up to build 127, and still has on the web.
String syncRowsKey(String userId) => 'sync.v1.$userId.rows';

/// The copy as one SharedPreferences value (the web, where it is localStorage, and unit tests).
class PrefsSyncRows implements SyncRows {
  PrefsSyncRows(this._store);
  final LocalStore _store;

  @override
  Map<String, dynamic>? read(String userId) => _store.getJson(syncRowsKey(userId));

  @override
  void write(String userId, Map<String, dynamic> rows) => _store.setJson(syncRowsKey(userId), rows);

  @override
  Future<void> remove(String userId) => _store.remove(syncRowsKey(userId));
}

/// This platform's store: a file per player on the iPhone ([platform.FileSyncRows]), SharedPreferences
/// (localStorage) on the web.
Future<SyncRows> openSyncRows(LocalStore store) => platform.openSyncRows(store);
