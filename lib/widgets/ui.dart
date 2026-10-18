import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart' show SpringDescription, SpringSimulation;

import '../core/a11y.dart';
import '../core/haptics.dart';
import '../core/numbers.dart';
import '../core/sfx.dart';
import '../core/theme/tokens.dart';
import 'adaptive.dart';
import 'cached_url_image.dart';
import 'glass.dart';
import 'hash_image.dart';
import 'icons.dart';
import 'sheets.dart';

export '../core/dates.dart';
export '../core/numbers.dart';
export 'adaptive.dart';

/// A tappable surface that scales down slightly while pressed (iOS-style).
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.onTap, this.onLongPress, this.scale = 0.97, this.haptic = true, this.sound = true});
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final bool haptic;
  final bool sound;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    // A pointer (the web on a desktop) shows the hand over anything tappable, as on a website.
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => setState(() => _down = true) : null,
      onTapUp: enabled ? (_) => setState(() => _down = false) : null,
      onTapCancel: enabled ? () => setState(() => _down = false) : null,
      onTap: widget.onTap == null
          ? null
          : () {
              if (widget.haptic) Haptics.light();
              if (widget.sound) Sfx.instance.tap();
              widget.onTap!();
            },
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        // Reduce motion: no shrink; the dim below still shows the press.
        scale: _down && !A11y.reduceMotionOf(context) ? widget.scale : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: AnimatedOpacity(opacity: _down ? 0.85 : 1, duration: const Duration(milliseconds: 110), child: widget.child),
      ),
      ),
    );
  }
}

/// Pads a compact control to Apple's 44 pt minimum touch area without changing how it looks:
/// the control keeps its size and sits centred in the larger box, which takes the touches. Put it
/// inside the [Pressable] so the whole box is tappable.
class TapTarget extends StatelessWidget {
  const TapTarget({super.key, required this.child, this.minSize = 44});
  final Widget child;
  final double minSize;
  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: BoxConstraints(minWidth: minSize, minHeight: minSize),
        child: Center(widthFactor: 1, heightFactor: 1, child: child),
      );
}

/// Flat surface card: 1px hairline, no shadow. The main container.
class SoftCard extends StatelessWidget {
  const SoftCard({
    super.key,
    required this.child,
    this.padding = Insets.card,
    this.radius = Radii.lg,
    this.color,
    this.gradient,
    this.onTap,
    this.border = true,
    this.borderColor,
    this.margin,
    this.clip = Clip.antiAlias,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? color;
  final Gradient? gradient;
  final VoidCallback? onTap;
  final bool border;

  /// Outline colour (the theme's stroke by default).
  final Color? borderColor;
  final EdgeInsetsGeometry? margin;
  final Clip clip;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rounded = BorderRadius.circular(radius);
    final outline = border && gradient == null ? Border.all(color: borderColor ?? c.stroke) : null;
    // The outline is drawn over the content, and the content is clipped to the same radius: rows with
    // their own fill (the swipe rows of Inbox, Friends and Quests) never cover the rounded corners
    // (owner, 2026-10-18). The content keeps its inset of the outline's width.
    final card = Container(
      margin: margin,
      clipBehavior: clip,
      decoration: BoxDecoration(
        color: gradient == null ? (color ?? c.card) : null,
        gradient: gradient,
        borderRadius: rounded,
      ),
      foregroundDecoration: outline == null ? null : BoxDecoration(borderRadius: rounded, border: outline),
      child: Padding(padding: outline == null ? padding : padding.add(outline.dimensions), child: child),
    );
    return onTap == null ? card : Pressable(onTap: onTap, scale: 0.985, child: card);
  }
}

/// [destructive]: the one action that throws something away for good (Delete account), a red
/// fill with a white label; never the default of a screen. [plain]: a label without a surface, for
/// the quiet way out under a primary action (Cancel under Delete account).
enum ButtonKind { primary, secondary, ghost, ghostLight, coral, gold, teal, dark, destructive, plain }

/// The CTA button. Solid fills, no gradients.
class BigButton extends StatelessWidget {
  const BigButton({
    super.key,
    required this.label,
    this.onTap,
    this.kind = ButtonKind.primary,
    this.icon,
    this.trailing,
    this.expand = true,
    this.height = 52,
    this.loading = false,
  })  : currency = null,
        amount = null,
        amountPrefix = '';

  /// A button for an action that costs or pays [currency]: the label is
  /// followed by the currency mark and the amount ("Open for [ticket] 1").
  /// The one style for every spend in the app: wheel spin, piggy bank, tier
  /// and pack unlocks, boosters.
  const BigButton.cost({
    super.key,
    required this.label,
    required Currency this.currency,
    required int this.amount,
    this.amountPrefix = '',
    this.onTap,
    this.kind = ButtonKind.primary,
    this.expand = true,
    this.height = 52,
    this.loading = false,
  })  : icon = null,
        trailing = null;

  final String label;
  final VoidCallback? onTap;
  final ButtonKind kind;
  final IconData? icon;
  final Widget? trailing;
  final bool expand;
  final double height;
  final bool loading;
  final Currency? currency;
  final int? amount;
  final String amountPrefix;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final disabled = onTap == null;
    Color bg;
    Color fg = Colors.white;
    Border? border;
    switch (kind) {
      case ButtonKind.primary:
      case ButtonKind.coral:
      case ButtonKind.teal:
        bg = context.accentFill;
        fg = context.onAccent;
      case ButtonKind.gold:
        bg = Brand.coin;
        fg = const Color(0xFF2A1F00);
      case ButtonKind.dark:
        // Inverted surface: white on dark themes, ink on light ones, so the
        // label must be the opposite of the fill, not the theme's text colour.
        bg = context.isDark ? Colors.white : c.textPrimary;
        fg = context.isDark ? const Color(0xFF111827) : Colors.white;
      case ButtonKind.secondary:
        bg = c.accentTint;
        fg = context.accent;
      case ButtonKind.ghost:
        bg = Colors.transparent;
        fg = c.textPrimary;
        border = Border.all(color: c.controlStroke);
      case ButtonKind.ghostLight:
        // For always-dark surfaces such as the VIP card.
        bg = Colors.transparent;
        fg = Colors.white;
        border = Border.all(color: Colors.white.withValues(alpha: 0.45));
      case ButtonKind.destructive:
        // The light theme's red in both themes: white on it is 4.8:1 (the dark theme's softer red
        // is tuned for text and would leave a white label at 2.8:1).
        bg = Brand.danger;
        fg = Colors.white;
      case ButtonKind.plain:
        bg = Colors.transparent;
        fg = context.accent;
    }
    // Disabled (and not busy): every kind turns into the same neutral slab
    // with a tertiary label, the iOS disabled button. Fading the kind's own
    // colour instead left a dimmed cobalt that read as an enabled tonal
    // button in dark mode, and a brown "gold".
    final inactive = disabled && !loading;
    if (inactive) {
      final onDark = context.isDark || kind == ButtonKind.ghostLight;
      bg = onDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05);
      fg = kind == ButtonKind.ghostLight ? Colors.white.withValues(alpha: 0.45) : c.textTertiary;
      border = null;
    }
    // On a filled button a ticket mark (in a cost label or a trailing
    // [Amount]) is drawn in the label colour, never teal on cobalt.
    final filled = bg != Colors.transparent;
    final Widget content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          // The iOS activity indicator, as everywhere else in the app (was Material's ring).
          CupertinoActivityIndicator(color: fg, radius: 9)
        else ...[
          if (icon != null) ...[Icon(icon, color: fg, size: 19), const SizedBox(width: 8)],
          // A call to action is never cut: with Larger Text on a small phone the label shrinks to fit.
          if (currency != null)
            Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: CostLabel(label: label, currency: currency!, amount: amount!, prefix: amountPrefix, color: fg, fontSize: TypeSize.callout)))
          else
            Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1, softWrap: false, style: TextStyle(fontSize: TypeSize.callout, fontWeight: FontWeight.w600, letterSpacing: -0.2, color: fg)))),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ],
    );
    return Pressable(
      onTap: loading ? null : onTap,
      // Compact buttons (Claim, Play: 34-36 pt) keep their look and get a 44 pt touch box.
      child: TapTarget(
        minSize: height < 44 ? 44 : 0,
        child: Container(
          height: height,
          padding: EdgeInsets.symmetric(horizontal: expand ? 16 : 20),
          decoration: BoxDecoration(color: bg, border: border, borderRadius: BorderRadius.circular(Radii.md)),
          // Gold coins and amber hints go grey with the label when disabled.
          child: inactive
              ? ColorFiltered(colorFilter: _greyscale, child: Opacity(opacity: 0.7, child: CurrencyInk(color: fg, child: content)))
              : (filled ? CurrencyInk(color: fg, child: content) : content),
        ),
      ),
    );
  }
}

const _greyscale = ColorFilter.matrix(<double>[
  0.2126, 0.7152, 0.0722, 0, 0,
  0.2126, 0.7152, 0.0722, 0, 0,
  0.2126, 0.7152, 0.0722, 0, 0,
  0, 0, 0, 1, 0,
]);

/// "Label [currency mark] amount" for anything that costs or pays coins,
/// tickets or hints. Used inside [BigButton.cost]; also usable on its own in
/// rows and sheets so prices read the same everywhere.
class CostLabel extends StatelessWidget {
  const CostLabel({super.key, required this.label, required this.currency, required this.amount, this.prefix = '', this.color, this.fontSize = TypeSize.body, this.iconSize});
  final String label;
  final Currency currency;
  final int amount;
  /// E.g. "+" for a payout.
  final String prefix;
  final Color? color;
  final double fontSize;
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    final fg = color ?? context.colors.textPrimary;
    final mark = iconSize ?? fontSize * 1.15;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600, letterSpacing: -0.2, color: fg))),
        SizedBox(width: fontSize * 0.5),
        currencyIcon(currency, size: mark, mono: fg.computeLuminance() > 0.8, monoColor: fg),
        SizedBox(width: fontSize * 0.3),
        Text('$prefix${formatCount(amount)}', style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w700, letterSpacing: -0.2, color: fg)),
      ],
    );
  }
}

/// Small round icon button (used in HUDs and headers).
class RoundIconButton extends StatelessWidget {
  const RoundIconButton({super.key, required this.icon, this.onTap, this.size = 40, this.color, this.iconColor, this.badge, this.label});
  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final Color? color;
  final Color? iconColor;
  final String? badge;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final button = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color ?? c.card, shape: BoxShape.circle, border: Border.all(color: c.stroke)),
      child: Icon(icon, size: size * 0.48, color: iconColor ?? c.textPrimary),
    );
    Widget child = badge == null
        ? button
        : Stack(
            clipBehavior: Clip.none,
            children: [
              button,
              Positioned(
                right: -4,
                top: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Brand.live, borderRadius: BorderRadius.circular(999)),
                  child: Text(badge!, style: const TextStyle(color: Colors.white, fontSize: TypeSize.micro, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          );
    if (label != null) {
      child = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          child,
          const SizedBox(height: 4),
          Text(label!, style: TextStyle(fontSize: TypeSize.micro, fontWeight: FontWeight.w600, color: c.textSecondary)),
        ],
      );
    }
    return Pressable(onTap: onTap, scale: 0.9, child: TapTarget(child: child));
  }
}

/// Coins / tickets / hints pill shown in headers.
class CurrencyPill extends StatelessWidget {
  const CurrencyPill({super.key, required this.currency, required this.value, this.onAdd, this.color = Brand.coin, this.compact = false, this.abbreviate = false});
  final Currency currency;
  final int value;
  final VoidCallback? onAdd;
  final Color color;
  final bool compact;

  /// Balances from 100,000 written short ([compactCount]: "123K", "1.23M"), so the pill keeps its
  /// width in the header; the exact number is in the Store.
  final bool abbreviate;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Pressable(
      onTap: onAdd,
      scale: 0.95,
      child: TapTarget(
        child: Container(
        height: 34,
        padding: EdgeInsets.only(left: 9, right: onAdd != null ? 5 : 12),
        decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(999), border: Border.all(color: c.stroke)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            currencyIcon(currency, size: 16),
            const SizedBox(width: 6),
            AnimatedCounter(
              value: value,
              format: abbreviate ? compactCount : null,
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: compact ? TypeSize.footnote : TypeSize.body, color: c.textPrimary, letterSpacing: -0.2),
            ),
            if (onAdd != null) ...[
              const SizedBox(width: 6),
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(color: c.accentTint, shape: BoxShape.circle),
                child: Icon(AppIcons.plus, size: 13, color: context.accent),
              ),
            ],
          ],
        ),
      ),
      ),
    );
  }
}

/// Number that counts up/down when changed.
class AnimatedCounter extends StatelessWidget {
  const AnimatedCounter({super.key, required this.value, this.style, this.format});
  final int value;
  final TextStyle? style;

  /// How the number is written ([formatCount] by default).
  final String Function(int value)? format;
  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value.toDouble()),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
      builder: (_, v, _) => Text((format ?? formatCount)(v.round()), style: (style ?? const TextStyle()).copyWith(fontFeatures: tabularFigures)),
    );
  }
}

/// A tab's large title (Library, Quests, Social, Profile). One line at
/// every text size: when Larger Text leaves too little room it scales down
/// instead of wrapping ("So" / "cial").
class PageTitle extends StatelessWidget {
  const PageTitle(this.title, {super.key});
  final String title;
  @override
  Widget build(BuildContext context) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(title, maxLines: 1, softWrap: false, style: Theme.of(context).textTheme.headlineLarge),
      );
}

/// Section title with optional trailing action.
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.subtitle, this.action, this.onAction, this.trailing, this.padding = const EdgeInsets.fromLTRB(20, 28, 20, 12)});
  final String title;
  final String? subtitle;
  final String? action;
  final VoidCallback? onAction;
  /// Widget on the right instead of the text [action] (e.g. a countdown chip).
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final titleText = Text(title, style: Theme.of(context).textTheme.headlineSmall);
    // A text action sits on the title's baseline, as iOS places "See All"; a trailing widget (a
    // countdown chip) stays aligned to the bottom of the title block.
    final Widget titleRow = action == null || trailing != null
        ? titleText
        : Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(child: titleText),
              const SizedBox(width: 12),
              Pressable(
                onTap: onAction,
                // 168: at least 44 pt wide. A 44 pt tall box would move the title's baseline (011) and
                // push the subtitle down, so the height stays the title's line.
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 44),
                  child: Text(action!, textAlign: TextAlign.right, style: TextStyle(color: context.accent, fontWeight: FontWeight.w600, fontSize: TypeSize.body)),
                ),
              ),
            ],
          );
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                titleRow,
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: TextStyle(color: c.textSecondary, fontSize: TypeSize.footnote)),
                ],
                // Large text: the trailing chip goes under the title instead of squeezing it.
                if (trailing != null && A11y.largeText(context)) Padding(padding: const EdgeInsets.only(top: 8), child: trailing!),
              ],
            ),
          ),
          if (trailing != null && !A11y.largeText(context)) Padding(padding: const EdgeInsets.only(bottom: 2), child: trailing!),
        ],
      ),
    );
  }
}

/// Frosted glass panel for overlays on top of imagery.
class Glass extends StatelessWidget {
  const Glass({super.key, required this.child, this.radius = Radii.md, this.padding = const EdgeInsets.all(12), this.opacity = 0.55, this.dark = false});
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final double opacity;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final base = dark ? Colors.black : (context.isDark ? const Color(0xFF17171C) : Colors.white);
    // Increase contrast: dark glass on a photo is at least 62% black, so white text on it reads.
    final alpha = A11y.increaseContrastOf(context) ? math.max(opacity, dark ? 0.62 : 0.9) : opacity;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: base.withValues(alpha: alpha),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: Colors.white.withValues(alpha: dark ? 0.12 : 0.35)),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Network image with a BlurHash (or shimmer) placeholder and rounded corners.
class NetImage extends StatelessWidget {
  const NetImage({super.key, required this.url, this.blurhash, this.fit = BoxFit.cover, this.radius = 0, this.width, this.height, this.alignment = Alignment.center});
  final String url;
  /// Compact BlurHash string; when present the blurred colours show instantly.
  final String? blurhash;
  final BoxFit fit;
  final double radius;
  final double? width;
  final double? height;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hasHash = blurhash != null && blurhash!.length >= 6;
    Widget img = url.isEmpty
        ? Container(color: c.boardBackground)
        : Image(
            image: CachedUrlImage(url),
            fit: fit,
            width: width,
            height: height,
            alignment: alignment,
            gaplessPlayback: true,
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
              if (wasSynchronouslyLoaded) return child;
              return Stack(
                fit: StackFit.passthrough,
                children: [
                  // A BlurHash is static, so it can stay under the picture;
                  // the animated shimmer goes away once the picture is in.
                  if (frame == null || hasHash) Positioned.fill(child: hasHash ? HashImage(hash: blurhash!, color: c.boardBackground) : const _Shimmer()),
                  AnimatedOpacity(opacity: frame == null ? 0 : 1, duration: const Duration(milliseconds: 250), curve: Curves.easeOut, child: child),
                ],
              );
            },
            errorBuilder: (_, _, _) => SizedBox(
              width: width,
              height: height,
              child: hasHash
                  ? HashImage(hash: blurhash!, color: c.boardBackground)
                  : Container(color: c.boardBackground, child: Icon(AppIcons.image, color: c.textTertiary)),
            ),
          );
    if (radius > 0) img = ClipRRect(borderRadius: BorderRadius.circular(radius), child: img);
    return img;
  }
}

class _Shimmer extends StatefulWidget {
  const _Shimmer();
  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // Reduce motion: no sweeping highlight, a still placeholder.
    if (A11y.reduceMotionOf(context)) {
      if (_c.isAnimating) _c.stop();
      return ColoredBox(color: c.boardBackground);
    }
    if (!_c.isAnimating) _c.repeat();
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment(-1 + _c.value * 3, 0),
            end: Alignment(_c.value * 3, 0),
            colors: [c.boardBackground, c.stroke, c.boardBackground],
          ),
        ),
      ),
    );
  }
}

/// A block of content that is still loading: the image shimmer in a rounded box. Screens show
/// skeletons shaped like what is coming (their title and bars stay), never a lone spinner on an
/// empty page; spinners are for actions (buttons) and for "more" at the end of a list.
class Skeleton extends StatelessWidget {
  const Skeleton({super.key, this.width, this.height, this.radius = Radii.sm});
  final double? width;
  final double? height;
  final double radius;
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: SizedBox(width: width ?? double.infinity, height: height ?? double.infinity, child: const _Shimmer()),
      );
}

/// A loading pack card: the shape of a `PackCard` (cover, name, progress line).
class SkeletonPackCard extends StatelessWidget {
  const SkeletonPackCard({super.key});
  @override
  Widget build(BuildContext context) => SoftCard(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Expanded(child: Skeleton(radius: 0)),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Skeleton(width: 96, height: 14),
                  SizedBox(height: 10),
                  Skeleton(height: 6, radius: 3),
                ],
              ),
            ),
          ],
        ),
      );
}

/// Star row for ratings (0-3).
class Stars extends StatelessWidget {
  const Stars({super.key, required this.count, this.size = 16, this.max = 3, this.animate = false});
  final int count;
  final double size;
  final int max;
  final bool animate;
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < max; i++)
          Icon(i < count ? AppIcons.star : AppIcons.starOutline, size: size, color: i < count ? context.star : context.colors.textTertiary.withValues(alpha: context.highContrast ? 1 : 0.5)),
      ],
    );
  }
}

/// Rounded progress bar.
class ProgressBar extends StatelessWidget {
  const ProgressBar({super.key, required this.value, this.height = 8, this.color, this.background, this.gradient});
  final double value;
  final double height;
  final Color? color;
  final Color? background;
  final Gradient? gradient;
  @override
  Widget build(BuildContext context) {
    final fill = color ?? context.accent;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            Container(color: background ?? context.colors.track),
            TweenAnimationBuilder<double>(
              tween: Tween(end: value.clamp(0, 1)),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (_, v, _) => FractionallySizedBox(
                widthFactor: v,
                alignment: Alignment.centerLeft,
                child: Container(decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(height))),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The app's segmented control in the iOS 26 shape (Social's Leaderboard / Friends, the Account
/// form's Create account / Sign in, Settings > Theme): a capsule track and a glass thumb that
/// springs to the chosen segment, stretches a little while it travels and lifts under the finger,
/// which can drag it to another segment. The thumb carries a light rim on its upper edge, the
/// specular edge of iOS glass; the selected label is in the primary text colour and a step
/// heavier, the others in secondary. Right in light and dark, on cards, sheets and the canvas.
class AppSegmentedControl<T extends Object> extends StatefulWidget {
  const AppSegmentedControl({super.key, required this.value, required this.segments, required this.onChanged, this.height = 36, this.segmentPadding = const EdgeInsets.symmetric(horizontal: 10), this.badges = const {}});
  final T value;
  final Map<T, String> segments;
  final ValueChanged<T> onChanged;

  /// Segments with something new behind them (an unopened message): a small accent dot after the
  /// label, shown whether or not the segment is selected, until the thing is dealt with.
  final Set<T> badges;

  /// Capsule height at the default text size (it grows with Larger Text).
  final double height;
  final EdgeInsetsGeometry segmentPadding;

  /// The track: iOS's tertiary fill, a grey wash that reads on white cards, the canvas and sheets.
  static Color trackColor(BuildContext context) => context.isDark ? const Color(0x3D767680) : const Color(0x1F767680);

  /// The thumb's fill: white in light mode; a white glass layer over the track in dark mode.
  static Color thumbColor(BuildContext context) => context.isDark ? const Color(0xFF4A4A52) : Colors.white;

  @override
  State<AppSegmentedControl<T>> createState() => _AppSegmentedControlState<T>();
}

class _AppSegmentedControlState<T extends Object> extends State<AppSegmentedControl<T>> with SingleTickerProviderStateMixin {
  static const _inset = 3.0;
  static const _spring = SpringDescription(mass: 1, stiffness: 420, damping: 34);

  /// The thumb's position in segments (0 = first). Unbounded so the spring may overshoot.
  late final AnimationController _pos = AnimationController.unbounded(vsync: this, value: _index.toDouble());
  bool _lifted = false;
  bool _dragging = false;

  List<T> get _keys => widget.segments.keys.toList();
  int get _index => _keys.indexOf(widget.value).clamp(0, widget.segments.length - 1);

  @override
  void didUpdateWidget(AppSegmentedControl<T> old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && !_dragging) _springTo(_index);
  }

  @override
  void dispose() {
    _pos.dispose();
    super.dispose();
  }

  void _springTo(int i) {
    // Reduce motion: the thumb moves to the segment at once, without the spring.
    if (A11y.reduceMotionOf(context)) {
      _pos.value = i.toDouble();
      return;
    }
    _pos.animateWith(SpringSimulation(_spring, _pos.value, i.toDouble(), _pos.velocity));
  }

  int _segmentAt(double x, double width) {
    final n = widget.segments.length;
    final seg = (width - _inset * 2) / n;
    return ((x - _inset) / seg).floor().clamp(0, n - 1);
  }

  void _select(int i) {
    if (i == _index) {
      _springTo(i);
      return;
    }
    Haptics.selection();
    _springTo(i);
    widget.onChanged(_keys[i]);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dark = context.isDark;
    final n = widget.segments.length;
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.35);
    final height = math.max(widget.height, scaler.scale(TypeSize.footnote) + 20);
    final radius = BorderRadius.circular(height / 2);
    final labelStyle = const TextStyle(fontSize: TypeSize.footnote, letterSpacing: -0.1, fontWeight: FontWeight.w600);
    return LayoutBuilder(
      builder: (context, cons) {
        // Full width where the parent gives one (Social, the Account form); in a row's trailing
        // slot (Settings > Theme) every segment is as wide as the longest label.
        var width = cons.maxWidth;
        if (!cons.hasBoundedWidth) {
          var widest = 0.0;
          for (final label in widget.segments.values) {
            final tp = TextPainter(text: TextSpan(text: label, style: labelStyle), textDirection: TextDirection.ltr, textScaler: scaler, maxLines: 1)..layout();
            widest = math.max(widest, tp.width);
            tp.dispose();
          }
          width = n * (widest + widget.segmentPadding.horizontal) + _inset * 2;
        }
        final seg = (width - _inset * 2) / n;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) {
            setState(() => _lifted = false);
            _select(_segmentAt(d.localPosition.dx, width));
          },
          onTapDown: (d) {
            if (_segmentAt(d.localPosition.dx, width) == _index) setState(() => _lifted = true);
          },
          onTapCancel: () => setState(() => _lifted = false),
          onHorizontalDragStart: (d) {
            // Like iOS: only the thumb can be dragged; a drag elsewhere does nothing.
            if (_segmentAt(d.localPosition.dx, width) != _index) return;
            _pos.stop();
            setState(() {
              _dragging = true;
              _lifted = true;
            });
          },
          onHorizontalDragUpdate: (d) {
            if (!_dragging) return;
            _pos.value = ((d.localPosition.dx - _inset - seg / 2) / seg).clamp(-0.08, n - 1 + 0.08);
          },
          onHorizontalDragEnd: (_) {
            if (!_dragging) return;
            setState(() {
              _dragging = false;
              _lifted = false;
            });
            _select(_pos.value.round().clamp(0, n - 1));
          },
          onHorizontalDragCancel: () {
            if (!_dragging) return;
            setState(() {
              _dragging = false;
              _lifted = false;
            });
            _springTo(_index);
          },
          child: Listener(
            onPointerUp: (_) {
              if (_lifted && !_dragging) setState(() => _lifted = false);
            },
            child: SizedBox(
              height: height,
              width: width,
              child: DecoratedBox(
                decoration: BoxDecoration(color: AppSegmentedControl.trackColor(context), borderRadius: radius),
                child: AnimatedBuilder(
                  animation: _pos,
                  builder: (context, _) {
                    final at = _pos.value;
                    // The thumb stretches with its speed, the way the iOS 26 thumb does in motion.
                    final stretch = 1 + (_pos.velocity.abs() * 0.012).clamp(0.0, 0.12);
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          left: _inset + seg * at,
                          top: _inset,
                          bottom: _inset,
                          width: seg,
                          child: Transform.scale(
                            scaleX: A11y.reduceMotionOf(context) ? 1 : stretch,
                            child: AnimatedScale(
                              scale: _lifted && !A11y.reduceMotionOf(context) ? 1.06 : 1,
                              duration: const Duration(milliseconds: 160),
                              curve: Curves.easeOutCubic,
                              child: _SegmentThumb(dark: dark, lifted: _lifted, radius: radius),
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            const SizedBox(width: _inset),
                            for (var i = 0; i < n; i++)
                              Expanded(
                                child: () {
                                  // 1 on the thumb, 0 a segment or more away: the label's colour and
                                  // weight follow the thumb as it slides.
                                  final on = (1 - (at - i).abs()).clamp(0.0, 1.0);
                                  final label = widget.segments[_keys[i]]!;
                                  return Semantics(
                                    button: true,
                                    selected: i == _index,
                                    inMutuallyExclusiveGroup: true,
                                    // VoiceOver activates a segment here; touches go through the
                                    // control's own gesture detector.
                                    onTap: () => _select(i),
                                    child: Padding(
                                      padding: widget.segmentPadding,
                                      child: Center(
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                label,
                                                maxLines: 1,
                                                softWrap: false,
                                                style: labelStyle.copyWith(
                                                  fontWeight: FontWeight.lerp(FontWeight.w500, FontWeight.w600, on),
                                                  color: Color.lerp(c.textSecondary, c.textPrimary, on),
                                                ),
                                              ),
                                              if (widget.badges.contains(_keys[i])) ...[
                                                const SizedBox(width: 6),
                                                Container(
                                                  key: ValueKey('segment-badge-${_keys[i]}'),
                                                  width: 7,
                                                  height: 7,
                                                  decoration: BoxDecoration(color: context.accent, shape: BoxShape.circle),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                }(),
                              ),
                            const SizedBox(width: _inset),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The glass thumb of [AppSegmentedControl]: a capsule with a soft shadow and a rim that is
/// brighter along its upper edge. Lifted (under the finger) it turns clearer and its shadow grows.
class _SegmentThumb extends StatelessWidget {
  const _SegmentThumb({required this.dark, required this.lifted, required this.radius});
  final bool dark;
  final bool lifted;
  final BorderRadius radius;

  @override
  Widget build(BuildContext context) {
    final fill = AppSegmentedControl.thumbColor(context).withValues(alpha: lifted ? (dark ? 0.78 : 0.82) : 1);
    // Increase contrast: a solid outline, so the selected segment stands out from the track at 3:1.
    final contrast = context.highContrast;
    final rim = contrast
        ? [context.colors.controlStroke, context.colors.controlStroke]
        : dark
            ? [Colors.white.withValues(alpha: 0.34), Colors.white.withValues(alpha: 0.06)]
            : [Colors.white, Colors.black.withValues(alpha: 0.07)];
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.all(contrast ? 1 : 0.75),
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: rim),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: dark ? 0.35 : (lifted ? 0.16 : 0.10)), blurRadius: lifted ? 14 : 6, offset: Offset(0, lifted ? 4 : 2)),
          BoxShadow(color: Colors.black.withValues(alpha: dark ? 0.2 : 0.04), blurRadius: 1, offset: const Offset(0, 0.5)),
        ],
      ),
      child: DecoratedBox(decoration: BoxDecoration(color: fill, borderRadius: radius)),
    );
  }
}

/// A reward as a chip, the Home level card's style (design QA 006 C): a currency amount in a
/// neutral pill ([RewardChip.amount]); something that opens or is given (an avatar, a shape, a
/// board size) in a cobalt-tinted pill ([RewardChip.unlock]). Achievements, the level card and
/// Claim all use the same marks, so a reward reads the same wherever it is promised.
///
/// Two sizes: the default is compact (24 pt, 12 pt figures) for lists of rewards (achievements,
/// Claim all); [large] is the one reward a card is about (the Home level card's next level): the
/// pill sizes to its content with 13 pt figures.
class RewardChip extends StatelessWidget {
  const RewardChip.amount({super.key, required Currency this.currency, required int this.value, this.large = false})
      : leading = null,
        label = null;
  const RewardChip.unlock({super.key, required Widget this.leading, required String this.label, this.large = false})
      : currency = null,
        value = null;

  final Currency? currency;
  final int? value;
  final Widget? leading;
  final String? label;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final unlock = currency == null;
    return Container(
      height: large ? null : 24,
      padding: large ? const EdgeInsets.symmetric(horizontal: 9, vertical: 5) : const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: unlock ? c.accentTint : c.canvas,
        borderRadius: BorderRadius.circular(Radii.pill),
        border: unlock ? null : Border.all(color: c.stroke),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: unlock
            ? [leading!, const SizedBox(width: 4), Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Text(label!, maxLines: 1, style: TextStyle(fontSize: TypeSize.caption, fontWeight: FontWeight.w600, color: context.accent))))]
            : [Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Amount(currency: currency!, value: value!, size: 14, fontSize: large ? TypeSize.footnote : TypeSize.caption, weight: FontWeight.w700)))],
      ),
    );
  }
}

/// Small label chip (category, status). On a photo ([onImage]) it is a
/// [PhotoChip]: the one style for anything drawn over a picture.
class Chip2 extends StatelessWidget {
  const Chip2({super.key, required this.label, this.icon, this.onImage = false, this.color, this.foreground, this.dot});
  final String label;
  final IconData? icon;
  final bool onImage;
  final Color? color;
  final Color? foreground;

  /// A status dot before the label (`Brand.live` for live, today, new).
  final Color? dot;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (onImage && color == null) {
      return PhotoChip(
        dot: dot,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 12, color: Colors.white), const SizedBox(width: 4)],
            Text(label, style: PhotoChip.textStyle),
          ],
        ),
      );
    }
    final bg = color ?? c.canvas;
    final fg = foreground ?? c.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999), border: color != null ? null : Border.all(color: c.controlStroke)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot != null) ...[Container(width: 6, height: 6, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)), const SizedBox(width: 5)],
          if (icon != null) ...[Icon(icon, size: 12, color: fg), const SizedBox(width: 4)],
          // A chip in a narrow place shrinks its words with a large text size instead of overflowing.
          Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1, style: TextStyle(color: fg, fontSize: TypeSize.caption, fontWeight: FontWeight.w600)))),
        ],
      ),
    );
  }
}

/// The one chip for text over a photo (covers, pack cards, picture tiles,
/// the pack hero, event cards, house ads): a dark translucent pill with a
/// hairline, white 11.5 pt semibold text, and an optional status dot.
/// Status is the dot, never a solid red or gold fill over the picture, so
/// the photo keeps its colour and every chip reads on light and dark photos.
class PhotoChip extends StatelessWidget {
  const PhotoChip({super.key, required this.child, this.dot});
  final Widget child;
  final Color? dot;

  static const textStyle = TextStyle(color: Colors.white, fontSize: TypeSize.caption, fontWeight: FontWeight.w600, letterSpacing: -0.1);

  @override
  Widget build(BuildContext context) {
    return Container(
      // 24 pt, taller only when a large text size needs it (the label is never cut off).
      constraints: const BoxConstraints(minHeight: 24),
      padding: EdgeInsets.only(left: dot != null ? 8 : 9, right: 9, top: 2, bottom: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: A11y.increaseContrastOf(context) ? 0.66 : 0.5),
        borderRadius: BorderRadius.circular(Radii.pill),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot != null) ...[Container(width: 6, height: 6, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)), const SizedBox(width: 6)],
          child,
        ],
      ),
    );
  }
}

/// The one round button over a photo (the picture credit on the difficulty
/// preview, the back button over the finished picture and on the pack cover):
/// frosted dark glass with a hairline and a white mark, the [PhotoChip]'s
/// material, so it reads on light and dark photos alike. Drawn at [size],
/// tapped in 44 pt.
class PhotoButton extends StatelessWidget {
  const PhotoButton({super.key, required this.icon, required this.onTap, this.size = 36, this.semanticLabel, this.onPhoto = true});
  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final String? semanticLabel;

  /// False once the photo has gone from under it (the pack cover collapsed into the glass bar):
  /// the plain round bar button, card fill, hairline and an ink mark. The change animates.
  final bool onPhoto;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Pressable(
        onTap: onTap,
        scale: 0.9,
        child: TapTarget(
          child: ClipOval(
            child: BackdropFilter(
              enabled: onPhoto,
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: onPhoto ? Colors.black.withValues(alpha: A11y.increaseContrastOf(context) ? 0.55 : 0.34) : c.card,
                  shape: BoxShape.circle,
                  border: Border.all(color: onPhoto ? Colors.white.withValues(alpha: 0.2) : c.stroke, width: onPhoto ? 0.5 : 1),
                ),
                child: Icon(icon, size: size * 0.48, color: onPhoto ? Colors.white : c.textPrimary),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The title block every sheet starts with: one title style (20 pt bold) and
/// one subtitle style (14 pt, secondary), so sheets read as one family.
/// Sheets that are a list or a choice align it left; sheets that lead with
/// a picture or an icon centre it ([center]).
class SheetHeader extends StatelessWidget {
  const SheetHeader({super.key, required this.title, this.subtitle, this.center = false});
  final String title;
  final String? subtitle;
  final bool center;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final align = center ? TextAlign.center : TextAlign.start;
    return Column(
      crossAxisAlignment: center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, textAlign: align, style: TextStyle(fontSize: TypeSize.title3, fontWeight: FontWeight.w700, letterSpacing: -0.3, height: 1.2, color: c.textPrimary)),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle!, textAlign: align, style: TextStyle(fontSize: TypeSize.body, height: 1.35, color: c.textSecondary)),
        ],
      ],
    );
  }
}

/// Content-sized modal sheet in the iOS 26 style: glass surface, grabber,
/// light dim behind it. For full-height modals (Store, Wheel, Account) the
/// router uses [SheetPage].
///
/// Every sheet follows one rule (`lib/widgets/sheets.dart`, docs/native-ui.md "Sheets"): it stops
/// below [SheetMetrics.topGap], so a strip of the page stays in view and a tap there closes it; a
/// drag down on the grabber, or on the content once it is at its top, closes it. Content taller
/// than the sheet scrolls. With [scrollable] the builder lays out its own [SheetScrollBody], with a
/// footer (the sheet's buttons) that stays put while the list above it scrolls. With [dismissible]
/// false neither the dim nor a drag closes it.
///
/// On a wide window (the web on a tablet or desktop) the same sheet opens as a centred panel
/// ([PanelRoute]), the way iPad shows a form sheet, instead of stretching along the bottom.
Future<T?> showAppSheet<T>(BuildContext context, {required WidgetBuilder builder, bool scrollable = false, bool dismissible = true}) {
  // The dim has to be stronger in dark mode to separate the sheet from a dark page.
  final barrier = Colors.black.withValues(alpha: context.isDark ? 0.5 : 0.32);
  if (context.isWide) {
    return Navigator.of(context, rootNavigator: true).push<T>(PanelRoute<T>(
      maxWidth: PageWidth.sheet,
      dismissible: dismissible,
      barrierColor: barrier,
      builder: (ctx) => GlassSheet(panel: true, scrollable: scrollable, child: builder(ctx)),
    ));
  }
  // Root navigator: the sheet must cover the floating tab bar, which lives above the tab shell's body.
  final navigator = Navigator.of(context, rootNavigator: true);
  return navigator.push<T>(GlassSheetRoute<T>(
    dismissible: dismissible,
    barrierColor: barrier,
    capturedThemes: InheritedTheme.capture(from: context, to: navigator.context),
    builder: (ctx) => GlassSheet(
      grabber: dismissible,
      scrollable: scrollable,
      bottomInset: MediaQuery.viewInsetsOf(ctx).bottom,
      child: builder(ctx),
    ),
  ));
}

/// Root messenger; `CardenApp` hosts a Scaffold above the Navigator for
/// it. Toasts no longer use it (see [showToast]); kept for the host.
final appMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// How long a toast stays: long enough to read (about 45 ms a character),
/// 2.2 s at least and 5 s at most.
Duration toastDuration(String message) => Duration(milliseconds: (1500 + message.length * 45).clamp(2200, 5000));

/// The shortest a toast with an action stays, so there is time to reach it.
const toastActionDuration = Duration(seconds: 4);

OverlayEntry? _toastEntry;

/// A short notice in an iOS 26 glass capsule that drops in under the status
/// bar (the Dynamic Island on newer phones), above every screen, sheet and
/// alert, and never over the tab bar, a game's tools or a sheet's buttons.
/// One at a time: a new toast replaces the one on screen. Tap or swipe up to
/// close it early; VoiceOver reads it out.
///
/// An [action] (Gather's Undo) is a text button at the end in the accent
/// colour, 44 pt to tap and a button to VoiceOver; the toast then stays at
/// least [toastActionDuration], and tapping the action runs it and closes the
/// toast. The callback runs after the screen that showed the toast may have
/// gone, so it checks `mounted` itself.
void showToast(BuildContext context, String message, {IconData? icon, Widget? leading, ({String label, VoidCallback onTap})? action}) {
  // The root navigator's own context sits above its overlay.
  final overlay = context is StatefulElement && context.state is NavigatorState ? (context.state as NavigatorState).overlay : Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _toastEntry?.remove();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _Toast(
      key: const ValueKey('toast'),
      message: message,
      icon: icon,
      leading: leading,
      action: action,
      duration: action == null || toastDuration(message) > toastActionDuration ? toastDuration(message) : toastActionDuration,
      onDone: () {
        if (_toastEntry == entry) _toastEntry = null;
        if (entry.mounted) entry.remove();
      },
    ),
  );
  _toastEntry = entry;
  overlay.insert(entry);
}

class _Toast extends StatefulWidget {
  const _Toast({super.key, required this.message, this.icon, this.leading, this.action, required this.duration, required this.onDone});
  final String message;
  final IconData? icon;
  final Widget? leading;
  final ({String label, VoidCallback onTap})? action;
  final Duration duration;
  final VoidCallback onDone;

  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 280), reverseDuration: const Duration(milliseconds: 200))..forward();
  late final _curve = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic, reverseCurve: Curves.easeIn);
  Timer? _timer;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.duration + const Duration(milliseconds: 280), _close);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _curve.dispose();
    _c.dispose();
    super.dispose();
  }

  void _close() {
    if (_closing || !mounted) return;
    _closing = true;
    _timer?.cancel();
    _c.reverse().whenComplete(widget.onDone);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isDark = context.isDark;
    final top = MediaQuery.viewPaddingOf(context).top;
    final action = widget.action;
    return Positioned(
      top: top + 6,
      left: 16,
      right: 16,
      child: Align(
        alignment: Alignment.topCenter,
        child: FadeTransition(
          opacity: _curve,
          child: SlideTransition(
            position: Tween(begin: A11y.reduceMotionOf(context) ? Offset.zero : const Offset(0, -0.5), end: Offset.zero).animate(_curve),
            child: GestureDetector(
              onTap: _close,
              onVerticalDragUpdate: (d) {
                if (d.delta.dy < -2) _close();
              },
              child: Semantics(
                liveRegion: true,
                child: Material(
                  type: MaterialType.transparency,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420, minHeight: 44),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.14), blurRadius: 24, offset: const Offset(0, 8))],
                      ),
                      child: GlassSurface(
                        sigma: 30,
                        opacity: isDark ? 0.82 : 0.88,
                        borderRadius: BorderRadius.circular(22),
                        hairline: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.14) : Colors.black.withValues(alpha: 0.06), width: 0.5),
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(16, 0, action == null ? 18 : 4, 0),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (widget.leading != null) ...[widget.leading!, const SizedBox(width: 10)] else if (widget.icon != null) ...[Icon(widget.icon, size: 18, color: c.textSecondary), const SizedBox(width: 10)],
                              Flexible(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 11),
                                  child: Text(widget.message, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: TypeSize.body, height: 1.3, fontWeight: FontWeight.w600, color: c.textPrimary, letterSpacing: -0.1)),
                                ),
                              ),
                              if (action != null)
                                Semantics(
                                  container: true,
                                  button: true,
                                  child: Pressable(
                                    key: const ValueKey('toast-action'),
                                    onTap: () {
                                      _close();
                                      action.onTap();
                                    },
                                    child: TapTarget(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 12),
                                        child: Text(action.label, style: TextStyle(fontSize: TypeSize.body, fontWeight: FontWeight.w700, color: context.accent, letterSpacing: -0.1)),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Empty-state placeholder.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: c.accentTint, shape: BoxShape.circle),
              child: Icon(icon, size: 30, color: context.accent),
            ),
            const SizedBox(height: 14),
            Text(title, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(message!, textAlign: TextAlign.center, style: TextStyle(color: c.textSecondary)),
            ],
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}

/// Adaptive activity indicator.
class Loader extends StatelessWidget {
  const Loader({super.key, this.size = 28});
  final double size;
  @override
  Widget build(BuildContext context) => Center(child: SizedBox(width: size, height: size, child: const CupertinoActivityIndicator()));
}

/// Settings-style list row: leading icon tile, title, subtitle, chevron.
class ListRow extends StatelessWidget {
  const ListRow({super.key, required this.icon, required this.title, this.subtitle, this.onTap, this.trailing, this.tone});
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  /// Colours the icon tile, the title and the chevron (e.g. the theme's
  /// warning colour); the accent and neutral text by default.
  final Color? tone;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = this.tone;
    return Pressable(
      onTap: onTap,
      scale: 0.99,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            tone == null ? IconTile(icon: icon, size: IconTile.small) : IconTile(icon: icon, size: IconTile.small, color: tone.withValues(alpha: 0.16), iconColor: tone),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontWeight: FontWeight.w600, fontSize: TypeSize.body, color: tone)),
                  if (subtitle != null) Text(subtitle!, style: TextStyle(fontSize: TypeSize.footnote, color: c.textSecondary)),
                ],
              ),
            ),
            trailing ?? Icon(AppIcons.chevronRight, size: 16, color: tone ?? c.textTertiary),
          ],
        ),
      ),
    );
  }
}

/// iOS 26 style alert: a glass card with a large radius, title, optional
/// message and child (e.g. an [AlertTextField]), and one or two actions.
/// Returns true when the confirm action was tapped. Use it for every
/// confirmation in the app so they all look the same. With a text field
/// child the card rises above the keyboard.
Future<bool> showAppAlert(
  BuildContext context, {
  required String title,
  String? message,
  Widget? child,
  // Always named for the action (copy guide: never "OK").
  required String confirmLabel,
  String? cancelLabel = 'Cancel',
  bool destructive = false,
  bool Function()? canConfirm,
}) async {
  final result = await showGeneralDialog<bool>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: cancelLabel != null,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.black.withValues(alpha: context.isDark ? 0.5 : 0.28),
    transitionDuration: const Duration(milliseconds: 240),
    transitionBuilder: (ctx, anim, _, widget) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic, reverseCurve: Curves.easeIn);
      // Reduce motion: a fade without the zoom.
      if (A11y.reduceMotionOf(ctx)) return FadeTransition(opacity: curved, child: widget);
      return FadeTransition(opacity: curved, child: ScaleTransition(scale: Tween(begin: 1.06, end: 1.0).animate(curved), child: widget));
    },
    pageBuilder: (ctx, _, _) => _AppAlert(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      destructive: destructive,
      canConfirm: canConfirm,
      child: child,
    ),
  );
  return result ?? false;
}

/// Text field styled for [showAppAlert]: rounded 12, filled, no outline, in
/// the iOS 26 alert idiom. Pass the same [controller] you read after the
/// alert resolves.
class AlertTextField extends StatelessWidget {
  const AlertTextField({
    super.key,
    required this.controller,
    this.placeholder,
    this.autofocus = true,
    this.maxLength,
    this.textCapitalization = TextCapitalization.none,
    this.autocorrect = false,
    this.onChanged,
    this.onSubmitted,
    this.keyboardType,
    this.textInputAction = TextInputAction.done,
  });
  final TextEditingController controller;
  final String? placeholder;
  final bool autofocus;
  final int? maxLength;
  final TextCapitalization textCapitalization;
  final bool autocorrect;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputType? keyboardType;
  final TextInputAction textInputAction;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fill = context.isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05);
    return CupertinoTextField(
      controller: controller,
      placeholder: placeholder,
      autofocus: autofocus,
      maxLength: maxLength,
      textCapitalization: textCapitalization,
      autocorrect: autocorrect,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      textAlign: TextAlign.center,
      cursorColor: context.accent,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      style: TextStyle(fontSize: TypeSize.callout, color: c.textPrimary, letterSpacing: -0.2),
      placeholderStyle: TextStyle(fontSize: TypeSize.callout, color: c.textTertiary, letterSpacing: -0.2),
      decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(12)),
    );
  }
}

class _AppAlert extends StatelessWidget {
  const _AppAlert({required this.title, this.message, this.child, required this.confirmLabel, this.cancelLabel, required this.destructive, this.canConfirm});
  final String title;
  final String? message;
  final Widget? child;
  final String confirmLabel;
  final String? cancelLabel;
  final bool destructive;
  final bool Function()? canConfirm;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isDark = context.isDark;
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    const radius = 28.0;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: inset),
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 290),
            child: Material(
              type: MaterialType.transparency,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.16), blurRadius: 40, offset: const Offset(0, 16))],
                ),
                child: GlassSurface(
                  sigma: 36,
                  // Dark alerts sit one level above sheets: a lighter tint.
                  tint: isDark ? context.colors.elevated.cardElevated : null,
                  opacity: isDark ? 0.9 : 0.86,
                  borderRadius: BorderRadius.circular(radius),
                  hairline: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.14) : Colors.white.withValues(alpha: 0.8), width: 0.5),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // The text and field scroll when a large text size (or the keyboard) leaves too
                      // little room; the buttons below always stay on screen.
                      Flexible(
                        child: SingleChildScrollView(
                          physics: const ClampingScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
                          child: Column(
                          children: [
                            Text(title, textAlign: TextAlign.center, style: TextStyle(fontSize: TypeSize.headline, fontWeight: FontWeight.w700, color: c.textPrimary, letterSpacing: -0.3, height: 1.25)),
                            if (message != null) ...[
                              const SizedBox(height: 6),
                              Text(message!, textAlign: TextAlign.center, style: TextStyle(fontSize: TypeSize.footnote, height: 1.4, color: c.textSecondary)),
                            ],
                            if (child != null) ...[const SizedBox(height: 16), child!],
                          ],
                        ),
                        ),
                      ),
                      // iOS 26 alert actions: capsules, side by side when both
                      // labels fit, otherwise stacked with Cancel last.
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: LayoutBuilder(builder: (context, box) {
                          final cancel = cancelLabel == null ? null : _AlertAction(label: cancelLabel!, onTap: () => Navigator.of(context).pop(false));
                          final confirm = _AlertAction(
                            label: confirmLabel,
                            bold: true,
                            // A deeper red on light glass keeps the label above 4.5:1.
                            color: destructive ? (isDark ? c.danger : const Color(0xFFB91C1C)) : context.accent,
                            onTap: () {
                              if (canConfirm != null && !canConfirm!()) return;
                              Navigator.of(context).pop(true);
                            },
                          );
                          const gap = 10.0;
                          final half = (box.maxWidth - gap) / 2 - 2 * _AlertAction.padding;
                          final sideBySide = cancel == null || (_AlertAction.widthOf(context, cancelLabel!, bold: false) <= half && _AlertAction.widthOf(context, confirmLabel, bold: true) <= half);
                          if (sideBySide) {
                            return Row(
                              children: [
                                if (cancel != null) ...[Expanded(child: cancel), const SizedBox(width: gap)],
                                Expanded(child: confirm),
                              ],
                            );
                          }
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [confirm, const SizedBox(height: gap), cancel],
                          );
                        }),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One choice of [showAppActionSheet].
class AppAction<T> {
  const AppAction(this.label, this.value, {this.destructive = false, this.key, this.leading});
  final String label;
  final T value;

  /// Red: the choice throws something away or acts against someone (Delete, Block).
  final bool destructive;
  final Key? key;

  /// A mark before the label (the ticket or coin of a gift).
  final Widget? leading;
}

/// iOS 26 action sheet in the alert's family: a glass card at the bottom of the screen with an
/// optional title, the choices as capsules (cobalt, or red when destructive) and Cancel last,
/// neutral. Returns the chosen value, or null for Cancel or a tap outside. Use it for every menu of
/// actions (a "..." button, "Add a photo").
Future<T?> showAppActionSheet<T>(BuildContext context, {String? title, String? message, required List<AppAction<T>> actions, String cancelLabel = 'Cancel'}) {
  return showGeneralDialog<T>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.black.withValues(alpha: context.isDark ? 0.5 : 0.28),
    transitionDuration: const Duration(milliseconds: 280),
    transitionBuilder: (ctx, anim, _, widget) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
      if (A11y.reduceMotionOf(ctx)) return FadeTransition(opacity: curved, child: widget);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(position: Tween(begin: const Offset(0, 0.25), end: Offset.zero).animate(curved), child: widget),
      );
    },
    pageBuilder: (ctx, _, _) => _AppActionSheet<T>(title: title, message: message, actions: actions, cancelLabel: cancelLabel),
  );
}

class _AppActionSheet<T> extends StatelessWidget {
  const _AppActionSheet({this.title, this.message, required this.actions, required this.cancelLabel});
  final String? title;
  final String? message;
  final List<AppAction<T>> actions;
  final String cancelLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isDark = context.isDark;
    const radius = 28.0;
    return SafeArea(
      minimum: const EdgeInsets.only(bottom: 8),
      child: Align(
        // On a wide window the menu opens in the middle, like the alerts, not at a far-away edge.
        alignment: context.isWide ? Alignment.center : Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Material(
              type: MaterialType.transparency,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.16), blurRadius: 40, offset: const Offset(0, 16))],
                ),
                child: GlassSurface(
                  sigma: 36,
                  tint: isDark ? context.colors.elevated.cardElevated : null,
                  opacity: isDark ? 0.9 : 0.86,
                  borderRadius: BorderRadius.circular(radius),
                  hairline: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.14) : Colors.white.withValues(alpha: 0.8), width: 0.5),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (title != null || message != null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(8, 2, 8, 14),
                            child: Column(
                              children: [
                                if (title != null)
                                  Text(title!, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: TypeSize.footnote, fontWeight: FontWeight.w600, color: c.textSecondary)),
                                if (message != null) ...[
                                  const SizedBox(height: 2),
                                  Text(message!, textAlign: TextAlign.center, style: TextStyle(fontSize: TypeSize.footnote, height: 1.4, color: c.textSecondary)),
                                ],
                              ],
                            ),
                          ),
                        for (final a in actions) ...[
                          _AlertAction(
                            key: a.key,
                            label: a.label,
                            leading: a.leading,
                            bold: true,
                            color: a.destructive ? (isDark ? c.danger : const Color(0xFFB91C1C)) : context.accent,
                            onTap: () => Navigator.of(context).pop(a.value),
                          ),
                          const SizedBox(height: 10),
                        ],
                        _AlertAction(label: cancelLabel, onTap: () => Navigator.of(context).pop()),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One alert action: a 48 pt capsule. Cancel is neutral; the action is tinted
/// with its colour (cobalt, or red when destructive), text in that colour.
class _AlertAction extends StatelessWidget {
  const _AlertAction({super.key, required this.label, required this.onTap, this.bold = false, this.color, this.leading});
  final String label;
  final VoidCallback onTap;
  final bool bold;
  final Widget? leading;

  /// The action's colour; null for Cancel.
  final Color? color;

  /// Space kept on each side of a label.
  static const padding = 14.0;

  static TextStyle _style({required bool bold, Color? color}) => TextStyle(fontSize: TypeSize.headline, fontWeight: bold ? FontWeight.w600 : FontWeight.w500, color: color, letterSpacing: -0.2);

  /// Width of [label] as drawn, at the current text size.
  static double widthOf(BuildContext context, String label, {required bool bold}) {
    final tp = TextPainter(text: TextSpan(text: label, style: _style(bold: bold)), textDirection: TextDirection.ltr, textScaler: MediaQuery.textScalerOf(context), maxLines: 1)..layout();
    final w = tp.width;
    tp.dispose();
    return w;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = color;
    final fill = tone == null
        ? (context.isDark ? Colors.white.withValues(alpha: 0.10) : Colors.black.withValues(alpha: 0.06))
        : tone.withValues(alpha: context.isDark ? 0.12 : 0.10);
    return Pressable(
      onTap: onTap,
      scale: 0.97,
      sound: false,
      child: Container(
        height: 48,
        width: double.infinity,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: padding),
        decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(Radii.pill)),
        child: leading == null
            ? Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: _style(bold: bold, color: tone ?? c.textPrimary))
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  leading!,
                  const SizedBox(width: 8),
                  Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: _style(bold: bold, color: tone ?? c.textPrimary))),
                ],
              ),
      ),
    );
  }
}
