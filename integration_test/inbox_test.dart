// Social > Inbox on the real app (live Appwrite, a QA guest). The messages come from outside the
// app, as in real life: while this test waits on the inbox (it prints INBOX_QA_USER <id>), give
// the guest a label and send two label messages, and keep a message to every player in the table:
//   python3 tools/dev/inbox.py labels <id> --add early --yes
//   python3 tools/dev/inbox.py send --label early --subject "Thanks for testing early" --body "..." \
//     --cta-label "Send feedback" --cta-link /feedback --yes
//   python3 tools/dev/inbox.py send --label girlfriend --subject "Only for the girlfriend label" --body "..." --yes
// (delete the two label messages afterwards). It checks what row-level permissions let through,
// the Inbox dot, Claim in the gift card, the feedback button and Delete.
//
//   tools/dev/qa-run.sh drive --driver=test_driver/integration_test.dart --target=integration_test/inbox_test.dart -d <simulator>
import 'package:carden/app.dart';
import 'package:carden/core/sfx.dart';
import 'package:carden/data/local_store.dart';
import 'package:carden/state/first_steps.dart';
import 'package:carden/state/inbox.dart';
import 'package:carden/state/profile.dart';
import 'package:carden/state/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> settle(WidgetTester tester, [int ms = 1500]) async {
  await tester.pump(const Duration(milliseconds: 50));
  final end = DateTime.now().add(Duration(milliseconds: ms));
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  Future<void> shot(WidgetTester tester, String name) async {
    await settle(tester, 400);
    await binding.takeScreenshot(name);
  }

  Future<void> tapText(WidgetTester tester, String text, {int ms = 1200}) async {
    final f = find.text(text);
    expect(f, findsWidgets, reason: 'expected "$text" on screen');
    await tester.tap(f.first, warnIfMissed: false);
    await settle(tester, ms);
  }

  testWidgets('inbox: list, open, claim, button, delete', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    await FirstSteps.skipFor(store); // the whole app; integration_test/first_steps_test.dart plays the first steps
    Sfx.instance.soundEnabled = false;
    Sfx.instance.musicEnabled = false;
    await tester.pumpWidget(ProviderScope(overrides: [localStoreProvider.overrideWithValue(store)], child: const CardenApp()));
    await settle(tester, 1500);
    await tapText(tester, 'Continue');
    await tapText(tester, 'Continue');
    await tapText(tester, 'Start playing', ms: 5000);
    await settle(tester, 4000);
    final c = ProviderScope.containerOf(tester.element(find.byType(CardenApp)));
    debugPrint('INBOX_QA_USER ${c.read(profileProvider).value?.userId}');

    await tapText(tester, 'Social', ms: 2500);
    await tapText(tester, 'Inbox', ms: 2000);
    await shot(tester, 'ib_00_empty');

    // Wait for the messages sent from outside (up to 4 minutes), reading the inbox again as a pull would:
    // the launch message to every player, one to the label `early` this guest was given, and one to
    // the label `girlfriend` it does not carry, which must never show.
    bool ready() => find.text('Celebrating Carden 2.0').evaluate().isNotEmpty && find.text('Thanks for testing early').evaluate().isNotEmpty;
    for (var i = 0; i < 80 && !ready(); i++) {
      c.invalidate(inboxMessagesProvider);
      await settle(tester, 3000);
    }
    expect(find.text('Celebrating Carden 2.0'), findsWidgets, reason: 'a message to every player');
    expect(find.text('Thanks for testing early'), findsWidgets, reason: 'a message to a label this player carries');
    expect(find.text('Only for the girlfriend label'), findsNothing, reason: 'row-level permissions keep other labels out');
    expect(c.read(inboxUnseenProvider), isTrue);
    expect(find.byKey(const ValueKey('segment-badge-2')), findsOneWidget, reason: 'the Inbox segment has its dot');
    await shot(tester, 'ib_01_list');

    // The launch message: Claim in its gift card, then Claimed; a drag down closes it.
    final coins = c.read(profileProvider).value!.coins;
    await tapText(tester, 'Celebrating Carden 2.0', ms: 1500);
    expect(find.byKey(const ValueKey('message-claim')), findsOneWidget);
    await shot(tester, 'ib_02_message');
    await tester.tap(find.byKey(const ValueKey('message-claim')), warnIfMissed: false);
    await settle(tester, 2500);
    expect(find.byKey(const ValueKey('message-claimed')), findsOneWidget, reason: 'the card says Claimed');
    expect(c.read(profileProvider).value!.coins, coins + 500);
    await shot(tester, 'ib_03_claimed');
    // No close button (owner, 2026-10-18): a drag down closes the sheet.
    await tester.drag(find.byKey(const ValueKey('sheet-grabber')), const Offset(0, 500));
    await settle(tester, 1500);

    // The early message's button opens Send feedback; opening it was the last unseen message.
    await tapText(tester, 'Thanks for testing early', ms: 1500);
    await tester.tap(find.byKey(const ValueKey('message-cta')), warnIfMissed: false);
    await settle(tester, 2500);
    expect(find.byKey(const ValueKey('feedback-field')), findsOneWidget, reason: 'the button opened the feedback sheet');
    await shot(tester, 'ib_04_feedback');
    Navigator.of(tester.element(find.byKey(const ValueKey('feedback-field')))).pop();
    await settle(tester, 1500);
    expect(c.read(inboxUnseenProvider), isFalse);
    expect(find.byKey(const ValueKey('segment-badge-2')), findsNothing, reason: 'every message opened: no dot');

    // Delete the early message: its row swipes left, and it asks first (the sheet has no delete button).
    final row = find.ancestor(of: find.text('Thanks for testing early'), matching: find.byType(Dismissible));
    await tester.drag(row.first, const Offset(-500, 0));
    await settle(tester, 1200);
    await tapText(tester, 'Delete', ms: 2000);
    expect(find.text('Thanks for testing early'), findsNothing);
    await shot(tester, 'ib_05_deleted');
  });
}
