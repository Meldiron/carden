import 'dart:async';
import 'dart:math' as math;

import 'package:confetti/confetti.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/a11y.dart';
import '../../core/analytics.dart';
import '../../core/haptics.dart';
import '../../core/sfx.dart';
import '../../core/theme/tokens.dart';
import '../../state/profile.dart';
import '../../widgets/glass.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';

/// One slice of the Lucky Wheel: [amount] of [kind]. [weight] is its share
/// of the draw: the chance of a slice is its weight over the sum of all weights.
class WheelSegment {
  const WheelSegment(this.kind, this.amount, this.color, {this.weight = 1, this.jackpot = false});
  final Currency kind;
  final int amount;
  final Color color;
  final double weight;
  final bool jackpot;

  String get label => formatCount(amount);

  /// The prize of a spin that pays [times] over (the ×5 spin).
  int amountFor(int times) => amount * times;

  /// What the prize is, after its icon and number ("2 Hints", "5 Peeks",
  /// "1 Magic"). Coins carry the coin mark only.
  String? get name => switch (kind) {
        Currency.coins => null,
        Currency.tickets => amount == 1 ? 'Ticket' : 'Tickets',
        Currency.hints => amount == 1 ? 'Hint' : 'Hints',
        Currency.peeks => amount == 1 ? 'Peek' : 'Peeks',
        Currency.magics => 'Magic',
      };

  /// The prize in coins, at what the same boosters cost in a game.
  int get coinValue => switch (kind) {
        Currency.coins => amount,
        Currency.tickets => 0,
        Currency.hints => amount * Economy.hintCostCoins,
        Currency.peeks => amount * Economy.peekCostCoins,
        Currency.magics => amount * Economy.magicLockCostCoins,
      };
}

/// Balance: a spin costs 1 Ticket. The weights are the chances in percent
/// (owner, 2026-10-15): 100 and 250 coins 23% each, 5 Peeks 18%, 10 Peeks 14%,
/// 1 Magic 10%, 3 Hints 9%, 3 Magic 2% and the 1,000-coin jackpot exactly 1%.
/// Expected value per spin, boosters at their price in coins (Peek 10, Hint 150,
/// Magic 300):
///   coins    = 100·0.23 + 250·0.23 + 1000·0.01 ≈ 90 coins
///   boosters = 50·0.18 + 100·0.14 + 300·0.10 + 450·0.09 + 900·0.02 ≈ 112 coins
///   together ≈ 200 coins (150 before, with 60, 120 and a 500 jackpot at 2.3%)
/// Tickets are never a reward, so the wheel cannot pay for itself. The odds
/// sheet reads this same table ([wheelOdds]), so what players are shown is what
/// the spin draws. Old builds keep their own table: the spin is drawn on the device.
const wheelSegments = [
  WheelSegment(Currency.coins, 100, Color(0xFFD97706), weight: 23),
  WheelSegment(Currency.peeks, 5, Color(0xFF64748B), weight: 18),
  WheelSegment(Currency.coins, 250, Color(0xFF0F9D8F), weight: 23),
  WheelSegment(Currency.hints, 3, Brand.accent, weight: 9),
  WheelSegment(Currency.peeks, 10, Color(0xFF475569), weight: 14),
  WheelSegment(Currency.magics, 1, Color(0xFFB45309), weight: 10),
  WheelSegment(Currency.coins, 1000, Color(0xFF3730A3), weight: 1, jackpot: true),
  WheelSegment(Currency.magics, 3, Color(0xFF0B7A70), weight: 2),
];

const _segments = wheelSegments;

/// The slice a spin lands on for [r], a uniform random number in [0, 1).
int wheelPick(double r, [List<WheelSegment> segments = wheelSegments]) {
  final total = segments.fold<double>(0, (s, e) => s + e.weight);
  var left = r * total;
  for (var i = 0; i < segments.length; i++) {
    left -= segments[i].weight;
    if (left < 0) return i;
  }
  return segments.length - 1;
}

/// One prize on the odds sheet and its chance in percent (one decimal).
typedef WheelOdd = ({WheelSegment segment, double percent});

/// Every prize with its chance, the most likely first. Percentages carry one
/// decimal and are rounded by largest remainder, so they add up to exactly 100.
List<WheelOdd> wheelOdds([List<WheelSegment> segments = wheelSegments]) {
  final total = segments.fold<double>(0, (s, e) => s + e.weight);
  final tenths = [for (final s in segments) s.weight / total * 1000];
  final floors = [for (final t in tenths) t.floor()];
  var missing = 1000 - floors.fold<int>(0, (a, b) => a + b);
  final order = List.generate(segments.length, (i) => i)..sort((a, b) => (tenths[b] - floors[b]).compareTo(tenths[a] - floors[a]));
  for (final i in order) {
    if (missing <= 0) break;
    floors[i]++;
    missing--;
  }
  final odds = [for (var i = 0; i < segments.length; i++) (segment: segments[i], percent: floors[i] / 10)];
  // Most likely first (owner, 112); equal chances in prize order: coins by amount, then hints, Peeks and Magic.
  odds.sort((a, b) {
    if (a.percent != b.percent) return b.percent.compareTo(a.percent);
    if (a.segment.kind != b.segment.kind) return a.segment.kind.index.compareTo(b.segment.kind.index);
    return a.segment.amount.compareTo(b.segment.amount);
  });
  return odds;
}

/// "23%", "1%", "22.7%": one decimal only when the chance has one.
String formatOdds(double percent) {
  final tenths = (percent * 10).round();
  return tenths % 10 == 0 ? '${tenths ~/ 10}%' : '${(tenths / 10).toStringAsFixed(1)}%';
}

/// The odds sheet, opened from "See odds" on the wheel (App Review guideline
/// 3.1.1: the odds of a paid random reward are shown before spending).
Future<void> showWheelOdds(BuildContext context) {
  AppAnalytics.event('wheel_odds_opened');
  return showAppSheet(
      context,
      builder: (ctx) {
        final c = ctx.colors;
        final odds = wheelOdds();
        final most = odds.map((o) => o.percent).reduce(math.max);
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // The shared sheet header (130): a table, so left-aligned.
              SizedBox(
                width: double.infinity,
                child: SheetHeader(
                  title: 'Lucky Wheel odds',
                  subtitle: 'Every spin costs ${countOf(Economy.wheelSpinTickets, 'ticket')} and pays one prize. Each spin is drawn on its own with these chances. '
                      'A ×${Economy.wheelBigSpin} spin costs ${countOf(Economy.wheelBigSpin * Economy.wheelSpinTickets, 'ticket')} and pays the prize it lands on ${_times(Economy.wheelBigSpin)}, with the same chances.',
                ),
              ),
              const SizedBox(height: 14),
              SoftCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < odds.length; i++) ...[
                      Padding(
                        key: ValueKey('wheel-odd-$i'),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                        child: Row(
                          children: [
                            // Mark, then the prize in words at one weight: "100 coins", "3 Hints".
                            currencyIcon(odds[i].segment.kind, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              // Wraps (the Jackpot chip onto its own line) with a large text size.
                              child: Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 4,
                                runSpacing: 4,
                                children: [
                                  Text(formatCount(odds[i].segment.amount), style: const TextStyle(fontSize: TypeSize.body, fontWeight: FontWeight.w600)),
                                  Text(odds[i].segment.name ?? 'coins', style: const TextStyle(fontSize: TypeSize.body, fontWeight: FontWeight.w600)),
                                  if (odds[i].segment.jackpot) ...[const SizedBox(width: 4), Chip2(label: 'Jackpot', color: Brand.coin.withValues(alpha: 0.16), foreground: ctx.isDark ? Brand.coin : (ctx.highContrast ? const Color(0xFF966100) : Brand.coinDeep))],
                                ],
                              ),
                            ),
                            // 112 B: a short bar beside each chance, scaled to the most likely prize,
                            // so 23% and 1% also read as large and small at a glance (never less than a dot).
                            SizedBox(
                              width: 56,
                              height: 6,
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: FractionallySizedBox(
                                  heightFactor: 1,
                                  widthFactor: (odds[i].percent / most).clamp(6 / 56, 1.0),
                                  child: DecoratedBox(decoration: BoxDecoration(color: ctx.accent.withValues(alpha: ctx.isDark ? 0.5 : 0.35), borderRadius: BorderRadius.circular(3))),
                                ),
                              ),
                            ),
                            SizedBox(
                              // The chance column grows with the text size, so "23%" stays on one line.
                              width: MediaQuery.textScalerOf(ctx).scale(52),
                              child: Text(formatOdds(odds[i].percent), maxLines: 1, softWrap: false, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: TypeSize.body)),
                            ),
                          ],
                        ),
                      ),
                      if (i < odds.length - 1) Divider(height: 1, color: c.stroke, indent: 16),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
}

/// "five times", "twice".
String _times(int n) => switch (n) {
      1 => 'once',
      2 => 'twice',
      5 => 'five times',
      _ => '$n times',
    };

/// Lucky Wheel: every spin costs one Ticket; a ×5 spin costs five and pays its prize five times.
class WheelScreen extends ConsumerStatefulWidget {
  const WheelScreen({super.key});
  @override
  ConsumerState<WheelScreen> createState() => _WheelScreenState();
}

class _WheelScreenState extends ConsumerState<WheelScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 4200));
  /// Jackpot burst from the wheel centre.
  late final ConfettiController _confetti = ConfettiController(duration: const Duration(milliseconds: 900));
  double _from = 0;
  double _to = 0;
  bool _spinning = false;
  WheelSegment? _result;
  int _lastTick = -1;
  int _spins = 0;

  /// ×1 or ×[Economy.wheelBigSpin]: what the next spin costs and pays over. [_wonTimes] is the
  /// multiplier the shown prize was won with.
  int _times = 1;
  int _wonTimes = 1;

  @override
  void initState() {
    super.initState();
    _c.addListener(() {
      final angle = _angle;
      final tick = (angle / (2 * math.pi / _segments.length)).floor();
      if (tick != _lastTick) {
        _lastTick = tick;
        Sfx.instance.spin();
        Haptics.selection();
      }
    });
  }

  @override
  void dispose() {
    _c.dispose();
    _confetti.dispose();
    super.dispose();
  }

  double get _angle => _from + (_to - _from) * Curves.easeOutQuart.transform(_c.value);

  Future<void> _spin() async {
    if (_spinning) return;
    final n = ref.read(profileProvider.notifier);
    final times = _times;
    final cost = times * Economy.wheelSpinTickets;
    final reason = times == 1 ? 'wheel' : 'wheel-x$times';
    final ok = await n.spendTickets(cost, reason: reason);
    if (!ok) {
      if (mounted) showToast(context, times == 1 ? 'You need ${countOf(cost, 'ticket')} to spin.' : 'You need ${countOf(cost, 'ticket')} to spin ×$times.', leading: const TicketIcon(size: 18));
      return;
    }
    // Weighted pick, from the same table the odds sheet shows.
    final idx = wheelPick(math.Random().nextDouble());
    final prize = _segments[idx];
    AppAnalytics.event('wheel_spun', {'spin': 'x$times', 'tickets': cost, 'prize': prize.kind.name, 'amount': prize.amountFor(times), 'jackpot': prize.jackpot});
    final seg = 2 * math.pi / _segments.length;
    // Pointer is at top (-pi/2). Segment i spans [i*seg, (i+1)*seg) starting at -pi/2 when rotation=0.
    final target = -(idx * seg + seg / 2) + (math.Random().nextDouble() - 0.5) * seg * 0.6;
    // Reduce motion: the wheel does not spin. It turns to the prize at once and, after a short
    // pause, the prize fades in below it.
    if (!mounted) return;
    final still = A11y.reduceMotionOf(context);
    _c.duration = still ? const Duration(milliseconds: 500) : const Duration(milliseconds: 4200);
    setState(() {
      _spinning = true;
      _result = null;
      _from = _angle % (2 * math.pi);
      _to = _from + 2 * math.pi * 6 + ((target - _from) % (2 * math.pi));
      if (still) _from = _to;
    });
    _c.forward(from: 0).whenComplete(() async {
      final won = _segments[idx];
      // The same ops as a single spin, the prize paid [times] over.
      final amount = won.amountFor(times);
      switch (won.kind) {
        case Currency.coins:
          await n.addCoins(amount, reason: reason);
        case Currency.tickets:
          await n.addTickets(amount, reason: reason);
        case Currency.hints:
          await n.addHints(amount, reason: reason);
        case Currency.peeks:
          await n.addPeeks(amount, reason: reason);
        case Currency.magics:
          await n.addMagics(amount, reason: reason);
      }
      if (!mounted) return;
      Sfx.instance.win();
      Haptics.success();
      if (won.jackpot && !A11y.reduceMotionOf(context)) _confetti.play();
      setState(() {
        _spinning = false;
        _result = won;
        _wonTimes = times;
        _spins++;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final profile = ref.watch(profileProvider).value;
    final tickets = profile?.tickets ?? 0;
    final cost = _times * Economy.wheelSpinTickets;
    final canSpin = tickets >= cost && !_spinning;
    final jackpot = _result?.jackpot ?? false;
    return Scaffold(
      // The ticket balance sits in the bar, as in the Store, so the wheel gets the height.
      appBar: GlassAppBar(
        title: const Text('Lucky Wheel'),
        leading: Padding(padding: const EdgeInsets.only(left: 12), child: RoundIconButton(icon: AppIcons.xmark, size: 38, onTap: () => context.pop())),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: CurrencyPill(currency: Currency.tickets, value: tickets, compact: true, onAdd: () => context.push('/store')),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 8),
            Expanded(
              child: Center(
                child: LayoutBuilder(
                  builder: (_, cons) {
                    // The wheel fits the space left in both directions: on an SE the result
                    // card and "Get tickets" take height the width-only size did not leave.
                    final size = math.max(160.0, math.min(math.min(cons.maxWidth - 48, cons.maxHeight - 32), 340.0));
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: size + 20,
                          height: size + 20,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: c.card, border: Border.all(color: c.stroke)),
                        ),
                        AnimatedBuilder(
                          animation: _c,
                          builder: (_, _) => _WheelFace(angle: _angle, size: size, times: _times),
                        ),
                        // A plain cap on the axle: the old wheel glyph there read as a loading spinner.
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: c.cardElevated,
                            shape: BoxShape.circle,
                            border: Border.all(color: c.stroke),
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: context.isDark ? 0.4 : 0.12), blurRadius: 8, offset: const Offset(0, 2))],
                          ),
                          child: Center(child: Container(width: 10, height: 10, decoration: BoxDecoration(color: context.accent, shape: BoxShape.circle))),
                        ),
                        if (jackpot)
                          // Glow pulse on the whole wheel when the jackpot lands.
                          IgnorePointer(
                            child: Container(
                              width: size + 20,
                              height: size + 20,
                              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Brand.coin, width: 4)),
                            )
                                .animate(onPlay: (ctrl) => ctrl.repeat(count: A11y.reduceMotionOf(context) ? 1 : 3))
                                .fadeIn(duration: 200.ms)
                                // Reduce motion: one glow that fades, without growing.
                                .scale(begin: const Offset(0.96, 0.96), end: A11y.reduceMotionOf(context) ? const Offset(0.96, 0.96) : const Offset(1.06, 1.06), duration: 600.ms, curve: Curves.easeOut)
                                .fadeOut(delay: 300.ms, duration: 300.ms),
                          ),
                        ConfettiWidget(
                          confettiController: _confetti,
                          blastDirectionality: BlastDirectionality.explosive,
                          emissionFrequency: 0.6,
                          numberOfParticles: 18,
                          maxBlastForce: 24,
                          minBlastForce: 8,
                          gravity: 0.25,
                          shouldLoop: false,
                          colors: [Brand.coin, Brand.coinDeep, context.accent, Colors.white],
                        ),
                        Positioned(
                          top: -4,
                          child: Transform.rotate(
                            angle: math.pi,
                            child: CustomPaint(size: const Size(28, 34), painter: _PointerPainter(color: context.accent, edge: c.card)),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            // One fixed slot under the wheel: the jackpot before a spin, the prize after it.
            // Its height never changes, so the wheel does not jump when a prize lands.
            SizedBox(
              height: 56,
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  switchInCurve: A11y.reduceMotionOf(context) ? Curves.easeOut : Curves.easeOutBack,
                  transitionBuilder: (child, a) => A11y.reduceMotionOf(context)
                      ? FadeTransition(opacity: a, child: child)
                      : FadeTransition(opacity: a, child: ScaleTransition(scale: Tween(begin: 0.9, end: 1.0).animate(a), child: child)),
                  child: _result == null
                      ? Row(
                          key: ValueKey('jackpot-$_times'),
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Jackpot', style: TextStyle(color: c.textSecondary, fontSize: TypeSize.footnote, fontWeight: FontWeight.w600)),
                            const SizedBox(width: 8),
                            Amount(currency: Currency.coins, value: _segments.firstWhere((s) => s.jackpot).amountFor(_times), size: 16, fontSize: TypeSize.body, weight: FontWeight.w700),
                          ],
                        )
                      : SoftCard(
                          key: ValueKey('won-${_result!.kind}-${_result!.amount}-$_wonTimes-$_spins'),
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                          radius: Radii.pill,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('You won', style: TextStyle(fontWeight: FontWeight.w600, fontSize: TypeSize.body)),
                              const SizedBox(width: 10),
                              Amount(currency: _result!.kind, value: _result!.amountFor(_wonTimes), size: 18, fontSize: TypeSize.callout, weight: FontWeight.w700),
                              // The name follows the amount paid ("5 Magic", "15 Peeks").
                              if (_result!.name != null) ...[const SizedBox(width: 5), Text(WheelSegment(_result!.kind, _result!.amountFor(_wonTimes), _result!.color).name!, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: TypeSize.body))],
                              if (jackpot) ...[const SizedBox(width: 8), const Chip2(label: 'Jackpot', color: Brand.coin, foreground: Color(0xFF2A1F00))],
                            ],
                          ),
                        ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Column(
                children: [
                  // One spin or a ×5 spin (five tickets, the prize paid five times, same odds).
                  SizedBox(
                    width: 180,
                    child: AppSegmentedControl<int>(
                      key: const ValueKey('wheel-times'),
                      value: _times,
                      segments: const {1: '×1', Economy.wheelBigSpin: '×${Economy.wheelBigSpin}'},
                      onChanged: (v) {
                        if (!_spinning) setState(() => _times = v);
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Out of tickets: one clear way on instead of a disabled Spin above a second button.
                  if (tickets < cost && !_spinning) ...[
                    BigButton(label: 'Get tickets', onTap: () => context.push('/store')),
                    const SizedBox(height: 8),
                    Text(
                      _times == 1
                          ? 'A spin costs ${countOf(cost, 'ticket')}. Earn them from weekly quests, level-ups and events.'
                          : 'A ×$_times spin costs ${countOf(cost, 'ticket')}. You have ${formatCount(tickets)}. Earn more from weekly quests, level-ups and events.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: c.textSecondary, fontSize: TypeSize.footnote, height: 1.35),
                    ),
                  ] else
                    BigButton.cost(
                      key: const ValueKey('wheel-spin'),
                      label: _times == 1 ? 'Spin for' : 'Spin ×$_times for',
                      currency: Currency.tickets,
                      amount: cost,
                      onTap: canSpin ? _spin : null,
                    ),
                  CupertinoButton(
                    key: const ValueKey('wheel-see-odds'),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    minimumSize: const Size(44, 32),
                    onPressed: () => showWheelOdds(context),
                    child: Text('See odds', style: TextStyle(color: context.accent, fontSize: TypeSize.body, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The wheel: slices painted by [_SlicePainter], prizes as the game's own marks
/// (coin, hint, Peek, Magic) laid on top. The slices turn with [angle]; each prize
/// moves with its slice but stays upright, so no amount is ever upside down.
class _WheelFace extends StatelessWidget {
  const _WheelFace({required this.angle, required this.size, this.times = 1});
  final double angle;
  final double size;

  /// The spin's multiplier: each slice shows what it pays ×[times].
  final int times;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = size / 2;
    final seg = 2 * math.pi / _segments.length;
    final palette = _WheelPalette.of(context);
    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Transform.rotate(angle: angle, child: CustomPaint(size: Size.square(size), painter: _SlicePainter(palette: palette, ring: c.card))),
          for (var i = 0; i < _segments.length; i++)
            Builder(builder: (context) {
              final a = -math.pi / 2 + i * seg + seg / 2 + angle;
              const box = 56.0;
              return Positioned(
                left: r + math.cos(a) * r * 0.64 - box / 2,
                top: r + math.sin(a) * r * 0.64 - box / 2,
                width: box,
                height: box,
                child: _PrizeMark(segment: _segments[i], times: times, ink: palette.ink(i), ring: palette.markRing),
              );
            }),
        ],
      ),
    );
  }
}

/// A prize on the wheel: its currency mark over its amount.
class _PrizeMark extends StatelessWidget {
  const _PrizeMark({required this.segment, this.times = 1, required this.ink, this.ring});
  final WheelSegment segment;
  final int times;
  final Color ink;
  final Color? ring;

  @override
  Widget build(BuildContext context) {
    Widget mark = currencyIcon(segment.kind, size: 24);
    if (ring != null) {
      mark = DecoratedBox(decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: ring!, width: 1.5)), child: mark);
    }
    // The wheel keeps its size: with a large text size the prize shrinks to fit its slice (the odds
    // sheet lists every prize in full).
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          mark,
          const SizedBox(height: 3),
          Text(formatCount(segment.amountFor(times)), style: TextStyle(fontWeight: FontWeight.w700, fontSize: TypeSize.body, height: 1.1, color: ink, letterSpacing: -0.2)),
        ],
      ),
    );
  }
}

/// 105 A: calm slices in two neutral tones from the theme, the jackpot in a soft
/// coin gold. The colour on the wheel comes from the prizes' own marks.
class _WheelPalette {
  const _WheelPalette({required this.a, required this.b, required this.jackpot, required this.spoke, required this.text});
  final Color a, b, jackpot, spoke, text;

  /// The marks keep their own colours on these light slices.
  Color? get markRing => null;

  static _WheelPalette of(BuildContext context) {
    final c = context.colors;
    return context.isDark
        ? _WheelPalette(a: c.cardElevated, b: c.card, jackpot: const Color(0xFF3A2E10), spoke: c.stroke, text: c.textPrimary)
        : _WheelPalette(a: Colors.white, b: const Color(0xFFECEFF5), jackpot: const Color(0xFFFFEFC2), spoke: c.stroke, text: c.textPrimary);
  }

  Color fill(int i) => _segments[i].jackpot ? jackpot : (i.isEven ? a : b);
  Color ink(int i) => text;

  @override
  bool operator ==(Object other) => other is _WheelPalette && other.a == a && other.b == b && other.jackpot == jackpot && other.spoke == spoke && other.text == text;
  @override
  int get hashCode => Object.hash(a, b, jackpot, spoke, text);
}

class _SlicePainter extends CustomPainter {
  _SlicePainter({required this.palette, required this.ring});
  final _WheelPalette palette;
  final Color ring;
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.width / 2;
    final seg = 2 * math.pi / _segments.length;
    final rect = Rect.fromCircle(center: center, radius: r);
    for (var i = 0; i < _segments.length; i++) {
      final start = -math.pi / 2 + i * seg;
      canvas.drawArc(rect, start, seg, true, Paint()..color = palette.fill(i));
    }
    // Hairline spokes between the slices.
    final spoke = Paint()
      ..color = palette.spoke
      ..strokeWidth = 1.5;
    for (var i = 0; i < _segments.length; i++) {
      final a = -math.pi / 2 + i * seg;
      canvas.drawLine(center, Offset(center.dx + math.cos(a) * r, center.dy + math.sin(a) * r), spoke);
    }
    canvas.drawCircle(center, r, Paint()..style = PaintingStyle.stroke..strokeWidth = 6..color = ring);
    // A hairline just inside the rim, so light slices do not melt into it.
    canvas.drawCircle(center, r - 3, Paint()..style = PaintingStyle.stroke..strokeWidth = 1..color = palette.spoke);
  }

  @override
  bool shouldRepaint(_SlicePainter old) => old.palette != palette || old.ring != ring;
}

class _PointerPainter extends CustomPainter {
  _PointerPainter({required this.color, required this.edge});
  final Color color;
  final Color edge;
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width, size.height * 0.75)
      ..quadraticBezierTo(size.width / 2, size.height, 0, size.height * 0.75)
      ..close();
    canvas.drawShadow(path, Colors.black, 3, false);
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(path, Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = edge);
  }

  @override
  bool shouldRepaint(_PointerPainter old) => old.color != color || old.edge != edge;
}
