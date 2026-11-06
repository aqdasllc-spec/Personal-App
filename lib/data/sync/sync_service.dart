import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:sync_engine/sync_engine.dart';

import '../local/app_database.dart';
import 'sync_transport.dart';
import 'synced_store.dart';

class SyncReport {
  const SyncReport({required this.pushed, required this.pulled, required this.newConflicts});
  final int pushed;
  final int pulled;
  final int newConflicts;
}

/// Exponential backoff with a cap. Pure so it can be tested; callers add jitter.
Duration backoffFor(int attempt, {Duration base = const Duration(seconds: 2), Duration max = const Duration(minutes: 15)}) {
  final ms = base.inMilliseconds * (1 << attempt.clamp(0, 20));
  return Duration(milliseconds: ms > max.inMilliseconds ? max.inMilliseconds : ms);
}

/// Push local edits, pull remote ones, fetch conflicts. Safe to call repeatedly and
/// concurrently (calls are serialised); every step is resumable.
class SyncService {
  SyncService(this.store, this.transport, {this.batchSize = 100});

  final SyncedStore store;
  final SyncTransport transport;
  final int batchSize;
  Future<SyncReport>? _running;

  AppDatabase get _db => store.db;

  /// Number of local edits waiting to be uploaded (for the sync status chip).
  Future<int> pendingCount() async =>
      (await (_db.selectOnly(_db.syncOutbox)..addColumns([_db.syncOutbox.id.count()])).getSingle())
          .read(_db.syncOutbox.id.count())!;

  Future<DateTime?> lastSuccessfulSync() async {
    final v = await store.state('last_sync_at');
    return v == null ? null : DateTime.fromMillisecondsSinceEpoch(int.parse(v));
  }

  Future<SyncReport> sync() => _running ??= _run().whenComplete(() => _running = null);

  Future<SyncReport> _run() async {
    final pushed = await _push();
    final pulled = await _pull();
    final conflicts = await _pullConflicts();
    await store.setState('last_sync_at', DateTime.now().millisecondsSinceEpoch.toString());
    return SyncReport(pushed: pushed, pulled: pulled, newConflicts: conflicts);
  }

  Future<int> _push() async {
    var total = 0;
    while (true) {
      final rows = await (_db.select(_db.syncOutbox)
            ..orderBy([(o) => OrderingTerm.asc(o.id)])
            ..limit(batchSize))
          .get();
      if (rows.isEmpty) return total;
      final changes = [
        for (final r in rows)
          Change(
            key: FieldKey(r.tbl, r.rowId, r.field),
            value: r.valueJson == null ? null : jsonDecode(r.valueJson!),
            hlc: Hlc.parse(r.hlc),
            baseHlc: r.baseHlc == null ? null : Hlc.parse(r.baseHlc!),
            deviceId: store.deviceId,
            changeId: r.changeId,
          )
      ];
      try {
        await transport.push(changes);
      } on SyncTransportException catch (e) {
        await (_db.update(_db.syncOutbox)..where((o) => o.id.isIn(rows.map((r) => r.id))))
            .write(SyncOutboxCompanion.custom(
                attempts: _db.syncOutbox.attempts + const Constant(1), lastError: Constant(e.message)));
        rethrow; // outbox rows stay: nothing is dropped
      }
      // Only after the server acknowledged: remove exactly the rows we sent.
      await (_db.delete(_db.syncOutbox)..where((o) => o.id.isIn(rows.map((r) => r.id)))).go();
      total += rows.length;
    }
  }

  Future<int> _pull() async {
    var total = 0;
    var cursor = int.parse(await store.state('cursor') ?? '0');
    while (true) {
      final page = await transport.pull(cursor: cursor);
      for (final sc in page.changes) {
        await store.applyRemote(sc.change);
        cursor = sc.seq;
        await store.setState('cursor', '$cursor'); // resumable mid-page
        total++;
      }
      if (!page.hasMore) return total;
    }
  }

  Future<int> _pullConflicts() async {
    final after = int.parse(await store.state('conflict_cursor') ?? '0');
    final list = await transport.conflicts(afterId: after);
    var added = 0;
    for (final sc in list) {
      final c = sc.conflict;
      final n = await _db.into(_db.localConflicts).insert(
            LocalConflictsCompanion.insert(
              serverId: Value(sc.id),
              tbl: c.key.table,
              rowId: c.key.rowId,
              field: c.key.field,
              lostValueJson: Value(jsonEncode(c.lostValue)),
              lostHlc: c.lostHlc.toString(),
              winnerHlc: c.winnerHlc.toString(),
              createdAt: DateTime.now().millisecondsSinceEpoch,
            ),
            mode: InsertMode.insertOrIgnore,
          );
      if (n > 0) added++;
      await store.setState('conflict_cursor', '${sc.id}');
    }
    return added;
  }
}
