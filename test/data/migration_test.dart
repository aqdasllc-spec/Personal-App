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

  test('upgrade from v1 keeps existing data, creates the tracker-engine tables and indexes', () async {
    final schema = await verifier.schemaAt(1);
    // seed data as a v1 install would have it
    schema.rawDatabase.execute("INSERT INTO trackers (id, name, icon, color, sort_key, created_at) VALUES ('t1', 'Reading', 'book', 'teal', 'a', 1700000000000)");
    schema.rawDatabase.execute("INSERT INTO field_meta (tbl, row_id, field, hlc) VALUES ('trackers', 't1', 'name', '00018bcfe56a-0000-dev')");
    schema.rawDatabase.execute("INSERT INTO sync_outbox (tbl, row_id, field, value_json, hlc, change_id, created_at) VALUES ('trackers', 't1', 'name', '\"Reading\"', '00018bcfe56a-0000-dev', 'c1', 1)");
    schema.rawDatabase.execute("INSERT INTO sync_state (key, value) VALUES ('device_id', 'dev-1')");

    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 2);

    final t = await db.select(db.trackers).getSingle();
    expect((t.id, t.name, t.icon), ('t1', 'Reading', 'book'));
    expect((await db.select(db.syncOutbox).get()), hasLength(1), reason: 'pending sync edits survive an upgrade');
    expect((await db.select(db.syncState).getSingle()).value, 'dev-1');

    // the new tables are usable and the performance indexes exist
    await db.customStatement("INSERT INTO records (id, tracker_id, sort_key, created_at) VALUES ('r1', 't1', 'a', 1)");
    final idx = await db.customSelect("SELECT name FROM sqlite_master WHERE type = 'index' AND name LIKE 'cells_prop_%'").get();
    expect(idx.length, 4);
  });
}
