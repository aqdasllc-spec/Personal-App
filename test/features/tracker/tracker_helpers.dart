import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:folio/data/local/app_database.dart';
import 'package:folio/data/local/database_opener.dart';
import 'package:folio/data/sync/in_memory_transport.dart';
import 'package:folio/data/sync/sync_service.dart';
import 'package:folio/data/sync/synced_store.dart';
import 'package:folio/features/tracker/data/tracker_repository.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:tracker_engine/tracker_engine.dart' as te;

class Env {
  Env._(this.db, this.store, this.repo, this.sync, this.transport);
  final AppDatabase db;
  final SyncedStore store;
  final TrackerRepository repo;
  final SyncService sync;
  final InMemoryTransport transport;

  static int clock = 1700000000000;

  static Future<Env> create({FakeServer? server, String device = 'dev'}) async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final db = openInMemory();
    // strictly increasing "wall clock" so edits made in sequence order deterministically
    final store = await SyncedStore.open(db, now: () => clock += 7, deviceId: device);
    final transport = InMemoryTransport(server ?? FakeServer());
    return Env._(db, store, TrackerRepository(store), SyncService(store, transport), transport);
  }

  Future<void> close() => db.close();

  /// Tracker with Name(text, title) + Status + Hours + Due + Tags + Done.
  Future<({String tracker, Map<String, String> p})> taskTracker({String name = 'Tasks'}) async {
    final t = await repo.createTracker(name: name);
    final props = await repo.properties(t);
    final p = <String, String>{'name': props.single.id};
    p['status'] = await repo.addProperty(t, 'Status', te.PropertyType.status, config: te.Cfg.options(const [
      te.SelectOption(id: 'todo', label: 'Not started', group: te.StatusGroup.todo),
      te.SelectOption(id: 'doing', label: 'In progress', group: te.StatusGroup.inProgress),
      te.SelectOption(id: 'done', label: 'Done', group: te.StatusGroup.complete),
    ]));
    p['hours'] = await repo.addProperty(t, 'Hours', te.PropertyType.number);
    p['due'] = await repo.addProperty(t, 'Due', te.PropertyType.date);
    p['tags'] = await repo.addProperty(t, 'Tags', te.PropertyType.multiSelect, config: te.Cfg.options(const [
      te.SelectOption(id: 'a', label: 'Alpha'),
      te.SelectOption(id: 'b', label: 'Beta'),
    ]));
    p['done'] = await repo.addProperty(t, 'Done?', te.PropertyType.checkbox);
    return (tracker: t, p: p);
  }
}

Future<List<String>> names(Env e, String tracker, String nameProp, te.ViewConfig view, {String search = '', bool forceReference = false, DateTime? now}) async {
  final page = await e.repo.queryPage(tracker, view, search: search, limit: 1000, forceReference: forceReference, now: now);
  return [for (final r in page.records) r.cells[nameProp] as String? ?? '?'];
}
