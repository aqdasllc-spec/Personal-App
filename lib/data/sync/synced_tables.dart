import '../local/app_database.dart';
import 'cell_sync.dart';

/// Writes/handles one field of a custom-stored table. Runs inside the store's transaction.
typedef FieldHook = Future<void> Function(AppDatabase db, String rowId, String field, Object? value, int wallMs);

/// Registry of tables that take part in sync and how each synced field maps to local storage.
/// Field and column names are allow-listed here, so they can be interpolated into SQL safely.
/// The server-side allow-list lives in `apply_changes` (supabase/migrations).
class SyncedTable {
  const SyncedTable(this.name, this.fieldToColumn, {this.createdAtColumn = 'created_at', this.custom, this.afterApply});
  final String name;
  final Map<String, String> fieldToColumn;
  final String createdAtColumn;

  /// Replaces the generic column write (used by `cells`).
  final FieldHook? custom;

  /// Runs after a field was applied (local edit or remote change).
  final FieldHook? afterApply;
}

Future<void> _reindexOnDefChange(AppDatabase db, String rowId, String field, Object? value, int wallMs) async {
  if (field == 'type' || field == 'config_json') await reindexProperty(db, rowId);
}

Future<void> _touchOwnRecord(AppDatabase db, String rowId, String field, Object? value, int wallMs) => touchRecord(db, rowId, wallMs);

final Map<String, SyncedTable> syncedTables = {
  'trackers': const SyncedTable('trackers', {
    'name': 'name',
    'icon': 'icon',
    'color': 'color',
    'sort_key': 'sort_key',
    'archived_at': 'archived_at',
    'deleted_at': 'deleted_at',
  }),
  'properties': const SyncedTable('properties', {
    'tracker_id': 'tracker_id',
    'name': 'name',
    'type': 'type',
    'config_json': 'config_json',
    'sort_key': 'sort_key',
    'deleted_at': 'deleted_at',
  }, afterApply: _reindexOnDefChange),
  'records': const SyncedTable('records', {
    'tracker_id': 'tracker_id',
    'parent_id': 'parent_id',
    'sort_key': 'sort_key',
    'archived_at': 'archived_at',
    'deleted_at': 'deleted_at',
  }, afterApply: _touchOwnRecord),
  'cells': const SyncedTable('cells', {'value': 'raw'}, custom: applyCellField),
  'record_links': const SyncedTable('record_links', {
    'relation_property_id': 'relation_property_id',
    'from_record_id': 'from_record_id',
    'to_record_id': 'to_record_id',
    'sort_key': 'sort_key',
    'deleted_at': 'deleted_at',
  }),
  'views': const SyncedTable('views', {
    'tracker_id': 'tracker_id',
    'name': 'name',
    'config_json': 'config_json',
    'sort_key': 'sort_key',
    'deleted_at': 'deleted_at',
  }),
};
