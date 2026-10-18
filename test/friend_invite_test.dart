// Social > Friends > Invite friends (TestFlight feedback ABL5vmG1UgNFRNAPJvaSmGY, owner 2026-10-18):
// "Share" opens the system share sheet (Copy, Messages, WhatsApp, Instagram...) with one line and the
// invite link; where there is no share sheet (a browser without one) the link is copied as before.
import 'package:carden/core/theme/app_theme.dart';
import 'package:carden/features/social/friend_invite.dart';
import 'package:carden/state/auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');

  late List<MethodCall> shared;
  late List<String> copied;
  var shareFails = false;

  setUp(() {
    shared = [];
    copied = [];
    shareFails = false;
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(shareChannel, (call) async {
      if (shareFails) throw PlatformException(code: 'unavailable');
      shared.add(call);
      return 'dev.fluttercommunity.plus/share/success';
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
      return null;
    });
  });

  Future<void> pumpCard(WidgetTester tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [currentUserIdProvider.overrideWithValue('6acbbf8a8898f585d3ca')],
      child: MaterialApp(theme: AppTheme.light(), home: Scaffold(body: Padding(padding: const EdgeInsets.all(20), child: FriendInviteCard(onAdd: () {})))),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('the invite card says Share and opens the share sheet with the link', (tester) async {
    await pumpCard(tester);
    expect(find.text('Share'), findsOneWidget);
    expect(find.text('Copy link'), findsNothing);
    expect(find.text('Add friend'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('share-invite')));
    await tester.pumpAndSettle();
    expect(shared, hasLength(1));
    final args = shared.single.arguments as Map;
    expect(args['text'], 'Add me as a friend in Carden\nhttps://play.carden.page/add-friend?code=6acbbf8a8898f585d3ca');
    expect(args['subject'], friendInviteText);
    expect(args['originWidth'], greaterThan(0), reason: 'the iPad popover points at the button');
    expect(copied, isEmpty, reason: 'the share sheet has its own Copy');
  });

  testWidgets('without a share sheet the link is copied, with the toast as before', (tester) async {
    await pumpCard(tester);
    shareFails = true;
    await tester.tap(find.byKey(const ValueKey('share-invite')));
    await tester.pumpAndSettle();
    expect(copied, [friendInviteLink('6acbbf8a8898f585d3ca')]);
    expect(find.text('Copied your invite link'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
  });
}
