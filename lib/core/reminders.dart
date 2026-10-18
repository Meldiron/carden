import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'platform.dart';
import 'qa.dart';

/// Notification permission for the app, as iOS reports it.
enum ReminderPermission { granted, denied, notDetermined }

/// Bridge to the native daily reminders (`DailyReminders` in
/// `ios/Runner/AppDelegate.swift`). Local notifications only: they are
/// scheduled on the device, nothing goes over the network. Every call is a
/// no-op where [supportsNotifications] is false (web, Android).
class ReminderChannel {
  ReminderChannel._();

  static const _channel = MethodChannel('cjw/reminders');

  static Future<ReminderPermission> status() async {
    if (!supportsNotifications) return ReminderPermission.denied;
    final s = await _call<String>('status');
    return switch (s) {
      'granted' => ReminderPermission.granted,
      'notDetermined' => ReminderPermission.notDetermined,
      _ => ReminderPermission.denied,
    };
  }

  /// Shows the iOS permission prompt the first time; later calls return the
  /// earlier answer without a prompt. [quiet] asks for provisional
  /// permission instead (no prompt; reminders go quietly to Notification
  /// Center): only integration runs use it, as nothing can tap the prompt.
  static Future<bool> request({bool quiet = false}) async {
    if (!supportsNotifications) return false;
    return await _call<bool>('request', {'quiet': quiet}) ?? false;
  }

  /// Integration runs ask quietly ([request] with `quiet`), as nothing can tap the iOS prompt. A
  /// suite that checks the real prompt (the host takes the screenshot) turns this off.
  static bool quietInIntegrationRuns = true;

  /// Whether a permission request now should be the quiet one.
  static bool get quietNow => quietInIntegrationRuns && QaRun.enabled && QaRun.integrationRun;

  /// The reminders iOS holds for later, as scheduled (for QA).
  static Future<List<Map<String, Object?>>> pending() => _list('pending');

  /// The reminders that fired and are still in Notification Center (for QA).
  static Future<List<Map<String, Object?>>> delivered() => _list('delivered');

  static Future<List<Map<String, Object?>>> _list(String method) async {
    if (!supportsNotifications) return const [];
    final rows = await _call<List<Object?>>(method) ?? const [];
    return [for (final r in rows) if (r is Map) r.cast<String, Object?>()];
  }

  /// Replaces every pending reminder with [notes] (JSON from `ReminderNote`).
  static Future<void> schedule(List<Map<String, Object?>> notes) async {
    if (!supportsNotifications) return;
    await _call<void>('schedule', notes);
  }

  static Future<void> cancel() async {
    if (!supportsNotifications) return;
    await _call<void>('cancel');
  }

  /// The app's notification page in iOS Settings.
  static Future<void> openSettings() async {
    if (!supportsNotifications) return;
    await _call<void>('openSettings');
  }

  /// Calls [onOpen] with the route of every reminder the player taps,
  /// including the one that launched the app.
  static Future<void> listen(void Function(String route) onOpen) async {
    if (!supportsNotifications) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'open' && call.arguments is String) onOpen(call.arguments as String);
    });
    final launch = await _call<String>('ready');
    if (launch != null && launch.isNotEmpty) onOpen(launch);
  }

  static Future<T?> _call<T>(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      debugPrint('reminders $method failed: $e');
      return null;
    }
  }
}
