import 'dart:math' as math;

import 'models.dart';

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime addDays(DateTime d, int n) =>
    DateTime(d.year, d.month, d.day + n, d.hour, d.minute);
bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// First day of the week containing [d] (Monday by default).
DateTime startOfWeek(DateTime d, {bool mondayFirst = true}) {
  final back = mondayFirst ? d.weekday - 1 : d.weekday % 7;
  return DateTime(d.year, d.month, d.day - back);
}

enum ItemKind { task, event }

/// One line/block on the planner, whether it came from a task or an event occurrence.
class AgendaItem {
  const AgendaItem({
    required this.kind,
    required this.id,
    required this.title,
    this.start,
    this.end,
    this.allDay = false,
    this.done = false,
    this.priority = Priority.none,
    this.repeats = false,
    this.color = '',
    this.hasTime = false,
    this.checklist = const [],
  });

  final ItemKind kind;

  /// Sub-tasks (tasks only).
  final List<ChecklistItem> checklist;
  int get checkDone => checklist.where((c) => c.done).length;
  final String id;
  final String title;
  final DateTime? start;
  final DateTime? end;
  final bool allDay;
  final bool done;
  final Priority priority;
  final bool repeats;
  final String color;

  /// Whether [start] carries a meaningful time of day (so the UI can print it).
  final bool hasTime;
}

class EventOccurrence {
  const EventOccurrence(this.event, this.start, this.end);
  final PlannerEvent event;
  final DateTime start;
  final DateTime end;
}

/// Occurrences of [e] that overlap [from, to). Repeats keep their wall-clock time and duration.
List<EventOccurrence> eventOccurrences(
  PlannerEvent e,
  DateTime from,
  DateTime to,
) {
  final r = e.recurrence;
  bool overlaps(DateTime s, DateTime en) =>
      s.isBefore(to) && en.isAfter(from) ||
      (s == en && !s.isBefore(from) && s.isBefore(to));
  if (r == null) {
    return overlaps(e.start, e.end)
        ? [EventOccurrence(e, e.start, e.end)]
        : const [];
  }

  final spanDays = e.allDay
      ? DateTime.utc(e.end.year, e.end.month, e.end.day)
            .difference(DateTime.utc(e.start.year, e.start.month, e.start.day))
            .inDays
      : 0;
  final duration = e.end.difference(e.start);
  // starts that could still overlap the range began up to one event-length earlier
  final lookBack = e.allDay
      ? addDays(from, -spanDays)
      : from.subtract(duration);
  final out = <EventOccurrence>[];
  for (final s in r.between(e.start, lookBack, to)) {
    final en = e.allDay
        ? DateTime(s.year, s.month, s.day + spanDays)
        : s.add(duration);
    if (overlaps(s, en)) out.add(EventOccurrence(e, s, en));
  }
  return out;
}

class DayAgenda {
  const DayAgenda({
    required this.day,
    this.allDay = const [],
    this.timed = const [],
    this.tasks = const [],
    this.overdue = const [],
  });
  final DateTime day;

  /// All-day events.
  final List<AgendaItem> allDay;

  /// Timed events and time-blocked tasks (the timeline), start-ordered, clipped to this day.
  final List<AgendaItem> timed;

  /// Tasks due or planned on this day (the checklist).
  final List<AgendaItem> tasks;

  /// Open tasks past their due date (only filled for today).
  final List<AgendaItem> overdue;

  bool get isEmpty =>
      allDay.isEmpty && timed.isEmpty && tasks.isEmpty && overdue.isEmpty;
}

const defaultBlockMinutes = 30;

AgendaItem _taskItem(PlannerTask t, {bool block = false}) {
  final start = block
      ? t.planned
      : (t.dueHasTime ? t.due : (t.planned ?? t.due));
  final end = block && t.planned != null
      ? t.planned!.add(
          Duration(minutes: t.plannedMinutes ?? defaultBlockMinutes),
        )
      : null;
  return AgendaItem(
    kind: ItemKind.task,
    id: t.id,
    title: t.title,
    start: start,
    end: end,
    done: t.done,
    priority: t.priority,
    repeats: t.repeats,
    hasTime: block || t.dueHasTime,
    checklist: t.checklist,
  );
}

int _cmpTasks(AgendaItem a, AgendaItem b) {
  if (a.done != b.done) return a.done ? 1 : -1; // open first
  final ta = a.hasTime ? a.start : null, tb = b.hasTime ? b.start : null;
  if (ta != null && tb != null) {
    final c = ta.compareTo(tb);
    if (c != 0) return c;
  } else if (ta != null) {
    return -1;
  } else if (tb != null) {
    return 1;
  }
  final p = b.priority.index.compareTo(a.priority.index);
  return p != 0 ? p : a.title.toLowerCase().compareTo(b.title.toLowerCase());
}

/// Everything planned for [day]. [today] decides whether overdue tasks are included.
DayAgenda dayAgenda(
  DateTime day,
  List<PlannerTask> tasks,
  List<PlannerEvent> events, {
  required DateTime today,
}) {
  final from = dateOnly(day), to = addDays(from, 1);
  final allDay = <AgendaItem>[];
  final timed = <AgendaItem>[];

  for (final e in events) {
    for (final o in eventOccurrences(e, from, to)) {
      final item = AgendaItem(
        kind: ItemKind.event,
        id: e.id,
        title: e.title,
        start: o.start.isBefore(from) ? from : o.start,
        end: o.end.isAfter(to) ? to : o.end,
        allDay: e.allDay,
        repeats: e.recurrence != null,
        color: e.color,
        hasTime: !e.allDay,
      );
      (e.allDay ? allDay : timed).add(item);
    }
  }

  final list = <AgendaItem>[];
  for (final t in tasks) {
    final plannedToday =
        t.planned != null &&
        !t.planned!.isBefore(from) &&
        t.planned!.isBefore(to);
    final dueToday =
        t.due != null && !t.due!.isBefore(from) && t.due!.isBefore(to);
    if (plannedToday) timed.add(_taskItem(t, block: true));
    if (plannedToday || dueToday) list.add(_taskItem(t));
  }
  list.sort(_cmpTasks);
  allDay.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  timed.sort((a, b) {
    final c = a.start!.compareTo(b.start!);
    return c != 0 ? c : a.end!.compareTo(b.end!);
  });

  final overdue = <AgendaItem>[];
  if (sameDay(day, today)) {
    final startToday = dateOnly(today);
    for (final t in tasks) {
      if (!t.done && t.due != null && t.due!.isBefore(startToday)) {
        overdue.add(_taskItem(t));
      }
    }
    overdue.sort((a, b) => a.start!.compareTo(b.start!));
  }
  return DayAgenda(
    day: from,
    allDay: allDay,
    timed: timed,
    tasks: list,
    overdue: overdue,
  );
}

class DayCount {
  const DayCount({this.events = 0, this.open = 0, this.done = 0});
  final int events, open, done;
  int get total => events + open + done;
  DayCount plus({int events = 0, int open = 0, int done = 0}) => DayCount(
    events: this.events + events,
    open: this.open + open,
    done: this.done + done,
  );
}

/// Item counts per day in [from, to) - drives the month grid and the year overview.
Map<DateTime, DayCount> rangeCounts(
  DateTime from,
  DateTime to,
  List<PlannerTask> tasks,
  List<PlannerEvent> events,
) {
  final out = <DateTime, DayCount>{};
  void bump(DateTime d, {int events = 0, int open = 0, int done = 0}) {
    final k = dateOnly(d);
    if (k.isBefore(from) || !k.isBefore(to)) return;
    out[k] = (out[k] ?? const DayCount()).plus(
      events: events,
      open: open,
      done: done,
    );
  }

  for (final e in events) {
    for (final o in eventOccurrences(e, from, to)) {
      // every day the occurrence touches (end is exclusive, so a midnight end does not spill)
      var d = dateOnly(o.start);
      final last = o.end.isAfter(o.start)
          ? o.end.subtract(const Duration(milliseconds: 1))
          : o.start;
      while (!d.isAfter(last)) {
        bump(d, events: 1);
        d = addDays(d, 1);
      }
    }
  }
  for (final t in tasks) {
    final days = <DateTime>{
      if (t.due != null) dateOnly(t.due!),
      if (t.planned != null) dateOnly(t.planned!),
    };
    for (final d in days) {
      t.done ? bump(d, done: 1) : bump(d, open: 1);
    }
  }
  return out;
}

class PositionedBlock {
  const PositionedBlock(
    this.item,
    this.column,
    this.columns,
    this.startMinute,
    this.endMinute,
  );
  final AgendaItem item;
  final int column, columns;
  final int startMinute, endMinute;
}

const minBlockMinutes = 20;

/// Lays out overlapping blocks side by side: each block gets a column, and every block in a connected
/// overlap cluster shares the cluster's column count so widths line up.
List<PositionedBlock> layoutBlocks(List<AgendaItem> timed, DateTime day) {
  final from = dateOnly(day);
  int minutes(DateTime d) =>
      math.max(0, math.min(1440, d.difference(from).inMinutes));
  final blocks = [
    for (final i in timed)
      if (i.start != null)
        (
          i,
          minutes(i.start!),
          math
              .max(
                minutes(i.end ?? i.start!),
                minutes(i.start!) + minBlockMinutes,
              )
              .clamp(0, 1440),
        ),
  ]..sort((a, b) => a.$2 != b.$2 ? a.$2.compareTo(b.$2) : b.$3.compareTo(a.$3));

  final result = <PositionedBlock>[];
  var cluster = <(AgendaItem, int, int, int)>[];
  var colEnds = <int>[];
  var clusterEnd = -1;

  void flush() {
    for (final c in cluster) {
      result.add(PositionedBlock(c.$1, c.$4, colEnds.length, c.$2, c.$3));
    }
    cluster = [];
    colEnds = [];
  }

  for (final b in blocks) {
    if (cluster.isNotEmpty && b.$2 >= clusterEnd) flush();
    var col = colEnds.indexWhere((end) => end <= b.$2);
    if (col < 0) {
      col = colEnds.length;
      colEnds.add(b.$3);
    } else {
      colEnds[col] = b.$3;
    }
    clusterEnd = cluster.isEmpty ? b.$3 : math.max(clusterEnd, b.$3);
    cluster.add((b.$1, b.$2, b.$3, col));
  }
  flush();
  return result;
}
