import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/a11y.dart';
import '../../core/analytics.dart';
import '../../core/haptics.dart';
import '../../core/theme/tokens.dart';
import '../../state/first_steps.dart';
import '../../widgets/glass.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';

/// The guided start on screen (lib/state/first_steps.dart, docs/first-steps.md): the next step on
/// Home, the blurred look at what is still to come with "Unlock
/// anyway", locked sections and tabs that say when they open, and one-time tips.

/// Home's one suggestion: the next small thing worth doing, with its picture. With [heroHeight]
/// it takes the top of Home as a large picture (while the daily puzzle is not open yet).
class NextStepCard extends ConsumerWidget {
  const NextStepCard({super.key, this.heroHeight});
  final double? heroHeight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final step = ref.watch(nextStepProvider);
    if (step == null) return const SizedBox.shrink();
    final c = context.colors;
    final puzzle = step.puzzle;
    void open() {
      Haptics.light();
      if (step.route == '/library') {
        context.go('/library');
      } else {
        context.push(step.route);
      }
    }

    if (heroHeight != null && puzzle != null) {
      return Pressable(
        key: ValueKey('next-step-${step.key}'),
        onTap: open,
        scale: 0.985,
        child: Container(
          height: heroHeight,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: c.boardBackground, borderRadius: BorderRadius.circular(Radii.lg), border: Border.all(color: c.stroke)),
          child: Stack(
            fit: StackFit.expand,
            children: [
              NetImage(url: puzzle.imageUrl, blurhash: puzzle.blurhash),
              DecoratedBox(decoration: BoxDecoration(gradient: Brand.scrim(strength: 0.8, contrast: A11y.increaseContrastOf(context)))),
              Positioned(left: 14, top: 14, child: Chip2(label: step.label, icon: AppIcons.playFill, onImage: true)),
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(step.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.white)),
                          const SizedBox(height: 4),
                          Text(step.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: TypeSize.footnote, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 46,
                      height: 46,
                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                      child: const Icon(AppIcons.playFill, color: Colors.black, size: 20),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    return SoftCard(
      key: ValueKey('next-step-${step.key}'),
      onTap: open,
      padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
      child: Row(
        children: [
          if (puzzle != null)
            SizedBox(width: 52, height: 52, child: NetImage(url: puzzle.thumbUrl, blurhash: puzzle.blurhash, radius: 10))
          else
            const Padding(padding: EdgeInsets.all(6), child: IconTile(icon: AppIcons.library, size: IconTile.medium)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(step.label, style: TextStyle(fontSize: TypeSize.caption, fontWeight: FontWeight.w600, color: context.accent, letterSpacing: -0.1)),
                const SizedBox(height: 1),
                Text(step.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(step.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: TypeSize.footnote, height: 1.25, color: c.textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: context.accentFill, shape: BoxShape.circle),
            child: Icon(step.route == '/library' ? AppIcons.chevronRight : AppIcons.playFill, color: context.onAccent, size: 18),
          ),
        ],
      ),
    );
  }
}

/// The end of the guided Home: what is still to come, blurred and fading behind a card that
/// says why it waits, lists what opens when, and offers "Unlock anyway". Like a locked card, every
/// title and line in it is one line at the default text size on a 390 pt iPhone (owner, TestFlight
/// 2026-10-18; test/hint_lines_test.dart).
class MoreToComeCard extends ConsumerWidget {
  const MoreToComeCard({super.key, required this.preview});

  /// Under its title, "More opens as you play".
  static const intro = 'Carden starts simple, one thing at a time.';

  /// The hidden part of Home (Lucky Wheel and piggy bank, packs, level), drawn blurred.
  final Widget preview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final upcoming = ref.watch(upcomingRevealsProvider);
    if (upcoming.isEmpty) return const SizedBox.shrink();
    final counted = ref.watch(countedSolvesProvider);
    final c = context.colors;
    final shown = upcoming.take(4).toList();
    return Stack(
      key: const ValueKey('more-to-come'),
      children: [
        // The real sections, out of focus: there is more, and it looks like Home.
        Positioned.fill(
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: ClipRect(
                child: ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (rect) => const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black, Colors.black, Colors.transparent],
                    stops: [0, 0.08, 0.6, 1],
                  ).createShader(rect),
                  child: ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4, tileMode: TileMode.decal),
                    child: Opacity(
                      opacity: 0.8,
                      child: OverflowBox(
                        alignment: Alignment.topCenter,
                        maxHeight: double.infinity,
                        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24), child: preview),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 150, 28, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: PageWidth.sheet),
              child: Container(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                decoration: BoxDecoration(
                  color: c.card,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: c.stroke, width: 0.5),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: context.isDark ? 0.4 : 0.10), blurRadius: 28, offset: const Offset(0, 8))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const IconTile(icon: AppIcons.lock, size: IconTile.small, radius: 9),
                        const SizedBox(width: 10),
                        Expanded(child: Text('More opens as you play', style: Theme.of(context).textTheme.titleLarge)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      MoreToComeCard.intro,
                      style: TextStyle(fontSize: TypeSize.footnote, height: 1.35, color: c.textSecondary),
                    ),
                    const SizedBox(height: 12),
                    for (final r in shown)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // The name and when it opens; at a large text size the chip moves under the name.
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(r.label, style: TextStyle(fontSize: TypeSize.body, fontWeight: FontWeight.w600, color: c.textPrimary)),
                                Chip2(label: r.more(counted)),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(r.blurb, style: TextStyle(fontSize: TypeSize.footnote, height: 1.3, color: c.textSecondary)),
                          ],
                        ),
                      ),
                    const SizedBox(height: 10),
                    BigButton(
                      key: const ValueKey('unlock-anyway'),
                      label: 'Unlock anyway',
                      kind: ButtonKind.secondary,
                      height: 44,
                      onTap: () {
                        Haptics.light();
                        unlockFromHome(context, ref);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A section that waits for the player (Profile's achievements, Quests' live events), under the
/// section's own header: when it opens and what it is, one line each at the default text size on a
/// 390 pt iPhone (owner, TestFlight 2026-10-18; test/hint_lines_test.dart), and "Unlock anyway".
class LockedSectionCard extends ConsumerWidget {
  const LockedSectionCard({super.key, required this.reveal});
  final Reveal reveal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final counted = ref.watch(countedSolvesProvider);
    return SoftCard(
      key: ValueKey('locked-${reveal.name}'),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const IconTile(icon: AppIcons.lock, size: IconTile.medium),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(reveal.opensAfter(counted), style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(reveal.blurb, style: TextStyle(fontSize: TypeSize.footnote, height: 1.3, color: c.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          BigButton(
            key: ValueKey('unlock-${reveal.name}'),
            label: 'Unlock anyway',
            kind: ButtonKind.secondary,
            height: 40,
            onTap: () => confirmUnlock(context, ref, [reveal]),
          ),
        ],
      ),
    );
  }
}

/// A locked tab was tapped: what it is, when it opens, and "Unlock anyway" (which asks first). True
/// when it opened.
Future<bool> askUnlockEarly(BuildContext context, WidgetRef ref, Reveal r) async {
  final yes = await showAppAlert(
    context,
    title: r.opensTitle(ref.read(countedSolvesProvider)),
    message: '${r.blurb} ${r.plural ? 'They wait' : 'It waits'} until then to keep the start simple.',
    confirmLabel: 'Unlock anyway',
    cancelLabel: 'Not now',
  );
  if (!yes || !context.mounted) return false;
  return confirmUnlock(context, ref, [r]);
}

/// "Unlock anyway" on Home: with more than one thing still to come, a sheet lists them with a
/// check each, only the nearest picked (owner, 2026-10-16); then the confirmation.
Future<void> unlockFromHome(BuildContext context, WidgetRef ref) async {
  final upcoming = ref.read(upcomingRevealsProvider);
  if (upcoming.isEmpty) return;
  final picked = upcoming.length == 1
      ? upcoming
      : await showAppSheet<List<Reveal>>(context, scrollable: true, builder: (_) => _UnlockPicker(upcoming: upcoming, counted: ref.read(countedSolvesProvider)));
  if (picked == null || picked.isEmpty || !context.mounted) return;
  final everything = picked.length == upcoming.length;
  if (await confirmUnlock(context, ref, picked, everything: everything) && context.mounted) {
    showToast(
      context,
      everything ? 'Everything is open. Settings > Guided start brings the steps back.' : '${_names(picked)} ${picked.length == 1 && !picked.first.plural ? 'is' : 'are'} open',
      icon: AppIcons.unlock,
    );
  }
}

String _names(List<Reveal> rs) => rs.length == 1 ? rs.first.label : '${rs.take(rs.length - 1).map((r) => r.label).join(', ')} and ${rs.last.label}';

/// Every "Unlock anyway" asks first (owner, 2026-10-16) and says what waiting gives. [everything]
/// opens all that is left (Home's list with every item picked). True when it opened.
Future<bool> confirmUnlock(BuildContext context, WidgetRef ref, List<Reveal> picked, {bool everything = false}) async {
  final counted = ref.read(countedSolvesProvider);
  final one = picked.length == 1 ? picked.first : null;
  final yes = await showAppAlert(
    context,
    title: 'Are you sure?',
    message: '${one != null ? '${one.label} ${one.plural ? 'open' : 'opens'} by ${one.plural ? 'themselves' : 'itself'} after ${one.more(counted)}.' : 'They open by themselves as you solve pictures.'} '
        'Waiting keeps the start calm: one new thing at a time, each when you are ready for it, and quests and '
        'achievements count only from the moment they open.',
    confirmLabel: everything ? 'Unlock everything' : one != null ? 'Unlock ${one.label}' : 'Unlock ${picked.length}',
    cancelLabel: 'Keep waiting',
  );
  if (!yes) return false;
  final steps = ref.read(firstStepsProvider.notifier);
  if (everything) {
    steps.showEverything();
    AppAnalytics.event('feature_unlocked', {'feature': 'everything', 'by': 'unlock_anyway', 'pictures': counted});
  } else {
    for (final r in picked) {
      steps.openEarly(r);
      AppAnalytics.event('feature_unlocked', {'feature': r.name, 'by': 'unlock_anyway', 'pictures': counted});
    }
  }
  return true;
}

/// The sheet behind Home's "Unlock anyway": what is still to come, each with a check (the nearest
/// picked), and Unlock, which asks once more.
class _UnlockPicker extends StatefulWidget {
  const _UnlockPicker({required this.upcoming, required this.counted});
  final List<Reveal> upcoming;
  final int counted;

  @override
  State<_UnlockPicker> createState() => _UnlockPickerState();
}

class _UnlockPickerState extends State<_UnlockPicker> {
  late final Set<Reveal> _picked = {widget.upcoming.first};

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final picked = [for (final r in widget.upcoming) if (_picked.contains(r)) r];
    // The list scrolls under the header; the button stays pinned at the bottom (owner, 2026-10-18).
    return SheetScrollBody(
      key: const ValueKey('unlock-picker'),
      footer: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: BigButton(
          key: const ValueKey('unlock-picked'),
          label: picked.isEmpty ? 'Pick something to unlock' : picked.length == widget.upcoming.length ? 'Unlock everything' : picked.length == 1 ? 'Unlock ${picked.first.label}' : 'Unlock ${picked.length}',
          onTap: picked.isEmpty ? null : () => Navigator.of(context).pop(picked),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetHeader(title: 'Unlock early', subtitle: 'Pick what to open now. The rest keeps opening as you solve pictures.'),
            const SizedBox(height: 12),
            SoftCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < widget.upcoming.length; i++) ...[
                    if (i > 0) Divider(height: 1, color: c.stroke, indent: 52),
                    _row(context, widget.upcoming[i]),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, Reveal r) {
    final c = context.colors;
    final on = _picked.contains(r);
    return Semantics(
      checked: on,
      button: true,
      label: '${r.label}, opens after ${r.more(widget.counted)}',
      excludeSemantics: true,
      child: Pressable(
        key: ValueKey('unlock-pick-${r.name}'),
        onTap: () => setState(() => on ? _picked.remove(r) : _picked.add(r)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(on ? AppIcons.checkmarkCircleFill : AppIcons.circle, size: 24, color: on ? context.accent : c.textTertiary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(r.label, style: TextStyle(fontSize: TypeSize.body, fontWeight: FontWeight.w600, color: c.textPrimary)),
                        Chip2(label: r.more(widget.counted)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(r.blurb, style: TextStyle(fontSize: TypeSize.footnote, height: 1.3, color: c.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A tip said once, where it matters (the Library, the board picker), with a close. Two lines at
/// most on a 390 pt iPhone at the default text size (owner, TestFlight 2026-10-18;
/// test/hint_lines_test.dart).
class OneTimeTip extends ConsumerWidget {
  const OneTimeTip({super.key, required this.id, required this.icon, required this.text, this.padding = EdgeInsets.zero});
  final String id;
  final IconData icon;
  final String text;
  final EdgeInsets padding;

  /// The Library's tip, the first time it opens.
  static const libraryText = 'Start with the free packs. Every picture earns coins to open more.';

  /// The board picker's tip, the first time it opens.
  static const boardText = 'Pick a shape and a size. Bigger boards pay more coins and XP.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final steps = ref.watch(firstStepsProvider);
    if (!steps.guided || steps.tips.contains('tip:$id')) return const SizedBox.shrink();
    final c = context.colors;
    return Padding(
      padding: padding,
      child: SoftCard(
        key: ValueKey('tip-$id'),
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        child: Row(
          children: [
            IconTile(icon: icon, size: IconTile.small, radius: 9),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: TextStyle(fontSize: TypeSize.footnote, height: 1.35, color: c.textPrimary))),
            IconButton(
              key: ValueKey('tip-$id-close'),
              tooltip: 'Close',
              onPressed: () => ref.read(firstStepsProvider.notifier).sawTip('tip:$id'),
              icon: Icon(AppIcons.xmark, size: 18, color: c.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
