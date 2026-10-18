import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/analytics.dart';
import '../../core/haptics.dart';
import '../../core/a11y.dart';
import '../../core/theme/tokens.dart';
import '../../data/repositories.dart';
import '../../models/models.dart';
import '../../state/auth.dart';
import '../../state/inbox.dart';
import '../../state/profile.dart';
import '../../state/social.dart';
import '../../widgets/glass.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';
import '../home/header_bar.dart';
import 'friend_gifts.dart';
import 'friend_invite.dart';
import 'inbox.dart';

/// Social's tab: 0 the leaderboard, 1 friends, 2 the inbox. A provider, so a link
/// (`/social?tab=friends`, `/inbox`, `/add-friend?code=...`) can pick it.
class SocialTab extends Notifier<int> {
  static const leaderboard = 0;
  static const friends = 1;
  static const inbox = 2;

  @override
  int build() => leaderboard;

  void select(int tab) {
    if (tab == inbox && state != inbox) AppAnalytics.event('inbox_opened');
    state = tab;
  }
}

final socialTabProvider = NotifierProvider<SocialTab, int>(SocialTab.new);

/// "Add friend by code": Social > Friends, and the link `/add-friend?code=<friend code>`, which
/// fills the code in.
Future<void> showAddFriendAlert(BuildContext context, {String? code}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final controller = TextEditingController(text: code?.trim() ?? '');
  final c = context.colors;
  final mine = container.read(currentUserIdProvider);
  final ok = await showAppAlert(
    context,
    title: 'Add friend by code',
    message: 'Paste the code your friend shared.',
    confirmLabel: 'Add friend',
    cancelLabel: 'Not now',
    canConfirm: () => controller.text.trim().isNotEmpty,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CupertinoTextField(
      key: const ValueKey('add-friend-field'),
      controller: controller,
      placeholder: 'Friend code',
      autofocus: code == null || code.trim().isEmpty,
      autocorrect: false,
      textAlign: TextAlign.center,
      cursorColor: context.accent,
      style: TextStyle(fontSize: TypeSize.callout, color: c.textPrimary, letterSpacing: -0.2),
      placeholderStyle: TextStyle(fontSize: TypeSize.callout, color: c.textTertiary, letterSpacing: -0.2),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      // The look of AlertTextField (the other alert fields), keyed for the deep-link tests.
      decoration: BoxDecoration(color: context.isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(12)),
        ),
        // The player's own code, for a friend who adds by code instead of the link.
        if (mine != null) ...[const SizedBox(height: 2), _YourCode(code: mine)],
      ],
    ),
  );
  final entered = ok ? controller.text.trim() : null;
  if (entered == null || entered.isEmpty || !context.mounted) return;
  final me = container.read(currentUserIdProvider);
  if (me == null) return;
  if (entered == me) {
    showToast(context, 'That is your own code. Share it with a friend instead.', icon: AppIcons.profile);
    return;
  }
  try {
    final friend = await container.read(profileRepositoryProvider).findByUserId(entered);
    if (friend == null) {
      if (context.mounted) showToast(context, 'No player with that code. Check it and try again.', icon: AppIcons.search);
      return;
    }
    await container.read(socialRepositoryProvider).addFriend(me, friend);
    AppAnalytics.event('friend_added', {'fromLink': code != null && code.trim().isNotEmpty});
    container.invalidate(friendsProvider);
    if (context.mounted) {
      Haptics.success();
      showToast(context, 'Added ${friend.displayName}', icon: AppIcons.addFriend);
      // Friends send gifts: the moment to offer gift notifications (asked once).
      await offerGiftNotifications(context, container);
    }
  } catch (e) {
    if (context.mounted) showToast(context, 'Could not add friend. Check your connection and try again.', icon: AppIcons.signal);
  }
}

/// "Your code 6acb...  [copy]" under the Add friend field: tap to copy. The alert sits above the
/// toasts, so the line itself confirms the copy.
class _YourCode extends StatefulWidget {
  const _YourCode({required this.code});
  final String code;
  @override
  State<_YourCode> createState() => _YourCodeState();
}

class _YourCodeState extends State<_YourCode> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Pressable(
      key: const ValueKey('add-friend-your-code'),
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: widget.code));
        if (!mounted) return;
        setState(() => _copied = true);
        await Future<void>.delayed(const Duration(seconds: 2));
        if (mounted) setState(() => _copied = false);
      },
      child: TapTarget(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Your code', style: TextStyle(fontSize: TypeSize.caption, color: c.textSecondary)),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                _copied ? 'Copied' : widget.code,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: TypeSize.caption, fontWeight: FontWeight.w600, color: c.textPrimary, fontFeatures: tabularFigures),
              ),
            ),
            const SizedBox(width: 5),
            Icon(_copied ? AppIcons.checkmarkAlt : AppIcons.copy, size: 13, color: context.accent),
          ],
        ),
      ),
    );
  }
}

/// Social: the leaderboard (every player by total XP), friends (add by friend code) and the inbox
/// (messages from Carden, lib/features/social/inbox.dart).
class SocialScreen extends ConsumerWidget {
  const SocialScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(socialTabProvider);
    return Scaffold(
      body: Column(
        children: [
          const HeaderBar(title: 'Social', sliver: false, contentWidth: PageWidth.reading),
          // A wide window keeps the league in a reading column; the lists below scroll the whole
          // window's width, so a mouse wheel works anywhere on the page.
          Padding(
            padding: EdgeInsets.fromLTRB(20 + pageInsetOf(context, maxWidth: PageWidth.reading), 10, 20 + pageInsetOf(context, maxWidth: PageWidth.reading), 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The large title alone on its line and the switch under it, full width (the iOS
                // pattern): neither squeezes the other at any text size.
                const PageTitle('Social'),
                const SizedBox(height: 10),
                AppSegmentedControl<int>(
                  value: tab,
                  segments: const {0: 'Leaderboard', 1: 'Friends', 2: 'Inbox'},
                  // An unopened message: a dot on Inbox until it is opened.
                  badges: {if (ref.watch(inboxUnseenProvider)) SocialTab.inbox},
                  segmentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  onChanged: (v) => ref.read(socialTabProvider.notifier).select(v),
                ),
              ],
            ),
          ),
          Expanded(
            child: switch (tab) {
              SocialTab.leaderboard => const _Leaderboard(),
              SocialTab.inbox => const InboxList(),
              _ => _Friends(onAdd: () => showAddFriendAlert(context)),
            },
          ),
        ],
      ),
    );
  }
}

class _Leaderboard extends ConsumerStatefulWidget {
  const _Leaderboard();
  @override
  ConsumerState<_Leaderboard> createState() => _LeaderboardState();
}

class _LeaderboardState extends ConsumerState<_Leaderboard> {
  final _scroll = ScrollController();
  final _meKey = GlobalKey();

  /// Whether the player's own row is on screen; the pinned "your place" bar shows only when it is not.
  bool _meOnScreen = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _checkMe() {
    final box = _meKey.currentContext?.findRenderObject() as RenderBox?;
    var on = false;
    if (box != null && box.attached && box.hasSize) {
      final top = box.localToGlobal(Offset.zero).dy;
      final screen = MediaQuery.sizeOf(context).height;
      // Between the Social title row and the pinned bar above the tab bar.
      on = top + box.size.height > 200 && top < screen - GlassTabBar.scrollEndPadding(context, margin: 0) - 70;
    }
    if (on != _meOnScreen && mounted) setState(() => _meOnScreen = on);
  }

  /// How many players stand on the podium card (the first three), 0 when the league is too small
  /// for one; the list continues after them.
  static int _podiumCount(List<Profile> list) => list.length >= 3 ? 3 : 0;

  /// Scrolls to the player's row when it is loaded; otherwise opens their own profile.
  Future<void> _showMe(List<Profile> list, String? me) async {
    final index = list.indexWhere((p) => p.userId == me);
    if (index < 0) {
      if (me != null) context.push('/player/$me');
      return;
    }
    if (_meKey.currentContext == null) {
      // The podium is about 200 pt and rows about 57 pt; land near the row, then let
      // ensureVisible place it exactly.
      final start = _podiumCount(list);
      final offset = index < start ? 30.0 : 30.0 + (start > 0 ? 200 : 0) + (index - start) * 57;
      await _scroll.animateTo(offset.clamp(0, _scroll.position.maxScrollExtent), duration: A11y.motion(context, const Duration(milliseconds: 350)), curve: Curves.easeOutCubic);
    }
    final ctx = _meKey.currentContext;
    if (ctx != null && ctx.mounted) await Scrollable.ensureVisible(ctx, alignment: 0.4, duration: A11y.motion(ctx, const Duration(milliseconds: 250)), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final board = ref.watch(leaderboardProvider);
    final me = ref.watch(currentUserIdProvider);
    final place = ref.watch(leaderboardRankProvider).value;
    final myProfile = ref.watch(profileProvider).value;
    final showBar = place != null && myProfile != null && !_meOnScreen;
    final side = 20 + pageInsetOf(context, maxWidth: PageWidth.reading);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _checkMe();
    });
    return board.when(
      loading: () => const Loader(),
      error: (e, _) => EmptyState(
        icon: AppIcons.signal,
        title: 'Leaderboard could not load',
        message: 'Check your connection and try again.',
        action: BigButton(
          label: 'Try again',
          kind: ButtonKind.secondary,
          height: 44,
          expand: false,
          onTap: () {
            ref.invalidate(leaderboardProvider);
            ref.invalidate(leaderboardRankProvider);
          },
        ),
      ),
      data: (paged) {
        final list = paged.items;
        final start = _podiumCount(list);
        final podium = start > 0;
        final rowCount = list.length - start;
        if (list.isEmpty) return const EmptyState(icon: AppIcons.trophy, title: 'The leaderboard is empty', message: 'Solve a puzzle to earn XP and take the first place.');
        final listView = RefreshIndicator.adaptive(
          onRefresh: () async {
            ref.invalidate(leaderboardProvider);
            ref.invalidate(leaderboardRankProvider);
          },
          child: NotificationListener<ScrollNotification>(
            onNotification: (_) {
              // After the frame: rows that scroll in are built during layout.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _checkMe();
              });
              return false;
            },
            child: ListView.builder(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            // Room for the pinned bar, so the last rows can scroll above it.
            padding: EdgeInsets.fromLTRB(side, 0, side, GlassTabBar.scrollEndPadding(context) + (place != null ? 72 : 0)),
            itemCount: rowCount + 1 + (podium ? 1 : 0) + (paged.hasMore ? 1 : 0),
            itemBuilder: (_, i) {
              // Next page when the list nears its end (infinite scroll).
              if (paged.hasMore && i >= rowCount - 10) {
                WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(leaderboardProvider.notifier).loadMore());
              }
              if (i == rowCount + 1 + (podium ? 1 : 0)) {
                return const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Center(child: CupertinoActivityIndicator()));
              }
              if (i == 0) {
                // One quiet line instead of a card that repeats the tab's name; the player's own
                // place is the pinned bar at the bottom.
                return Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
                  child: Text(
                    place != null ? '${formatCount(place.total)} players · ranked by total XP' : 'Ranked by total XP. Solve a puzzle to join.',
                    style: TextStyle(color: c.textSecondary, fontSize: TypeSize.footnote),
                  ),
                );
              }
              // The first three stand on a podium card; the list continues from fourth.
              if (podium && i == 1) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _Podium(top: list.take(3).toList(), places: [for (var k = 0; k < 3; k++) leaguePlace(list, k)], me: me, meKey: _meKey),
                );
              }
              final index = start + i - 1 - (podium ? 1 : 0);
              final p = list[index];
              final rank = leaguePlace(list, index);
              final isMe = p.userId == me;
              // One grouped list (iOS inset style): rounded ends, full-width hairlines between rows.
              final first = index == start, last = index == list.length - 1;
              return Pressable(
                key: isMe ? _meKey : null,
                scale: 0.99,
                onTap: () => context.push('/player/${p.userId}'),
                child: Container(
                  decoration: BoxDecoration(
                    color: isMe ? c.accentTint : c.card,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(first ? Radii.lg : 0), bottom: Radius.circular(last ? Radii.lg : 0)),
                  ),
                  child: Column(
                    children: [
                      _PlayerRow(rank: rank, profile: p, me: isMe),
                      if (!last) Divider(height: 1, thickness: 1, indent: _dividerIndent, color: c.stroke),
                    ],
                  ),
                ),
              );
            },
          ),
          ),
        );
        return Stack(
          children: [
            listView,
            Positioned(
              left: side,
              right: side,
              bottom: GlassTabBar.scrollEndPadding(context, margin: 0),
              child: IgnorePointer(
                ignoring: !showBar,
                child: AnimatedSlide(
                  offset: showBar || A11y.reduceMotionOf(context) ? Offset.zero : const Offset(0, 0.3),
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: AnimatedOpacity(
                    opacity: showBar ? 1 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: myProfile == null || place == null
                        ? const SizedBox.shrink()
                        : _MyPlaceBar(profile: myProfile, rank: place.rank, total: place.total, onTap: () => _showMe(list, me)),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The player's own league row, pinned above the tab bar while their row is off screen: place,
/// avatar, name and XP, so "where am I" never needs a scroll through the whole league.
class _MyPlaceBar extends StatelessWidget {
  const _MyPlaceBar({required this.profile, required this.rank, required this.total, required this.onTap});
  final Profile profile;
  final int rank;
  final int total;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      scale: 0.98,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.lg),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: context.isDark ? 0.4 : 0.08), blurRadius: 18, offset: const Offset(0, 6))],
        ),
        child: GlassSurface(
          opacity: context.isDark ? 0.8 : 0.88,
          borderRadius: BorderRadius.circular(Radii.lg),
          hairline: Border.all(color: context.accent.withValues(alpha: 0.55)),
          child: _PlayerRow(rank: rank, profile: profile, me: true),
        ),
      ),
    );
  }
}

class _Friends extends ConsumerStatefulWidget {
  const _Friends({required this.onAdd});
  final VoidCallback onAdd;
  @override
  ConsumerState<_Friends> createState() => _FriendsState();
}

class _FriendsState extends ConsumerState<_Friends> {
  /// Rows swiped away and confirmed; hidden at once while the delete runs.
  final _removed = <String>{};

  Future<void> _remove(Friend f) async {
    setState(() => _removed.add(f.id));
    try {
      await ref.read(socialRepositoryProvider).removeFriend(f.id);
    } catch (_) {
      if (mounted) {
        setState(() => _removed.remove(f.id));
        showToast(context, 'Could not remove friend. Check your connection and try again.', icon: AppIcons.signal);
      }
      return;
    }
    ref.invalidate(friendsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final onAdd = widget.onAdd;
    final c = context.colors;
    final friends = ref.watch(friendsProvider);
    final side = 20 + pageInsetOf(context, maxWidth: PageWidth.reading);
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(side, 0, side, GlassTabBar.scrollEndPadding(context)),
      children: [
        // Invite: Share sends the link that opens the game with this player's code filled in
        // (lib/features/social/friend_invite.dart), and Add friend takes a friend's code.
        FriendInviteCard(onAdd: onAdd),
        const SizedBox(height: 16),
        friends.when(
          loading: () => const Padding(padding: EdgeInsets.all(30), child: Loader()),
          error: (e, _) => EmptyState(
            icon: AppIcons.signal,
            title: 'Friends could not load',
            message: 'Check your connection and try again.',
            action: BigButton(label: 'Try again', kind: ButtonKind.secondary, height: 44, expand: false, onTap: () => ref.invalidate(friendsProvider)),
          ),
          data: (list) => list.isEmpty
              ? const EmptyState(icon: AppIcons.wave, title: 'No friends yet', message: 'Send your invite link, or add a friend by their code, to compare stars.')
              : SoftCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (final (i, f) in list.where((f) => !_removed.contains(f.id)).indexed) ...[
                        if (i > 0) Divider(height: 1, thickness: 1, indent: _dividerIndent, color: c.stroke),
                        Dismissible(
                            key: ValueKey(f.id),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              color: c.danger,
                              child: const Icon(AppIcons.trash, color: Colors.white),
                            ),
                            confirmDismiss: (_) => showAppAlert(
                              context,
                              title: 'Remove friend?',
                              message: '${f.name} will leave your friends list. You can add them again with their code.',
                              confirmLabel: 'Remove',
                              destructive: true,
                            ),
                            onDismissed: (_) => _remove(f),
                            child: _FriendRow(friend: f),
                          ),
                      ],
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class _FriendRow extends ConsumerWidget {
  const _FriendRow({required this.friend});
  final Friend friend;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return FutureBuilder<Profile?>(
      future: ref.read(profileRepositoryProvider).findByUserId(friend.friendId),
      builder: (_, snap) {
        final p = snap.data;
        return Pressable(
          scale: 0.99,
          onTap: () => context.push('/player/${friend.friendId}'),
          child: Container(
            color: c.card,
            padding: const EdgeInsets.fromLTRB(12, 9, 16, 9),
            child: Row(
              children: [
                AvatarCircle(avatarKey: p?.avatar ?? friend.avatar, size: 36),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _PlayerName(name: p?.displayName ?? friend.name),
                      const SizedBox(height: 1),
                      if (p == null) Text('Loading…', style: TextStyle(fontSize: TypeSize.caption, color: c.textSecondary)) else _SubStats(solved: p.puzzlesCompleted, stars: p.totalStars),
                    ],
                  ),
                ),
                if (p != null) ...[const SizedBox(width: 8), _XpColumn(xp: p.xp, level: p.level)],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A league row: place, avatar, name with solved count and stars, XP and level on the right.
class _PlayerRow extends StatelessWidget {
  const _PlayerRow({required this.rank, required this.profile, required this.me});
  final int rank;
  final Profile profile;
  final bool me;
  @override
  Widget build(BuildContext context) {
    final p = profile;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 9, 16, 9),
      child: Row(
        children: [
          _RankNumber(rank: rank),
          const SizedBox(width: 8),
          AvatarCircle(avatarKey: p.avatar, size: 36),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PlayerName(name: p.displayName, me: me),
                const SizedBox(height: 1),
                _SubStats(solved: p.puzzlesCompleted, stars: p.totalStars),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _XpColumn(xp: p.xp, level: p.level),
        ],
      ),
    );
  }
}

/// "428 solved · 1,000 [star]": the star is part of the text, so it always sits right after its
/// number and can never be drawn after an ellipsis.
class _SubStats extends StatelessWidget {
  const _SubStats({required this.solved, required this.stars});
  final int solved;
  final int stars;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: '${formatCount(solved)} solved · ${formatCount(stars)} '),
        WidgetSpan(alignment: PlaceholderAlignment.middle, child: Icon(AppIcons.star, size: 11, color: context.star)),
      ]),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: TypeSize.caption, color: c.textSecondary),
    );
  }
}

/// The ranking number on top, the level under it: "60,020 XP" / "Level 44".
class _XpColumn extends StatelessWidget {
  const _XpColumn({required this.xp, required this.level});
  final int xp;
  final int level;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text('${formatCount(xp)} XP', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: TypeSize.body)),
        const SizedBox(height: 1),
        Text('Level $level', style: TextStyle(fontSize: TypeSize.caption, color: c.textSecondary)),
      ],
    );
  }
}

/// A player's name on one line (long names end in an ellipsis) and, on the player's own row, a
/// small "You" tag that never gets cut.
class _PlayerName extends StatelessWidget {
  const _PlayerName({required this.name, this.me = false});
  final String name;
  final bool me;
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: TypeSize.body),
          ),
        ),
        if (me) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.pill),
              border: Border.all(color: context.accent),
            ),
            child: Text(
              'You',
              style: TextStyle(fontSize: TypeSize.micro, fontWeight: FontWeight.w700, color: context.accent),
            ),
          ),
        ],
      ],
    );
  }
}

/// Hairlines between league and friend rows run the full width of the list: with the place column
/// in front of the avatar the rows read as one table, and an inset line looked cut in half.
const double _dividerIndent = 0;

/// A league place as plain figures in a fixed column, so the avatar is the only circle in a row
/// (the medals live on the podium card). Places past 999 widen the column.
class _RankNumber extends StatelessWidget {
  const _RankNumber({required this.rank});
  final int rank;
  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 30),
        child: Text(
          formatCount(rank),
          textAlign: TextAlign.center,
          maxLines: 1,
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: TypeSize.footnote, color: context.colors.textSecondary, fontFeatures: tabularFigures),
        ),
      );
}

/// First, second and third place side by side (second, first, third), first raised and larger:
/// the avatar carries its place in a medal disc, then the name ("You" for the player) and XP.
/// Each opens the player's profile.
class _Podium extends StatelessWidget {
  const _Podium({required this.top, required this.places, required this.me, required this.meKey});
  final List<Profile> top;
  final List<int> places;
  final String? me;
  final Key meKey;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget spot(int index) {
      final p = top[index];
      final first = index == 0;
      final isMe = p.userId == me;
      final size = first ? 68.0 : 56.0;
      return Expanded(
        child: Pressable(
          key: isMe ? meKey : null,
          scale: 0.97,
          onTap: () => context.push('/player/${p.userId}'),
          child: Padding(
            padding: EdgeInsets.only(top: first ? 0 : 16, left: 4, right: 4),
            child: Column(
              children: [
                SizedBox(
                  width: size + 8,
                  height: size + 12,
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.topCenter,
                    children: [
                      AvatarCircle(avatarKey: p.avatar, size: size, border: true),
                      Positioned(bottom: 0, child: _MedalBadge(place: places[index])),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isMe ? 'You' : p.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: first ? TypeSize.body : TypeSize.footnote, color: isMe ? context.accent : c.textPrimary),
                ),
                const SizedBox(height: 1),
                Text('${formatCount(p.xp)} XP', maxLines: 1, style: TextStyle(fontSize: TypeSize.caption, color: c.textSecondary, fontFeatures: tabularFigures)),
              ],
            ),
          ),
        ),
      );
    }

    return SoftCard(
      padding: const EdgeInsets.fromLTRB(8, 18, 8, 16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [spot(1), spot(0), spot(2)]),
    );
  }
}

/// A podium place on its avatar: the medal's soft tint with a deep-tone number (white on gold and
/// silver read at about 2:1), ringed in the card colour so it sits cleanly on the avatar's edge.
class _MedalBadge extends StatelessWidget {
  const _MedalBadge({required this.place});
  final int place;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dark = context.isDark;
    // (fill, number) per medal, opaque so the disc covers the avatar; light and dark themes.
    final medal = switch (place) {
      1 => dark ? (const Color(0xFF4A3B12), const Color(0xFFF5C84A)) : (const Color(0xFFF8E7B3), const Color(0xFF7A5600)),
      2 => dark ? (const Color(0xFF3A3C43), const Color(0xFFD5D8E0)) : (const Color(0xFFE6E8EE), const Color(0xFF4B505C)),
      _ => dark ? (const Color(0xFF45301F), const Color(0xFFE5A577)) : (const Color(0xFFF3DED0), const Color(0xFF7D4520)),
    };
    return Container(
      constraints: const BoxConstraints(minWidth: 28),
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: medal.$1, borderRadius: BorderRadius.circular(Radii.pill), border: Border.all(color: c.card, width: 2.5)),
      child: Text('$place', style: TextStyle(fontWeight: FontWeight.w700, fontSize: TypeSize.footnote, color: medal.$2, fontFeatures: tabularFigures)),
    );
  }
}
