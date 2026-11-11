import 'agenda.dart';
import 'models.dart';

class Reminder {
  const Reminder({
    required this.id,
    required this.at,
    required this.title,
    required this.body,
    required this.payload,
    this.tone = 'notification',
    this.insistent = false,
    this.speech,
    this.sound,
  });

  /// Prayer reminders that speak: the words to say (made into sound on the phone).
  final String? speech;

  /// Prayer reminders with the user's own sound: the file, relative to the app's documents folder.
  final String? sound;

  /// Sound: 'notification' (the phone's notification sound), 'alarm', 'ringtone' or 'vibrate'; prayer reminders also
  /// 'spoken' / 'voice' (they say [speech]) and 'own' (they play [sound]). Planner reminders keep the default.
  final String tone;

  /// Keep ringing until the notification is opened or swiped away.
  final bool insistent;

  /// Stable 31-bit notification id derived from what is being reminded.
  final int id;
  final DateTime at;
  final String title;
  final String body;

  /// `task:<id>` or `event:<id>` - lets a tap open the right item.
  final String payload;
}

/// All-day items remind at this local time of day (minus their offset).
const allDayReminderHour = 9;

/// Platforms cap pending notifications (iOS: 64), so we schedule only the next [max] reminders and
/// re-plan whenever data changes or the app starts/resumes.
const maxPendingReminders = 60;

int stableId(String key) {
  // FNV-1a, folded to 31 bits (Android notification ids are 32-bit signed ints)
  var h = 0x811c9dc5;
  for (final u in key.codeUnits) {
    h ^= u;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return (h & 0x7fffffff) % reservedNotificationIds; // the top of the range belongs to prayer reminders and tests
}

/// Notification ids from here up are not the planner's (prayer-time reminders, test notifications); the planner
/// never uses or cancels them.
const reservedNotificationIds = 0x7f000000;

/// Prayer-time reminders use ids from here (up to 0x7f00ffff).
const prayerNotificationIds = 0x7f000000;

/// The morning "ayah of the day" notification uses ids from here (up to 0x7f01ffff).
const dailyAyahNotificationIds = 0x7f010000;

/// Sunnah surahs, Jumu'ah, "Did you pray?" and Islamic dates use ids from here (up to 0x7f02ffff).
const islamicNotificationIds = 0x7f020000;

String _two(int v) => v.toString().padLeft(2, '0');
String _clock(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';

String _when(DateTime target, DateTime fireAt, {required bool hasTime}) {
  final today = dateOnly(fireAt), day = dateOnly(target);
  final diff = day.difference(today).inDays;
  final label = diff == 0
      ? 'Today'
      : diff == 1
      ? 'Tomorrow'
      : '${target.year}-${_two(target.month)}-${_two(target.day)}';
  return hasTime ? '$label at ${_clock(target)}' : label;
}

/// The reminders to schedule right now: those still in the future within [horizon], soonest first.
List<Reminder> pickReminders(
  DateTime now,
  List<PlannerTask> tasks,
  List<PlannerEvent> events, {
  Duration horizon = const Duration(days: 60),
  int max = maxPendingReminders,
}) {
  final until = now.add(horizon);
  final out = <Reminder>[];

  void add(
    String kind,
    String id,
    String title,
    DateTime target,
    bool hasTime,
    int offset,
  ) {
    final base = hasTime
        ? target
        : DateTime(target.year, target.month, target.day, allDayReminderHour);
    final at = base.subtract(Duration(minutes: offset));
    if (!at.isAfter(now) || at.isAfter(until)) return;
    out.add(
      Reminder(
        id: stableId('$kind:$id:${target.millisecondsSinceEpoch}'),
        at: at,
        title: title.isEmpty ? 'Reminder' : title,
        body: _when(target, at, hasTime: hasTime),
        payload: '$kind:$id',
      ),
    );
  }

  for (final t in tasks) {
    final offset = t.remindMinutes;
    if (offset == null || t.done) continue;
    // a planned time block wins over the due date as "when it matters"
    final target = t.planned ?? t.due;
    if (target == null) continue;
    final hasTime = t.planned != null || t.dueHasTime;
    add('task', t.id, t.title, target, hasTime, offset);
    // a repeating task keeps reminding at its later occurrences until it is completed (completing advances it)
    final r = t.recurrence;
    if (r != null) {
      for (final o in r.between(target, target, until).skip(1)) {
        add('task', t.id, t.title, o, hasTime, offset);
      }
    }
  }
  for (final e in events) {
    final offset = e.remindMinutes;
    if (offset == null) continue;
    for (final o in eventOccurrences(
      e,
      now.subtract(const Duration(days: 1)),
      until,
    )) {
      add('event', e.id, e.title, o.start, !e.allDay, offset);
    }
  }
  out.sort((a, b) => a.at.compareTo(b.at));
  return out.take(max).toList();
}
