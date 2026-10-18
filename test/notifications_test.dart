// The notification question (docs/notifications.md; owner, 2026-10-18): asked once, after the second
// finished picture, at a calm moment, never on the web, in QA runs or once iOS has answered; every
// switch starts on; Allow writes them where Settings keeps them and then shows iOS's real prompt
// (nothing when every switch is off); Not now changes nothing. Settings > Messages from Carden.
import 'dart:io' show Directory;

import 'package:appwrite/appwrite.dart';
import 'package:carden/core/platform.dart';
import 'package:carden/core/reminders.dart';
import 'package:carden/core/theme/app_theme.dart';
import 'package:carden/data/local_store.dart';
import 'package:carden/data/purchases.dart';
import 'package:carden/features/notifications/notification_prompt.dart';
import 'package:carden/features/profile/settings_screen.dart';
import 'package:carden/models/models.dart';
import 'package:carden/router.dart';
import 'package:carden/state/auth.dart';
import 'package:carden/state/first_steps.dart';
import 'package:carden/state/profile.dart';
import 'package:carden/state/purchases.dart';
import 'package:carden/state/push.dart';
import 'package:carden/state/reminders.dart';
import 'package:carden/state/settings.dart';
import 'package:carden/state/unlocks.dart';
import 'package:carden/widgets/ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _ios = TargetPlatformVariant.only(TargetPlatform.iOS);

/// iOS's answer as the native side gives it, and every request it got (`quiet` or the real prompt).
class _Permission {
  String status = 'notDetermined';
  bool answer = true;
  final requests = <bool>[];

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('cjw/reminders'), (call) async {
      switch (call.method) {
        case 'status':
          return status;
        case 'request':
          requests.add((call.arguments as Map)['quiet'] == true);
          status = answer ? 'granted' : 'denied';
          return answer;
      }
      return null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('cjw/push'), (call) async => null);
  }
}

class _Reminders extends RemindersController {
  _Reminders(super.ref);
  final calls = <String>[];
  @override
  Future<void> apply({required bool daily, required bool events}) async => calls.add('apply daily:$daily events:$events');
  @override
  Future<void> refresh() async => calls.add('refresh');
}

class _Push extends PushRegistration {
  _Push(this._r) : super(_r);
  final Ref _r;
  final calls = <String>[];
  @override
  Future<void> apply({required bool gifts, required bool messages}) async => calls.add('apply gifts:$gifts messages:$messages');
  @override
  Future<bool> setMessages(bool on) async {
    calls.add('messages $on');
    _r.read(messageNotificationsProvider.notifier).set(on);
    return true;
  }

  @override
  Future<void> refresh() async {}
}

class _Guest extends ProfileNotifier {
  @override
  Future<Profile> build() async => Profile.guest('local');
}

class _NoStore extends PurchaseService {
  _NoStore() : super(Client());
  @override
  Future<void> start() async {}
  @override
  Future<bool> isAvailable() async => false;
  @override
  Future<Map<String, ProductDetails>> queryProducts() async => const {};
}

/// An iPhone 17 Pro's screen (393 x 852 points).
void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1179, 2556);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The Appwrite IO client asks path_provider for its cookie jar folder.
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async => Directory.systemTemp.createTempSync('cjw-test').path,
  );

  group('when it is asked', () {
    bool due({bool supported = true, bool qaRun = false, String? decision, bool askedBefore = false, int finished = 2, ReminderPermission permission = ReminderPermission.notDetermined}) =>
        NotificationPrompt.due(supported: supported, qaRun: qaRun, decision: decision, askedBefore: askedBefore, finished: finished, permission: permission);

    test('after the second finished picture, once', () {
      expect(NotificationPrompt.afterPictures, 2);
      expect(due(finished: 1), isFalse);
      expect(due(finished: 2), isTrue);
      expect(due(finished: 40), isTrue, reason: 'a player from before is asked at the next calm moment');
      for (final d in ['allowed', 'declined', 'decided']) {
        expect(due(decision: d), isFalse, reason: d);
      }
    });

    test('never on the web, in QA runs, after an earlier question or once iOS has answered', () {
      expect(due(supported: false), isFalse);
      expect(due(qaRun: true), isFalse);
      expect(due(askedBefore: true), isFalse);
      expect(due(permission: ReminderPermission.granted), isFalse);
      expect(due(permission: ReminderPermission.denied), isFalse);
    });

    test('a player who answered a question of an earlier build has been asked', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await LocalStore.open();
      expect(NotificationPrompt.askedBefore(store), isFalse);
      store.reminderOfferShown = true;
      expect(NotificationPrompt.askedBefore(store), isTrue);
      SharedPreferences.setMockInitialValues({'giftNotificationsOffer': 'shown'});
      expect(NotificationPrompt.askedBefore(await LocalStore.open()), isTrue);
    });

    test('only on a tab\'s own page (the host also needs nothing above it, below)', () {
      for (final path in ['/home', '/library', '/events', '/social', '/profile']) {
        expect(NotificationPromptHost.calmPath(path), isTrue, reason: path);
      }
      for (final path in ['/game/abc/4x4', '/play/abc', '/store', '/wheel', '/welcome', '/profile/settings', '/library/pack/p', '/player/u', null]) {
        expect(NotificationPromptHost.calmPath(path), isFalse, reason: path);
      }
      final popup = RawDialogRoute<void>(pageBuilder: (_, _, _) => const SizedBox());
      expect(NotificationPromptHost.calmAt(path: '/home', top: popup, introPending: false, onboarded: true), isFalse, reason: 'a sheet, alert or menu');
      expect(NotificationPromptHost.calmAt(path: '/home', top: null, introPending: false, onboarded: true), isFalse);
    });
  });

  group('the question', () {
    late _Permission permission;
    late _Reminders reminders;
    late _Push push;

    Future<ProviderContainer> pump(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({'onboarded': true});
      _phone(tester);
      final store = await LocalStore.open();
      permission = _Permission()..install();
      late BuildContext ctx;
      await tester.pumpWidget(ProviderScope(
        overrides: [
          localStoreProvider.overrideWithValue(store),
          platformCapsProvider.overrideWithValue(PlatformCaps.ios),
          remindersProvider.overrideWith((ref) => reminders = _Reminders(ref)),
          pushRegistrationProvider.overrideWith((ref) => push = _Push(ref)),
          solvedCountProvider.overrideWithValue(2),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Builder(builder: (c) {
            ctx = c;
            return Scaffold(body: Center(child: TextButton(onPressed: () => showNotificationPrompt(c), child: const Text('ask'))));
          }),
        ),
      ));
      final c = ProviderScope.containerOf(ctx);
      c.read(remindersProvider);
      c.read(pushRegistrationProvider);
      await tester.tap(find.text('ask'));
      await tester.pumpAndSettle();
      return c;
    }

    bool switchOf(WidgetTester tester, String kind) =>
        tester.widget<CupertinoSwitch>(find.descendant(of: find.byKey(ValueKey('notification-prompt-$kind')), matching: find.byType(CupertinoSwitch))).value;

    testWidgets('a switch for every kind, in the words Settings uses, all on', (tester) async {
      await pump(tester);
      expect(find.text('Turn on notifications?'), findsOneWidget);
      for (final (key, kind) in [('daily', NotificationKind.daily), ('events', NotificationKind.events), ('gifts', NotificationKind.gifts), ('messages', NotificationKind.messages)]) {
        expect(find.text(kind.label), findsOneWidget);
        expect(find.text(kind.subtitle), findsOneWidget);
        expect(switchOf(tester, key), isTrue, reason: '${kind.label} starts on');
      }
      // The promotional kinds are named plainly, so Allow with them on is the player's yes.
      expect(NotificationKind.events.subtitle, 'The evening before an event opens');
      expect(NotificationKind.messages.subtitle, contains('offers'));
      expect(find.text('Allow'), findsOneWidget);
      expect(find.text('Not now'), findsOneWidget);
    }, variant: _ios);

    testWidgets('Allow: the switches as left, then the real iOS prompt', (tester) async {
      final c = await pump(tester);
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('notification-prompt-messages')), matching: find.byType(CupertinoSwitch)));
      await tester.pumpAndSettle();
      expect(switchOf(tester, 'messages'), isFalse);
      await tester.tap(find.text('Allow'));
      await tester.pumpAndSettle();
      expect(permission.requests, [false], reason: 'the real prompt, not the quiet (provisional) one');
      expect(c.read(settingsProvider).reminders, isTrue);
      expect(c.read(eventRemindersProvider), isTrue);
      expect(c.read(giftNotificationsProvider), isTrue);
      expect(c.read(messageNotificationsProvider), isFalse);
      expect(reminders.calls, ['apply daily:true events:true']);
      expect(push.calls, ['apply gifts:true messages:false']);
      expect(c.read(notificationPromptProvider), 'allowed');
      expect(find.text('Notifications on'), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
    }, variant: _ios);

    testWidgets('Allow when iOS says no: the reminders follow iOS', (tester) async {
      final c = await pump(tester);
      permission.answer = false;
      await tester.tap(find.text('Allow'));
      await tester.pumpAndSettle();
      expect(permission.requests, [false]);
      expect(reminders.calls, ['refresh']);
      expect(push.calls, isEmpty);
      expect(c.read(notificationPromptProvider), 'allowed', reason: 'answered: never asked again');
    }, variant: _ios);

    testWidgets('every switch off: Allow asks iOS nothing', (tester) async {
      final c = await pump(tester);
      for (final kind in ['daily', 'events', 'gifts', 'messages']) {
        await tester.tap(find.descendant(of: find.byKey(ValueKey('notification-prompt-$kind')), matching: find.byType(CupertinoSwitch)));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Allow'));
      await tester.pumpAndSettle();
      expect(permission.requests, isEmpty);
      expect(reminders.calls, isEmpty);
      expect(push.calls, isEmpty);
      expect(c.read(notificationPromptProvider), 'declined');
    }, variant: _ios);

    testWidgets('Not now: no switch changes and iOS is not asked', (tester) async {
      final c = await pump(tester);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(find.text('Turn on notifications?'), findsNothing);
      expect(permission.requests, isEmpty);
      expect(c.read(settingsProvider).reminders, isFalse);
      expect(c.read(eventRemindersProvider), isFalse);
      expect(c.read(messageNotificationsProvider), isFalse);
      expect(c.read(giftNotificationsProvider), isTrue, reason: 'as before the question');
      expect(c.read(notificationPromptProvider), 'declined');
    }, variant: _ios);
  });

  group('the host', () {
    late _Permission permission;
    late GoRouter router;

    setUp(() {
      NotificationPromptHost.tick = const Duration(milliseconds: 200);
      NotificationPromptHost.settle = Duration.zero;
    });
    tearDown(() {
      NotificationPromptHost.tick = const Duration(seconds: 2);
      NotificationPromptHost.settle = const Duration(seconds: 5);
    });

    Future<ProviderContainer> pump(WidgetTester tester, {int solved = 2, String start = '/home', Map<String, Object> prefs = const {}}) async {
      _Solved.initial = solved;
      _phone(tester);
      SharedPreferences.setMockInitialValues({'onboarded': true, ...prefs});
      final store = await LocalStore.open();
      permission = _Permission()..install();
      router = GoRouter(navigatorKey: rootNavigatorKey, initialLocation: start, routes: [
        GoRoute(path: '/home', builder: (_, _) => const Scaffold(body: Center(child: Text('Home')))),
        GoRoute(path: '/game/:id', builder: (_, _) => const Scaffold(body: Center(child: Text('Game')))),
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          localStoreProvider.overrideWithValue(store),
          platformCapsProvider.overrideWithValue(PlatformCaps.ios),
          routerProvider.overrideWithValue(router),
          solvedCountProvider.overrideWith((ref) => ref.watch(_solved)),
          pendingUnlockIntroProvider.overrideWithValue(null),
          remindersProvider.overrideWith((ref) => _Reminders(ref)),
          pushRegistrationProvider.overrideWith((ref) => _Push(ref)),
        ],
        child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router, builder: (c, child) => NotificationPromptHost(child: child!)),
      ));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      return ProviderScope.containerOf(tester.element(find.byType(NotificationPromptHost)));
    }

    Future<void> wait(WidgetTester tester) async {
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      await tester.pumpAndSettle();
    }

    final question = find.text('Turn on notifications?');

    testWidgets('shows on Home after the second picture, and never again once answered', (tester) async {
      final c = await pump(tester);
      await wait(tester);
      expect(question, findsOneWidget);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      await wait(tester);
      expect(question, findsNothing);
      expect(c.read(notificationPromptProvider), 'declined');
    }, variant: _ios);

    testWidgets('waits for the second picture', (tester) async {
      await pump(tester, solved: 1);
      await wait(tester);
      expect(question, findsNothing);
    }, variant: _ios);

    testWidgets('never over a game: it waits until the player is back on Home', (tester) async {
      await pump(tester, start: '/game/abc');
      await wait(tester);
      expect(question, findsNothing);
      router.go('/home');
      await tester.pumpAndSettle();
      await wait(tester);
      expect(question, findsOneWidget);
    }, variant: _ios);

    testWidgets('never over another sheet or alert: it waits until that closes', (tester) async {
      final c = await pump(tester, solved: 1);
      final ctx = rootNavigatorKey.currentContext!;
      final alert = showAppAlert(ctx, title: 'Synced from another device', confirmLabel: 'Keep playing', cancelLabel: null);
      await tester.pumpAndSettle();
      // The second picture is counted while the alert is up (a save from another device).
      c.read(_solved.notifier).set(2);
      await wait(tester);
      expect(question, findsNothing);
      await tester.tap(find.text('Keep playing'));
      await alert;
      await tester.pumpAndSettle();
      await wait(tester);
      expect(question, findsOneWidget);
    }, variant: _ios);

    testWidgets('iOS has already answered: nothing is asked, and it is not looked at again', (tester) async {
      final c = await pump(tester);
      permission.status = 'granted';
      await wait(tester);
      expect(question, findsNothing);
      expect(c.read(notificationPromptProvider), 'decided');
    }, variant: _ios);

    testWidgets('a player who answered an earlier build\'s question is not asked again', (tester) async {
      await pump(tester, prefs: const {'reminderOfferShown': true});
      await wait(tester);
      expect(question, findsNothing);
    }, variant: _ios);
  });

  group('Settings', () {
    testWidgets('Messages from Carden: off until the player turns it on', (tester) async {
      SharedPreferences.setMockInitialValues({'onboarded': true});
      final store = await LocalStore.open();
      _Permission()..status = 'granted'..install();
      late _Push push;
      await tester.pumpWidget(ProviderScope(
        overrides: [
          localStoreProvider.overrideWithValue(store),
          platformCapsProvider.overrideWithValue(PlatformCaps.ios),
          profileProvider.overrideWith(_Guest.new),
          isGuestProvider.overrideWithValue(true),
          purchaseServiceProvider.overrideWith((ref) => _NoStore()),
          storeAvailableProvider.overrideWith((ref) => false),
          productsProvider.overrideWith((ref) => const <String, ProductDetails>{}),
          notificationsAllowedProvider.overrideWith((ref) async => true),
          pushRegistrationProvider.overrideWith((ref) => push = _Push(ref)),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: const SettingsScreen()),
      ));
      await tester.pumpAndSettle();
      final row = find.byKey(const ValueKey('settings-message-notifications'));
      // In the middle of the screen, clear of the glass bar at the top.
      await Scrollable.ensureVisible(tester.element(row), alignment: 0.5);
      await tester.pumpAndSettle();
      expect(find.text('Messages from Carden'), findsOneWidget);
      expect(find.text(NotificationKind.messages.subtitle), findsOneWidget);
      expect(find.text(NotificationKind.gifts.subtitle), findsOneWidget);
      final toggle = find.descendant(of: row, matching: find.byType(CupertinoSwitch));
      expect(tester.widget<CupertinoSwitch>(toggle).value, isFalse);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(push.calls, ['messages true']);
      expect(tester.widget<CupertinoSwitch>(toggle).value, isTrue);
      // New events has its own row, whatever the daily reminders are.
      expect(find.byKey(const ValueKey('settings-event-reminders')), findsOneWidget);
    }, variant: _ios);
  });
}

/// Pictures finished, changeable while the host runs.
class _Solved extends Notifier<int> {
  static int initial = 2;
  @override
  int build() => initial;
  void set(int n) => state = n;
}

final _solved = NotifierProvider<_Solved, int>(_Solved.new);
