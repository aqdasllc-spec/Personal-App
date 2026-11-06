import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../data/planner_repository.dart';
import '../data/reminder_scheduler.dart';
import '../domain/agenda.dart';
import '../domain/models.dart';
import '../domain/reminders.dart';

final plannerRepositoryProvider = Provider<PlannerRepository>((ref) => PlannerRepository(ref.watch(syncedStoreProvider)));
final reminderSchedulerProvider = Provider<ReminderScheduler>((ref) => NoopReminderScheduler());

enum PlannerMode { day, week, month, year }

class PlannerState {
  const PlannerState({
    required this.day,
    required this.today,
    this.mode = PlannerMode.day,
    this.tasks = const [],
    this.events = const [],
    this.message,
    this.undoLabel,
    this.notificationsDenied = false,
  });

  /// The date being looked at (local, midnight).
  final DateTime day;
  final DateTime today;
  final PlannerMode mode;
  final List<PlannerTask> tasks;
  final List<PlannerEvent> events;

  /// One-shot, user-facing message (validation errors, "moved to next occurrence"...).
  final String? message;

  /// When set the UI offers an Undo action with this label.
  final String? undoLabel;

  /// The user turned notifications off at the OS level, so reminders cannot fire.
  final bool notificationsDenied;

  DayAgenda get agenda => dayAgenda(day, tasks, events, today: today);

  PlannerState copyWith({
    DateTime? day,
    DateTime? today,
    PlannerMode? mode,
    List<PlannerTask>? tasks,
    List<PlannerEvent>? events,
    Value<String?> message = const Value.absent(),
    Value<String?> undoLabel = const Value.absent(),
    bool? notificationsDenied,
  }) =>
      PlannerState(
        day: day ?? this.day,
        today: today ?? this.today,
        mode: mode ?? this.mode,
        tasks: tasks ?? this.tasks,
        events: events ?? this.events,
        message: message.present ? message.value : this.message,
        undoLabel: undoLabel.present ? undoLabel.value : this.undoLabel,
        notificationsDenied: notificationsDenied ?? this.notificationsDenied,
      );
}


class PlannerController extends AsyncNotifier<PlannerState> {
  PlannerController({DateTime Function()? now}) : _now = now ?? DateTime.now;
  final DateTime Function() _now;

  Timer? _debounce;
  bool _disposed = false;
  Future<void> Function()? _undo;
  String _lastReminderSignature = '';

  PlannerRepository get repo => ref.read(plannerRepositoryProvider);
  ReminderScheduler get _scheduler => ref.read(reminderSchedulerProvider);

  @override
  Future<PlannerState> build() async {
    final sub = repo.watchChanges().listen((_) => _scheduleRefresh());
    ref.onDispose(() {
      _disposed = true;
      _debounce?.cancel();
      sub.cancel();
    });
    final today = dateOnly(_now());
    return _load(PlannerState(day: today, today: today));
  }

  void _scheduleRefresh() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 60), () async {
      if (_disposed || state.value == null) return;
      final next = await _load(state.requireValue);
      if (!_disposed) state = AsyncData(next);
    });
  }

  Future<PlannerState> _load(PlannerState cur) async {
    final tasks = await repo.tasks();
    final events = await repo.events();
    // UI state (day, mode, message) is read fresh after the await: the user may have navigated meanwhile
    final ui = state.value ?? cur;
    final next = ui.copyWith(today: dateOnly(_now()), tasks: tasks, events: events);
    unawaited(_replanReminders(tasks, events));
    return next;
  }

  /// Re-reads everything (call when the screen is shown or the app resumes, so "today" rolls over).
  Future<void> refresh() async => state = AsyncData(await _load(state.requireValue));

  PlannerState get _s => state.requireValue;
  void _set(PlannerState s) => state = AsyncData(s);
  void clearMessage() => _set(_s.copyWith(message: const Value(null)));
  void _say(String m) => _set(_s.copyWith(message: Value(m)));
  void _fail(Object e) => _say(e is PlannerValidationException ? e.message : 'Something went wrong. Your data is unchanged.');

  // ----------------------------------------------------------------- navigation
  void setMode(PlannerMode m) => _set(_s.copyWith(mode: m));
  void setDay(DateTime d) => _set(_s.copyWith(day: dateOnly(d)));
  void goToday() => _set(_s.copyWith(day: dateOnly(_now())));

  /// Opens [d] in the day view (from a month/week/year cell).
  void openDay(DateTime d) => _set(_s.copyWith(day: dateOnly(d), mode: PlannerMode.day));

  void shift(int direction) {
    final d = _s.day;
    final next = switch (_s.mode) {
      PlannerMode.day => DateTime(d.year, d.month, d.day + direction),
      PlannerMode.week => DateTime(d.year, d.month, d.day + 7 * direction),
      PlannerMode.month => DateTime(d.year, d.month + direction, 1),
      PlannerMode.year => DateTime(d.year + direction, 1, 1),
    };
    _set(_s.copyWith(day: next));
  }

  // ---------------------------------------------------------------------- undo
  Future<void> undo() async {
    final u = _undo;
    if (u == null) return;
    _undo = null;
    _set(_s.copyWith(undoLabel: const Value(null)));
    try {
      await u();
    } catch (e) {
      _fail(e);
    }
    await refresh();
  }

  /// The UI showed the undo prompt; keep the undo itself available but stop re-announcing it.
  void acknowledgeUndo() => _set(_s.copyWith(undoLabel: const Value(null)));

  void _offerUndo(String label, Future<void> Function() undo) {
    _undo = undo;
    _set(_s.copyWith(undoLabel: Value(label)));
  }

  // ------------------------------------------------------------------- actions
  /// Adds a task for the selected day (date-only). Returns its id, or null (with a message) on failure.
  Future<String?> quickAdd(String title, {DateTime? due}) async {
    try {
      final day = due ?? _s.day;
      final id = await repo.saveTask(TaskInput(title: title, due: dateOnly(day)));
      _offerUndo('Task added', () => repo.deleteTask(id));
      await refresh();
      return id;
    } catch (e) {
      _fail(e);
      return null;
    }
  }

  Future<void> toggleDone(String id) async {
    final t = _s.tasks.where((x) => x.id == id).firstOrNull;
    if (t == null) return;
    try {
      final r = await repo.setTaskDone(id, !t.done, now: _now());
      _offerUndo(r.advanced ? 'Moved to the next occurrence' : (t.done ? 'Reopened' : 'Done'), () => repo.restoreTaskFields(id, r.before));
      await refresh();
    } catch (e) {
      _fail(e);
    }
  }

  Future<bool> saveTask(TaskInput input, {String? id}) async {
    try {
      final before = id == null ? null : TaskInput.of(_s.tasks.firstWhere((t) => t.id == id));
      final saved = await repo.saveTask(input, id: id);
      _offerUndo(id == null ? 'Task added' : 'Task updated', () async {
        if (id == null) {
          await repo.deleteTask(saved);
        } else {
          await repo.saveTask(before!, id: id);
        }
      });
      await refresh();
      _explainReminder('task', saved, input.remindMinutes);
      await _maybeAskForNotifications(input.remindMinutes != null);
      return true;
    } catch (e) {
      _fail(e);
      return false;
    }
  }

  Future<bool> saveEvent(EventInput input, {String? id}) async {
    try {
      final before = id == null ? null : EventInput.of(_s.events.firstWhere((e) => e.id == id));
      final saved = await repo.saveEvent(input, id: id);
      _offerUndo(id == null ? 'Event added' : 'Event updated', () async {
        if (id == null) {
          await repo.deleteEvent(saved);
        } else {
          await repo.saveEvent(before!, id: id);
        }
      });
      await refresh();
      _explainReminder('event', saved, input.remindMinutes);
      await _maybeAskForNotifications(input.remindMinutes != null);
      return true;
    } catch (e) {
      _fail(e);
      return false;
    }
  }

  Future<void> deleteTask(String id) async {
    await repo.deleteTask(id);
    _offerUndo('Task deleted', () => repo.restoreTask(id));
    await refresh();
  }

  Future<void> deleteEvent(String id) async {
    await repo.deleteEvent(id);
    _offerUndo('Event deleted', () => repo.restoreEvent(id));
    await refresh();
  }

  // ----------------------------------------------------------------- reminders
  /// A reminder that can never fire is the commonest reason "nothing came", so say so at save time.
  void _explainReminder(String kind, String id, int? remind) {
    if (remind == null) return;
    final now = _now();
    final picked = pickReminders(now, _s.tasks, _s.events);
    if (picked.any((r) => r.payload == '$kind:$id')) return;
    DateTime? base;
    if (kind == 'task') {
      final t = _s.tasks.where((x) => x.id == id).firstOrNull;
      final target = t?.planned ?? t?.due;
      if (t != null && target != null) base = (t.planned != null || t.dueHasTime) ? target : DateTime(target.year, target.month, target.day, allDayReminderHour);
    } else {
      final e = _s.events.where((x) => x.id == id).firstOrNull;
      if (e != null) base = e.allDay ? DateTime(e.start.year, e.start.month, e.start.day, allDayReminderHour) : e.start;
    }
    if (base == null) return;
    final fire = base.subtract(Duration(minutes: remind));
    if (!fire.isAfter(now)) {
      _say('That reminder time has already passed (${fire.year}-${fire.month.toString().padLeft(2, '0')}-${fire.day.toString().padLeft(2, '0')} ${fire.hour.toString().padLeft(2, '0')}:${fire.minute.toString().padLeft(2, '0')}), so it won\'t fire. Items without a time remind you at 09:00 — give it a time, or pick a later one.');
    } else {
      _say('Saved. This reminder is more than 60 days away; it will be scheduled automatically as the date gets closer.');
    }
  }

  Future<void> _maybeAskForNotifications(bool wanted) async {
    if (!wanted) return;
    final ok = await _scheduler.hasPermission() || await _scheduler.requestPermission();
    _set(_s.copyWith(notificationsDenied: !ok, message: ok ? const Value.absent() : const Value('Reminders are saved, but notifications are turned off for Folio, so they can\'t appear. Allow them in the system settings.')));
    if (ok) await _replanReminders(_s.tasks, _s.events, force: true);
  }

  Future<void> _replanReminders(List<PlannerTask> tasks, List<PlannerEvent> events, {bool force = false}) async {
    try {
      if (!await _scheduler.hasPermission()) return;
      final picked = pickReminders(_now(), tasks, events);
      final signature = picked.map((r) => '${r.id}@${r.at.millisecondsSinceEpoch}:${r.title}:${r.body}').join('|');
      if (!force && signature == _lastReminderSignature) return; // nothing changed since the last plan
      await _scheduler.replaceAll(picked);
      _lastReminderSignature = signature;
    } catch (_) {
      // a failing notification plugin must never break the planner
    }
  }
}

final plannerControllerProvider = AsyncNotifierProvider<PlannerController, PlannerState>(PlannerController.new);

/// Reminders that will fire next (for Settings → Notifications).
final upcomingRemindersProvider = FutureProvider.autoDispose<List<Reminder>>((ref) async {
  final repo = ref.watch(plannerRepositoryProvider);
  return pickReminders(DateTime.now(), await repo.tasks(), await repo.events());
});

final reminderDiagnosticsProvider = FutureProvider.autoDispose<ReminderDiagnostics>((ref) => ref.watch(reminderSchedulerProvider).diagnostics());
