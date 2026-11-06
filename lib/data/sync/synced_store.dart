import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:uuid/uuid.dart';

import '../local/app_database.dart';
import 'synced_tables.dart';

/// The single write path for synced data. A local edit is ONE transaction that
///   1. writes the column,
///   2. records the field's new HLC (and the HLC it replaced, as `baseHlc`),
///   3. appends to the outbox,
///   4. persists the clock,
/// so a crash can never leave data without its sync record (or vice versa).
class SyncedStore {
  SyncedStore._(this.db, this.clock, this.deviceId, this._now);

  final AppDatabase db;
  final HlcClock clock;
  final String deviceId;
  final int Function() _now;
  final _uuid = const Uuid();

  static Future<SyncedStore> open(AppDatabase db, {int Function()? now, String? deviceId}) async {
    final nowFn = now ?? () => DateTime.now().millisecondsSinceEpoch;
    var id = deviceId ?? await _getState(db, 'device_id');
    if (id == null) {
      id = const Uuid().v4();
      await _setState(db, 'device_id', id);
    }
    final clock = HlcClock(id, now: nowFn, maxDrift: const Duration(days: 365));
    final last = await _getState(db, 'last_hlc');
    if (last != null) clock.seed(Hlc.parse(last));
    return SyncedStore._(db, clock, id, nowFn);
  }

  static Future<String?> _getState(AppDatabase db, String key) async =>
      (await (db.select(db.syncState)..where((t) => t.key.equals(key))).getSingleOrNull())?.value;

  static Future<void> _setState(AppDatabase db, String key, String value) =>
      db.into(db.syncState).insertOnConflictUpdate(SyncStateCompanion.insert(key: key, value: value));

  Future<String?> state(String key) => _getState(db, key);
  Future<void> setState(String key, String value) => _setState(db, key, value);

  String newId() => _uuid.v7();

  /// Local edit of one or more fields of one row, atomically.
  Future<void> setFields(String tbl, String rowId, Map<String, Object?> fields) {
    final table = syncedTables[tbl] ?? (throw ArgumentError('Table $tbl is not synced'));
    return db.transaction(() async {
      await _ensureRow(table, rowId);
      for (final e in fields.entries) {
        final column = table.fieldToColumn[e.key] ?? (throw ArgumentError('Unknown field ${e.key} on $tbl'));
        final hlc = clock.tick();
        final base = await _metaHlc(tbl, rowId, e.key);
        await db.customUpdate('UPDATE $tbl SET $column = ? WHERE id = ?',
            variables: [_variable(e.value), Variable.withString(rowId)], updates: {_tableInfo(tbl)});
        await _putMeta(tbl, rowId, e.key, hlc);
        await db.into(db.syncOutbox).insert(SyncOutboxCompanion.insert(
              tbl: tbl,
              rowId: rowId,
              field: e.key,
              valueJson: Value(jsonEncode(e.value)),
              hlc: hlc.toString(),
              baseHlc: Value(base),
              changeId: _uuid.v4(),
              createdAt: _now(),
            ));
      }
      await _setState(db, 'last_hlc', clock.latest.toString());
    });
  }

  /// Apply a change received from the server. Returns true when it changed local data.
  /// Rule: a remote value is applied only if it is newer than what we hold; a newer local
  /// pending edit is kept and will be reconciled (and logged as a conflict) at the server.
  Future<bool> applyRemote(Change c) {
    final table = syncedTables[c.key.table];
    if (table == null) return Future.value(false); // unknown table from a newer app version: skip, don't crash
    final column = table.fieldToColumn[c.key.field];
    if (column == null) return Future.value(false);
    return db.transaction(() async {
      clock.observe(c.hlc);
      final current = await _metaHlc(c.key.table, c.key.rowId, c.key.field);
      if (current != null && !(c.hlc > Hlc.parse(current))) {
        await _setState(db, 'last_hlc', clock.latest.toString());
        return false;
      }
      await _ensureRow(table, c.key.rowId);
      await db.customUpdate('UPDATE ${table.name} SET $column = ? WHERE id = ?',
          variables: [_variable(c.value), Variable.withString(c.key.rowId)], updates: {_tableInfo(table.name)});
      await _putMeta(c.key.table, c.key.rowId, c.key.field, c.hlc);
      await _setState(db, 'last_hlc', clock.latest.toString());
      return true;
    });
  }

  Future<void> _ensureRow(SyncedTable t, String rowId) => db.customInsert(
        'INSERT INTO ${t.name} (id, ${t.createdAtColumn}) VALUES (?, ?) ON CONFLICT(id) DO NOTHING',
        variables: [Variable.withString(rowId), Variable.withInt(_now())],
      );

  TableInfo _tableInfo(String tbl) => db.allTables.firstWhere((t) => t.actualTableName == tbl);

  Future<String?> _metaHlc(String tbl, String rowId, String field) async {
    final row = await (db.select(db.fieldMeta)
          ..where((m) => m.tbl.equals(tbl) & m.rowId.equals(rowId) & m.field.equals(field)))
        .getSingleOrNull();
    return row?.hlc;
  }

  Future<void> _putMeta(String tbl, String rowId, String field, Hlc hlc) => db.into(db.fieldMeta).insertOnConflictUpdate(
      FieldMetaCompanion.insert(tbl: tbl, rowId: rowId, field: field, hlc: hlc.toString()));

  static Variable _variable(Object? v) => switch (v) {
        null => const Variable<Object>(null),
        String s => Variable.withString(s),
        int i => Variable.withInt(i),
        bool b => Variable.withInt(b ? 1 : 0),
        double d => Variable.withReal(d),
        _ => throw ArgumentError('Unsupported scalar ${v.runtimeType}; complex values need a codec'),
      };
}
