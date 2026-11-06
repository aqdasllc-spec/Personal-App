import 'package:test/test.dart';
import 'package:tracker_engine/tracker_engine.dart';

import 'fixtures.dart';

QueryResult q(ViewConfig v, {List<TrackerRecord>? records, String search = ''}) => runQuery(tasksSnapshot(records), v, now: now, search: search);
FilterCondition c(String p, FilterOp op, [Object? v]) => FilterCondition(propertyId: p, op: op, value: v);
ViewConfig f(FilterNode n) => ViewConfig(filter: n is FilterGroup ? n : FilterGroup(children: [n]));

void main() {
  group('filters', () {
    test('archived hidden by default, shown on request', () {
      expect(ids(q(ViewConfig())), ['t1', 't2', 't3', 't4', 't5']);
      expect(ids(q(ViewConfig(showArchived: true))), contains('t6'));
    });
    test('text: contains is case/diacritic-insensitive; empty rows handled', () {
      expect(ids(q(f(c('name', FilterOp.contains, 'ECLAIR')))), ['t2']);
      expect(ids(q(f(c('name', FilterOp.startsWith, 'file')))), ['t3']);
      expect(ids(q(f(c('name', FilterOp.notContains, 'a')))), ['t1'], reason: '"write intro" is the only name without an a');
      expect(ids(q(f(c('name', FilterOp.eq, 'call dentist')))), ['t5']);
    });
    test('numbers: comparison ignores empties except neq/isEmpty', () {
      expect(ids(q(f(c('hours', FilterOp.gt, 1)))), ['t1', 't3']);
      expect(ids(q(f(c('hours', FilterOp.gte, 1)))), ['t1', 't2', 't3']);
      expect(ids(q(f(c('hours', FilterOp.isEmpty)))), ['t4', 't5']);
      expect(ids(q(f(c('hours', FilterOp.neq, 1)))), ['t1', 't3', 't4', 't5']);
    });
    test('select/status', () {
      expect(ids(q(f(c('status', FilterOp.eq, 'doing')))), ['t1', 't4']);
      expect(ids(q(f(c('status', FilterOp.isAnyOf, ['todo', 'done'])))), ['t2', 't3']);
      expect(ids(q(f(c('status', FilterOp.isNoneOf, ['doing'])))), ['t2', 't3', 't5']);
      expect(ids(q(f(c('status', FilterOp.isEmpty)))), ['t5']);
    });
    test('multi-select', () {
      expect(ids(q(f(c('tags', FilterOp.hasAny, ['t1'])))), ['t2', 't3']);
      expect(ids(q(f(c('tags', FilterOp.hasNone, ['t1'])))), ['t1', 't4', 't5']);
    });
    test('checkbox: unset counts as unchecked', () {
      expect(ids(q(f(c('done', FilterOp.isChecked)))), ['t3']);
      expect(ids(q(f(c('done', FilterOp.isUnchecked)))), ['t1', 't2', 't4', 't5']);
    });
    test('dates compare by day; relative windows use "now"', () {
      expect(ids(q(f(c('due', FilterOp.eq, '2026-11-06')))), ['t2']);
      expect(ids(q(f(c('due', FilterOp.before, '2026-11-06')))), ['t3']);
      expect(ids(q(f(c('due', FilterOp.onOrAfter, '2026-11-08')))), ['t1', 't4']);
      expect(ids(q(f(c('due', FilterOp.inNextDays, 3)))), ['t1', 't2']);
      expect(ids(q(f(c('due', FilterOp.inLastDays, 7)))), ['t2', 't3']);
    });
    test('filters on computed (formula) properties work', () {
      // t1 due in 2 days, t2 today (0), t3 7 days ago (-7), t4 in 25 days; t5 has no due date -> formula error -> never matches
      expect(ids(q(f(c('daysLeft', FilterOp.lt, 3)))), ['t1', 't2', 't3']);
    });
    test('nested AND / OR groups', () {
      final g = FilterGroup(and: true, children: [
        c('status', FilterOp.isNoneOf, ['done']),
        FilterGroup(and: false, children: [c('hours', FilterOp.gt, 3), c('tags', FilterOp.hasAny, ['t1'])]),
      ]);
      expect(ids(q(f(g))), ['t1', 't2']);
    });
    test('a filter on a deleted property is ignored (never silently hides data)', () {
      expect(ids(q(f(c('gone', FilterOp.eq, 'x')))).length, 5);
    });
    test('free-text search across visible values, folded', () {
      expect(ids(q(ViewConfig(), search: 'eclair')), ['t2']);
      expect(ids(q(ViewConfig(), search: 'urgent')), ['t2', 't3']);
      expect(ids(q(ViewConfig(), search: 'In prog')), ['t1', 't4']);
      expect(ids(q(ViewConfig(), search: 'zzz')), isEmpty);
    });
  });

  group('sorting', () {
    test('ascending/descending, empties always last', () {
      expect(ids(q(ViewConfig(sorts: [const SortKey('hours')]))), ['t2', 't3', 't1', 't4', 't5']);
      expect(ids(q(ViewConfig(sorts: [const SortKey('hours', descending: true)]))), ['t1', 't3', 't2', 't4', 't5']);
    });
    test('text sort is diacritic/case-insensitive', () {
      expect(ids(q(ViewConfig(sorts: [const SortKey('name')]))), ['t5', 't2', 't3', 't4', 't1']);
    });
    test('select sorts by option order, not label', () {
      expect(ids(q(ViewConfig(sorts: [const SortKey('status')]))), ['t2', 't1', 't4', 't3', 't5']);
    });
    test('multi-key and stable tie-break by sort key then id', () {
      final recs = [task('b', 'x', hours: 1, key: 'a2'), task('a', 'x', hours: 1, key: 'a1'), task('c', 'y', hours: 0)];
      expect(ids(q(ViewConfig(sorts: [const SortKey('hours', descending: true)]), records: recs)), ['a', 'b', 'c']);
      expect(ids(q(ViewConfig(sorts: [const SortKey('name'), const SortKey('hours', descending: true)]), records: recs)), ['a', 'b', 'c']);
    });
    test('sort by computed property', () {
      final r = ids(q(ViewConfig(sorts: [const SortKey('daysLeft')])));
      expect(r.first, 't3');
      expect(r.sublist(r.length - 1), ['t5']);
    });
    test('property: any sort result is non-decreasing under its own comparator, for random data', () {
      var s = 1;
      int rnd(int n) => (s = (s * 1103515245 + 12345) & 0x7fffffff) % n;
      for (var trial = 0; trial < 50; trial++) {
        final recs = [
          for (var i = 0; i < 40; i++) task('r$i', 'n${rnd(5)}', hours: rnd(4) == 0 ? null : rnd(6), status: ['todo', 'doing', 'done', null][rnd(4)])
        ];
        final res = q(ViewConfig(sorts: [const SortKey('hours'), const SortKey('status', descending: true)]), records: recs).records;
        final hs = [for (final r in res) r.cells['hours']];
        final firstNull = hs.indexWhere((h) => h == null);
        if (firstNull >= 0) expect(hs.sublist(firstNull).every((h) => h == null), isTrue, reason: 'nulls last');
        final nonNull = hs.whereType<num>().toList();
        for (var i = 1; i < nonNull.length; i++) {
          expect(nonNull[i - 1] <= nonNull[i], isTrue);
        }
        expect(res.length, recs.length);
      }
    });
  });

  group('grouping', () {
    test('status groups follow option order and keep empty columns (Kanban)', () {
      final res = q(ViewConfig(groupBy: const GroupBy('status')));
      expect([for (final g in res.groups!) g.key], ['todo', 'doing', 'done', null]);
      expect([for (final g in res.groups!) g.records.length], [1, 2, 1, 1]);
      expect(res.groups!.last.label, 'No value');
    });
    test('hideEmpty drops empty groups and the no-value group', () {
      final recs = [task('a', 'x', status: 'todo'), task('b', 'y')];
      final res = q(ViewConfig(groupBy: const GroupBy('status', hideEmpty: true)), records: recs);
      expect([for (final g in res.groups!) g.key], ['todo']);
    });
    test('orphaned option ids still group (shown as removed), after declared options', () {
      final res = q(ViewConfig(groupBy: const GroupBy('status')), records: [task('a', 'x', status: 'ghost')]);
      expect(res.groups!.map((g) => g.label), containsAll(['(removed)']));
    });
    test('group by date uses the day; checkbox groups', () {
      expect(q(ViewConfig(groupBy: const GroupBy('due'))).groups!.first.key, '2026-10-30');
      expect(q(ViewConfig(groupBy: const GroupBy('done'))).groups!.map((g) => g.key), ['checked', 'unchecked', null]);
    });
    test('grouping preserves in-group sort and the union of all records', () {
      final res = q(ViewConfig(groupBy: const GroupBy('status'), sorts: [const SortKey('hours', descending: true)]));
      expect(res.groups![1].records.map((r) => r.id), ['t1', 't4']);
      expect(res.records.length, 5);
    });
  });

  group('view config json', () {
    test('round trip', () {
      final v = ViewConfig(
        layout: ViewLayout.kanban,
        filter: FilterGroup(and: false, children: [c('hours', FilterOp.gt, 2), FilterGroup(children: [c('status', FilterOp.isAnyOf, ['a', 'b'])])]),
        sorts: [const SortKey('hours', descending: true)],
        groupBy: const GroupBy('status', hideEmpty: true),
        visibleProperties: ['name', 'status'],
        widths: {'name': 240},
        compact: true,
        layoutOptions: {'cardProperties': ['hours']},
      );
      final back = ViewConfig.fromJson(v.toJson());
      expect(back.toJson(), v.toJson());
      expect(back.filter.and, isFalse);
    });
    test('unknown layout / operator from a newer version degrades safely', () {
      final v = ViewConfig.fromJson({'layout': 'hologram', 'filter': {'op': 'and', 'children': [{'property': 'x', 'op': 'telepathy'}]}});
      expect(v.layout, ViewLayout.table);
      expect(v.filter.isEmpty, isTrue);
    });
    test('opsFor offers type-appropriate operators only', () {
      expect(opsFor(PropertyType.checkbox), [FilterOp.isChecked, FilterOp.isUnchecked]);
      expect(opsFor(PropertyType.date), contains(FilterOp.inNextDays));
      expect(opsFor(PropertyType.number), isNot(contains(FilterOp.contains)));
    });
  });
}
