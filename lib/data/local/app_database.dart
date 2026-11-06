import 'package:drift/drift.dart';

part 'app_database.g.dart';

/// Planner tasks - the first real synced entity. (Events, time blocks and recurrence build on this.)
@DataClassName('TaskRow')
class Tasks extends Table {
  TextColumn get id => text()();
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get notes => text().withDefault(const Constant(''))();

  /// '', 'low', 'medium' or 'high'.
  TextColumn get priority => text().withDefault(const Constant(''))();

  /// Due date/time, epoch milliseconds (UTC).
  IntColumn get dueAt => integer().nullable()();
  IntColumn get doneAt => integer().nullable()();
  TextColumn get sortKey => text().withDefault(const Constant(''))();
  IntColumn get deletedAt => integer().nullable()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// HLC of the value currently held for each synced field (generic, so entity tables
/// need no per-column clock columns).
class FieldMeta extends Table {
  TextColumn get tbl => text()();
  TextColumn get rowId => text()();
  TextColumn get field => text()();
  TextColumn get hlc => text()();

  @override
  Set<Column> get primaryKey => {tbl, rowId, field};
}

/// Local edits not yet acknowledged by the server.
class SyncOutbox extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get tbl => text()();
  TextColumn get rowId => text()();
  TextColumn get field => text()();
  TextColumn get valueJson => text().nullable()();
  TextColumn get hlc => text()();
  TextColumn get baseHlc => text().nullable()();
  TextColumn get changeId => text()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
  IntColumn get createdAt => integer()();
}

/// Key/value sync bookkeeping: device_id, cursor, last_sync_at, last_hlc, ...
class SyncState extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// Values that lost a concurrent edit (mirrors server `sync_conflicts`).
class LocalConflicts extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get serverId => integer().nullable().unique()();
  TextColumn get tbl => text()();
  TextColumn get rowId => text()();
  TextColumn get field => text()();
  TextColumn get lostValueJson => text().nullable()();
  TextColumn get lostHlc => text()();
  TextColumn get winnerHlc => text()();
  IntColumn get createdAt => integer()();
  IntColumn get resolvedAt => integer().nullable()();
}

@DriftDatabase(tables: [Tasks, FieldMeta, SyncOutbox, SyncState, LocalConflicts])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await customStatement('CREATE INDEX outbox_order ON sync_outbox (id)');
          await customStatement('CREATE INDEX tasks_due ON tasks (due_at) WHERE deleted_at IS NULL');
        },
        onUpgrade: (m, from, to) async {
          // Every schema change adds a step here and a migration test (test/data/migration_test.dart).
          if (from < 3) {
            // v3: the custom-tracker feature was removed from the product (user decision 2026-11-06).
            // Drop its tables AND every piece of sync bookkeeping that refers to them, so no pending
            // edit for a deleted table is ever pushed to the server.
            const removed = ['trackers', 'properties', 'records', 'cells', 'record_links', 'views'];
            for (final t in removed) {
              await customStatement('DROP TABLE IF EXISTS $t');
              await customStatement("DELETE FROM sync_outbox WHERE tbl = '$t'");
              await customStatement("DELETE FROM field_meta WHERE tbl = '$t'");
              await customStatement("DELETE FROM local_conflicts WHERE tbl = '$t'");
            }
            // the sync cursor now points past changes for tables we no longer keep: harmless, they are skipped on apply
            await m.createTable(tasks);
            await customStatement('CREATE INDEX tasks_due ON tasks (due_at) WHERE deleted_at IS NULL');
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}
