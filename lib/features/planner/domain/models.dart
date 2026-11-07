import 'dart:convert';

import '../../../data/local/app_database.dart';
import 'recurrence.dart';

enum Priority {
  none,
  low,
  medium,
  high;

  static Priority parse(String s) => Priority.values.firstWhere(
    (p) => p.name == s,
    orElse: () => Priority.none,
  );
  String get label => switch (this) {
    Priority.none => 'None',
    Priority.low => 'Low',
    Priority.medium => 'Medium',
    Priority.high => 'High',
  };
}

/// One sub-task of a task.
class ChecklistItem {
  const ChecklistItem({
    required this.id,
    required this.title,
    this.done = false,
  });
  final String id;
  final String title;
  final bool done;

  ChecklistItem copyWith({String? title, bool? done}) => ChecklistItem(
    id: id,
    title: title ?? this.title,
    done: done ?? this.done,
  );

  Map<String, Object?> toJson() => {'id': id, 'title': title, 'done': done};

  @override
  bool operator ==(Object other) =>
      other is ChecklistItem &&
      other.id == id &&
      other.title == title &&
      other.done == done;
  @override
  int get hashCode => Object.hash(id, title, done);
}

const maxChecklistItems = 100;
const maxChecklistTitle = 200;

/// Canonical JSON (stable key order) so that equal lists compare equal as strings.
String encodeChecklist(List<ChecklistItem> items) =>
    jsonEncode([for (final i in items) i.toJson()]);

/// Tolerant: anything unreadable becomes an empty list rather than breaking the task.
List<ChecklistItem> decodeChecklist(String json) {
  try {
    final out = <ChecklistItem>[];
    for (final e in jsonDecode(json) as List) {
      if (e is! Map) continue;
      final m = e;
      final id = m['id'], title = m['title'];
      if (id is String && title is String) {
        out.add(ChecklistItem(id: id, title: title, done: m['done'] == true));
      }
    }
    return out;
  } catch (_) {
    return const [];
  }
}

DateTime? _local(int? ms) =>
    ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);

class PlannerTask {
  const PlannerTask({
    required this.id,
    required this.title,
    this.notes = '',
    this.priority = Priority.none,
    this.due,
    this.dueHasTime = false,
    this.planned,
    this.plannedMinutes,
    this.doneAt,
    this.rrule = '',
    this.remindMinutes,
    this.checklist = const [],
    this.createdAt,
  });

  final String id;
  final String title;
  final String notes;
  final Priority priority;

  /// Sub-tasks, in order.
  final List<ChecklistItem> checklist;

  /// Due date (local midnight when [dueHasTime] is false).
  final DateTime? due;
  final bool dueHasTime;

  /// Time block start and length.
  final DateTime? planned;
  final int? plannedMinutes;
  final DateTime? doneAt;
  final String rrule;
  final int? remindMinutes;
  final DateTime? createdAt;

  bool get done => doneAt != null;
  Recurrence? get recurrence => Recurrence.parse(rrule);
  bool get repeats => recurrence != null;

  factory PlannerTask.fromRow(TaskRow r) => PlannerTask(
    id: r.id,
    title: r.title,
    notes: r.notes,
    priority: Priority.parse(r.priority),
    due: _local(r.dueAt),
    dueHasTime: r.dueHasTime == 1,
    planned: _local(r.plannedAt),
    plannedMinutes: r.plannedMinutes,
    doneAt: _local(r.doneAt),
    rrule: r.rrule,
    remindMinutes: r.remindMinutes,
    checklist: decodeChecklist(r.checklist),
    createdAt: _local(r.createdAt),
  );
}

class PlannerEvent {
  const PlannerEvent({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
    this.notes = '',
    this.allDay = false,
    this.rrule = '',
    this.remindMinutes,
    this.color = '',
  });

  final String id;
  final String title;
  final String notes;
  final DateTime start;

  /// Exclusive end (for all-day events: local midnight after the last day).
  final DateTime end;
  final bool allDay;
  final String rrule;
  final int? remindMinutes;
  final String color;

  Recurrence? get recurrence => Recurrence.parse(rrule);

  factory PlannerEvent.fromRow(EventRow r) => PlannerEvent(
    id: r.id,
    title: r.title,
    notes: r.notes,
    start: DateTime.fromMillisecondsSinceEpoch(r.startAt),
    end: DateTime.fromMillisecondsSinceEpoch(r.endAt),
    allDay: r.allDay == 1,
    rrule: r.rrule,
    remindMinutes: r.remindMinutes,
    color: r.color,
  );
}
