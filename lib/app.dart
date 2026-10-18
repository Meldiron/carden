import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quick_actions/quick_actions.dart';

import 'core/a11y.dart';
import 'core/analytics.dart';
import 'core/app_links.dart';
import 'core/appwrite.dart';
import 'core/image_files.dart';
import 'core/platform.dart';
import 'core/reminders.dart';
import 'core/sfx.dart';
import 'core/theme/app_theme.dart';
import 'features/coop/coop_host.dart';
import 'features/links/deep_links.dart';
import 'features/notifications/notification_prompt.dart';
import 'features/profile/shake_feedback.dart';
import 'features/store/purchase_host.dart';
import 'features/sync/sync_host.dart';
import 'features/update/update_host.dart';
import 'router.dart';
import 'state/auth.dart';
import 'state/catalog.dart';
import 'state/inbox.dart';
import 'state/purchases.dart';
import 'state/push.dart';
import 'state/reminders.dart';
import 'state/settings.dart';
import 'state/sync.dart';
import 'widgets/icons.dart';
import 'widgets/ui.dart';

class CardenApp extends ConsumerStatefulWidget {
  const CardenApp({super.key});

  @override
  ConsumerState<CardenApp> createState() => _CardenAppState();
}

class _CardenAppState extends ConsumerState<CardenApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    // Usage analytics on the app's Appwrite client, first (the settings bring the player's Share
    // usage data switch): the router gives its navigators observers only once analytics is
    // attached (lib/core/analytics.dart).
    ref.read(settingsProvider);
    AppAnalytics.attach(ref.read(appwriteClientProvider));
    WidgetsBinding.instance.addObserver(this);
    ImageFiles.attach(ref.read(storageProvider));
    if (supportsQuickActions) _setUpQuickActions();
    if (supportsNotifications) {
      _setUpReminders();
      _setUpPush();
    }
    // Apple: listen for transactions as soon as the app starts, so a purchase paid while the app
    // was closed, restarted or on another screen is added now. After the sign-in: the check needs
    // the session.
    if (supportsPurchases) _startPurchases();
  }

  Future<void> _startPurchases() async {
    try {
      await ref.read(authProvider.future);
    } catch (_) {}
    if (mounted) await ref.read(purchaseFlowProvider.notifier).start();
  }

  /// Home Screen long-press menu: "One last game?" opens a playable puzzle.
  /// Never called on web: the plugin has no implementation there.
  Future<void> _setUpQuickActions() async {
    const actions = QuickActions();
    await actions.initialize((type) async {
      if (type != 'one_last_game') return;
      if (!ref.read(settingsProvider).onboarded) ref.read(settingsProvider.notifier).setOnboarded();
      try {
        await ref.read(allPuzzlesProvider.future);
        await ref.read(packsProvider.future);
      } catch (_) {}
      final daily = ref.read(dailyPuzzleProvider);
      final puzzle = daily ?? pickRandomPlayable(ref);
      if (puzzle == null || !mounted) return;
      AppAnalytics.event('shortcut_opened', {'daily': daily != null});
      ref.read(routerProvider).push('/play/${puzzle.id}');
    });
    // The shortcut itself is declared statically in Info.plist
    // (UIApplicationShortcutItems) so it uses an SF Symbol and shows once.
  }

  /// A tapped daily reminder opens its daily puzzle (or Home); the week of
  /// reminders is planned again from the current state.
  void _setUpReminders() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ReminderChannel.listen((route) {
        if (!mounted) return;
        AppAnalytics.event('reminder_opened', {'daily': route.startsWith('/play/')});
        final router = ref.read(routerProvider);
        if (route.startsWith('/play/')) {
          router.push(route);
        } else {
          router.go(route);
        }
      });
      ref.read(remindersProvider).refresh();
    });
  }

  /// Gift notifications and messages from Carden (docs/notifications.md): this iPhone's token
  /// becomes a push target of the player once notifications are allowed; a tapped notification
  /// opens its message in the inbox, and one that arrives while the game is open refreshes the
  /// inbox and shows a toast instead of a banner. After the sign-in: the target belongs to the
  /// session.
  void _setUpPush() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await ref.read(authProvider.future);
      } catch (_) {}
      if (!mounted) return;
      await ref.read(pushRegistrationProvider).start(
        onOpen: (link) {
          AppAnalytics.event('push_opened', {'kind': pushKindOf(link)});
          final parsed = AppLink.parse(Uri.parse(link));
          if (mounted && parsed != null) ref.read(deepLinksProvider).show(parsed);
        },
        onReceive: (note) {
          if (!mounted) return;
          ref.invalidate(inboxMessagesProvider);
          final ctx = rootNavigatorKey.currentContext;
          if (ctx != null && ctx.mounted && note.title.isNotEmpty) showToast(ctx, note.title, icon: pushKindOf(note.link) == 'message' ? AppIcons.envelope : AppIcons.gift);
        },
      );
    });
  }

  /// Links opened from outside the app on iPhone (the `carden://` scheme, universal links to
  /// the web site, the widget) reach this observer before the router's: [DeepLinks] shows them,
  /// with Home beneath a sheet or a page that opens above the tabs. Other schemes (the Appwrite
  /// sign-in redirect) go on to the router. On the web the link is the address the visit starts
  /// on (`routerProvider`), and browser back and forward stay with the router.
  @override
  Future<bool> didPushRouteInformation(RouteInformation routeInformation) async {
    if (isWeb) return false;
    final link = AppLink.parse(routeInformation.uri);
    if (link == null) return false;
    DeepLinks.reportOpened(link);
    ref.read(deepLinksProvider).show(link);
    return true;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // On the web, resumed and inactive also follow the tab's focus.
    if (state == AppLifecycleState.resumed) {
      if (ref.read(settingsProvider).music) Sfx.instance.startMusic();
      ref.read(syncProvider.notifier).onResume();
      // New messages in the inbox (Social > Inbox and the tab's dot).
      ref.invalidate(inboxMessagesProvider);
      if (supportsPurchases) ref.read(purchaseFlowProvider.notifier).onResume();
      // Picks up a permission change made in iOS Settings.
      if (supportsNotifications) {
        ref.read(remindersProvider).refresh();
        ref.read(pushRegistrationProvider).refresh();
        ref.invalidate(notificationsAllowedProvider);
      }
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive || state == AppLifecycleState.hidden) {
      Sfx.instance.stopMusic();
      ref.read(syncProvider.notifier).onPause();
      // Leaving the game: plan reminders from today's state (gift, daily puzzle).
      if (supportsNotifications && state == AppLifecycleState.paused) ref.read(remindersProvider).refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    // Watched for the app's life, so it follows sign-ins (a provider nobody listens to is paused).
    if (supportsNotifications) ref.watch(pushRegistrationProvider);
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Carden',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: appMessengerKey,
      theme: AppTheme.light(highContrast: settings.accessibility.increaseContrast),
      darkTheme: AppTheme.dark(highContrast: settings.accessibility.increaseContrast),
      themeMode: settings.themeMode,
      routerConfig: router,
      builder: (context, child) {
        // Keep the UI readable on large accessibility font sizes.
        final mq = MediaQuery.of(context);
        // Toast host: a Scaffold above the Navigator shows the root
        // messenger's snack bars over every route, sheet and the tab bar.
        // Page Scaffolds register with the inner messenger instead, so a
        // toast is drawn once.
        final host = Scaffold(
          resizeToAvoidBottomInset: false,
          backgroundColor: Colors.transparent,
          body: ScaffoldMessenger(child: UpdateHost(child: SyncHost(child: PurchaseHost(child: CoopHost(child: NotificationPromptHost(child: ShakeFeedbackHost(child: child!))))))),
        );
        // Text follows the system size up to iOS "xxxLarge" (1.35), unless Settings > Accessibility
        // picks Large (150%) or Largest (200%); bars cap themselves at 1.2 (ChromeText).
        // Wider windows (the web on a tablet or desktop) get their own layouts, see widgets/adaptive.dart.
        final a11y = settings.accessibility;
        final size = a11y.textSize.scale;
        final data = mq.copyWith(
          textScaler: size == null ? mq.textScaler.clamp(minScaleFactor: 0.9, maxScaleFactor: 1.35) : TextScaler.linear(size),
          // Flutter's own widgets follow these too; the app's changes read the settings (A11y).
          disableAnimations: mq.disableAnimations || a11y.reduceMotion,
          highContrast: mq.highContrast || a11y.increaseContrast,
          onOffSwitchLabels: mq.onOffSwitchLabels || a11y.differentiateWithoutColour,
        );
        return A11y(prefs: a11y, child: MediaQuery(data: data, child: host));
      },
    );
  }
}
