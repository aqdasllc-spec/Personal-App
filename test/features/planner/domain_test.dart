import 'package:flutter_test/flutter_test.dart';
import 'package:folio/features/planner/domain/agenda.dart';
import 'package:folio/features/planner/domain/models.dart';
import 'package:folio/features/planner/domain/recurrence.dart';
import 'package:folio/features/planner/domain/reminders.dart';

DateTime d(int y, int m, int day, [int h = 0, int mi = 0]) => DateTime(y, m, day, h, mi);
List<String> ymd(Iterable<DateTime> l) => [for (final x in l) '${x.year}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}'];

PlannerTask task(String id, {DateTime? due, bool time = false, DateTime? planned, int? minutes, bool done = false, Priority p = Priority.none, String rrule = '', int? remind, String? title}) =>
    PlannerTask(id: id, title: title ?? id, due: due, dueHasTime: time, planned: planned, plannedMinutes: minutes, doneAt: done ? d(2026, 1, 1) : null, priority: p, rrule: rrule, remindMinutes: remind);

PlannerEvent event(String id, DateTime s, DateTime e, {bool allDay = false, String rrule = '', int? remind}) => PlannerEvent(id: id, title: id, start: s, end: e, allDay: allDay, rrule: rrule, remindMinutes: remind);

void main() {
  group('Recurrence parse / format', () {
    test('round trip and tolerant parsing', () {
      for (final s in ['FREQ=DAILY', 'FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE;COUNT=5', 'FREQ=MONTHLY;UNTIL=20261231', 'FREQ=YEARLY']) {
        expect(Recurrence.parse(s)!.toRule(), s);
      }
      expect(Recurrence.parse(''), isNull);
      expect(Recurrence.parse(null), isNull);
      expect(Recurrence.parse('FREQ=HOURLY'), isNull, reason: 'unsupported frequency -> no repeat, never a crash');
      expect(Recurrence.parse('garbage'), isNull);
      expect(Recurrence.parse('freq=daily;interval=0')!.interval, 1);
      expect(Recurrence.parse('FREQ=DAILY;INTERVAL=99999')!.interval, 999);
      expect(Recurrence.parse('FREQ=DAILY;X-UNKNOWN=1;COUNT=-3')!.count, isNull);
      expect(Recurrence.parse('FREQ=MONTHLY;BYDAY=MO')!.byWeekday, isEmpty, reason: 'BYDAY only applies to weekly');
    });
    test('describe', () {
      expect(Recurrence.parse('FREQ=DAILY')!.describe(), 'Every day');
      expect(Recurrence.parse('FREQ=WEEKLY;INTERVAL=2;BYDAY=WE,MO')!.describe(), 'Every 2 weeks on Mon, Wed');
      expect(Recurrence.parse('FREQ=MONTHLY;COUNT=6')!.describe(), 'Every month, 6 times');
    });
  });

  group('Recurrence expansion', () {
    test('daily with interval and count', () {
      final r = Recurrence.parse('FREQ=DAILY;INTERVAL=2;COUNT=4')!;
      expect(ymd(r.occurrences(d(2026, 11, 1, 9)).toList()), ['2026-11-01', '2026-11-03', '2026-11-05', '2026-11-07']);
    });
    test('daily keeps the wall-clock time across daylight-saving changes (run with TZ=Europe/Berlin and America/New_York too)', () {
      final r = Recurrence.parse('FREQ=DAILY')!;
      final occ = r.between(d(2026, 3, 1, 9, 30), d(2026, 3, 1), d(2026, 4, 15));
      expect(occ.length, 45);
      for (final o in occ) {
        expect((o.hour, o.minute), (9, 30), reason: '$o drifted');
      }
      final fall = r.between(d(2026, 10, 20, 23, 0), d(2026, 10, 20), d(2026, 11, 10));
      for (final o in fall) {
        expect(o.hour, 23, reason: '$o drifted');
      }
    });
    test('weekly on several weekdays; start before the first matching weekday', () {
      final r = Recurrence.parse('FREQ=WEEKLY;BYDAY=MO,WE,FR')!;
      // 2026-11-04 is a Wednesday
      expect(ymd(r.between(d(2026, 11, 4, 8), d(2026, 11, 1), d(2026, 11, 15))), ['2026-11-04', '2026-11-06', '2026-11-09', '2026-11-11', '2026-11-13']);
      // start on a Tuesday with BYDAY=MO: the Tuesday itself is not an occurrence
      expect(ymd(Recurrence.parse('FREQ=WEEKLY;BYDAY=MO')!.occurrences(d(2026, 11, 3, 8)).take(2)), ['2026-11-09', '2026-11-16']);
    });
    test('weekly without BYDAY repeats on the start weekday; interval skips weeks', () {
      expect(ymd(Recurrence.parse('FREQ=WEEKLY;INTERVAL=2')!.occurrences(d(2026, 11, 4, 8)).take(3)), ['2026-11-04', '2026-11-18', '2026-12-02']);
    });
    test('weekly crossing a year boundary', () {
      expect(ymd(Recurrence.parse('FREQ=WEEKLY;BYDAY=TH')!.between(d(2026, 12, 24, 8), d(2026, 12, 20), d(2027, 1, 10))), ['2026-12-24', '2026-12-31', '2027-01-07']);
    });
    test('monthly on the 31st falls on the last day of shorter months (not skipped)', () {
      expect(ymd(Recurrence.parse('FREQ=MONTHLY')!.occurrences(d(2026, 1, 31, 10)).take(5)), ['2026-01-31', '2026-02-28', '2026-03-31', '2026-04-30', '2026-05-31']);
      expect(ymd(Recurrence.parse('FREQ=MONTHLY')!.occurrences(d(2028, 1, 31, 10)).take(2)), ['2028-01-31', '2028-02-29'], reason: 'leap year February');
    });
    test('monthly interval and year rollover', () {
      expect(ymd(Recurrence.parse('FREQ=MONTHLY;INTERVAL=5')!.occurrences(d(2026, 10, 15, 10)).take(3)), ['2026-10-15', '2027-03-15', '2027-08-15']);
    });
    test('yearly on 29 February', () {
      expect(ymd(Recurrence.parse('FREQ=YEARLY')!.occurrences(d(2028, 2, 29, 9)).take(5)), ['2028-02-29', '2029-02-28', '2030-02-28', '2031-02-28', '2032-02-29']);
    });
    test('UNTIL is inclusive of that day regardless of time', () {
      final r = Recurrence.parse('FREQ=DAILY;UNTIL=20261105')!;
      expect(ymd(r.occurrences(d(2026, 11, 3, 23, 59)).toList()), ['2026-11-03', '2026-11-04', '2026-11-05']);
    });
    test('COUNT includes the first occurrence; COUNT=1 is a single occurrence', () {
      expect(Recurrence.parse('FREQ=WEEKLY;COUNT=1')!.occurrences(d(2026, 11, 4, 8)).length, 1);
      expect(Recurrence.parse('FREQ=WEEKLY;BYDAY=MO,TU;COUNT=3')!.occurrences(d(2026, 11, 2, 8)).length, 3);
    });
    test('between and nextAfter', () {
      final r = Recurrence.parse('FREQ=DAILY')!;
      expect(ymd(r.between(d(2026, 11, 1, 9), d(2026, 11, 5), d(2026, 11, 8))), ['2026-11-05', '2026-11-06', '2026-11-07']);
      expect(r.nextAfter(d(2026, 11, 1, 9), d(2026, 11, 5, 9)), d(2026, 11, 6, 9));
      expect(r.nextAfter(d(2026, 11, 1, 9), d(2026, 11, 5, 8)), d(2026, 11, 5, 9), reason: 'strictly after the instant given');
      expect(Recurrence.parse('FREQ=DAILY;COUNT=2')!.nextAfter(d(2026, 11, 1, 9), d(2026, 11, 2, 9)), isNull, reason: 'rule has ended');
    });
    test('an unbounded rule is always bounded in practice (no runaway loops)', () {
      final all = Recurrence.parse('FREQ=DAILY')!.occurrences(d(2026, 1, 1, 9)).length;
      expect(all, lessThan(200001));
    });
  });

  group('dayAgenda', () {
    final today = d(2026, 11, 6);
    test('tasks due or planned that day are listed; open before done; timed before untimed; then priority', () {
      final tasks = [
        task('done-1', due: d(2026, 11, 6), done: true),
        task('low', due: d(2026, 11, 6), p: Priority.low),
        task('high', due: d(2026, 11, 6), p: Priority.high),
        task('at-3pm', due: d(2026, 11, 6, 15), time: true),
        task('at-9am', due: d(2026, 11, 6, 9), time: true),
        task('other-day', due: d(2026, 11, 7)),
        task('no-date'),
      ];
      final a = dayAgenda(today, tasks, const [], today: today);
      expect(a.tasks.map((i) => i.id), ['at-9am', 'at-3pm', 'high', 'low', 'done-1']);
    });
    test('a time-blocked task appears in the timeline AND the checklist, with its planned length', () {
      final t = task('write', due: d(2026, 11, 9), planned: d(2026, 11, 6, 14), minutes: 90);
      final a = dayAgenda(today, [t], const [], today: today);
      expect(a.timed.single.start, d(2026, 11, 6, 14));
      expect(a.timed.single.end, d(2026, 11, 6, 15, 30));
      expect(a.tasks.map((i) => i.id), ['write']);
      final due = dayAgenda(d(2026, 11, 9), [t], const [], today: today);
      expect(due.timed, isEmpty, reason: 'the block is on the 6th, the deadline on the 9th');
      expect(due.tasks.map((i) => i.id), ['write']);
    });
    test('a block without a length defaults to 30 minutes', () {
      final a = dayAgenda(today, [task('x', planned: d(2026, 11, 6, 10))], const [], today: today);
      expect(a.timed.single.end, d(2026, 11, 6, 10, 30));
    });
    test('overdue tasks show only on today, only when open', () {
      final tasks = [task('late', due: d(2026, 11, 3)), task('late-done', due: d(2026, 11, 3), done: true), task('future', due: d(2026, 11, 8))];
      expect(dayAgenda(today, tasks, const [], today: today).overdue.map((i) => i.id), ['late']);
      expect(dayAgenda(d(2026, 11, 7), tasks, const [], today: today).overdue, isEmpty);
      expect(dayAgenda(d(2026, 11, 5), tasks, const [], today: today).overdue, isEmpty);
    });
    test('a task due earlier today (with a time already past) is not overdue until the day is over', () {
      final a = dayAgenda(today, [task('earlier', due: d(2026, 11, 6, 8), time: true)], const [], today: d(2026, 11, 6, 12));
      expect(a.overdue, isEmpty);
      expect(a.tasks.single.id, 'earlier');
    });
    test('multi-day all-day events appear on each day; timed events are clipped at midnight', () {
      final trip = event('trip', d(2026, 11, 5), d(2026, 11, 8), allDay: true); // 5th..7th
      final night = event('night', d(2026, 11, 6, 22), d(2026, 11, 7, 2));
      for (final day in [5, 6, 7]) {
        expect(dayAgenda(d(2026, 11, day), const [], [trip], today: today).allDay.map((i) => i.id), ['trip'], reason: 'day $day');
      }
      expect(dayAgenda(d(2026, 11, 8), const [], [trip], today: today).allDay, isEmpty, reason: 'end is exclusive');
      final d6 = dayAgenda(d(2026, 11, 6), const [], [night], today: today).timed.single;
      expect((d6.start, d6.end), (d(2026, 11, 6, 22), d(2026, 11, 7)));
      final d7 = dayAgenda(d(2026, 11, 7), const [], [night], today: today).timed.single;
      expect((d7.start, d7.end), (d(2026, 11, 7), d(2026, 11, 7, 2)));
    });
    test('repeating events expand onto the right days with the right time', () {
      final standup = event('standup', d(2026, 11, 2, 9), d(2026, 11, 2, 9, 15), rrule: 'FREQ=WEEKLY;BYDAY=MO,WE');
      expect(dayAgenda(d(2026, 11, 9), const [], [standup], today: today).timed.single.start, d(2026, 11, 9, 9));
      expect(dayAgenda(d(2026, 11, 10), const [], [standup], today: today).timed, isEmpty);
      expect(dayAgenda(d(2026, 11, 11), const [], [standup], today: today).timed.single.repeats, isTrue);
    });
    test('a multi-day repeating all-day event shows on its middle days', () {
      final conf = event('conf', d(2026, 11, 2), d(2026, 11, 5), allDay: true, rrule: 'FREQ=WEEKLY'); // Mon-Wed, weekly
      expect(dayAgenda(d(2026, 11, 11), const [], [conf], today: today).allDay.map((i) => i.id), ['conf']);
      expect(dayAgenda(d(2026, 11, 12), const [], [conf], today: today).allDay, isEmpty);
    });
    test('an empty day is empty', () => expect(dayAgenda(today, const [], const [], today: today).isEmpty, isTrue));
  });

  group('rangeCounts', () {
    test('counts events, open and done tasks per day; multi-day events count on every day they touch; a midnight end does not spill', () {
      final from = d(2026, 11, 1), to = d(2026, 12, 1);
      final c = rangeCounts(from, to, [
        task('a', due: d(2026, 11, 6)),
        task('b', due: d(2026, 11, 6), done: true),
        task('c', due: d(2026, 11, 10), planned: d(2026, 11, 8, 9)),
      ], [
        event('trip', d(2026, 11, 5), d(2026, 11, 7), allDay: true),
        event('late', d(2026, 11, 20, 22), d(2026, 11, 21)),
        event('rep', d(2026, 11, 2, 9), d(2026, 11, 2, 10), rrule: 'FREQ=WEEKLY'),
      ]);
      expect((c[d(2026, 11, 6)]!.events, c[d(2026, 11, 6)]!.open, c[d(2026, 11, 6)]!.done), (1, 1, 1));
      expect(c[d(2026, 11, 5)]!.events, 1);
      expect(c[d(2026, 11, 7)], isNull, reason: 'all-day trip ends before the 7th');
      expect(c[d(2026, 11, 21)], isNull, reason: 'ends exactly at midnight');
      expect(c[d(2026, 11, 20)]!.events, 1);
      expect([for (final k in c.keys) if (c[k]!.events > 0 && k.weekday == DateTime.monday) k.day], [2, 9, 16, 23, 30]);
      expect(c[d(2026, 11, 8)]!.open, 1, reason: 'planned day');
      expect(c[d(2026, 11, 10)]!.open, 1, reason: 'due day');
    });
    test('items outside the range are ignored', () {
      final c = rangeCounts(d(2026, 11, 1), d(2026, 12, 1), [task('x', due: d(2026, 12, 1))], const []);
      expect(c, isEmpty);
    });
  });

  group('layoutBlocks', () {
    AgendaItem blk(String id, int sh, int sm, int eh, int em) => AgendaItem(kind: ItemKind.event, id: id, title: id, start: d(2026, 11, 6, sh, sm), end: d(2026, 11, 6, eh, em), hasTime: true);
    final day = d(2026, 11, 6);
    Map<String, PositionedBlock> byId(List<PositionedBlock> l) => {for (final p in l) p.item.id: p};

    test('non-overlapping blocks each get a full-width column', () {
      final l = byId(layoutBlocks([blk('a', 9, 0, 10, 0), blk('b', 10, 0, 11, 0)], day));
      expect((l['a']!.column, l['a']!.columns, l['b']!.column, l['b']!.columns), (0, 1, 0, 1));
    });
    test('two overlapping blocks sit side by side', () {
      final l = byId(layoutBlocks([blk('a', 9, 0, 10, 30), blk('b', 10, 0, 11, 0)], day));
      expect({l['a']!.column, l['b']!.column}, {0, 1});
      expect((l['a']!.columns, l['b']!.columns), (2, 2));
    });
    test('a chain A-B-C reuses a freed column and shares the cluster width', () {
      final l = byId(layoutBlocks([blk('a', 9, 0, 10, 0), blk('b', 9, 30, 10, 30), blk('c', 10, 0, 11, 0)], day));
      expect(l['a']!.column, 0);
      expect(l['b']!.column, 1);
      expect(l['c']!.column, 0, reason: 'A ended, so C reuses its column');
      expect([for (final p in l.values) p.columns], [2, 2, 2]);
    });
    test('separate clusters do not affect each other', () {
      final l = byId(layoutBlocks([blk('a', 9, 0, 10, 0), blk('b', 9, 0, 10, 0), blk('c', 14, 0, 15, 0)], day));
      expect(l['a']!.columns, 2);
      expect(l['c']!.columns, 1);
    });
    test('three-way overlap uses three columns; very short blocks get a minimum height', () {
      final l = byId(layoutBlocks([blk('a', 9, 0, 11, 0), blk('b', 9, 0, 11, 0), blk('c', 9, 30, 9, 31)], day));
      expect(l['a']!.columns, 3);
      expect(l['c']!.endMinute - l['c']!.startMinute, minBlockMinutes);
    });
    test('blocks are clipped to the day', () {
      final l = layoutBlocks([AgendaItem(kind: ItemKind.event, id: 'n', title: 'n', start: d(2026, 11, 6, 23, 0), end: d(2026, 11, 7, 3, 0), hasTime: true)], day);
      expect((l.single.startMinute, l.single.endMinute), (1380, 1440));
    });
  });

  group('pickReminders', () {
    final now = d(2026, 11, 6, 12);
    test('timed task: fires offset minutes before; all-day task at 09:00 (minus offset); none for done or past', () {
      final r = pickReminders(now, [
        task('timed', due: d(2026, 11, 6, 15), time: true, remind: 30),
        task('allday', due: d(2026, 11, 8), remind: 0),
        task('day-before', due: d(2026, 11, 8), remind: 1440),
        task('done', due: d(2026, 11, 7, 10), time: true, remind: 10, done: true),
        task('past', due: d(2026, 11, 6, 12, 5), time: true, remind: 10),
        task('no-reminder', due: d(2026, 11, 7, 10), time: true),
      ], const []);
      expect([for (final x in r) '${x.payload}@${x.at.day}-${x.at.hour}:${x.at.minute.toString().padLeft(2, '0')}'], ['task:timed@6-14:30', 'task:day-before@7-9:00', 'task:allday@8-9:00']);
      expect(r.first.body, 'Today at 15:00');
    });
    test('a planned time block wins over the due date', () {
      final r = pickReminders(now, [task('t', due: d(2026, 11, 20), planned: d(2026, 11, 7, 10), remind: 15)], const []);
      expect(r.single.at, d(2026, 11, 7, 9, 45));
      expect(r.single.body, 'Today at 10:00', reason: 'the label is relative to when the notification FIRES (09:45 on the 7th)');
    });
    test('events: every upcoming occurrence of a repeating event within the horizon', () {
      final r = pickReminders(now, const [], [event('standup', d(2026, 11, 2, 9), d(2026, 11, 2, 9, 15), rrule: 'FREQ=DAILY', remind: 10)], horizon: const Duration(days: 3));
      expect(r.map((x) => x.at), [d(2026, 11, 7, 8, 50), d(2026, 11, 8, 8, 50), d(2026, 11, 9, 8, 50)]);
    });
    test('a repeating task keeps reminding at later occurrences until completed', () {
      final r = pickReminders(now, [task('water', due: d(2026, 11, 6, 18), time: true, rrule: 'FREQ=DAILY', remind: 0)], const [], horizon: const Duration(days: 3));
      expect(r.map((x) => x.at), [d(2026, 11, 6, 18), d(2026, 11, 7, 18), d(2026, 11, 8, 18)]);
      expect(pickReminders(now, [task('water', due: d(2026, 11, 6, 18), time: true, rrule: 'FREQ=DAILY', remind: 0)], const [], horizon: const Duration(days: 2)).length, 2, reason: 'the horizon bounds how far ahead we schedule');
    });
    test('capped to the platform limit, soonest first', () {
      final many = [for (var i = 0; i < 200; i++) task('t$i', due: d(2026, 11, 7, 8, 0).add(Duration(minutes: 200 - i)), time: true, remind: 0)];
      final r = pickReminders(now, many, const []);
      expect(r.length, maxPendingReminders);
      for (var i = 1; i < r.length; i++) {
        expect(r[i].at.isBefore(r[i - 1].at), isFalse);
      }
      expect(r.first.payload, 'task:t199');
    });
    test('notification ids are stable and differ per occurrence', () {
      final a = pickReminders(now, [task('t', due: d(2026, 11, 7, 9), time: true, rrule: 'FREQ=DAILY', remind: 0)], const [], horizon: const Duration(days: 3));
      final b = pickReminders(now, [task('t', due: d(2026, 11, 7, 9), time: true, rrule: 'FREQ=DAILY', remind: 0)], const [], horizon: const Duration(days: 3));
      expect(a.map((x) => x.id), b.map((x) => x.id));
      expect(a.map((x) => x.id).toSet().length, a.length);
      for (final x in a) {
        expect(x.id, inInclusiveRange(0, 0x7fffffff));
      }
    });
    test('empty titles still produce a readable notification', () {
      expect(pickReminders(now, [task('t', title: '', due: d(2026, 11, 7, 9), time: true, remind: 0)], const []).single.title, 'Reminder');
    });
  });
}
