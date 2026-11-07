import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/data/local/database_opener.dart';

import '../generated_migrations/schema.dart';

/// Every released schema version is snapshotted in drift_schemas/. When you bump `schemaVersion`:
/// dump + regenerate (see docs/DEVELOPMENT.md), add the upgrade step in AppDatabase.migration, and
/// add a `from N` test below that seeds data at version N and checks it survives.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;
  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  test('a fresh install matches the committed schema for the current version exactly', () async {
    final current = openInMemory().schemaVersion;
    final connection = await verifier.startAt(current);
    final db = AppDatabase(connection);
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, current);
  });

  test('every committed snapshot up to the current version exists (forgot to dump?)', () {
    final db = openInMemory();
    addTearDown(db.close);
    expect(GeneratedHelper.versions, [for (var v = 1; v <= db.schemaVersion; v++) v]);
  });

  /// Data a v1/v2 install would have: tracker tables, sync bookkeeping for them, and device state.
  void seedLegacy(dynamic raw, {required bool v2}) {
    raw.execute("INSERT INTO trackers (id, name, icon, color, sort_key, created_at) VALUES ('t1', 'Reading', 'book', 'teal', 'a', 1700000000000)");
    raw.execute("INSERT INTO field_meta (tbl, row_id, field, hlc) VALUES ('trackers', 't1', 'name', '00018bcfe56a-0000-dev')");
    raw.execute("INSERT INTO sync_outbox (tbl, row_id, field, value_json, hlc, change_id, created_at) VALUES ('trackers', 't1', 'name', '\"Reading\"', '00018bcfe56a-0000-dev', 'c1', 1)");
    raw.execute("INSERT INTO local_conflicts (server_id, tbl, row_id, field, lost_value_json, lost_hlc, winner_hlc, created_at) VALUES (1, 'trackers', 't1', 'name', '\"x\"', 'a', 'b', 1)");
    raw.execute("INSERT INTO sync_state (key, value) VALUES ('device_id', 'dev-1'), ('cursor', '42')");
    if (v2) {
      raw.execute("INSERT INTO records (id, tracker_id, sort_key, created_at) VALUES ('r1', 't1', 'a', 1)");
      raw.execute("INSERT INTO cells (record_id, property_id, raw) VALUES ('r1', 'p1', '\"x\"')");
      raw.execute("INSERT INTO sync_outbox (tbl, row_id, field, value_json, hlc, change_id, created_at) VALUES ('cells', 'r1:p1', 'value', '\"x\"', '00018bcfe56b-0000-dev', 'c2', 2)");
    }
  }

  for (final from in [1, 2]) {
    test('upgrade from v$from: removed tracker tables and their sync records are gone, device identity and the sync cursor survive', () async {
      final schema = await verifier.schemaAt(from);
      seedLegacy(schema.rawDatabase, v2: from == 2);

      final db = AppDatabase(schema.newConnection());
      addTearDown(db.close);
      await verifier.migrateAndValidate(db, db.schemaVersion);

      final tables = (await db.customSelect("SELECT name FROM sqlite_master WHERE type = 'table'").get()).map((r) => r.read<String>('name')).toSet();
      for (final gone in ['trackers', 'properties', 'records', 'cells', 'record_links', 'views']) {
        expect(tables, isNot(contains(gone)), reason: '$gone should be dropped');
      }
      expect(tables, containsAll(['tasks', 'events']));
      // nothing for a deleted table may remain to be pushed to the server
      expect(await db.select(db.syncOutbox).get(), isEmpty, reason: 'pending edits for removed tables must not survive');
      expect(await db.select(db.fieldMeta).get(), isEmpty);
      expect(await db.select(db.localConflicts).get(), isEmpty);
      final state = {for (final r in await db.select(db.syncState).get()) r.key: r.value};
      expect(state, {'device_id': 'dev-1', 'cursor': '42'}, reason: 'this device keeps its identity and position in the change feed');
      // the new tables work end to end
      await db.customStatement("INSERT INTO tasks (id, title, created_at) VALUES ('k1', 'first task', 1)");
      final task = await db.select(db.tasks).getSingle();
      expect((task.title, task.dueHasTime, task.rrule, task.remindMinutes), ('first task', 0, '', null));
      await db.customStatement("INSERT INTO events (id, title, start_at, end_at, created_at) VALUES ('e1', 'meet', 1, 2, 1)");
      expect((await db.select(db.events).getSingle()).title, 'meet');
    });
  }

  test('upgrade from v3 keeps every task and every pending sync edit, and gives them the new column defaults', () async {
    final schema = await verifier.schemaAt(3);
    final raw = schema.rawDatabase;
    raw.execute("INSERT INTO tasks (id, title, notes, priority, due_at, done_at, sort_key, created_at) VALUES ('t1', 'Pay rent', 'monthly', 'high', 1700000000000, NULL, 'a', 1699999999999)");
    raw.execute("INSERT INTO tasks (id, title, done_at, created_at) VALUES ('t2', 'Done thing', 1700000001000, 1)");
    raw.execute("INSERT INTO field_meta (tbl, row_id, field, hlc) VALUES ('tasks', 't1', 'title', '00018bcfe56a-0000-dev')");
    raw.execute("INSERT INTO sync_outbox (tbl, row_id, field, value_json, hlc, change_id, created_at) VALUES ('tasks', 't1', 'title', '\"Pay rent\"', '00018bcfe56a-0000-dev', 'c1', 1)");
    raw.execute("INSERT INTO sync_state (key, value) VALUES ('device_id', 'dev-1')");

    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, db.schemaVersion);

    final tasks = {for (final t in await db.select(db.tasks).get()) t.id: t};
    expect(tasks.keys, {'t1', 't2'});
    expect((tasks['t1']!.title, tasks['t1']!.notes, tasks['t1']!.priority, tasks['t1']!.dueAt), ('Pay rent', 'monthly', 'high', 1700000000000));
    expect(tasks['t2']!.doneAt, 1700000001000);
    for (final t in tasks.values) {
      expect((t.dueHasTime, t.plannedAt, t.plannedMinutes, t.rrule, t.remindMinutes), (0, null, null, '', null), reason: 'new columns get safe defaults');
      expect(t.checklist, '[]', reason: 'sub-tasks start empty');
    }
    expect(await db.select(db.syncOutbox).get(), hasLength(1), reason: 'an un-synced edit must survive the upgrade');
    expect(await db.select(db.fieldMeta).get(), hasLength(1));
    final idx = (await db.customSelect("SELECT name FROM sqlite_master WHERE type = 'index'").get()).map((r) => r.read<String>('name')).toSet();
    expect(idx, containsAll(['tasks_due', 'tasks_planned', 'events_start']));
  });
}
