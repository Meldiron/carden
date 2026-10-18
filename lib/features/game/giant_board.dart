import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/a11y.dart';
import '../../core/haptics.dart';
import '../../core/theme/tokens.dart';
import '../../game/board.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';
import 'board_widget.dart';

/// The tools around a giant board (100 to 300 cards and more), chosen from
/// how big-board jigsaw apps help on a phone (see docs/giant-boards.md):
/// a bar with Gather and the zoom buttons, an overview map of the whole board
/// while zoomed in (showing where the selected card belongs),
/// a pointer to a selected card that is out of view, and calm milestones on
/// the way (the frame, halfway).

/// Above a giant board: Gather (at any zoom), the zoom level and the overview
/// map switch (while zoomed in), zoom in, and back to the whole board.
class GiantBoardBar extends StatelessWidget {
  const GiantBoardBar({
    super.key,
    required this.zoom,
    required this.width,
    required this.showMap,
    required this.onMap,
    this.onGather,
  });

  final BoardZoom zoom;
  final double width;
  final bool showMap;
  final VoidCallback onMap;

  /// Gather: brings the cards that belong in view into it (at any zoom). Null while there is
  /// nothing to gather for the view: the button stays, dimmed.
  final VoidCallback? onGather;

  static const height = 44.0;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // Narrow boards (smaller phones, wide pictures) get tighter chips.
    final compact = width < 330;
    return SizedBox(
      width: width,
      height: height,
      child: ListenableBuilder(
        listenable: zoom,
        builder: (context, _) {
          final canZoomIn = zoom.zoom < zoom.limit - 0.01;
          return Row(
            children: [
              _BarChip(key: const ValueKey('giant-gather'), icon: AppIcons.gather, label: 'Gather', compact: compact, onTap: onGather),
              const SizedBox(width: 10),
              Expanded(
                child: LayoutBuilder(
                  // The zoom level, while zoomed in and only when it fits whole.
                  builder: (context, cons) => !zoom.zoomed || cons.maxWidth < 72
                      ? const SizedBox.shrink()
                      : Text(
                          'Zoom ${zoom.zoom.toStringAsFixed(1)}x',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: TypeSize.caption, fontWeight: FontWeight.w500, color: c.textSecondary),
                        ),
                ),
              ),
              if (zoom.zoomed) ...[
                RoundIconButton(
                  key: const ValueKey('giant-map'),
                  // Differentiate without colour: the map glyph fills in while the map is on.
                  icon: showMap && A11y.symbolsOf(context) ? AppIcons.minimapOn : AppIcons.minimap,
                  size: 34,
                  color: showMap ? c.accentTint : null,
                  iconColor: showMap ? context.accent : c.textSecondary,
                  onTap: onMap,
                ),
                const SizedBox(width: 8),
              ],
              RoundIconButton(
                key: const ValueKey('zoom-in'),
                icon: AppIcons.zoom,
                size: 34,
                iconColor: canZoomIn ? context.accent : c.textTertiary,
                onTap: canZoomIn ? () => zoom.zoomTo(zoom.zoomed ? math.min(zoom.limit, zoom.zoom * 1.6) : zoom.step) : null,
              ),
              const SizedBox(width: 8),
              RoundIconButton(
                key: const ValueKey('zoom-whole-board'),
                icon: AppIcons.wholeBoard,
                size: 34,
                iconColor: zoom.zoomed ? context.accent : c.textTertiary,
                onTap: zoom.zoomed ? zoom.reset : null,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A small capsule button: icon and label (Gather). Dimmed and still while [onTap] is null.
class _BarChip extends StatelessWidget {
  const _BarChip({super.key, required this.icon, required this.label, this.compact = false, required this.onTap});
  final IconData icon;
  final String label;
  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = c.textSecondary;
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        child: AnimatedOpacity(
          opacity: onTap == null ? 0.4 : 1,
          duration: const Duration(milliseconds: 160),
          child: Container(
            height: 34,
            padding: EdgeInsets.symmetric(horizontal: compact ? 9 : 12),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: c.stroke),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: fg),
                SizedBox(width: compact ? 4 : 6),
                Text(label, style: TextStyle(fontSize: compact ? TypeSize.caption : TypeSize.footnote, fontWeight: FontWeight.w600, color: fg)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The whole board in miniature while zoomed in: the cards as they lie now
/// (cards in place bright, the rest darker, so the unfinished areas are easy
/// to spot), the part in view outlined, and the selected card marked with
/// where it belongs (Locate): a ring there and a line to it. Tap or drag on
/// the map to move the view there.
class GiantMinimap extends StatelessWidget {
  const GiantMinimap({
    super.key,
    required this.image,
    required this.board,
    required this.boardSize,
    required this.zoom,
    required this.width,
    this.selected,
    this.painting = false,
    this.locate,
    this.others = const {},
    this.otherPoints = const [],
  });

  final ui.Image image;
  final Board board;

  /// The board's size on screen at zoom 1.
  final Size boardSize;
  final BoardZoom zoom;
  final double width;
  final int? selected;
  final bool painting;

  /// The located card's slot: the selected card (not in place).
  final int? locate;

  /// Play together: where other players' held cards are (slot to the player's colour), as dots.
  final Map<int, Color> others;

  /// Play together: other players' dragged cards, where their finger is (board coordinates).
  final List<(Offset, Color)> otherPoints;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final scale = width / boardSize.width;
    final size = Size(width, boardSize.height * scale);
    const inset = 3.0;
    Offset toBoard(Offset local) => (local - const Offset(inset, inset)) / scale;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (d) {
        Haptics.selection();
        zoom.centreOn(toBoard(d.localPosition));
      },
      onPanStart: (d) => zoom.lookAt(toBoard(d.localPosition)),
      onPanUpdate: (d) => zoom.lookAt(toBoard(d.localPosition)),
      child: Container(
        key: const ValueKey('giant-minimap'),
        width: size.width + 2 * inset,
        height: size.height + 2 * inset,
        padding: const EdgeInsets.all(inset),
        decoration: BoxDecoration(
          color: c.card.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.stroke),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 14, offset: const Offset(0, 4))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: Stack(
            children: [
              RepaintBoundary(child: CustomPaint(size: size, painter: _MiniBoardPainter(image: image, board: board, boardSize: boardSize, painting: painting))),
              ListenableBuilder(
                listenable: zoom,
                builder: (context, _) => CustomPaint(
                  size: size,
                  painter: _ViewPainter(
                    view: Rect.fromLTRB(zoom.visible.left * scale, zoom.visible.top * scale, zoom.visible.right * scale, zoom.visible.bottom * scale),
                    selected: selected == null || selected == locate ? null : board.tiling.cellCenter(selected!, boardSize) * scale,
                    from: locate == null ? null : board.tiling.cellCenter(locate!, boardSize) * scale,
                    home: locate == null ? null : board.tiling.cellCenter(board.homeOf(locate!), boardSize) * scale,
                    accent: context.accent,
                  ),
                ),
              ),
              for (final (point, colour) in [
                for (final e in others.entries)
                  if (e.key < board.cells) (board.tiling.cellCenter(e.key, boardSize), e.value),
                ...otherPoints,
              ])
                Positioned(
                  left: point.dx * scale - 3.5,
                  top: point.dy * scale - 3.5,
                  child: IgnorePointer(
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(color: colour, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 1)),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniBoardPainter extends CustomPainter {
  _MiniBoardPainter({required this.image, required this.board, required this.boardSize, required this.painting});
  final ui.Image image;
  final Board board;
  final Size boardSize;
  final bool painting;

  static const _grey = ColorFilter.matrix(<double>[
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0, 0, 0, 1, 0,
  ]);

  @override
  void paint(Canvas canvas, Size size) {
    final tiling = board.tiling;
    canvas.save();
    canvas.scale(size.width / boardSize.width);
    final crop = tiling.crop(Size(image.width.toDouble(), image.height.toDouble()), boardSize);
    final colour = Paint()..filterQuality = FilterQuality.low;
    final grey = Paint()
      ..filterQuality = FilterQuality.low
      ..colorFilter = _grey;
    final shade = Paint()..color = Colors.black.withValues(alpha: 0.3);
    for (var slot = 0; slot < board.cells; slot++) {
      final locked = board.isLocked(slot);
      final bounds = tiling.cellBounds(slot, boardSize);
      final poly = tiling.polygon(slot, boardSize);
      final rect = poly.length == 4 && poly.every((p) => (p.dx - bounds.left).abs() < 0.01 || (p.dx - bounds.right).abs() < 0.01);
      canvas.save();
      if (rect) {
        canvas.clipRect(bounds);
      } else {
        canvas.clipPath(Path()..addPolygon(poly, true));
      }
      canvas.drawImageRect(image, tiling.sourceRect(board.slots[slot], crop), bounds, painting && !locked ? grey : colour);
      if (!locked) canvas.drawRect(bounds, shade);
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MiniBoardPainter old) =>
      old.board != board || old.image != image || old.painting != painting || old.boardSize != boardSize;
}

class _ViewPainter extends CustomPainter {
  _ViewPainter({required this.view, required this.selected, required this.accent, this.from, this.home});
  final Rect view;
  final Offset? selected;
  final Color accent;

  /// A located card: where it lies and where it belongs.
  final Offset? from;
  final Offset? home;

  @override
  void paint(Canvas canvas, Size size) {
    final r = view.intersect(Offset.zero & size);
    // Everything outside the view a touch darker, the view outlined.
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(r, const Radius.circular(3)));
    canvas.drawPath(outside, Paint()..color = Colors.black.withValues(alpha: 0.22));
    canvas.drawRRect(
      RRect.fromRectAndRadius(r.deflate(0.75), const Radius.circular(3)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.white,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(r.inflate(0.75), const Radius.circular(3.5)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = accent,
    );
    final s = selected;
    if (s != null) {
      canvas.drawCircle(s, 4.2, Paint()..color = Colors.white);
      canvas.drawCircle(s, 2.8, Paint()..color = accent);
    }
    final f = from, h = home;
    if (f != null && h != null) {
      // A line from the card to its place, the card as a dot, its place as a ring.
      canvas.drawLine(f, h, Paint()
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round
        ..color = Colors.black.withValues(alpha: 0.35));
      canvas.drawLine(f, h, Paint()
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round
        ..color = Colors.white);
      canvas.drawCircle(f, 3.6, Paint()..color = Colors.white);
      canvas.drawCircle(f, 2.4, Paint()..color = accent);
      canvas.drawCircle(h, 5.6, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.4
        ..color = Colors.white);
      canvas.drawCircle(h, 5.6, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..color = accent);
    }
  }

  @override
  bool shouldRepaint(_ViewPainter old) =>
      old.view != view || old.selected != selected || old.accent != accent || old.from != from || old.home != home;
}

/// While zoomed in with a card selected that is out of view: a small round
/// pointer on the edge of the view, turned towards the card. Tap it to bring
/// the card back into view.
class OffscreenSelection extends StatelessWidget {
  const OffscreenSelection({super.key, required this.zoom, required this.board, required this.boardSize, required this.selected, this.point, this.color, this.onColor, this.label});
  final BoardZoom zoom;
  final Board board;
  final Size boardSize;
  final int? selected;

  /// Play together: a card another player is dragging, where their finger is (board coordinates),
  /// instead of [selected]'s slot.
  final Offset? point;

  /// Play together: another player's held card, in their colour and with their initial instead of
  /// the arrow (the pointer's place on the edge shows the way).
  final Color? color;
  final Color? onColor;
  final String? label;

  static const _size = 36.0;

  @override
  Widget build(BuildContext context) {
    final slot = selected;
    if (slot == null && point == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: zoom,
      builder: (context, _) {
        if (!zoom.zoomed) return const SizedBox.shrink();
        final centre = point ?? board.tiling.cellCenter(slot!, boardSize);
        final p = zoom.toViewport(centre);
        final view = Offset.zero & boardSize;
        if (view.deflate(4).contains(p)) return const SizedBox.shrink();
        final inset = view.deflate(_size / 2 + 6);
        final at = Offset(p.dx.clamp(inset.left, inset.right), p.dy.clamp(inset.top, inset.bottom));
        final angle = math.atan2(p.dy - at.dy, p.dx - at.dx) + math.pi / 2;
        return Positioned(
          left: at.dx - _size / 2,
          top: at.dy - _size / 2,
          child: Pressable(
            key: ValueKey(label == null ? 'giant-offscreen-selection' : 'giant-offscreen-$label-${slot ?? 'drag'}'),
            onTap: () => zoom.centreOn(centre),
            child: Container(
              width: _size,
              height: _size,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color ?? context.accentFill,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 10, offset: const Offset(0, 3))],
              ),
              child: label != null
                  ? Text(label!, textScaler: TextScaler.noScaling, style: TextStyle(color: onColor ?? context.onAccent, fontSize: TypeSize.body, fontWeight: FontWeight.w700))
                  : Transform.rotate(angle: angle, child: Icon(AppIcons.towards, size: 18, color: context.onAccent)),
            ),
          ),
        );
      },
    );
  }
}

/// Calm milestones on a long board: the frame done (every edge card in place)
/// and halfway, each shown once per board as a toast.
class GiantMilestones extends StatefulWidget {
  const GiantMilestones({super.key, required this.board, required this.playing});
  final Board board;
  final bool playing;

  @override
  State<GiantMilestones> createState() => _GiantMilestonesState();
}

class _GiantMilestonesState extends State<GiantMilestones> {
  // What was already done when the board opened (a resumed board past
  // halfway says nothing).
  late bool _frame;
  late bool _half;

  @override
  void initState() {
    super.initState();
    _frame = _frameDone(widget.board);
    _half = _halfDone(widget.board);
  }

  static bool _frameDone(Board b) {
    for (var s = 0; s < b.cells; s++) {
      if (isEdgeCard(b.tiling, s) && !b.isLocked(s)) return false;
    }
    return true;
  }

  static bool _halfDone(Board b) {
    var locked = 0;
    for (var s = 0; s < b.cells; s++) {
      if (b.isLocked(s)) locked++;
    }
    return locked * 2 >= b.cells;
  }

  @override
  void didUpdateWidget(GiantMilestones old) {
    super.didUpdateWidget(old);
    if (old.board == widget.board) return;
    final frame = _frameDone(widget.board), half = _halfDone(widget.board);
    if (old.board.spec != widget.board.spec) {
      // Another board: start over without toasts.
      _frame = frame;
      _half = half;
      return;
    }
    if (widget.playing && !widget.board.isSolved) {
      // One toast per move: the frame, else halfway.
      final String? text = frame && !_frame ? 'Frame complete' : (half && !_half ? 'Halfway there' : null);
      if (text != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) showToast(context, text, icon: AppIcons.puzzle);
        });
      }
    }
    _frame = frame;
    _half = half;
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
