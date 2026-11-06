import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart' show OrderingTerm, driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/data/local/database_opener.dart';
import 'package:folio/data/sync/in_memory_transport.dart';
import 'package:folio/data/sync/sync_service.dart';
import 'package:folio/data/sync/sync_transport.dart';
import 'package:folio/data/sync/synced_store.dart';
import 'package:sync_engine/sync_engine.dart';

class Dev {
  Dev(this.db, this.store, this.transport, this.sync);
  final AppDatabase db;
  final SyncedStore store;
  final InMemoryTransport transport;
  final SyncService sync;

  static Future<Dev> create(FakeServer server, String id, int Function() now) async {
    final db = openInMemory();
    final store = await SyncedStore.open(db, now: now, deviceId: id);
    final t = InMemoryTransport(server);
    return Dev(db, store, t, SyncService(store, t));
  }

  Future<Tracker?> tracker(String id) =>
      (db.select(db.trackers)..where((t) => t.id.equals(id))).getSingleOrNull();
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late FakeServer server;
  var clock = 1700000000000;
  int now() => clock;

  setUp(() {
    server = FakeServer();
    clock = 1700000000000;
  });

  test('edit on device A appears on device B after sync; column and field clock are written atomically', () async {
    final a = await Dev.create(server, 'devA', now);
    final b = await Dev.create(server, 'devB', now);
    await a.store.setFields('trackers', 't1', {'name': 'Reading', 'color': 'teal'});
    expect(await a.sync.pendingCount(), 2);
    await a.sync.sync();
    expect(await a.sync.pendingCount(), 0);
    final r = await b.sync.sync();
    expect(r.pulled, 2);
    final t = await b.tracker('t1');
    expect((t!.name, t.color), ('Reading', 'teal'));
  });

  test('offline edits queue, nothing is lost, and sync resumes when the network returns', () async {
    final a = await Dev.create(server, 'devA', now);
    a.transport.offline = true;
    await a.store.setFields('trackers', 't1', {'name': 'Offline name'});
    await expectLater(a.sync.sync(), throwsA(isA<SyncTransportException>()));
    expect(await a.sync.pendingCount(), 1, reason: 'outbox retained after failure');
    final row = await a.db.select(a.db.syncOutbox).getSingle();
    expect(row.attempts, 1);
    expect(row.lastError, 'offline');
    a.transport.offline = false;
    await a.sync.sync();
    expect(await a.sync.pendingCount(), 0);
    expect(server.state[const FieldKey('trackers', 't1', 'name')]!.value, 'Offline name');
    expect(await a.sync.lastSuccessfulSync(), isNotNull);
  });

  test('concurrent edits to the SAME field: newer wins everywhere, loser is preserved as a conflict', () async {
    final a = await Dev.create(server, 'devA', now);
    final b = await Dev.create(server, 'devB', now);
    await a.store.setFields('trackers', 't1', {'name': 'Base'});
    await a.sync.sync();
    await b.sync.sync();
    // both go offline and edit the same field
    clock += 1000;
    await a.store.setFields('trackers', 't1', {'name': 'From A'});
    clock += 1000;
    await b.store.setFields('trackers', 't1', {'name': 'From B (later)'});
    await a.sync.sync();
    await b.sync.sync();
    await a.sync.sync();
    expect((await a.tracker('t1'))!.name, 'From B (later)');
    expect((await b.tracker('t1'))!.name, 'From B (later)');
    final lost = await a.db.select(a.db.localConflicts).get();
    expect(lost, hasLength(1));
    expect(lost.single.lostValueJson, '"From A"', reason: 'the overwritten value is kept for review');
    // idempotent: syncing again does not duplicate conflicts
    await a.sync.sync();
    expect(await a.db.select(a.db.localConflicts).get(), hasLength(1));
  });

  test('concurrent edits to DIFFERENT fields merge without any conflict', () async {
    final a = await Dev.create(server, 'devA', now);
    final b = await Dev.create(server, 'devB', now);
    await a.store.setFields('trackers', 't1', {'name': 'N', 'color': 'red'});
    await a.sync.sync();
    await b.sync.sync();
    clock += 10;
    await a.store.setFields('trackers', 't1', {'name': 'N2'});
    await b.store.setFields('trackers', 't1', {'color': 'blue'});
    for (final d in [a, b, a, b]) {
      await d.sync.sync();
    }
    for (final d in [a, b]) {
      final t = (await d.tracker('t1'))!;
      expect((t.name, t.color), ('N2', 'blue'));
    }
    expect(server.conflicts, isEmpty);
  });

  test('clock persists across restart: later edits never get an older HLC than earlier ones', () async {
    final file = File('${Directory.systemTemp.createTempSync('folio').path}/db.sqlite');
    const key = '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';
    var db = openEncrypted(file, key);
    var store = await SyncedStore.open(db, now: now, deviceId: 'devA');
    clock = 5000000000000;
    await store.setFields('trackers', 't1', {'name': 'one'});
    await db.close();
    clock = 1000; // system clock went backwards while the app was closed
    db = openEncrypted(file, key);
    store = await SyncedStore.open(db, now: now, deviceId: 'devA');
    await store.setFields('trackers', 't1', {'name': 'two'});
    final rows = await (db.select(db.syncOutbox)..orderBy([(o) => OrderingTerm.asc(o.id)])).get();
    expect(Hlc.parse(rows[1].hlc) > Hlc.parse(rows[0].hlc), isTrue);
    expect(rows[1].baseHlc, rows[0].hlc, reason: 'second edit is causally based on the first');
    await db.close();
  });

  test('randomized: 60 scenarios of 3 devices with outages converge to the server state', () async {
    for (var seed = 0; seed < 60; seed++) {
      final r = Random(seed);
      final srv = FakeServer();
      var t = 1700000000000;
      final devs = [for (var i = 0; i < 3; i++) await Dev.create(srv, 'd$i', () => t + i * 40)];
      for (var step = 0; step < 40; step++) {
        t += r.nextInt(5);
        final d = devs[r.nextInt(3)];
        switch (r.nextInt(4)) {
          case 0:
          case 1:
            await d.store.setFields('trackers', 't${r.nextInt(2)}', {['name', 'color', 'icon'][r.nextInt(3)]: 'v${seed}_$step'});
          case 2:
            d.transport.offline = r.nextInt(3) == 0;
            try {
              await d.sync.sync();
            } on SyncTransportException {/* queued */}
          default:
            d.transport.offline = false;
        }
      }
      for (final d in devs) {
        d.transport.offline = false;
      }
      for (var round = 0; round < 3; round++) {
        for (final d in devs) {
          await d.sync.sync();
        }
      }
      for (final d in devs) {
        for (final id in ['t0', 't1']) {
          final row = await d.tracker(id);
          for (final f in ['name', 'color', 'icon']) {
            final expected = srv.state[FieldKey('trackers', id, f)]?.value;
            final actual = row == null ? null : {'name': row.name, 'color': row.color, 'icon': row.icon}[f];
            expect(actual == '' ? null : actual, expected, reason: 'seed $seed ${d.store.deviceId} $id.$f');
          }
        }
        expect(await d.sync.pendingCount(), 0);
        await d.db.close();
      }
    }
  });

  test('backoff grows exponentially and is capped', () {
    expect(backoffFor(0), const Duration(seconds: 2));
    expect(backoffFor(3), const Duration(seconds: 16));
    expect(backoffFor(30), const Duration(minutes: 15));
  });

  test('encrypted DB: plaintext not on disk; wrong key rejected', () async {
    final file = File('${Directory.systemTemp.createTempSync('folio').path}/enc.sqlite');
    const key = 'aa112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';
    final db = openEncrypted(file, key);
    final store = await SyncedStore.open(db, now: now, deviceId: 'd');
    await store.setFields('trackers', 't1', {'name': 'TOP-SECRET-TRACKER-NAME'});
    await db.close();
    expect(String.fromCharCodes(file.readAsBytesSync()).contains('TOP-SECRET-TRACKER-NAME'), isFalse);
    final wrong = openEncrypted(file, '${'bb' * 32}');
    await expectLater(wrong.select(wrong.trackers).get(), throwsA(anything));
    final ok = openEncrypted(file, key);
    expect((await ok.select(ok.trackers).get()).single.name, 'TOP-SECRET-TRACKER-NAME');
    await ok.close();
  });
}
