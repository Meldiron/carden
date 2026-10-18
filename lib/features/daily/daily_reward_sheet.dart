import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/haptics.dart';
import '../../core/platform.dart';
import '../../core/reminders.dart';
import '../../core/sfx.dart';
import '../../core/a11y.dart';
import '../../core/analytics.dart';
import '../../core/theme/tokens.dart';
import '../../state/daily_gift.dart';
import '../../state/profile.dart';
import '../../state/reminders.dart';
import '../../state/settings.dart';
import '../../widgets/confetti.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';

/// The daily gift sheet. When the player claimed a gift in it, the sheet may
/// be followed by the one-time reminder question ([offerRemindersAfterGift]).
Future<void> showDailyRewardSheet(BuildContext context) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final before = container.read(localStoreProvider).giftClaimDays;
  await showAppSheet(context, builder: (_) => const DailyRewardSheet());
  if (!context.mounted || container.read(localStoreProvider).giftClaimDays == before) return;
  await offerRemindersAfterGift(context, container);
}

/// Asks once, in the game, whether the player wants a daily reminder, before
/// iOS shows its own permission prompt (see [shouldOfferReminders]). "Turn on"
/// goes on to the iOS prompt; either answer closes the question for good.
Future<void> offerRemindersAfterGift(BuildContext context, ProviderContainer container) async {
  if (!container.read(platformCapsProvider).notifications) return;
  final store = container.read(localStoreProvider);
  final settings = container.read(settingsProvider);
  final profile = container.read(profileProvider).value;
  final permission = await ReminderChannel.status();
  final offer = shouldOfferReminders(
    giftDays: store.giftClaimDays,
    streak: profile?.streak ?? 0,
    remindersOn: settings.reminders,
    offerShown: store.reminderOfferShown,
    permission: permission,
  );
  if (!offer || !context.mounted) return;
  store.reminderOfferShown = true;
  final time = TimeOfDay(hour: settings.reminderMinutes ~/ 60, minute: settings.reminderMinutes % 60).format(context);
  final yes = await showAppAlert(
    context,
    title: 'Get a daily reminder?',
    message: 'One notification a day with the daily puzzle at $time, and one the evening before a new event opens. You can change or turn off either in Settings.',
    confirmLabel: 'Turn on',
    cancelLabel: 'Not now',
  );
  if (!yes) return;
  // The question named event notes too, so Turn on is the explicit yes to them.
  container.read(eventRemindersProvider.notifier).set(true);
  final granted = await container.read(remindersProvider).enable();
  if (granted && context.mounted) showToast(context, 'Daily reminder at $time', icon: AppIcons.bellFill);
}

/// The daily gift sheet (107 B): the week as a list, every day with its full
/// gift, today's row larger than the rest. After missed days a lost streak can
/// be restored together with today's claim (001 B).
class DailyRewardSheet extends ConsumerStatefulWidget {
  const DailyRewardSheet({super.key});
  @override
  ConsumerState<DailyRewardSheet> createState() => _DailyRewardSheetState();
}

class _DailyRewardSheetState extends ConsumerState<DailyRewardSheet> {
  bool _claiming = false;
  bool _restoring = false;

  /// Restores the lost streak and claims today's gift with it.
  Future<void> _restore() async {
    final p = ref.read(profileProvider).value;
    if (p == null) return;
    final cost = Economy.streakRestoreTickets(p.streak);
    if (p.tickets < cost) {
      showToast(context, 'You need $cost tickets to restore the streak.', leading: const TicketIcon(size: 18));
      context.push('/store');
      return;
    }
    setState(() => _restoring = true);
    final r = await ref.read(profileProvider.notifier).claimDaily(restore: true);
    if (r != null) AppAnalytics.event('daily_gift_claimed', {'day': r.day + 1, 'streakRestored': true});
    if (r != null) {
      final store = ref.read(localStoreProvider);
      store.giftClaimDays = store.giftClaimDays + 1;
    }
    if (!mounted) return;
    setState(() => _restoring = false);
    if (r != null) {
      Sfx.instance.coin();
      Haptics.success();
      _celebrate();
      showToast(context, 'Streak restored', icon: AppIcons.streak);
    } else {
      showToast(context, 'The streak could not be restored right now.', icon: AppIcons.streak);
    }
  }

  Future<void> _claim() async {
    setState(() => _claiming = true);
    final r = await ref.read(profileProvider.notifier).claimDaily();
    if (r != null) AppAnalytics.event('daily_gift_claimed', {'day': r.day + 1, 'streakRestored': false});
    if (r != null) {
      final store = ref.read(localStoreProvider);
      store.giftClaimDays = store.giftClaimDays + 1;
    }
    if (!mounted) return;
    if (r != null) {
      Sfx.instance.coin();
      Haptics.success();
      _celebrate();
    }
    setState(() => _claiming = false);
  }

  /// A claimed gift gets the finished board's confetti (owner, 2026-10-17), bursting from the top of
  /// the sheet over the page behind it. None with Reduce motion.
  void _celebrate() {
    final box = context.findRenderObject();
    final from = box is RenderBox && box.hasSize ? box.localToGlobal(Offset(box.size.width / 2, 0)) : null;
    showConfettiBurst(context, from: from);
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).value;
    final available = profile?.dailyAvailable ?? false;
    final streak = profile?.streak ?? 0;
    // Numbered by the streak (Day 8 to 14 in the second week). After a missed day the next claim
    // starts again at day 1, whatever the stored streak says.
    final week = profile == null ? GiftWeek.of(streak: 0, claimedToday: false) : GiftWeek.forProfile(profile);
    final missed = profile != null && !profile.streakAlive && profile.streak > 0;
    final canRestore = profile != null && ref.read(profileProvider.notifier).canRestoreStreak;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeader(
            title: 'Daily gift',
            subtitle: !available
                ? 'Streak: $streak day${streak == 1 ? '' : 's'}. Back tomorrow.'
                : missed
                ? (canRestore ? 'You missed a day. Restore your streak or start again.' : 'You missed a day, so the streak starts again.')
                : 'Come back every day to grow your streak.',
            center: true,
          ),
          const SizedBox(height: 16),
          _WeekList(week: week),
          if (profile != null && canRestore) ...[
            const SizedBox(height: 10),
            // 001 B: restoring the streak just lost also claims today's gift as the next day of it.
            _RestoreRow(streak: profile.streak, day: profile.streak + 1, cost: Economy.streakRestoreTickets(profile.streak), loading: _restoring, onTap: _restore),
          ],
          const SizedBox(height: 16),
          BigButton(
            label: available ? 'Claim day ${week.today} gift' : 'Close',
            icon: available ? AppIcons.dailyGift : null,
            kind: available ? ButtonKind.primary : ButtonKind.secondary,
            loading: _claiming,
            onTap: available ? _claim : () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }
}

/// Where a day stands in this round of seven.
enum _DayState { claimed, today, claimedToday, later }

/// The week as a list: a status mark, the day, then its coins, tickets and
/// hints in aligned columns. Nothing is abbreviated: every gift reads in full.
/// The days carry the streak's own numbers ([GiftWeek]): Day 8 to 14 in the
/// second week, whose gifts are those of Day 1 to 7.
class _WeekList extends StatelessWidget {
  const _WeekList({required this.week});
  final GiftWeek week;

  _DayState _state(int i) {
    if (i < week.todayIndex) return _DayState.claimed;
    if (i > week.todayIndex) return _DayState.later;
    return week.claimedToday ? _DayState.claimedToday : _DayState.today;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rows = <Widget>[];
    for (var i = 0; i < 7; i++) {
      final isToday = i == week.todayIndex;
      final day = week.dayAt(i);
      // No hairline next to today's row: its own raised card separates it.
      if (i > 0 && !isToday && i - 1 != week.todayIndex) rows.add(Divider(height: 1, thickness: 0.5, color: c.stroke, indent: 52));
      rows.add(
        _DayRow(
          day: day,
          reward: Economy.dailyRewards[GiftWeek.rewardIndex(day)],
          state: _state(i),
          tag: switch (_state(i)) {
            _DayState.today => 'Today',
            _DayState.claimedToday => 'Claimed',
            _ when week.claimedToday && i == week.todayIndex + 1 => 'Tomorrow',
            _ => null,
          },
        ),
      );
    }
    return SoftCard(
      padding: const EdgeInsets.symmetric(vertical: 4),
      clip: Clip.none,
      child: Column(mainAxisSize: MainAxisSize.min, children: rows),
    );
  }
}

/// One day of the week. Today's row is larger than the rest (owner, 107): a raised
/// card a little wider than the list, the day on two lines, bigger marks and amounts.
/// Compared on screen with a tinted row and with rows that grow towards today
/// (round2/107/variants); the raised card reads clearest and keeps the list even.
class _DayRow extends StatelessWidget {
  const _DayRow({required this.day, required this.reward, required this.state, this.tag});
  final int day;
  final ({int coins, int tickets, int hints}) reward;
  final _DayState state;

  /// "Today", "Claimed" (today's, once claimed) or "Tomorrow".
  final String? tag;

  // Column widths, the same in every row so the amounts line up (they grow with Larger Text).
  static const _coinsColumn = 62.0;
  static const _extraColumn = 44.0;
  static const _overhang = 6.0;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final accent = context.accent;
    final today = state == _DayState.today || state == _DayState.claimedToday;
    final done = state == _DayState.claimed;
    final markSize = today ? 30.0 : 24.0;
    final iconSize = today ? 20.0 : 16.0;
    final amountFont = today ? TypeSize.headline : TypeSize.body;
    final labelFont = today ? TypeSize.headline : TypeSize.body;
    final scaler = MediaQuery.textScalerOf(context);
    final height = scaler.scale(today ? 60.0 : 40.0);
    // The reward columns grow with the text up to 135%; past that (Settings > Accessibility > Text
    // size) the amounts shrink to fit them, so the day keeps its room on a small phone.
    double column(double w) => w * scaler.scale(1).clamp(1.0, 1.35);

    // The streak's day in the mark; a long streak's three digits shrink to stay inside the circle.
    Widget dayNumber(TextStyle style) => Padding(
      padding: EdgeInsets.all(markSize * 0.12),
      child: FittedBox(fit: BoxFit.scaleDown, child: Text('$day', maxLines: 1, style: style)),
    );

    final Widget mark = switch (state) {
      _DayState.claimed || _DayState.claimedToday => Container(
        width: markSize,
        height: markSize,
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, color: today ? context.accentFill : c.accentTint),
        child: Icon(AppIcons.checkmarkAlt, size: markSize * 0.6, color: today ? context.onAccent : accent),
      ),
      _DayState.today => Container(
        width: markSize,
        height: markSize,
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, color: context.accentFill),
        child: dayNumber(TextStyle(fontSize: markSize * 0.47, fontWeight: FontWeight.w700, color: context.onAccent)),
      ),
      _DayState.later => Container(
        width: markSize,
        height: markSize,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: c.stroke, width: 1.5),
        ),
        child: dayNumber(TextStyle(fontSize: markSize * 0.47, fontWeight: FontWeight.w600, color: c.textSecondary)),
      ),
    };

    final dim = done ? 0.45 : 1.0;
    // Right-aligned in its column; a figure wider than the column shrinks a little instead of running over.
    Widget amount(Currency currency, int value) => FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerRight,
      child: Opacity(
        opacity: dim,
        child: Amount(currency: currency, value: value, size: iconSize, fontSize: amountFont, weight: today ? FontWeight.w700 : FontWeight.w600),
      ),
    );

    // With a large text size the label shrinks to fit beside the rewards instead of being cut.
    final label = FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(
      'Day $day',
      maxLines: 1,
      style: TextStyle(
        fontSize: labelFont,
        fontWeight: today ? FontWeight.w700 : FontWeight.w500,
        color: done ? c.textTertiary : c.textPrimary,
        letterSpacing: today ? -0.2 : 0,
      ),
    ));
    // Today's label on two lines (with the largest text sizes on a small phone it scales down rather
    // than cut); the others on one, with "Tomorrow" after the day once today is claimed, which moves
    // under the day when the line is too short.
    final Widget title = today
        ? FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                label,
                Text(tag!, maxLines: 1, style: TextStyle(fontSize: TypeSize.footnote, fontWeight: FontWeight.w600, color: accent)),
              ],
            ),
          )
        : Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              label,
              if (tag != null)
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(tag!, maxLines: 1, style: TextStyle(fontSize: TypeSize.footnote, fontWeight: FontWeight.w600, color: c.textSecondary)),
                ),
            ],
          );

    final pad = 14.0 + (today ? _overhang : 0);
    final row = SizedBox(
      height: height,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: pad),
        child: Row(
          children: [
            SizedBox(
              width: 30,
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  switchInCurve: Curves.easeOutBack,
                  transitionBuilder: (child, a) => A11y.reduceMotionOf(context) ? FadeTransition(opacity: a, child: child) : ScaleTransition(scale: a, child: child),
                  child: KeyedSubtree(key: ValueKey(state), child: mark),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Align(alignment: Alignment.centerLeft, child: title),
            ),
            SizedBox(
              width: column(_coinsColumn),
              child: Align(alignment: Alignment.centerRight, child: amount(Currency.coins, reward.coins)),
            ),
            SizedBox(
              width: column(_extraColumn),
              child: reward.tickets > 0 ? Align(alignment: Alignment.centerRight, child: amount(Currency.tickets, reward.tickets)) : null,
            ),
            SizedBox(
              width: column(_extraColumn),
              child: reward.hints > 0 ? Align(alignment: Alignment.centerRight, child: amount(Currency.hints, reward.hints)) : null,
            ),
          ],
        ),
      ),
    );

    // VoiceOver reads a row as one line: "Day 8, today: 50 coins".
    Widget spoken(Widget child) => Semantics(
      container: true,
      label: 'Day $day${tag != null ? ', ${tag!.toLowerCase()}' : (done ? ', claimed' : '')}: ${giftWords(reward)}',
      child: ExcludeSemantics(child: child),
    );

    if (today) {
      // A raised card over the list, reaching a little past its edges.
      return spoken(LayoutBuilder(
        builder: (context, cons) => SizedBox(
          height: height,
          width: cons.maxWidth,
          child: OverflowBox(
            minWidth: cons.maxWidth + _overhang * 2,
            maxWidth: cons.maxWidth + _overhang * 2,
            child: Container(
              decoration: BoxDecoration(
                color: c.cardElevated,
                borderRadius: BorderRadius.circular(Radii.md),
                border: Border.all(color: accent.withValues(alpha: 0.55), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: context.isDark ? 0.4 : 0.10),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: row,
            ),
          ),
        ),
      ));
    }
    return spoken(row);
  }
}

/// A gift in words, for VoiceOver: "100 coins, 1 ticket".
String giftWords(({int coins, int tickets, int hints}) r) => [
      countOf(r.coins, 'coin'),
      if (r.tickets > 0) countOf(r.tickets, 'ticket'),
      if (r.hints > 0) countOf(r.hints, 'hint'),
    ].join(', ');

/// The streak restore offer as one row: what happened, what it brings back,
/// and a small tinted button with the price. It sits above the claim and
/// never outweighs it.
class _RestoreRow extends StatelessWidget {
  const _RestoreRow({required this.streak, required this.day, required this.cost, required this.loading, required this.onTap});

  /// The streak lost to the missed days, and the gift day a restore claims with it.
  final int streak;
  final int day;
  final int cost;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SoftCard(
      padding: Insets.cardCompact,
      child: Row(
        children: [
          const IconTile(icon: AppIcons.streak, size: IconTile.small),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$streak-day streak', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: TypeSize.body, fontWeight: FontWeight.w600)),
                Text('Restore and claim day $day', maxLines: 2, style: TextStyle(fontSize: TypeSize.footnote, color: c.textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          BigButton.cost(label: 'Restore', currency: Currency.tickets, amount: cost, kind: ButtonKind.secondary, height: 36, expand: false, loading: loading, onTap: onTap),
        ],
      ),
    );
  }
}
