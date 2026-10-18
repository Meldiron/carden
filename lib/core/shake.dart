import 'package:flutter/services.dart';

import 'platform.dart';

/// Shakes of the iPhone (owner, 2026-10-18: "shaking, no matter on what screen, opens feedback
/// form"). The native side (`ShakeToFeedback` in `ios/Runner/AppDelegate.swift`) hears UIKit's
/// shake motion and sends `shake` on channel `cjw/shake`, only while nothing native (an alert, the
/// share sheet) is presented over the game. The web and Android have no native side: nothing comes.
abstract final class ShakeChannel {
  static const channel = MethodChannel('cjw/shake');

  /// Whether this platform reports shakes: the iPhone app, where the native side lives.
  static bool supportedOn(PlatformCaps caps) => !caps.isWeb && caps.notifications;

  /// [onShake] runs on every shake until [stop].
  static void listen(VoidCallback onShake) {
    channel.setMethodCallHandler((call) async {
      if (call.method == 'shake') onShake();
    });
  }

  static void stop() => channel.setMethodCallHandler(null);
}
