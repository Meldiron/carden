import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/platform.dart';
import '../../core/shake.dart';
import '../../router.dart';
import '../../state/settings.dart';
import 'help.dart';

/// Settings > Help > Shake to send feedback: on until the player turns it off (stored on the device).
class ShakeFeedbackNotifier extends Notifier<bool> {
  static const _key = 'shakeFeedback';

  @override
  bool build() => ref.watch(localStoreProvider).getText(_key) != 'off';

  void set(bool on) {
    ref.read(localStoreProvider).setText(_key, on ? 'on' : 'off');
    state = on;
  }
}

final shakeFeedbackProvider = NotifierProvider<ShakeFeedbackNotifier, bool>(ShakeFeedbackNotifier.new);

/// A shake of the iPhone opens Send feedback (Settings > Help) as a sheet on the root navigator, over
/// whatever is on screen (owner, 2026-10-18). One at a time: nothing while a feedback form is open,
/// while one of the app's alerts or action sheets is up (the native side already keeps quiet under a
/// system alert or the share sheet), or while the app is not in front. Off with the Settings switch;
/// nothing on the web.
class ShakeFeedbackHost extends ConsumerStatefulWidget {
  const ShakeFeedbackHost({super.key, required this.child, this.navigatorKey});
  final Widget child;

  /// The navigator the sheet opens on (the app's root navigator; tests pass their own).
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  ConsumerState<ShakeFeedbackHost> createState() => _ShakeFeedbackHostState();
}

class _ShakeFeedbackHostState extends ConsumerState<ShakeFeedbackHost> {
  bool _listening = false;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    if (ShakeChannel.supportedOn(ref.read(platformCapsProvider))) {
      ShakeChannel.listen(_onShake);
      _listening = true;
    }
  }

  @override
  void dispose() {
    if (_listening) ShakeChannel.stop();
    super.dispose();
  }

  Future<void> _onShake() async {
    if (!mounted || _opening || FeedbackPanel.isOpen || !ref.read(shakeFeedbackProvider)) return;
    final state = WidgetsBinding.instance.lifecycleState;
    if (state != null && state != AppLifecycleState.resumed) return;
    final navigator = (widget.navigatorKey ?? rootNavigatorKey).currentState;
    if (navigator == null || !navigator.mounted) return;
    // An alert or an action sheet (showAppAlert, showAppActionSheet) waits for an answer first.
    Route<dynamic>? top;
    navigator.popUntil((route) {
      top = route;
      return true;
    });
    if (top is RawDialogRoute) return;
    _opening = true;
    try {
      await showFeedbackSheet(navigator.context, via: 'shake');
    } finally {
      _opening = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
