import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/a11y.dart';
import '../../core/analytics.dart';
import '../../core/theme/tokens.dart';
import '../../game/board.dart';
import '../../game/game_controller.dart';
import '../../state/catalog.dart';
import '../../state/first_steps.dart';
import '../../state/profile.dart';
import '../../state/settings.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';
import '../game/board_widget.dart';

/// Three-slide welcome. The art shows real catalogue pictures so the game
/// sells itself; players start as guests and can link an account later.
///
/// Every picture here is bundled with the app (`assets/welcome/`), so the
/// welcome is complete in its first frames: no catalogue, no network, no
/// BlurHash placeholders, also on a first launch offline.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});
  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _page = PageController();
  int _index = 0;
  bool _precached = false;

  static const _slides = [
    (title: 'Pictures made of cards', body: 'Every puzzle is a photo cut into cards and shuffled. Tap a card, then tap where it belongs, or drag it there.'),
    (title: 'Snap, group, lock', body: 'Cards that belong together snap into a group anywhere on the board. A card in its true spot locks into the picture for good.'),
    (title: 'A new picture daily', body: 'Play the daily puzzle to keep your streak. Earn coins and tickets to open more packs and events.'),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Decode every fan picture while page 1 fades in, so no card is ever
    // drawn empty (page 2's board picture is decoded by [_boardPicture]).
    if (_precached) return;
    _precached = true;
    for (final p in [..._Welcome.firstFan, ..._Welcome.dailyFan]) {
      precacheImage(AssetImage(p), context);
    }
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  /// "Start playing" or Skip is waiting for the catalogue (a slow first visit): the button shows a
  /// spinner, on any page.
  bool _starting = false;

  /// "Start playing" and Skip: a new player goes straight into a first board (Home waits under it,
  /// for when they leave it); anyone else lands on Home. A catalogue still loading (a slow first
  /// visit) is waited for up to 10 seconds, so the first board is not skipped.
  ///
  /// The welcome ends for good at the tap, before that wait (owner, TestFlight 2026-10-18: the
  /// welcome pages came back at every launch). A player who closes the app while the first board
  /// loads starts on Home next time, where the first picture waits on top (docs/first-steps.md).
  Future<void> _finish() async {
    if (_starting) return;
    final router = GoRouter.of(context);
    bool newPlayer() => ref.read(firstStepsProvider).firstBoard && ref.read(solvedCountProvider) == 0 && (ref.read(profileProvider).value?.level ?? 1) <= 1;
    ref.read(settingsProvider.notifier).setOnboarded();
    if (ref.read(firstBoardProvider) == null && newPlayer()) {
      setState(() => _starting = true);
      try {
        await ref.read(allPuzzlesProvider.future).timeout(const Duration(seconds: 10));
      } catch (_) {}
      if (!mounted) return;
    }
    final first = ref.read(firstBoardProvider);
    final play = first != null && newPlayer();
    AppAnalytics.event('onboarding_completed', {'firstBoard': play});
    router.go('/home');
    if (play) WidgetsBinding.instance.addPostFrameCallback((_) => router.push(first.route));
  }

  /// Continue, or "Start playing" on the last page.
  void _next() {
    if (_index == _slides.length - 1) {
      _finish();
    } else {
      A11y.reduceMotionOf(context) ? _page.jumpToPage(_page.page!.round() + 1) : _page.nextPage(duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
    }
  }

  /// [builder] with how far the last page has come in: 0 on the pages before it, 1 on it, in
  /// between while it slides in or out. The controls that change on the last page follow the swipe
  /// with it (owner, TestFlight 2026-10-18: they switched at its midpoint, with no animation). With
  /// Reduce motion the page changes at once, and they cross-fade instead.
  Widget _toLast(Widget Function(BuildContext context, double t) builder) {
    final end = _slides.length - 1;
    if (A11y.reduceMotionOf(context)) {
      return TweenAnimationBuilder<double>(
        tween: Tween(end: _index == end ? 1.0 : 0.0),
        duration: const Duration(milliseconds: 250),
        builder: (context, t, _) => builder(context, t),
      );
    }
    return AnimatedBuilder(
      animation: _page,
      builder: (context, _) {
        final page = _page.hasClients && _page.position.hasContentDimensions ? _page.page ?? _index.toDouble() : _index.toDouble();
        return builder(context, (page - (end - 1)).clamp(0.0, 1.0));
      },
    );
  }

  /// A Skip on its way out as the last page comes in ([t]): it fades, and drifts and shrinks a
  /// little (not with Reduce motion). Its space stays, so nothing around it moves; out of reach and
  /// out of VoiceOver once it is mostly gone.
  Widget _leaving(BuildContext context, double t, Widget child) {
    final reduce = A11y.reduceMotionOf(context);
    final gone = Curves.easeOut.transform((t / 0.7).clamp(0.0, 1.0));
    return IgnorePointer(
      ignoring: t > 0.5,
      child: ExcludeSemantics(
        excluding: t > 0.5,
        child: Opacity(
          opacity: 1 - gone,
          child: reduce ? child : Transform.translate(offset: Offset(0, 6 * gone), child: Transform.scale(scale: 1 - 0.1 * gone, child: child)),
        ),
      ),
    );
  }

  /// The main button: "Continue" turns into "Start playing" as the last page comes in ([t]), the
  /// two labels cross-fading on the one button (the old label rises out, the new one rises in, not
  /// with Reduce motion). A spinner while the first board's picture is on its way.
  Widget _startButton(BuildContext context, double t, VoidCallback onTap) {
    final reduce = A11y.reduceMotionOf(context);
    final fg = context.onAccent;
    // Mostly one after the other, so a finger held halfway does not show two labels over each other.
    final out = 1 - Curves.easeIn.transform((t / 0.55).clamp(0.0, 1.0));
    final into = Curves.easeOut.transform(((t - 0.45) / 0.55).clamp(0.0, 1.0));
    Widget label(String text, IconData? icon, double opacity, double dy) => Opacity(
          opacity: opacity,
          child: Transform.translate(
            offset: Offset(0, reduce ? 0 : dy),
            // As BigButton draws its label: never cut, shrunk to fit at a large text size.
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[Icon(icon, color: fg, size: 19), const SizedBox(width: 8)],
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(text, maxLines: 1, softWrap: false, style: TextStyle(fontSize: TypeSize.callout, fontWeight: FontWeight.w600, letterSpacing: -0.2, color: fg)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
    final last = _index == _slides.length - 1;
    // One button for VoiceOver, named by the page (the labels drawn over it are only pictures).
    return Semantics(
      button: true,
      label: last ? 'Start playing' : 'Continue',
      onTap: _starting ? null : onTap,
      excludeSemantics: true,
      child: Stack(
        alignment: Alignment.center,
        children: [
          BigButton(key: const ValueKey('welcome-next'), label: '', loading: _starting, onTap: onTap),
          if (!_starting)
            IgnorePointer(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Far enough apart that halfway the two never sit on each other.
                  if (out > 0) label('Continue', null, out, -14 * (1 - out)),
                  if (into > 0) label('Start playing', AppIcons.playFill, into, 14 * (1 - into)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final safeTop = MediaQuery.paddingOf(context).top;
    // Room under the art for the longest title and text, so every page puts
    // its title on the same line.
    final textBlock = MediaQuery.textScalerOf(context).scale(196);
    // Starts decoding page 2's picture on page 1 and keeps it for the welcome.
    ref.watch(_boardPicture);
    // The first board's picture loads meanwhile, so the cards are dealt at once.
    ref.watch(firstBoardPrefetchProvider);
    if (context.isExpanded) return _wide(context);

    return Scaffold(
      backgroundColor: c.canvas,
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: PageView.builder(
                  controller: _page,
                  itemCount: _slides.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (_, i) {
                    final s = _slides[i];
                    final Widget art = switch (i) {
                      0 => const _CardFan(pictures: _Welcome.firstFan),
                      1 => const _DemoBoard(),
                      _ => const _CardFan(pictures: _Welcome.dailyFan),
                    };
                    return LayoutBuilder(
                      builder: (context, box) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // The art starts below the status bar and takes what the
                          // text leaves: more on tall phones, never under the clock.
                          Padding(
                            padding: EdgeInsets.only(top: safeTop + 8),
                            child: SizedBox(
                              height: math.max(160, box.maxHeight - textBlock - safeTop - 8),
                              width: double.infinity,
                              // The fans fade into the page; the board is shown whole.
                              child: i == 1
                                  ? art.animate(key: ValueKey('a$i')).fadeIn(duration: 400.ms)
                                  : _FadeToCanvas(
                                      child: art.animate(key: ValueKey('a$i')).fadeIn(duration: 400.ms),
                                    ),
                            ),
                          ),
                          Expanded(
                            // Scrolls when Settings > Accessibility > Text size makes the words taller than the space.
                            child: SingleChildScrollView(
                              physics: const ClampingScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(28, 20, 28, 0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    s.title,
                                    style: Theme.of(context).textTheme.displaySmall,
                                  ).animate(key: ValueKey('t$i')).fadeIn(delay: 80.ms, duration: 350.ms).slideY(begin: A11y.reduceMotionOf(context) ? 0 : 0.08, curve: Curves.easeOut),
                                  const SizedBox(height: 12),
                                  Text(
                                    s.body,
                                    style: TextStyle(fontSize: TypeSize.callout, height: 1.45, color: c.textSecondary),
                                  ).animate(key: ValueKey('b$i')).fadeIn(delay: 160.ms, duration: 350.ms).slideY(begin: A11y.reduceMotionOf(context) ? 0 : 0.08, curve: Curves.easeOut),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var i = 0; i < _slides.length; i++)
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              width: i == _index ? 20 : 6,
                              height: 6,
                              decoration: BoxDecoration(color: i == _index ? context.accent : c.textTertiary.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(6)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _toLast((context, t) => _startButton(context, t, _next)),
                      const SizedBox(height: 8),
                      // "Start playing" already finishes on the last page: Skip leaves with the
                      // swipe, and its space stays so the button does not move.
                      _toLast(
                        (context, t) => _leaving(
                          context,
                          t,
                          Pressable(
                            key: const ValueKey('welcome-skip'),
                            onTap: _finish,
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Text(
                                'Skip',
                                style: TextStyle(color: c.textSecondary, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          // Skip also where iOS puts it, at the top right over the art (the
          // owner keeps both here). Not on the last page, where "Start
          // playing" does the same.
          Positioned(
            top: safeTop + 4,
            right: 12,
            child: _toLast(
              (context, t) => _leaving(
                context,
                t,
                Pressable(
                  onTap: _finish,
                  child: TapTarget(
                    child: Glass(
                      radius: Radii.pill,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      opacity: 0.72,
                      child: Text(
                        'Skip',
                        style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600, fontSize: TypeSize.body),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The welcome on a desktop: the art large on the left (it still turns page by page), the
  /// page's title and text with the controls on the right.
  Widget _wide(BuildContext context) {
    final c = context.colors;
    final s = _slides[_index];

    return Scaffold(
      backgroundColor: c.canvas,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120, maxHeight: 760),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
              child: Row(
                children: [
                  Expanded(
                    flex: 6,
                    child: PageView.builder(
                      controller: _page,
                      itemCount: _slides.length,
                      onPageChanged: (i) => setState(() => _index = i),
                      itemBuilder: (_, i) {
                        final Widget art = switch (i) {
                          0 => const _CardFan(pictures: _Welcome.firstFan),
                          1 => const _DemoBoard(),
                          _ => const _CardFan(pictures: _Welcome.dailyFan),
                        };
                        return i == 1
                            ? art.animate(key: ValueKey('a$i')).fadeIn(duration: 400.ms)
                            : _FadeToCanvas(child: art.animate(key: ValueKey('a$i')).fadeIn(duration: 400.ms));
                      },
                    ),
                  ),
                  const SizedBox(width: 56),
                  Expanded(
                    flex: 5,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.title, style: Theme.of(context).textTheme.displaySmall)
                            .animate(key: ValueKey('t$_index'))
                            .fadeIn(delay: 80.ms, duration: 350.ms)
                            .slideY(begin: A11y.reduceMotionOf(context) ? 0 : 0.08, curve: Curves.easeOut),
                        const SizedBox(height: 12),
                        Text(s.body, style: TextStyle(fontSize: TypeSize.callout, height: 1.45, color: c.textSecondary))
                            .animate(key: ValueKey('b$_index'))
                            .fadeIn(delay: 160.ms, duration: 350.ms)
                            .slideY(begin: A11y.reduceMotionOf(context) ? 0 : 0.08, curve: Curves.easeOut),
                        const SizedBox(height: 32),
                        Row(
                          children: [
                            for (var i = 0; i < _slides.length; i++)
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 250),
                                margin: const EdgeInsets.only(right: 8),
                                width: i == _index ? 20 : 6,
                                height: 6,
                                decoration: BoxDecoration(color: i == _index ? context.accent : c.textTertiary.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(6)),
                              ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            SizedBox(width: 240, child: _toLast((context, t) => _startButton(context, t, _next))),
                            const SizedBox(width: 12),
                            // "Start playing" already finishes on the last page: Skip leaves with the swipe.
                            _toLast(
                              (context, t) => _leaving(
                                context,
                                t,
                                Pressable(
                                  onTap: _finish,
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Text('Skip', style: TextStyle(color: c.textSecondary, fontWeight: FontWeight.w600)),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Fades the bottom of the artwork into the canvas colour.
class _FadeToCanvas extends StatelessWidget {
  const _FadeToCanvas({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final canvas = context.colors.canvas;
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, stops: const [0, 0.72, 1], colors: [canvas.withValues(alpha: 0), canvas.withValues(alpha: 0), canvas]),
            ),
          ),
        ),
      ],
    );
  }
}

/// A fan of overlapping, slightly rotated picture cards.
class _CardFan extends StatelessWidget {
  const _CardFan({required this.pictures});

  /// Bundled pictures (asset paths), drawn in [layout] order.
  final List<String> pictures;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // Fixed layout: fraction of width/height, rotation in radians, card size.
    const layout = <(double, double, double, double)>[
      (0.08, 0.14, -0.22, 0.34),
      (0.36, 0.04, 0.08, 0.30),
      (0.64, 0.12, 0.20, 0.34),
      (0.02, 0.50, 0.12, 0.30),
      (0.30, 0.42, -0.06, 0.38),
      (0.66, 0.50, -0.16, 0.32),
      (0.42, 0.74, 0.14, 0.28),
    ];
    return LayoutBuilder(
      builder: (_, box) {
        final w = box.maxWidth, h = box.maxHeight;
        return Stack(
          children: [
            for (var i = 0; i < math.min(pictures.length, layout.length); i++)
              Positioned(
                left: w * layout[i].$1,
                top: h * layout[i].$2,
                child: Transform.rotate(
                  angle: layout[i].$3,
                  child: Container(
                    width: w * layout[i].$4,
                    height: w * layout[i].$4 * 1.3,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: c.boardBackground,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: c.card, width: 3),
                    ),
                    child: Image.asset(pictures[i], fit: BoxFit.cover, gaplessPlayback: true),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Page 2's picture, decoded from the app bundle for the board renderer.
/// Lives while the welcome is open (it is watched from page 1 on).
final _boardPicture = FutureProvider.autoDispose<ui.Image>((ref) async {
  final data = await rootBundle.load(_Welcome.board);
  final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
  final frame = await codec.getNextFrame();
  codec.dispose();
  ref.onDispose(frame.image.dispose);
  return frame.image;
});

/// A bundled picture on a real 3x3 board, drawn by the game's own board
/// renderer in the middle of a game (static): the red panda's face locked
/// into its place at the top (edge to edge, no frame), two cards that
/// belong together joined into a group on the bottom row (one piece, cobalt
/// outline), and the other five loose. What "Snap, group, lock" means, in
/// the look the player meets a minute later.
class _DemoBoard extends ConsumerWidget {
  const _DemoBoard();

  static const _spec = BoardSpec(GameMode.cards, 3, 3, 'Cozy');

  /// `slots[i]` is the card in slot i. Cards 1 and 2 are locked; cards 4
  /// and 5 are joined on slots 6 and 7; no other card is in place or next
  /// to a card it belongs beside.
  static const _layout = [8, 1, 2, 7, 0, 6, 4, 5, 3];

  /// Height of the Skip pill's corner, from the top of the art.
  static const _skipZone = 44.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final image = ref.watch(_boardPicture).value;
    // Decoded before page 2 can be reached; nothing to show before that.
    if (image == null) return const SizedBox.expand();
    final style = ref.watch(settingsProvider).cardStyle;
    final board = Board(_spec, _layout);
    return LayoutBuilder(
      builder: (_, box) {
        final w = box.maxWidth, h = box.maxHeight, aspect = image.width / image.height;
        var size = board.tiling.fit(Size(w - 64, h - 16), aspect);
        // On taller phones the board grows into the top-right corner, where
        // the Skip pill is (about 80 x 44 pt): there it starts below the pill.
        final clear = (w + size.width) / 2 <= w - 80 || (h - size.height) / 2 >= _skipZone;
        if (!clear) size = board.tiling.fit(Size(w - 64, h - _skipZone - 8), aspect);
        return Padding(
          padding: EdgeInsets.only(top: clear ? 0 : _skipZone - 8),
          child: Center(
            child: IgnorePointer(
              child: BoardWidget(
                image: image,
                state: GameState(
                  board: board,
                  par: board.par,
                  moves: 0,
                  elapsed: 0,
                  status: GameStatus.playing,
                  selected: null,
                  hintsUsed: 0,
                  history: const [],
                  justLocked: const {},
                  justJoined: const {},
                  hintSlot: null,
                  hintTarget: null,
                  peeking: false,
                  chain: 0,
                  tick: 0,
                ),
                width: size.width,
                height: size.height,
                cardStyle: style,
                onTap: (_) {},
                onDrop: (_, _) {},
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The welcome pictures, bundled in `assets/welcome/`: catalogue pictures in
/// the public domain or CC0 (no attribution required; the catalogue credits
/// in Settings list their collections), 420 px wide for the fans, 800 px for
/// the board.
abstract final class _Welcome {
  static const _dir = 'assets/welcome';

  /// Page 2's board: Red panda sleeping (p-76aea56b17bf), Mathias Appel, Wikimedia Commons, CC0.
  static const board = '$_dir/red-panda.jpg';

  static const firstFan = [
    '$_dir/island-lake.jpg', // Island Lake, Wind River Range (p-8343ffdf7c5f), USGS, public domain
    '$_dir/red-panda.jpg', // Red panda sleeping (p-76aea56b17bf), Mathias Appel, CC0
    '$_dir/tulip-fields.jpg', // Tulip Fields 11 (pack-tulip-fields-11), rawpixel, CC0
    '$_dir/amsterdam-canal.jpg', // Amsterdam canal at night II (p-225db9df81b5), Supertrouper33, CC0
    '$_dir/azure-window.jpg', // Gozo Azure Window (p-08dd8a134e87), public domain
    '$_dir/antelope-canyon.jpg', // Lower Antelope Canyon II (p-73d4629c3222), Lucas Löffler, public domain
    '$_dir/emperor-penguins.jpg', // Emperor penguin (p-4105a374e572), Denis Luyten, public domain
  ];

  static const dailyFan = [
    '$_dir/cherry-blossom.jpg', // Cherry blossom (p-a5bb6e304932), Syced, CC0
    '$_dir/meerkat.jpg', // Meerkat standing (daily-2023-09-30), Mathias Appel, CC0
    '$_dir/parthenon.jpg', // Parthenon Athens (p-e0aebce38975), Jebulon, CC0
    '$_dir/water-lilies.jpg', // Water lilies (p-0251484d723a), Nathalie E. Julien, StockSnap, CC0
    '$_dir/tropical-beach.jpg', // Tropical Beaches 3 (pack-tropical-beaches-03), Joe deSousa, StockSnap, CC0
    '$_dir/california-rolls.jpg', // California rolls (p-343eda272172), Benoît Prieur, CC0
    '$_dir/ammonoosuc-falls.jpg', // Upper Ammonoosuc Falls (p-7855f96224a6), USFS Eastern Region, public domain
  ];
}
