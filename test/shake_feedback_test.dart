// Shake to send feedback (TestFlight feedback AD2vI9mqyY_OfTc3X7SyHJA, owner 2026-10-18): a shake of
// the iPhone, reported by the native side on channel `cjw/shake`, opens Send feedback over whatever
// is on screen; one at a time, not over an alert, and not when Settings turned it off. The web gets
// nothing (no listener, no Settings row).
import 'dart:io' show Directory;

import 'package:carden/core/platform.dart';
import 'package:carden/core/shake.dart';
import 'package:carden/core/theme/app_theme.dart';
import 'package:carden/data/local_store.dart';
import 'package:carden/features/profile/help.dart';
import 'package:carden/features/profile/shake_feedback.dart';
import 'package:carden/state/auth.dart';
import 'package:carden/state/settings.dart';
import 'package:carden/widgets/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async => Directory.systemTemp.createTempSync('cjw-test').path,
  );

  late LocalStore store;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = await LocalStore.open();
  });

  /// What the native side sends when the iPhone is shaken.
  Future<void> shake(WidgetTester tester) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      ShakeChannel.channel.name,
      const StandardMethodCodec().encodeMethodCall(const MethodCall('shake')),
      (_) {},
    );
    await tester.pumpAndSettle();
  }

  Future<ProviderContainer> pumpApp(WidgetTester tester, {PlatformCaps caps = PlatformCaps.ios}) async {
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        platformCapsProvider.overrideWithValue(caps),
        currentUserIdProvider.overrideWithValue('player-1'),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        navigatorKey: key,
        builder: (context, child) => ShakeFeedbackHost(navigatorKey: key, child: child!),
        home: const Scaffold(body: Center(child: Text('Home'))),
      ),
    ));
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.text('Home')));
  }

  bool feedbackOpen() => find.byType(FeedbackPanel).evaluate().isNotEmpty;

  testWidgets('a shake opens Send feedback over the screen, once', (tester) async {
    await pumpApp(tester);
    expect(feedbackOpen(), isFalse);
    await shake(tester);
    expect(feedbackOpen(), isTrue);
    expect(find.text('Send feedback'), findsWidgets);
    // Another shake while the form is open opens no second one.
    await shake(tester);
    expect(find.byType(FeedbackPanel), findsOneWidget);
  });

  testWidgets('Settings turns it off (on by default), and it stays off', (tester) async {
    final c = await pumpApp(tester);
    expect(c.read(shakeFeedbackProvider), isTrue, reason: 'on until the player turns it off');
    c.read(shakeFeedbackProvider.notifier).set(false);
    await shake(tester);
    expect(feedbackOpen(), isFalse);
    expect(store.getText('shakeFeedback'), 'off', reason: 'kept on the device for the next launch');
    c.read(shakeFeedbackProvider.notifier).set(true);
    await shake(tester);
    expect(feedbackOpen(), isTrue);
  });

  testWidgets('not over an alert that waits for an answer', (tester) async {
    await pumpApp(tester);
    final context = tester.element(find.text('Home'));
    showAppAlert(context, title: 'Block anet?', confirmLabel: 'Block', cancelLabel: 'Cancel', destructive: true);
    await tester.pumpAndSettle();
    await shake(tester);
    expect(feedbackOpen(), isFalse);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await shake(tester);
    expect(feedbackOpen(), isTrue);
  });

  testWidgets('the web listens for nothing', (tester) async {
    await pumpApp(tester, caps: PlatformCaps.web);
    await shake(tester);
    expect(feedbackOpen(), isFalse);
    expect(ShakeChannel.supportedOn(PlatformCaps.web), isFalse);
    expect(ShakeChannel.supportedOn(PlatformCaps.ios), isTrue);
  });
}
