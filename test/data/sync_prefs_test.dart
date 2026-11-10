import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/data/local/database_opener.dart';
import 'package:folio/data/sync/in_memory_transport.dart';
import 'package:folio/data/sync/sync_service.dart';
import 'package:folio/data/sync/sync_transport.dart';
import 'package:folio/data/sync/synced_store.dart';
import 'package:folio/features/backup/backup_service.dart' show mergePref;
import 'package:sync_engine/sync_engine.dart';

/// A server that has not run the prefs migration yet: it refuses the whole batch when a setting is in it.
class _OldServer extends InMemoryTransport {
  _OldServer(super.server);
  int refused = 0;
  @override
  Future<void> push(List<Change> changes) async {
    if (changes.any((c) => c.key.table == 'prefs')) {
      refused++;
      throw SyncTransportException('invalid table: prefs', retryable: false);
    }
    return super.push(changes);
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  var clock = 1700000000000;
  int now() => clock += 10;

  test('Quran and prayer settings reach the other device, and the screens there hear about it', () async {
    final server = FakeServer();
    final a = await SyncedStore.open(openInMemory(), now: now, deviceId: 'A');
    final b = await SyncedStore.open(openInMemory(), now: now, deviceId: 'B');
    final heard = <String>[];
    b.remotePrefChanges.listen(heard.add);
    await a.setState('quran_bookmarks', '[{"s":2,"a":255,"n":"","t":1}]');
    await a.setState('prayer_settings', '{"lat":31.5}');
    await a.setState('quran_text_scale', '1.40'); // this one stays on the device
    await SyncService(a, InMemoryTransport(server)).sync();
    await SyncService(b, InMemoryTransport(server)).sync();
    await pumpEventQueue();
    expect(await b.state('quran_bookmarks'), '[{"s":2,"a":255,"n":"","t":1}]');
    expect(await b.state('prayer_settings'), '{"lat":31.5}');
    expect(await b.state('quran_text_scale'), isNull);
    expect(heard, containsAll(['quran_bookmarks', 'prayer_settings']));
  });

  test('settings saved before sync existed are sent once', () async {
    final server = FakeServer();
    final db = openInMemory();
    final a = await SyncedStore.open(db, now: now, deviceId: 'A');
    // written straight into the table, as an older app version did
    await db.customStatement("INSERT INTO sync_state (key, value) VALUES ('quran_khatm', 'plan')");
    await SyncService(a, InMemoryTransport(server)).sync();
    final b = await SyncedStore.open(openInMemory(), now: now, deviceId: 'B');
    await SyncService(b, InMemoryTransport(server)).sync();
    expect(await b.state('quran_khatm'), 'plan');
  });

  test('a server without the prefs migration: everything else still syncs, settings wait', () async {
    final server = FakeServer();
    final a = await SyncedStore.open(openInMemory(), now: now, deviceId: 'A');
    final old = _OldServer(server);
    final sync = SyncService(a, old);
    await a.setState('quran_khatm', 'plan');
    await a.setFields('tag_colors', 'work', {'color': 3});
    await sync.sync();
    expect(old.refused, 1);
    expect(server.since(0).map((c) => c.key.table).toSet(), {'tag_colors'});
    expect(await sync.pendingCount(), 0, reason: 'held-back settings are not shown as stuck');
    await sync.sync(); // within the day: not tried again
    expect(old.refused, 1);
  });

  test('restoring a backup joins settings with what the device has', () {
    expect(mergePref(null, 'x'), 'x');
    expect(mergePref('mine', 'theirs'), 'mine');
    expect(mergePref('{"a":1}', '{"a":2,"b":3}'), '{"a":1,"b":3}');
    expect(
      mergePref('[{"s":1,"a":1,"n":"mine"}]', '[{"s":1,"a":1,"n":"old"},{"s":2,"a":5}]'),
      '[{"s":1,"a":1,"n":"mine"},{"s":2,"a":5}]',
    );
  });
}
