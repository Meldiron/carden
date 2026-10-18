import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../../core/a11y.dart';
import '../../core/haptics.dart';
import '../../core/theme/tokens.dart';
import '../../game/board.dart';
import '../../game/game_controller.dart';
import '../../state/settings.dart';
import '../../widgets/icons.dart';
import '../coop/coop_players.dart';

/// Interactive board for every tiling (cards, squares, triangles, hexagons).
///
/// Cards animate between slots. Correctly adjacent cards form groups: the
/// gutter closes on every edge shared with a member of the same group, so the
/// group reads as one piece, and a floating group carries an accent border
/// along its outer edges and moves as one when dragged. Cards not yet in
/// place keep rounded corners, the gutter and a light frame and sit a touch
/// darker; a card in place (alone or in a cluster) fills its whole cell edge
/// to edge with square corners and no frame, so it visibly becomes part of
/// the finished picture. One code path serves all four modes, including the
/// half pieces along the edges of triangle and hexagon boards: every edge
/// only asks who is on the other side.
class BoardWidget extends StatefulWidget {
  const BoardWidget({
    super.key,
    required this.image,
    required this.state,
    required this.onTap,
    required this.onDrop,
    required this.cardStyle,
    required this.width,
    required this.height,
    this.painting = false,
    this.zoom,
    this.marks = const {},
    this.ghosts,
    this.onDragMove,
    this.onDragEnd,
    this.blocked = const {},
    this.onDragRefused,
    this.onDragLost,
  });

  final ui.Image image;
  final GameState state;
  final void Function(int slot) onTap;
  final void Function(int from, int to) onDrop;
  final CardStyle cardStyle;
  final double width;
  final double height;

  /// Painting: cards not in place are drawn in black and white and get their
  /// colour back as they lock.
  final bool painting;

  /// Zoom and pan for giant boards (pinch to zoom, two fingers to move); null
  /// on normal boards, which behave exactly as before.
  final BoardZoom? zoom;

  /// Play together: cards other players hold or just moved, by card number, drawn with an outline
  /// in the player's colour and their initial (docs/multiplayer.md).
  final Map<int, CoopCardMark> marks;

  /// Play together: other players' cards being dragged, by card number, drawn where their finger
  /// has them (with their group) and redrawn whenever this changes (every frame while they move).
  final ValueListenable<Map<int, CoopGhost>>? ghosts;

  /// Where the card the finger holds is: its centre as a fraction of the board ([start] for the
  /// first, when the drag begins), so the others can see it move.
  final void Function(int slot, Offset at, bool start)? onDragMove;

  /// The drag of the card that was at [slot] ended (after [onDrop], when it dropped somewhere), or
  /// was given up ([onDragLost]).
  final void Function(int slot)? onDragEnd;

  /// Play together: cards another player has in hand (and their groups). They cannot be dragged
  /// ([onDragRefused]); a drag that comes to touch one is given up ([onDragLost], [DragLoss.claimed]).
  final Set<int> blocked;

  /// A drag of the card at [slot] was refused: another player has it ([blocked]).
  final void Function(int slot)? onDragRefused;

  /// The card this player was dragging was taken from under the finger: another player's move moved
  /// it, put it in place or joined it to others, or another player holds it now. The drag ended
  /// ([onDragEnd] came first) and the cards went back.
  final void Function(int card, DragLoss reason)? onDragLost;

  @override
  State<BoardWidget> createState() => _BoardWidgetState();
}

/// Why a drag was given up ([BoardWidget.onDragLost]).
enum DragLoss {
  /// Another player's move moved the card or changed its group.
  moved,

  /// Another player's move put the card (or its group) in place.
  locked,

  /// Another player has the card in hand, and had it first.
  claimed,
}

/// Whether [card] belongs on the edge of the board (a cell with a side on the
/// board's outline). Works for every tiling: an edge cell has a missing
/// neighbour.
bool isEdgeCard(Tiling tiling, int card) => tiling.edgeNeighbours(card).contains(null);

/// Zoom and pan of a giant board. The game screen owns it (its zoom buttons
/// call [zoomTo] and [reset]); [BoardWidget] draws the board through it and
/// feeds it the player's pinch. [pan] is where the scaled board's top left
/// corner sits in the viewport; the board always covers the viewport.
class BoardZoom extends ChangeNotifier {
  BoardZoom({required TickerProvider vsync}) : _anim = AnimationController(vsync: vsync, duration: const Duration(milliseconds: 260)) {
    _anim.addListener(() {
      final t = Curves.easeOutCubic.transform(_anim.value);
      _apply(ui.lerpDouble(_from.$1, _to.$1, t)!, Offset.lerp(_from.$2, _to.$2, t)!);
    });
  }

  /// The most any board zooms in.
  static const maxZoom = 4.0;

  /// Settings > Accessibility > Reduce motion (the game screen keeps it current): the zoom
  /// buttons, the map and Locate move the view at once instead of gliding there.
  bool reduceMotion = false;

  /// Zoom the zoom-in button goes to from the whole board.
  static const stepZoom = 2.5;

  /// On-screen width a card reaches at the board's own zoom limit: enough to
  /// see its detail, never so close that only two or three cards show (the
  /// smaller giant boards stop earlier than the 300-card ones).
  static const closeCard = 96.0;

  final AnimationController _anim;
  double _zoom = 1;
  Offset _pan = Offset.zero;
  Size _viewport = Size.zero;
  (double, Offset) _from = (1, Offset.zero), _to = (1, Offset.zero);
  double _limit = maxZoom;
  ({double zoom, Offset centre})? _pending;

  double get zoom => _zoom;
  Offset get pan => _pan;
  bool get zoomed => _zoom > 1.01;

  /// This board's zoom limit (at most [maxZoom]).
  double get limit => _limit;

  /// Where the zoom-in button goes from the whole board.
  double get step => math.min(stepZoom, _limit);

  /// Sets the limit from the size of one cell on screen at zoom 1. Called
  /// while the board builds: no notification, the build reads the result.
  void fitCell(double cell) {
    final l = cell <= 0 ? maxZoom : (closeCard / cell).clamp(2.0, maxZoom);
    if (l == _limit) return;
    _limit = l;
    _apply(_zoom, _pan, notify: false);
  }

  /// The board's size on screen at zoom 1 (set by [BoardWidget]).
  Size get viewport => _viewport;
  set viewport(Size size) {
    if (size == _viewport) return;
    _viewport = size;
    _apply(_zoom, _pan, notify: false);
    final p = _pending;
    if (p != null && !size.isEmpty) {
      _pending = null;
      // Set while the board builds (it draws the restored view at once); the
      // bar and the overview map hear about it after the frame.
      _apply(p.zoom, _panFor(p.zoom, p.centre), notify: false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_disposed) notifyListeners();
      });
    }
  }

  /// The part of the board in view, in board coordinates (zoom 1).
  Rect get visible => Rect.fromLTWH(-_pan.dx / _zoom, -_pan.dy / _zoom, _viewport.width / _zoom, _viewport.height / _zoom);

  /// Where the board point [p] (zoom 1 coordinates) is in the viewport.
  Offset toViewport(Offset p) => p * _zoom + _pan;

  /// The view to save: the zoom and the board point in the middle of the
  /// view as a share of the board's width and height, so a different screen
  /// size still opens on the same part of the picture.
  ({double zoom, Offset centre}) get snapshot {
    if (_viewport.isEmpty) return (zoom: _zoom, centre: const Offset(0.5, 0.5));
    final c = visible.center;
    return (zoom: _zoom, centre: Offset(c.dx / _viewport.width, c.dy / _viewport.height));
  }

  /// Opens on a saved view (applied once the viewport is known).
  void restore(double zoom, Offset centre) {
    if (_viewport.isEmpty) {
      _pending = (zoom: zoom, centre: centre);
      return;
    }
    _apply(zoom, _panFor(zoom, centre));
  }

  Offset _panFor(double zoom, Offset centre) {
    final z = zoom.clamp(1.0, _limit);
    return _viewport.center(Offset.zero) - Offset(centre.dx * _viewport.width, centre.dy * _viewport.height) * z;
  }

  /// Animates so the board point [p] (zoom 1 coordinates) sits in the middle
  /// of the view, at the current zoom (or [zoom]).
  void centreOn(Offset p, {double? zoom}) {
    final z = (zoom ?? _zoom).clamp(1.0, _limit);
    _animateTo(z, _viewport.center(Offset.zero) - p * z);
  }

  /// Puts the board point [p] in the middle of the view at once (a finger
  /// dragging over the overview map).
  void lookAt(Offset p) {
    _anim.stop();
    _apply(_zoom, _viewport.center(Offset.zero) - p * _zoom);
  }

  /// Moves the view by [delta] viewport points at once (auto-pan while a card
  /// is dragged to the edge); returns how far the board actually moved.
  Offset panBy(Offset delta) {
    _anim.stop();
    final before = _pan;
    _apply(_zoom, _pan + delta);
    return _pan - before;
  }

  void _apply(double zoom, Offset pan, {bool notify = true}) {
    final z = zoom.clamp(1.0, _limit);
    final p = Offset(pan.dx.clamp(_viewport.width * (1 - z), 0.0), pan.dy.clamp(_viewport.height * (1 - z), 0.0));
    if (z == _zoom && p == _pan) return;
    _zoom = z;
    _pan = p;
    if (notify) notifyListeners();
  }

  /// The player's fingers: applied at once.
  void set(double zoom, Offset pan) {
    _anim.stop();
    _apply(zoom, pan);
  }

  /// Animates to [zoom] around the viewport point [focal] (the middle by default).
  void zoomTo(double zoom, {Offset? focal}) {
    final f = focal ?? _viewport.center(Offset.zero);
    final content = (f - _pan) / _zoom;
    final z = zoom.clamp(1.0, _limit);
    _animateTo(z, f - content * z);
  }

  /// Back to the whole board.
  void reset() => _animateTo(1, Offset.zero);

  void _animateTo(double zoom, Offset pan) {
    if (reduceMotion) {
      _anim.stop();
      _apply(zoom, pan);
      return;
    }
    _from = (_zoom, _pan);
    _to = (zoom, pan);
    _anim.forward(from: 0);
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _anim.dispose();
    super.dispose();
  }
}

class _BoardWidgetState extends State<BoardWidget> with SingleTickerProviderStateMixin {
  int? _dragSlot; // the slot of the card under the finger
  Offset _dragDelta = Offset.zero; // how far the finger moved since pan start
  int? _hoverSlot; // slot under the dragged card's centre
  // The drag by card (Play together: another player's move can change the board under the finger):
  // the card under the finger, the cards of its group and their widget keys when it began.
  int? _dragCard;
  Set<int> _dragCards = const {};
  Map<int, int> _dragKeys = const {};
  // The finger of the drag, for the backstop that ends a drag whose card's gesture never saw it end.
  int? _dragPointer;
  final _down = <int>{};

  // Auto-pan (zoomed boards): while a dragged card is held near the edge of
  // the view, the board slides the other way under it, so a card can travel
  // across a zoomed board in one drag.
  late final Ticker _autoPan = createTicker(_onAutoPan);
  Offset _autoPanVelocity = Offset.zero; // viewport points per second
  Duration _autoPanLast = Duration.zero;

  // Pinch (zoomable boards): fingers on the board, the pinch's starting
  // point, and whether this touch has had two fingers (its taps and drags
  // are then ignored until every finger is up and a new touch starts).
  final _pointers = <int, Offset>{};
  ({double dist, double zoom, Offset focal, Offset pan})? _pinch;
  bool _multiTouch = false;

  // Built cards, reused while only the dragged card changes (a 300-card
  // board rebuilds on every finger move otherwise).
  Object? _cacheKey;
  final _cache = <int, (int, Widget)>{};

  // Peek: the cards fly to their places while the state peeks and back
  // when it stops; [_peekReturn] marks the flight back. The preview's end
  // is the same flight, the deal ([_dealFlight]): a slower sweep across the
  // picture, so it comes apart card by card.
  bool _peekReturn = false;
  bool _dealFlight = false;
  Timer? _peekReturnTimer;

  // The deal's soft ticks still to come ([_dealTicks]), and whether motion is reduced (from the
  // last build).
  HapticRun? _ticks;
  bool _still = false;

  Tiling get tiling => widget.state.board.tiling;
  Size get boardSize => Size(widget.width, widget.height);

  @override
  void initState() {
    super.initState();
    widget.zoom?.addListener(_onZoom);
    widget.ghosts?.addListener(_onGhosts);
  }

  void _onGhosts() {
    if (mounted) setState(() {});
  }

  /// Starts a drag of the card at [slot], unless another player has it.
  bool _beginDrag(int slot) {
    final board = widget.state.board;
    final group = board.groupOf(slot);
    if (group.any((s) => widget.blocked.contains(board.slots[s]))) {
      widget.onDragRefused?.call(slot);
      return false;
    }
    final keys = widget.state.cardKeys;
    // Picked up: the same click as a tap that picks a card.
    Haptics.selection();
    setState(() {
      _dragSlot = slot;
      _dragDelta = Offset.zero;
      _hoverSlot = slot;
      _dragCard = board.slots[slot];
      _dragCards = {for (final s in group) board.slots[s]};
      _dragKeys = {for (final c in _dragCards) c: keys?[c] ?? c};
      _dragPointer = _down.length == 1 ? _down.first : null;
    });
    return true;
  }

  /// Ends the drag in progress where it is, without a drop (the cards go back), and says so.
  void _endDrag() {
    final slot = _dragSlot;
    _stopAutoPan();
    _clearDrag();
    if (slot != null) widget.onDragEnd?.call(slot);
  }

  void _clearDrag() {
    _dragSlot = null;
    _hoverSlot = null;
    _dragDelta = Offset.zero;
    _dragCard = null;
    _dragCards = const {};
    _dragKeys = const {};
    _dragPointer = null;
    if (mounted) setState(() {});
  }

  /// After the board changed (another player's move, their hand): whether the drag in progress can
  /// go on. It cannot when the dragged card moved, locked, joined or left a group, traded its widget
  /// with a twin, or another player has any of its cards in hand: it ends, and the cards glide back.
  DragLoss? _dragStillOk() {
    final card = _dragCard;
    if (card == null) return null;
    final board = widget.state.board;
    final slot = board.slotOfCard(card);
    if (slot < 0) return DragLoss.moved;
    final group = board.groupOf(slot);
    if (group.any((s) => board.isLocked(s))) return DragLoss.locked;
    final cards = {for (final s in group) board.slots[s]};
    if (cards.any(widget.blocked.contains)) return DragLoss.claimed;
    if (slot != _dragSlot || !setEquals(cards, _dragCards)) return DragLoss.moved;
    final keys = widget.state.cardKeys;
    if (cards.any((c) => (keys?[c] ?? c) != _dragKeys[c])) return DragLoss.moved;
    return null;
  }

  void _trackDown(PointerDownEvent e) => _down.add(e.pointer);

  /// The backstop: the finger of a drag lifted (or the system took it) and the card's own gesture did
  /// not end the drag (its widget changed under the finger): end it now.
  void _trackUp(PointerEvent e) {
    _down.remove(e.pointer);
    if (_dragSlot == null || (_dragPointer != null && e.pointer != _dragPointer)) return;
    // The card's gesture hears this lift after the board's listeners: give it the first word.
    scheduleMicrotask(() {
      if (mounted && _dragSlot != null) _endDrag();
    });
  }

  /// Tells the game screen where the dragged card is (Play together).
  void _reportDrag(int slot, {bool start = false}) {
    final report = widget.onDragMove;
    if (report == null) return;
    final c = tiling.cellCenter(slot, boardSize) + _dragDelta;
    report(slot, Offset(c.dx / boardSize.width, c.dy / boardSize.height), start);
  }

  @override
  void didUpdateWidget(BoardWidget old) {
    super.didUpdateWidget(old);
    if (old.zoom != widget.zoom) {
      old.zoom?.removeListener(_onZoom);
      widget.zoom?.addListener(_onZoom);
    }
    if (old.ghosts != widget.ghosts) {
      old.ghosts?.removeListener(_onGhosts);
      widget.ghosts?.addListener(_onGhosts);
    }
    // The board changed under a drag: it goes on only while its card is where it was.
    if (_dragCard != null && (!identical(old.state.board, widget.state.board) || old.blocked != widget.blocked || old.state.cardKeys != widget.state.cardKeys)) {
      final lost = _dragStillOk();
      if (lost != null) {
        final card = _dragCard!;
        final slot = _dragSlot;
        _stopAutoPan();
        _dragSlot = null;
        _hoverSlot = null;
        _dragDelta = Offset.zero;
        _dragCard = null;
        _dragCards = const {};
        _dragKeys = const {};
        _dragPointer = null;
        // Told after this frame: the game screen may change its own state in answer.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (slot != null) widget.onDragEnd?.call(slot);
          widget.onDragLost?.call(card, lost);
        });
      }
    }
    if (old.state.showingPicture && !widget.state.showingPicture) {
      _peekReturn = true;
      _dealFlight = old.state.previewing;
      _peekReturnTimer?.cancel();
      if (_dealFlight) _dealTicks();
      _peekReturnTimer = Timer(_dealFlight ? _dealTime : _peekFlight + _peekSpread, () {
        if (mounted) {
          setState(() {
            _peekReturn = false;
            _dealFlight = false;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    widget.zoom?.removeListener(_onZoom);
    widget.ghosts?.removeListener(_onGhosts);
    _autoPan.dispose();
    _bandTimer?.cancel();
    _peekReturnTimer?.cancel();
    _ticks?.cancel();
    super.dispose();
  }

  /// The deal's touch (owner, 2026-10-18): a soft tick as the sweep takes cards off the picture (a
  /// handful at most, never closer than 70 ms, whatever the board's size), then a light tap as they
  /// land in their dealt places. Reduce motion: the picture fades into the deal, one tick.
  void _dealTicks() {
    _ticks?.cancel();
    if (_still) return Haptics.selection();
    final board = widget.state.board;
    final leave = <Duration>[
      for (var s = 0; s < board.cells; s++)
        if (!board.isLocked(s) && board.slots[s] != s) _dealTime * _dealStart(board.slots[s]),
    ];
    if (leave.isEmpty) return;
    _ticks = Haptics.run(leave, lastAt: _dealTime - const Duration(milliseconds: 60));
  }

  /// Peek's flight: each card takes [_peekFlight] plus up to [_peekSpread]
  /// (a little different for every card), so the picture builds itself in a
  /// ripple rather than all at once.
  static const _peekFlight = Duration(milliseconds: 420);
  static const _peekSpread = Duration(milliseconds: 320);
  static Duration _flightOf(int card) => _peekFlight + Duration(milliseconds: (card * 97 + 31) % 11 * _peekSpread.inMilliseconds ~/ 10);

  /// The deal after the preview: every card leaves the picture within [_dealTime], in a sweep from
  /// the top left corner to the bottom right one (a card's start waits up to 45% of the time, by
  /// where its place is), then glides to where it was dealt, easing in and out.
  static const _dealTime = Duration(milliseconds: 1050);
  Curve _dealCurve(int card) => Interval(_dealStart(card), 1, curve: Curves.easeInOutCubic);

  /// When [card] leaves the picture in the deal, as a fraction of [_dealTime].
  double _dealStart(int card) {
    final home = tiling.cellCenter(card, boardSize);
    return 0.45 * ((home.dx + home.dy) / (boardSize.width + boardSize.height)).clamp(0.0, 1.0);
  }

  /// A tap on [slot]: select, deselect or move (the controller decides). No
  /// double tap on giant boards (owner, 2026-10-14): two quick taps on a card
  /// select and deselect it like on any board; pinch and the zoom buttons zoom.
  void _tapped(int slot) {
    if (_multiTouch) return;
    widget.onTap(slot);
  }

  /// Starts, steers or stops the auto-pan for a dragged card whose finger is
  /// at [global] (screen coordinates).
  void _steerAutoPan(Offset global) {
    final zoom = widget.zoom;
    final box = context.findRenderObject() as RenderBox?;
    if (zoom == null || !zoom.zoomed || box == null || !box.hasSize) return _stopAutoPan();
    final p = box.globalToLocal(global);
    const margin = 44.0, maxSpeed = 520.0;
    double axis(double v, double extent) {
      if (v < margin) return maxSpeed * ((margin - v) / margin).clamp(0.0, 1.0);
      if (v > extent - margin) return -maxSpeed * ((v - (extent - margin)) / margin).clamp(0.0, 1.0);
      return 0;
    }

    _autoPanVelocity = Offset(axis(p.dx, box.size.width), axis(p.dy, box.size.height));
    if (_autoPanVelocity == Offset.zero) return _stopAutoPan();
    if (!_autoPan.isActive) {
      _autoPanLast = Duration.zero;
      _autoPan.start();
    }
  }

  void _stopAutoPan() {
    _autoPanVelocity = Offset.zero;
    if (_autoPan.isActive) _autoPan.stop();
  }

  void _onAutoPan(Duration elapsed) {
    final zoom = widget.zoom, slot = _dragSlot;
    if (zoom == null || slot == null) return _stopAutoPan();
    final dt = (elapsed - _autoPanLast).inMicroseconds / 1e6;
    _autoPanLast = elapsed;
    if (dt <= 0 || dt > 0.1) return;
    final moved = zoom.panBy(_autoPanVelocity * dt);
    if (moved == Offset.zero) return;
    // The finger stays put while the board slides: the card it holds moves
    // through the board by the same amount the other way.
    setState(() {
      _dragDelta -= moved / zoom.zoom;
      _hoverSlot = tiling.slotAt(tiling.cellCenter(slot, boardSize) + _dragDelta, boardSize);
    });
    _reportDrag(slot);
  }

  void _onZoom() {
    if (!mounted) return;
    setState(() {});
    // The outline step follows the zoom once it rests: changing it rebuilds
    // every card, which a pinch or a zoom animation must not do on each frame.
    final band = _bandFor(widget.zoom!.zoom);
    _bandTimer?.cancel();
    if (band != _band) {
      _bandTimer = Timer(const Duration(milliseconds: 180), () {
        if (mounted) setState(() => _band = _bandFor(widget.zoom!.zoom));
      });
    }
  }

  /// Outline step of a zoomed giant board (1 to 4, see [build]).
  double _band = 1;
  Timer? _bandTimer;
  static double _bandFor(double zoom) => zoom < 1.6 ? 1.0 : (zoom < 2.6 ? 2.0 : (zoom < 3.4 ? 3.0 : 4.0));

  void _cancelDrag() => _endDrag();

  void _pointerDown(PointerDownEvent e) {
    if (_pointers.isEmpty) _multiTouch = false;
    _pointers[e.pointer] = e.localPosition;
    if (_pointers.length >= 2) {
      _multiTouch = true;
      _cancelDrag();
      _startPinch();
    }
  }

  void _startPinch() {
    final zoom = widget.zoom;
    if (zoom == null) return;
    final ps = _pointers.values.take(2).toList();
    _pinch = (dist: (ps[0] - ps[1]).distance, zoom: zoom.zoom, focal: (ps[0] + ps[1]) / 2, pan: zoom.pan);
  }

  void _pointerMove(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.localPosition;
    final p = _pinch, zoom = widget.zoom;
    if (p == null || zoom == null || _pointers.length < 2) return;
    final ps = _pointers.values.take(2).toList();
    final dist = (ps[0] - ps[1]).distance, focal = (ps[0] + ps[1]) / 2;
    final z = (p.zoom * (p.dist <= 0 ? 1 : dist / p.dist)).clamp(1.0, zoom.limit);
    // Keep the board point that was under the fingers under them.
    final content = (p.focal - p.pan) / p.zoom;
    zoom.set(z, focal - content * z);
  }

  void _pointerUp(PointerEvent e) {
    _pointers.remove(e.pointer);
    _pinch = null;
    if (_pointers.length >= 2) _startPinch();
  }

  /// Trackpad and mouse wheel (web): a pinch on the trackpad arrives as scale
  /// signals (the browser's ctrl+wheel; Safari's gesture events are turned
  /// into the same in `web/index.html`) and zooms around the pointer; a
  /// two-finger scroll or the wheel moves the zoomed board.
  void _pointerSignal(PointerSignalEvent e) {
    final zoom = widget.zoom;
    if (zoom == null || _dragSlot != null) return;
    if (e is PointerScaleEvent) {
      GestureBinding.instance.pointerSignalResolver.register(e, (event) {
        final s = event as PointerScaleEvent;
        final z = (zoom.zoom * s.scale).clamp(1.0, zoom.limit);
        // Keep the board point under the pointer under it.
        final content = (s.localPosition - zoom.pan) / zoom.zoom;
        zoom.set(z, s.localPosition - content * z);
      });
    } else if (e is PointerScrollEvent && zoom.zoomed) {
      GestureBinding.instance.pointerSignalResolver.register(e, (event) {
        zoom.panBy(-(event as PointerScrollEvent).scrollDelta);
      });
    }
  }

  /// The part of the picture the board shows: a centre crop with the board's
  /// aspect (the whole picture when the board could take its proportions;
  /// the peek overlay uses the same `BoxFit.cover`).
  Rect get imageCrop => tiling.crop(Size(widget.image.width.toDouble(), widget.image.height.toDouble()), boardSize);

  /// Destination cells of the dragged group if dropped on the hovered slot.
  Set<int> _hoverTargets() {
    final d = _dragSlot, h = _hoverSlot;
    if (d == null || h == null || d == h) return const {};
    final delta = tiling.delta(d, h);
    if (delta == null) return const {};
    final out = <int>{};
    for (final s in widget.state.board.groupOf(d)) {
      final t = tiling.apply(s, delta.$1, delta.$2);
      if (t == null) return const {};
      out.add(t);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final board = widget.state.board;
    final c = context.colors;
    _still = A11y.reduceMotionOf(context);
    final cell = tiling.cellSize(boardSize);
    final zoom = widget.zoom;
    // Giant boards have cells of 20 to 30 pt: gutters, corners and strokes
    // follow the cell instead of the minimums tuned for normal boards (which
    // keep exactly their old values).
    final fine = zoom != null;
    // Giant boards are scaled up as a whole, so their gutters, frames and
    // outlines stay thin for the close view (at 4x a normal frame would take
    // a third of every card). Outlines also thin out in steps as the player
    // zooms in, so they read about the same on screen at every zoom; the step
    // changes once the zoom rests ([_onZoom]), so 300 cards are not rebuilt
    // during a pinch.
    if (fine) {
      zoom.viewport = boardSize;
      zoom.fitCell(cell);
    }
    final band = fine ? _band : 1.0;
    final gap = widget.cardStyle == CardStyle.classic ? (fine ? math.max(0.8, cell * 0.05) : math.max(6.0, cell * 0.08)) : (fine ? math.max(0.6, cell * 0.035) : 2.0);
    final radius = widget.cardStyle == CardStyle.classic ? (fine ? cell * 0.12 : math.min(18.0, cell * 0.17)) : (fine ? cell * 0.1 : 8.0);
    final strokeScale = fine ? (cell / 56).clamp(0.3, 1.0) / math.pow(band, 0.6) : 1.0;
    final cacheKey = (widget.state, widget.cardStyle, boardSize, widget.image, widget.painting, gap, radius, strokeScale, _peekReturn, _dealFlight, widget.marks);
    if (cacheKey != _cacheKey) {
      _cacheKey = cacheKey;
      _cache.clear();
    }
    // Never a card in place: a drag that came to touch one has ended (didUpdateWidget).
    final dragGroup = _dragSlot == null ? const <int>{} : board.groupOf(_dragSlot!).where((s) => !board.isLocked(s)).toSet();
    final selectedGroup = widget.state.selectedGroup.toSet();
    final hintGroup = widget.state.hintSlot == null ? const <int>{} : {widget.state.hintSlot!};
    final targets = _hoverTargets();
    final targetsValid = targets.isNotEmpty && !targets.any((t) => board.isLocked(t) && !dragGroup.contains(t));
    // Play together: the others' dragged cards (and their groups), moved by where their finger is.
    final ghosts = <int, ({Offset delta, CoopGhost ghost, bool lead})>{};
    if (!widget.state.showingPicture) {
      for (final g in (widget.ghosts?.value ?? const <int, CoopGhost>{}).values) {
        final slot = board.slotOfCard(g.card);
        if (slot < 0 || board.isLocked(slot)) continue;
        final group = board.groupOf(slot);
        if (group.any((s) => board.isLocked(s) || dragGroup.contains(s) || ghosts.containsKey(s))) continue;
        final delta = Offset(g.at.dx * boardSize.width, g.at.dy * boardSize.height) - tiling.cellCenter(slot, boardSize);
        for (final s in group) {
          ghosts[s] = (delta: delta, ghost: g, lead: s == slot);
        }
      }
    }

    // Render order: locked, free, (zone lines,) selected/hinted, the others' dragged cards, this
    // player's dragged group last.
    int rank(int s) {
      if (dragGroup.contains(s)) return 4;
      if (ghosts.containsKey(s)) return 3;
      if (selectedGroup.contains(s) || hintGroup.contains(s)) return 2;
      return board.isLocked(s) ? 0 : 1;
    }

    final order = List<int>.generate(board.cells, (i) => i)..sort((a, b) => rank(a).compareTo(rank(b)));
    Widget card(int slot) {
      final selected = selectedGroup.contains(slot) || hintGroup.contains(slot);
      final hovered = targets.contains(slot) && !dragGroup.contains(slot) ? (targetsValid ? _Hover.ok : _Hover.blocked) : _Hover.none;
      final ghost = ghosts[slot];
      // Another player's dragged card moves every frame: always built afresh.
      if (ghost != null) return _buildCard(slot, gap, radius, strokeScale, dragging: false, selected: selected, hovered: hovered, ghost: ghost);
      return _cachedCard(slot, gap, radius, strokeScale, dragging: dragGroup.contains(slot), selected: selected, hovered: hovered);
    }

    Widget content = Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(color: c.boardBackground, borderRadius: BorderRadius.circular(radius + 2)),
            ),
          ),
          if (widget.state.hintTarget != null && !widget.state.showingPicture)
            Positioned.fromRect(
              rect: tiling.cellBounds(widget.state.hintTarget!, boardSize),
              child: _PulseRing(
                color: Brand.star,
                polygon: _local(tiling.polygon(widget.state.hintTarget!, boardSize), tiling.cellBounds(widget.state.hintTarget!, boardSize)),
              ),
            ),
          for (final slot in order)
            if (rank(slot) <= 1) card(slot),
          for (final slot in order)
            if (rank(slot) >= 2) card(slot),
          // Differentiate without colour: the hint's target also carries the hint glyph, above the
          // cards, so it does not rest on the amber outline alone.
          if (widget.state.hintTarget != null && !widget.state.showingPicture && A11y.symbolsOf(context))
            Positioned.fromRect(
              rect: tiling.cellBounds(widget.state.hintTarget!, boardSize),
              child: const IgnorePointer(child: Center(child: _BoardGlyph(AppIcons.hint))),
            ),
          // Reduce motion: the preview's picture fades into the dealt cards instead of breaking
          // apart (the cards jump under it).
          if (A11y.reduceMotionOf(context) && (widget.state.previewing || _dealFlight))
            Positioned.fill(
              key: const ValueKey('deal-preview-fade'),
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: widget.state.previewing ? 1 : 0,
                  duration: const Duration(milliseconds: 450),
                  curve: Curves.easeInOut,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(radius + 2),
                    child: CustomPaint(painter: _PicturePainter(widget.image, imageCrop)),
                  ),
                ),
              ),
            ),
        ],
      );
    // Nothing is played while Peek or the preview shows the picture. Always in
    // the tree, so the cards keep their elements and fly instead of jumping.
    content = IgnorePointer(ignoring: widget.state.showingPicture, child: content);
    if (zoom != null) {
      // The board is laid out at its size on screen and scaled, so every
      // card, gutter and stroke grows with the zoom and the picture is drawn
      // from the full-size decode at the zoomed resolution.
      content = Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _pointerDown,
        onPointerMove: _pointerMove,
        onPointerUp: _pointerUp,
        onPointerCancel: _pointerUp,
        onPointerSignal: _pointerSignal,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius + 2),
          child: Transform(
            transform: Matrix4.diagonal3Values(zoom.zoom, zoom.zoom, 1)..setTranslationRaw(zoom.pan.dx, zoom.pan.dy, 0),
            child: content,
          ),
        ),
      );
    }
    // Every finger on the board, so a drag always ends when its finger lifts (the backstop).
    content = Listener(onPointerDown: _trackDown, onPointerUp: _trackUp, onPointerCancel: _trackUp, child: content);
    return SizedBox(width: widget.width, height: widget.height, child: content);
  }

  /// [_buildCard], reused from the last build when nothing about the card
  /// changed (same game state and the same drag, selection and hover flags).
  Widget _cachedCard(int slot, double gap, double radius, double strokeScale, {required bool dragging, required bool selected, required _Hover hovered}) {
    // A dragged card moves with the finger, so it is always built afresh.
    if (dragging) return _buildCard(slot, gap, radius, strokeScale, dragging: true, selected: selected, hovered: hovered);
    final flags = (selected ? 1 : 0) | (hovered.index << 1);
    final hit = _cache[slot];
    if (hit != null && hit.$1 == flags) return hit.$2;
    final built = _buildCard(slot, gap, radius, strokeScale, dragging: false, selected: selected, hovered: hovered);
    _cache[slot] = (flags, built);
    return built;
  }

  static List<Offset> _local(List<Offset> poly, Rect bounds) => [for (final p in poly) p - bounds.topLeft];

  static double _norm(double a) {
    while (a <= -math.pi) {
      a += 2 * math.pi;
    }
    while (a > math.pi) {
      a -= 2 * math.pi;
    }
    return a;
  }

  /// Angular wedge `(start, span)` of cell [s] at its vertex [v], with the
  /// span positive clockwise on screen; null when [v] is not a vertex of [s].
  (double, double)? _wedge(int s, Offset v) {
    final poly = tiling.polygon(s, boardSize);
    for (var i = 0; i < poly.length; i++) {
      if ((poly[i] - v).distance > 0.01) continue;
      final a = poly[(i - 1 + poly.length) % poly.length] - v, b = poly[(i + 1) % poly.length] - v;
      final ta = math.atan2(a.dy, a.dx), tb = math.atan2(b.dy, b.dx);
      final sweep = _norm(tb - ta);
      return sweep > 0 ? (ta, sweep) : (tb, -sweep);
    }
    return null;
  }

  /// The group's fan at vertex [k] of [slot]: the contiguous run of group
  /// cells around that vertex that includes this cell, as an angular range.
  /// Its two bounding rays are the open edges the outline follows into and
  /// out of the vertex, so every cell on the fan can draw the exact band
  /// (straight, rounded concave or rounded convex) through its own clip.
  /// Null where this cell has no fused edge at the vertex (an ordinary
  /// rounded corner) or where the group surrounds the vertex completely.
  _Fan? _fan(Board board, int slot, int k, int groupId, List<bool> fused) {
    final n = fused.length;
    if (!fused[(k - 1 + n) % n] && !fused[k]) return null;
    final v = tiling.polygon(slot, boardSize)[k];
    var (start, span) = _wedge(slot, v)!;
    final others = <(double, double)>[
      for (final s in tiling.cornerNeighbours(slot, k))
        if (board.groupIdOf(s) == groupId) ?_wedge(s, v),
    ];
    var grew = true;
    while (grew && span < 2 * math.pi - 1e-3) {
      grew = false;
      for (var i = 0; i < others.length; i++) {
        final w = others[i];
        if (_norm(w.$1 + w.$2 - start).abs() < 1e-3) {
          start = w.$1;
          span += w.$2;
        } else if (_norm(start + span - w.$1).abs() < 1e-3) {
          span += w.$2;
        } else {
          continue;
        }
        others.removeAt(i);
        grew = true;
        break;
      }
    }
    if (span >= 2 * math.pi - 1e-3) return null;
    return _Fan(_norm(start), span);
  }

  Widget _buildCard(int slot, double gap, double radius, double strokeScale, {required bool dragging, required bool selected, required _Hover hovered, ({Offset delta, CoopGhost ghost, bool lead})? ghost}) {
    final state = widget.state;
    final board = state.board;
    final card = board.slots[slot];
    final locked = board.isLocked(slot);
    final justLocked = state.justLocked.contains(slot);
    final justJoined = state.justJoined.contains(slot);
    // Peek: every card not in place sits in its own place, drawn as if
    // locked, so the whole picture shows; the flight there and back is the
    // card's usual slide, a little slower and different for every card.
    final peek = state.showingPicture && !locked;
    final flight = !locked && (state.showingPicture || _peekReturn);
    final at = peek ? card : slot;
    final bounds = tiling.cellBounds(at, boardSize);
    final origin = dragging ? bounds.topLeft + _dragDelta : (ghost != null ? bounds.topLeft + ghost.delta : bounds.topLeft);
    final grouped = board.groupOf(slot).length > 1;
    final localPoly = _local(tiling.polygon(at, boardSize), bounds);

    // Edges shared with a member of the same group (locked clusters are
    // groups too): the gutter closes there so the group reads as one piece.
    // Board edges and other neighbours keep the gutter, so a lone cell keeps
    // its size.
    final groupId = board.groupIdOf(slot);
    final fusedEdges = peek
        ? [for (final n in tiling.edgeNeighbours(card)) n != null]
        : [for (final n in tiling.edgeNeighbours(slot)) n != null && board.groupIdOf(n) == groupId];
    // Where the group's outline passes a vertex of this cell next to a fused
    // edge, the cell needs to know how the group continues around it. Cards
    // in place fill their cell edge to edge with square corners, so they
    // need none of that.
    final fans = locked || peek
        ? List<_Fan?>.filled(fusedEdges.length, null)
        : [for (var k = 0; k < fusedEdges.length; k++) _fan(board, slot, k, groupId, fusedEdges)];

    // [plain]: the face without the finger's marks (pick-up, outline, drop target), the one a twin
    // swap fades out.
    Widget face({bool plain = false}) => _CardFace(
          image: widget.image,
          polygon: localPoly,
          source: tiling.sourceRect(card, imageCrop),
          locked: locked || peek,
          gap: gap,
          radius: radius,
          selected: !plain && (selected || dragging),
          dragging: !plain && dragging,
          hovered: plain ? _Hover.none : hovered,
          lift: plain ? 0 : (dragging || ghost != null ? 1.0 : (selected ? 0.5 : 0)),
          cardStyle: widget.cardStyle,
          fusedEdges: fusedEdges,
          fans: fans,
          gutterHalf: gap / 2,
          grouped: grouped,
          painting: widget.painting,
          strokeScale: strokeScale,
          thinFrame: widget.zoom != null,
        );
    var child = face();
    // Differentiate without colour: a blocked drop target also shows a no-entry sign, not only a red edge.
    if (hovered == _Hover.blocked && A11y.symbolsOf(context)) {
      child = Stack(fit: StackFit.expand, children: [child, const IgnorePointer(child: Center(child: _BoardGlyph(AppIcons.noEntry)))]);
    }
    if (justLocked || justJoined) {
      child = _LockPulse(key: ValueKey('pulse-$slot-${state.tick}'), strong: justLocked, child: child);
    }
    // Play together: another player's card, in their colour and with their initial (on a dragged
    // group, the initial goes on the card under their finger).
    final mark = peek || locked ? null : (ghost?.ghost.mark ?? widget.marks[card]);
    if (mark != null && !dragging) {
      final badge = (math.min(bounds.width, bounds.height) * 0.42).clamp(8.0, 22.0);
      final centre = localPoly.fold(Offset.zero, (a, p) => a + p) / localPoly.length.toDouble();
      final since = mark.since, fadeFor = mark.fadeFor;
      Widget outline = IgnorePointer(key: mark.held ? null : ValueKey('coop-moved-$card'), child: CustomPaint(painter: _MarkPainter(polygon: localPoly, color: mark.color, width: mark.held ? 3 * strokeScale : 2 * strokeScale, faded: !mark.held)));
      // A moved card's mark fades out from the moment it moved (also after a rebuild part way).
      if (!mark.held && since != null && fadeFor != null && ghost == null) {
        outline = _FadeOut(key: ValueKey('mark-fade-$card-${since.microsecondsSinceEpoch}'), since: since, duration: fadeFor, child: outline);
      }
      final badgeShown = ghost == null ? mark.badge : ghost.lead;
      child = Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: child),
          Positioned.fill(child: outline),
          if (badgeShown)
            Positioned(
              left: centre.dx - badge / 2,
              top: centre.dy - badge / 2,
              child: IgnorePointer(
                child: Semantics(
                  label: ghost != null ? 'Moved by ${mark.initial} now' : (mark.held ? 'Held by ${mark.initial}' : 'Moved by ${mark.initial}'),
                  child: PlayerInitialBadge(key: ValueKey(ghost != null ? 'coop-drag-$card' : 'coop-mark-$card'), initial: mark.initial, color: mark.color, onColor: mark.onColor, size: mark.held || ghost != null ? badge : badge * 0.7),
                ),
              ),
            ),
        ],
      );
    }

    // Reduce motion: cards (and Peek) jump to their places; the lock flash still marks a change.
    final still = A11y.reduceMotionOf(context);
    return AnimatedPositioned(
      // Twins that traded identities keep their places on screen, so each keeps its widget (docs/twins.md).
      key: ValueKey('card-${state.cardKeys?[card] ?? card}'),
      duration: dragging || ghost != null || still ? Duration.zero : (flight ? (_dealFlight ? _dealTime : _flightOf(card)) : const Duration(milliseconds: 280)),
      curve: flight ? (_dealFlight ? _dealCurve(card) : Curves.easeInOutCubic) : Curves.easeOutBack,
      left: origin.dx,
      top: origin.dy,
      width: bounds.width,
      height: bounds.height,
      child: _PolygonHitTest(
        polygon: localPoly,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // A touch that became a pinch neither taps nor drags. A card held
          // still for a moment shows where it belongs (Locate).
          onTapUp: (_) => _tapped(slot),
          onPanStart: locked || state.status != GameStatus.playing
              ? null
              : (_) {
                  if (_multiTouch) return;
                  if (_beginDrag(slot)) _reportDrag(slot, start: true);
                },
          onPanUpdate: locked
              ? null
              : (d) {
                  if (_dragSlot != slot) return;
                  setState(() {
                    _dragDelta += d.delta;
                    _hoverSlot = tiling.slotAt(tiling.cellCenter(slot, boardSize) + _dragDelta, boardSize);
                  });
                  _reportDrag(slot);
                  _steerAutoPan(d.globalPosition);
                },
          onPanEnd: locked
              ? null
              : (_) {
                  _stopAutoPan();
                  final from = _dragSlot;
                  if (from == null) return;
                  // Not this card's drag (its card moved under the finger): it ends, with no drop.
                  if (from != slot) return _endDrag();
                  final target = tiling.slotAt(tiling.cellCenter(from, boardSize) + _dragDelta, boardSize);
                  _clearDrag();
                  if (target != null && target != from) widget.onDrop(from, target);
                  widget.onDragEnd?.call(from);
                },
          onPanCancel: () {
            if (_dragSlot != null) _endDrag();
          },
          child: AnimatedScale(
            scale: still ? 1 : (dragging || ghost != null ? 1.06 : (selected ? 1.03 : 1)),
            duration: const Duration(milliseconds: 140),
            child: _TwinFade(card: card, face: () => face(plain: true), child: child),
          ),
        ),
      ),
    );
  }
}

enum _Hover { none, ok, blocked }

/// The board's part of the picture, whole ([BoardWidget]'s crop): the preview's picture as it fades
/// into the dealt cards when motion is reduced.
class _PicturePainter extends CustomPainter {
  const _PicturePainter(this.image, this.crop);
  final ui.Image image;
  final Rect crop;

  @override
  void paint(Canvas canvas, Size size) => canvas.drawImageRect(image, crop, Offset.zero & size, Paint()..filterQuality = FilterQuality.medium);

  @override
  bool shouldRepaint(_PicturePainter old) => old.image != image || old.crop != crop;
}

/// The group's angular coverage around one vertex of a card: a run of
/// [span] radians clockwise on screen from [start], bounded by the two open
/// edges that leave the vertex (rays [d1] and [d2]). More than a half turn
/// is a concave corner of the group's outline, less than a half turn a
/// convex corner shared by two fused cells, exactly a half turn a straight
/// stretch passing the vertex.
class _Fan {
  const _Fan(this.start, this.span);
  final double start;
  final double span;

  bool get concave => span > math.pi + 1e-3;
  bool get convex => span < math.pi - 1e-3;
  double get end => start + span;
  Offset get d1 => Offset(math.cos(start), math.sin(start));
  Offset get d2 => Offset(math.cos(end), math.sin(end));

  /// Inward normals of the two open edges (angles).
  double get n1 => start + math.pi / 2;
  double get n2 => end - math.pi / 2;

  @override
  bool operator ==(Object other) => other is _Fan && (other.start - start).abs() < 1e-9 && (other.span - span).abs() < 1e-9;
  @override
  int get hashCode => Object.hash(start, span);
}

/// Limits hit-testing to the cell's polygon so overlapping bounding boxes
/// (triangles, hexagons) route taps to the right card.
class _PolygonHitTest extends SingleChildRenderObjectWidget {
  const _PolygonHitTest({required this.polygon, required super.child});
  final List<Offset> polygon;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderPolygonHitTest(polygon);

  @override
  void updateRenderObject(BuildContext context, _RenderPolygonHitTest renderObject) {
    renderObject.polygon = polygon;
  }
}

class _RenderPolygonHitTest extends RenderProxyBox {
  _RenderPolygonHitTest(this.polygon);
  List<Offset> polygon;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!_inside(position)) return false;
    return super.hitTest(result, position: position);
  }

  bool _inside(Offset p) {
    var sign = 0;
    for (var i = 0; i < polygon.length; i++) {
      final a = polygon[i], b = polygon[(i + 1) % polygon.length];
      final cross = (b.dx - a.dx) * (p.dy - a.dy) - (b.dy - a.dy) * (p.dx - a.dx);
      if (cross.abs() < 1e-9) continue;
      final s = cross > 0 ? 1 : -1;
      if (sign == 0) {
        sign = s;
      } else if (s != sign) {
        return false;
      }
    }
    return true;
  }
}

/// Paints one card: its slice of the image with frame, shadow and state
/// outline. The same treatment applies to every tiling:
///
/// * free: rounded corners, the gutter, a light frame with a dark hairline
///   outside it (classic style; it reads on dark and light pictures and on
///   both board colours), a slight dim;
/// * grouped: the gutter closes towards members of the same group and a
///   2 px accent border runs along the group's outer edges;
/// * selected / dragged: ink outline along the outer edges, lift (shadow +
///   scale);
/// * locked (in place, alone or in a cluster): fills its whole cell edge to
///   edge with square corners, full brightness, no frame, shadow or accent,
///   so it visibly becomes part of the finished picture.
///
/// The dim is one flat overlay clipped to the card's own shape. Fused cards
/// abut exactly, so a group darkens evenly with no seam or double layer.
class _CardFace extends StatelessWidget {
  const _CardFace({
    required this.image,
    required this.polygon,
    required this.source,
    required this.locked,
    required this.gap,
    required this.radius,
    required this.selected,
    this.dragging = false,
    required this.hovered,
    required this.lift,
    required this.cardStyle,
    required this.fusedEdges,
    required this.fans,
    required this.gutterHalf,
    required this.grouped,
    this.painting = false,
    this.strokeScale = 1,
    this.thinFrame = false,
  });

  final ui.Image image;
  final List<Offset> polygon;
  final Rect source;
  final bool locked;

  /// Giant boards: the frame follows the thin gutter instead of a 2 pt minimum.
  final bool thinFrame;

  /// Painting: black and white until the card locks, then its colour fades in
  /// with the lock.
  final bool painting;

  /// Outline widths relative to a normal board (giant boards' small cells).
  final double strokeScale;
  final double gap;
  final double radius;
  final bool selected;

  /// Picked up under the finger: square corners, no gutter, frame or dim, and
  /// the outline outside the picture, so every pixel up to the corners shows
  /// while the player looks for its spot (owner feedback 2026-10-13).
  final bool dragging;
  final _Hover hovered;
  final double lift;
  final CardStyle cardStyle;
  final List<bool> fusedEdges;
  final List<_Fan?> fans;
  final double gutterHalf;
  final bool grouped;

  static const _selectionStroke = 5.6;

  /// Outline of a dragged card, drawn entirely outside its picture.
  static const _dragStroke = 2.5;

  /// Drawn at twice this inside the clip, so 2 px show.
  static const _groupStroke = 4.0;

  /// Fused edges reach this far past the cell edge so two abutting clips
  /// overlap by a pixel: antialiasing on a diagonal seam (triangles,
  /// hexagons) otherwise lets the background show through as a hairline.
  /// The picture is continuous across a fused edge, so the overdraw shows
  /// the right pixels.
  static const _overlap = 0.5;

  /// Flat darkening over cards that are not in place yet.
  static const _dim = 0.16;

  @override
  Widget build(BuildContext context) {
    // The edge colour is "ink": near-black on the light theme (where the card
    // frame is white) and white on the dark theme (where the frame is a
    // softer grey), so it always contrasts with the frame.
    final ink = context.isDark ? Colors.white : const Color(0xFF111118);
    final half = gap / 2;
    // Frame of a card not yet in place: a light band with a dark hairline
    // just outside it. The light band shows on dark pictures and the dark
    // board, the hairline on light pictures and the light board.
    final classic = cardStyle == CardStyle.classic;
    final frame = context.isDark ? const Color(0xFFA9AEB9) : Colors.white;
    final edge = Colors.black.withValues(alpha: context.isDark ? 0.55 : 0.22);
    final frameWidth = thinFrame ? gap * 0.45 : math.max(2.0, gap * 0.38);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: locked ? 1 : 0),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      builder: (_, lockT, _) => TweenAnimationBuilder<_EdgeInsets>(
        // Each edge's gutter slides shut as the card snaps to its group, in
        // step with the card's own move.
        tween: _EdgeInsetsTween(end: _EdgeInsets([for (final fused in fusedEdges) fused ? -_overlap : (locked || dragging ? 0.0 : half)])),
        duration: A11y.motion(context, const Duration(milliseconds: 280)),
        curve: Curves.easeOutCubic,
        builder: (_, insets, _) {
          // Interaction language: a picked-up card lifts (shadow + scale) and
          // gets an ink edge; the drop target brightens; a blocked target dims
          // with a red edge; a floating group shares one accent edge. No colour
          // casts over the picture.
          final Color? outline;
          final double stroke;
          var outerOnly = true;
          if (selected) {
            outline = ink;
            stroke = _selectionStroke * strokeScale;
          } else if (hovered == _Hover.ok) {
            outline = ink;
            stroke = _selectionStroke * strokeScale;
            outerOnly = false;
          } else if (hovered == _Hover.blocked) {
            outline = Brand.danger;
            stroke = _selectionStroke * strokeScale;
            outerOnly = false;
          } else if (grouped && !locked) {
            outline = context.accent;
            stroke = _groupStroke * strokeScale;
          } else {
            outline = null;
            stroke = 0;
          }
          return CustomPaint(
            painter: _CardPainter(
              image: image,
              polygon: polygon,
              source: source,
              insets: insets.values,
              radius: dragging ? 0 : radius * (1 - lockT),
              fusedEdges: fusedEdges,
              fans: fans,
              gutterHalf: gutterHalf,
              borderColor: classic ? frame : Colors.transparent,
              borderWidth: classic && !dragging ? frameWidth * (1 - lockT) : 0,
              edgeColor: classic && !dragging ? edge.withValues(alpha: edge.a * (1 - lockT)) : null,
              shadow: lockT > 0.95 || lift == 0 ? null : Colors.black.withValues(alpha: (0.25 + 0.2 * lift) * (1 - lockT)),
              shadowBlur: 10 + lift * 20,
              shadowDy: 4 + lift * 10,
              tint: hovered == _Hover.ok
                  ? Colors.white.withValues(alpha: 0.28)
                  : hovered == _Hover.blocked
                      ? Colors.black.withValues(alpha: 0.35)
                      : null,
              dim: dragging ? 0 : _dim * (1 - lockT),
              saturation: painting ? lockT : 1.0,
              outline: outline,
              outlineWidth: dragging ? _dragStroke * strokeScale : stroke,
              outlineOuterOnly: outerOnly,
              outlineOutside: dragging,
            ),
          );
        },
      ),
    );
  }
}

/// Per-edge gutter insets with value equality, so the implicit animation only
/// restarts when an edge actually opens or closes.
class _EdgeInsets {
  const _EdgeInsets(this.values);
  final List<double> values;

  @override
  bool operator ==(Object other) {
    if (other is! _EdgeInsets || other.values.length != values.length) return false;
    for (var i = 0; i < values.length; i++) {
      if (other.values[i] != values[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(values);
}

class _EdgeInsetsTween extends Tween<_EdgeInsets> {
  _EdgeInsetsTween({super.end});

  @override
  _EdgeInsets lerp(double t) {
    final a = begin ?? end!, b = end!;
    return _EdgeInsets([for (var i = 0; i < b.values.length; i++) (i < a.values.length ? a.values[i] : b.values[i]) + (b.values[i] - (i < a.values.length ? a.values[i] : b.values[i])) * t]);
  }
}

class _CardPainter extends CustomPainter {
  _CardPainter({
    required this.image,
    required this.polygon,
    required this.source,
    required this.insets,
    required this.radius,
    required this.fusedEdges,
    required this.fans,
    required this.gutterHalf,
    required this.borderColor,
    required this.borderWidth,
    required this.edgeColor,
    required this.shadow,
    required this.shadowBlur,
    required this.shadowDy,
    required this.tint,
    required this.dim,
    this.saturation = 1,
    required this.outline,
    required this.outlineWidth,
    required this.outlineOuterOnly,
    this.outlineOutside = false,
  });

  final ui.Image image;
  final List<Offset> polygon;
  final Rect source;

  /// Gutter inset per polygon edge (edge k runs from vertex k to k+1).
  final List<double> insets;
  final double radius;
  final List<bool> fusedEdges;

  /// How the group continues around each vertex (see [_Fan]); null where
  /// the vertex needs no special treatment.
  final List<_Fan?> fans;

  /// Half the gutter: the inset of every open edge once the card is at rest.
  final double gutterHalf;
  final Color borderColor;
  final double borderWidth;

  /// Hairline along the outside of the frame (null: none).
  final Color? edgeColor;
  final Color? shadow;
  final double shadowBlur;
  final double shadowDy;
  final Color? tint;

  /// Alpha of the flat black overlay (0 for a card in place).
  final double dim;

  /// Colour of the picture: 0 is black and white (Painting, not in place),
  /// 1 the full picture.
  final double saturation;
  final Color? outline;
  final double outlineWidth;

  /// Draw the outline just outside the shape instead of inside it.
  final bool outlineOutside;

  /// Whether the outline follows only the open (non-fused) edges, so a fused
  /// group gets one border around its outside; otherwise the whole shape.
  final bool outlineOuterOnly;

  /// The card polygon with every edge moved inward by its inset.
  List<Offset> _shrunk() {
    final n = polygon.length;
    var cx = 0.0, cy = 0.0;
    for (final p in polygon) {
      cx += p.dx;
      cy += p.dy;
    }
    final centroid = Offset(cx / n, cy / n);
    // Offset each edge line inward, then intersect consecutive lines.
    final lines = <(Offset, Offset)>[];
    for (var i = 0; i < n; i++) {
      final a = polygon[i], b = polygon[(i + 1) % n];
      final d = insets[i];
      final edge = b - a;
      final len = edge.distance;
      if (len == 0) {
        lines.add((a, b));
        continue;
      }
      var normal = Offset(-edge.dy / len, edge.dx / len);
      final mid = (a + b) / 2;
      if ((centroid - mid).dx * normal.dx + (centroid - mid).dy * normal.dy < 0) normal = -normal;
      lines.add((a + normal * d, b + normal * d));
    }
    final out = <Offset>[];
    for (var i = 0; i < n; i++) {
      final prev = lines[(i - 1 + n) % n], cur = lines[i];
      out.add(_intersect(prev.$1, prev.$2, cur.$1, cur.$2) ?? cur.$1);
    }
    return out;
  }

  static Offset? _intersect(Offset p1, Offset p2, Offset p3, Offset p4) {
    final d = (p1.dx - p2.dx) * (p3.dy - p4.dy) - (p1.dy - p2.dy) * (p3.dx - p4.dx);
    if (d.abs() < 1e-9) return null;
    final t = ((p1.dx - p3.dx) * (p3.dy - p4.dy) - (p1.dy - p3.dy) * (p3.dx - p4.dx)) / d;
    return Offset(p1.dx + t * (p2.dx - p1.dx), p1.dy + t * (p2.dy - p1.dy));
  }

  /// Closed shape path: shrunk polygon with corners rounded where both
  /// adjoining edges are open, and half of a rounded corner where this cell
  /// and a fused neighbour share a convex corner of the group (the 120°
  /// corners of two triangles), so the group's corners all look alike.
  Path _shape(List<Offset> pts) {
    final n = pts.length;
    final path = Path();
    void to(Offset p, {required bool first}) => first ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    for (var i = 0; i < n; i++) {
      final prev = pts[(i - 1 + n) % n], cur = pts[i], next = pts[(i + 1) % n];
      final prevOpen = !fusedEdges[(i - 1 + n) % n], curOpen = !fusedEdges[i];
      if (prevOpen != curOpen) {
        final cc = _convexCorner(pts, i, incoming: prevOpen);
        if (cc != null) {
          if (prevOpen) {
            to(cc.t, first: i == 0);
            path.quadraticBezierTo(cc.ctrl.dx, cc.ctrl.dy, cc.q.dx, cc.q.dy);
          } else {
            to(cc.q, first: i == 0);
            path.quadraticBezierTo(cc.ctrl.dx, cc.ctrl.dy, cc.t.dx, cc.t.dy);
          }
          continue;
        }
      }
      if (!(prevOpen && curOpen) && fans[i] != null && !fans[i]!.convex) {
        _concaveCorner(path, pts, i, start: i == 0);
        continue;
      }
      final r = _cornerRadius(pts, i);
      if (r <= 0.5) {
        to(cur, first: i == 0);
        continue;
      }
      final inDir = (cur - prev) / (cur - prev).distance;
      final outDir = (next - cur) / (next - cur).distance;
      to(cur - inDir * r, first: i == 0);
      final b = cur + outDir * r;
      path.quadraticBezierTo(cur.dx, cur.dy, b.dx, b.dy);
    }
    path.close();
    return path;
  }

  /// Perpendicular foot of [v] on the line through [a] and [b].
  static Offset _foot(Offset a, Offset b, Offset v) {
    final d = b - a;
    final len2 = d.dx * d.dx + d.dy * d.dy;
    if (len2 == 0) return a;
    return a + d * (((v - a).dx * d.dx + (v - a).dy * d.dy) / len2);
  }

  /// A convex corner of the group shared with the fused neighbour at vertex
  /// [i] (the fan there spans less than a half turn): the corner [p] of the
  /// group's inset outline, the tangent point [t] on this cell's open edge
  /// and the midpoint [q] of the rounded corner, which lies on the shared
  /// edge where the neighbour's half of the curve takes over. Null when the
  /// corner is not of that kind or too tight to round.
  ({Offset t, Offset ctrl, Offset q})? _convexCorner(List<Offset> pts, int i, {required bool incoming}) {
    final fan = fans[i];
    if (fan == null || !fan.convex) return null;
    final n = pts.length;
    final v = polygon[i];
    final h = gutterHalf;
    final l1 = v + Offset(math.cos(fan.n1), math.sin(fan.n1)) * h, l2 = v + Offset(math.cos(fan.n2), math.sin(fan.n2)) * h;
    final p = _intersect(l1, l1 + fan.d1, l2, l2 + fan.d2);
    if (p == null) return null;
    // Which of the fan's rays is this cell's own open edge?
    final e = (incoming ? polygon[(i - 1 + n) % n] : polygon[(i + 1) % n]) - v;
    if (e.distance == 0) return null;
    final u = e / e.distance;
    final ownIsFirst = u.dx * fan.d1.dx + u.dy * fan.d1.dy >= u.dx * fan.d2.dx + u.dy * fan.d2.dy;
    final own = ownIsFirst ? fan.d1 : fan.d2, far = ownIsFirst ? fan.d2 : fan.d1;
    final r = math.min(radius, e.distance / 2.2);
    // The rounding must reach past the shared edge into this cell.
    if (r <= (p - pts[i]).distance + 0.5) return null;
    final t = p + own * r, t2 = p + far * r;
    // The curve's midpoint sits on the shared edge; push it across by the
    // overlap like every other fused edge, so the two clips meet without
    // an antialiasing seam.
    final bisector = own + far;
    var across = Offset(-bisector.dy, bisector.dx) / bisector.distance;
    if (across.dx * own.dx + across.dy * own.dy > 0) across = -across;
    final q = (t + p * 2 + t2) / 4 + across * _CardFace._overlap;
    return (t: t, ctrl: (t + p) / 2, q: q);
  }

  /// Distance from [q] to the ray from [v] in direction [d] (unit).
  static double _rayDist(Offset q, Offset v, Offset d) {
    final w = q - v;
    if (w.dx * d.dx + w.dy * d.dy <= 0) return w.distance;
    return (w.dx * d.dy - w.dy * d.dx).abs();
  }

  /// Distance from [q] to the group's boundary near the fan's vertex [v]:
  /// the nearer of its two open rays.
  static double _boundaryDist(Offset q, Offset v, _Fan fan) => math.min(_rayDist(q, v, fan.d1), _rayDist(q, v, fan.d2));

  /// Where, walking from [from] towards [to] along a fused edge, the cell
  /// leaves the gutter band of the group's boundary (distance [h]).
  static Offset _cutPoint(Offset from, Offset to, Offset v, _Fan fan, double h) {
    if (_boundaryDist(from, v, fan) >= h) return from;
    if (_boundaryDist(to, v, fan) < h) return to;
    var lo = 0.0, hi = 1.0;
    for (var k = 0; k < 24; k++) {
      final mid = (lo + hi) / 2;
      if (_boundaryDist(from + (to - from) * mid, v, fan) < h) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return from + (to - from) * ((lo + hi) / 2);
  }

  /// Appends this cell's part of the group's inset boundary around the
  /// vertex [i] of a concave (or straight) fan: the lines parallel to the
  /// two open edges at the gutter inset, joined by an arc of that radius
  /// around the vertex. Every cell on the fan traces the same curve, so the
  /// pieces meet exactly on the fused edges and the picture, the card
  /// border and the accent all follow one continuous rounded outline; the
  /// vertex itself (and a middle cell's tip) stays inside the gutter.
  void _concaveCorner(Path path, List<Offset> pts, int i, {required bool start}) {
    final fan = fans[i]!;
    final n = pts.length;
    final v = polygon[i];
    final h = gutterHalf;
    final prev = pts[(i - 1 + n) % n], cur = pts[i], next = pts[(i + 1) % n];
    final prevOpen = !fusedEdges[(i - 1 + n) % n], curOpen = !fusedEdges[i];
    // Where the curve enters along the incoming edge and leaves along the
    // outgoing one: the tangent foot on an open (already inset) edge, the
    // crossing of the gutter band on a fused edge.
    final a = prevOpen ? _foot(prev, cur, v) : _cutPoint(cur, prev, v, fan, h);
    final b = curOpen ? _foot(cur, next, v) : _cutPoint(cur, next, v, fan, h);
    // Angles measured from the fan's first ray, and the curve's tangent
    // there (in the direction of growing angle).
    double u(Offset p) {
      var t = math.atan2(p.dy, p.dx) - fan.start;
      while (t < 0) {
        t += 2 * math.pi;
      }
      while (t >= 2 * math.pi) {
        t -= 2 * math.pi;
      }
      return t;
    }

    final lo = math.pi / 2, hi = math.max(lo, fan.span - math.pi / 2);
    Offset tangent(double t) {
      if (t < lo) return -fan.d1;
      if (t > hi) return fan.d2;
      return Offset(-math.sin(fan.start + t), math.cos(fan.start + t));
    }

    final ua = u(a - v), ub = u(b - v);
    final dir = ub >= ua ? 1.0 : -1.0;
    // Ends on a fused edge carry on by the overlap so the neighbour's
    // overdraw never covers the last half pixel of this cell's stroke.
    final a0 = prevOpen ? a : a - tangent(ua) * (dir * _CardFace._overlap);
    final b0 = curOpen ? b : b + tangent(ub) * (dir * _CardFace._overlap);
    start ? path.moveTo(a0.dx, a0.dy) : path.lineTo(a0.dx, a0.dy);
    if (a0 != a) path.lineTo(a.dx, a.dy);
    // The arc between the two parallel lines, as far as it runs through
    // this cell.
    final s = ua.clamp(lo, hi), e = ub.clamp(lo, hi);
    if ((e - s).abs() > 1e-6) path.arcTo(Rect.fromCircle(center: v, radius: h), fan.start + s, e - s, false);
    path.lineTo(b.dx, b.dy);
    if (b0 != b) path.lineTo(b0.dx, b0.dy);
  }

  /// Unit vector from [from] to [to] (zero when they coincide).
  static Offset _unit(Offset from, Offset to) {
    final d = to - from;
    return d.distance == 0 ? Offset.zero : d / d.distance;
  }

  /// Corner radius used by [_shape] at vertex [i] (0 where an adjoining edge
  /// is fused, so fused cells meet in a straight line).
  double _cornerRadius(List<Offset> pts, int i) {
    final n = pts.length;
    if (fusedEdges[(i - 1 + n) % n] || fusedEdges[i]) return 0;
    final prev = pts[(i - 1 + n) % n], cur = pts[i], next = pts[(i + 1) % n];
    return math.min(radius, math.min((cur - prev).distance, (next - cur).distance) / 2.2);
  }

  /// The open (non-fused) edges as stroke runs: rounded where two open edges
  /// meet. Where an open edge meets a fused one the run ends at the foot of
  /// the vertex on the edge (where a concave corner's arc takes over, see
  /// [_fanBand]) or follows this cell's half of a shared convex corner; with
  /// no fan known it overshoots by [ext] so the neighbour's run meets it.
  /// With nothing fused this is the whole rounded shape.
  Path _outline(List<Offset> pts, double ext) {
    final n = pts.length;
    if (!fusedEdges.contains(true)) return _shape(pts);
    final path = Path();
    // Start the walk just after a fused edge so no run wraps around.
    final start = (fusedEdges.indexOf(true) + 1) % n;
    var down = false;
    for (var k = 0; k < n; k++) {
      final i = (start + k) % n;
      final prev = pts[(i - 1 + n) % n], cur = pts[i], next = pts[(i + 1) % n];
      final prevOpen = !fusedEdges[(i - 1 + n) % n], curOpen = !fusedEdges[i];
      if (prevOpen && curOpen) {
        final r = _cornerRadius(pts, i);
        if (r <= 0.5) {
          down ? path.lineTo(cur.dx, cur.dy) : path.moveTo(cur.dx, cur.dy);
        } else {
          final inDir = (cur - prev) / (cur - prev).distance;
          final outDir = (next - cur) / (next - cur).distance;
          final a = cur - inDir * r, b = cur + outDir * r;
          down ? path.lineTo(a.dx, a.dy) : path.moveTo(a.dx, a.dy);
          path.quadraticBezierTo(cur.dx, cur.dy, b.dx, b.dy);
        }
        down = true;
      } else if (prevOpen) {
        // An open run ends at a fused edge.
        final cc = _convexCorner(pts, i, incoming: true);
        if (cc != null) {
          down ? path.lineTo(cc.t.dx, cc.t.dy) : path.moveTo(cc.t.dx, cc.t.dy);
          path.quadraticBezierTo(cc.ctrl.dx, cc.ctrl.dy, cc.q.dx, cc.q.dy);
          final e = cc.q + _unit(cc.ctrl, cc.q) * _CardFace._overlap;
          path.lineTo(e.dx, e.dy);
        } else if (fans[i] != null) {
          _concaveCorner(path, pts, i, start: !down);
        } else {
          final inDir = (cur - prev) / (cur - prev).distance;
          final e = cur + inDir * ext;
          down ? path.lineTo(e.dx, e.dy) : path.moveTo(e.dx, e.dy);
        }
        down = false;
      } else if (curOpen) {
        // An open run starts at a fused edge.
        final cc = _convexCorner(pts, i, incoming: false);
        if (cc != null) {
          final s = cc.q - _unit(cc.q, cc.ctrl) * _CardFace._overlap;
          path.moveTo(s.dx, s.dy);
          path.lineTo(cc.q.dx, cc.q.dy);
          path.quadraticBezierTo(cc.ctrl.dx, cc.ctrl.dy, cc.t.dx, cc.t.dy);
        } else if (fans[i] != null) {
          _concaveCorner(path, pts, i, start: true);
        } else {
          final outDir = (next - cur) / (next - cur).distance;
          final e = cur - outDir * ext;
          path.moveTo(e.dx, e.dy);
        }
        down = true;
      } else if (fans[i] != null && !fans[i]!.convex) {
        // Both edges fused: only the corner curve passes through this cell.
        _concaveCorner(path, pts, i, start: true);
        down = false;
      }
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final pts = _shrunk();
    final shape = _shape(pts);
    if (shadow != null) {
      canvas.drawPath(shape.shift(Offset(0, shadowDy)), Paint()..color = shadow!..maskFilter = MaskFilter.blur(BlurStyle.normal, shadowBlur / 2));
    }
    canvas.save();
    canvas.clipPath(shape);
    // The image slice maps to the cell bounds plus a pixel of overdraw (the
    // neighbouring picture, which is what shows across a fused edge); the
    // clip trims the gutter and everything beyond the shape.
    const over = 1.0;
    final dest = (Offset.zero & size).inflate(over);
    final sx = source.width / size.width, sy = source.height / size.height;
    final src = Rect.fromLTRB(source.left - over * sx, source.top - over * sy, source.right + over * sx, source.bottom + over * sy);
    // Cards not yet in place sit a touch darker, and the picture brightens
    // as it locks. The dim is part of the image draw (not a layer on top)
    // so the overlap zone of two fused cells is never darkened twice.
    final imagePaint = Paint()..filterQuality = FilterQuality.medium;
    final filter = _imageFilter();
    if (filter != null) imagePaint.colorFilter = filter;
    canvas.drawImageRect(image, src, dest, imagePaint);
    if (tint != null) canvas.drawRect(dest, Paint()..color = tint!);
    // Strokes are drawn at twice the width inside the clip, so exactly half
    // shows: the visible band hugs the edge without bleeding into the gutter.
    if (borderWidth > 0) {
      final run = _outline(pts, borderWidth * 2);
      canvas.drawPath(run, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth * 2
        ..color = borderColor);
      if (edgeColor != null && edgeColor!.a > 0) {
        canvas.drawPath(run, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = edgeColor!);
      }
    }
    if (outline != null && outlineWidth > 0 && !outlineOutside) {
      canvas.drawPath(outlineOuterOnly ? _outline(pts, outlineWidth) : shape, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = outlineWidth
        ..color = outline!);
    }
    canvas.restore();
    if (outline != null && outlineWidth > 0 && outlineOutside) {
      // Twice the width, clipped to everything outside the shape: the band
      // hugs the picture without covering a pixel of it.
      final outside = Path.combine(PathOperation.difference, Path()..addRect((Offset.zero & size).inflate(outlineWidth * 2)), shape);
      canvas.save();
      canvas.clipPath(outside);
      canvas.drawPath(outlineOuterOnly ? _outline(pts, 0) : shape, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = outlineWidth * 2
        ..color = outline!);
      canvas.restore();
    }
  }

  /// The dim and, for Painting, the black and white in one colour filter:
  /// luminance (Rec. 709) blended with the colour by [saturation], darkened
  /// by [dim] exactly like the plain dim (a black `srcATop` overlay scales
  /// every channel by `1 - dim`).
  ColorFilter? _imageFilter() {
    if (saturation >= 0.999) return dim > 0 ? ColorFilter.mode(Colors.black.withValues(alpha: dim), BlendMode.srcATop) : null;
    final s = saturation.clamp(0.0, 1.0), k = 1 - dim;
    const lr = 0.2126, lg = 0.7152, lb = 0.0722;
    final g = 1 - s;
    return ColorFilter.matrix(<double>[
      k * (lr * g + s), k * lg * g, k * lb * g, 0, 0,
      k * lr * g, k * (lg * g + s), k * lb * g, 0, 0,
      k * lr * g, k * lg * g, k * (lb * g + s), 0, 0,
      0, 0, 0, 1, 0,
    ]);
  }

  @override
  bool shouldRepaint(_CardPainter o) =>
      o.saturation != saturation ||
      o.image != image ||
      o.source != source ||
      o.radius != radius ||
      !_sameList(o.insets, insets) ||
      !_sameList(o.fusedEdges, fusedEdges) ||
      !_sameList(o.fans, fans) ||
      o.gutterHalf != gutterHalf ||
      !_sameList(o.polygon, polygon) ||
      o.tint != tint ||
      o.outline != outline ||
      o.outlineWidth != outlineWidth ||
      o.outlineOutside != outlineOutside ||
      o.outlineOuterOnly != outlineOuterOnly ||
      o.dim != dim ||
      o.borderWidth != borderWidth ||
      o.edgeColor != edgeColor ||
      o.shadow != shadow;

  static bool _sameList(List<Object?> a, List<Object?> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Twin cards (docs/twins.md): when the card a widget shows becomes its twin (the two traded
/// identities and stay where they are), the old face fades out over the new one, so not even a
/// rendering difference flashes. The pictures look the same, so this is a fade, kept under Reduce
/// motion like every fade.
class _TwinFade extends StatefulWidget {
  const _TwinFade({required this.card, required this.face, required this.child});
  final int card;

  /// The card's face alone, built to fade out when the card changes.
  final Widget Function() face;
  final Widget child;

  @override
  State<_TwinFade> createState() => _TwinFadeState();
}

class _TwinFadeState extends State<_TwinFade> with SingleTickerProviderStateMixin {
  AnimationController? _fade;
  Widget? _old;

  @override
  void didUpdateWidget(_TwinFade old) {
    super.didUpdateWidget(old);
    if (old.card == widget.card) return;
    _old = old.face();
    final fade = _fade ??= AnimationController(vsync: this, duration: const Duration(milliseconds: 180))
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) setState(() => _old = null);
      });
    fade.forward(from: 0);
  }

  @override
  void dispose() {
    _fade?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final old = _old;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (old != null) IgnorePointer(child: FadeTransition(opacity: ReverseAnimation(_fade!), child: old)),
      ],
    );
  }
}

/// Flash + scale pop played when a card locks in place (strong) or snaps to a
/// neighbour (soft).
class _LockPulse extends StatefulWidget {
  const _LockPulse({super.key, required this.child, required this.strong});
  final Widget child;
  final bool strong;
  @override
  State<_LockPulse> createState() => _LockPulseState();
}

class _LockPulseState extends State<_LockPulse> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 520))..forward();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.strong ? Brand.star : Colors.white;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) {
        final t = _c.value;
        // Reduce motion: the flash and glow only, no pop.
        final scale = A11y.reduceMotionOf(context) ? 1.0 : 1 + math.sin(t * math.pi) * (widget.strong ? 0.1 : 0.05);
        return Transform.scale(
          scale: scale,
          child: Stack(
            fit: StackFit.expand,
            children: [
              child!,
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: (1 - t) * (widget.strong ? 0.55 : 0.3)),
                    boxShadow: [BoxShadow(color: color.withValues(alpha: (1 - t) * 0.8), blurRadius: 24 * (1 - t) + 4, spreadRadius: 2)],
                  ),
                ),
              ),
            ],
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// A white glyph with a soft shadow, readable on any picture (Differentiate without colour).
class _BoardGlyph extends StatelessWidget {
  const _BoardGlyph(this.icon);
  final IconData icon;

  @override
  Widget build(BuildContext context) => Icon(icon, size: 26, color: Colors.white, shadows: const [Shadow(color: Color(0xB3000000), blurRadius: 8)]);
}

/// Pulsing outline used to show where a hinted card belongs.
class _PulseRing extends StatefulWidget {
  const _PulseRing({required this.color, required this.polygon});
  final Color color;
  final List<Offset> polygon;
  @override
  State<_PulseRing> createState() => _PulseRingState();
}

class _PulseRingState extends State<_PulseRing> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Reduce motion: a steady outline instead of the pulse.
    if (A11y.reduceMotionOf(context)) {
      if (_c.isAnimating) _c.stop();
      return CustomPaint(painter: _PulsePainter(polygon: widget.polygon, color: widget.color, t: 1));
    }
    if (!_c.isAnimating) _c.repeat(reverse: true);
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) => CustomPaint(painter: _PulsePainter(polygon: widget.polygon, color: widget.color, t: _c.value)),
    );
  }
}

/// The outline of another player's card (Play together): solid while they hold it, lighter on a card
/// they just moved.
/// Fades its child out over [duration] from [since] (a moved card's mark, Play together), starting
/// part way when it is built late. A fade, so it stays under Reduce motion.
class _FadeOut extends StatefulWidget {
  const _FadeOut({super.key, required this.since, required this.duration, required this.child});
  final DateTime since;
  final Duration duration;
  final Widget child;

  @override
  State<_FadeOut> createState() => _FadeOutState();
}

class _FadeOutState extends State<_FadeOut> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration);

  @override
  void initState() {
    super.initState();
    final total = widget.duration.inMicroseconds;
    final gone = DateTime.now().difference(widget.since).inMicroseconds;
    _c.value = total <= 0 ? 1 : (gone / total).clamp(0.0, 1.0);
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(opacity: ReverseAnimation(CurvedAnimation(parent: _c, curve: Curves.easeIn)), child: widget.child);
}

class _MarkPainter extends CustomPainter {
  _MarkPainter({required this.polygon, required this.color, required this.width, required this.faded});
  final List<Offset> polygon;
  final Color color;
  final double width;
  final bool faded;

  @override
  void paint(Canvas canvas, Size size) {
    if (polygon.isEmpty) return;
    final path = Path()..addPolygon(polygon, true);
    canvas.drawPath(path, Paint()
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = width
      ..color = faded ? color.withValues(alpha: 0.75) : color);
  }

  @override
  bool shouldRepaint(_MarkPainter o) => o.color != color || o.width != width || o.faded != faded || o.polygon != polygon;
}

class _PulsePainter extends CustomPainter {
  _PulsePainter({required this.polygon, required this.color, required this.t});
  final List<Offset> polygon;
  final Color color;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    if (polygon.isEmpty) return;
    final path = Path()..moveTo(polygon.first.dx, polygon.first.dy);
    for (final p in polygon.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.5 * t)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
    canvas.drawPath(path, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = color.withValues(alpha: 0.5 + t * 0.5));
  }

  @override
  bool shouldRepaint(_PulsePainter o) => o.t != t || o.color != color || o.polygon != polygon;
}
