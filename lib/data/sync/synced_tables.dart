import 'dart:convert';

import 'package:drift/drift.dart';

import '../local/app_database.dart';

/// Writes/handles one field of a custom-stored table. Runs inside the store's transaction.
typedef FieldHook = Future<void> Function(
  AppDatabase db,
  String rowId,
  String field,
  Object? value,
  int wallMs,
);

/// Registry of tables that take part in sync and how each synced field maps to local storage.
/// Field and column names are allow-listed here, so they can be interpolated into SQL safely.
/// The server-side allow-list lives in `apply_changes` (supabase/migrations).
class SyncedTable {
  const SyncedTable(
    this.name,
    this.fieldToColumn, {
    this.createdAtColumn = 'created_at',
    this.custom,
    this.afterApply,
  });
  final String name;
  final Map<String, String> fieldToColumn;
  final String createdAtColumn;

  /// Replaces the generic column write (for tables that need derived columns).
  final FieldHook? custom;

  /// Runs after a field was applied (local edit or remote change).
  final FieldHook? afterApply;
}

final Map<String, SyncedTable> syncedTables = {
  ..._more,
  'tasks': const SyncedTable('tasks', {
    'title': 'title',
    'notes': 'notes',
    'priority': 'priority',
    'due_at': 'due_at',
    'due_has_time': 'due_has_time',
    'planned_at': 'planned_at',
    'planned_minutes': 'planned_minutes',
    'done_at': 'done_at',
    'rrule': 'rrule',
    'remind_minutes': 'remind_minutes',
    'checklist': 'checklist',
    'sort_key': 'sort_key',
    'deleted_at': 'deleted_at',
  }),
  'events': const SyncedTable('events', {
    'title': 'title',
    'notes': 'notes',
    'start_at': 'start_at',
    'end_at': 'end_at',
    'all_day': 'all_day',
    'rrule': 'rrule',
    'remind_minutes': 'remind_minutes',
    'color': 'color',
    'deleted_at': 'deleted_at',
  }),
};

// ---- small things that sync like rows but are stored elsewhere (a setting, or a table with its own key) ----

Future<String?> _state(AppDatabase db, String key) async =>
    (await (db.select(db.syncState)..where((t) => t.key.equals(key))).getSingleOrNull())?.value;

Future<void> _putState(AppDatabase db, String key, String value) =>
    db.into(db.syncState).insertOnConflictUpdate(SyncStateCompanion.insert(key: key, value: value));

/// Tag colours: one synced row per tag (row id = tag, lower case), field `color` = palette index or null.
/// Stored locally as one JSON map in the `tag_colors` setting.
Future<void> _writeTagColor(AppDatabase db, String tag, String field, Object? value, int wallMs) async {
  Map<String, Object?> map;
  try {
    map = {...(jsonDecode(await _state(db, 'tag_colors') ?? '{}') as Map).cast<String, Object?>()};
  } catch (_) {
    map = {};
  }
  if (value is int) {
    map[tag] = value;
  } else {
    map.remove(tag);
  }
  await _putState(db, 'tag_colors', jsonEncode(map));
}

/// Saved Library views: one synced row per view (row id = name, lower case), field `view` = the view or null (deleted).
/// Stored locally as one JSON list in the `smart_views` setting.
Future<void> _writeSmartView(AppDatabase db, String key, String field, Object? value, int wallMs) async {
  List<Object?> list;
  try {
    list = [...(jsonDecode(await _state(db, 'smart_views') ?? '[]') as List)];
  } catch (_) {
    list = [];
  }
  bool same(Object? e) => e is Map && (e['n'] as String?)?.trim().toLowerCase() == key;
  final at = list.indexWhere(same);
  if (value is Map) {
    if (at >= 0) {
      list[at] = value;
    } else {
      list.add(value);
    }
  } else if (at >= 0) {
    list.removeAt(at);
  }
  await _putState(db, 'smart_views', jsonEncode(list));
}

/// Pen drawings: one synced row per page (row id = `<book id>:<page>`), field `strokes` = JSON text, or null/empty = none.
Future<void> _writeInk(AppDatabase db, String rowId, String field, Object? value, int wallMs) async {
  final cut = rowId.lastIndexOf(':');
  final page = cut < 0 ? null : int.tryParse(rowId.substring(cut + 1));
  if (page == null) return;
  final bookId = rowId.substring(0, cut);
  final text = value is String ? value : '';
  if (text.isEmpty || text == '[]') {
    await (db.delete(db.pageInk)..where((t) => t.bookId.equals(bookId) & t.page.equals(page))).go();
  } else {
    await db.into(db.pageInk).insertOnConflictUpdate(PageInkCompanion.insert(bookId: bookId, page: page, strokes: Value(text)));
  }
}

final Map<String, SyncedTable> _more = {
  'tag_colors': const SyncedTable('tag_colors', {'color': 'color'}, custom: _writeTagColor),
  'smart_views': const SyncedTable('smart_views', {'view': 'view'}, custom: _writeSmartView),
  'page_ink': const SyncedTable('page_ink', {'strokes': 'strokes'}, custom: _writeInk),
};
