import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart';
import '../../../data/sync/synced_store.dart';
import '../domain/models.dart';
import '../domain/recurrence.dart';

class PlannerValidationException implements Exception {
  PlannerValidationException(this.message);
  final String message;
  @override
  String toString() => message;
}

int? _ms(DateTime? d) => d?.millisecondsSinceEpoch;

/// Everything the user can set on a task, as one value. Saving diffs it against what is stored so only
/// changed fields are written (and synced), which lets edits to different fields on two devices merge.
class TaskInput {
  const TaskInput({
    required this.title,
    this.notes = '',
    this.priority = Priority.none,
    this.due,
    this.dueHasTime = false,
    this.planned,
    this.plannedMinutes,
    this.rrule = '',
    this.remindMinutes,
  });
  final String title, notes;
  final Priority priority;
  final DateTime? due;
  final bool dueHasTime;
  final DateTime? planned;
  final int? plannedMinutes;
  final String rrule;
  final int? remindMinutes;

  factory TaskInput.of(PlannerTask t) => TaskInput(
    title: t.title,
    notes: t.notes,
    priority: t.priority,
    due: t.due,
    dueHasTime: t.dueHasTime,
    planned: t.planned,
    plannedMinutes: t.plannedMinutes,
    rrule: t.rrule,
    remindMinutes: t.remindMinutes,
  );

  Map<String, Object?> toFields() => {
    'title': title.trim(),
    'notes': notes,
    'priority': priority == Priority.none ? '' : priority.name,
    'due_at': _ms(due),
    'due_has_time': dueHasTime && due != null ? 1 : 0,
    'planned_at': _ms(planned),
    'planned_minutes': planned == null ? null : plannedMinutes,
    'rrule': rrule,
    'remind_minutes': remindMinutes,
  };
}

class EventInput {
  const EventInput({
    required this.title,
    required this.start,
    required this.end,
    this.notes = '',
    this.allDay = false,
    this.rrule = '',
    this.remindMinutes,
    this.color = '',
  });
  final String title, notes;
  final DateTime start, end;
  final bool allDay;
  final String rrule;
  final int? remindMinutes;
  final String color;

  factory EventInput.of(PlannerEvent e) => EventInput(
    title: e.title,
    notes: e.notes,
    start: e.start,
    end: e.end,
    allDay: e.allDay,
    rrule: e.rrule,
    remindMinutes: e.remindMinutes,
    color: e.color,
  );

  Map<String, Object?> toFields() => {
    'title': title.trim(),
    'notes': notes,
    'start_at': start.millisecondsSinceEpoch,
    'end_at': end.millisecondsSinceEpoch,
    'all_day': allDay ? 1 : 0,
    'rrule': rrule,
    'remind_minutes': remindMinutes,
    'color': color,
  };
}

class CompletionResult {
  const CompletionResult({required this.advanced, required this.before});

  /// true when a repeating task moved to its next occurrence instead of being closed.
  final bool advanced;

  /// Field values before the change, for undo.
  final Map<String, Object?> before;
}

/// The only write path for planner data (tasks and events). Every write goes through [SyncedStore].
class PlannerRepository {
  PlannerRepository(this.store);
  final SyncedStore store;
  AppDatabase get db => store.db;

  /// Emits whenever a task or event changes (local edit or sync).
  Stream<void> watchChanges() => db
      .tableUpdates(TableUpdateQuery.onAllTables([db.tasks, db.events]))
      .map((_) {});

  Future<List<PlannerTask>> tasks() async => [
    for (final r in await (db.select(
      db.tasks,
    )..where((t) => t.deletedAt.isNull())).get())
      PlannerTask.fromRow(r),
  ];
  Future<List<PlannerEvent>> events() async => [
    for (final r in await (db.select(
      db.events,
    )..where((e) => e.deletedAt.isNull())).get())
      PlannerEvent.fromRow(r),
  ];

  // ------------------------------------------------------------------ validation
  void _validateCommon(String title, String rrule, int? remind) {
    if (title.trim().isEmpty) {
      throw PlannerValidationException('Give it a title.');
    }
    if (title.length > 300) {
      throw PlannerValidationException(
        'That title is too long (300 characters at most).',
      );
    }
    if (rrule.isNotEmpty && Recurrence.parse(rrule) == null) {
      throw PlannerValidationException('That repeat rule isn\'t valid.');
    }
    if (remind != null && (remind < 0 || remind > 60 * 24 * 30)) {
      throw PlannerValidationException('Choose a reminder within 30 days.');
    }
  }

  void _validateTask(TaskInput t) {
    _validateCommon(t.title, t.rrule, t.remindMinutes);
    if (t.notes.length > 20000) {
      throw PlannerValidationException('The notes are too long.');
    }
    if (t.plannedMinutes != null &&
        (t.plannedMinutes! < 5 || t.plannedMinutes! > 24 * 60)) {
      throw PlannerValidationException(
        'A time block must be between 5 minutes and 24 hours.',
      );
    }
    if (t.rrule.isNotEmpty && t.due == null && t.planned == null) {
      throw PlannerValidationException(
        'Give a repeating task a date to start from.',
      );
    }
    if (t.remindMinutes != null && t.due == null && t.planned == null) {
      throw PlannerValidationException(
        'A reminder needs a due date or a planned time.',
      );
    }
  }

  void _validateEvent(EventInput e) {
    _validateCommon(e.title, e.rrule, e.remindMinutes);
    if (!e.end.isAfter(e.start)) {
      throw PlannerValidationException(
        e.allDay
            ? 'An event lasts at least one day.'
            : 'The event must end after it starts.',
      );
    }
    if (e.end.difference(e.start).inDays > 366) {
      throw PlannerValidationException('An event can last at most a year.');
    }
  }

  // ----------------------------------------------------------------------- tasks
  /// Creates the task (when [id] is null) or saves only the fields that changed.
  Future<String> saveTask(TaskInput input, {String? id}) async {
    _validateTask(input);
    final fields = input.toFields();
    if (id == null) {
      final newId = store.newId();
      // an empty/default value is the column default, so only non-defaults need writing
      await store.setFields('tasks', newId, {
        'title': fields['title'],
        for (final e in fields.entries)
          if (e.key != 'title' && _isSet(e.key, e.value)) e.key: e.value,
      });
      return newId;
    }
    final row = await (db.select(
      db.tasks,
    )..where((t) => t.id.equals(id))).getSingle();
    final current = TaskInput.of(PlannerTask.fromRow(row)).toFields();
    final changed = {
      for (final e in fields.entries)
        if ('${current[e.key]}' != '${e.value}') e.key: e.value,
    };
    if (changed.isNotEmpty) await store.setFields('tasks', id, changed);
    return id;
  }

  /// Whether [v] differs from the column default and so must be written on creation. Nullable columns
  /// default to NULL, so for them 0 is a real value (e.g. a reminder "at the time" = 0 minutes).
  bool _isSet(String field, Object? v) =>
      const {
        'due_at',
        'planned_at',
        'planned_minutes',
        'remind_minutes',
        'start_at',
        'end_at',
      }.contains(field)
      ? v != null
      : (v != null && v != '' && v != 0);

  /// Marks a task done / not done. A repeating task with a next occurrence ADVANCES instead of closing.
  Future<CompletionResult> setTaskDone(
    String id,
    bool done, {
    DateTime? now,
  }) async {
    final row = await (db.select(
      db.tasks,
    )..where((t) => t.id.equals(id))).getSingle();
    final t = PlannerTask.fromRow(row);
    final before = <String, Object?>{
      'done_at': row.doneAt,
      'due_at': row.dueAt,
      'planned_at': row.plannedAt,
    };
    if (!done) {
      await store.setFields('tasks', id, {'done_at': null});
      return CompletionResult(advanced: false, before: before);
    }
    final r = t.recurrence;
    final anchor = t.due ?? t.planned;
    if (r != null && anchor != null) {
      final at = now ?? DateTime.fromMillisecondsSinceEpoch(store.nowMs);
      final next = r.nextAfter(anchor, at.isAfter(anchor) ? at : anchor);
      if (next != null) {
        final delta = next.difference(anchor);
        await store.setFields('tasks', id, {
          if (t.due != null) 'due_at': next.millisecondsSinceEpoch,
          if (t.due == null && t.planned != null)
            'planned_at': next.millisecondsSinceEpoch,
          if (t.due != null && t.planned != null)
            'planned_at': t.planned!.add(delta).millisecondsSinceEpoch,
        });
        return CompletionResult(advanced: true, before: before);
      }
    }
    await store.setFields('tasks', id, {'done_at': store.nowMs});
    return CompletionResult(advanced: false, before: before);
  }

  /// Restores raw column values (used by undo).
  Future<void> restoreTaskFields(String id, Map<String, Object?> fields) =>
      store.setFields('tasks', id, fields);

  Future<void> deleteTask(String id) =>
      store.setFields('tasks', id, {'deleted_at': store.nowMs});
  Future<void> restoreTask(String id) =>
      store.setFields('tasks', id, {'deleted_at': null});

  // ---------------------------------------------------------------------- events
  Future<String> saveEvent(EventInput input, {String? id}) async {
    _validateEvent(input);
    final fields = input.toFields();
    if (id == null) {
      final newId = store.newId();
      await store.setFields('events', newId, {
        'title': fields['title'],
        'start_at': fields['start_at'],
        'end_at': fields['end_at'],
        for (final e in fields.entries)
          if (!const {'title', 'start_at', 'end_at'}.contains(e.key) &&
              _isSet(e.key, e.value))
            e.key: e.value,
      });
      return newId;
    }
    final row = await (db.select(
      db.events,
    )..where((e) => e.id.equals(id))).getSingle();
    final current = EventInput.of(PlannerEvent.fromRow(row)).toFields();
    final changed = {
      for (final e in fields.entries)
        if ('${current[e.key]}' != '${e.value}') e.key: e.value,
    };
    if (changed.isNotEmpty) await store.setFields('events', id, changed);
    return id;
  }

  Future<void> deleteEvent(String id) =>
      store.setFields('events', id, {'deleted_at': store.nowMs});
  Future<void> restoreEvent(String id) =>
      store.setFields('events', id, {'deleted_at': null});
}
