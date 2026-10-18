import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/tokens.dart';
import '../../models/models.dart';
import '../../state/achievements.dart';
import '../../state/auth.dart';
import '../../state/completion.dart';
import '../../state/social.dart';
import '../../widgets/glass.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';
import '../profile/stats.dart';
import 'friend_gifts.dart';
import 'player_safety.dart';

/// Read-only profile of another player: identity, headline numbers, the
/// public statistics and the achievement tiers they have claimed. Profiles
/// are public, so this works for league rows and friends alike; progress
/// rows are not, so the Statistics section shows the profile's aggregates
/// (the same widget as the own profile, minus the owner-only tiles).
class PlayerScreen extends ConsumerWidget {
  const PlayerScreen({super.key, required this.userId});
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final profile = ref.watch(playerProfileProvider(userId));
    final isMe = ref.watch(currentUserIdProvider) == userId;
    final blocked = ref.watch(blockedPlayersProvider).value?.any((b) => b.playerId == userId) ?? false;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        title: ScrolledUnder(
          builder: (context, under) => AnimatedOpacity(
            opacity: under ? 1 : 0,
            duration: const Duration(milliseconds: 180),
            child: Text(profile.value?.displayName ?? 'Player', maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
        leading: Padding(padding: const EdgeInsets.only(left: 12), child: RoundIconButton(icon: AppIcons.back, size: 38, onTap: () => context.pop())),
        actions: [
          // Report and block (guideline 1.2) for another player: one menu in the bar, reachable at
          // any scroll position, as in Messages and Mail. App Review: Player > ... > Report / Block.
          if (!isMe && ref.watch(currentUserIdProvider) != null && profile.value != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: RoundIconButton(
                key: const ValueKey('player-more'),
                icon: AppIcons.ellipsis,
                size: 38,
                onTap: () => _showPlayerMenu(context, profile.value!, blocked: blocked),
              ),
            ),
        ],
      ),
      body: profile.when(
        loading: () => const Loader(),
        error: (e, _) => const EmptyState(icon: AppIcons.signal, title: 'Profile could not load', message: 'Check your connection and try again.'),
        data: (p) {
          if (p == null) return const EmptyState(icon: AppIcons.profile, title: 'Player not found', message: 'This player may have deleted their account.');
          final claimed = <({AchievementFamily family, int tier})>[
            for (final f in achievementFamilies)
              for (var i = f.steps.length; i >= 1; i--)
                if (p.claimedAchievements.contains('${f.id}:$i')) ...[(family: f, tier: i)],
          ];
          // One entry per family: its highest claimed tier.
          final badges = <String, ({AchievementFamily family, int tier})>{};
          for (final b in claimed) {
            badges.putIfAbsent(b.family.id, () => b);
          }
          final top = MediaQuery.paddingOf(context).top + kToolbarHeight;
          final side = 20 + pageInsetOf(context, maxWidth: PageWidth.reading);
          return ListView(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.fromLTRB(side, top + 12, side, GlassTabBar.scrollEndPadding(context)),
            children: [
              SoftCard(
                padding: Insets.card,
                child: Column(
                  children: [
                    Row(
                      children: [
                        AvatarCircle(avatarKey: p.avatar, size: 72, border: true),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(isMe ? '${p.displayName} (you)' : p.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.headlineSmall),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Flexible(child: Text('Level ${p.level} · ${formatCount(p.xp)} XP', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.textSecondary, fontSize: TypeSize.footnote, fontWeight: FontWeight.w500))),
                                  if (p.isVip) ...[
                                    const SizedBox(width: 8),
                                    Chip2(label: 'VIP', icon: AppIcons.vip, color: c.accentTint, foreground: context.accent),
                                  ],
                                  // The menu's Unblock is the way back; the card says why they are missing from the league.
                                  if (blocked && !isMe) ...[
                                    const SizedBox(width: 8),
                                    const Chip2(key: ValueKey('player-blocked'), label: 'Blocked', icon: AppIcons.block),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 10),
                              ProgressBar(value: p.levelProgress, height: 6),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Divider(height: 1, thickness: 1, color: c.stroke),
                    const SizedBox(height: 12),
                    IntrinsicHeight(
                      child: Row(
                        children: [
                          _SummaryStat(icon: AppIcons.puzzle, value: compactCount(p.puzzlesCompleted), label: 'Solved'),
                          VerticalDivider(width: 1, thickness: 1, color: c.stroke),
                          _SummaryStat(icon: AppIcons.star, iconColor: context.star, value: compactCount(p.totalStars), label: 'Stars'),
                          VerticalDivider(width: 1, thickness: 1, color: c.stroke),
                          _SummaryStat(icon: AppIcons.streak, value: compactCount(p.streak), label: 'Day streak'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // A friend's profile: Send a gift (lib/features/social/friend_gifts.dart).
              if (!isMe && !blocked && ref.watch(currentUserIdProvider) != null) SendGiftButton(friend: p),
              SectionHeader(
                padding: const EdgeInsets.fromLTRB(0, 28, 0, 12),
                title: 'Statistics',
                subtitle: isMe ? 'Everything you have played so far' : 'Everything ${p.displayName} has played so far',
              ),
              // The three headline numbers and the level are shown above; the section has the rest.
              StatisticsSection(
                stats: isMe ? ref.watch(playerStatsProvider) : PlayerStats.fromProfile(p, catalogue: ref.watch(catalogueSizeProvider)),
                omit: const {'solved', 'stars', 'streak', 'level'},
              ),
              SectionHeader(padding: const EdgeInsets.fromLTRB(0, 28, 0, 12), title: 'Achievements', subtitle: badges.isEmpty ? 'Nothing claimed yet' : '${badges.length} of ${achievementFamilies.length} families claimed'),
              if (badges.isEmpty)
                const EmptyState(icon: AppIcons.level, title: 'No badges yet', message: 'Claimed achievement tiers show up here.')
              else
                GridView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 0.92),
                  itemCount: badges.length,
                  itemBuilder: (_, i) {
                    final b = badges.values.elementAt(i);
                    return _BadgeTile(family: b.family, tier: b.tier);
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}

/// One of the three headline numbers in the profile card: icon and value on one line, label under it.
class _SummaryStat extends StatelessWidget {
  const _SummaryStat({required this.icon, required this.value, required this.label, this.iconColor});
  final IconData icon;
  final Color? iconColor;
  final String value;
  final String label;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Expanded(
      child: Column(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: iconColor ?? context.accent),
              const SizedBox(width: 5),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: TypeSize.headline, letterSpacing: -0.3)),
            ],
          ),
          const SizedBox(height: 2),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: TypeSize.caption, color: c.textSecondary)),
        ],
      ),
    );
  }
}

/// The player menu: Report, Block in red (Unblock once blocked), Cancel, as an action sheet in
/// the alerts' family (as for "Add a photo" in My Puzzles).
Future<void> _showPlayerMenu(BuildContext context, Profile p, {required bool blocked}) async {
  final choice = await showAppActionSheet<String>(
    context,
    title: p.displayName,
    actions: [
      AppAction('Report ${p.displayName}', 'report', key: const ValueKey('player-report')),
      if (blocked)
        AppAction('Unblock ${p.displayName}', 'unblock', key: const ValueKey('player-unblock'))
      else
        AppAction('Block ${p.displayName}', 'block', destructive: true, key: const ValueKey('player-block')),
    ],
  );
  if (!context.mounted) return;
  switch (choice) {
    case 'report':
      // Report with "Also block" closes the profile too, like Block.
      if (await showReportSheet(context, p) && context.mounted) leaveBlockedProfile(context);
    case 'unblock':
      unblockPlayer(context, p.userId, p.displayName);
    case 'block':
      if (await confirmBlock(context, p) && context.mounted) leaveBlockedProfile(context);
  }
}

class _BadgeTile extends StatelessWidget {
  const _BadgeTile({required this.family, required this.tier});
  final AchievementFamily family;
  final int tier;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final step = family.steps[tier - 1];
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (step.avatarKey != null)
            AvatarCircle(avatarKey: step.avatarKey, size: 40)
          else
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(shape: BoxShape.circle, color: c.accentTint),
              child: Icon(family.icon, size: 20, color: context.accent),
            ),
          const SizedBox(height: 8),
          Text(family.title, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: TypeSize.footnote)),
          const SizedBox(height: 2),
          Text(family.steps.length > 1 ? 'Tier $tier of ${family.steps.length}' : family.describe(step.threshold), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: TypeSize.micro, color: c.textSecondary)),
        ],
      ),
    );
  }
}
