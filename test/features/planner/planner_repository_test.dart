import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/features/planner/data/planner_repository.dart';
import 'package:folio/features/planner/domain/models.dart';
import 'package:sync_engine/sync_engine.dart';

import 'planner_helpers.dart';

void main() {
  late PEnv e;
  setUp(() async => e = await PEnv.create());
  tearDown(() => e.close());

  Future<PlannerTask> get(String id) async => (await e.repo.tasks()).firstWhere((t) => t.id == id);
  Future<int> outbox() async => (await e.db.select(e.db.syncOutbox).get()).length;

  group('creating and editing tasks', () {
    test('a minimal task stores only its title (everything else is a default)', () async {
      final id = await e.repo.saveTask(const TaskInput(title: '  Buy milk  '));
      final t = await get(id);
      expect((t.title, t.due, t.planned, t.rrule, t.remindMinutes, t.priority, t.done), ('Buy milk', null, null, '', null, Priority.none, false));
      expect(await outbox(), 1);
    });

    test('every field round-trips', () async {
      final id = await e.repo.saveTask(TaskInput(title: 'Report', notes: 'draft + figures', priority: Priority.high, due: d(2026, 11, 20, 17), dueHasTime: true, planned: d(2026, 11, 18, 9), plannedMinutes: 120, rrule: 'FREQ=WEEKLY', remindMinutes: 60));
      final t = await get(id);
      expect((t.notes, t.priority, t.due, t.dueHasTime, t.planned, t.plannedMinutes, t.rrule, t.remindMinutes), ('draft + figures', Priority.high, d(2026, 11, 20, 17), true, d(2026, 11, 18, 9), 120, 'FREQ=WEEKLY', 60));
    });

    test('saving writes ONLY the changed fields (so edits to different fields merge across devices)', () async {
      final id = await e.repo.saveTask(TaskInput(title: 'A', due: d(2026, 11, 20)));
      final before = await outbox();
      await e.repo.saveTask(TaskInput(title: 'A', due: d(2026, 11, 20), priority: Priority.low), id: id);
      expect(await outbox(), before + 1);
      final last = (await (e.db.select(e.db.syncOutbox)..orderBy([(o) => OrderingTerm.desc(o.id)])).get()).first;
      expect(last.field, 'priority');
      await e.repo.saveTask(TaskInput(title: 'A', due: d(2026, 11, 20), priority: Priority.low), id: id);
      expect(await outbox(), before + 1, reason: 'saving without changes is a no-op');
    });

    test('clearing a field clears it', () async {
      final id = await e.repo.saveTask(TaskInput(title: 'A', due: d(2026, 11, 20, 9), dueHasTime: true, remindMinutes: 10));
      await e.repo.saveTask(const TaskInput(title: 'A'), id: id);
      final t = await get(id);
      expect((t.due, t.dueHasTime, t.remindMinutes), (null, false, null));
    });

    test('validation explains the problem in plain language and stores nothing', () async {
      Future<void> bad(TaskInput t, String part) => expectLater(e.repo.saveTask(t), throwsA(isA<PlannerValidationException>().having((x) => x.message, 'message', contains(part))));
      await bad(const TaskInput(title: '   '), 'title');
      await bad(TaskInput(title: 'x' * 301), 'too long');
      await bad(TaskInput(title: 'x', due: d(2026, 11, 6), rrule: 'FREQ=NOPE'), 'repeat rule');
      await bad(const TaskInput(title: 'x', rrule: 'FREQ=DAILY'), 'date to start');
      await bad(const TaskInput(title: 'x', remindMinutes: 10), 'due date or a planned time');
      await bad(TaskInput(title: 'x', due: d(2026, 11, 6), remindMinutes: -1), 'reminder');
      await bad(TaskInput(title: 'x', planned: d(2026, 11, 6, 9), plannedMinutes: 1), 'time block');
      expect(await e.repo.tasks(), isEmpty);
      expect(await outbox(), 0);
    });

    test('delete is soft and restorable', () async {
      final id = await e.repo.saveTask(const TaskInput(title: 'A'));
      await e.repo.deleteTask(id);
      expect(await e.repo.tasks(), isEmpty);
      await e.repo.restoreTask(id);
      expect((await e.repo.tasks()).single.id, id);
    });
  });

  group('completing tasks', () {
    test('a normal task is closed and can be reopened; the result carries undo values', () async {
      final id = await e.repo.saveTask(TaskInput(title: 'A', due: d(2026, 11, 6)));
      final r = await e.repo.setTaskDone(id, true);
      expect(r.advanced, isFalse);
      expect((await get(id)).done, isTrue);
      await e.repo.setTaskDone(id, false);
      expect((await get(id)).done, isFalse);
    });

    test('a repeating task ADVANCES to its next occurrence instead of closing', () async {
      final id = await e.repo.saveTask(TaskInput(title: 'Water plants', due: d(2026, 11, 6), rrule: 'FREQ=DAILY'));
      final r = await e.repo.setTaskDone(id, true, now: d(2026, 11, 6, 10));
      expect(r.advanced, isTrue);
      final t = await get(id);
      expect(t.done, isFalse);
      expect(t.due, d(2026, 11, 7));
    });

    test('completing an OVERDUE repeating task jumps to the next occurrence after today, not the next missed one', () async {
      final id = await e.repo.saveTask(TaskInput(title: 'Gym', due: d(2026, 10, 26, 18), dueHasTime: true, rrule: 'FREQ=WEEKLY;BYDAY=MO,TH'));
      await e.repo.setTaskDone(id, true, now: d(2026, 11, 6, 10)); // Friday
      expect((await get(id)).due, d(2026, 11, 9, 18), reason: 'next Monday, keeping 18:00');
    });

    test('the planned time block moves with the due date', () async {
      final id = await e.repo.saveTask(TaskInput(title: 'Review', due: d(2026, 11, 6), planned: d(2026, 11, 5, 14), plannedMinutes: 60, rrule: 'FREQ=WEEKLY'));
      await e.repo.setTaskDone(id, true, now: d(2026, 11, 6, 9));
      final t = await get(id);
      expect((t.due, t.planned), (d(2026, 11, 13), d(2026, 11, 12, 14)));
    });

    test('a repeating task anchored only on a planned time advances that', () async {
      final id = await e.repo.saveTask(TaskInput(title: 'Stretch', planned: d(2026, 11, 6, 7), plannedMinutes: 10, rrule: 'FREQ=DAILY'));
      await e.repo.setTaskDone(id, true, now: d(2026, 11, 6, 7, 30));
      expect((await get(id)).planned, d(2026, 11, 7, 7));
    });

    test('when the rule has ended the final occurrence is simply closed', () async {
      final id = await e.repo.saveTask(TaskInput(title: 'Course', due: d(2026, 11, 6), rrule: 'FREQ=DAILY;COUNT=1'));
      final r = await e.repo.setTaskDone(id, true, now: d(2026, 11, 6, 9));
      expect(r.advanced, isFalse);
      expect((await get(id)).done, isTrue);
    });

    test('undo values restore the previous state after an advance', () async {
      final id = await e.repo.saveTask(TaskInput(title: 'Daily', due: d(2026, 11, 6), rrule: 'FREQ=DAILY'));
      final r = await e.repo.setTaskDone(id, true, now: d(2026, 11, 6, 9));
      await e.repo.restoreTaskFields(id, r.before);
      final t = await get(id);
      expect((t.due, t.done), (d(2026, 11, 6), false));
    });
  });

  group('events', () {
    test('create, edit only what changed, delete', () async {
      final id = await e.repo.saveEvent(EventInput(title: 'Dentist', start: d(2026, 11, 10, 14), end: d(2026, 11, 10, 15), remindMinutes: 60));
      var ev = (await e.repo.events()).single;
      expect((ev.title, ev.start, ev.end, ev.allDay, ev.remindMinutes), ('Dentist', d(2026, 11, 10, 14), d(2026, 11, 10, 15), false, 60));
      final before = await outbox();
      await e.repo.saveEvent(EventInput(title: 'Dentist', start: d(2026, 11, 10, 14), end: d(2026, 11, 10, 15, 30), remindMinutes: 60), id: id);
      expect(await outbox(), before + 1);
      ev = (await e.repo.events()).single;
      expect(ev.end, d(2026, 11, 10, 15, 30));
      await e.repo.deleteEvent(id);
      expect(await e.repo.events(), isEmpty);
    });

    test('all-day and repeating events round-trip', () async {
      await e.repo.saveEvent(EventInput(title: 'Holiday', start: d(2026, 12, 24), end: d(2026, 12, 27), allDay: true, rrule: 'FREQ=YEARLY'));
      final ev = (await e.repo.events()).single;
      expect((ev.allDay, ev.rrule, ev.end), (true, 'FREQ=YEARLY', d(2026, 12, 27)));
    });

    test('validation: must end after it starts, sane length, valid rule', () async {
      Future<void> bad(EventInput x, String part) => expectLater(e.repo.saveEvent(x), throwsA(isA<PlannerValidationException>().having((v) => v.message, 'message', contains(part))));
      await bad(EventInput(title: 'x', start: d(2026, 11, 6, 10), end: d(2026, 11, 6, 10)), 'end after');
      await bad(EventInput(title: 'x', start: d(2026, 11, 6), end: d(2026, 11, 6), allDay: true), 'one day');
      await bad(EventInput(title: 'x', start: d(2026, 11, 6), end: d(2028, 1, 1), allDay: true), 'at most a year');
      await bad(EventInput(title: '', start: d(2026, 11, 6, 9), end: d(2026, 11, 6, 10)), 'title');
      await bad(EventInput(title: 'x', start: d(2026, 11, 6, 9), end: d(2026, 11, 6, 10), rrule: 'nonsense'), 'repeat rule');
      expect(await e.repo.events(), isEmpty);
    });
  });

  group('two devices', () {
    test('tasks and events replicate; edits to DIFFERENT fields of one task merge without conflict', () async {
      final server = FakeServer();
      final a = await PEnv.create(server: server, device: 'devA');
      final b = await PEnv.create(server: server, device: 'devB');
      addTearDown(a.close);
      addTearDown(b.close);
      final id = await a.repo.saveTask(TaskInput(title: 'Taxes', due: d(2026, 11, 30)));
      await a.repo.saveEvent(EventInput(title: 'Meet', start: d(2026, 11, 9, 9), end: d(2026, 11, 9, 10)));
      await a.sync.sync();
      await b.sync.sync();
      expect((await b.repo.tasks()).single.title, 'Taxes');
      expect((await b.repo.events()).single.title, 'Meet');

      await a.repo.saveTask(TaskInput(title: 'Taxes', due: d(2026, 11, 30), priority: Priority.high), id: id);
      await b.repo.saveTask(TaskInput(title: 'Taxes', due: d(2026, 11, 30), remindMinutes: 1440), id: id);
      for (final x in [a, b, a, b]) {
        await x.sync.sync();
      }
      for (final x in [a, b]) {
        final t = (await x.repo.tasks()).single;
        expect((t.priority, t.remindMinutes), (Priority.high, 1440));
      }
      expect(server.conflicts, isEmpty);
    });

    test('completing on one device and renaming on another both survive', () async {
      final server = FakeServer();
      final a = await PEnv.create(server: server, device: 'devA');
      final b = await PEnv.create(server: server, device: 'devB');
      addTearDown(a.close);
      addTearDown(b.close);
      final id = await a.repo.saveTask(const TaskInput(title: 'Draft'));
      await a.sync.sync();
      await b.sync.sync();
      await a.repo.setTaskDone(id, true);
      await b.repo.saveTask(const TaskInput(title: 'Final draft'), id: id);
      for (final x in [a, b, a, b]) {
        await x.sync.sync();
      }
      for (final x in [a, b]) {
        final t = (await x.repo.tasks()).single;
        expect((t.title, t.done), ('Final draft', true));
      }
    });

    test('the same field edited on both devices: the later edit wins and the other is kept in the conflict log', () async {
      final server = FakeServer();
      final a = await PEnv.create(server: server, device: 'devA');
      final b = await PEnv.create(server: server, device: 'devB');
      addTearDown(a.close);
      addTearDown(b.close);
      final id = await a.repo.saveTask(TaskInput(title: 'Call', due: d(2026, 11, 10)));
      await a.sync.sync();
      await b.sync.sync();
      await a.repo.saveTask(TaskInput(title: 'Call', due: d(2026, 11, 11)), id: id);
      await b.repo.saveTask(TaskInput(title: 'Call', due: d(2026, 11, 12)), id: id); // later
      for (final x in [a, b, a, b]) {
        await x.sync.sync();
      }
      expect((await a.repo.tasks()).single.due, d(2026, 11, 12));
      expect((await b.repo.tasks()).single.due, d(2026, 11, 12));
      expect((await a.db.select(a.db.localConflicts).get()).length, 1, reason: 'the overwritten date (11th) is preserved for review');
    });

    test('a task deleted on one device disappears on the other and can be restored', () async {
      final server = FakeServer();
      final a = await PEnv.create(server: server, device: 'devA');
      final b = await PEnv.create(server: server, device: 'devB');
      addTearDown(a.close);
      addTearDown(b.close);
      final id = await a.repo.saveTask(const TaskInput(title: 'Old'));
      await a.sync.sync();
      await b.sync.sync();
      await a.repo.deleteTask(id);
      await a.sync.sync();
      await b.sync.sync();
      expect(await b.repo.tasks(), isEmpty);
      await b.repo.restoreTask(id);
      await b.sync.sync();
      await a.sync.sync();
      expect(await a.repo.tasks(), hasLength(1));
    });
  });

  group('sub-tasks (checklist)', () {
    ChecklistItem item(String id, String title, {bool done = false}) => ChecklistItem(id: id, title: title, done: done);

    test('a task with no sub-tasks writes nothing extra; sub-tasks round-trip with order, ticks and blanks dropped', () async {
      final plain = await e.repo.saveTask(const TaskInput(title: 'Plain'));
      expect((await get(plain)).checklist, isEmpty);
      final fields = (await e.db.select(e.db.syncOutbox).get()).where((o) => o.rowId == plain).map((o) => o.field);
      expect(fields, isNot(contains('checklist')), reason: 'the default [] is the column default');

      final id = await e.repo.saveTask(TaskInput(title: 'Trip', checklist: [item('a', 'Passport'), item('b', '   '), item('c', ' Tickets ', done: true)]));
      final t = await get(id);
      expect(t.checklist, [item('a', 'Passport'), item('c', 'Tickets', done: true)]);
    });

    test('ticking one sub-task writes only the checklist field, and is a no-op when already in that state', () async {
      final id = await e.repo.saveTask(TaskInput(title: 'Trip', checklist: [item('a', 'Passport'), item('c', 'Tickets')]));
      final before = await outbox();
      await e.repo.setChecklistItemDone(id, 'a', true);
      expect((await get(id)).checklist.map((c) => c.done), [true, false]);
      final fresh = (await e.db.select(e.db.syncOutbox).get()).skip(before).toList();
      expect(fresh.map((o) => o.field), ['checklist']);
      await e.repo.setChecklistItemDone(id, 'a', true);
      await e.repo.setChecklistItemDone(id, 'missing', true);
      expect(await outbox(), before + 1);
    });

    test('editing a task changes the checklist field only when the sub-tasks changed', () async {
      final id = await e.repo.saveTask(TaskInput(title: 'Trip', checklist: [item('a', 'Passport')]));
      final base = await outbox();
      await e.repo.saveTask(TaskInput(title: 'Trip 2', checklist: [item('a', 'Passport')]), id: id);
      expect((await e.db.select(e.db.syncOutbox).get()).skip(base).map((o) => o.field), ['title']);
      await e.repo.saveTask(TaskInput(title: 'Trip 2', checklist: [item('a', 'Passport'), item('b', 'Visa')]), id: id);
      expect((await get(id)).checklist.length, 2);
    });

    test('limits: at most 100 sub-tasks and 200 characters each', () async {
      await expectLater(e.repo.saveTask(TaskInput(title: 'x', checklist: [for (var i = 0; i < 101; i++) item('$i', 'n$i')])), throwsA(isA<PlannerValidationException>()));
      await expectLater(e.repo.saveTask(TaskInput(title: 'x', checklist: [item('a', 'y' * 201)])), throwsA(isA<PlannerValidationException>()));
    });

    test('completing a REPEATING task starts the next occurrence with every sub-task unticked; undo restores the ticks', () async {
      final id = await e.repo.saveTask(TaskInput(title: 'Weekly review', due: d(2026, 11, 9), rrule: 'FREQ=WEEKLY', checklist: [item('a', 'Inbox', done: true), item('b', 'Plan', done: true)]));
      final r = await e.repo.setTaskDone(id, true, now: d(2026, 11, 9, 10));
      expect(r.advanced, isTrue);
      final t = await get(id);
      expect(t.due, d(2026, 11, 16));
      expect(t.checklist.map((c) => c.done).toList(), [false, false]);
      await e.repo.restoreTaskFields(id, r.before);
      final back = await get(id);
      expect(back.due, d(2026, 11, 9));
      expect(back.checklist.map((c) => c.done).toList(), [true, true]);
    });

    test('two devices: sub-tasks sync, and ticks made offline on the other device arrive', () async {
      final server = FakeServer();
      final a = await PEnv.create(server: server, device: 'devA');
      final b = await PEnv.create(server: server, device: 'devB');
      addTearDown(a.close);
      addTearDown(b.close);
      final id = await a.repo.saveTask(TaskInput(title: 'Trip', checklist: [item('a', 'Passport'), item('b', 'Visa')]));
      await a.sync.sync();
      await b.sync.sync();
      expect((await b.repo.tasks()).single.checklist.map((c) => c.title).toList(), ['Passport', 'Visa']);
      await b.repo.setChecklistItemDone(id, 'b', true);
      await b.sync.sync();
      await a.sync.sync();
      expect((await a.repo.tasks()).single.checklist.map((c) => c.done).toList(), [false, true]);
    });

    test('a one-off task keeps its ticks when completed', () async {
      final id = await e.repo.saveTask(TaskInput(title: 'Once', checklist: [item('a', 'Step', done: true)]));
      await e.repo.setTaskDone(id, true);
      expect((await get(id)).checklist.single.done, isTrue);
    });

    test('decoding is forgiving: garbage or wrong shapes give an empty / partial list, never a crash', () {
      expect(decodeChecklist('nope'), isEmpty);
      expect(decodeChecklist('{"a":1}'), isEmpty);
      expect(decodeChecklist('[{"id":"x","title":"ok","done":true},{"id":1,"title":"bad"},5]'), [item('x', 'ok', done: true)]);
    });
  });
}
