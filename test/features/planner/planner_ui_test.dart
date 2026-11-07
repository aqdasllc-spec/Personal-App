import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/app/app.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/features/planner/application/planner_controller.dart';
import 'package:folio/features/planner/data/planner_repository.dart';
import 'package:folio/features/planner/data/reminder_scheduler.dart';
import 'package:folio/features/planner/domain/models.dart';
import 'package:folio/features/planner/domain/reminders.dart';

import '../../helpers.dart';

/// Friday 6 Nov 2026, 12:00 - every test runs "today" on this date.
final fixedNow = DateTime(2026, 11, 6, 12);
DateTime d(int y, int m, int day, [int h = 0, int mi = 0]) => DateTime(y, m, day, h, mi);

class FakeScheduler implements ReminderScheduler {
  FakeScheduler({this.granted = true});
  bool granted;
  int requests = 0;
  List<Reminder> last = const [];
  int replaceCalls = 0;
  @override
  Future<bool> hasPermission() async => granted;
  @override
  Future<bool> requestPermission() async {
    requests++;
    return granted;
  }

  @override
  Future<void> replaceAll(List<Reminder> reminders) async {
    replaceCalls++;
    last = reminders;
  }

  int testNow = 0;
  int testLater = 0;
  @override
  Future<ReminderDiagnostics> diagnostics() async => ReminderDiagnostics(
      supported: true,
      permissionGranted: granted,
      exactAlarms: true,
      pendingCount: last.length,
      lastMode: 'exact');
  @override
  Future<bool> sendTestNow() async {
    testNow++;
    return true;
  }

  @override
  Future<bool> scheduleTest(Duration after) async {
    testLater++;
    return true;
  }
}

void _size(WidgetTester t, double w, double h) {
  t.view.physicalSize = Size(w, h);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

Future<void> settleP(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 80));
  }
  await t.pumpAndSettle();
}

Future<void> dispose(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 1));
}

typedef Seed = Future<void> Function(PlannerRepository repo);

/// Opens the real app on the Planner tab with "now" fixed.
Future<(TestEnv, FakeScheduler)> openPlanner(WidgetTester t, {Seed? seed, double w = 411, double h = 890, bool granted = true}) async {
  _size(t, w, h);
  final env = await TestEnv.create();
  addTearDown(env.db.close);
  final scheduler = FakeScheduler(granted: granted);
  if (seed != null) await t.runAsync(() => seed(PlannerRepository(env.store)));
  await t.pumpWidget(ProviderScope(
    overrides: [
      ...env.overrides,
      reminderSchedulerProvider.overrideWithValue(scheduler),
      plannerControllerProvider.overrideWith(() => PlannerController(now: () => fixedNow)),
    ],
    child: const FolioApp(),
  ));
  await t.pumpAndSettle();
  if (w < 600) {
    await t.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Planner')));
  } else if (w < 900) {
    await t.tap(find.byTooltip('Planner'));
  } else {
    await t.tap(find.text('Planner'));
  }
  await settleP(t);
  return (env, scheduler);
}

/// The editor page's own scrolling list (the planner page underneath has others).
Finder editorScroll() => find.descendant(of: find.byType(Scaffold).last, matching: find.byType(Scrollable)).first;

Future<List<TaskRow>> dbTasks(WidgetTester t, TestEnv env) async => (await t.runAsync(() => env.db.select(env.db.tasks).get()))!;

void main() {
  group('day view', () {
    testWidgets('an empty planner invites you to plan; quick add creates a task due that day', (t) async {
      final (env, _) = await openPlanner(t);
      expect(find.text('Plan your day'), findsOneWidget);
      expect(find.text('Friday 6 November'), findsOneWidget);
      await t.enterText(find.byKey(const Key('planner-quick-add')), 'Buy milk');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await settleP(t);
      expect(find.text('Buy milk'), findsOneWidget);
      expect(find.text('Plan your day'), findsNothing);
      final rows = await dbTasks(t, env);
      expect(rows.single.title, 'Buy milk');
      expect(DateTime.fromMillisecondsSinceEpoch(rows.single.dueAt!), d(2026, 11, 6), reason: 'date-only, local midnight of the selected day');
      expect(find.text('Task added'), findsOneWidget, reason: 'undo prompt');
      await dispose(t);
    });

    testWidgets('quick add on another day files the task under that day; blank input is ignored', (t) async {
      final (env, _) = await openPlanner(t);
      await t.tap(find.byKey(const Key('planner-next')));
      await settleP(t);
      expect(find.text('Saturday 7 November'), findsOneWidget);
      await t.enterText(find.byKey(const Key('planner-quick-add')), '   ');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await settleP(t);
      expect(await dbTasks(t, env), isEmpty);
      await t.enterText(find.byKey(const Key('planner-quick-add')), 'Laundry');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await settleP(t);
      expect(DateTime.fromMillisecondsSinceEpoch((await dbTasks(t, env)).single.dueAt!), d(2026, 11, 7));
      await t.tap(find.byKey(const Key('planner-today')));
      await settleP(t);
      expect(find.text('Laundry'), findsNothing, reason: 'it belongs to tomorrow');
      await dispose(t);
    });

    testWidgets('completing a task strikes it through; Undo reopens it', (t) async {
      final (env, _) = await openPlanner(t, seed: (r) async => r.saveTask(TaskInput(title: 'Pay rent', due: d(2026, 11, 6))).then((_) {}));
      final id = (await dbTasks(t, env)).single.id;
      await t.tap(find.byKey(Key('done-$id')));
      await settleP(t);
      expect((await dbTasks(t, env)).single.doneAt, isNotNull);
      expect(find.text('Done'), findsOneWidget);
      await t.tap(find.text('Undo'));
      await settleP(t);
      expect((await dbTasks(t, env)).single.doneAt, isNull);
      await dispose(t);
    });

    testWidgets('a repeating task moves to its next occurrence when completed and says so', (t) async {
      final (env, _) = await openPlanner(t, seed: (r) async => r.saveTask(TaskInput(title: 'Water plants', due: d(2026, 11, 6), rrule: 'FREQ=DAILY')).then((_) {}));
      final id = (await dbTasks(t, env)).single.id;
      expect(find.byIcon(Icons.repeat), findsOneWidget);
      await t.tap(find.byKey(Key('done-$id')));
      await settleP(t);
      expect(find.text('Moved to the next occurrence'), findsOneWidget);
      expect(find.text('Water plants'), findsNothing, reason: 'no longer due today');
      expect(DateTime.fromMillisecondsSinceEpoch((await dbTasks(t, env)).single.dueAt!), d(2026, 11, 7));
      await t.tap(find.byKey(const Key('planner-next')));
      await settleP(t);
      expect(find.text('Water plants'), findsOneWidget);
      await dispose(t);
    });

    testWidgets('overdue tasks are called out on today only', (t) async {
      await openPlanner(t, seed: (r) async => r.saveTask(TaskInput(title: 'Renew passport', due: d(2026, 11, 3))).then((_) {}));
      expect(find.text('Overdue · 1'), findsOneWidget);
      expect(find.text('Renew passport'), findsOneWidget);
      await t.tap(find.byKey(const Key('planner-next')));
      await settleP(t);
      expect(find.text('Overdue · 1'), findsNothing);
      await dispose(t);
    });

    testWidgets('timed events and time-blocked tasks appear on the schedule; overlapping ones sit side by side', (t) async {
      final (env, _) = await openPlanner(t, seed: (r) async {
        await r.saveEvent(EventInput(title: 'Team sync', start: d(2026, 11, 6, 10), end: d(2026, 11, 6, 11)));
        await r.saveEvent(EventInput(title: 'Dentist', start: d(2026, 11, 6, 10, 30), end: d(2026, 11, 6, 11, 30)));
        await r.saveTask(TaskInput(title: 'Write report', planned: d(2026, 11, 6, 14), plannedMinutes: 90));
      });
      final tasks = await dbTasks(t, env);
      final events = (await t.runAsync(() => env.db.select(env.db.events).get()))!;
      final a = find.byKey(Key('block-event-${events.firstWhere((e) => e.title == 'Team sync').id}'));
      final b = find.byKey(Key('block-event-${events.firstWhere((e) => e.title == 'Dentist').id}'));
      expect(a, findsOneWidget);
      expect(b, findsOneWidget);
      expect(t.getTopLeft(a).dx, isNot(t.getTopLeft(b).dx), reason: 'overlapping events are in different columns');
      expect(t.getSize(a).width, closeTo(t.getSize(b).width, 0.5), reason: 'and share the width');
      expect(find.byKey(Key('block-task-${tasks.single.id}')), findsOneWidget);
      expect(find.text('Write report'), findsWidgets, reason: 'both in the checklist and as a block');
      expect(t.takeException(), isNull);
      await dispose(t);
    });

    testWidgets('all-day events show as chips; repeating events appear on later days', (t) async {
      await openPlanner(t, seed: (r) async {
        await r.saveEvent(EventInput(title: 'Holiday', start: d(2026, 11, 6), end: d(2026, 11, 8), allDay: true));
        await r.saveEvent(EventInput(title: 'Standup', start: d(2026, 11, 2, 9), end: d(2026, 11, 2, 9, 15), rrule: 'FREQ=WEEKLY;BYDAY=MO,FR'));
      });
      expect(find.text('All day'), findsOneWidget);
      expect(find.widgetWithText(ActionChip, 'Holiday'), findsOneWidget);
      expect(find.textContaining('Standup'), findsWidgets, reason: 'Friday 6th is a standup day');
      await t.tap(find.byKey(const Key('planner-next'))); // Saturday: no standup, holiday continues
      await settleP(t);
      expect(find.widgetWithText(ActionChip, 'Holiday'), findsOneWidget);
      expect(find.textContaining('Standup'), findsNothing);
      await t.tap(find.byKey(const Key('planner-next'))); // Sunday: holiday over
      await settleP(t);
      expect(find.widgetWithText(ActionChip, 'Holiday'), findsNothing);
      await dispose(t);
    });
  });

  group('editors', () {
    testWidgets('create a task with a time block and a reminder: schedules the notification and asks permission once', (t) async {
      final (env, sched) = await openPlanner(t);
      await t.tap(find.byKey(const Key('planner-next'))); // tomorrow, so a 09:00 reminder is in the future
      await settleP(t);
      await t.tap(find.byKey(const Key('planner-add-menu')));
      await settleP(t);
      await t.tap(find.text('New task'));
      await settleP(t);
      await t.enterText(find.byKey(const Key('title')), 'Prepare slides');
      await t.tap(find.byKey(const Key('has-block')));
      await settleP(t);
      await t.scrollUntilVisible(find.byKey(const Key('reminder')), 200, scrollable: editorScroll());
      await t.drag(editorScroll(), const Offset(0, -150)); // bring it away from the bottom edge
      await t.pump();
      await t.tap(find.byKey(const Key('reminder')));
      await settleP(t);
      await t.tap(find.text('15 minutes before').last);
      await settleP(t);
      await t.tap(find.byKey(const Key('save')));
      await settleP(t);
      final row = (await dbTasks(t, env)).single;
      expect((row.title, row.plannedMinutes, row.remindMinutes), ('Prepare slides', 60, 15));
      expect(DateTime.fromMillisecondsSinceEpoch(row.plannedAt!), d(2026, 11, 7, 9));
      expect(find.byKey(Key('block-task-${row.id}')), findsOneWidget);
      expect(sched.requests, 0, reason: 'permission already granted in this fake');
      expect(sched.last.single.at, d(2026, 11, 7, 8, 45));
      expect(sched.last.single.payload, 'task:${row.id}');
      await dispose(t);
    });

    testWidgets('create an event; it validates, saves, and can be edited and deleted with Undo', (t) async {
      final (env, _) = await openPlanner(t);
      await t.tap(find.byKey(const Key('planner-add-menu')));
      await settleP(t);
      await t.tap(find.text('New event').last); // (the empty state has a button with the same label)
      await settleP(t);
      await t.tap(find.byKey(const Key('save')));
      await settleP(t);
      expect(find.text('Give it a title.'), findsOneWidget, reason: 'empty title is refused with a reason');
      expect(find.byKey(const Key('title')), findsOneWidget, reason: 'the editor stays open');
      await t.enterText(find.byKey(const Key('title')), 'Dentist');
      await t.tap(find.byKey(const Key('save')));
      await settleP(t);
      final ev = (await t.runAsync(() => env.db.select(env.db.events).getSingle()))!;
      expect((ev.title, DateTime.fromMillisecondsSinceEpoch(ev.startAt), DateTime.fromMillisecondsSinceEpoch(ev.endAt)), ('Dentist', d(2026, 11, 6, 9), d(2026, 11, 6, 10)));
      await t.tap(find.byKey(Key('block-event-${ev.id}')));
      await settleP(t);
      expect(find.text('Edit event'), findsOneWidget);
      await t.enterText(find.byKey(const Key('title')), 'Dentist (moved)');
      await t.tap(find.byKey(const Key('save')));
      await settleP(t);
      expect(find.textContaining('Dentist (moved)'), findsWidgets);
      await t.tap(find.byKey(Key('block-event-${ev.id}')));
      await settleP(t);
      await t.tap(find.byKey(const Key('delete')));
      await settleP(t);
      expect(find.byKey(Key('block-event-${ev.id}')), findsNothing);
      await t.tap(find.text('Undo'));
      await settleP(t);
      expect(find.byKey(Key('block-event-${ev.id}')), findsOneWidget);
      await dispose(t);
    });

    testWidgets('a repeating task without a date is refused with a clear message and nothing typed is lost', (t) async {
      final (env, _) = await openPlanner(t);
      await t.tap(find.byKey(const Key('planner-add-menu')));
      await settleP(t);
      await t.tap(find.text('New task'));
      await settleP(t);
      await t.enterText(find.byKey(const Key('title')), 'Stretch');
      await t.tap(find.byKey(const Key('has-due'))); // new tasks opened from the planner start with the day's date; turn it off
      await settleP(t);
      await t.scrollUntilVisible(find.byKey(const Key('repeat-freq')), 200, scrollable: editorScroll());
      await t.tap(find.byKey(const Key('repeat-freq')));
      await settleP(t);
      await t.tap(find.text('Daily').last);
      await settleP(t);
      await t.tap(find.byKey(const Key('save')));
      await settleP(t);
      expect(find.text('Give a repeating task a date to start from.'), findsOneWidget);
      expect(find.text('Stretch'), findsOneWidget, reason: 'the title is still in the editor');
      expect(await dbTasks(t, env), isEmpty);
      await dispose(t);
    });

    testWidgets('editing a task changes only what you touched', (t) async {
      final (env, _) = await openPlanner(t, seed: (r) async => r.saveTask(TaskInput(title: 'Draft', due: d(2026, 11, 6), notes: 'keep me')).then((_) {}));
      final id = (await dbTasks(t, env)).single.id;
      await t.tap(find.byKey(Key('task-$id')));
      await settleP(t);
      expect(find.text('Edit task'), findsOneWidget);
      await t.enterText(find.byKey(const Key('title')), 'Draft v2');
      await t.tap(find.text('High'));
      await settleP(t);
      await t.tap(find.byKey(const Key('save')));
      await settleP(t);
      final row = (await dbTasks(t, env)).single;
      expect((row.title, row.priority, row.notes), ('Draft v2', 'high', 'keep me'));
      final outbox = (await t.runAsync(() => env.db.select(env.db.syncOutbox).get()))!;
      expect(outbox.where((o) => o.field == 'notes').length, 1, reason: 'notes were written once at creation and not re-sent');
      await dispose(t);
    });

    testWidgets('when notifications are blocked, saving a reminder still works and a clear banner explains why none will appear', (t) async {
      final (env, sched) = await openPlanner(t, granted: false);
      await t.tap(find.byKey(const Key('planner-next')));
      await settleP(t);
      await t.tap(find.byKey(const Key('planner-add-menu')));
      await settleP(t);
      await t.tap(find.text('New task'));
      await settleP(t);
      await t.enterText(find.byKey(const Key('title')), 'Call mum');
      await t.scrollUntilVisible(find.byKey(const Key('reminder')), 200, scrollable: editorScroll());
      await t.drag(editorScroll(), const Offset(0, -150)); // bring it away from the bottom edge
      await t.pump();
      await t.tap(find.byKey(const Key('reminder')));
      await settleP(t);
      await t.tap(find.text('At the time').last);
      await settleP(t);
      await t.tap(find.byKey(const Key('save')));
      await settleP(t);
      expect(sched.requests, 1, reason: 'asked for permission because the user set a reminder');
      expect((await dbTasks(t, env)).single.remindMinutes, 0, reason: 'the reminder is kept');
      expect(find.byKey(const Key('notifications-denied')), findsOneWidget);
      expect(sched.replaceCalls, 0, reason: 'nothing is scheduled without permission');
      await dispose(t);
    });
  });

  group('reminder planning', () {
    testWidgets('the pending reminders are planned on open, not re-sent when nothing changed, and dropped when the task is completed', (t) async {
      final (env, sched) = await openPlanner(t, seed: (r) async => r.saveTask(TaskInput(title: 'Call bank', due: d(2026, 11, 7, 9), dueHasTime: true, remindMinutes: 30)).then((_) {}));
      expect(sched.replaceCalls, 1);
      expect(sched.last.map((r) => (r.title, r.at)), [('Call bank', d(2026, 11, 7, 8, 30))]);
      final container = ProviderScope.containerOf(t.element(find.byType(FolioApp)));
      final ctrl = container.read(plannerControllerProvider.notifier);
      await ctrl.refresh();
      await ctrl.refresh();
      await settleP(t);
      expect(sched.replaceCalls, 1, reason: 'an unchanged plan is not re-sent to the OS');
      // complete it (tomorrow's page)
      await t.tap(find.byKey(const Key('planner-next')));
      await settleP(t);
      final id = (await dbTasks(t, env)).single.id;
      await t.tap(find.byKey(Key('done-$id')));
      await settleP(t);
      expect(sched.replaceCalls, 2);
      expect(sched.last, isEmpty, reason: 'a finished task no longer reminds');
      await dispose(t);
    });
  });

  group('week, month and year', () {
    Future<void> seedMix(PlannerRepository r) async {
      await r.saveTask(TaskInput(title: 'Pay rent', due: d(2026, 11, 6)));
      await r.saveTask(TaskInput(title: 'Taxes', due: d(2026, 11, 10)));
      await r.saveEvent(EventInput(title: 'Dentist', start: d(2026, 11, 10, 9), end: d(2026, 11, 10, 10)));
      await r.saveEvent(EventInput(title: 'Conference', start: d(2026, 11, 12), end: d(2026, 11, 14), allDay: true));
    }

    testWidgets('week: lists every day of the week with its items; tapping a day opens it', (t) async {
      await openPlanner(t, seed: seedMix);
      await t.tap(find.text('Week'));
      await settleP(t);
      expect(find.text('2 – 8 Nov 2026'), findsOneWidget);
      for (final day in [2, 3, 4, 5, 6, 7, 8]) {
        expect(find.byKey(Key('week-day-$day')), findsOneWidget, reason: 'day $day');
      }
      expect(find.text('Pay rent'), findsOneWidget);
      await t.tap(find.byKey(const Key('planner-next')));
      await settleP(t);
      expect(find.text('9 – 15 Nov 2026'), findsOneWidget);
      expect(find.text('Taxes'), findsOneWidget);
      expect(find.textContaining('Dentist'), findsOneWidget);
      expect(find.textContaining('Conference'), findsWidgets, reason: 'a 2-day event shows on each day');
      await t.tap(find.byKey(const Key('week-day-10')));
      await settleP(t);
      expect(find.text('Tuesday 10 November'), findsOneWidget);
      await dispose(t);
    });

    testWidgets('month: counts per day; tapping a day opens it', (t) async {
      await openPlanner(t, seed: seedMix);
      await t.tap(find.text('Month'));
      await settleP(t);
      expect(find.text('November 2026'), findsOneWidget);
      expect(find.byKey(const Key('month-task-11-6')), findsOneWidget);
      expect(find.byKey(const Key('month-ev-11-10')), findsOneWidget);
      expect(find.byKey(const Key('month-task-11-10')), findsOneWidget);
      for (final day in [12, 13]) {
        expect(find.byKey(Key('month-ev-11-$day')), findsOneWidget, reason: 'the conference spans the 12th and 13th (end is exclusive)');
      }
      expect(find.byKey(const Key('month-ev-11-14')), findsNothing);
      await t.tap(find.byKey(const Key('planner-next')));
      await settleP(t);
      expect(find.text('December 2026'), findsOneWidget);
      await t.tap(find.byKey(const Key('planner-prev')));
      await settleP(t);
      await t.tap(find.byKey(const Key('month-11-10')));
      await settleP(t);
      expect(find.text('Tuesday 10 November'), findsOneWidget);
      expect(find.text('Taxes'), findsOneWidget);
      await dispose(t);
    });

    testWidgets('year: twelve months; tapping one opens the month; navigation steps by year', (t) async {
      await openPlanner(t, seed: seedMix);
      await t.tap(find.text('Year'));
      await settleP(t);
      expect(find.byKey(const Key('planner-title')), findsOneWidget);
      expect(find.text('2026'), findsOneWidget);
      for (var m = 1; m <= 12; m++) {
        await t.scrollUntilVisible(find.byKey(Key('year-month-$m')), 200, scrollable: find.byType(Scrollable).first);
        expect(find.byKey(Key('year-month-$m')), findsOneWidget, reason: 'month $m');
      }
      await t.scrollUntilVisible(find.byKey(const Key('year-month-1')), -200, scrollable: find.byType(Scrollable).first);
      await t.tap(find.byKey(const Key('planner-next')));
      await settleP(t);
      expect(find.text('2027'), findsOneWidget);
      await t.tap(find.byKey(const Key('planner-prev')));
      await settleP(t);
      await t.scrollUntilVisible(find.byKey(const Key('year-month-11')), 200, scrollable: find.byType(Scrollable).first);
      await t.ensureVisible(find.byKey(const Key('year-month-11')));
      await settleP(t);
      await t.tap(find.byKey(const Key('year-month-11')));
      await settleP(t);
      expect(find.text('November 2026'), findsOneWidget);
      await dispose(t);
    });
  });

  group('layouts', () {
    testWidgets('landscape phone (850 × 390): every view fits without overflow', (t) async {
      await openPlanner(t, w: 850, h: 390, seed: (r) async {
        await r.saveTask(TaskInput(title: 'Pay rent', due: d(2026, 11, 6)));
        await r.saveEvent(EventInput(title: 'Dentist', start: d(2026, 11, 6, 10), end: d(2026, 11, 6, 11)));
      });
      for (final mode in ['Day', 'Week', 'Month', 'Year']) {
        await t.tap(find.text(mode));
        await settleP(t);
        expect(t.takeException(), isNull, reason: '$mode overflowed in landscape');
      }
      await dispose(t);
    });

    testWidgets('desktop: day view shows checklist and schedule side by side; week view shows seven columns', (t) async {
      await openPlanner(t, w: 1400, h: 900, seed: (r) async {
        await r.saveTask(TaskInput(title: 'Pay rent', due: d(2026, 11, 6)));
        await r.saveEvent(EventInput(title: 'Dentist', start: d(2026, 11, 6, 10), end: d(2026, 11, 6, 11)));
      });
      final list = t.getTopLeft(find.text('Pay rent'));
      final block = t.getTopLeft(find.textContaining('Dentist').first);
      expect(block.dx, greaterThan(list.dx + 200), reason: 'schedule is a second column to the right');
      await t.tap(find.text('Week'));
      await settleP(t);
      final xs = {for (final day in [2, 3, 4, 5, 6, 7, 8]) t.getTopLeft(find.byKey(Key('week-day-$day'))).dx.round()};
      expect(xs.length, 7, reason: 'seven distinct columns');
      expect(t.takeException(), isNull);
      await dispose(t);
    });

    testWidgets('a phone-width planner has no overflow in any view, with data', (t) async {
      await openPlanner(t, w: 360, h: 740, seed: (r) async {
        await r.saveTask(TaskInput(title: 'A task with a rather long title that has to wrap onto another line', due: d(2026, 11, 6), priority: Priority.high, rrule: 'FREQ=DAILY'));
        await r.saveEvent(EventInput(title: 'Event with a long name too', start: d(2026, 11, 6, 10), end: d(2026, 11, 6, 11)));
      });
      for (final mode in ['Day', 'Week', 'Month', 'Year']) {
        await t.tap(find.text(mode));
        await settleP(t);
        expect(t.takeException(), isNull, reason: '$mode overflowed at 360 px');
      }
      await dispose(t);
    });
  });

  group('app lock-in with the rest of the app', () {
    testWidgets('Back from the Planner goes Home', (t) async {
      await openPlanner(t);
      await t.binding.handlePopRoute();
      await settleP(t);
      expect(find.byKey(const Key('home-quick-add')), findsOneWidget);
      await dispose(t);
    });
  });

  group('notifications panel', () {
    testWidgets('Settings shows status and the test buttons call the scheduler', (t) async {
      final (_, sch) = await openPlanner(t);
      await t.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Settings')));
      await settleP(t);
      final scroll = find.byType(Scrollable).first;
      await t.scrollUntilVisible(find.byKey(const Key('notif-test-now')), 300, scrollable: scroll);
      await t.ensureVisible(find.byKey(const Key('notif-test-now')));
      await t.pump();
      await t.tap(find.byKey(const Key('notif-test-now')), warnIfMissed: false);
      await settleP(t);
      expect(sch.testNow, 1);
      await t.ensureVisible(find.byKey(const Key('notif-test-later')));
      await t.pump();
      await t.tap(find.byKey(const Key('notif-test-later')), warnIfMissed: false);
      await settleP(t);
      expect(sch.testLater, 1);
      await dispose(t);
    });
  });

  group('sub-tasks', () {
    testWidgets('add sub-tasks in the editor (button, Enter, and an unsubmitted one on Save); the task shows a counter', (t) async {
      final (env, _) = await openPlanner(t);
      await t.tap(find.byKey(const Key('planner-add-menu')));
      await settleP(t);
      await t.tap(find.text('New task'));
      await settleP(t);
      await t.enterText(find.byKey(const Key('title')), 'Pack for trip');
      await t.scrollUntilVisible(find.byKey(const Key('new-subtask')), 200, scrollable: editorScroll());
      await t.enterText(find.byKey(const Key('new-subtask')), 'Passport');
      await t.drag(editorScroll(), const Offset(0, -120)); // the button must be well inside the viewport
      await t.pump();
      await t.tap(find.byKey(const Key('add-subtask')));
      await settleP(t);
      await t.enterText(find.byKey(const Key('new-subtask')), 'Charger');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await settleP(t);
      await t.enterText(find.byKey(const Key('new-subtask')), 'Toothbrush');
      await t.tap(find.byKey(const Key('save')));
      await settleP(t);
      final row = (await dbTasks(t, env)).single;
      expect(decodeChecklist(row.checklist).map((c) => c.title).toList(), ['Passport', 'Charger', 'Toothbrush']);
      expect(find.text('0/3'), findsOneWidget);
      await dispose(t);
    });

    testWidgets('the counter expands the sub-tasks in place; ticking updates the count and is saved', (t) async {
      final (env, _) = await openPlanner(t, seed: (repo) async {
        await repo.saveTask(TaskInput(title: 'Pack for trip', due: d(2026, 11, 6), checklist: const [ChecklistItem(id: 'a', title: 'Passport'), ChecklistItem(id: 'b', title: 'Charger')]));
      });
      final id = (await dbTasks(t, env)).single.id;
      expect(find.text('Passport'), findsNothing, reason: 'collapsed by default');
      await t.tap(find.byKey(Key('subtasks-$id')));
      await settleP(t);
      expect(find.text('Passport'), findsOneWidget);
      await t.tap(find.byKey(const Key('sub-a')));
      await settleP(t);
      expect(find.text('1/2'), findsOneWidget);
      expect(decodeChecklist((await dbTasks(t, env)).single.checklist).map((c) => c.done).toList(), [true, false]);
      expect(find.text('Passport'), findsOneWidget, reason: 'stays expanded');
      await t.tap(find.byKey(const Key('sub-b')));
      await settleP(t);
      expect(find.text('2/2'), findsOneWidget);
      expect((await dbTasks(t, env)).single.doneAt, isNull, reason: 'ticking every sub-task does not silently close the task');
      await dispose(t);
    });

    testWidgets('edit: rename, tick, remove a sub-task; only the checklist changes', (t) async {
      final (env, _) = await openPlanner(t, seed: (repo) async {
        await repo.saveTask(TaskInput(title: 'Pack for trip', due: d(2026, 11, 6), checklist: const [ChecklistItem(id: 'a', title: 'Passport'), ChecklistItem(id: 'b', title: 'Charger')]));
      });
      final id = (await dbTasks(t, env)).single.id;
      await t.tap(find.byKey(Key('task-$id')));
      await settleP(t);
      await t.scrollUntilVisible(find.byKey(const Key('item-title-a')), 200, scrollable: editorScroll());
      await t.enterText(find.byKey(const Key('item-title-a')), 'Passport + visa');
      await t.tap(find.byKey(const Key('item-done-a')));
      await t.tap(find.byKey(const Key('item-delete-b')));
      await settleP(t);
      await t.tap(find.byKey(const Key('save')));
      await settleP(t);
      final items = decodeChecklist((await dbTasks(t, env)).single.checklist);
      expect(items, [const ChecklistItem(id: 'a', title: 'Passport + visa', done: true)]);
      expect(find.text('1/1'), findsOneWidget);
      await dispose(t);
    });
  });
}
