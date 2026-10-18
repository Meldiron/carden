// Social > Inbox UI (owner, 2026-10-18): the message sheet has no delete or close buttons (a drag
// down or a tap above closes it), its actions stay pinned under the text, and a message is deleted
// from its row: a swipe left that asks first, or VoiceOver's "Delete message" action.
import 'package:carden/core/theme/app_theme.dart';
import 'package:carden/features/social/inbox.dart';
import 'package:carden/models/models.dart';
import 'package:carden/state/inbox.dart';
import 'package:carden/state/profile.dart';
import 'package:carden/widgets/glass.dart';
import 'package:carden/widgets/icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<String> deleted;

  Future<void> pumpInbox(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
    addTearDown(tester.view.reset);
    deleted = [];
    final message = InboxMessage(
      id: 'm1',
      subject: 'Celebrating Carden 2.0',
      body: 'Carden 2.0 is our first release on the App Store. Here are 500 coins for any pack you like.',
      sentAt: DateTime.now().subtract(const Duration(hours: 2)),
      coins: 500,
      ctaLabel: 'Open the Library',
      ctaLink: '/library',
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        inboxMessagesProvider.overrideWith((ref) async => [message]),
        profileProvider.overrideWith(() => _Profile(deleted)),
      ],
      child: MaterialApp(theme: AppTheme.dark(), home: const Scaffold(body: InboxList())),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Celebrating Carden 2.0'), findsOneWidget);
  }

  testWidgets('the message sheet has no delete or close buttons and closes with a drag down', (tester) async {
    await pumpInbox(tester);
    await tester.tap(find.text('Celebrating Carden 2.0'));
    await tester.pumpAndSettle();
    final sheet = find.byType(GlassSheet);
    expect(find.byKey(const ValueKey('message-sheet-m1')), findsOneWidget);
    expect(find.byKey(const ValueKey('message-delete')), findsNothing);
    expect(find.byKey(const ValueKey('message-close')), findsNothing);
    expect(find.descendant(of: sheet, matching: find.byIcon(AppIcons.trash)), findsNothing);
    expect(find.descendant(of: sheet, matching: find.byIcon(AppIcons.xmark)), findsNothing);
    // Claim and the message's button sit in the pinned footer.
    final footer = find.byKey(const ValueKey('sheet-footer'));
    expect(find.descendant(of: footer, matching: find.byKey(const ValueKey('message-claim'))), findsOneWidget);
    expect(find.descendant(of: footer, matching: find.byKey(const ValueKey('message-cta'))), findsOneWidget);

    await tester.drag(find.descendant(of: sheet, matching: find.textContaining('Carden 2.0 is our first release')), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(sheet, findsNothing);
  });

  testWidgets('a message is deleted from its row: a swipe left that asks first, or the VoiceOver action', (tester) async {
    await pumpInbox(tester);
    final handle = tester.ensureSemantics();
    expect(
      tester.getSemantics(find.byKey(const ValueKey('message-row-m1'))),
      isSemantics(customActions: [const CustomSemanticsAction(label: 'Delete message')]),
    );
    handle.dispose();

    await tester.drag(find.byKey(const ValueKey('message-row-m1')), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text('Delete message?'), findsOneWidget, reason: 'it asks first');
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(deleted, ['m1']);
  });
}

class _Profile extends ProfileNotifier {
  _Profile(this.deleted);
  final List<String> deleted;

  @override
  Future<Profile> build() async => Profile.guest('u1');

  @override
  void markMessageSeen(String id) {}

  @override
  void deleteMessage(String id) => deleted.add(id);
}
