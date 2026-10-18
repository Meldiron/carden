import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../core/a11y.dart';
import '../core/theme/tokens.dart';
import 'glass.dart';
import 'icons.dart';
import 'sheets.dart';

/// Layouts for wider windows: the web build in a tablet or desktop browser. The iPhone app is
/// portrait only (at most 440 pt wide), so it always gets the compact layout, which is the
/// phone layout exactly as before; only the web reaches the wider ones. Details: docs/web.md.
///
/// - compact (below [Breakpoints.medium]): the phone layout.
/// - medium (from [Breakpoints.medium]): still the floating tab bar, but pages and grids use the
///   width (centred content, more columns) and sheets open as centred panels.
/// - expanded (from [Breakpoints.expanded]): the website layout. A top bar ([WideTopBar] in
///   the tab shell) instead of the floating tab bar, two-column pages where a page has two parts.
class Breakpoints {
  static const double medium = 600;
  static const double expanded = 900;
}

/// Widest the content of a page grows; the rest of the window is margin.
class PageWidth {
  /// Pages of pictures and packs (Home, Library, a pack, Quests).
  static const double wide = 1200;

  /// Lists and forms (Settings, Account, Social, a player).
  static const double reading = 720;

  /// Sheets shown as a centred panel (`showAppSheet` on medium and expanded windows).
  static const double sheet = 520;

  /// The full-height sheets (Store, Wheel, Account) as a centred panel. Below
  /// [Breakpoints.medium], so the screen inside keeps its phone layout.
  static const double panel = 580;
}

enum WindowClass { compact, medium, expanded }

extension AdaptiveContext on BuildContext {
  /// The class of the window (or of the panel a sheet is shown in, which narrows the
  /// MediaQuery to its own size).
  WindowClass get windowClass {
    final w = MediaQuery.sizeOf(this).width;
    if (w >= Breakpoints.expanded) return WindowClass.expanded;
    if (w >= Breakpoints.medium) return WindowClass.medium;
    return WindowClass.compact;
  }

  /// Medium or expanded: anything wider than a phone.
  bool get isWide => windowClass != WindowClass.compact;

  /// The website layout (top bar, two columns).
  bool get isExpanded => windowClass == WindowClass.expanded;
}

/// The horizontal inset that centres content of at most [maxWidth] in a window of [width]:
/// zero on a phone (pages keep their own 20 pt margins), and on wider windows at least a small
/// extra margin so the content never touches the window edge.
double pageInset(double width, {double maxWidth = PageWidth.wide}) {
  if (width < Breakpoints.medium) return 0;
  final extra = width >= Breakpoints.expanded ? 12.0 : 4.0;
  return math.max(extra, (width - maxWidth) / 2);
}

/// Width of the content column in [context]'s window, less the pages' own 20 pt margins.
double contentWidthOf(BuildContext context, {double maxWidth = PageWidth.wide}) {
  final w = MediaQuery.sizeOf(context).width;
  return w - 2 * pageInset(w, maxWidth: maxWidth) - 40;
}

/// [pageInset] for the window [context] sits in.
double pageInsetOf(BuildContext context, {double maxWidth = PageWidth.wide}) => pageInset(MediaQuery.sizeOf(context).width, maxWidth: maxWidth);

/// Slivers of a page laid out in the centred content column of [maxWidth] (their own 20 pt
/// margins stay inside it). On a phone it is just the slivers. Put the page's pinned header
/// outside it, so the header's glass still runs from edge to edge.
class SliverPage extends StatelessWidget {
  const SliverPage({super.key, required this.slivers, this.maxWidth = PageWidth.wide});
  final List<Widget> slivers;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final inset = pageInsetOf(context, maxWidth: maxWidth);
    final group = SliverMainAxisGroup(slivers: slivers);
    if (inset == 0) return group;
    return SliverPadding(padding: EdgeInsets.symmetric(horizontal: inset), sliver: group);
  }
}

/// Box version of [SliverPage]: [child] in the centred content column, full height.
class PageColumn extends StatelessWidget {
  const PageColumn({super.key, required this.child, this.maxWidth = PageWidth.wide});
  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final inset = pageInsetOf(context, maxWidth: maxWidth);
    if (inset == 0) return child;
    return Padding(padding: EdgeInsets.symmetric(horizontal: inset), child: child);
  }
}

/// About how wide a pack card gets in the grids of a wider window.
const double packCardWidth = 200;

/// Columns of a grid of cards in [width] (the grid's own width, margins taken off): two on a
/// phone, as before; on wider windows as many as fit at about [target] each.
int gridColumns(double width, {double target = packCardWidth, double spacing = 12, int compact = 2, int max = 8}) {
  if (width < Breakpoints.medium - 40) return compact;
  return ((width + spacing) / (target + spacing)).floor().clamp(compact, max);
}

/// Grid delegate for card grids (packs, pictures): [compact] columns on a phone, more on wider
/// windows (see [gridColumns]). The aspect ratio stays the phone's, so cards keep their shape.
class AdaptiveGridDelegate extends SliverGridDelegate {
  const AdaptiveGridDelegate({this.target = packCardWidth, this.compact = 2, this.max = 8, this.mainAxisSpacing = 12, this.crossAxisSpacing = 12, required this.childAspectRatio});
  final double target;
  final int compact;
  final int max;
  final double mainAxisSpacing;
  final double crossAxisSpacing;
  final double childAspectRatio;

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) {
    final columns = gridColumns(constraints.crossAxisExtent, target: target, spacing: crossAxisSpacing, compact: compact, max: max);
    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: columns,
      mainAxisSpacing: mainAxisSpacing,
      crossAxisSpacing: crossAxisSpacing,
      childAspectRatio: childAspectRatio,
    ).getLayout(constraints);
  }

  @override
  bool shouldRelayout(AdaptiveGridDelegate old) =>
      old.target != target || old.compact != compact || old.max != max || old.mainAxisSpacing != mainAxisSpacing || old.crossAxisSpacing != crossAxisSpacing || old.childAspectRatio != childAspectRatio;
}

/// A horizontal row of cards (a home shelf). On a phone it is the plain list it always was. On
/// wider windows a mouse can drag it too, and round arrow buttons at its ends page through it:
/// a mouse wheel only scrolls up and down, so without them a desktop visitor could not reach the
/// cards past the edge.
class Shelf extends StatefulWidget {
  const Shelf({super.key, required this.height, required this.itemCount, required this.itemBuilder, this.spacing = 12, this.padding = const EdgeInsets.symmetric(horizontal: 20), this.controller, this.listKey});
  final double height;

  /// Key of the list itself (tests find the row's Scrollable through it).
  final Key? listKey;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double spacing;
  final EdgeInsets padding;
  final ScrollController? controller;

  @override
  State<Shelf> createState() => _ShelfState();
}

class _ShelfState extends State<Shelf> {
  ScrollController? _own;
  ScrollController get _controller => widget.controller ?? (_own ??= ScrollController());
  bool _back = false;
  bool _forward = false;
  bool _hover = false;

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  void _update() {
    if (!mounted || !_controller.hasClients) return;
    final p = _controller.position;
    if (!p.hasContentDimensions) return;
    final back = p.extentBefore > 1;
    final forward = p.extentAfter > 1;
    if (back != _back || forward != _forward) {
      setState(() {
        _back = back;
        _forward = forward;
      });
    }
  }

  void _page(int direction) {
    if (!_controller.hasClients) return;
    final p = _controller.position;
    final target = (p.pixels + direction * p.viewportDimension * 0.8).clamp(p.minScrollExtent, p.maxScrollExtent);
    if (A11y.reduceMotionOf(context)) {
      _controller.jumpTo(target);
      return;
    }
    _controller.animateTo(target, duration: const Duration(milliseconds: 420), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final list = ListView.separated(
      key: widget.listKey,
      controller: _controller,
      scrollDirection: Axis.horizontal,
      padding: widget.padding,
      physics: const BouncingScrollPhysics(),
      itemCount: widget.itemCount,
      separatorBuilder: (_, _) => SizedBox(width: widget.spacing),
      itemBuilder: widget.itemBuilder,
    );
    if (!context.isWide) return SizedBox(height: widget.height, child: list);
    WidgetsBinding.instance.addPostFrameCallback((_) => _update());
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: SizedBox(
        height: widget.height,
        child: Stack(
          children: [
            NotificationListener<ScrollMetricsNotification>(
              onNotification: (_) {
                _update();
                return false;
              },
              child: NotificationListener<ScrollUpdateNotification>(
                onNotification: (_) {
                  _update();
                  return false;
                },
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context).copyWith(dragDevices: {...PointerDeviceKind.values}, scrollbars: false),
                  child: list,
                ),
              ),
            ),
            if (_back) Positioned(left: 4, top: 0, bottom: 0, child: Center(child: _ShelfArrow(icon: AppIcons.chevronLeft, visible: _hover, label: 'Previous', onTap: () => _page(-1)))),
            if (_forward) Positioned(right: 4, top: 0, bottom: 0, child: Center(child: _ShelfArrow(icon: AppIcons.chevronRight, visible: _hover, label: 'Next', onTap: () => _page(1)))),
          ],
        ),
      ),
    );
  }
}

class _ShelfArrow extends StatelessWidget {
  const _ShelfArrow({required this.icon, required this.visible, required this.label, required this.onTap});
  final IconData icon;
  final bool visible;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isDark = context.isDark;
    return AnimatedOpacity(
      opacity: visible ? 1 : 0.0,
      duration: const Duration(milliseconds: 160),
      child: Semantics(
        button: true,
        label: label,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: onTap,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.14), blurRadius: 14, offset: const Offset(0, 4))],
              ),
              child: GlassSurface(
                borderRadius: BorderRadius.circular(22),
                opacity: isDark ? 0.82 : 0.88,
                hairline: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.06), width: 0.5),
                child: SizedBox.square(dimension: 44, child: Icon(icon, size: 18, color: c.textPrimary)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A modal shown as a centred panel on a wide window, where an edge-to-edge sheet from the bottom
/// would stretch across a desktop: the content-sized sheets of `showAppSheet` (hugging their
/// content, [height] null) and the full-height ones of the router (Store, Wheel, Account; the
/// window's height less a margin). Inside, the MediaQuery is narrowed to the panel with no safe
/// area, so the screen lays itself out as on a phone. A tap outside or Escape closes it unless
/// [dismissible] is false.
class PanelRoute<T> extends RawDialogRoute<T> {
  PanelRoute({required WidgetBuilder builder, required double maxWidth, bool full = false, bool dismissible = true, required Color barrierColor, super.settings})
      : super(
          barrierDismissible: dismissible,
          barrierLabel: 'Dismiss',
          barrierColor: barrierColor,
          transitionDuration: const Duration(milliseconds: 260),
          transitionBuilder: (ctx, anim, _, child) {
            final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
            if (A11y.reduceMotionOf(ctx)) return FadeTransition(opacity: curved, child: child);
            return FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: Tween(begin: const Offset(0, 0.03), end: Offset.zero).animate(curved),
                child: ScaleTransition(scale: Tween(begin: 0.98, end: 1.0).animate(curved), child: child),
              ),
            );
          },
          pageBuilder: (ctx, _, _) => _PanelFrame(maxWidth: maxWidth, full: full, child: Builder(builder: builder)),
        );
}

/// Whether [context] is inside a sheet: the stacked sheet on a phone (with Reduce motion a
/// [GlassSheetRoute]) or its centred panel on a wide window (a close button instead of a back arrow).
bool isSheetRoute(BuildContext context) {
  final route = ModalRoute.of(context);
  return route is CupertinoSheetRoute || route is PanelRoute || route is GlassSheetRoute;
}

class _PanelFrame extends StatelessWidget {
  const _PanelFrame({required this.maxWidth, required this.full, required this.child});
  final double maxWidth;
  final bool full;
  final Widget child;

  static const _margin = 24.0;
  static const _radius = 28.0;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final isDark = context.isDark;
    final width = math.min(maxWidth, mq.size.width - 2 * _margin);
    final maxHeight = math.min(full ? 960.0 : 860.0, mq.size.height - 2 * _margin - mq.viewInsets.bottom);
    final inner = MediaQuery(
      data: mq.copyWith(
        size: Size(width, maxHeight),
        padding: EdgeInsets.zero,
        viewPadding: EdgeInsets.zero,
        viewInsets: EdgeInsets.zero,
      ),
      child: child,
    );
    final shadow = BoxDecoration(
      borderRadius: BorderRadius.circular(_radius),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.18), blurRadius: 48, offset: const Offset(0, 20))],
    );
    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: Center(
        child: SizedBox(
          width: width,
          height: full ? maxHeight : null,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: DecoratedBox(
              decoration: shadow,
              child: full
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(_radius),
                      child: DecoratedBox(
                        position: DecorationPosition.foreground,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(_radius),
                          border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.10) : Colors.black.withValues(alpha: 0.06), width: 0.5),
                        ),
                        child: inner,
                      ),
                    )
                  : Material(type: MaterialType.transparency, child: inner),
            ),
          ),
        ),
      ),
    );
  }
}
