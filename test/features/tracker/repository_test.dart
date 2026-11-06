import 'dart:convert';

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/features/tracker/data/tracker_repository.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:tracker_engine/tracker_engine.dart' as te;

import 'tracker_helpers.dart';

void main() {
  late Env e;
  setUp(() async => e = await Env.create());
  tearDown(() => e.close());

  group('trackers & properties', () {
    test('a new tracker has a Name title property and a Table view', () async {
      final t = await e.repo.createTracker(name: '  Reading ');
      expect((await e.repo.watchTrackers().first).single.name, 'Reading');
      final props = await e.repo.properties(t);
      expect([for (final p in props) (p.name, p.type)], [('Name', te.PropertyType.text)]);
      expect(props.single.config['isTitle'], true);
      final views = await e.repo.watchViews(t).first;
      expect(views.single.$2, 'Table');
    });

    test('property names are required; formulas are validated on save', () async {
      final t = await e.repo.createTracker(name: 'X');
      await expectLater(e.repo.addProperty(t, '  ', te.PropertyType.text), throwsA(isA<CellValidationException>()));
      await expectLater(e.repo.addProperty(t, 'F', te.PropertyType.formula, config: {'formula': '1 +'}), throwsA(isA<CellValidationException>()));
      final ok = await e.repo.addProperty(t, 'F', te.PropertyType.formula, config: {'formula': '1 + 1'});
      expect(ok, isNotEmpty);
    });

    test('a formula that would create a circular reference is rejected, the old one is kept', () async {
      final t = await e.repo.createTracker(name: 'X');
      final a = await e.repo.addProperty(t, 'A', te.PropertyType.formula, config: {'formula': '1'});
      final b = await e.repo.addProperty(t, 'B', te.PropertyType.formula, config: {'formula': 'prop("$a") + 1'});
      await expectLater(e.repo.updateProperty(a, config: {'formula': 'prop("$b")'}), throwsA(isA<CellValidationException>().having((x) => x.message, 'message', contains('loop'))));
      final defs = await e.repo.properties(t);
      expect(defs.firstWhere((d) => d.id == a).formulaSource, '1');
    });

    test('deleting a property hides it and its data; restoring brings both back', () async {
      final x = await e.taskTracker();
      final r = await e.repo.createRecord(x.tracker, values: {x.p['name']!: 'A', x.p['hours']!: 5});
      await e.repo.deleteProperty(x.p['hours']!);
      var snap = await e.repo.loadSnapshot(x.tracker);
      expect(snap.property(x.p['hours']!), isNull);
      expect(snap.record(r)!.cells.containsKey(x.p['hours']), isFalse);
      await e.repo.restoreProperty(x.p['hours']!);
      snap = await e.repo.loadSnapshot(x.tracker);
      expect(snap.record(r)!.cells[x.p['hours']], 5);
    });

    test('properties keep a stable user-defined order', () async {
      final x = await e.taskTracker();
      await e.repo.moveProperty(x.p['done']!, afterPropertyId: x.p['name']);
      final order = [for (final d in await e.repo.properties(x.tracker)) d.name];
      expect(order, ['Name', 'Done?', 'Status', 'Hours', 'Due', 'Tags']);
    });
  });

  group('cells', () {
    test('typed edits are validated; failures leave data untouched and explain why', () async {
      final x = await e.taskTracker();
      final r = await e.repo.createRecord(x.tracker, values: {x.p['hours']!: 3});
      await expectLater(e.repo.setCell(r, x.p['hours']!, 'lots'), throwsA(isA<CellValidationException>().having((v) => v.message, 'msg', 'Enter a valid number.')));
      await expectLater(e.repo.setCell(r, x.p['due']!, '2026-02-31'), throwsA(isA<CellValidationException>()));
      await expectLater(e.repo.setCell(r, x.p['status']!, 'ghost'), throwsA(isA<CellValidationException>()));
      expect(await e.repo.cellValue(r, x.p['hours']!), 3);
    });

    test('setCell returns the previous value (undo), normalizes, and treats null as clear', () async {
      final x = await e.taskTracker();
      final r = await e.repo.createRecord(x.tracker);
      expect(await e.repo.setCell(r, x.p['name']!, '  Hello  '), isNull);
      expect(await e.repo.cellValue(r, x.p['name']!), 'Hello');
      expect(await e.repo.setCell(r, x.p['name']!, 'World'), 'Hello');
      expect(await e.repo.setCell(r, x.p['name']!, '   '), 'World', reason: 'blank text clears');
      expect(await e.repo.cellValue(r, x.p['name']!), isNull);
      final cells = await e.db.select(e.db.cells).get();
      expect(cells, isEmpty, reason: 'empty cells are not stored');
    });

    test('writing the same value again is a no-op (no outbox noise)', () async {
      final x = await e.taskTracker();
      final r = await e.repo.createRecord(x.tracker, values: {x.p['hours']!: 3});
      final before = (await e.db.select(e.db.syncOutbox).get()).length;
      await e.repo.setCell(r, x.p['hours']!, 3);
      await e.repo.setCell(r, x.p['hours']!, 3.0);
      expect((await e.db.select(e.db.syncOutbox).get()).length, before);
    });

    test('calculated properties cannot be edited', () async {
      final t = await e.repo.createTracker(name: 'X');
      final f = await e.repo.addProperty(t, 'F', te.PropertyType.formula, config: {'formula': '1'});
      final r = await e.repo.createRecord(t);
      await expectLater(e.repo.setCell(r, f, 5), throwsA(isA<CellValidationException>()));
    });

    test('bulk edit is atomic: one bad value changes nothing', () async {
      final x = await e.taskTracker();
      final a = await e.repo.createRecord(x.tracker, values: {x.p['status']!: 'todo'});
      final b = await e.repo.createRecord(x.tracker, values: {x.p['status']!: 'todo'});
      await expectLater(e.repo.setCellForRecords([a, b], x.p['status']!, 'nope'), throwsA(isA<CellValidationException>()));
      expect(await e.repo.cellValue(a, x.p['status']!), 'todo');
      final prev = await e.repo.setCellForRecords([a, b], x.p['status']!, 'done');
      expect(prev, {a: 'todo', b: 'todo'});
      expect(await e.repo.cellValue(b, x.p['status']!), 'done');
    });

    test('record updatedAt follows cell edits', () async {
      final x = await e.taskTracker();
      final r = await e.repo.createRecord(x.tracker);
      final t0 = (await e.repo.loadSnapshot(x.tracker)).record(r)!.updatedAt;
      await e.repo.setCell(r, x.p['hours']!, 1);
      final t1 = (await e.repo.loadSnapshot(x.tracker)).record(r)!.updatedAt;
      expect(t1.isAfter(t0), isTrue);
    });
  });

  group('records', () {
    test('order: append, insert after, move; subtasks order independently', () async {
      final x = await e.taskTracker();
      final n = x.p['name']!;
      final a = await e.repo.createRecord(x.tracker, values: {n: 'A'});
      final c = await e.repo.createRecord(x.tracker, values: {n: 'C'});
      await e.repo.createRecord(x.tracker, values: {n: 'B'}, afterRecordId: a);
      await e.repo.createRecord(x.tracker, values: {n: 'a1'}, parentId: a);
      final all = (await e.repo.queryPage(x.tracker, te.ViewConfig())).records;
      expect(all.where((r) => r.parentId == null).map((r) => r.cells[n]), ['A', 'B', 'C']);
      expect(all.singleWhere((r) => r.parentId != null).parentId, a, reason: 'subtask belongs to A');
      await e.repo.moveRecord(c, afterRecordId: null);
      final top = (await e.repo.queryPage(x.tracker, te.ViewConfig())).records.where((r) => r.parentId == null).map((r) => r.cells[n]).toList();
      expect(top, ['A', 'B', 'C']);
      await e.repo.moveRecord(c, afterRecordId: a);
      final top2 = (await e.repo.queryPage(x.tracker, te.ViewConfig())).records.where((r) => r.parentId == null).map((r) => r.cells[n]).toList();
      expect(top2, ['A', 'C', 'B']);
    });

    test('delete is soft and restorable; archive hides from default views only', () async {
      final x = await e.taskTracker();
      final n = x.p['name']!;
      final a = await e.repo.createRecord(x.tracker, values: {n: 'A'});
      final b = await e.repo.createRecord(x.tracker, values: {n: 'B'});
      await e.repo.deleteRecords([a]);
      expect(await names(e, x.tracker, n, te.ViewConfig()), ['B']);
      await e.repo.restoreRecords([a]);
      expect(await names(e, x.tracker, n, te.ViewConfig()), ['A', 'B']);
      await e.repo.archiveRecords([b], true);
      expect(await names(e, x.tracker, n, te.ViewConfig()), ['A']);
      expect(await names(e, x.tracker, n, te.ViewConfig(showArchived: true)), ['A', 'B']);
      await e.repo.archiveRecords([b], false);
      expect(await names(e, x.tracker, n, te.ViewConfig()), ['A', 'B']);
    });

    test('duplicate copies cells and sits right after the original', () async {
      final x = await e.taskTracker();
      final n = x.p['name']!;
      final a = await e.repo.createRecord(x.tracker, values: {n: 'A', x.p['hours']!: 4, x.p['tags']!: ['a', 'b']});
      await e.repo.createRecord(x.tracker, values: {n: 'Z'});
      final copy = await e.repo.duplicateRecord(a);
      final snap = await e.repo.loadSnapshot(x.tracker);
      expect(snap.records.map((r) => r.cells[n]), ['A', 'A', 'Z']);
      expect(snap.record(copy)!.cells[x.p['tags']], ['a', 'b']);
      expect(snap.records[1].id, copy);
    });

    test('records of an unknown property are ignored on create', () async {
      final x = await e.taskTracker();
      final r = await e.repo.createRecord(x.tracker, values: {'nope': 'x', x.p['name']!: 'ok'});
      expect((await e.repo.loadSnapshot(x.tracker)).record(r)!.cells, {x.p['name']: 'ok'});
    });
  });

  group('relations', () {
    test('two-way links mirror in both directions; removal soft-deletes both edges', () async {
      final tasks = await e.taskTracker();
      final proj = await e.repo.createTracker(name: 'Projects');
      final (toProj, toTasks) = await e.repo.addRelationPair(trackerA: tasks.tracker, nameA: 'Project', trackerB: proj, nameB: 'Tasks', manyA: false);
      final p1 = await e.repo.createRecord(proj);
      final t1 = await e.repo.createRecord(tasks.tracker);
      final t2 = await e.repo.createRecord(tasks.tracker);
      await e.repo.setLinks(toTasks, p1, [t1, t2]);
      expect(await e.repo.links(toProj, t1), [p1], reason: 'reverse edge created');
      expect(await e.repo.links(toTasks, p1), [t1, t2]);
      await e.repo.setLinks(toTasks, p1, [t2]);
      expect(await e.repo.links(toProj, t1), isEmpty);
      expect(await e.repo.links(toProj, t2), [p1]);
      // re-adding revives the same edge row (deterministic id) instead of piling up rows
      await e.repo.setLinks(toTasks, p1, [t1, t2]);
      final rows = await e.db.select(e.db.recordLinks).get();
      expect(rows.length, 4);
      expect(rows.where((r) => r.deletedAt == null).length, 4);
    });

    test('cardinality, wrong tracker and deleted targets are rejected', () async {
      final tasks = await e.taskTracker();
      final proj = await e.repo.createTracker(name: 'Projects');
      final (toProj, _) = await e.repo.addRelationPair(trackerA: tasks.tracker, nameA: 'Project', trackerB: proj, nameB: 'Tasks', manyA: false);
      final p1 = await e.repo.createRecord(proj), p2 = await e.repo.createRecord(proj);
      final t1 = await e.repo.createRecord(tasks.tracker);
      await expectLater(e.repo.setLinks(toProj, t1, [p1, p2]), throwsA(isA<CellValidationException>().having((x) => x.message, 'm', contains('only one'))));
      await expectLater(e.repo.setLinks(toProj, t1, [t1]), throwsA(isA<CellValidationException>().having((x) => x.message, 'm', contains('different tracker'))));
      await e.repo.deleteRecords([p2]);
      await expectLater(e.repo.setLinks(toProj, t1, [p2]), throwsA(isA<CellValidationException>().having((x) => x.message, 'm', contains('no longer exists'))));
    });

    test('duplicate keeps relation links', () async {
      final tasks = await e.taskTracker();
      final proj = await e.repo.createTracker(name: 'Projects');
      final (toProj, _) = await e.repo.addRelationPair(trackerA: tasks.tracker, nameA: 'Project', trackerB: proj, nameB: 'Tasks');
      final p1 = await e.repo.createRecord(proj);
      final t1 = await e.repo.createRecord(tasks.tracker);
      await e.repo.setLinks(toProj, t1, [p1]);
      final copy = await e.repo.duplicateRecord(t1);
      expect(await e.repo.links(toProj, copy), [p1]);
    });
  });

  group('views', () {
    test('create, update, reorder-safe delete; the last view can not be deleted', () async {
      final t = await e.repo.createTracker(name: 'X');
      final v2 = await e.repo.createView(t, 'Board', te.ViewConfig(layout: te.ViewLayout.kanban));
      var views = await e.repo.watchViews(t).first;
      expect(views.map((v) => v.$2), ['Table', 'Board']);
      expect(views[1].$3.layout, te.ViewLayout.kanban);
      await e.repo.updateView(v2, name: 'Status board', config: te.ViewConfig(layout: te.ViewLayout.list));
      views = await e.repo.watchViews(t).first;
      expect((views[1].$2, views[1].$3.layout), ('Status board', te.ViewLayout.list));
      await e.repo.deleteView(v2);
      await expectLater(e.repo.deleteView(views[0].$1), throwsA(isA<CellValidationException>()));
      expect((await e.repo.watchViews(t).first).length, 1);
    });

    test('views own no records: creating/deleting views never changes the data', () async {
      final x = await e.taskTracker();
      await e.repo.createRecord(x.tracker, values: {x.p['name']!: 'A'});
      final before = await e.db.select(e.db.records).get();
      final v = await e.repo.createView(x.tracker, 'Another', te.ViewConfig(filter: te.FilterGroup(children: [te.FilterCondition(propertyId: x.p['name']!, op: te.FilterOp.isEmpty)])));
      await e.repo.deleteView(v);
      expect((await e.db.select(e.db.records).get()).length, before.length);
      expect((await e.db.select(e.db.cells).get()).length, 1);
    });

    test('a corrupt saved view falls back to a default view instead of breaking the tracker', () async {
      final t = await e.repo.createTracker(name: 'X');
      final id = (await e.db.select(e.db.trackerViews).getSingle()).id;
      await e.db.customStatement("UPDATE views SET config_json = 'not json' WHERE id = '$id'");
      expect((await e.repo.watchViews(t).first).single.$3.layout, te.ViewLayout.table);
    });
  });

  group('templates', () {
    test('Goals · Projects · Tasks is created with linked trackers, views and working progress rollups', () async {
      final ids = await e.repo.createFromTemplate(te.goalsProjectsTasks);
      expect(ids.length, 3);
      final trackers = {for (final t in await e.repo.watchTrackers().first) t.name: t.id};
      expect(trackers.keys, containsAll(['Goals', 'Projects', 'Tasks']));
      final taskProps = {for (final p in await e.repo.properties(trackers['Tasks']!)) p.name: p};
      final projProps = {for (final p in await e.repo.properties(trackers['Projects']!)) p.name: p};
      expect(taskProps['Project']!.relationTargetTrackerId, trackers['Projects']);
      expect(taskProps['Project']!.config['pairPropertyId'], projProps['Tasks']!.id, reason: 'pair ids remapped');
      expect((await e.repo.watchViews(trackers['Tasks']!).first).map((v) => v.$2), ['All tasks', 'Board', 'Calendar', 'Milestones']);

      final proj = await e.repo.createRecord(trackers['Projects']!, values: {projProps['Project']!.id: 'Thesis'});
      final tasks = [for (var i = 0; i < 4; i++) await e.repo.createRecord(trackers['Tasks']!, values: {taskProps['Task']!.id: 'T$i', taskProps['Status']!.id: i < 3 ? 'done' : 'doing'})];
      await e.repo.setLinks(projProps['Tasks']!.id, proj, tasks);
      final snap = await e.repo.loadSnapshot(trackers['Projects']!);
      expect(te.Computed(snap).valueOf(snap.record(proj)!, snap.property(projProps['Progress']!.id)!), 75);
      // and the reverse relation is readable from a task
      expect(await e.repo.links(taskProps['Project']!.id, tasks.first), [proj]);
    });

    test('all built-in templates can be applied', () async {
      for (final t in te.builtInTemplates) {
        final ids = await e.repo.createFromTemplate(t);
        expect(ids, isNotEmpty, reason: t.id);
      }
      expect((await e.repo.watchTrackers().first).length, greaterThan(5));
    });
  });

  group('sync records for every write', () {
    test('each field of a created record is one outbox entry with a causal base for later edits', () async {
      final x = await e.taskTracker();
      final r = await e.repo.createRecord(x.tracker, values: {x.p['hours']!: 1});
      await e.repo.setCell(r, x.p['hours']!, 2);
      final rows = await (e.db.select(e.db.syncOutbox)..orderBy([(o) => OrderingTerm.asc(o.id)])).get();
      final cellEdits = rows.where((o) => o.tbl == 'cells' && o.rowId == '$r:${x.p['hours']}').toList();
      expect(cellEdits.length, 2);
      expect(cellEdits[1].baseHlc, cellEdits[0].hlc);
      expect(jsonDecode(cellEdits[1].valueJson!), 2);
    });
  });

  group('two devices', () {
    test('tracker, properties, records and cells replicate; both devices query the same rows', () async {
      final server = FakeServer();
      final a = await Env.create(server: server, device: 'devA');
      final b = await Env.create(server: server, device: 'devB');
      addTearDown(a.close);
      addTearDown(b.close);
      final x = await a.taskTracker();
      final r1 = await a.repo.createRecord(x.tracker, values: {x.p['name']!: 'Write', x.p['hours']!: 3, x.p['status']!: 'doing', x.p['tags']!: ['a'], x.p['due']!: '2026-11-08'});
      await a.repo.createRecord(x.tracker, values: {x.p['name']!: 'Read', x.p['hours']!: 1});
      await a.sync.sync();
      await b.sync.sync();
      final view = te.ViewConfig(sorts: [te.SortKey(x.p['hours']!)], filter: te.FilterGroup(children: [te.FilterCondition(propertyId: x.p['hours']!, op: te.FilterOp.gte, value: 1)]));
      final onA = await names(a, x.tracker, x.p['name']!, view);
      final onB = await names(b, x.tracker, x.p['name']!, view);
      expect(onB, ['Read', 'Write']);
      expect(onB, onA);
      final snapB = await b.repo.loadSnapshot(x.tracker);
      expect(snapB.record(r1)!.cells[x.p['tags']], ['a']);
      expect([for (final d in snapB.properties) d.name], ['Name', 'Status', 'Hours', 'Due', 'Tags', 'Done?']);
    });

    test('same cell edited offline on both devices: later wins, the other value is kept in the conflict log', () async {
      final server = FakeServer();
      final a = await Env.create(server: server, device: 'devA');
      final b = await Env.create(server: server, device: 'devB');
      addTearDown(a.close);
      addTearDown(b.close);
      final x = await a.taskTracker();
      final r = await a.repo.createRecord(x.tracker, values: {x.p['hours']!: 1});
      await a.sync.sync();
      await b.sync.sync();
      await a.repo.setCell(r, x.p['hours']!, 10);
      await b.repo.setCell(r, x.p['hours']!, 20); // later in time
      for (final d in [a, b, a, b]) {
        await d.sync.sync();
      }
      expect(await a.repo.cellValue(r, x.p['hours']!), 20);
      expect(await b.repo.cellValue(r, x.p['hours']!), 20);
      final lost = await a.db.select(a.db.localConflicts).get();
      expect(lost.map((c) => c.lostValueJson), ['10']);
    });

    test('different cells of one record edited on two devices merge without conflict', () async {
      final server = FakeServer();
      final a = await Env.create(server: server, device: 'devA');
      final b = await Env.create(server: server, device: 'devB');
      addTearDown(a.close);
      addTearDown(b.close);
      final x = await a.taskTracker();
      final r = await a.repo.createRecord(x.tracker, values: {x.p['name']!: 'T'});
      await a.sync.sync();
      await b.sync.sync();
      await a.repo.setCell(r, x.p['hours']!, 5);
      await b.repo.setCell(r, x.p['status']!, 'done');
      for (final d in [a, b, a, b]) {
        await d.sync.sync();
      }
      for (final d in [a, b]) {
        expect(await d.repo.cellValue(r, x.p['hours']!), 5);
        expect(await d.repo.cellValue(r, x.p['status']!), 'done');
      }
      expect(server.conflicts, isEmpty);
    });

    test('a record deleted on one device disappears on the other; edit-after-delete stays deleted until restored', () async {
      final server = FakeServer();
      final a = await Env.create(server: server, device: 'devA');
      final b = await Env.create(server: server, device: 'devB');
      addTearDown(a.close);
      addTearDown(b.close);
      final x = await a.taskTracker();
      final r = await a.repo.createRecord(x.tracker, values: {x.p['name']!: 'T'});
      await a.sync.sync();
      await b.sync.sync();
      await a.repo.deleteRecords([r]);
      await a.sync.sync();
      await b.sync.sync();
      expect(await names(b, x.tracker, x.p['name']!, te.ViewConfig()), isEmpty);
      await b.repo.restoreRecords([r]);
      await b.sync.sync();
      await a.sync.sync();
      expect(await names(a, x.tracker, x.p['name']!, te.ViewConfig()), ['T']);
    });

    test('a cell that arrives BEFORE its property definition becomes queryable once the property arrives', () async {
      final x = await e.taskTracker();
      final rec = await e.repo.createRecord(x.tracker, values: {x.p['name']!: 'T'});
      // simulate device B having received only the cell first: apply a remote cell for a property we don't have yet
      const lateProp = 'late-prop';
      final hlc = Hlc(e.store.clock.latest.wall + 1000, 0, 'devX');
      await e.store.applyRemote(Change(key: FieldKey('cells', '$rec:$lateProp', 'value'), value: 42, hlc: hlc, baseHlc: null, deviceId: 'devX', changeId: 'c1'));
      var cell = await (e.db.select(e.db.cells)..where((c) => c.propertyId.equals(lateProp))).getSingle();
      expect(cell.raw, '42', reason: 'raw value kept');
      expect(cell.vNum, isNull, reason: 'typed columns not derivable until the property is known');
      // now the property definition arrives
      final h2 = Hlc(hlc.wall + 1, 0, 'devX');
      await e.store.applyRemote(Change(key: const FieldKey('properties', lateProp, 'tracker_id'), value: x.tracker, hlc: h2, baseHlc: null, deviceId: 'devX', changeId: 'c2'));
      await e.store.applyRemote(Change(key: const FieldKey('properties', lateProp, 'name'), value: 'Late', hlc: Hlc(h2.wall, 1, 'devX'), baseHlc: null, deviceId: 'devX', changeId: 'c3'));
      await e.store.applyRemote(Change(key: const FieldKey('properties', lateProp, 'type'), value: 'number', hlc: Hlc(h2.wall, 2, 'devX'), baseHlc: null, deviceId: 'devX', changeId: 'c4'));
      cell = await (e.db.select(e.db.cells)..where((c) => c.propertyId.equals(lateProp))).getSingle();
      expect(cell.vNum, 42.0, reason: 'reindexed when the type became known');
      final v = te.ViewConfig(filter: te.FilterGroup(children: [te.FilterCondition(propertyId: lateProp, op: te.FilterOp.gt, value: 40)]));
      expect((await e.repo.queryPage(x.tracker, v)).records.map((r) => r.id), [rec]);
    });
  });
}
