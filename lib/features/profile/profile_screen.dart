import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/haptics.dart';
import '../../core/name_filter.dart';
import '../../core/sfx.dart';
import '../../core/a11y.dart';
import '../../core/analytics.dart';
import '../../core/theme/tokens.dart';
import '../../models/models.dart';
import '../../state/achievements.dart';
import '../../state/auth.dart';
import '../../state/first_steps.dart';
import '../../state/profile.dart';
import '../../state/progress.dart';
import '../../widgets/glass.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';
import '../home/guided_start.dart';
import 'achievement_order.dart';
import 'avatar_picker.dart';
import 'stats.dart';

/// Profile: identity, stats, achievements and shortcuts.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  /// Achievement order, fixed while the player is on the screen so a card
  /// never moves under the finger after a claim. Recomputed when the page
  /// comes back into view: another tab or a page pushed on top hides it,
  /// which turns its tickers off.
  List<String>? _achievementOrder;
  bool _visible = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = TickerMode.valuesOf(context).enabled;
    if (visible && !_visible) _achievementOrder = null;
    _visible = visible;
  }

  /// The live statuses in the frozen order. The order is only fixed once the
  /// progress rows have settled, so it is not taken from an empty save.
  List<AchievementStatus> _orderedAchievements(List<AchievementStatus> live) {
    final order = _achievementOrder ?? achievementOrder(live);
    final rows = ref.read(progressProvider);
    if (_achievementOrder == null && (rows.hasValue || rows.hasError)) _achievementOrder = order;
    return applyAchievementOrder(live, order);
  }

  Future<void> _editName(BuildContext context, WidgetRef ref, Profile p) async {
    final controller = TextEditingController(text: p.displayName);
    // The alert's own field (filled, no outline), as in every alert that asks for text.
    final ok = await showAppAlert(
      context,
      title: 'Your name',
      confirmLabel: 'Save',
      canConfirm: () => controller.text.trim().isNotEmpty,
      child: AlertTextField(controller: controller, placeholder: 'Name', maxLength: 20, textCapitalization: TextCapitalization.words),
    );
    final name = ok ? controller.text.trim() : null;
    if (name == null || name.isEmpty) return;
    if (NameFilter.isRefused(name)) {
      if (context.mounted) showToast(context, 'That name is not allowed. Choose another one.', icon: AppIcons.report);
      return;
    }
    await ref.read(profileProvider.notifier).setIdentity(name: name);
    try {
      await ref.read(authProvider.notifier).updateName(name);
    } catch (_) {}
  }

  /// Every statistic (boosters, packs, events, quests, best times by mode) in a tall sheet. The
  /// sheet scrolls it, and a drag down at its top closes the sheet (owner, 2026-10-18).
  void _showAllStatistics(BuildContext context) {
    showAppSheet(
      context,
      builder: (ctx) => Consumer(
        builder: (ctx, ref, _) => Padding(
          key: const ValueKey('statistics-sheet'),
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SheetHeader(title: 'Statistics', subtitle: 'Everything you have played so far'),
              const SizedBox(height: 14),
              StatisticsSection(stats: ref.watch(playerStatsProvider)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final profile = ref.watch(profileProvider).value;
    final user = ref.watch(authProvider).value;
    final isGuest = ref.watch(isGuestProvider);
    if (profile == null) return const Scaffold(body: Loader());
    final achievements = _orderedAchievements(ref.watch(achievementsProvider));
    final totalSteps = achievements.fold<int>(0, (s, a) => s + a.family.steps.length);
    final claimedSteps = achievements.fold<int>(0, (s, a) => s + a.claimedSteps);
    final readyToClaim = achievements.where((a) => a.done).length;
    // The guided start keeps achievements back until level 5: one card says when, with "Unlock anyway".
    final achievementsOpen = ref.watch(revealsProvider).contains(Reveal.achievements);
    final wide = context.isExpanded;
    final Widget profileCard = SoftCard(
      padding: Insets.card,
      child: Column(
        children: [
          Row(
            children: [
              Pressable(
                onTap: () => showAvatarPicker(context),
                child: AvatarCircle(avatarKey: profile.avatar, size: 72, border: true),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Pressable(
                      onTap: () => _editName(context, ref, profile),
                      child: Row(
                        children: [
                          Flexible(child: Text(profile.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.headlineSmall)),
                          const SizedBox(width: 6),
                          Icon(AppIcons.pencil, color: c.textTertiary, size: 16),
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Flexible(child: Text(isGuest ? 'Guest account' : (user?.email ?? ''), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.textSecondary, fontSize: TypeSize.footnote))),
                        if (profile.isVip) ...[
                          const SizedBox(width: 8),
                          Chip2(label: 'VIP', icon: AppIcons.vip, color: c.accentTint, foreground: context.accent),
                        ],
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Large text: the level and its XP on one line, the bar under them.
                    if (A11y.largeText(context)) ...[
                      Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text('Level ${profile.level}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: TypeSize.footnote)),
                          Text('${formatCount(profile.xpIntoLevel)}/${formatCount(Profile.xpForLevel(profile.level))}', style: TextStyle(color: c.textSecondary, fontSize: TypeSize.micro, fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ProgressBar(value: profile.levelProgress, height: 6),
                    ] else
                    Row(
                      children: [
                        Text('Level ${profile.level}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: TypeSize.footnote)),
                        const SizedBox(width: 8),
                        Expanded(child: ProgressBar(value: profile.levelProgress, height: 6)),
                        const SizedBox(width: 8),
                        Text('${formatCount(profile.xpIntoLevel)}/${formatCount(Profile.xpForLevel(profile.level))}', style: TextStyle(color: c.textSecondary, fontSize: TypeSize.micro, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(height: 1, color: c.stroke),
          const SizedBox(height: 12),
          // The wallet: three columns split by hairlines. The streak lives in Statistics
          // (and on Home), so each balance gets a third of the card at full size; from
          // 100,000 a balance is written short ("235K", "1.2M") and keeps that size.
          IntrinsicHeight(
            child: Row(
              children: [
                _Stat(value: compactCount(profile.coins), label: 'Coins', icon: const CoinIcon(size: 14)),
                VerticalDivider(width: 1, thickness: 1, color: c.stroke),
                _Stat(value: compactCount(profile.tickets), label: 'Tickets', icon: const TicketIcon(size: 13)),
                VerticalDivider(width: 1, thickness: 1, color: c.stroke),
                _Stat(value: compactCount(profile.hints), label: 'Hints', icon: const HintIcon(size: 14)),
              ],
            ),
          ),
        ],
      ),
    );
    final saveButton = BigButton(label: 'Save progress · create account', icon: AppIcons.save, onTap: () => context.push('/account'));
    final achievementsHeader = SliverToBoxAdapter(
      child: SectionHeader(
        title: 'Achievements',
        subtitle: readyToClaim > 0 ? '$claimedSteps of $totalSteps claimed · $readyToClaim ready' : '$claimedSteps of $totalSteps claimed',
      ),
    );
    final claimAll = SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
        child: _ClaimAllCard(ready: [for (final a in achievements) if (a.done) a]),
      ),
    );
    return Scaffold(
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          GlassSliverHeader(
            height: 52,
            child: Padding(
              padding: EdgeInsets.fromLTRB(20 + pageInsetOf(context), 4, 20 + pageInsetOf(context), 4),
              child: Row(
                children: [
                  const Expanded(child: PageTitle('Profile')),
                  RoundIconButton(icon: AppIcons.gearAltFill, onTap: () => context.go('/profile/settings')),
                ],
              ),
            ),
          ),
          SliverPage(
            slivers: [
              if (wide) ...[
                // The website layout: who the player is and the way to everything else beside the
                // statistics; the achievements in two columns under them.
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 5,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              profileCard,
                              if (isGuest) ...[const SizedBox(height: 12), saveButton],
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 7,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SectionHeader(title: 'Statistics', action: 'See all', onAction: () => _showAllStatistics(context), padding: const EdgeInsets.fromLTRB(0, 2, 0, 12)),
                              StatisticsSection(stats: ref.watch(playerStatsProvider), compact: true),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (!achievementsOpen) ...[
                  const SliverToBoxAdapter(child: SectionHeader(title: 'Achievements')),
                  const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: LockedSectionCard(reveal: Reveal.achievements))),
                ] else ...[
                achievementsHeader,
                if (readyToClaim > 1) claimAll,
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var col = 0; col < 2; col++) ...[
                          if (col > 0) const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              children: [
                                for (var i = col; i < achievements.length; i += 2) ...[
                                  if (i > col) const SizedBox(height: 8),
                                  _AchievementCard(key: ValueKey(achievements[i].family.id), status: achievements[i]),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                ],
              ] else ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: profileCard,
                  ),
                ),
                if (isGuest)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      child: saveButton,
                    ),
                  ),
                SliverToBoxAdapter(child: SectionHeader(title: 'Statistics', action: 'See all', onAction: () => _showAllStatistics(context))),
                SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: StatisticsSection(stats: ref.watch(playerStatsProvider), compact: true))),
                if (!achievementsOpen) ...[
                  const SliverToBoxAdapter(child: SectionHeader(title: 'Achievements')),
                  const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: LockedSectionCard(reveal: Reveal.achievements))),
                ] else ...[
                  achievementsHeader,
                  if (readyToClaim > 1) claimAll,
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    sliver: SliverList.separated(
                      itemCount: achievements.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _AchievementCard(key: ValueKey(achievements[i].family.id), status: achievements[i]),
                    ),
                  ),
                ],
              ],
            ],
          ),
          SliverToBoxAdapter(child: SizedBox(height: GlassTabBar.scrollEndPadding(context))),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, required this.icon});
  final String value;
  final String label;
  final Widget icon;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Expanded(
      child: Column(
        children: [
          FittedBox(fit: BoxFit.scaleDown, child: Text(value, maxLines: 1, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: TypeSize.headline, letterSpacing: -0.3))),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              icon,
              const SizedBox(width: 4),
              Text(label, style: TextStyle(color: c.textSecondary, fontSize: TypeSize.micro, fontWeight: FontWeight.w500)),
            ],
          ),
        ],
      ),
    );
  }
}

/// "12 rewards ready": what the ready tiers pay together, and one button that claims them all
/// (including the next tiers they unlock that are already reached).
class _ClaimAllCard extends ConsumerStatefulWidget {
  const _ClaimAllCard({required this.ready});
  final List<AchievementStatus> ready;
  @override
  ConsumerState<_ClaimAllCard> createState() => _ClaimAllCardState();
}

class _ClaimAllCardState extends ConsumerState<_ClaimAllCard> {
  bool _busy = false;

  Future<void> _claimAll() async {
    setState(() => _busy = true);
    final notifier = ref.read(profileProvider.notifier);
    var coins = 0, tickets = 0, avatars = 0, count = 0;
    // Claiming a tier can make the next tier ready too: keep going until none is left.
    for (var guard = 0; guard < 200; guard++) {
      final next = ref.read(achievementsProvider).where((a) => a.done).firstOrNull;
      final step = next?.step;
      if (next == null || step == null) break;
      final ok = await notifier.claimAchievement(next.stepKey, coins: step.coins, tickets: step.tickets, avatar: step.avatarKey);
      if (!ok) break;
      AppAnalytics.event('achievement_claimed', {'achievement': next.stepKey, 'claimAll': true});
      count++;
      coins += step.coins;
      tickets += step.tickets;
      if (step.avatarKey != null) avatars++;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (count == 0) return;
    Sfx.instance.coin();
    Haptics.success();
    final parts = [
      if (coins > 0) '${formatCount(coins)} coins',
      if (tickets > 0) countOf(tickets, 'ticket'),
      if (avatars > 0) '$avatars avatar${avatars == 1 ? '' : 's'}',
    ];
    showToast(context, '$count rewards claimed: ${parts.join(', ')}', icon: AppIcons.check);
  }

  @override
  Widget build(BuildContext context) {
    var coins = 0, tickets = 0, avatars = 0;
    for (final a in widget.ready) {
      coins += a.step?.coins ?? 0;
      tickets += a.step?.tickets ?? 0;
      if (a.step?.avatarKey != null) avatars++;
    }
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${widget.ready.length} rewards ready', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: TypeSize.body)),
                const SizedBox(height: 6),
                // Together, in the level card's reward marks.
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (coins > 0) RewardChip.amount(currency: Currency.coins, value: coins),
                    if (tickets > 0) RewardChip.amount(currency: Currency.tickets, value: tickets),
                    if (avatars > 0) RewardChip.unlock(leading: Icon(AppIcons.personCropCircle, size: 14, color: context.accent), label: countOf(avatars, 'avatar')),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          BigButton(label: 'Claim all', height: 36, expand: false, loading: _busy, onTap: _claimAll),
        ],
      ),
    );
  }
}

class _AchievementCard extends ConsumerWidget {
  const _AchievementCard({super.key, required this.status});
  final AchievementStatus status;

  Future<void> _claim(BuildContext context, WidgetRef ref) async {
    final step = status.step;
    if (step == null) return;
    final ok = await ref.read(profileProvider.notifier).claimAchievement(status.stepKey, coins: step.coins, tickets: step.tickets, avatar: step.avatarKey);
    if (ok) AppAnalytics.event('achievement_claimed', {'achievement': status.stepKey, 'claimAll': false});
    if (!ok || !context.mounted) return;
    Sfx.instance.coin();
    Haptics.success();
    showToast(context, step.avatarKey != null ? 'New avatar unlocked' : 'Reward claimed', icon: AppIcons.check);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final f = status.family;
    final step = status.step;
    final all = status.allClaimed;
    final done = status.done;
    final ratio = all ? 1.0 : (status.progress / status.target).clamp(0.0, 1.0);
    // Compact, in the quests' checklist language: the icon in a progress ring (the bar), the title
    // with its tier dots and the one fraction, the description, then the next tier's reward as
    // chips. Claim sits alone on the right once the tier is reached; a finished family keeps two
    // lines.
    // Cobalt while it runs and once ready (the colour of its Claim button); green when every tier is in.
    final tone = all ? c.success : context.accent;
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
      child: Row(
        children: [
          SizedBox(
            width: 42,
            height: 42,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.expand(child: CircularProgressIndicator(value: ratio, strokeWidth: 3, strokeCap: StrokeCap.round, backgroundColor: c.stroke, color: tone)),
                Icon(all ? AppIcons.checkmarkAlt : f.icon, size: 18, color: (all || done) ? tone : c.textSecondary),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The title, then one dot per tier (filled once claimed) instead of a second fraction.
                Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          // Up to two lines with a large text size, so the title is never cut to a few letters.
                          Flexible(child: Text(f.title, maxLines: A11y.largeText(context) ? 2 : 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: TypeSize.body))),
                          if (f.steps.length > 1) ...[const SizedBox(width: 8), _TierDots(claimed: status.claimedSteps, total: f.steps.length)],
                        ],
                      ),
                    ),
                    // The one fraction, at the end of the title line, while the tier runs.
                    if (!done && !all) ...[
                      const SizedBox(width: 8),
                      Text(
                        '${formatCount(status.progress.clamp(0, status.target))} / ${formatCount(status.target)}',
                        style: TextStyle(fontSize: TypeSize.footnote, color: c.textSecondary, fontWeight: FontWeight.w600, fontFeatures: tabularFigures),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(all ? 'Every tier claimed' : status.description, style: TextStyle(fontSize: TypeSize.footnote, color: c.textSecondary)),
                if (!all) ...[
                  const SizedBox(height: 8),
                  // What the next tier pays, in the level card's reward chips.
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (step!.coins > 0) RewardChip.amount(currency: Currency.coins, value: step.coins),
                      if (step.tickets > 0) RewardChip.amount(currency: Currency.tickets, value: step.tickets),
                      if (step.avatarKey != null) RewardChip.unlock(leading: AvatarCircle(avatarKey: step.avatarKey, size: 16), label: 'Avatar'),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (done) ...[
            const SizedBox(width: 12),
            BigButton(label: 'Claim', height: 34, expand: false, onTap: () => _claim(context, ref)),
          ],
        ],
      ),
    );
  }
}

/// One small dot per tier of an achievement, filled for the tiers already claimed.
class _TierDots extends StatelessWidget {
  const _TierDots({required this.claimed, required this.total});
  final int claimed;
  final int total;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label: 'Tier ${claimed.clamp(0, total)} of $total claimed',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < total; i++)
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(right: 3),
              // Differentiate without colour: unclaimed tiers are rings, claimed ones filled.
              decoration: A11y.symbolsOf(context) && i >= claimed
                  ? BoxDecoration(shape: BoxShape.circle, border: Border.all(color: c.textTertiary, width: 1.2))
                  : BoxDecoration(shape: BoxShape.circle, color: i < claimed ? context.accent : c.stroke),
            ),
        ],
      ),
    );
  }
}
