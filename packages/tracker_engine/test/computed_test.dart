import 'package:test/test.dart';
import 'package:tracker_engine/tracker_engine.dart';

import 'fixtures.dart';

void main() {
  group('formula properties over records', () {
    test('computed per record from stored cells; empty inputs give a formula error, not a crash', () {
      final s = tasksSnapshot();
      final c = Computed(s, now: now);
      final def = s.property('daysLeft')!;
      expect(c.valueOf(s.record('t1')!, def), 2);
      expect(c.valueOf(s.record('t2')!, def), 0);
      expect(c.valueOf(s.record('t3')!, def), -7);
      expect(c.valueOf(s.record('t5')!, def), isA<FormulaError>());
    });

    test('formulas can use other formulas, select labels, checkboxes and multi-select', () {
      final props = [
        ...taskProps,
        const PropertyDef(id: 'f2', name: 'Label', type: PropertyType.formula, config: {'formula': 'concat(prop("status"), ": ", prop("name"), if(prop("done"), " ✓", ""))'}),
        const PropertyDef(id: 'f3', name: 'Late', type: PropertyType.formula, config: {'formula': 'prop("daysLeft") < 0 and prop("status") != "Done"'}),
        const PropertyDef(id: 'f4', name: 'Tag list', type: PropertyType.formula, config: {'formula': 'join(prop("tags"), "/")'}),
      ];
      final s = TrackerSnapshot(trackerId: 'tasks', properties: props, records: sampleTasks());
      final c = Computed(s, now: now);
      expect(c.valueOf(s.record('t3')!, s.property('f2')!), 'Done: File taxes ✓');
      expect(c.valueOf(s.record('t3')!, s.property('f3')!), false, reason: 'overdue but done');
      expect(c.valueOf(s.record('t2')!, s.property('f4')!), 'Home/Urgent');
    });

    test('an error in a dependency propagates (no stale or fake value)', () {
      final props = [
        const PropertyDef(id: 'a', name: 'A', type: PropertyType.formula, config: {'formula': '1/0'}),
        const PropertyDef(id: 'b', name: 'B', type: PropertyType.formula, config: {'formula': 'prop("a") + 1'}),
      ];
      final s = TrackerSnapshot(trackerId: 't', properties: props, records: [TrackerRecord(id: 'r', trackerId: 't')]);
      expect(Computed(s).valueOf(s.records.single, props[1]), const FormulaError('#DIV0'));
    });

    test('a formula loop evaluates to an error instead of hanging', () {
      final props = [
        const PropertyDef(id: 'a', name: 'A', type: PropertyType.formula, config: {'formula': 'prop("b")'}),
        const PropertyDef(id: 'b', name: 'B', type: PropertyType.formula, config: {'formula': 'prop("a")'}),
      ];
      final s = TrackerSnapshot(trackerId: 't', properties: props, records: [TrackerRecord(id: 'r', trackerId: 't')]);
      expect(Computed(s).valueOf(s.records.single, props[0]), isA<FormulaError>());
    });

    test('created / last edited come from record metadata', () {
      final r = TrackerRecord(id: 'r', trackerId: 't', createdAt: DateTime.utc(2026, 1, 2), updatedAt: DateTime.utc(2026, 3, 4, 5));
      final s = TrackerSnapshot(trackerId: 't', properties: const [], records: [r]);
      final c = Computed(s);
      expect(c.valueOf(r, const PropertyDef(id: 'c', name: 'C', type: PropertyType.createdTime)), '2026-01-02T00:00:00.000Z');
      expect(c.valueOf(r, const PropertyDef(id: 'e', name: 'E', type: PropertyType.lastEditedTime)), '2026-03-04T05:00:00.000Z');
    });
  });

  group('rollups', () {
    // projects -> tasks
    final projProps = [
      const PropertyDef(id: 'pname', name: 'Project', type: PropertyType.text),
      const PropertyDef(id: 'tasks', name: 'Tasks', type: PropertyType.relation, config: {'targetTrackerId': 'tasks'}),
      const PropertyDef(id: 'pct', name: '% done', type: PropertyType.rollup, config: {'relationPropertyId': 'tasks', 'targetPropertyId': 'status', 'aggregate': 'percentComplete'}),
      const PropertyDef(id: 'hrs', name: 'Hours', type: PropertyType.rollup, config: {'relationPropertyId': 'tasks', 'targetPropertyId': 'hours', 'aggregate': 'sum'}),
      const PropertyDef(id: 'avg', name: 'Avg', type: PropertyType.rollup, config: {'relationPropertyId': 'tasks', 'targetPropertyId': 'hours', 'aggregate': 'avg'}),
      const PropertyDef(id: 'med', name: 'Median', type: PropertyType.rollup, config: {'relationPropertyId': 'tasks', 'targetPropertyId': 'hours', 'aggregate': 'median'}),
      const PropertyDef(id: 'cnt', name: 'Count', type: PropertyType.rollup, config: {'relationPropertyId': 'tasks', 'aggregate': 'count'}),
      const PropertyDef(id: 'uniq', name: 'Statuses', type: PropertyType.rollup, config: {'relationPropertyId': 'tasks', 'targetPropertyId': 'status', 'aggregate': 'countUnique'}),
      const PropertyDef(id: 'first', name: 'Next due', type: PropertyType.rollup, config: {'relationPropertyId': 'tasks', 'targetPropertyId': 'due', 'aggregate': 'earliest'}),
      const PropertyDef(id: 'names', name: 'Names', type: PropertyType.rollup, config: {'relationPropertyId': 'tasks', 'targetPropertyId': 'name', 'aggregate': 'showOriginal'}),
      const PropertyDef(id: 'late', name: 'Overdue tasks', type: PropertyType.rollup, config: {'relationPropertyId': 'tasks', 'targetPropertyId': 'daysLeft', 'aggregate': 'min'}),
      const PropertyDef(id: 'bad', name: 'Broken', type: PropertyType.rollup, config: {'relationPropertyId': 'nope', 'aggregate': 'count'}),
    ];
    TrackerSnapshot projects({Map<String, List<String>>? links, List<TrackerRecord>? tasks}) {
      final ts = tasksSnapshot(tasks);
      return TrackerSnapshot(
        trackerId: 'projects',
        properties: projProps,
        records: [TrackerRecord(id: 'p1', trackerId: 'projects'), TrackerRecord(id: 'p2', trackerId: 'projects')],
        links: {'tasks': links ?? {'p1': ['t1', 't2', 't3', 't6'], 'p2': []}},
        others: {'tasks': ts},
      );
    }

    CellValue roll(TrackerSnapshot s, String rec, String prop) => Computed(s, now: now).valueOf(s.record(rec)!, s.property(prop)!);

    test('aggregates over related records; archived related records are excluded', () {
      final s = projects();
      expect(roll(s, 'p1', 'cnt'), 3, reason: 't6 is archived');
      expect(roll(s, 'p1', 'pct'), closeTo(33.33, .01), reason: '1 of 3 complete');
      expect(roll(s, 'p1', 'hrs'), 6.5);
      expect(roll(s, 'p1', 'avg'), closeTo(2.1667, .001));
      expect(roll(s, 'p1', 'med'), 2);
      expect(roll(s, 'p1', 'uniq'), 3);
      expect(roll(s, 'p1', 'first'), '2026-10-30');
      expect(roll(s, 'p1', 'names'), ['Write intro', 'Éclair recipe', 'File taxes']);
      expect(roll(s, 'p1', 'late'), -7, reason: 'rollup of a formula in the related tracker');
    });
    test('empty relation: counts are 0, averages/percent are empty, never NaN', () {
      final s = projects();
      expect(roll(s, 'p2', 'cnt'), 0);
      expect(roll(s, 'p2', 'hrs'), 0);
      expect(roll(s, 'p2', 'avg'), isNull);
      expect(roll(s, 'p2', 'pct'), isNull);
      expect(roll(s, 'p2', 'first'), isNull);
    });
    test('misconfigured rollup yields an error value, not an exception', () {
      expect(roll(projects(), 'p1', 'bad'), isA<FormulaError>());
    });
    test('a link to a deleted record is ignored', () {
      final s = projects(links: {'p1': ['t1', 'ghost']});
      expect(roll(s, 'p1', 'cnt'), 1);
    });
    test('rollup values can themselves be filtered and sorted', () {
      final s = projects();
      final res = runQuery(s, ViewConfig(sorts: [const SortKey('pct', descending: true)]), now: now);
      expect(res.records.map((r) => r.id), ['p1', 'p2'], reason: 'empty rollup sorts last');
      final res2 = runQuery(s, ViewConfig(filter: FilterGroup(children: [FilterCondition(propertyId: 'hrs', op: FilterOp.gt, value: 5)])), now: now);
      expect(res2.records.map((r) => r.id), ['p1']);
    });
    test('automatic progress chain: tasks -> project % -> goal average', () {
      final ps = projects();
      final goalProps = [
        const PropertyDef(id: 'projs', name: 'Projects', type: PropertyType.relation, config: {'targetTrackerId': 'projects'}),
        const PropertyDef(id: 'gp', name: 'Progress', type: PropertyType.rollup, config: {'relationPropertyId': 'projs', 'targetPropertyId': 'pct', 'aggregate': 'avg'}),
      ];
      final goals = TrackerSnapshot(
        trackerId: 'goals',
        properties: goalProps,
        records: [TrackerRecord(id: 'g1', trackerId: 'goals')],
        links: {'projs': {'g1': ['p1', 'p2']}},
        others: {'projects': ps},
      );
      // p1 = 33.33, p2 has no tasks (empty) -> average over non-empty = 33.33
      expect(Computed(goals, now: now).valueOf(goals.record('g1')!, goalProps[1]) as num, closeTo(33.33, .01));
      // complete the remaining tasks and progress becomes 100
      final all = sampleTasks().map((r) => task(r.id, r.cells['name'] as String, status: 'done', hours: r.cells['hours'] as num?, archived: r.archived)).toList();
      final ps2 = projects(tasks: all);
      final goals2 = TrackerSnapshot(trackerId: 'goals', properties: goalProps, records: goals.records, links: goals.links, others: {'projects': ps2});
      expect(Computed(goals2, now: now).valueOf(goals2.record('g1')!, goalProps[1]), 100);
    });
  });
}
