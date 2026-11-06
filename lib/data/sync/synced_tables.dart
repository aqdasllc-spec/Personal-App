import '../local/app_database.dart';

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

  /// Replaces the generic column write (for tables that need derived columns).
  final FieldHook? custom;

  /// Runs after a field was applied (local edit or remote change).
  final FieldHook? afterApply;
}

final Map<String, SyncedTable> syncedTables = {
  'tasks': const SyncedTable('tasks', {
    'title': 'title',
    'notes': 'notes',
    'priority': 'priority',
    'due_at': 'due_at',
    'done_at': 'done_at',
    'sort_key': 'sort_key',
    'deleted_at': 'deleted_at',
  }),
};
