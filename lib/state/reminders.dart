import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/platform.dart';
import '../core/reminders.dart';
import '../models/models.dart';
import 'catalog.dart';
import 'profile.dart';
import 'progress.dart';
import 'push.dart';
import 'rewards.dart';
import 'settings.dart';

/// Days ahead that get a reminder. A player away for a week hears nothing
/// more until they open the game again (each open plans the next week).
const reminderDays = 7;

/// One daily reminder: a local notification at the player's reminder time.
@immutable
class ReminderNote {
  const ReminderNote({required this.id, required this.at, required this.title, required this.body, required this.route});

  /// The day (`2026-10-14`) for a daily reminder, `event-<id>` for an event note; iOS keeps one
  /// reminder per id.
  final String id;
  final DateTime at;
  final String title;
  final String body;

  /// Where a tap goes: the day's daily puzzle, Home, or an event's pack.
  final String route;

  Map<String, Object?> toJson() => {'id': id, 'at': at.millisecondsSinceEpoch, 'title': title, 'body': body, 'route': route};

  @override
  String toString() => 'ReminderNote($id ${at.hour}:${at.minute.toString().padLeft(2, '0')} "$title" / "$body" -> $route)';
}

/// The reminders to schedule at [now]: one a day at [minutes] after local
/// midnight, for today and the next [days] - 1 days. Today is skipped once
/// the player has claimed today's daily gift or solved today's daily
/// puzzle, and any time already past is skipped. A reminder names the
/// day's daily puzzle when the catalogue has it, and asks to keep the
/// streak when that day's gift would continue a streak of 2 or more.
///
/// [puzzles] is the released catalogue (daily pictures carry a `date`).
List<ReminderNote> planReminders({
  required DateTime now,
  required int minutes,
  required Iterable<Puzzle> puzzles,
  required Profile? profile,
  required Map<String, PuzzleProgress> progress,
  int days = reminderDays,
}) {
  final last = profile?.lastDailyClaim?.toLocal();
  final claimedToday = last != null && Goals.sameDay(last, now);
  final claimedYesterday = last != null && Goals.sameDay(last, DateTime(now.year, now.month, now.day - 1));
  final streak = profile?.streak ?? 0;
  final byDay = {for (final p in puzzles) if (p.date != null) Goals.dayKey(p.date!): p};
  final notes = <ReminderNote>[];
  for (var d = 0; d < days; d++) {
    // Built from calendar fields, so a daylight saving change keeps the time.
    final at = DateTime(now.year, now.month, now.day + d, minutes ~/ 60, minutes % 60);
    if (!at.isAfter(now)) continue;
    final key = Goals.dayKey(at);
    final puzzle = byDay[key];
    if (d == 0 && (claimedToday || (puzzle != null && progress[puzzle.id]?.completed == true))) continue;
    // The gift on day d continues the streak only if the day before was
    // claimed: yesterday for today, today for tomorrow. Later days follow
    // a day without the game, so the streak is gone by then.
    final keepsStreak = streak >= 2 && ((d == 0 && claimedYesterday) || (d == 1 && claimedToday));
    final String title, body;
    if (keepsStreak) {
      title = 'Keep your $streak-day streak';
      body = puzzle != null ? "${puzzle.title} is today's daily puzzle, and your daily gift is waiting." : "Today's daily puzzle and your daily gift are waiting.";
    } else {
      title = "Today's daily puzzle";
      body = puzzle != null ? '${puzzle.title} is ready, and so is your daily gift.' : 'A new picture is ready, and so is your daily gift.';
    }
    notes.add(ReminderNote(id: key, at: at, title: title, body: body, route: puzzle != null ? '/play/${puzzle.id}' : '/home'));
  }
  return notes;
}

/// An upcoming world-day event the reminders can announce.
@immutable
class UpcomingEvent {
  const UpcomingEvent({required this.id, required this.name, required this.opensAt, this.packId, this.pictures = 0});
  final String id;
  final String name;
  final DateTime opensAt;
  final String? packId;

  /// Pictures in its pack (0 when unknown).
  final int pictures;
}

/// Event notes go only to players who stopped opening the game: a note is at least this far
/// ahead when it is planned, and every open plans again (so a player who keeps playing never gets
/// one; the daily reminders cover them).
const eventReminderLead = Duration(days: 5);

/// How far ahead event notes are planned, and the shortest gap between two of them.
const eventReminderWeeks = 6;
const eventReminderGap = Duration(days: 7);

/// The event notes to schedule at [now]: "World Food Day opens tomorrow" at [minutes] after
/// local midnight on the day before an event opens, for events opening within
/// [eventReminderWeeks], only when the note is at least [eventReminderLead] away, at most one per
/// [eventReminderGap], and never on a day in [busyDays] (day keys that already have a daily
/// reminder). A tap opens the event's pack.
List<ReminderNote> planEventReminders({
  required DateTime now,
  required int minutes,
  required Iterable<UpcomingEvent> events,
  Set<String> busyDays = const {},
  int weeks = eventReminderWeeks,
}) {
  final until = now.add(Duration(days: weeks * 7));
  final candidates = <(DateTime, UpcomingEvent)>[];
  for (final e in events) {
    final opens = e.opensAt.toLocal();
    final at = DateTime(opens.year, opens.month, opens.day - 1, minutes ~/ 60, minutes % 60);
    if (at.isBefore(now.add(eventReminderLead)) || at.isAfter(until)) continue;
    if (busyDays.contains(Goals.dayKey(at))) continue;
    candidates.add((at, e));
  }
  candidates.sort((a, b) => a.$1.compareTo(b.$1));
  final notes = <ReminderNote>[];
  DateTime? last;
  for (final (at, e) in candidates) {
    if (last != null && at.difference(last) < eventReminderGap) continue;
    last = at;
    notes.add(ReminderNote(
      id: 'event-${e.id}',
      at: at,
      title: '${e.name} opens tomorrow',
      body: e.pictures > 0 ? 'A new pack of ${e.pictures} pictures for the day, open for a week.' : 'A new picture pack for the day, open for a week.',
      route: e.packId != null && e.packId!.isNotEmpty ? '/library/pack/${e.packId}' : '/events',
    ));
  }
  return notes;
}

/// Settings > New events: a note the evening before a world-day event opens, stored on the device.
/// They promote events, so they are off until the player turns them on: the switch, or Allow in the
/// notification question, whose switch names them (guideline 4.5.4, explicit opt-in; owner,
/// 2026-10-15). Independent of the daily reminders since 2026-10-18.
class EventRemindersNotifier extends Notifier<bool> {
  static const _key = 'eventReminders';

  @override
  bool build() => ref.watch(localStoreProvider).getText(_key) == 'on';

  void set(bool on) {
    ref.read(localStoreProvider).setText(_key, on ? 'on' : 'off');
    state = on;
  }
}

final eventRemindersProvider = NotifierProvider<EventRemindersNotifier, bool>(EventRemindersNotifier.new);

/// The catalogue's world-day events as [UpcomingEvent]s: every event row (created up to a year
/// ahead, released or not) with its pack's picture count.
List<UpcomingEvent> upcomingEvents(Iterable<GameEvent> events, Iterable<Pack> packRows) {
  final pictures = {for (final p in packRows) p.id: p.imageCount};
  return [
    for (final e in events)
      if (e.startAt != null) UpcomingEvent(id: e.id, name: e.name, opensAt: e.startAt!, packId: e.packId, pictures: pictures[e.packId] ?? 0),
  ];
}

/// Keeps the pending reminders in line with the Settings switches (Daily reminders, New events),
/// the iOS permission and the player's day. [refresh] runs when the app starts, comes back and goes
/// to the background, so the week ahead is always planned from the latest state (a claimed gift
/// removes today's reminder). The two switches are independent: event notes need no daily reminder.
class RemindersController {
  RemindersController(this._ref);
  final Ref _ref;

  Future<void> refresh() async {
    if (!supportsNotifications) return;
    final daily = _ref.read(settingsProvider).reminders;
    final events = _ref.read(eventRemindersProvider);
    if (!daily && !events) {
      await ReminderChannel.cancel();
      return;
    }
    if (await ReminderChannel.status() != ReminderPermission.granted) {
      // Turned off in iOS Settings: the switches follow (event notes need a new yes after it).
      _ref.read(settingsProvider.notifier).setReminders(false);
      _ref.read(eventRemindersProvider.notifier).set(false);
      await ReminderChannel.cancel();
      return;
    }
    final now = DateTime.now();
    final minutes = _ref.read(settingsProvider).reminderMinutes;
    final notes = <ReminderNote>[];
    if (daily) {
      var puzzles = const <Puzzle>[];
      try {
        puzzles = await _ref.read(allPuzzlesProvider.future).timeout(const Duration(seconds: 15));
      } catch (e) {
        debugPrint('reminders: catalogue not ready ($e)');
      }
      notes.addAll(planReminders(
        now: now,
        minutes: minutes,
        puzzles: puzzles,
        profile: _ref.read(profileProvider).value,
        progress: _ref.read(progressProvider).value ?? const {},
      ));
    }
    if (events) {
      try {
        final rows = await _ref.read(eventsProvider.future).timeout(const Duration(seconds: 15));
        final packs = await _ref.read(packRowsProvider.future).timeout(const Duration(seconds: 15));
        notes.addAll(planEventReminders(
          now: now,
          minutes: minutes,
          events: upcomingEvents(rows, packs),
          busyDays: {for (final n in notes) Goals.dayKey(n.at)},
        ));
      } catch (e) {
        debugPrint('reminders: events not ready ($e)');
      }
    }
    await ReminderChannel.schedule([for (final n in notes) n.toJson()]);
  }

  /// Turns reminders on, asking iOS the first time. False when iOS does not
  /// allow notifications (the switch stays off).
  Future<bool> enable() async {
    final granted = await NotificationPermission.ask(from: 'settings_reminders');
    _ref.read(settingsProvider.notifier).setReminders(granted);
    _ref.invalidate(notificationsAllowedProvider);
    if (granted) await refresh();
    return granted;
  }

  /// Settings > Daily reminders off (event notes stay as they are).
  Future<void> disableDaily() async {
    _ref.read(settingsProvider.notifier).setReminders(false);
    await refresh();
  }

  /// Every reminder off, daily reminders and event notes (a deleted account starts over).
  Future<void> disable() async {
    _ref.read(settingsProvider.notifier).setReminders(false);
    _ref.read(eventRemindersProvider.notifier).set(false);
    await ReminderChannel.cancel();
  }

  /// Settings > New events: on asks iOS the first time; false when iOS does not allow
  /// notifications (the switch stays off).
  Future<bool> setEvents(bool on) async {
    if (!on) {
      _ref.read(eventRemindersProvider.notifier).set(false);
      await refresh();
      return true;
    }
    final granted = await NotificationPermission.ask(from: 'settings_events');
    _ref.read(eventRemindersProvider.notifier).set(granted);
    _ref.invalidate(notificationsAllowedProvider);
    if (granted) await refresh();
    return granted;
  }

  /// The notification question's answer: both switches at once, without asking iOS (the question
  /// asks it), then the week planned again.
  Future<void> apply({required bool daily, required bool events}) async {
    _ref.read(settingsProvider.notifier).setReminders(daily);
    _ref.read(eventRemindersProvider.notifier).set(events);
    await refresh();
  }

  Future<void> setTime(int minutes) async {
    _ref.read(settingsProvider.notifier).setReminderMinutes(minutes);
    await refresh();
  }
}

final remindersProvider = Provider<RemindersController>((ref) => RemindersController(ref));
