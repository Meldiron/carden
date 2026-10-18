import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The kinds of touch the app plays (docs/native-ui.md, "Haptics"): only the gentle iOS ones.
enum HapticKind {
  /// A selection click: picking something, a segment, a tab, one tick of a deal or a shuffle.
  selection,

  /// A light impact: a button, a card put down.
  light,

  /// A medium impact: a card that locks in place or joins a group.
  medium,

  /// The system's success notification: a finished picture, a claimed reward.
  success,
}

/// Haptics, gentle and few (owner, 2026-10-18: "subtle, gentle, but in more places"). Off with
/// Settings > Haptics ([enabled]); iOS's own System Haptics switch silences them too. Nothing on
/// the web (a browser would buzz the phone). Every touch passes one gate ([HapticGate]): never two
/// within 70 ms and at most 10 a second, so a busy board (a giant deal, a shared game's changes)
/// never turns into a buzz; a success always plays.
class Haptics {
  Haptics._();

  /// Settings > Haptics.
  static bool enabled = true;

  /// The gate every touch passes ([success] excepted).
  static final gate = HapticGate();

  /// Tests: receives what would play instead of the platform (still through [enabled] and the gate).
  @visibleForTesting
  static void Function(HapticKind kind)? debugSink;

  /// Tests: plays as if on the web (nothing).
  @visibleForTesting
  static bool debugWeb = false;

  /// The time the gate reads (tests set a fake clock).
  @visibleForTesting
  static DateTime Function() now = DateTime.now;

  /// A selection click: picking a card, a segment, a tab.
  static void selection() => play(HapticKind.selection);

  /// A light impact: buttons, a card put down.
  static void light() => play(HapticKind.light);

  /// A medium impact: a lock or a join.
  static void medium() => play(HapticKind.medium);

  /// The success notification: a finished picture, a pack done, a reward claimed.
  static void success() => play(HapticKind.success);

  /// Plays [kind] now, unless haptics are off, this is the web, or the gate says it is too soon.
  static void play(HapticKind kind) {
    if (!enabled || kIsWeb || debugWeb) return;
    if (kind != HapticKind.success && !gate.allow(now())) return;
    final sink = debugSink;
    if (sink != null) return sink(kind);
    switch (kind) {
      case HapticKind.selection:
        HapticFeedback.selectionClick();
      case HapticKind.light:
        HapticFeedback.lightImpact();
      case HapticKind.medium:
        HapticFeedback.mediumImpact();
      case HapticKind.success:
        HapticFeedback.successNotification();
    }
  }

  /// A short run of soft ticks along an animation (the deal, Shuffle): one selection click at each
  /// of [at] (from now) that [planTicks] keeps, then [last] when [lastAt] is given (the cards
  /// landing). Cancel it when the animation goes away.
  static HapticRun run(List<Duration> at, {Duration? lastAt, HapticKind last = HapticKind.light, int max = HapticRun.maxTicks}) {
    final timers = <Timer>[
      for (final t in planTicks(at, max: max)) Timer(t, selection),
      if (lastAt != null) Timer(lastAt, () => play(last)),
    ];
    return HapticRun._(timers);
  }

  /// The ticks of a run: the times of [at] in order, each at least [minGap] after the one before,
  /// at most [max] of them (spread over the whole run, not bunched at its start).
  static List<Duration> planTicks(List<Duration> at, {int max = HapticRun.maxTicks, Duration minGap = HapticRun.tickGap}) {
    if (max <= 0 || at.isEmpty) return const [];
    final sorted = [...at]..sort();
    final spaced = <Duration>[];
    for (final t in sorted) {
      if (spaced.isEmpty || t - spaced.last >= minGap) spaced.add(t);
    }
    if (spaced.length <= max) return spaced;
    // Evenly picked across the run, first and last kept.
    if (max == 1) return [spaced.first];
    return [for (var i = 0; i < max; i++) spaced[(i * (spaced.length - 1) / (max - 1)).round()]];
  }
}

/// A run of ticks in flight ([Haptics.run]).
class HapticRun {
  HapticRun._(this._timers);
  final List<Timer> _timers;

  /// Ticks a run plays at most: a handful, never a buzz.
  static const maxTicks = 5;

  /// The least time between two ticks of a run.
  static const tickGap = Duration(milliseconds: 70);

  /// Stops the ticks still to come.
  void cancel() {
    for (final t in _timers) {
      t.cancel();
    }
  }
}

/// The rate limit every touch passes: at least [minGap] after the last one, and at most
/// [perSecond] in any second.
class HapticGate {
  HapticGate({this.minGap = const Duration(milliseconds: 70), this.perSecond = 10});
  final Duration minGap;
  final int perSecond;
  final _recent = <DateTime>[];

  /// Whether a touch may play at [now]; when it may, it counts.
  bool allow(DateTime now) {
    _recent.removeWhere((t) => now.difference(t) >= const Duration(seconds: 1) || now.isBefore(t));
    if (_recent.isNotEmpty && now.difference(_recent.last) < minGap) return false;
    if (_recent.length >= perSecond) return false;
    _recent.add(now);
    return true;
  }

  /// Forgets what played (tests).
  @visibleForTesting
  void reset() => _recent.clear();

  /// Touches counted in the last second (tests).
  @visibleForTesting
  int get recent => _recent.length;
}
