import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:tracker_engine/tracker_engine.dart';

import '../local/app_database.dart';

PropertyDef? propertyDefFromRow(PropertyRow r) {
  try {
    return PropertyDef(
      id: r.id,
      name: r.name,
      type: PropertyType.parse(r.type),
      config: Map<String, Object?>.from(jsonDecode(r.configJson) as Map),
    );
  } catch (_) {
    return null; // unknown type/config from a newer app version: keep data, don't derive columns
  }
}

/// Derived typed columns for [value] under [def]; null when it can't be derived (kept as raw only).
CellStorage? _storageFor(PropertyDef? def, Object? value) {
  if (def == null || !def.type.isStored) return null;
  final n = Values.normalize(def, value);
  // Option ids may legitimately outlive their option (shown as "(removed)"), so for option-based
  // types we derive columns from the id alone; everything else must still be a valid value.
  if (!def.type.isOptionBased && Values.validate(def, n) != null) return null;
  return Values.toStorage(def, n);
}

Future<void> _upsertCell(AppDatabase db, String recordId, String propertyId, Object? value, PropertyDef? def) async {
  final s = _storageFor(def, value);
  await db.into(db.cells).insertOnConflictUpdate(CellsCompanion.insert(
        recordId: recordId,
        propertyId: propertyId,
        raw: jsonEncode(value),
        vText: Value(s?.text),
        vNum: Value(s?.num),
        vInt: Value(s?.intVal),
        vSort: Value(s?.sort),
        vDay: Value(s?.day),
      ));
}

/// Sync handler for table `cells`: row id is `recordId:propertyId`, single field `value`.
Future<void> applyCellField(AppDatabase db, String rowId, String field, Object? value, int wallMs) async {
  if (field != 'value') return;
  final i = rowId.indexOf(':');
  if (i <= 0) return;
  final recordId = rowId.substring(0, i), propertyId = rowId.substring(i + 1);
  if (value == null) {
    await (db.delete(db.cells)..where((c) => c.recordId.equals(recordId) & c.propertyId.equals(propertyId))).go();
  } else {
    final row = await (db.select(db.properties)..where((p) => p.id.equals(propertyId))).getSingleOrNull();
    await _upsertCell(db, recordId, propertyId, value, row == null ? null : propertyDefFromRow(row));
  }
  await touchRecord(db, recordId, wallMs);
}

Future<void> touchRecord(AppDatabase db, String recordId, int wallMs) => db.customUpdate(
      'UPDATE records SET updated_at = MAX(updated_at, ?) WHERE id = ?',
      variables: [Variable.withInt(wallMs), Variable.withString(recordId)],
      updates: {db.records},
    );

/// Recompute typed columns of every cell of [propertyId] from `raw`. Needed when the property
/// definition arrives after its cells (sync ordering) or its type/config changes.
Future<void> reindexProperty(AppDatabase db, String propertyId) async {
  final row = await (db.select(db.properties)..where((p) => p.id.equals(propertyId))).getSingleOrNull();
  if (row == null) return;
  final def = propertyDefFromRow(row);
  final cells = await (db.select(db.cells)..where((c) => c.propertyId.equals(propertyId))).get();
  for (final c in cells) {
    await _upsertCell(db, c.recordId, propertyId, jsonDecode(c.raw), def);
  }
}
