import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/haptics.dart';
import '../../core/sfx.dart';
import '../../core/a11y.dart';
import '../../core/theme/tokens.dart';
import '../../models/models.dart';
import '../../state/catalog.dart';
import '../../state/first_steps.dart';
import '../../state/profile.dart';
import '../../state/progress.dart';
import '../../state/rewards.dart';
import '../../state/settings.dart';
import '../../state/social.dart';
import '../../state/unlocks.dart';
import '../../game/board.dart';
import '../../widgets/glass.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';
import '../gallery/pack_progress.dart';
import '../home/guided_start.dart';
import '../home/header_bar.dart';
import 'quest_rewards.dart';

/// Quests tab: daily quests, weekly quests, then live events.
class EventsScreen extends ConsumerStatefulWidget {
  const EventsScreen({super.key});

  @override
  ConsumerState<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends ConsumerState<EventsScreen> {
  /// Ticks the "Resets in" chips (and re-rolls the quests at midnight).
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final events = ref.watch(eventsProvider);
    final eventProgress = ref.watch(eventProgressProvider).value ?? {};
    final progress = ref.watch(progressProvider).value ?? {};
    final now = DateTime.now();
    final profile = ref.watch(profileProvider).value;
    final open = ref.watch(openFeaturesProvider);
    final dailyPuzzle = ref.watch(dailyPuzzleProvider)?.id;
    // Guided start: only pictures finished after Quests opened count.
    final since = ref.watch(countsFromProvider(Reveal.quests));
    final quests = questsFor(progress.values, profile, open, now, dailyPuzzle: dailyPuzzle, since: since);
    final daily = quests.daily, weekly = quests.weekly;
    final readyQuests = readyGoals(progress.values, profile, open, now, dailyPuzzle: dailyPuzzle, since: since);
    final readyEvents = ref.watch(readyEventsProvider);
    final eventsOpen = ref.watch(revealsProvider).contains(Reveal.liveEvents);
    // Swaps are a swipe: one line under the daily quests says so until the player swipes one.
    bool swappable(List<Goal> goals, int free) => goals.indexed.any((e) => e.$2.swap != null && !goalLocked(e.$2, e.$1, free, profile));
    final swipeHint = !ref.watch(questSwipeLearnedProvider) && (swappable(daily, Goals.dailyFree) || swappable(weekly, Goals.weeklyFree));
    // The website layout: daily and weekly quests side by side, the live events beside what is
    // coming up.
    final wide = context.isExpanded;
    final dailyHeader = SectionHeader(
      title: 'Daily quests',
      subtitle: 'Coins · new every day',
      trailing: _ResetsIn(at: Goals.nextDailyReset(now), now: now),
      padding: EdgeInsets.fromLTRB(wide ? 0 : 20, 20, wide ? 0 : 20, 12),
    );
    final weeklyHeader = SectionHeader(
      title: 'Weekly quests',
      subtitle: 'Tickets · new every week',
      trailing: _ResetsIn(at: Goals.nextWeeklyReset(now), now: now),
      padding: wide ? const EdgeInsets.fromLTRB(0, 20, 0, 12) : const EdgeInsets.fromLTRB(20, 28, 20, 12),
    );
    Widget side(List<Widget> left, List<Widget> right) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: left)),
              const SizedBox(width: 16),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: right)),
            ],
          ),
        );

    return Scaffold(
      body: RefreshIndicator.adaptive(
        edgeOffset: MediaQuery.paddingOf(context).top + HeaderBar.height,
        onRefresh: () async {
          ref.invalidate(catalogProvider);
          ref.invalidate(eventProgressProvider);
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          slivers: [
            const HeaderBar(title: 'Quests', contentWidth: PageWidth.reading),
            SliverPage(
              maxWidth: wide ? PageWidth.wide : PageWidth.reading,
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                    child: const PageTitle('Quests'),
                  ),
                ),
                // Two or more rewards waiting: one tap claims them all.
                if (readyQuests.length + readyEvents.length >= 2)
                  SliverToBoxAdapter(child: _ClaimAllCard(goals: readyQuests, events: readyEvents)),
                if (wide)
                  SliverToBoxAdapter(
                    child: side(
                      [dailyHeader, _GoalList(goals: daily, freeCount: Goals.dailyFree, inset: 0), if (swipeHint) const QuestSwipeHint(inset: 0)],
                      [weeklyHeader, _GoalList(goals: weekly, freeCount: Goals.weeklyFree, weekly: true, inset: 0)],
                    ),
                  )
                else ...[
                  SliverToBoxAdapter(child: dailyHeader),
                  SliverToBoxAdapter(child: _GoalList(goals: daily, freeCount: Goals.dailyFree)),
                  if (swipeHint) const SliverToBoxAdapter(child: QuestSwipeHint()),
                  SliverToBoxAdapter(child: weeklyHeader),
                  SliverToBoxAdapter(child: _GoalList(goals: weekly, freeCount: Goals.weeklyFree, weekly: true)),
                ],
                if (!wide) const SliverToBoxAdapter(child: SectionHeader(title: 'Live events', subtitle: 'World-day events, one week each')),
                // Guided start: live events open after 35 pictures; one card says so, with Unlock anyway.
                if (!eventsOpen)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(20, wide ? 28 : 0, 20, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (wide) const SectionHeader(title: 'Live events', subtitle: 'World-day events, one week each', padding: EdgeInsets.fromLTRB(0, 0, 0, 12)),
                          const LockedSectionCard(reveal: Reveal.liveEvents),
                        ],
                      ),
                    ),
                  )
                else
                events.when(
                  loading: () => const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(40), child: Loader())),
                  error: (e, _) => const SliverToBoxAdapter(child: EmptyState(icon: AppIcons.signal, title: 'Events could not load', message: 'Check your connection and pull to refresh.')),
                  data: (list) {
                    final active = list.where((e) => e.isActive).toList();
                    final upcoming = list.where((e) => e.isUpcoming).toList()..sort((a, b) => a.startAt!.compareTo(b.startAt!));
                    if (active.isEmpty && upcoming.isEmpty) {
                      return SliverToBoxAdapter(
                        child: Column(
                          children: [
                            if (wide) const SectionHeader(title: 'Live events', subtitle: 'World-day events, one week each'),
                            const EmptyState(icon: AppIcons.balloon, title: 'No events this week', message: 'New world-day events open every few days.'),
                          ],
                        ),
                      );
                    }
                    if (wide) {
                      const live = SectionHeader(title: 'Live events', subtitle: 'World-day events, one week each', padding: EdgeInsets.fromLTRB(0, 28, 0, 12));
                      return SliverToBoxAdapter(
                        child: side(
                          [
                            live,
                            for (var i = 0; i < active.length; i++) ...[
                              if (i > 0) const SizedBox(height: 12),
                              _EventCard(event: active[i], progress: eventProgress[active[i].id]),
                            ],
                            if (active.isEmpty)
                              SoftCard(
                                padding: Insets.cardCompact,
                                child: Text('Nothing live right now. The next event opens soon.', style: TextStyle(color: context.colors.textSecondary, fontSize: TypeSize.footnote)),
                              ),
                          ],
                          [
                            if (upcoming.isNotEmpty) ...[
                              const SectionHeader(title: 'Coming up', subtitle: 'Each event opens three days before its day', padding: EdgeInsets.fromLTRB(0, 28, 0, 12)),
                              SoftCard(
                                padding: EdgeInsets.zero,
                                child: Column(
                                  children: [
                                    for (var i = 0; i < upcoming.length; i++) ...[
                                      _UpcomingRow(event: upcoming[i]),
                                      if (i < upcoming.length - 1) Divider(height: 1, color: context.colors.stroke, indent: 76),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    }
                    return SliverList(
                      delegate: SliverChildListDelegate([
                        for (var i = 0; i < active.length; i++)
                          Padding(
                            padding: EdgeInsets.fromLTRB(20, i == 0 ? 0 : 12, 20, 0),
                            child: _EventCard(event: active[i], progress: eventProgress[active[i].id]),
                          ),
                        if (active.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: SoftCard(
                              padding: Insets.cardCompact,
                              child: Text('Nothing live right now. The next event opens soon.', style: TextStyle(color: context.colors.textSecondary, fontSize: TypeSize.footnote)),
                            ),
                          ),
                        if (upcoming.isNotEmpty) ...[
                          const SectionHeader(title: 'Coming up', subtitle: 'Each event opens three days before its day'),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: SoftCard(
                              padding: EdgeInsets.zero,
                              child: Column(
                                children: [
                                  for (var i = 0; i < upcoming.length; i++) ...[
                                    _UpcomingRow(event: upcoming[i]),
                                    if (i < upcoming.length - 1) Divider(height: 1, color: context.colors.stroke, indent: 76),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ],
                      ]),
                    );
                  },
                ),
              ],
            ),
            SliverToBoxAdapter(child: SizedBox(height: GlassTabBar.scrollEndPadding(context))),
          ],
        ),
      ),
    );
  }
}

/// "Resets in 5h 12m" chip next to a quest section header.
class _ResetsIn extends StatelessWidget {
  const _ResetsIn({required this.at, required this.now});
  final DateTime at;
  final DateTime now;

  @override
  Widget build(BuildContext context) => Chip2(label: 'Resets in ${Goals.formatLeft(at.difference(now))}', icon: AppIcons.time);
}

class _GoalList extends ConsumerWidget {
  const _GoalList({required this.goals, required this.freeCount, this.weekly = false, this.inset = 20});
  final List<Goal> goals;
  final bool weekly;

  /// Side margin (none inside a column of the website layout, which has its own).
  final double inset;
  /// Quests past this index are VIP-only: locked cards for everyone else.
  final int freeCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final profile = ref.watch(profileProvider).value;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: inset),
      child: SoftCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            for (var i = 0; i < goals.length; i++) ...[
              () {
                final claimed = profile?.claimedGoals.contains(goals[i].key) ?? false;
                return goalLocked(goals[i], i, freeCount, profile) ? _VipGoalRow(weekly: weekly) : _GoalRow(goal: goals[i], claimed: claimed);
              }(),
              if (i < goals.length - 1) Divider(height: 1, color: c.stroke, indent: 16),
            ],
          ],
        ),
      ),
    );
  }
}

/// What non-VIP players see in place of the extra quest: an invitation, not the quest. One
/// checklist row in the style of the others (a ring with the VIP mark), "One more quest every day"
/// (or week) and "With VIP", leading to the Store's VIP card. The quest itself, its goal and its
/// reward stay out of sight until the player is a member.
class _VipGoalRow extends StatelessWidget {
  const _VipGoalRow({required this.weekly});
  final bool weekly;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Pressable(
      key: ValueKey(weekly ? 'quest-vip-weekly' : 'quest-vip-daily'),
      onTap: () => context.push('/store?vip=1'),
      scale: 0.99,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(shape: BoxShape.circle, color: c.accentTint),
              child: Icon(AppIcons.vip, size: 18, color: context.accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(weekly ? 'One more quest every week' : 'One more quest every day', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: TypeSize.body)),
                  const SizedBox(height: 3),
                  Text('Included with VIP', style: TextStyle(fontSize: TypeSize.caption, fontWeight: FontWeight.w600, color: context.accent)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(AppIcons.chevronRight, size: 15, color: c.textTertiary),
          ],
        ),
      ),
    );
  }
}

class _GoalRow extends ConsumerWidget {
  const _GoalRow({required this.goal, required this.claimed});
  final Goal goal;
  final bool claimed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    Future<void> claim() async {
      final ok = await ref.read(profileProvider.notifier).claimGoal(goal);
      if (ok) questClaimed(goal, all: false);
      if (!context.mounted || !ok) return;
      Sfx.instance.coin();
      Haptics.success();
      final what = goal.coins > 0 ? countOf(goal.coins, 'coin') : countOf(goal.tickets, 'ticket');
      showToast(context, 'Claimed $what', icon: AppIcons.check);
    }

    void play() {
      if (goal.puzzleId != null) {
        context.push('/play/${goal.puzzleId}');
        return;
      }
      final p = pickRandomPlayable(ref);
      if (p != null) {
        final grid = goal.minCells > 0 ? GridSpec.atLeast(goal.minCells).code : '';
        context.push('/play/${p.id}?grid=$grid${goal.mode != null ? '&mode=${goal.mode!.code}' : ''}${goal.painting ? '&painting=1' : ''}');
      } else {
        showToast(context, 'Unlock a pack to start playing', icon: AppIcons.lock);
      }
    }

    // Swapped for another for a ticket (a swipe to the left, or the VoiceOver action), asked first;
    // short of tickets, the store.
    Future<void> swap() async {
      final next = goal.swap;
      if (next == null) return;
      ref.read(questSwipeLearnedProvider.notifier).learn();
      final tickets = ref.read(profileProvider).value?.tickets ?? 0;
      if (tickets < QuestSwap.tickets) {
        Sfx.instance.error();
        showToast(context, 'Not enough tickets. Finish weekly quests or level up to earn more.', leading: const TicketIcon(size: 20));
        context.push('/store');
        return;
      }
      final sure = await showAppAlert(
        context,
        title: 'Swap this quest?',
        message: '“${goal.title}” becomes “${next.nextTitle}”, for the same reward. This costs ${countOf(QuestSwap.tickets, 'ticket')}. You have ${formatCount(tickets)}.',
        confirmLabel: 'Swap for ${countOf(QuestSwap.tickets, 'ticket')}',
      );
      if (!sure || !context.mounted) return;
      if (!await ref.read(profileProvider.notifier).swapQuest(goal)) return;
      questSwapped(goal, next);
      if (!context.mounted) return;
      Haptics.success();
      showToast(context, 'Quest swapped', icon: AppIcons.check);
    }

    final ready = goal.done && !claimed;
    final currency = goal.coins > 0 ? Currency.coins : Currency.tickets;
    final amount = goal.coins > 0 ? goal.coins : goal.tickets;
    final status = claimed ? 'Claimed' : (ready ? 'Ready to claim' : (goal.target > 1 ? '${goal.progress.clamp(0, goal.target)} of ${goal.target}' : 'Not done yet'));

    // A checklist row: progress ring with the quest's icon, the quest, its reward and status; the
    // only button is Claim. An open quest is a tap target that starts a fitting board, and swipes
    // left to be swapped (as a friend swipes away on Social).
    final row = Pressable(
      onTap: ready ? claim : (claimed ? null : play),
      scale: 0.99,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
        child: Row(
          children: [
            _QuestRing(value: claimed ? 1 : goal.progress / goal.target, done: claimed || goal.done, icon: claimed ? AppIcons.checkmarkAlt : _questIcon(goal.icon)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(goal.title, style: TextStyle(fontWeight: FontWeight.w600, fontSize: TypeSize.body, color: claimed ? c.textSecondary : c.textPrimary)),
                  const SizedBox(height: 3),
                  // Wraps the status under the reward when a large text size leaves no room.
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Opacity(opacity: claimed ? 0.5 : 1, child: Amount(currency: currency, value: amount, prefix: '+', size: 13, fontSize: TypeSize.caption, weight: FontWeight.w700)),
                      Text('  ·  $status', style: TextStyle(fontSize: TypeSize.caption, color: ready ? c.success : c.textSecondary, fontWeight: ready ? FontWeight.w600 : FontWeight.w500)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (ready)
              BigButton(label: 'Claim', height: 34, expand: false, onTap: claim)
            else if (!claimed)
              Icon(AppIcons.chevronRight, size: 15, color: c.textTertiary),
          ],
        ),
      ),
    );
    final s = goal.swap;
    if (s == null || ready || claimed) return row;
    // The swipe goes as far as the action, which asks first; the row then slides back, showing the
    // quest that came (or the same one, cancelled). VoiceOver: the row's "Swap for 1 ticket" action.
    return Semantics(
      customSemanticsActions: {CustomSemanticsAction(label: 'Swap for ${countOf(QuestSwap.tickets, 'ticket')}'): () => swap()},
      child: Dismissible(
        key: ValueKey('quest-swap-${s.slot}'),
        direction: DismissDirection.endToStart,
        // Reduce motion: the row jumps out and back instead of sliding (the swipe itself follows the finger).
        movementDuration: A11y.reduceMotionOf(context) ? Duration.zero : const Duration(milliseconds: 200),
        background: const _SwapAction(),
        confirmDismiss: (_) async {
          await swap();
          return false;
        },
        child: ColoredBox(color: c.card, child: row),
      ),
    );
  }
}

/// What a quest shows as it is swiped left: the swap and its price, white on the accent.
class _SwapAction extends StatelessWidget {
  const _SwapAction();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        color: context.accentFill,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(AppIcons.swaps, size: 20, color: context.onAccent),
            const SizedBox(height: 4),
            CostLabel(label: 'Swap', currency: Currency.tickets, amount: QuestSwap.tickets, color: context.onAccent, fontSize: TypeSize.footnote),
          ],
        ),
      ),
    );
  }
}

/// Under the daily quests until the player first swipes one: how a quest is swapped. Two lines at
/// most on a 390 pt iPhone, as every hint (test/hint_lines_test.dart).
class QuestSwipeHint extends StatelessWidget {
  const QuestSwipeHint({super.key, this.inset = 20});

  /// Side margin, as the quest list's.
  final double inset;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      key: const ValueKey('quest-swipe-hint'),
      padding: EdgeInsets.fromLTRB(inset + 4, 10, inset + 4, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 2), child: Icon(AppIcons.swaps, size: 14, color: c.textTertiary)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Swipe left on a quest to swap it for another. A swap costs ${countOf(QuestSwap.tickets, 'ticket')}.',
              style: TextStyle(fontSize: TypeSize.footnote, color: c.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// The player has swiped a quest once: the line under the daily quests that explains swaps is gone
/// (on this device).
final questSwipeLearnedProvider = NotifierProvider<QuestSwipeLearned, bool>(QuestSwipeLearned.new);

class QuestSwipeLearned extends Notifier<bool> {
  @override
  bool build() => ref.read(localStoreProvider).questSwipeSeen;

  void learn() {
    if (state) return;
    ref.read(localStoreProvider).questSwipeSeen = true;
    state = true;
  }
}

/// Icon for a quest's kind (`Goal.icon`).
IconData _questIcon(String name) => switch (name) {
      'star' => AppIcons.star,
      'eye' => AppIcons.peek,
      'swaps' => AppIcons.swaps,
      // "Lock 5 cards in one move": a big move, not a locked quest.
      'lock' => AppIcons.sparkle,
      'streak' => AppIcons.streak,
      'bigBoard' => AppIcons.bigBoard,
      'painting' => AppIcons.painting,
      // "Solve a 4x4 board in under 1:30": the time to beat.
      'time' => AppIcons.timer,
      'dailyPuzzle' => AppIcons.dailyPuzzle,
      _ => AppIcons.puzzle,
    };

/// Progress ring around a quest's icon: accent while running, success green once done.
class _QuestRing extends StatelessWidget {
  const _QuestRing({required this.value, required this.done, required this.icon});
  final double value;
  final bool done;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = done ? c.success : context.accent;
    return SizedBox(
      width: 38,
      height: 38,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.expand(
            child: CircularProgressIndicator(value: value.clamp(0.0, 1.0), strokeWidth: 3, strokeCap: StrokeCap.round, backgroundColor: c.stroke, color: tone),
          ),
          Icon(icon, size: 17, color: done ? tone : c.textSecondary),
        ],
      ),
    );
  }
}

class _EventCard extends ConsumerWidget {
  const _EventCard({required this.event, required this.progress});
  final GameEvent event;
  final EventProgress? progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    // A pack event asks for every picture in its pack (N of N). The counts
    // come from packProgressProvider, the same source as the library cards;
    // the backend counter is the fallback for events without a pack
    // (community goals).
    final pack = _packProgress(ref, event);
    final isPackQuest = pack != null;
    final (value, target) = eventProgressOf(pack, event, progress);
    final done = value >= target;
    final claimed = progress?.claimed ?? false;
    final description = isPackQuest ? 'Finish all $target pictures in the ${event.name} pack while the event is live.' : event.description;
    // Same wording as the event tiles on Home and the event pack page.
    final left = event.timeLeft;
    final leftLabel = endsIn(left);
    final community = event.type == EventType.social ? ref.watch(communityProgressProvider(event.id)).value : null;

    Future<void> claim() async {
      if (!await claimEventReward(ref, event, value) || !context.mounted) return;
      Sfx.instance.win();
      Haptics.success();
      showToast(context, 'Claimed ${countOf(event.rewardCoins, 'coin')}${event.rewardTickets > 0 ? ' and ${countOf(event.rewardTickets, 'ticket')}' : ''}', icon: AppIcons.check);
    }

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(Radii.lg), border: Border.all(color: c.stroke)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 150,
            child: Stack(
              fit: StackFit.expand,
              children: [
                NetImage(url: event.coverUrl, blurhash: _coverHash(ref, event)),
                DecoratedBox(decoration: BoxDecoration(gradient: Brand.scrim(strength: 0.7, contrast: A11y.increaseContrastOf(context)))),
                Positioned(
                  left: 14,
                  top: 12,
                  child: Chip2(label: leftLabel, onImage: true, dot: Brand.live),
                ),
                if (isPackQuest && pack.complete) Positioned(right: 14, top: 12, child: PackDoneBadges(progress: pack)),
                Positioned(
                  left: 16,
                  bottom: 12,
                  right: 16,
                  child: Text(event.name, style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: Colors.white)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(description, style: TextStyle(color: c.textSecondary, fontSize: TypeSize.footnote, height: 1.4)),
                const SizedBox(height: 12),
                if (isPackQuest)
                  PackProgressLine(progress: pack, height: 8, fontSize: TypeSize.footnote)
                else
                  Row(
                    children: [
                      Expanded(child: ProgressBar(value: target == 0 ? 0 : value / target, height: 8, color: done ? c.success : null)),
                      const SizedBox(width: 10),
                      Text('$value / $target', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: TypeSize.footnote)),
                    ],
                  ),
                if (community != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(AppIcons.community, size: 14, color: c.textSecondary),
                      const SizedBox(width: 6),
                      Text('$community puzzles solved by everyone', style: TextStyle(fontSize: TypeSize.caption, fontWeight: FontWeight.w500, color: c.textSecondary)),
                    ],
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Amount(currency: Currency.coins, value: event.rewardCoins, size: 16, fontSize: TypeSize.footnote),
                    if (event.rewardTickets > 0) ...[
                      const SizedBox(width: 12),
                      Amount(currency: Currency.tickets, value: event.rewardTickets, size: 16, fontSize: TypeSize.footnote),
                    ],
                    const Spacer(),
                    if (claimed)
                      Row(children: [Icon(AppIcons.filterFinished, color: c.success, size: 18), const SizedBox(width: 4), const Text('Claimed', style: TextStyle(fontWeight: FontWeight.w600))])
                    else if (done)
                      BigButton(label: 'Claim', expand: false, height: 38, onTap: claim)
                    else
                      BigButton(
                        label: event.packId != null ? 'Play pack' : 'Play',
                        kind: ButtonKind.secondary,
                        expand: false,
                        height: 38,
                        onTap: () => event.packId != null ? context.go('/library/pack/${event.packId}') : context.go('/library'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact row for an event that opens within the next three days.
class _UpcomingRow extends ConsumerWidget {
  const _UpcomingRow({required this.event});
  final GameEvent event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final opens = 'Opens in ${Goals.formatLeft(event.startsIn)}';
    final pack = _packProgress(ref, event);
    final showPack = pack != null;
    return Pressable(
      onTap: event.packId == null ? null : () => context.go('/library/pack/${event.packId}'),
      scale: 0.99,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
        child: Row(
          children: [
            SizedBox(
              width: 52,
              height: 52,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  NetImage(url: event.coverUrl, radius: 10, blurhash: _coverHash(ref, event)),
                  if (showPack && pack.complete) Positioned(right: 3, top: 3, child: PackDoneBadges(progress: pack, size: 18)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(event.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: TypeSize.body)),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(AppIcons.time, size: 12, color: c.textSecondary),
                      const SizedBox(width: 4),
                      Text(opens, style: TextStyle(fontSize: TypeSize.footnote, fontWeight: FontWeight.w500, color: c.textSecondary)),
                    ],
                  ),
                  if (showPack) ...[
                    const SizedBox(height: 6),
                    PackProgressLine(progress: pack, height: 4),
                  ],
                ],
              ),
            ),
            if (event.packId != null) ...[const SizedBox(width: 8), Icon(AppIcons.chevronRight, size: 14, color: c.textTertiary)],
          ],
        ),
      ),
    );
  }
}


/// Progress through the event's pack, or null for events without one
/// (community goals) and while its pictures are not in the catalogue.
PackProgress? _packProgress(WidgetRef ref, GameEvent event) {
  final packId = event.packId;
  if (packId == null || packId.isEmpty) return null;
  return ref.watch(eventPackProgressProvider(packId));
}

/// The event cover is its pack cover, so reuse the pack's BlurHash.
String? _coverHash(WidgetRef ref, GameEvent event) {
  final packs = ref.read(packsProvider).value ?? const <Pack>[];
  for (final p in packs) {
    if (p.id == event.packId) return p.blurhash;
  }
  return null;
}

/// Shown at the top of the Quests tab when two or more rewards are ready:
/// claims every finished quest and live event in one go, one toast with the
/// total.
class _ClaimAllCard extends ConsumerStatefulWidget {
  const _ClaimAllCard({required this.goals, required this.events});
  final List<Goal> goals;
  final List<({GameEvent event, int value})> events;

  @override
  ConsumerState<_ClaimAllCard> createState() => _ClaimAllCardState();
}

class _ClaimAllCardState extends ConsumerState<_ClaimAllCard> {
  bool _busy = false;

  Future<void> _claimAll() async {
    if (_busy) return;
    setState(() => _busy = true);
    var coins = 0, tickets = 0;
    final profile = ref.read(profileProvider.notifier);
    for (final g in widget.goals) {
      if (await profile.claimGoal(g)) {
        questClaimed(g, all: true);
        coins += g.coins;
        tickets += g.tickets;
      }
    }
    for (final e in widget.events) {
      if (await claimEventReward(ref, e.event, e.value)) {
        coins += e.event.rewardCoins;
        tickets += e.event.rewardTickets;
      }
    }
    if (!mounted) return;
    setState(() => _busy = false);
    Sfx.instance.win();
    Haptics.success();
    showToast(context, claimedLine(coins, tickets), icon: AppIcons.check);
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.goals.length + widget.events.length;
    final coins = widget.goals.fold<int>(0, (s, g) => s + g.coins) + widget.events.fold<int>(0, (s, e) => s + e.event.rewardCoins);
    final tickets = widget.goals.fold<int>(0, (s, g) => s + g.tickets) + widget.events.fold<int>(0, (s, e) => s + e.event.rewardTickets);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: SoftCard(
        key: const ValueKey('claim-all'),
        padding: Insets.cardCompact,
        child: Row(
          children: [
            const IconTile(icon: AppIcons.quests, size: IconTile.medium),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$count rewards ready', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: TypeSize.body)),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 10,
                    children: [
                      if (coins > 0) Amount(currency: Currency.coins, value: coins, prefix: '+', size: 14, fontSize: TypeSize.footnote),
                      if (tickets > 0) Amount(currency: Currency.tickets, value: tickets, prefix: '+', size: 14, fontSize: TypeSize.footnote),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            BigButton(label: 'Claim all', height: 36, expand: false, loading: _busy, onTap: _claimAll),
          ],
        ),
      ),
    );
  }
}
