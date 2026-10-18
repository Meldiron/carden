import '../local_store.dart';
import 'device_copy.dart';

/// The web: the copy stays in localStorage, as before.
Future<SyncRows> openSyncRows(LocalStore store) async => PrefsSyncRows(store);
