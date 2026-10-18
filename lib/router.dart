import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/analytics.dart';
import 'core/app_links.dart';
import 'core/platform.dart';
import 'features/coop/coop_routes.dart';
import 'features/daily/wheel_screen.dart';
import 'features/events/events_screen.dart';
import 'features/gallery/library_screen.dart';
import 'features/gallery/pack_screen.dart';
import 'features/game/game_screen.dart';
import 'features/game/difficulty_screen.dart';
import 'features/home/home_screen.dart';
import 'features/home/home_shell.dart';
import 'features/links/deep_links.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/profile/account_screen.dart';
import 'features/profile/my_puzzles_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/profile/settings_screen.dart';
import 'features/social/player_screen.dart';
import 'features/social/social_screen.dart';
import 'features/store/store_screen.dart';
import 'state/settings.dart';
import 'widgets/sheets.dart';

/// The app's root navigator (alerts and sheets raised outside a screen, e.g. by the save sync).
final rootNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  bool onboarded() => ref.read(settingsProvider).onboarded;
  final webLink = isWeb ? _webStartLink() : null;
  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    // Screen views (lib/core/analytics.dart): one observer for this navigator, one per tab.
    observers: AppAnalytics.observers(),
    // A web visit that starts on a link which needs Home beneath it (a picture, the store, a pack
    // code) starts on Home and hands the link to DeepLinks after the first frame.
    // An invite (Play together) opens its board above the welcome pages of a new visitor.
    initialLocation: onboarded() || (webLink != null && !webLink.path.startsWith('/join/')) ? '/home' : '/welcome',
    overridePlatformDefaultLocation: webLink != null,
    // Unknown paths (typed URLs on web, stale links) land on Home instead of the framework's
    // error page; a link the router has no page for (/quests, /redeem, /daily, see AppLink) goes
    // to DeepLinks. `/auth/callback` is reserved for the Appwrite OAuth redirect.
    onException: (context, state, router) {
      final link = AppLink.parse(state.uri);
      if (link != null && !(link.kind == LinkKind.page && link.path == '/home')) {
        DeepLinks.reportOpened(link);
        ref.read(deepLinksProvider).show(link);
      } else {
        router.go(onboarded() ? '/home' : '/welcome');
      }
    },
    redirect: (context, state) {
      // A link into the game (the widget's /play/<id>, a pack from an In-App Event, a web
      // address) goes straight to its screen, even for a new install, and counts as onboarding.
      // A shared board (Play together) is not one: a player who came in by an invite starts the
      // welcome pages after leaving the game.
      if (!onboarded() && state.uri.path != '/home' && !CoopRoutes.isCoop(state.uri) && AppLink.parse(state.uri) != null) {
        ref.read(settingsProvider.notifier).setOnboarded();
      }
      return null;
    },
    routes: [
      GoRoute(path: '/welcome', pageBuilder: (c, s) => _fade(const OnboardingScreen(), s)),
      StatefulShellRoute.indexedStack(
        // Each tab's navigator has its own observer; the root's sees only the root navigator.
        notifyRootObserver: false,
        builder: (context, state, shell) => HomeShell(shell: shell),
        branches: [
          StatefulShellBranch(observers: AppAnalytics.observers(tab: 0), routes: [GoRoute(path: '/home', pageBuilder: (c, s) => _noAnim(const HomeScreen(), s))]),
          StatefulShellBranch(observers: AppAnalytics.observers(tab: 1), routes: [
            GoRoute(
              path: '/library',
              pageBuilder: (c, s) => _noAnim(const LibraryScreen(), s),
              routes: [
                GoRoute(path: 'pack/:packId', pageBuilder: (c, s) => _cupertino(PackScreen(packId: s.pathParameters['packId']!), s)),
              ],
            ),
          ]),
          StatefulShellBranch(observers: AppAnalytics.observers(tab: 2), routes: [GoRoute(path: '/events', pageBuilder: (c, s) => _noAnim(const EventsScreen(), s))]),
          StatefulShellBranch(observers: AppAnalytics.observers(tab: 3), routes: [GoRoute(path: '/social', pageBuilder: (c, s) => _noAnim(const SocialScreen(), s))]),
          StatefulShellBranch(observers: AppAnalytics.observers(tab: 4), routes: [
            GoRoute(
              path: '/profile',
              pageBuilder: (c, s) => _noAnim(const ProfileScreen(), s),
              routes: [
                GoRoute(path: 'settings', pageBuilder: (c, s) => _cupertino(const SettingsScreen(), s)),
                GoRoute(path: 'my-puzzles', pageBuilder: (c, s) => _cupertino(const MyPuzzlesScreen(), s)),
              ],
            ),
          ]),
        ],
      ),
      // Full-screen routes above the tab shell.
      GoRoute(
        path: '/play/:puzzleId',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (c, s) => _cupertino(
          DifficultyScreen(
            puzzleId: s.pathParameters['puzzleId']!,
            initialGrid: s.uri.queryParameters['grid'],
            initialMode: s.uri.queryParameters['mode'],
            initialPainting: s.uri.queryParameters['painting'] == '1',
            initialExpand: s.uri.queryParameters['expand'] == '1',
            // Opened by Quick play (`?from=quick`): offers Another picture.
            fromQuick: s.uri.queryParameters['from'] == 'quick',
          ),
          s,
        ),
      ),
      GoRoute(
        // :grid is a BoardCode path form, e.g. hexagons-5x5t4 or 4x4 (cards); `?painting=1` starts a
        // new board in Painting (a saved board resumes as it was saved); `?expand=1` deals the next
        // picture with Expand too (a board that is not square is an Expand board anyway).
        path: '/game/:puzzleId/:grid',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (c, s) => _fade(
          GameScreen(
            puzzleId: s.pathParameters['puzzleId']!,
            gridCode: s.pathParameters['grid']!,
            painting: s.uri.queryParameters['painting'] == '1',
            expand: s.uri.queryParameters['expand'] == '1',
            first: s.uri.queryParameters['first'] == '1',
            // Play together: `?coop=<game id>` plays the game's shared board; with `&next=1` the host
            // deals the next board here and hands it to the game (docs/multiplayer.md).
            coopId: s.uri.queryParameters['coop'],
            coopNext: s.uri.queryParameters['next'] == '1',
          ),
          s,
        ),
      ),
      GoRoute(path: '/store', parentNavigatorKey: rootNavigatorKey, pageBuilder: (c, s) => _sheet(StoreScreen(showVip: s.uri.queryParameters['vip'] == '1'), s)),
      GoRoute(path: '/wheel', parentNavigatorKey: rootNavigatorKey, pageBuilder: (c, s) => _sheet(const WheelScreen(), s)),
      GoRoute(path: '/account', parentNavigatorKey: rootNavigatorKey, pageBuilder: (c, s) => _sheet(const AccountScreen(), s)),
      GoRoute(path: '/auth/callback', parentNavigatorKey: rootNavigatorKey, pageBuilder: (c, s) => _fade(AuthCallbackScreen(query: s.uri.queryParameters), s)),
      GoRoute(path: '/player/:userId', parentNavigatorKey: rootNavigatorKey, pageBuilder: (c, s) => _cupertino(PlayerScreen(userId: s.pathParameters['userId']!), s)),
    ],
  );
  // One router for the app's life, so a link that finishes onboarding keeps its screen. After an
  // account deletion (onboarded goes back to false) the welcome screens show again.
  ref.listen(settingsProvider.select((s) => s.onboarded), (was, now) {
    if (was == true && !now) router.go('/welcome');
  });
  if (webLink != null) {
    DeepLinks.reportOpened(webLink);
    WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(deepLinksProvider).show(webLink));
  }
  ref.onDispose(router.dispose);
  return router;
});

/// The link a web visit starts on, when it needs more than the router's own page: an alias
/// (`/quests`, `/pack/<id>`), a query the screen reads (`/library?filter=Giant`), an overlay that
/// needs Home beneath it, or an action. Null for the site root and for plain pages.
AppLink? _webStartLink() {
  final start = Uri.parse(WidgetsBinding.instance.platformDispatcher.defaultRouteName);
  if (start.path.isEmpty || start.path == '/') return null;
  final link = AppLink.parse(start);
  if (link == null) return null;
  if (link.kind == LinkKind.page && !link.location.hasQuery && link.path == start.path) return null;
  return link;
}

Page<T> _cupertino<T>(Widget child, GoRouterState s) => CupertinoPage<T>(key: s.pageKey, name: screenNameFor(s.fullPath), child: child);
Page<T> _noAnim<T>(Widget child, GoRouterState s) => NoTransitionPage<T>(key: s.pageKey, name: screenNameFor(s.fullPath), child: child);
Page<T> _fade<T>(Widget child, GoRouterState s) => CustomTransitionPage<T>(
      key: s.pageKey,
      name: screenNameFor(s.fullPath),
      child: child,
      transitionDuration: const Duration(milliseconds: 320),
      transitionsBuilder: (_, a, _, c) => FadeTransition(opacity: CurveTween(curve: Curves.easeOut).animate(a), child: c),
    );
/// The full-height sheets (Store, Wheel, Account): the iOS stacked sheet on a phone, a centred panel on
/// a wide window; they close with a drag down at the top of their content (`SheetPage`).
Page<T> _sheet<T>(Widget child, GoRouterState s) => SheetPage<T>(key: s.pageKey, name: screenNameFor(s.fullPath), child: child);
