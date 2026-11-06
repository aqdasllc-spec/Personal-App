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

/// Column definitions of a tracker.
@DataClassName('PropertyRow')
class Properties extends Table {
  TextColumn get id => text()();
  TextColumn get trackerId => text().withDefault(const Constant(''))();
  TextColumn get name => text().withDefault(const Constant(''))();
  TextColumn get type => text().withDefault(const Constant('text'))();
  TextColumn get configJson => text().withDefault(const Constant('{}'))();
  TextColumn get sortKey => text().withDefault(const Constant(''))();
  IntColumn get deletedAt => integer().nullable()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('RecordRow')
class Records extends Table {
  TextColumn get id => text()();
  TextColumn get trackerId => text().withDefault(const Constant(''))();
  TextColumn get parentId => text().nullable()();
  TextColumn get sortKey => text().withDefault(const Constant(''))();
  IntColumn get archivedAt => integer().nullable()();
  IntColumn get deletedAt => integer().nullable()();
  IntColumn get createdAt => integer()();

  /// Wall-clock ms of the latest change to the record or any of its cells (any device).
  IntColumn get updatedAt => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// One row per non-empty cell ("cells-as-rows", docs/04 §3.1). [raw] is the canonical JSON value
/// (source of truth, what is synced); the v* columns are derived from it for indexed SQL.
@DataClassName('CellRow')
class Cells extends Table {
  TextColumn get recordId => text()();
  TextColumn get propertyId => text()();
  TextColumn get raw => text()();
  TextColumn get vText => text().nullable()();
  RealColumn get vNum => real().nullable()();
  IntColumn get vInt => integer().nullable()();
  TextColumn get vSort => text().nullable()();
  IntColumn get vDay => integer().nullable()();

  @override
  Set<Column> get primaryKey => {recordId, propertyId};
}

/// Relation edges. Two-way relations store one row per direction so each property reads its own.
@DataClassName('RecordLinkRow')
class RecordLinks extends Table {
  TextColumn get id => text()();
  TextColumn get relationPropertyId => text().withDefault(const Constant(''))();
  TextColumn get fromRecordId => text().withDefault(const Constant(''))();
  TextColumn get toRecordId => text().withDefault(const Constant(''))();
  TextColumn get sortKey => text().withDefault(const Constant(''))();
  IntColumn get deletedAt => integer().nullable()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Saved views (queries + presentation); own no records.
@DataClassName('ViewRow')
class TrackerViews extends Table {
  @override
  String get tableName => 'views';

  TextColumn get id => text()();
  TextColumn get trackerId => text().withDefault(const Constant(''))();
  TextColumn get name => text().withDefault(const Constant(''))();
  TextColumn get configJson => text().withDefault(const Constant('{}'))();
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

@DriftDatabase(tables: [Trackers, Properties, Records, Cells, RecordLinks, TrackerViews, FieldMeta, SyncOutbox, SyncState, LocalConflicts])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await customStatement('CREATE INDEX outbox_order ON sync_outbox (id)');
          await _createTrackerIndexes();
        },
        onUpgrade: (m, from, to) async {
          // Every schema change adds a step here and a migration test (test/data/migration_test.dart).
          if (from < 2) {
            await m.createTable(properties);
            await m.createTable(records);
            await m.createTable(cells);
            await m.createTable(recordLinks);
            await m.createTable(trackerViews);
            await _createTrackerIndexes();
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  Future<void> _createTrackerIndexes() async {
    for (final s in const [
      'CREATE INDEX properties_tracker ON properties (tracker_id, sort_key)',
      'CREATE INDEX records_tracker ON records (tracker_id, sort_key)',
      'CREATE INDEX records_parent ON records (parent_id)',
      'CREATE INDEX cells_prop_num ON cells (property_id, v_num) WHERE v_num IS NOT NULL',
      'CREATE INDEX cells_prop_text ON cells (property_id, v_text) WHERE v_text IS NOT NULL',
      'CREATE INDEX cells_prop_sort ON cells (property_id, v_sort) WHERE v_sort IS NOT NULL',
      'CREATE INDEX cells_prop_day ON cells (property_id, v_day) WHERE v_day IS NOT NULL',
      'CREATE INDEX links_from ON record_links (relation_property_id, from_record_id)',
      'CREATE INDEX links_to ON record_links (to_record_id)',
      'CREATE INDEX views_tracker ON views (tracker_id, sort_key)',
    ]) {
      await customStatement(s);
    }
  }
}
