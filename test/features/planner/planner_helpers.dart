import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:folio/data/local/app_database.dart';
import 'package:folio/data/local/database_opener.dart';
import 'package:folio/data/sync/in_memory_transport.dart';
import 'package:folio/data/sync/sync_service.dart';
import 'package:folio/data/sync/synced_store.dart';
import 'package:folio/features/planner/data/planner_repository.dart';
import 'package:sync_engine/sync_engine.dart';

class PEnv {
  PEnv._(this.db, this.store, this.repo, this.sync, this.transport);
  final AppDatabase db;
  final SyncedStore store;
  final PlannerRepository repo;
  final SyncService sync;
  final InMemoryTransport transport;

  static int clock = 1700000000000;

  static Future<PEnv> create({FakeServer? server, String device = 'dev'}) async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final db = openInMemory();
    final store = await SyncedStore.open(db, now: () => clock += 7, deviceId: device);
    final transport = InMemoryTransport(server ?? FakeServer());
    return PEnv._(db, store, PlannerRepository(store), SyncService(store, transport), transport);
  }

  Future<void> close() => db.close();
}

DateTime d(int y, int m, int day, [int h = 0, int mi = 0]) => DateTime(y, m, day, h, mi);
