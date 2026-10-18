import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/analytics.dart';
import '../../core/platform.dart';
import '../../core/qa.dart';
import '../../core/reminders.dart';
import '../../core/theme/tokens.dart';
import '../../data/local_store.dart';
import '../../router.dart';
import '../../state/first_steps.dart';
import '../../state/push.dart';
import '../../state/reminders.dart';
import '../../state/settings.dart';
import '../../state/unlocks.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';

/// The one notification question (owner, 2026-10-18; docs/notifications.md): after the player's
/// second finished picture, at a calm moment, a sheet in the game's style asks first, with a
/// switch for every kind of notification (all on), Allow and Not now. Allow writes the switches to
/// the settings Settings uses and then shows iOS's own prompt; Not now changes nothing. Asked once
/// per device; never on the web, in QA runs (unless a suite asks for it) or once iOS has answered.
/// It replaced the reminder question after a daily gift and the gift question after a first friend
/// or gift, so a player gets one question.
class NotificationPrompt {
  NotificationPrompt._();

  /// Pictures finished before it is asked. The second, not the third: nothing else happens then (the
  /// third opens the Library and Quick play), and players who leave early mostly do so after a board
  /// or two, so the second reaches more of them while they have played one picture they chose.
  static const afterPictures = 2;

  /// The answer, kept on the device (`allowed`, `declined`, or `decided` when iOS had already
  /// answered); without one it may still be asked.
  static const storeKey = 'notificationPrompt';

  /// Integration suites run as QA players, where the question stays out of the way; a suite that
  /// checks it turns this on.
  static bool allowInQaRuns = false;

  /// The questions earlier builds asked (the reminder question after a daily gift, the gift
  /// question after a first friend or gift): a player who answered one has been asked.
  static bool askedBefore(LocalStore store) => store.reminderOfferShown || store.getText('giftNotificationsOffer') == 'shown';

  /// Whether to ask now, leaving the calm moment to the host.
  static bool due({
    required bool supported,
    required bool qaRun,
    required String? decision,
    required bool askedBefore,
    required int finished,
    required ReminderPermission permission,
  }) =>
      supported && !qaRun && decision == null && !askedBefore && finished >= afterPictures && permission == ReminderPermission.notDetermined;

  /// Allow: the switches go where Settings keeps them, then iOS asks (the real prompt). With every
  /// switch off nothing is asked. Returns whether iOS allows notifications now.
  static Future<bool> allow(ProviderContainer c, NotificationChoices choices) async {
    final decision = c.read(notificationPromptProvider.notifier);
    if (!choices.any) {
      decision.set('declined');
      AppAnalytics.event('notification_prompt_declined', {'allOff': true});
      return false;
    }
    decision.set('allowed');
    final reminders = c.read(remindersProvider);
    final push = c.read(pushRegistrationProvider);
    c.read(settingsProvider.notifier).setReminders(choices.daily);
    c.read(eventRemindersProvider.notifier).set(choices.events);
    c.read(giftNotificationsProvider.notifier).set(choices.gifts);
    c.read(messageNotificationsProvider.notifier).set(choices.messages);
    final granted = await NotificationPermission.ask(from: 'prompt');
    c.invalidate(notificationsAllowedProvider);
    AppAnalytics.event('notification_prompt_allowed', {...choices.toProps(), 'granted': granted});
    if (granted) {
      // Again after the answer: the app came back to the front from iOS's prompt meanwhile, and its
      // resume may have planned the reminders before the permission was there.
      await reminders.apply(daily: choices.daily, events: choices.events);
      await push.apply(gifts: choices.gifts, messages: choices.messages);
    } else {
      // iOS said no: the reminder switches follow, as when it is turned off in iOS Settings.
      await reminders.refresh();
    }
    return granted;
  }

  /// Not now: no switch changes and iOS is not asked.
  static void decline(ProviderContainer c) {
    c.read(notificationPromptProvider.notifier).set('declined');
    AppAnalytics.event('notification_prompt_declined', {'allOff': false});
  }
}

/// The kinds the question offers, as the player left the switches.
@immutable
class NotificationChoices {
  const NotificationChoices({this.daily = true, this.events = true, this.gifts = true, this.messages = true});
  final bool daily, events, gifts, messages;

  bool get any => daily || events || gifts || messages;

  NotificationChoices copyWith({bool? daily, bool? events, bool? gifts, bool? messages}) =>
      NotificationChoices(daily: daily ?? this.daily, events: events ?? this.events, gifts: gifts ?? this.gifts, messages: messages ?? this.messages);

  Map<String, Object> toProps() => {'daily': daily, 'events': events, 'gifts': gifts, 'messages': messages};
}

/// The question's answer on this device ([NotificationPrompt.storeKey]); null until answered.
class NotificationPromptDecision extends Notifier<String?> {
  @override
  String? build() => ref.watch(localStoreProvider).getText(NotificationPrompt.storeKey);

  void set(String value) {
    ref.read(localStoreProvider).setText(NotificationPrompt.storeKey, value);
    state = value;
  }
}

final notificationPromptProvider = NotifierProvider<NotificationPromptDecision, String?>(NotificationPromptDecision.new);

/// One kind of notification: the row Settings shows for it, in the same words.
class NotificationKind {
  const NotificationKind(this.icon, this.label, this.subtitle);
  final IconData icon;
  final String label;
  final String subtitle;

  static const daily = NotificationKind(AppIcons.bell, 'Daily reminders', 'One a day with the daily puzzle');
  static const events = NotificationKind(AppIcons.flag, 'New events', 'The evening before an event opens');
  static const gifts = NotificationKind(AppIcons.gift, 'Gifts from friends', 'When a friend sends you a gift');
  static const messages = NotificationKind(AppIcons.envelope, 'Messages from Carden', 'News, gifts and offers in your inbox');
}

/// Shows the question and carries out the answer. A toast confirms when notifications are on.
Future<void> showNotificationPrompt(BuildContext context) async {
  final container = ProviderScope.containerOf(context, listen: false);
  AppAnalytics.event('notification_prompt_shown', {'pictures': container.read(solvedCountProvider)});
  final choices = await showAppSheet<NotificationChoices>(context, dismissible: false, builder: (_) => const NotificationPromptSheet());
  if (choices == null) {
    NotificationPrompt.decline(container);
    return;
  }
  final granted = await NotificationPrompt.allow(container, choices);
  if (granted && context.mounted) showToast(context, 'Notifications on', icon: AppIcons.bellFill);
}

/// The question: a bell, a title and one line, a switch for each kind (all on), Allow and Not now.
class NotificationPromptSheet extends StatefulWidget {
  const NotificationPromptSheet({super.key});

  @override
  State<NotificationPromptSheet> createState() => _NotificationPromptSheetState();
}

class _NotificationPromptSheetState extends State<NotificationPromptSheet> {
  var _choices = const NotificationChoices();

  /// The buttons answer only once the sheet is in place: a tap meant for the page below while it
  /// slides in must not answer the question.
  bool get _settled => ModalRoute.of(context)?.animation?.status != AnimationStatus.forward;

  void _answer(NotificationChoices? choices) {
    if (_settled) Navigator.pop(context, choices);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget row(NotificationKind kind, bool value, NotificationChoices Function(bool v) change, String key) => _KindRow(
          key: ValueKey('notification-prompt-$key'),
          kind: kind,
          value: value,
          onChanged: (v) => setState(() => _choices = change(v)),
        );
    return Padding(
      key: const ValueKey('notification-prompt'),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: c.accentTint, shape: BoxShape.circle),
            child: Icon(AppIcons.bellFill, size: 26, color: context.accent),
          ),
          const SizedBox(height: 14),
          const SizedBox(
            width: double.infinity,
            child: SheetHeader(title: 'Turn on notifications?', subtitle: 'Choose what Carden may send you. You can change it any time in Settings.', center: true),
          ),
          const SizedBox(height: 16),
          SoftCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                row(NotificationKind.daily, _choices.daily, (v) => _choices.copyWith(daily: v), 'daily'),
                Divider(height: 1, color: c.stroke, indent: _KindRow.textInset),
                row(NotificationKind.events, _choices.events, (v) => _choices.copyWith(events: v), 'events'),
                Divider(height: 1, color: c.stroke, indent: _KindRow.textInset),
                row(NotificationKind.gifts, _choices.gifts, (v) => _choices.copyWith(gifts: v), 'gifts'),
                Divider(height: 1, color: c.stroke, indent: _KindRow.textInset),
                row(NotificationKind.messages, _choices.messages, (v) => _choices.copyWith(messages: v), 'messages'),
              ],
            ),
          ),
          const SizedBox(height: 20),
          BigButton(key: const ValueKey('notification-prompt-allow'), label: 'Allow', onTap: () => _answer(_choices)),
          const SizedBox(height: 4),
          // The way out is a plain text button, as on iOS sheets (the unlock intro's Later).
          Pressable(
            key: const ValueKey('notification-prompt-not-now'),
            onTap: () => _answer(null),
            child: SizedBox(
              height: 44,
              width: double.infinity,
              child: Center(child: Text('Not now', style: TextStyle(fontSize: TypeSize.callout, fontWeight: FontWeight.w600, color: c.textSecondary))),
            ),
          ),
        ],
      ),
    );
  }
}

/// A kind with its switch, laid out as a Settings row (icon column, label, one line under it).
class _KindRow extends StatelessWidget {
  const _KindRow({super.key, required this.kind, required this.value, required this.onChanged});
  final NotificationKind kind;
  final bool value;
  final ValueChanged<bool> onChanged;

  static const textInset = 14.0 + 22 + 12;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return MergeSemantics(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
          child: Row(
            children: [
              SizedBox(width: 22, child: Icon(kind.icon, size: 20, color: context.accent)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(kind.label, style: TextStyle(fontWeight: FontWeight.w600, fontSize: TypeSize.body, color: c.textPrimary)),
                    Text(kind.subtitle, style: TextStyle(fontSize: TypeSize.footnote, color: c.textSecondary)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              CupertinoSwitch(value: value, activeTrackColor: context.highContrast ? c.success : Brand.success, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows the question once it is due, at a calm moment: the player is on a tab's own page (Home,
/// Library, Quests, Social, Profile) with nothing above it (no sheet, alert or pushed page, no
/// unlock intro waiting), the game has been in front for a few seconds and stayed calm for
/// [calmLooks] looks in a row (at least 4 s), so the finish card, a celebration or another host's
/// alert always goes first, and a player who is still tapping their way somewhere is not
/// interrupted.
/// A moment that is not calm waits for the next one. Looks only while the question may be due.
class NotificationPromptHost extends ConsumerStatefulWidget {
  const NotificationPromptHost({super.key, required this.child});
  final Widget child;

  /// How often it looks while the question is due.
  static Duration tick = const Duration(seconds: 2);

  /// How long the game must have been in front first (a launch or a return from the background).
  static Duration settle = const Duration(seconds: 5);

  /// Calm looks in a row before it shows ([tick] apart).
  static const calmLooks = 3;

  /// What the last look saw (for QA logs).
  static String debugLastLook = '';

  /// The pages it may show over: the tabs' own pages.
  static const calmPaths = {'/home', '/library', '/events', '/social', '/profile'};

  /// Whether [path] (the top location, pushes included) is a tab's own page.
  static bool calmPath(String? path) => path != null && calmPaths.contains(path);

  /// Whether the app is at a calm moment: [path] is the top location (pushes included), [top] the
  /// root navigator's top route.
  static bool calmAt({required String? path, required Route<dynamic>? top, required bool introPending, required bool onboarded}) {
    if (!onboarded || introPending || !calmPath(path)) return false;
    if (top == null || top is PopupRoute || top.settings is! Page || !top.isCurrent) return false;
    final status = top is TransitionRoute ? top.animation?.status : null;
    return status == null || status == AnimationStatus.completed;
  }

  @override
  ConsumerState<NotificationPromptHost> createState() => _NotificationPromptHostState();
}

class _NotificationPromptHostState extends ConsumerState<NotificationPromptHost> with WidgetsBindingObserver {
  Timer? _timer;
  bool _showing = false;
  int _calmLooks = 0;
  DateTime _inFrontSince = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _inFrontSince = DateTime.now();
    _calmLooks = 0;
  }

  /// Everything but the permission and the moment (read when it looks).
  bool get _mayBeDue {
    if (!supportsNotifications || !ref.read(platformCapsProvider).notifications) return false;
    if (QaRun.enabled && !NotificationPrompt.allowInQaRuns) return false;
    return ref.read(notificationPromptProvider) == null &&
        !NotificationPrompt.askedBefore(ref.read(localStoreProvider)) &&
        ref.read(solvedCountProvider) >= NotificationPrompt.afterPictures;
  }

  void _update() {
    final due = _mayBeDue;
    if (due && _timer == null) {
      _timer = Timer.periodic(NotificationPromptHost.tick, (_) => _look());
    } else if (!due && _timer != null) {
      _timer!.cancel();
      _timer = null;
      _calmLooks = 0;
    }
  }

  bool _calmNow() {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
      NotificationPromptHost.debugLastLook = 'not in front: $lifecycle';
      return false;
    }
    if (DateTime.now().difference(_inFrontSince) < NotificationPromptHost.settle) {
      NotificationPromptHost.debugLastLook = 'in front for less than ${NotificationPromptHost.settle.inSeconds} s';
      return false;
    }
    final router = ref.read(routerProvider);
    final path = router.routerDelegate.currentConfiguration.isEmpty ? null : router.state.uri.path;
    final navigator = rootNavigatorKey.currentState;
    Route<dynamic>? top;
    // The top route, without popping anything (the predicate stops at the first one).
    navigator?.popUntil((route) {
      top = route;
      return true;
    });
    final introPending = ref.read(pendingUnlockIntroProvider) != null;
    final calm = NotificationPromptHost.calmAt(path: path, top: top, introPending: introPending, onboarded: ref.read(settingsProvider).onboarded);
    NotificationPromptHost.debugLastLook = 'calm $calm: path $path, top ${top.runtimeType} (${top?.settings.runtimeType}, current ${top?.isCurrent}), intro $introPending';
    return calm;
  }

  Future<void> _look() async {
    if (_showing || !mounted) return;
    if (!_mayBeDue) {
      NotificationPromptHost.debugLastLook = 'not due';
      return _update();
    }
    if (!_calmNow()) {
      _calmLooks = 0;
      return;
    }
    if (++_calmLooks < NotificationPromptHost.calmLooks) return;
    _calmLooks = 0;
    _showing = true;
    try {
      final permission = await ReminderChannel.status();
      if (!mounted) return;
      if (permission != ReminderPermission.notDetermined) {
        // iOS has answered (Settings, an earlier build): nothing to ask, the switches stay as they are.
        ref.read(notificationPromptProvider.notifier).set('decided');
        return;
      }
      final ctx = rootNavigatorKey.currentContext;
      if (ctx == null || !ctx.mounted || !_calmNow()) return;
      await showNotificationPrompt(ctx);
    } finally {
      _showing = false;
      if (mounted) _update();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Looks again whenever a picture is finished or the answer changes.
    ref.watch(solvedCountProvider);
    ref.watch(notificationPromptProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _update();
    });
    return widget.child;
  }
}
