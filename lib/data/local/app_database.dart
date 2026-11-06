import 'package:drift/drift.dart';

import 'schema_versions.dart';

part 'app_database.g.dart';

/// Planner tasks. A task may have a due date (optionally with a time), be scheduled into a time block
/// (plannedAt + plannedMinutes), repeat, and remind. Recurring tasks "advance": completing one moves
/// its due date to the next occurrence instead of closing it.
@DataClassName('TaskRow')
@TableIndex(name: 'tasks_due', columns: {#dueAt})
@TableIndex(name: 'tasks_planned', columns: {#plannedAt})
class Tasks extends Table {
  TextColumn get id => text()();
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get notes => text().withDefault(const Constant(''))();

  /// '', 'low', 'medium' or 'high'.
  TextColumn get priority => text().withDefault(const Constant(''))();

  /// Due date/time, epoch ms. For date-only tasks this is local midnight and [dueHasTime] is 0.
  IntColumn get dueAt => integer().nullable()();
  IntColumn get dueHasTime => integer().withDefault(const Constant(0))();

  /// Time block: when the user plans to work on it, and for how long.
  IntColumn get plannedAt => integer().nullable()();
  IntColumn get plannedMinutes => integer().nullable()();
  IntColumn get doneAt => integer().nullable()();

  /// Recurrence rule, e.g. `FREQ=WEEKLY;BYDAY=MO,WE` ('' = does not repeat). See planner/recurrence.dart.
  TextColumn get rrule => text().withDefault(const Constant(''))();

  /// Remind this many minutes before the due/planned time (null = no reminder).
  IntColumn get remindMinutes => integer().nullable()();
  TextColumn get sortKey => text().withDefault(const Constant(''))();
  IntColumn get deletedAt => integer().nullable()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Planner events (things that happen at a time). Repeating events are stored once and expanded on read.
@DataClassName('EventRow')
@TableIndex(name: 'events_start', columns: {#startAt})
class Events extends Table {
  TextColumn get id => text()();
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get notes => text().withDefault(const Constant(''))();
  IntColumn get startAt => integer().withDefault(const Constant(0))();
  IntColumn get endAt => integer().withDefault(const Constant(0))();

  /// 1 = all-day (start is local midnight, end is the exclusive next midnight).
  IntColumn get allDay => integer().withDefault(const Constant(0))();
  TextColumn get rrule => text().withDefault(const Constant(''))();
  IntColumn get remindMinutes => integer().nullable()();
  TextColumn get color => text().withDefault(const Constant(''))();
  IntColumn get deletedAt => integer().nullable()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// A PDF in the library. The file itself lives in the app's private library folder as
/// `<id>.pdf` (the original is copied, never modified). Library data is device-local for now:
/// the file bytes are not synced, so neither is this table.
@DataClassName('BookRow')
@TableIndex(name: 'books_shelf', columns: {#shelfId})
@TableIndex(name: 'books_hash', columns: {#sha256})
class Books extends Table {
  TextColumn get id => text()();
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get author => text().withDefault(const Constant(''))();
  TextColumn get fileName => text().withDefault(const Constant(''))();
  IntColumn get pageCount => integer().withDefault(const Constant(0))();
  IntColumn get sizeBytes => integer().withDefault(const Constant(0))();
  TextColumn get sha256 => text().withDefault(const Constant(''))();
  TextColumn get shelfId => text().nullable()();
  IntColumn get favorite => integer().withDefault(const Constant(0))();

  /// Last page read (1-based; 0 = never opened).
  IntColumn get lastPage => integer().withDefault(const Constant(0))();
  IntColumn get lastOpenedAt => integer().nullable()();
  IntColumn get addedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// A named bookshelf / collection.
@DataClassName('ShelfRow')
class Shelves extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
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

@DriftDatabase(tables: [Tasks, Events, Books, Shelves, FieldMeta, SyncOutbox, SyncState, LocalConflicts])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await customStatement('CREATE INDEX outbox_order ON sync_outbox (id)');
        },
        // Step-by-step migrations use generated snapshots of each old schema (schema_versions.dart), so a
        // later change to a table can never silently alter how an OLD upgrade runs.
        onUpgrade: stepByStep(
          from1To2: (m, schema) async {
            // v2 added the custom-tracker tables (removed again in v3).
            await m.createTable(schema.properties);
            await m.createTable(schema.records);
            await m.createTable(schema.cells);
            await m.createTable(schema.recordLinks);
            await m.createTable(schema.views);
          },
          from2To3: (m, schema) async {
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
            await m.createTable(schema.tasks);
            await customStatement('CREATE INDEX tasks_due ON tasks (due_at) WHERE deleted_at IS NULL');
          },
          from3To4: (m, schema) async {
            // v4: Planner - time blocks, repeat and reminders on tasks, plus events.
            await customStatement('DROP INDEX IF EXISTS tasks_due'); // v3 made a partial index by hand; v4 declares it
            await m.addColumn(schema.tasks, schema.tasks.dueHasTime);
            await m.addColumn(schema.tasks, schema.tasks.plannedAt);
            await m.addColumn(schema.tasks, schema.tasks.plannedMinutes);
            await m.addColumn(schema.tasks, schema.tasks.rrule);
            await m.addColumn(schema.tasks, schema.tasks.remindMinutes);
            await m.createIndex(schema.tasksDue);
            await m.createIndex(schema.tasksPlanned);
            await m.createTable(schema.events);
            await m.createIndex(schema.eventsStart);
          },
          from4To5: (m, schema) async {
            // v5: Library - books and shelves (device-local).
            await m.createTable(schema.books);
            await m.createTable(schema.shelves);
            await m.createIndex(schema.booksShelf);
            await m.createIndex(schema.booksHash);
          },
        ),
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}
