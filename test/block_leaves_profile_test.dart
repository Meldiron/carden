// Player > ... > Block (TestFlight feedback AJhAN2r4m1ttgfQ1iTQIYiU, owner 2026-10-18: "After blocking
// player, go away from their profile"): once the block is confirmed and saved, the profile closes
// back to where the player came from, with a "Blocked <name>" toast; a profile opened from a link
// with nothing under it goes to Social. Cancel, or a block that fails, stays on the profile.
import 'dart:io' show Directory;

import 'package:appwrite/appwrite.dart';
import 'package:carden/core/theme/app_theme.dart';
import 'package:carden/data/repositories.dart';
import 'package:carden/features/social/player_screen.dart';
import 'package:carden/models/models.dart';
import 'package:carden/state/auth.dart';
import 'package:carden/state/completion.dart';
import 'package:carden/state/friend_gifts.dart';
import 'package:carden/state/social.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Profile _player(String id) => Profile.fromRow(id, {'userId': id, 'displayName': 'anet', 'avatar': 'fox', 'xp': 4098, 'puzzlesCompleted': 24});

class _Social extends SocialRepository {
  _Social() : super(TablesDB(Client()));
  final calls = <String>[];
  final blocked = <BlockedPlayer>[];
  bool fail = false;

  @override
  Future<void> block(String userId, Profile player) async {
    if (fail) throw AppwriteException('Failed host lookup');
    calls.add('block ${player.userId}');
    blocked.add(BlockedPlayer(id: 'b-${player.userId}', playerId: player.userId, name: player.displayName, avatar: player.avatar));
  }

  @override
  Future<void> removeFriendOf(String userId, String friendId) async => calls.add('unfriend $friendId');
  @override
  Future<List<BlockedPlayer>> blocks(String userId) async => List.of(blocked);
  @override
  Future<List<Friend>> friends(String userId) async => const [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async => Directory.systemTemp.createTempSync('cjw-test').path,
  );

  late _Social social;
  setUp(() => social = _Social());

  Future<GoRouter> pumpApp(WidgetTester tester, {required String start}) async {
    final router = GoRouter(
      initialLocation: start,
      routes: [
        GoRoute(
          path: '/social',
          builder: (context, _) => Scaffold(body: Center(child: TextButton(onPressed: () => context.push('/player/p2'), child: const Text('Leaderboard')))),
        ),
        GoRoute(path: '/player/:userId', builder: (_, s) => PlayerScreen(userId: s.pathParameters['userId']!)),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentUserIdProvider.overrideWithValue('me'),
        socialRepositoryProvider.overrideWithValue(social),
        playerProfileProvider.overrideWith((ref, id) async => _player(id)),
        catalogueSizeProvider.overrideWithValue(null),
        giftSentProvider.overrideWith((ref, key) async => false),
      ],
      child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    ));
    await tester.pumpAndSettle();
    return router;
  }

  Future<void> block(WidgetTester tester, {bool confirm = true}) async {
    await tester.tap(find.byKey(const ValueKey('player-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('player-block')));
    await tester.pumpAndSettle();
    expect(find.text('Block anet?'), findsOneWidget);
    await tester.tap(find.text(confirm ? 'Block' : 'Cancel').last);
    await tester.pumpAndSettle();
  }

  testWidgets('blocking from the leaderboard goes back to the leaderboard, with a toast', (tester) async {
    final router = await pumpApp(tester, start: '/social');
    await tester.tap(find.text('Leaderboard'));
    await tester.pumpAndSettle();
    expect(find.byType(PlayerScreen), findsOneWidget);

    // Cancel keeps the profile.
    await block(tester, confirm: false);
    expect(find.byType(PlayerScreen), findsOneWidget);
    expect(social.calls, isEmpty);

    await block(tester);
    expect(social.calls, ['block p2', 'unfriend p2']);
    expect(find.byType(PlayerScreen), findsNothing, reason: 'the profile closes after the block');
    expect(router.state.uri.path, '/social');
    expect(find.text('Blocked anet'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('a profile opened from a link with nothing under it goes to Social', (tester) async {
    final router = await pumpApp(tester, start: '/player/p2');
    expect(find.byType(PlayerScreen), findsOneWidget);
    await block(tester);
    expect(find.byType(PlayerScreen), findsNothing);
    expect(router.state.uri.path, '/social');
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('a block that fails stays on the profile and says so', (tester) async {
    await pumpApp(tester, start: '/social');
    await tester.tap(find.text('Leaderboard'));
    await tester.pumpAndSettle();
    social.fail = true;
    await block(tester);
    expect(find.byType(PlayerScreen), findsOneWidget);
    expect(find.text('Could not block. Check your connection and try again.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
  });
}
