import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/a11y.dart';
import '../core/theme/tokens.dart';
import 'adaptive.dart';
import 'glass.dart';

/// How every sheet behaves on a phone (owner, 2026-10-18; docs/native-ui.md, "Sheets"):
///
/// - Its top stops at [topGap]: 8% of the screen height down, where [CupertinoSheetRoute] stops (iOS's
///   large detent), never inside the status bar. The strip of page above stays in view and a tap on
///   it closes the sheet.
/// - A drag down closes it: on the grabber, a header or a footer at once, and in the scrolling part
///   once the content is at its top. A drag that starts lower in the content scrolls it up first, then
///   the same pull carries on with the sheet. A fast flick down closes it too.
abstract final class SheetMetrics {
  /// The share of the screen height above an open sheet ([CupertinoSheetRoute]'s own).
  static const topGapRatio = 0.08;

  /// Distance from the top of the screen to the top of an open sheet.
  static double topGap(BuildContext context) => math.max(MediaQuery.sizeOf(context).height * topGapRatio, MediaQuery.viewPaddingOf(context).top);

  /// The tallest a sheet may be.
  static double maxHeight(BuildContext context) => MediaQuery.sizeOf(context).height - topGap(context);

  /// A sheet let go while moving down at least this fast closes (logical pixels a second).
  static const closeVelocity = 700.0;

  /// A sheet let go after it was dragged down this far closes: 40% of its height, at most 240 pt.
  static double closeDistance(double height) => math.min(height * 0.4, 240);

  /// Platforms on which a sheet's scroll views take the sheet's [PrimaryScrollController] (all of them,
  /// so a narrow desktop browser behaves as a phone).
  static final everywhere = TargetPlatform.values.toSet();
}

/// What a drag on a sheet moves: its route. The sheet's scroll views hand it a drag that starts at
/// their top ([SheetScrollController]); the grabber, header and footer hand it every vertical drag.
abstract interface class SheetDrag {
  /// A drag starts moving the sheet.
  void start();

  /// The finger moved by [delta] logical pixels (down is positive).
  void update(double delta);

  /// The finger let go, moving at [velocity] logical pixels a second (down is positive): the sheet
  /// closes or settles back.
  void end(double velocity);

  /// Whether the sheet sits lower than open (being dragged, or on its way in or out).
  bool get displaced;
}

/// Hands a sheet's [SheetDrag] to the scroll views inside it. Absent where the sheet does not drag
/// (a wide window's panel, a sheet that cannot be dismissed).
class SheetDragScope extends InheritedWidget {
  const SheetDragScope({super.key, required this.drag, required super.child});
  final SheetDrag drag;

  static SheetDrag? maybeOf(BuildContext context) => context.getInheritedWidgetOfExactType<SheetDragScope>()?.drag;

  @override
  bool updateShouldNotify(SheetDragScope oldWidget) => !identical(drag, oldWidget.drag);
}

/// The scroll controller of a sheet's scrolling part: a drag down while the content is at its top
/// moves the sheet instead of pulling the content past its edge (the empty band that used to open
/// above a sheet's title, owner 2026-10-18). Content always takes the drag, even when it fits, so a
/// drag anywhere on it reaches the sheet. [drag] is read when a drag happens (null: scrolls only).
class SheetScrollController extends ScrollController {
  SheetScrollController({required this.drag, super.debugLabel});
  final SheetDrag? Function() drag;

  @override
  ScrollPosition createScrollPosition(ScrollPhysics physics, ScrollContext context, ScrollPosition? oldPosition) => _SheetScrollPosition(
        sheetOf: drag,
        physics: physics.applyTo(const AlwaysScrollableScrollPhysics()),
        context: context,
        initialPixels: initialScrollOffset,
        keepScrollOffset: keepScrollOffset,
        oldPosition: oldPosition,
        debugLabel: debugLabel,
      );
}

class _SheetScrollPosition extends ScrollPositionWithSingleContext {
  _SheetScrollPosition({
    required this.sheetOf,
    required super.physics,
    required super.context,
    super.initialPixels,
    super.keepScrollOffset,
    super.oldPosition,
    super.debugLabel,
  });

  /// The sheet this position's drags may move (read when a drag happens).
  final SheetDrag? Function() sheetOf;

  /// The sheet this gesture is moving, from the moment it took over.
  SheetDrag? _moving;

  @override
  void applyUserOffset(double delta) {
    final sheet = _moving ?? sheetOf();
    // delta > 0: the finger moves down. At the top (or while the sheet is already lower than open) it
    // moves the sheet; back up past the open position, the content scrolls again.
    if (sheet != null && ((_moving != null && sheet.displaced) || (delta > 0 && pixels <= minScrollExtent))) {
      if (_moving == null) {
        _moving = sheet;
        sheet.start();
      }
      sheet.update(delta);
      return;
    }
    super.applyUserOffset(delta);
  }

  @override
  void goBallistic(double velocity) {
    final sheet = _moving;
    if (sheet != null) {
      _moving = null;
      if (sheet.displaced) {
        // velocity is the content's (positive: towards its end, the finger moving up).
        sheet.end(-velocity);
        super.goBallistic(0);
        return;
      }
      sheet.end(0);
    }
    super.goBallistic(velocity);
  }

  @override
  void dispose() {
    _moving?.end(0);
    _moving = null;
    super.dispose();
  }
}

/// The physics of a sheet's scrolling part: the iOS bounce at the end of long content, and none at
/// all when the content fits (nothing to scroll; the drag belongs to the sheet).
class SheetScrollPhysics extends BouncingScrollPhysics {
  const SheetScrollPhysics({super.parent});

  @override
  SheetScrollPhysics applyTo(ScrollPhysics? ancestor) => SheetScrollPhysics(parent: buildParent(ancestor));

  @override
  double applyBoundaryConditions(ScrollMetrics position, double value) {
    if (position.maxScrollExtent <= position.minScrollExtent) return value - position.pixels;
    return super.applyBoundaryConditions(position, value);
  }
}

/// The route of a sheet on a phone: content-sized sheets (`showAppSheet`) and, with Reduce motion, the
/// full-height ones ([full]: Store, Wheel, Account). It slides up from the bottom edge (Reduce motion:
/// fades), stops at [SheetMetrics.topGap] at most, dims the page behind and follows a drag down
/// ([SheetDrag]): released low enough or fast enough it closes, otherwise it settles back. A tap on
/// the dim closes it too. With [dismissible] false nothing but the sheet's own buttons close it.
class GlassSheetRoute<T> extends PopupRoute<T> implements SheetDrag {
  GlassSheetRoute({
    required this.builder,
    required this.barrierColor,
    this.dismissible = true,
    this.full = false,
    this.capturedThemes,
    super.settings,
  });

  final WidgetBuilder builder;
  final bool dismissible;

  /// A full-height sheet: the content (a Scaffold) gets the whole height under the top gap, rounded
  /// top corners and the drag-aware [PrimaryScrollController] for its scroll view.
  final bool full;

  /// Themes of the context that opened the sheet (the sheet itself lives on the root navigator).
  final CapturedThemes? capturedThemes;

  static const _curve = Curves.easeOutCubic;

  final _sheetKey = GlobalKey(debugLabel: 'sheet');

  /// With Reduce motion, how far a drag has moved the sheet down (the route animation only fades).
  final _offset = ValueNotifier<double>(0);

  SheetScrollController? _fullScroll;
  bool _dragging = false;
  bool _reduceMotion = false;

  /// The navigator whose user gesture a drag holds (null when none): while set, the sheet follows
  /// the route animation linearly, so the finger and the settling after it never jump.
  NavigatorState? _gestureNavigator;

  @override
  final Color barrierColor;

  @override
  bool get barrierDismissible => dismissible;

  @override
  String get barrierLabel => 'Close';

  @override
  Duration get transitionDuration => const Duration(milliseconds: 340);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 260);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) {
    final maxHeight = SheetMetrics.maxHeight(context);
    Widget sheet = Builder(builder: builder);
    if (capturedThemes != null) sheet = capturedThemes!.wrap(sheet);
    if (full) {
      sheet = ClipRSuperellipse(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        child: SizedBox(
          height: maxHeight,
          child: PrimaryScrollController(
            controller: _fullScroll ??= SheetScrollController(drag: () => dismissible ? this : null),
            automaticallyInheritForPlatforms: SheetMetrics.everywhere,
            child: sheet,
          ),
        ),
      );
    }
    sheet = Material(type: MaterialType.transparency, child: sheet);
    if (dismissible) {
      sheet = SheetDragScope(
        drag: this,
        // The grabber, a header or a footer outside the scrolling part: any vertical drag moves the
        // sheet (the scroll views inside win the drags that start on them).
        child: GestureDetector(
          onVerticalDragStart: (_) => start(),
          onVerticalDragUpdate: (d) => update(d.primaryDelta ?? 0),
          onVerticalDragEnd: (d) => end(d.primaryVelocity ?? 0),
          onVerticalDragCancel: () => end(0),
          child: sheet,
        ),
      );
    }
    sheet = Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      onDismiss: dismissible ? () => navigator?.maybePop() : null,
      child: KeyedSubtree(key: _sheetKey, child: sheet),
    );
    return MediaQuery.removePadding(
      context: context,
      removeTop: true,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Builder(
            builder: (context) {
              _reduceMotion = A11y.reduceMotionOf(context);
              if (_reduceMotion) {
                // Reduce motion: the sheet fades in and out; a drag still moves it with the finger.
                return FadeTransition(
                  opacity: animation,
                  child: ValueListenableBuilder<double>(
                    valueListenable: _offset,
                    child: sheet,
                    builder: (_, dy, child) => Transform.translate(offset: Offset(0, dy), child: child),
                  ),
                );
              }
              return AnimatedBuilder(
                animation: animation,
                child: sheet,
                builder: (_, child) {
                  final v = animation.value;
                  final shown = _gestureNavigator != null ? v : _curve.transform(v);
                  return FractionalTranslation(translation: Offset(0, 1 - shown), child: child);
                },
              );
            },
          ),
        ),
      ),
    );
  }

  double get _height => math.max(_sheetKey.currentContext?.size?.height ?? 0, 1);

  @override
  bool get displaced => _reduceMotion ? _offset.value > 0 : (controller?.value ?? 1) < 1;

  @override
  void start() {
    if (_dragging || !dismissible || !isActive) return;
    _dragging = true;
    if (!_reduceMotion && _gestureNavigator == null) {
      _gestureNavigator = navigator?..didStartUserGesture();
    }
  }

  @override
  void update(double delta) {
    if (!_dragging) start();
    if (!_dragging) return;
    if (_reduceMotion) {
      _offset.value = math.max(0, _offset.value + delta);
      return;
    }
    final c = controller;
    if (c == null) return;
    c.value = (c.value - delta / _height).clamp(0.0, 1.0);
  }

  @override
  void end(double velocity) {
    if (!_dragging) return;
    _dragging = false;
    final height = _height;
    final moved = _reduceMotion ? _offset.value : (1 - (controller?.value ?? 1)) * height;
    final letGo = velocity >= SheetMetrics.closeVelocity || (velocity > -SheetMetrics.closeVelocity && moved > SheetMetrics.closeDistance(height));
    // Popped meanwhile (a button, a link): it goes; something opened on top of it: it stays.
    final close = isCurrent ? letGo : !isActive;
    if (_reduceMotion) {
      if (close && isCurrent) {
        navigator?.pop(); // fades out where the finger left it
      } else if (!close) {
        _offset.value = 0; // jumps back: no slide with Reduce motion
      }
      return;
    }
    final c = controller;
    if (c == null) return _release();
    if (close) {
      if (isCurrent) navigator?.pop();
      c.animateBack(0, duration: _settle(c.value * height, velocity), curve: Curves.easeOut);
    } else {
      c.animateTo(1, duration: _settle((1 - c.value) * height, -velocity), curve: Curves.easeOutCubic);
    }
    if (!c.isAnimating) return _release();
    void settled(AnimationStatus status) {
      if (status.isAnimating) return;
      c.removeStatusListener(settled);
      // A new drag caught the sheet while it settled: that drag keeps the gesture.
      if (!_dragging) _release();
    }

    c.addStatusListener(settled);
  }

  /// How long the sheet takes to cover [distance] after a release at [speed] (both in logical pixels,
  /// the speed in the direction it goes): about the finger's pace, 120 to 320 ms.
  Duration _settle(double distance, double speed) {
    final ms = speed > 1 ? distance / speed * 1000 * 1.6 : 300 * distance / _height;
    return Duration(milliseconds: ms.clamp(120, 320).round());
  }

  void _release() {
    final navigator = _gestureNavigator;
    _gestureNavigator = null;
    if (navigator != null && navigator.mounted) navigator.didStopUserGesture();
  }

  @override
  void dispose() {
    _release();
    _offset.dispose();
    _fullScroll?.dispose();
    super.dispose();
  }
}

/// A full-height sheet page of the router (Store, Wheel, Account). On a phone the real iOS stacked
/// sheet ([CupertinoSheetRoute]: the page behind shrinks back) whose scroll view gets the route's own
/// drag-aware controller, so a drag down at the top of the content closes it; with Reduce motion a
/// [GlassSheetRoute] that fades instead. A tap on the strip above closes it in both. On a wide window
/// (the web on a tablet or desktop) a centred panel, as iPad shows a page sheet.
class SheetPage<T> extends Page<T> {
  const SheetPage({required this.child, super.key, super.name});
  final Widget child;

  @override
  Route<T> createRoute(BuildContext context) {
    final barrier = Colors.black.withValues(alpha: context.isDark ? 0.5 : 0.32);
    if (context.isWide) {
      return PanelRoute<T>(settings: this, full: true, maxWidth: PageWidth.panel, barrierColor: barrier, builder: (_) => Elevated(background: true, child: child));
    }
    if (A11y.reduceMotionOf(context)) {
      return GlassSheetRoute<T>(settings: this, full: true, barrierColor: barrier, builder: (_) => Elevated(background: true, child: child));
    }
    return _StackedSheetRoute<T>(
      settings: this,
      scrollableBuilder: (_, controller) => PrimaryScrollController(
        controller: controller,
        automaticallyInheritForPlatforms: SheetMetrics.everywhere,
        child: Elevated(background: true, child: child),
      ),
    );
  }
}

/// [CupertinoSheetRoute] with the one sheet rule for the strip above it: a tap there closes it.
class _StackedSheetRoute<T> extends CupertinoSheetRoute<T> {
  _StackedSheetRoute({super.settings, required super.scrollableBuilder});

  @override
  bool get barrierDismissible => true;

  @override
  String get barrierLabel => 'Close';
}
