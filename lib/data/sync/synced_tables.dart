/// Registry of tables that take part in sync and the columns each synced field maps to.
/// Field and column names are allow-listed here, so they can be interpolated into SQL safely.
class SyncedTable {
  const SyncedTable(this.name, this.fieldToColumn, {this.createdAtColumn = 'created_at'});
  final String name;
  final Map<String, String> fieldToColumn;
  final String createdAtColumn;
}

const Map<String, SyncedTable> syncedTables = {
  'trackers': SyncedTable('trackers', {
    'name': 'name',
    'icon': 'icon',
    'color': 'color',
    'sort_key': 'sort_key',
    'archived_at': 'archived_at',
    'deleted_at': 'deleted_at',
  }),
};
