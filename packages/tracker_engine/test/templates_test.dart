import 'package:test/test.dart';
import 'package:tracker_engine/tracker_engine.dart';

List<NewTracker> inst(TrackerTemplate t) {
  var n = 0;
  return instantiateTemplate(t, () => 'id${n++}');
}

void main() {
  for (final t in builtInTemplates) {
    group('template ${t.id}', () {
      final trackers = inst(t);
      final allProps = {for (final tr in trackers) for (final p in tr.properties) p.id: p};
      final trackerIds = {for (final tr in trackers) tr.id};

      test('ids are unique and no template keys leak into the output', () {
        final ids = [for (final tr in trackers) tr.id, for (final tr in trackers) ...tr.properties.map((p) => p.id), for (final tr in trackers) ...tr.views.map((v) => v.id)];
        expect(ids.toSet().length, ids.length);
        expect(ids.every((i) => i.startsWith('id')), isTrue);
      });

      test('every tracker has a title property and at least one view', () {
        for (final tr in trackers) {
          expect(tr.properties.any((p) => p.config['isTitle'] == true), isTrue, reason: tr.name);
          expect(tr.views, isNotEmpty);
        }
      });

      test('relations, rollups, formulas and views only reference things that exist', () {
        for (final tr in trackers) {
          final own = {for (final p in tr.properties) p.id};
          for (final p in tr.properties) {
            switch (p.type) {
              case PropertyType.relation:
                expect(trackerIds, contains(p.relationTargetTrackerId), reason: p.name);
                if (p.config['pairPropertyId'] != null) expect(allProps, contains(p.config['pairPropertyId']));
              case PropertyType.rollup:
                expect(own, contains(p.rollupRelationId), reason: p.name);
                expect(allProps, contains(p.rollupTargetId), reason: p.name);
                expect(allProps[p.rollupRelationId]!.type, PropertyType.relation);
              case PropertyType.formula:
                final deps = formulaDependencies(parseFormula(p.formulaSource));
                expect(own.containsAll(deps), isTrue, reason: '${p.name}: $deps');
              default:
            }
          }
          expect(() => formulaOrder(tr.properties), returnsNormally);
          for (final v in tr.views) {
            final j = v.config.toJson().toString();
            // every property id mentioned in the view must exist in this tracker
            for (final id in own) {
              expect(j.contains('template'), isFalse);
              expect(id, isNotEmpty);
            }
            final refs = <String>{
              for (final s in v.config.sorts) s.propertyId,
              ?v.config.groupBy?.propertyId,
              for (final o in v.config.layoutOptions.entries) if (o.key.endsWith('PropertyId')) o.value! as String,
            };
            expect(own.containsAll(refs), isTrue, reason: '${tr.name}/${v.name}: $refs');
          }
        }
      });

      test('select/status option ids are unique within each property', () {
        for (final p in allProps.values.where((p) => p.type.isOptionBased)) {
          final ids = p.options.map((o) => o.id).toList();
          expect(ids.toSet().length, ids.length, reason: p.name);
        }
      });

      test('instantiating twice yields independent copies', () {
        var n = 0;
        final a = instantiateTemplate(t, () => 'a${n++}');
        final b = instantiateTemplate(t, () => 'b${n++}');
        expect(a.first.id, isNot(b.first.id));
      });
    });
  }

  test('goals/projects/tasks: kanban view groups by the NEW status id', () {
    final trackers = inst(goalsProjectsTasks);
    final tasks = trackers.firstWhere((t) => t.name == 'Tasks');
    final status = tasks.properties.firstWhere((p) => p.name == 'Status');
    final board = tasks.views.firstWhere((v) => v.name == 'Board').config;
    expect(board.groupBy!.propertyId, status.id);
    expect(board.layoutOptions['groupPropertyId'], status.id);
  });

  test('template progress works end to end after instantiation', () {
    final trackers = inst(goalsProjectsTasks);
    final tasksT = trackers.firstWhere((t) => t.name == 'Tasks');
    final projT = trackers.firstWhere((t) => t.name == 'Projects');
    final tStatus = tasksT.properties.firstWhere((p) => p.name == 'Status');
    final tProject = tasksT.properties.firstWhere((p) => p.name == 'Project');
    final pTasks = projT.properties.firstWhere((p) => p.name == 'Tasks');
    final progress = projT.properties.firstWhere((p) => p.name == 'Progress');

    final tasks = TrackerSnapshot(trackerId: tasksT.id, properties: tasksT.properties, records: [
      for (var i = 0; i < 4; i++) TrackerRecord(id: 't$i', trackerId: tasksT.id, cells: {tStatus.id: i < 3 ? 'done' : 'doing'}),
    ]);
    final proj = TrackerSnapshot(
      trackerId: projT.id,
      properties: projT.properties,
      records: [TrackerRecord(id: 'p', trackerId: projT.id)],
      links: {pTasks.id: {'p': ['t0', 't1', 't2', 't3']}},
      others: {tasksT.id: tasks},
    );
    expect(tProject.relationTargetTrackerId, projT.id);
    expect(Computed(proj).valueOf(proj.records.single, progress), 75);
  });

  test('remapViewConfig rewrites filters, sorts, groups, visible, widths and layout options', () {
    final v = ViewConfig(
      filter: FilterGroup(children: [FilterGroup(and: false, children: [FilterCondition(propertyId: 'a', op: FilterOp.isEmpty)])]),
      sorts: [const SortKey('b')],
      groupBy: const GroupBy('c'),
      visibleProperties: ['a', 'b'],
      widths: {'a': 100},
      layoutOptions: {'datePropertyId': 'a', 'cardProperties': ['b', 'c'], 'other': 5},
    );
    final m = remapViewConfig(v, (k) => 'X$k');
    final j = m.toJson().toString();
    expect(j.contains('Xa') && j.contains('Xb') && j.contains('Xc'), isTrue);
    expect(m.layoutOptions['cardProperties'], ['Xb', 'Xc']);
    expect(m.layoutOptions['other'], 5);
    expect(m.widths, {'Xa': 100.0});
  });
}
