import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/a11y.dart';
import '../core/theme/tokens.dart';
import 'adaptive.dart';
import 'icons.dart';
import 'sheets.dart';

/// iOS bar material: the content behind is blurred and slightly saturated,
/// then tinted with the surface colour. Used for the tab bar, headers and
/// sheets so chrome reads as the same glass everywhere.
///
/// Flutter cannot reach UIKit's Liquid Glass from Dart (see
/// docs/native-ui.md); this reproduces the blur, vibrancy and tint of
/// `UIBlurEffect.systemChromeMaterial`, which is what the bars looked like up
/// to iOS 18 and what iOS 26 falls back to when "Reduce transparency" is on.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.visible = true,
    this.opacity,
    this.sigma = 24,
    this.borderRadius,
    this.hairline,
    this.tint,
  });

  final Widget child;

  /// Surface colour under the blur; [tintColor] by default.
  final Color? tint;

  /// When false the surface is fully transparent (nothing drawn, no blur)
  /// so a bar sitting over nothing stays invisible, like iOS bars do at the
  /// top of a scroll view. The change is animated.
  final bool visible;

  /// Tint alpha; defaults depend on brightness.
  final double? opacity;
  final double sigma;
  final BorderRadius? borderRadius;

  /// Which side gets the 1px separator. `null` means none.
  final Border? hairline;

  static Color tintColor(BuildContext context) => context.isDark ? const Color(0xFF1C1C22) : Colors.white;

  static double defaultOpacity(BuildContext context) => context.isDark ? 0.62 : 0.72;

  /// Blur plus a mild saturation boost, which is what gives system bars their
  /// vibrancy compared with a plain blur.
  static ImageFilter filter(double sigma) {
    const s = 1.35;
    const r = 0.213, g = 0.715, b = 0.072;
    return ImageFilter.compose(
      outer: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.mirror),
      inner: const ColorFilter.matrix(<double>[
        r + (1 - r) * s, g - g * s, b - b * s, 0, 0,
        r - r * s, g + (1 - g) * s, b - b * s, 0, 0,
        r - r * s, g - g * s, b + (1 - b) * s, 0, 0,
        0, 0, 0, 1, 0,
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tint = this.tint ?? tintColor(context);
    // Increase contrast: a solid surface with an outline instead of see-through glass, so text on
    // it reads the same over any content (it also stands in for iOS's Reduce Transparency).
    final solid = A11y.increaseContrastOf(context);
    final alpha = solid ? 1.0 : opacity ?? defaultOpacity(context);
    final hairline = solid ? (this.hairline ?? (borderRadius != null ? Border.all(color: context.colors.stroke) : null)) : this.hairline;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: visible ? 1 : 0),
      duration: A11y.motion(context, const Duration(milliseconds: 200)),
      curve: Curves.easeOut,
      child: child,
      builder: (context, t, child) {
        if (t <= 0.01) return child!;
        final box = DecoratedBox(
          decoration: BoxDecoration(
            color: tint.withValues(alpha: alpha * t),
            borderRadius: borderRadius,
            border: hairline == null ? null : _scaledBorder(hairline, t),
          ),
          child: child,
        );
        if (solid) return ClipRRect(borderRadius: borderRadius ?? BorderRadius.zero, child: box);
        return ClipRRect(
          borderRadius: borderRadius ?? BorderRadius.zero,
          child: BackdropFilter(filter: filter(sigma * t), child: box),
        );
      },
    );
  }

  static Border _scaledBorder(Border b, double t) {
    BorderSide s(BorderSide side) => side == BorderSide.none ? side : side.copyWith(color: side.color.withValues(alpha: side.color.a * t));
    return Border(top: s(b.top), bottom: s(b.bottom), left: s(b.left), right: s(b.right));
  }
}

/// Gives [child] the colours of a raised surface in dark mode
/// ([AppColors.darkElevated]): content sheets, alerts and the full-height
/// sheets wrap their content in it, so cards and buttons inside sit above the
/// surface. With [background] the Scaffold background follows too (the
/// full-height sheets). Light mode is unchanged.
class Elevated extends StatelessWidget {
  const Elevated({super.key, required this.child, this.background = false});
  final Widget child;
  final bool background;

  @override
  Widget build(BuildContext context) {
    if (!context.isDark) return child;
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        extensions: [context.colors.elevated],
        scaffoldBackgroundColor: background ? context.colors.elevated.canvas : theme.scaffoldBackgroundColor,
      ),
      child: child,
    );
  }
}

/// Reports whether a vertical scrollable in the enclosing Scaffold has
/// content scrolled under the top edge. Same rule Material's AppBar uses.
class ScrolledUnder extends StatefulWidget {
  const ScrolledUnder({super.key, required this.builder});
  final Widget Function(BuildContext context, bool scrolledUnder) builder;

  @override
  State<ScrolledUnder> createState() => _ScrolledUnderState();
}

class _ScrolledUnderState extends State<ScrolledUnder> {
  ScrollNotificationObserverState? _observer;
  bool _under = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _observer?.removeListener(_handle);
    _observer = ScrollNotificationObserver.maybeOf(context);
    _observer?.addListener(_handle);
  }

  @override
  void dispose() {
    _observer?.removeListener(_handle);
    super.dispose();
  }

  void _handle(ScrollNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return;
    if (n is! ScrollUpdateNotification && n is! ScrollMetricsNotification && n is! OverscrollNotification && n is! ScrollEndNotification) return;
    final under = n.metrics.extentBefore > 0;
    if (under != _under) setState(() => _under = under);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _under);
}

/// Top app bar with the iOS treatment: transparent while the list is at the
/// top, glass with a hairline once content scrolls beneath it. Use together
/// with `Scaffold.extendBodyBehindAppBar: true`; the body then receives the
/// bar height as `MediaQuery.padding.top`.
class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  const GlassAppBar({super.key, this.title, this.leading, this.actions, this.centerTitle = true, this.contentWidth = PageWidth.reading});
  final Widget? title;
  final Widget? leading;
  final List<Widget>? actions;
  final bool centerTitle;

  /// The page's content column on a wide window: the back button and the actions line up with
  /// its edges instead of the window's.
  final double contentWidth;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final inset = pageInsetOf(context, maxWidth: contentWidth);
    return AppBar(
      title: title,
      leading: leading == null || inset == 0 ? leading : Padding(padding: EdgeInsets.only(left: inset), child: leading),
      leadingWidth: leading == null || inset == 0 ? null : kToolbarHeight + inset,
      actions: actions == null || inset == 0 ? actions : [...actions!, SizedBox(width: inset)],
      centerTitle: centerTitle,
      backgroundColor: Colors.transparent,
      scrolledUnderElevation: 0,
      flexibleSpace: ScrolledUnder(
        builder: (context, under) => GlassSurface(
          visible: under,
          hairline: Border(bottom: BorderSide(color: c.stroke, width: 0.5)),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

/// A pinned header for `CustomScrollView`s. Sits in the safe area, turns
/// into glass as soon as the slivers below scroll under it.
class GlassSliverHeader extends StatelessWidget {
  const GlassSliverHeader({super.key, required this.height, required this.child});

  /// Content height, excluding the status bar.
  final double height;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return SliverPersistentHeader(
      pinned: true,
      delegate: _GlassHeaderDelegate(extent: height + top, top: top, child: child),
    );
  }
}

class _GlassHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _GlassHeaderDelegate({required this.extent, required this.top, required this.child});
  final double extent;
  final double top;
  final Widget child;

  @override
  double get minExtent => extent;
  @override
  double get maxExtent => extent;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final c = context.colors;
    // `overlapsContent` only reports overlap from preceding slivers; for a
    // pinned header at the top the signal is its own shrink offset.
    return GlassSurface(
      visible: overlapsContent || shrinkOffset > 0,
      hairline: Border(bottom: BorderSide(color: c.stroke, width: 0.5)),
      child: Padding(padding: EdgeInsets.only(top: top), child: SizedBox(height: extent - top, child: child)),
    );
  }

  @override
  bool shouldRebuild(_GlassHeaderDelegate old) => old.extent != extent || old.top != top || old.child != child;
}

/// Bars and controls that must keep their size (tab bar, header bar with
/// the balance pills, game HUD and booster bar) follow Larger Text only up
/// to [max]; reading text elsewhere follows it up to the app's cap (1.35,
/// iOS "xxxLarge", in app.dart).
class ChromeText extends StatelessWidget {
  const ChromeText({super.key, required this.child});
  static const max = 1.2;
  final Widget child;
  @override
  Widget build(BuildContext context) => MediaQuery.withClampedTextScaling(maxScaleFactor: max, child: child);
}

/// Floating glass tab bar in the iOS 26 shape: a capsule inset from the
/// screen edges, hovering above the home indicator, content scrolling under
/// it. The selected tab gets a soft tinted pill.
///
/// Give the hosting Scaffold `extendBody: true`; the bar's slot is
/// transparent so the page continues underneath.
class GlassTabBar extends StatelessWidget {
  const GlassTabBar({super.key, required this.items, required this.currentIndex, required this.onTap});
  final List<GlassTabItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  static const double barHeight = 60;
  static const double sideInset = 16;

  /// Widest the capsule gets (a wide window, the web on a tablet).
  static const double maxWidth = 520;

  /// Gap between the capsule and the screen bottom for a given safe inset.
  static double bottomGap(double safeBottom) => safeBottom > 0 ? safeBottom - 6 : 12;

  /// Height of the Scaffold slot the bar occupies (`extendBody` pages get
  /// this as `MediaQuery.padding.bottom`).
  static double slotHeight(double safeBottom) => barHeight + bottomGap(safeBottom) + 8;

  /// End padding for every scrolling page: enough for the last row to
  /// scroll fully clear of the floating tab bar (pages inside the tab
  /// shell, pushed ones included) or of the home indicator (full-screen
  /// routes and sheets), plus [margin]. Use it as the bottom padding of the
  /// list instead of reading `MediaQuery.padding.bottom` by hand.
  static double scrollEndPadding(BuildContext context, {double margin = 16}) {
    final reported = MediaQuery.paddingOf(context).bottom;
    if (!GlassTabBarScope.covers(context)) return reported + margin;
    // Inside the shell the Scaffold reports the bar's slot as the bottom
    // padding; the slot is recomputed from the raw view inset as well, so a
    // page still clears the bar where a nested widget consumed that padding.
    final safe = MediaQueryData.fromView(View.of(context)).padding.bottom;
    return math.max(reported, slotHeight(safe)) + margin;
  }

  @override
  // Chrome keeps its size above the text-size cap of the bars (see ChromeText).
  Widget build(BuildContext context) => ChromeText(child: Builder(builder: _build));

  Widget _build(BuildContext context) {
    final safe = MediaQuery.paddingOf(context).bottom;
    final bottom = bottomGap(safe);
    final isDark = context.isDark;
    const radius = BorderRadius.all(Radius.circular(barHeight / 2));
    return SizedBox(
      height: barHeight + bottom + 8,
      // On a phone the capsule spans the screen less the insets; on a wider window (the web on a
      // tablet) it keeps a phone's width in the middle.
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: maxWidth + 2 * sideInset),
          child: Padding(
            padding: EdgeInsets.fromLTRB(sideInset, 8, sideInset, bottom),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: radius,
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.10), blurRadius: 22, offset: const Offset(0, 8)),
                  BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04), blurRadius: 2, offset: const Offset(0, 1)),
                ],
              ),
              child: GlassSurface(
                borderRadius: radius,
                hairline: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.10) : Colors.black.withValues(alpha: 0.06), width: 0.5),
                child: LayoutBuilder(
                  builder: (context, cons) {
                    final n = items.length;
                    final cell = cons.maxWidth / n;
                    return Stack(
                      children: [
                        AnimatedPositioned(
                          duration: A11y.motion(context, const Duration(milliseconds: 260)),
                          curve: Curves.easeOutCubic,
                          left: cell * currentIndex + 5,
                          top: 6,
                          bottom: 6,
                          width: cell - 10,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: context.accent.withValues(alpha: context.highContrast ? (isDark ? 0.22 : 0.14) : (isDark ? 0.18 : 0.10)),
                              borderRadius: radius,
                              border: context.highContrast ? Border.all(color: context.accent) : null,
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            for (var i = 0; i < n; i++)
                              Expanded(
                                child: Semantics(
                                  button: true,
                                  selected: i == currentIndex,
                                  label: items[i].locked == null ? items[i].label : '${items[i].label}, ${items[i].locked}',
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () => onTap(i),
                                    child: _TabCell(item: items[i], selected: i == currentIndex),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Marks the part of the tree the floating [GlassTabBar] hovers over: the
/// tab shell's body, so every branch page and the routes pushed inside a
/// branch. Full-screen routes and sheets on the root navigator sit outside
/// it. Read through [GlassTabBar.scrollEndPadding].
class GlassTabBarScope extends InheritedWidget {
  const GlassTabBarScope({super.key, required super.child});

  /// Whether [context] sits under the floating tab bar.
  static bool covers(BuildContext context) => context.getInheritedWidgetOfExactType<GlassTabBarScope>() != null;

  @override
  bool updateShouldNotify(GlassTabBarScope oldWidget) => false;
}

class GlassTabItem {
  const GlassTabItem({required this.icon, required this.activeIcon, required this.label, this.badge = false, this.locked});
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool badge;

  /// The guided start keeps this tab back: drawn faded with a small lock, and this says when it
  /// opens (read by VoiceOver). Tapping it still calls onTap, which explains and offers "Unlock anyway".
  final String? locked;
}

class _TabCell extends StatelessWidget {
  const _TabCell({required this.item, required this.selected});
  final GlassTabItem item;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final locked = item.locked != null && !selected;
    final color = selected ? context.accent : (locked ? c.textTertiary : c.textSecondary);
    return Opacity(
      opacity: locked ? 0.55 : 1,
      child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(selected ? item.activeIcon : item.icon, color: color, size: 23),
            // Kept back by the guided start: a small lock where a dot would be.
            if (locked)
              Positioned(
                right: -8,
                top: -3,
                child: Icon(AppIcons.lock, key: ValueKey('tab-lock-${item.label}'), size: 11, color: c.textSecondary),
              ),
            // Something waits on that tab: a small cobalt dot (the one accent), no ring, clear of the
            // glyph's top-right corner. It stays on the tab being shown until the thing is dealt with
            // (owner, 2026-10-16).
            if (item.badge && !locked)
              Positioned(
                right: -6,
                top: -1,
                child: Container(width: 7, height: 7, decoration: BoxDecoration(color: context.accent, shape: BoxShape.circle)),
              ),
          ],
        ),
        const SizedBox(height: 3),
        Text(item.label, style: TextStyle(fontSize: TypeSize.micro, fontWeight: FontWeight.w600, color: color, letterSpacing: -0.1)),
      ],
      ),
    );
  }
}

/// Surface for content-sized modal sheets: rounded top, glass, grabber and
/// home-indicator inset, matching iOS 26 partial-height sheets.
///
/// The sheet hugs its content up to [SheetMetrics.maxHeight] (the route caps it). Taller content
/// (small phones, large text, long lists) scrolls in a [SheetScrollBody] under the grabber, and a
/// drag down at its top closes the sheet (`lib/widgets/sheets.dart`). With [scrollable] the content
/// lays out its own body: a [SheetScrollBody] with a [SheetScrollBody.footer] that stays put while
/// the rest scrolls (the buttons under a long list).
class GlassSheet extends StatelessWidget {
  const GlassSheet({super.key, required this.child, this.grabber = true, this.bottomInset = 0, this.panel = false, this.scrollable = false});
  final Widget child;
  final bool grabber;

  /// Extra space at the bottom outside the scrolling area (the keyboard).
  final double bottomInset;

  /// A centred panel (the sheet on a wide window, see `showAppSheet`): rounded on every corner,
  /// no grabber (nothing to drag) and no home-indicator inset.
  final bool panel;

  /// [child] brings its own [SheetScrollBody] (to pin a footer) instead of being wrapped in one.
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isDark = context.isDark;
    final radius = panel ? const BorderRadius.all(Radius.circular(28)) : const BorderRadius.vertical(top: Radius.circular(28));
    return GlassSurface(
      borderRadius: radius,
      sigma: 30,
      opacity: isDark ? (panel ? 0.92 : 0.80) : (panel ? 0.94 : 0.84),
      hairline: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.12) : (panel ? Colors.black.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.7)), width: 0.5),
      child: Padding(
        padding: EdgeInsets.only(bottom: (panel ? 12 : MediaQuery.paddingOf(context).bottom) + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (grabber && !panel)
              Padding(
                key: const ValueKey('sheet-grabber'),
                padding: const EdgeInsets.only(top: 8, bottom: 6),
                child: Container(width: 36, height: 5, decoration: BoxDecoration(color: c.textTertiary.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(999))),
              )
            else
              SizedBox(height: panel ? 20 : 14),
            Flexible(child: Elevated(child: scrollable ? child : SheetScrollBody(child: child))),
          ],
        ),
      ),
    );
  }
}

/// The scrolling part of a sheet, and an optional [footer] pinned under it (owner, 2026-10-18: the
/// button under a long list stays in view). Content that fits does not scroll; content that does not
/// fades out at the edge where more is waiting, so a cut-off row never looks like the end of the
/// sheet. A drag down at the top moves the sheet ([SheetScrollController]); scroll views inside
/// [child] get the same behaviour through their [PrimaryScrollController].
class SheetScrollBody extends StatefulWidget {
  const SheetScrollBody({super.key, required this.child, this.footer});
  final Widget child;

  /// Stays under the scrolling part (pad it as the content is padded).
  final Widget? footer;

  /// The key of the sheet's own scroll view (tests drag it).
  static const scrollKey = ValueKey('sheet-scroll');

  @override
  State<SheetScrollBody> createState() => _SheetScrollBodyState();
}

class _SheetScrollBodyState extends State<SheetScrollBody> {
  late final _controller = SheetScrollController(drag: _drag);

  /// For scroll views inside the content (the avatar grid).
  late final _inner = SheetScrollController(drag: _drag);
  bool _moreAbove = false;
  bool _moreBelow = false;

  static const _fade = 28.0;

  SheetDrag? _drag() => mounted ? SheetDragScope.maybeOf(context) : null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _update());
  }

  @override
  void dispose() {
    _controller.dispose();
    _inner.dispose();
    super.dispose();
  }

  void _update() {
    if (!mounted || !_controller.hasClients) return;
    final p = _controller.position;
    if (!p.hasContentDimensions) return;
    final above = p.extentBefore > 0.5;
    final below = p.extentAfter > 0.5;
    if (above != _moreAbove || below != _moreBelow) {
      setState(() {
        _moreAbove = above;
        _moreBelow = below;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scroll = SingleChildScrollView(
      key: SheetScrollBody.scrollKey,
      controller: _controller,
      physics: const SheetScrollPhysics(),
      child: PrimaryScrollController(controller: _inner, automaticallyInheritForPlatforms: SheetMetrics.everywhere, child: widget.child),
    );
    final body = NotificationListener<ScrollMetricsNotification>(
      onNotification: (_) {
        _update();
        return false;
      },
      child: NotificationListener<ScrollUpdateNotification>(
        onNotification: (_) {
          _update();
          return false;
        },
        // Always masked (opaque when nothing is hidden), so the scroll view
        // keeps its place in the tree and its offset when the fade changes.
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (rect) {
            final f = (_fade / math.max(rect.height, 1)).clamp(0.0, 0.5);
            return LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                _moreAbove ? Colors.transparent : Colors.black,
                Colors.black,
                Colors.black,
                _moreBelow ? Colors.transparent : Colors.black,
              ],
              stops: [0, f, 1 - f, 1],
            ).createShader(rect);
          },
          child: scroll,
        ),
      ),
    );
    final footer = widget.footer;
    if (footer == null) return body;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [Flexible(child: body), KeyedSubtree(key: const ValueKey('sheet-footer'), child: footer)],
    );
  }
}
