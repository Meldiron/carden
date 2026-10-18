import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'app.dart';
import 'core/platform.dart';
import 'core/sfx.dart';
import 'data/local_store.dart';
import 'data/sync/device_copy.dart';
import 'state/settings.dart';
import 'state/sync.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (isWeb) {
    // Path URLs (`/play/<id>`, `/auth/callback`) instead of `/#/play/<id>`,
    // so deep links and the Appwrite OAuth redirect resolve as plain routes.
    usePathUrlStrategy();
  } else {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(statusBarColor: Colors.transparent));
  }
  final store = await LocalStore.open();
  // The save sync's copy of the rows: a file per player on the iPhone, never NSUserDefaults (4 MB).
  final syncRows = await openSyncRows(store);
  Sfx.instance.init();
  runApp(
    ProviderScope(
      overrides: [localStoreProvider.overrideWithValue(store), syncRowsProvider.overrideWithValue(syncRows)],
      child: const CardenApp(),
    ),
  );
}
