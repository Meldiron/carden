import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/analytics.dart';
import '../../core/haptics.dart';
import '../../core/sfx.dart';
import '../../core/a11y.dart';
import '../../core/theme/tokens.dart';
import '../../game/board.dart';
import '../../game/game_controller.dart' show formatDuration;
import '../../game/image_loader.dart';
import '../../models/models.dart';
import '../../state/catalog.dart';
import '../../state/first_steps.dart';
import '../../state/giant.dart';
import '../../state/profile.dart';
import '../../state/progress.dart';
import '../../state/quick_play.dart';
import '../../state/rewards.dart';
import '../../state/settings.dart';
import '../../state/social.dart';
import '../../state/unlocks.dart';
import '../../widgets/cached_url_image.dart';
import '../../widgets/glass.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';
import '../gallery/giant_gate.dart' show showGiantGateFor;
import 'unlock_intro.dart';
import '../home/guided_start.dart';

/// Pre-game screen: preview with the cut overlay, mode picker, board picker
/// with reward preview, play button. This is the only place the cut preview
/// lives. Boards are square (3x3, 4x4, ...) whatever the picture, which is
/// centre-cropped to them; for a picture of another shape Expand deals the
/// same sizes with the columns and rows that suit it ([BoardSpec.ladder]),
/// read from the same decoded image the game uses. The preview frame takes
/// the aspect the real board will have (see [Tiling.boardAspect]) and shows
/// the part of the picture that is played, and the overlay is the real
/// tiling, so what is shown is what gets dealt. While a board is in progress
/// the choice is frozen on the saved mode and size: Continue resumes it,
/// Discard progress throws it away and reopens the choice.
class DifficultyScreen extends ConsumerStatefulWidget {
  const DifficultyScreen({super.key, required this.puzzleId, this.initialGrid, this.initialMode, this.initialPainting = false, this.initialExpand = false, this.fromQuick = false});
  final String puzzleId;

  /// Opened by Quick play: "Another picture" draws a new one from the same pool.
  final bool fromQuick;

  /// Painting preselected (`?painting=1`).
  final bool initialPainting;

  /// Expand preselected (`?expand=1`, or a board that is not square in [initialGrid]).
  final bool initialExpand;

  /// Optional tier code to preselect: legacy `5x5` or a full code such as
  /// `hexagons:5x6` / `hexagons-5x6` (used by goal shortcuts).
  final String? initialGrid;

  /// Optional mode code (`cards`, `squares`, `triangles`, `hexagons`).
  final String? initialMode;

  @override
  ConsumerState<DifficultyScreen> createState() => _DifficultyScreenState();
}

class _DifficultyScreenState extends ConsumerState<DifficultyScreen> {
  late GameMode _mode;

  /// Selected tier (its index, `BoardSpec.firstGiantTier` and up for giant
  /// sizes); its size follows the picture.
  late int _tier;

  /// Painting chosen for a new board.
  late bool _painting;

  /// Expand: the sizes laid out for the picture (when it offers Expand) instead of square.
  late bool _expand;

  /// The giant ladder step to open a Giant pack picture on (the last one chosen), when [_tier] is
  /// a normal step.
  int? _giantTier;

  /// Decoded picture size (full resolution), once the image is in.
  Size? _imageSize;

  /// The choices continue under the footer: it turns to glass with a
  /// hairline, like an iOS toolbar over a list that scrolls beneath it.
  bool _moreBelow = false;

  void _onMetrics(ScrollMetrics m) {
    if (m.axis != Axis.vertical) return;
    final more = m.extentAfter > 0.5;
    if (more != _moreBelow) setState(() => _moreBelow = more);
  }
  String? _resolvedUrl;
  ImageStream? _stream;
  ImageStreamListener? _listener;

  @override
  void initState() {
    super.initState();
    final grid = widget.initialGrid;
    final hasGrid = grid != null && grid.isNotEmpty;
    final decoded = hasGrid ? BoardSpec.fromCode(grid) : null;
    final modeArg = widget.initialMode;
    // A new picture opens on the board the player last chose (mode, size, Painting), unless the
    // link names one (a quest shortcut, Quick play).
    final last = ref.read(settingsProvider).lastBoard;
    _mode = modeArg != null && modeArg.isNotEmpty ? GameMode.fromCode(modeArg) : (decoded?.mode ?? (last != null ? GameMode.fromCode(last.mode) : GameMode.cards));
    _giantTier = last?.giantTier;
    _painting = widget.initialPainting || (last?.painting ?? false);
    // Remembered with the board; a link to a board that is not square turns it on for this picture.
    _expand = widget.initialExpand || (decoded?.expand ?? false) || (last?.expand ?? false);
    if (decoded != null) {
      // A code names its tier (legacy codes such as 5x5 map onto the ladder
      // step they were); the same step is kept for another mode.
      _tier = decoded.tierIndex < 0 ? 2 : decoded.tierIndex;
    } else if (last != null) {
      _tier = last.tier;
    } else if (ref.read(firstStepsProvider).calm) {
      // Guided start: one step up from the first board's nine cards.
      _tier = 1;
    } else {
      final idx = GridSpec.tiers.indexWhere((t) => t.cells == ref.read(settingsProvider).defaultGrid);
      _tier = idx < 0 ? 2 : idx;
    }
  }

  @override
  void dispose() {
    _stopListening();
    super.dispose();
  }

  void _stopListening() {
    if (_stream != null && _listener != null) _stream!.removeListener(_listener!);
    _stream = null;
    _listener = null;
  }

  /// Reads the picture's real dimensions from the same cached decode the
  /// preview shows, so the frame and the caption can follow the picture.
  void _resolveImage(Puzzle puzzle) {
    final url = puzzle.imageUrl;
    if (url.isEmpty || url == _resolvedUrl) return;
    _resolvedUrl = url;
    _stopListening();
    _imageSize = null;
    final stream = CachedUrlImage(url).resolve(ImageConfiguration.empty);
    final listener = ImageStreamListener((info, _) {
      final size = Size(info.image.width.toDouble(), info.image.height.toDouble());
      info.dispose();
      if (!mounted || _resolvedUrl != url) return;
      // The listener may fire synchronously from inside build; defer.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _resolvedUrl == url) setState(() => _imageSize = size);
      });
    }, onError: (_, _) {});
    _stream = stream;
    _listener = listener;
    stream.addListener(listener);
  }

  /// Who took the picture and where it is from: the credit its licence asks
  /// for, in full however long it is.
  Future<void> _showCredit(Puzzle puzzle) => showAppSheet(
        context,
        builder: (ctx) {
          final c = ctx.colors;
          // The name above the value (the iOS contact-card field), so a long
          // source or licence wraps under its own name.
          Widget row(String label, String value) => Padding(
                padding: const EdgeInsets.fromLTRB(16, 11, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: TextStyle(fontSize: TypeSize.footnote, fontWeight: FontWeight.w500, color: c.textSecondary)),
                      const SizedBox(height: 2),
                      Text(value, style: const TextStyle(fontSize: TypeSize.callout, height: 1.3, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              );
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const IconTile(icon: AppIcons.credit, size: IconTile.medium),
                    const SizedBox(width: 12),
                    Expanded(child: SheetHeader(title: 'Picture credit', subtitle: puzzle.title)),
                  ],
                ),
                const SizedBox(height: 16),
                SoftCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      row('Photographer', puzzle.author),
                      Divider(height: 0.5, thickness: 0.5, indent: 16, color: c.stroke),
                      row('Source', puzzle.source),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                BigButton(label: 'Done', kind: ButtonKind.secondary, onTap: () => Navigator.pop(ctx)),
              ],
            ),
          );
        },
      );

  Future<void> _discard(PuzzleProgress saved, BoardSpec savedSpec) async {
    final ok = await showAppAlert(
      context,
      title: 'Discard progress?',
      message: 'The board you started (${saved.moves} ${saved.moves == 1 ? 'move' : 'moves'} in) is deleted. Best scores and stars stay.',
      confirmLabel: 'Discard',
      destructive: true,
    );
    if (!ok || !mounted) return;
    // Keep the saved mode and size selected so the screen does not jump.
    setState(() {
      _mode = savedSpec.mode;
      _tier = savedSpec.tierIndex < 0 ? 2 : savedSpec.tierIndex;
      _painting = saved.painting;
      _expand = savedSpec.expand;
    });
    AppAnalytics.event('puzzle_discarded', {'from': 'setup', 'mode': savedSpec.mode.code, 'board': savedSpec.code, 'cards': savedSpec.cells, 'moves': saved.moves});
    await ref.read(progressProvider.notifier).discard(widget.puzzleId);
    if (!mounted) return;
    Haptics.medium();
    showToast(context, 'Progress discarded. Pick any mode or board.', icon: AppIcons.trash);
  }

  void _pickMode(GameMode m) {
    if (m == _mode) return;
    Haptics.selection();
    setState(() => _mode = m);
  }

  /// Quick play's "Another picture": a new picture from the same pool, on the
  /// same mode, size, Painting and Expand.
  void _anotherPicture(BoardSpec spec, bool painting) {
    final pool = ref.read(quickPlayPoolProvider);
    if (pool == null) return;
    final others = QuickPlayPool(pool.tier, [for (final z in pool.puzzles) if (z.id != widget.puzzleId) z]);
    final next = pickQuickPlay(others, _random);
    if (next == null) {
      showToast(context, 'No other picture to pick right now', icon: AppIcons.shuffle);
      return;
    }
    Haptics.light();
    AppAnalytics.event('quick_play', {'from': 'another', 'pool': pool.tier.name});
    final route = quickPlayRoute(next, saved: ref.read(puzzleProgressProvider(next.id)), board: spec.isGiant ? null : spec);
    context.pushReplacement('$route${painting ? '&painting=1' : ''}${_expand ? '&expand=1' : ''}');
  }

  static final _random = math.Random();

  Future<void> _offerUnlock(int tierIndex, BoardSpec t) async {
    final cost = Economy.tierUnlockCoins(tierIndex);
    final level = LevelRewards.tierUnlockLevel[tierIndex];
    await showAppSheet(
      context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const IconTile(icon: AppIcons.lock, size: IconTile.large),
                const SizedBox(width: 12),
                Expanded(
                  child: SheetHeader(
                    title: 'Unlock ${t.label} now',
                    subtitle: '${t.size} ${_mode.label.toLowerCase()} boards open at level $level. Unlock them early and keep the bigger rewards.',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            BigButton(
              label: 'Unlock for',
              trailing: Amount(currency: Currency.coins, value: cost, size: 18, color: context.onAccent),
              onTap: () async {
                final ok = await ref.read(profileProvider.notifier).unlockTier(_mode, tierIndex);
                if (!ctx.mounted || !mounted) return;
                Navigator.pop(ctx);
                if (ok) {
                  Sfx.instance.coin();
                  Haptics.success();
                  setState(() => _tier = tierIndex);
                  showToast(context, '${t.label} boards unlocked for ${_mode.label.toLowerCase()}', icon: AppIcons.unlock);
                } else {
                  showToast(context, 'Not enough coins. Visit the store or play more puzzles.', leading: const CoinIcon(size: 20));
                  context.push('/store');
                }
              },
            ),
            const SizedBox(height: 8),
            BigButton(label: 'Not now', kind: ButtonKind.ghost, onTap: () => Navigator.pop(ctx)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final puzzle = ref.watch(resolvedPuzzleProvider(widget.puzzleId));
    final progress = ref.watch(puzzleProgressProvider(widget.puzzleId));
    final profile = ref.watch(profileProvider).value;
    final profileN = ref.read(profileProvider.notifier);
    // Shapes, Painting and giant boards open as levels rise (or stay open once used).
    final open = ref.watch(openFeaturesProvider);
    if (puzzle != null) _resolveImage(puzzle);
    // Giant pack pictures offer only the giant sizes, all open with the pack.
    final giant = ref.watch(isGiantPuzzleProvider(widget.puzzleId));
    // Boards are laid out for the picture's proportions, read from the same
    // decode the game uses so the preview and the deal always agree. Until
    // it is in, the full-size picture's dimensions (or 3:4) stand in.
    final decoded = puzzle == null || puzzle.imageUrl.isEmpty ? null : ref.watch(puzzleImageFor(puzzle.imageUrl, giant: giant)).value;
    final known = decoded != null;
    final imageAspect = decoded != null
        ? decoded.width / decoded.height
        : (_imageSize == null ? BoardSpec.referenceAspect : _imageSize!.width / _imageSize!.height);
    // A saved board pins the choice to what was dealt; the state fields keep
    // the player's own pick for after a discard. A save whose board this
    // picture no longer deals (an older layout) cannot be resumed: it is
    // left to be replaced by the next game.
    final savedRow = progress != null && progress.inProgress ? progress : null;
    BoardSpec? savedSpec;
    if (savedRow != null) {
      final m = GameMode.fromCode(savedRow.mode);
      savedSpec = BoardSpec.fromSaved(m, savedRow.gridSize, imageAspect, layout: known ? savedRow.layout : null) ?? (known ? null : BoardSpec.fromCells(m, savedRow.gridSize));
      if (savedSpec != null && known && !Board.isValidLayout(savedSpec, savedRow.layout)) savedSpec = null;
    }
    final saved = savedSpec != null ? savedRow : null;
    // A shape not open yet (a preselection from a quest, say) falls back to Cards.
    final mode = saved != null ? savedSpec!.mode : (open.mode(_mode) ? _mode : GameMode.cards);
    // Giant pack pictures wait for giant boards to open (the pack itself can be bought before).
    final giantLocked = giant && saved == null && !open.giant;
    // Square sizes, or with Expand (when this picture offers it) sizes laid out for the picture.
    // Only once the picture's shape is known, so the switch does not come and go while it loads
    // (until then the square sizes show; they do not depend on the picture). The boards carry the
    // player's Expand either way, so the next picture is dealt the same way.
    final shapeKnown = known || _imageSize != null;
    final offersExpand = shapeKnown && BoardSpec.offersExpand(mode, imageAspect, giant: giant);
    final tiers = [for (final t in BoardSpec.ladder(mode, imageAspect, giant: giant, expand: _expand && offersExpand)) t.withExpand(_expand)];
    // A size picked on the other ladder (a normal tier carried to a Giant
    // pack picture, say) falls back to that ladder's first giant or Relaxed size.
    // A Giant pack picture opens on the giant size chosen last (or the first one).
    final giantPick = BoardSpec.isGiantTier(_tier) ? _tier : (_giantTier ?? BoardSpec.firstGiantTier);
    final pick = giant ? giantPick : (BoardSpec.isGiantTier(_tier) ? 2 : _tier);
    final maxTier = LevelRewards.maxTierIndex(profile?.level ?? 1);
    // A shape's smallest size is always open (Hexagons start at 4x4).
    bool tierLocked(BoardSpec t) => giant ? giantLocked : t.tier > maxTier && t != tiers.first && !profileN.hasTier(mode, t.tier);
    // A size this mode does not have (Hexagons have no 3x3) gives the nearest one; a remembered
    // size this player cannot play (another account on this device) steps down to the largest
    // open one.
    var at = tiers.indexOf(BoardSpec.nearest(tiers, pick));
    if (!giant) {
      while (at > 0 && tierLocked(tiers[at])) {
        at--;
      }
    }
    final spec = saved != null ? savedSpec! : tiers[at];
    final painting = saved != null ? saved.painting : (_painting && open.painting);
    // Pre-set pieces (docs/boards.md) are not played, so they do not pay.
    final coins = Economy.completionCoins(spec.playableCells, 3, mode: mode, painting: painting);
    final xp = Economy.completionXp(spec.playableCells, 3, mode: mode, painting: painting);
    final boardAspect = spec.tiling.boardAspect(imageAspect);
    // Short phones (SE, mini): a smaller preview, so every choice sits above Play.
    final compact = MediaQuery.sizeOf(context).height < 740;

    final footer = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // What a 3-star solve pays, next to the button that starts it.
        if (!giantLocked) ...[
          _RewardsLine(coins: coins, xp: xp, piggy: Economy.piggyPerPuzzle),
          const SizedBox(height: 10),
        ],
        // Shows the first-time intro of a shape or option that just opened.
        UnlockIntroHost(
          at: (path) => path == '/play/${widget.puzzleId}',
          onTryHere: (u) => setState(() {
            if (u.mode != null) _mode = u.mode!;
            if (u == Unlock.painting) _painting = true;
          }),
        ),
        if (giantLocked)
          BigButton(
            key: const ValueKey('giant-locked'),
            label: 'Giant boards open at level ${Unlock.giant.level}',
            kind: ButtonKind.secondary,
            icon: AppIcons.lock,
            // 027: the Giant pack's gate (level 10, or open now for tickets).
            onTap: () => showGiantGateFor(context, ref, puzzle?.packId),
          )
        else
        BigButton(
          key: const ValueKey('play-board'),
          // Just the word (owner, 2026-10-17): the board and its progress are shown above.
          label: saved != null ? 'Continue' : 'Play',
          onTap: () {
            // Remember this board (mode, size, Painting) for the next picture; a giant size is kept
            // apart from the normal one, each for its own kind of picture.
            final n = ref.read(settingsProvider.notifier);
            final last = ref.read(settingsProvider).lastBoard;
            final idx = spec.tierIndex < 0 ? 2 : spec.tierIndex;
            n.setLastBoard(LastBoard(
              mode: mode.code,
              tier: spec.isGiant ? (last?.tier ?? 2) : idx,
              giantTier: spec.isGiant ? idx : last?.giantTier,
              painting: painting,
              expand: _expand,
            ));
            if (!spec.isGiant) n.setDefaultGrid(GridSpec.tiers[idx].cells);
            // A saved board resumes the way it was saved, so only a new one carries Painting; Expand
            // goes along so the next picture is dealt the same way.
            final query = [if (saved == null && painting) 'painting=1', if (spec.expand) 'expand=1'];
            context.pushReplacement('/game/${widget.puzzleId}/${BoardCode.toPath(spec.fullCode)}${query.isEmpty ? '' : '?${query.join('&')}'}');
          },
        ),
        // The way to throw the board away: small, red, and it always asks first.
        if (saved != null) ...[const SizedBox(height: 4), _DiscardButton(onTap: () => _discard(saved, spec))],
        if (widget.fromQuick) ...[
          const SizedBox(height: 4),
          BigButton(
            key: const ValueKey('another-picture'),
            label: 'Another picture',
            kind: ButtonKind.ghost,
            height: 40,
            icon: AppIcons.shuffle,
            onTap: () => _anotherPicture(spec, painting),
          ),
        ],
      ],
    );

    // Preview in the real board's proportions with the chosen tiling drawn over the same centre
    // crop the board will use (BoxFit.cover == Tiling.crop), at most [maxHeight] tall.
    Widget preview(double maxHeight) => AnimatedSize(
      duration: A11y.motion(context, const Duration(milliseconds: 220)),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: AspectRatio(
          aspectRatio: boardAspect,
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.lg),
              border: Border.all(color: c.stroke),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                NetImage(url: puzzle!.imageUrl, blurhash: puzzle.blurhash),
                CustomPaint(
                  // A board in progress: the cards not in place yet are dimmed, so the
                  // preview shows how far along it is.
                  painter: _CutOverlay(
                    spec: spec,
                    imageAspect: imageAspect,
                    color: Colors.white.withValues(alpha: 0.7),
                    placed: saved?.layout == null ? null : {for (var i = 0; i < saved!.layout!.length; i++) if (saved.layout![i] == i) i},
                  ),
                ),
                // The credit waits behind a small camera button in the corner: the
                // photo and its cut lines stay clear, and a tap shows it in full.
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: PhotoButton(
                    key: const ValueKey('picture-credit'),
                    icon: AppIcons.credit,
                    size: 30,
                    semanticLabel: 'Picture credit',
                    onTap: () => _showCredit(puzzle),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ).animate().fadeIn(duration: 120.ms);

    Widget boardChip(int i) {
      final t = tiers[i];
      final locked = tierLocked(t);
      return _BoardChip(
        spec: t,
        step: i,
        steps: tiers.length,
        selected: t == spec,
        locked: locked,
        onTap: locked
            ? () => giant ? showLockedInfo(context, ref, Unlock.giant) : _offerUnlock(t.tier, t)
            : () {
                Haptics.selection();
                setState(() => _tier = t.tier);
              },
      );
    }

    // The choices under the preview (beside it on a wide window).
    List<Widget> options({required bool wide}) => [
      // A board in progress: what it is and how far along, instead of
      // pickers that cannot be used until it is discarded.
      if (saved != null) ...[
        _InProgressCard(spec: spec, saved: saved, painting: painting),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Continue where you left off, or discard it to pick another mode or size.',
            style: TextStyle(color: c.textSecondary, fontSize: TypeSize.footnote),
          ),
        ),
      ] else ...[
      // Guided start: said once, the first time the player picks a board.
      const OneTimeTip(id: 'board', icon: AppIcons.bigBoard, text: OneTimeTip.boardText, padding: EdgeInsets.only(bottom: 14)),
      const _SectionLabel('Mode'),
      const SizedBox(height: 8),
      _ModePicker(
        selected: mode,
        isOpen: open.mode,
        onTap: (m) => !open.mode(m) ? showLockedInfo(context, ref, Unlocks.ofMode(m)!) : _pickMode(m),
      ),
      SizedBox(height: compact ? 14 : 20),
      const _SectionLabel('Board'),
      if (giant) ...[
        const SizedBox(height: 2),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            giantLocked
                ? 'Giant boards of 100 cards and more open at level ${Unlock.giant.level}. This pack is ready for you then.'
                : 'Giant boards of 100 cards and more, all open with this pack. Pinch to zoom in while you play.',
            style: TextStyle(color: c.textSecondary, fontSize: TypeSize.footnote),
          ),
        ),
      ],
      const SizedBox(height: 8),
      // On a phone the row runs to the screen edges, so the next size peeks in as a
      // hint to scroll; a wide window shows every size at once.
      if (wide)
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(spacing: 8, runSpacing: 8, children: [for (var i = 0; i < tiers.length; i++) boardChip(i)]),
        )
      else
      SizedBox(
        // 167: the chips' two lines grow with Larger Text; so does the row
        // (the ladder meter under them keeps its 18 pt).
        height: MediaQuery.textScalerOf(context).scale(52) + 18,
        child: OverflowBox(
          maxWidth: MediaQuery.sizeOf(context).width,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: tiers.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) => boardChip(i),
          ),
        ),
      ),
      SizedBox(height: compact ? 12 : 16),
      // A picture that is not square enough for its square boards: Expand plays it whole.
      if (offersExpand) ...[
        _ExpandTile(
          on: _expand,
          onChanged: (v) {
            Haptics.selection();
            setState(() => _expand = v);
          },
        ),
        const SizedBox(height: 10),
      ],
      _PaintingTile(
        on: painting,
        enabled: saved == null,
        locked: saved == null && !open.painting,
        onLocked: () => showLockedInfo(context, ref, Unlock.painting),
        onChanged: (v) {
          Haptics.selection();
          setState(() => _painting = v);
        },
      ),
      ],
    ];

    // The website layout: the preview large on the left, the choices and Play beside it.
    final wide = context.isExpanded && puzzle != null;

    return Scaffold(
      extendBodyBehindAppBar: true,
      // The footer floats over the page and the choices scroll under it.
      extendBody: true,
      bottomNavigationBar: puzzle == null || wide ? null : _GlassFooter(glass: _moreBelow, child: footer),
      appBar: GlassAppBar(
        contentWidth: PageWidth.wide,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: RoundIconButton(icon: AppIcons.back, size: 38, onTap: () => context.canPop() ? context.pop() : context.go('/home')),
        ),
        title: Text(puzzle?.title ?? 'Puzzle'),
      ),
      body: puzzle == null
          // A link to a picture that is gone (or someone else's photo) says so once the
          // catalogue and the player's own photos have answered.
          ? (ref.watch(allPuzzlesProvider).hasValue && ref.watch(myPuzzleByIdProvider(widget.puzzleId)).hasValue
              ? const EmptyState(
                  key: ValueKey('picture-not-available'),
                  icon: AppIcons.image,
                  title: 'Picture not available',
                  message: 'The link may be out of date, or the picture belongs to another player.',
                )
              : const Loader())
          : wide
              // The body's top padding is the bar's height.
              ? Builder(
                  builder: (context) => Padding(
                    padding: EdgeInsets.fromLTRB(20 + pageInsetOf(context), MediaQuery.paddingOf(context).top + 8, 20 + pageInsetOf(context), 24),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 7,
                          child: Column(
                            children: [
                              preview(MediaQuery.sizeOf(context).height - MediaQuery.paddingOf(context).top - 80),
                              // A solved picture: its best result under the preview.
                              if (progress?.completed == true) ...[
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Stars(count: progress!.stars, size: 13),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Best ${countOf(progress.bestMoves ?? progress.moves, 'move')}',
                                      style: TextStyle(fontSize: TypeSize.footnote, fontWeight: FontWeight.w600, color: c.textSecondary),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 40),
                        Expanded(
                          flex: 5,
                          child: SingleChildScrollView(
                            physics: const BouncingScrollPhysics(),
                            child: Column(children: [...options(wide: true), const SizedBox(height: 28), footer]),
                          ),
                        ),
                      ],
                    ),
                  ),
              )
          : NotificationListener<ScrollMetricsNotification>(
              onNotification: (n) {
                if (n.depth == 0) _onMetrics(n.metrics);
                return false;
              },
              child: NotificationListener<ScrollUpdateNotification>(
                onNotification: (n) {
                  if (n.depth == 0) _onMetrics(n.metrics);
                  return false;
                },
                // The body's bottom padding is the footer's height.
                child: Builder(
                  builder: (context) => SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + 4, 20, MediaQuery.paddingOf(context).bottom + 16),
                      child: Column(
                        children: [
                          preview(MediaQuery.sizeOf(context).height * (compact ? 0.24 : 0.32)),
                          // A solved picture: its best result under the preview.
                          if (progress?.completed == true) ...[
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Stars(count: progress!.stars, size: 13),
                                const SizedBox(width: 6),
                                Text(
                                  'Best ${countOf(progress.bestMoves ?? progress.moves, 'move')}',
                                  style: TextStyle(fontSize: TypeSize.footnote, fontWeight: FontWeight.w600, color: c.textSecondary),
                                ),
                              ],
                            ),
                          ],
                          SizedBox(height: compact ? 14 : 20),
                          ...options(wide: false),
                        ],
                      ),
                    ),
                ),
              ),
            ),
    );
  }

  static String _fmtMult(double m) => m == m.roundToDouble() ? '${m.toInt()}.0' : m.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');
}

/// The Painting option: works with every shape and size and pays
/// [Economy.paintingMultiplier] more. Frozen while a board is in progress.
class _PaintingTile extends StatelessWidget {
  const _PaintingTile({required this.on, required this.enabled, required this.onChanged, this.locked = false, this.onLocked});
  final bool on;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  /// Not open yet (level below [Unlock.painting]): a tap explains when it opens.
  final bool locked;
  final VoidCallback? onLocked;

  /// What Painting is, in one line under its name (locked or open).
  static const explainer = 'Black and white until cards lock';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Pressable(
      key: const ValueKey('painting-option'),
      onTap: locked ? onLocked : (enabled ? () => onChanged(!on) : null),
      scale: 0.99,
      child: Opacity(
        // Locked is said by the level chip, not by fading the text.
        opacity: locked ? 1 : (enabled || on ? 1 : 0.45),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          decoration: BoxDecoration(
            color: on ? c.accentTint : c.card,
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(color: on ? context.accent : c.stroke),
          ),
          child: Row(
            children: [
              // Sized to the two lines beside it.
              const IconTile(icon: AppIcons.painting, size: IconTile.medium),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        // Keyed while on: the bonus is part of the rewards in the footer.
                        Expanded(child: Text('Painting · x${_DifficultyScreenState._fmtMult(Economy.paintingMultiplier)}', key: on ? const ValueKey('painting-bonus') : null, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: TypeSize.body))),
                        // Locked: the level chip beside the name, so the line under it runs the full width.
                        if (locked) ...[const SizedBox(width: 8), _LevelChip(level: Unlock.painting.level)],
                      ],
                    ),
                    const SizedBox(height: 1),
                    Text(
                      explainer,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: TypeSize.footnote, height: 1.3, color: c.textSecondary),
                    ),
                  ],
                ),
              ),
              if (!locked) ...[
                const SizedBox(width: 8),
                CupertinoSwitch(value: on, activeTrackColor: context.highContrast ? context.colors.success : Brand.success, onChanged: enabled ? onChanged : null),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Expand: the sizes take the columns and rows that suit the picture, so the
/// whole picture is played instead of the square board's crop. Shown only for
/// a picture that offers it ([BoardSpec.offersExpand]); remembered with the
/// board ([LastBoard.expand]). The same row as Painting.
class _ExpandTile extends StatelessWidget {
  const _ExpandTile({required this.on, required this.onChanged});
  final bool on;
  final ValueChanged<bool> onChanged;

  /// What Expand does, in one line under its name.
  static const explainer = 'Cut to fit the whole picture';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Pressable(
      key: const ValueKey('expand-option'),
      onTap: () => onChanged(!on),
      scale: 0.99,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        decoration: BoxDecoration(
          color: on ? c.accentTint : c.card,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: on ? context.accent : c.stroke),
        ),
        child: Row(
          children: [
            const IconTile(icon: AppIcons.expand, size: IconTile.medium),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Expand', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, fontSize: TypeSize.body)),
                  const SizedBox(height: 1),
                  Text(explainer, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: TypeSize.footnote, height: 1.3, color: c.textSecondary)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            CupertinoSwitch(value: on, activeTrackColor: context.highContrast ? context.colors.success : Brand.success, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

/// "[lock] Level 8" beside Painting's name until it opens: a quiet grey chip,
/// readable at full strength instead of a faded row.
class _LevelChip extends StatelessWidget {
  const _LevelChip({required this.level});
  final int level;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: context.isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(AppIcons.lock, size: 11, color: c.textSecondary),
          const SizedBox(width: 4),
          Text('Level $level', style: TextStyle(fontSize: TypeSize.caption, fontWeight: FontWeight.w600, color: c.textSecondary)),
        ],
      ),
    );
  }
}

/// Small outline drawing of a tiling for the mode tiles.
class _ModePreview extends CustomPainter {
  _ModePreview({required this.mode, required this.color});
  final GameMode mode;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeJoin = StrokeJoin.round;
    // About the same footprint for every mode, so no drawing looks heavier than another.
    final (cols, rows) = switch (mode) {
      GameMode.cards => (3, 2),
      GameMode.squares => (3, 2),
      GameMode.triangles => (5, 2),
      GameMode.hexagons => (3, 2),
    };
    final tiling = Tiling.of(mode, cols, rows);
    final box = Offset.zero & size;
    // Regular cells, centred in the icon box.
    final fitted = tiling.fit(box.size, box.width / box.height);
    final area = Rect.fromCenter(center: box.center, width: fitted.width, height: fitted.height);
    for (var s = 0; s < tiling.cells; s++) {
      final poly = tiling.polygon(s, area.size);
      final path = Path()..moveTo(poly.first.dx + area.left, poly.first.dy + area.top);
      for (final v in poly.skip(1)) {
        path.lineTo(v.dx + area.left, v.dy + area.top);
      }
      path.close();
      canvas.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(_ModePreview old) => old.mode != mode || old.color != color;
}

/// Draws the selected tiling's cell outlines over the preview, laid out the
/// way the board will be for a picture of [imageAspect] (same fit and
/// centre crop as the game, see [Tiling.fit] and [Tiling.crop]).
class _CutOverlay extends CustomPainter {
  _CutOverlay({required this.spec, required this.imageAspect, required this.color, this.placed});
  final BoardSpec spec;
  final double imageAspect;
  final Color color;

  /// Slots whose card is in place on a saved board; every other cell is dimmed.
  final Set<int>? placed;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final tiling = spec.tiling;
    // The frame already has the board's aspect, so this fills it; should the
    // two ever differ, the tiling is still centred in the board's proportions.
    final fitted = tiling.fit(size, imageAspect);
    final origin = Offset((size.width - fitted.width) / 2, (size.height - fitted.height) / 2);
    // Only the cuts inside the picture: edges on the board's outline are left
    // to the frame's own rounded border, which a square outline would cross
    // at the corners.
    const eps = 0.5;
    bool onOutline(Offset a, Offset b) =>
        (a.dx.abs() < eps && b.dx.abs() < eps) ||
        ((a.dx - fitted.width).abs() < eps && (b.dx - fitted.width).abs() < eps) ||
        (a.dy.abs() < eps && b.dy.abs() < eps) ||
        ((a.dy - fitted.height).abs() < eps && (b.dy - fitted.height).abs() < eps);
    final placed = this.placed;
    if (placed != null) {
      final dim = Paint()..color = Colors.black.withValues(alpha: 0.55);
      for (var s = 0; s < tiling.cells; s++) {
        if (placed.contains(s)) continue;
        final poly = tiling.polygon(s, fitted);
        final cell = Path()..moveTo(poly.first.dx + origin.dx, poly.first.dy + origin.dy);
        for (final v in poly.skip(1)) {
          cell.lineTo(v.dx + origin.dx, v.dy + origin.dy);
        }
        canvas.drawPath(cell..close(), dim);
      }
    }
    final path = Path();
    for (var s = 0; s < tiling.cells; s++) {
      final poly = tiling.polygon(s, fitted);
      for (var i = 0; i < poly.length; i++) {
        final a = poly[i], b = poly[(i + 1) % poly.length];
        if (onOutline(a, b)) continue;
        path
          ..moveTo(a.dx + origin.dx, a.dy + origin.dy)
          ..lineTo(b.dx + origin.dx, b.dy + origin.dy);
      }
    }
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(_CutOverlay old) => old.spec != spec || old.imageAspect != imageAspect || old.color != color || !setEquals(old.placed, placed);
}

/// The Play footer: transparent over the canvas while the choices end above
/// it, glass with a hairline once they continue underneath.
class _GlassFooter extends StatelessWidget {
  const _GlassFooter({required this.glass, required this.child});
  final bool glass;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      visible: glass,
      hairline: Border(top: BorderSide(color: context.colors.stroke, width: 0.5)),
      child: SafeArea(
        top: false,
        child: Padding(padding: const EdgeInsets.fromLTRB(20, 12, 20, 12), child: child),
      ),
    );
  }
}

/// Small section title, lighter than a page heading: the choices are the content.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: Text(title, style: const TextStyle(fontSize: TypeSize.headline, fontWeight: FontWeight.w700, letterSpacing: -0.3)),
      );
}

/// The four modes. Each says what it cuts the picture into (its cells drawn
/// small), what it pays (the multiplier) and, until it opens, the level it
/// opens at. The choice is the tinted tile with the cobalt outline, the same
/// selected state as the board sizes below.
class _ModePicker extends StatelessWidget {
  const _ModePicker({required this.selected, required this.isOpen, required this.onTap});
  final GameMode selected;
  final bool Function(GameMode) isOpen;
  final ValueChanged<GameMode> onTap;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          for (final m in GameMode.values) ...[
            if (m != GameMode.cards) const SizedBox(width: 8),
            Expanded(
              child: Semantics(
                button: true,
                selected: m == selected,
                child: Pressable(
                  key: ValueKey('mode-${m.code}'),
                  onTap: () => onTap(m),
                  scale: 0.96,
                  child: _ModeTile(mode: m, selected: m == selected, open: isOpen(m)),
                ),
              ),
            ),
          ],
        ],
      );
}

String _modeMult(GameMode m) => 'x${_DifficultyScreenState._fmtMult(m.multiplier)}';

/// One mode, a card like the board sizes below: its cells drawn small (cobalt
/// when chosen), its name, its multiplier; until it opens, the drawing fades
/// and a lock and the level take the multiplier's place.
class _ModeTile extends StatelessWidget {
  const _ModeTile({required this.mode, required this.selected, required this.open});
  final GameMode mode;
  final bool selected;
  final bool open;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return _SelectedBadge(
      selected: selected,
      child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      height: MediaQuery.textScalerOf(context).scale(84),
      decoration: BoxDecoration(
        color: selected ? c.accentTint : c.card,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: selected ? context.accent : c.controlStroke, width: selected ? 1.5 : 1),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 34,
            height: 26,
            child: CustomPaint(painter: _ModePreview(mode: mode, color: !open ? c.textTertiary.withValues(alpha: 0.5) : (selected ? context.accent : c.textSecondary))),
          ),
          const SizedBox(height: 7),
          Text(
            mode.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: TypeSize.footnote, fontWeight: FontWeight.w700, letterSpacing: -0.2, color: !open ? c.textTertiary : (selected ? context.accent : c.textPrimary)),
          ),
          const SizedBox(height: 1),
          if (open)
            Text(_modeMult(mode), style: TextStyle(fontSize: TypeSize.micro, fontWeight: FontWeight.w600, color: selected ? context.accent : c.textTertiary))
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(AppIcons.lock, size: 10, color: c.textTertiary),
                const SizedBox(width: 3),
                Flexible(child: Text('Level ${Unlocks.ofMode(mode)!.level}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: TypeSize.micro, fontWeight: FontWeight.w600, color: c.textTertiary))),
              ],
            ),
        ],
      ),
      ),
    );
  }
}

/// Settings > Accessibility > Differentiate without colour: a check in the corner of the selected
/// tile or chip, so the choice does not rest on the accent colour alone.
class _SelectedBadge extends StatelessWidget {
  const _SelectedBadge({required this.selected, required this.child});
  final bool selected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!selected || !A11y.symbolsOf(context)) return child;
    return Stack(
      // Passthrough: the tile keeps the size its row gives it.
      fit: StackFit.passthrough,
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(top: 4, right: 4, child: Icon(AppIcons.checkmarkCircleFill, size: 14, color: context.accent)),
      ],
    );
  }
}

/// One board size: its cut ("5x4") over its name ("Relaxed"), and a ladder
/// meter under them: one rising bar per size, this size's steps lit, so the
/// row reads as a ladder at a glance. Locked sizes show a lock instead of the
/// meter; a tap offers the unlock.
class _BoardChip extends StatelessWidget {
  const _BoardChip({required this.spec, required this.step, required this.steps, required this.selected, required this.locked, this.onTap});
  final BoardSpec spec;

  /// Place on the ladder shown (0-based) and its length.
  final int step;
  final int steps;
  final bool selected;
  final bool locked;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = selected ? context.accent : (locked ? c.textTertiary : c.textPrimary);
    return Pressable(
      onTap: onTap,
      child: _SelectedBadge(
        selected: selected,
        child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        constraints: const BoxConstraints(minWidth: 74),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? c.accentTint : c.card,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: selected ? context.accent : c.controlStroke, width: selected ? 1.5 : 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(spec.size, style: TextStyle(fontWeight: FontWeight.w700, fontSize: TypeSize.body, letterSpacing: -0.2, color: fg)),
            Text(spec.label, style: TextStyle(fontSize: TypeSize.micro, fontWeight: FontWeight.w500, color: selected ? context.accent : c.textTertiary)),
            const SizedBox(height: 6),
            SizedBox(
              height: 12,
              child: locked
                  ? Icon(AppIcons.lock, size: 11, color: c.textTertiary)
                  : _LadderSteps(step: step, of: steps, color: context.accent, rest: selected ? context.accent.withValues(alpha: 0.22) : c.stroke),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

/// A row of short rising bars, the first [step] + 1 lit: how far up the size
/// ladder a board is, like a signal meter.
class _LadderSteps extends StatelessWidget {
  const _LadderSteps({required this.step, required this.of, required this.color, required this.rest});
  final int step;
  final int of;
  final Color color;
  final Color rest;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var k = 0; k < of; k++) ...[
            if (k > 0) const SizedBox(width: 2),
            Container(
              width: 4,
              height: 4 + 8 * (k + 1) / of,
              // Differentiate without colour: the steps above this size are outlines, not fills.
              decoration: k > step && A11y.symbolsOf(context)
                  ? BoxDecoration(border: Border.all(color: context.colors.textTertiary, width: 1), borderRadius: BorderRadius.circular(1))
                  : BoxDecoration(color: k <= step ? color : rest, borderRadius: BorderRadius.circular(1)),
            ),
          ],
        ],
      );
}

/// "Up to [coin] 40 · 80 XP · [piggy] +5": what a 3-star solve pays.
class _RewardsLine extends StatelessWidget {
  const _RewardsLine({required this.coins, required this.xp, required this.piggy});
  final int coins;
  final int xp;
  final int piggy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = TextStyle(fontSize: TypeSize.footnote, fontWeight: FontWeight.w600, color: c.textSecondary);
    Widget dot() => Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text('·', style: style));
    // Scales down rather than overflowing with big numbers or Larger Text.
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('3 stars pay up to', style: style.copyWith(fontWeight: FontWeight.w500)),
        const SizedBox(width: 6),
        Amount(currency: Currency.coins, value: coins, size: 15, fontSize: TypeSize.footnote, weight: FontWeight.w700),
        dot(),
        Text('${formatCount(xp)} XP', style: style.copyWith(color: c.textPrimary, fontWeight: FontWeight.w700)),
        dot(),
        Icon(AppIcons.piggy, size: 14, color: c.textSecondary),
        const SizedBox(width: 3),
        Text('+$piggy', style: style.copyWith(color: c.textPrimary, fontWeight: FontWeight.w700)),
      ],
      ),
    );
  }
}

/// "Discard progress" under Continue: a quiet destructive text button (red,
/// 44 pt to tap) instead of a second full-size button next to the primary.
class _DiscardButton extends StatelessWidget {
  const _DiscardButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final red = context.colors.danger;
    return Pressable(
      key: const ValueKey('discard-progress'),
      onTap: onTap,
      child: SizedBox(
        height: 44,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(AppIcons.trash, size: 16, color: red),
            const SizedBox(width: 6),
            Text('Discard progress', style: TextStyle(fontSize: TypeSize.body, fontWeight: FontWeight.w600, color: red)),
          ],
        ),
      ),
    );
  }
}

/// The board in progress for this picture: mode and size, how many cards
/// are in place, moves and time.
class _InProgressCard extends StatelessWidget {
  const _InProgressCard({required this.spec, required this.saved, required this.painting});
  final BoardSpec spec;
  final PuzzleProgress saved;
  final bool painting;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final layout = saved.layout ?? const <int>[];
    // Pre-set pieces (docs/boards.md) count in neither number.
    final tiling = layout.length == spec.cells ? spec.tiling : null;
    final placed = [for (var i = 0; i < layout.length; i++) if (layout[i] == i && !(tiling?.isPreset(i) ?? false)) i].length;
    final cells = spec.playableCells;
    return SoftCard(
      key: const ValueKey('board-in-progress'),
      padding: Insets.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(color: c.accentTint, borderRadius: BorderRadius.circular(Radii.md)),
                child: CustomPaint(painter: _ModePreview(mode: spec.mode, color: context.accent)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Board in progress', style: TextStyle(fontWeight: FontWeight.w700, fontSize: TypeSize.callout)),
                    const SizedBox(height: 2),
                    Text(
                      '${spec.mode.label} · ${spec.size} ${spec.label}${painting ? ' · Painting' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: TypeSize.footnote, color: c.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ProgressBar(value: cells == 0 ? 0 : placed / cells, height: 6),
          const SizedBox(height: 8),
          Row(
            children: [
              Flexible(child: Text('$placed of $cells in place', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: TypeSize.footnote, fontWeight: FontWeight.w600))),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${saved.moves} ${saved.moves == 1 ? 'move' : 'moves'} · ${formatDuration(saved.elapsedSeconds)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: TypeSize.footnote, color: c.textSecondary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
