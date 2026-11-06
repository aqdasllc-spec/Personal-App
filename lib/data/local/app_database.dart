import 'package:drift/drift.dart';

part 'app_database.g.dart';

/// First synced entity (Phase 1). The full tracker engine tables arrive in Phase 2.
class Trackers extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withDefault(const Constant(''))();
  TextColumn get icon => text().withDefault(const Constant(''))();
  TextColumn get color => text().withDefault(const Constant(''))();
  TextColumn get sortKey => text().withDefault(const Constant(''))();
  IntColumn get archivedAt => integer().nullable()();
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

@DriftDatabase(tables: [Trackers, FieldMeta, SyncOutbox, SyncState, LocalConflicts])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await customStatement('CREATE INDEX outbox_order ON sync_outbox (id)');
        },
        onUpgrade: (m, from, to) async {
          // Every schema change adds a step here and a migration test (see test/migrations).
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}
