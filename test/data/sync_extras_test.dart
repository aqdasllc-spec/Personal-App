import 'dart:convert';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/data/local/database_opener.dart';
import 'package:folio/data/sync/in_memory_transport.dart';
import 'package:folio/data/sync/sync_service.dart';
import 'package:folio/data/sync/synced_store.dart';
import 'package:folio/features/library/domain_ink.dart';
import 'package:folio/features/library/domain_smart_views.dart';
import 'package:folio/features/library/domain_tag_colors.dart';
import 'package:sync_engine/sync_engine.dart';

class Dev {
  Dev(this.db, this.store, this.sync);
  final AppDatabase db;
  final SyncedStore store;
  final SyncService sync;
  static Future<Dev> create(FakeServer server, String id, int Function() now) async {
    final db = openInMemory();
    final store = await SyncedStore.open(db, now: now, deviceId: id);
    return Dev(db, store, SyncService(store, InMemoryTransport(server)));
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late FakeServer server;
  var clock = 1700000000000;
  int now() => clock += 10;
  setUp(() {
    server = FakeServer();
    clock = 1700000000000;
  });

  test('tag colours: a colour set on A shows on B; clearing it clears it there; per tag, so two tags do not clash', () async {
    final a = await Dev.create(server, 'devA', now);
    final b = await Dev.create(server, 'devB', now);
    await a.store.setFields('tag_colors', 'work', {'color': 5});
    await b.store.setFields('tag_colors', 'safety', {'color': 2});
    await a.sync.sync();
    await b.sync.sync();
    await a.sync.sync();
    expect(decodeTagColors(await a.store.state('tag_colors')), {'work': 5, 'safety': 2});
    expect(decodeTagColors(await b.store.state('tag_colors')), {'work': 5, 'safety': 2});
    await a.store.setFields('tag_colors', 'work', {'color': null});
    await a.sync.sync();
    await b.sync.sync();
    expect(decodeTagColors(await b.store.state('tag_colors')), {'safety': 2});
  });

  test('saved views: saving, changing and deleting a view reach the other device', () async {
    final a = await Dev.create(server, 'devA', now);
    final b = await Dev.create(server, 'devB', now);
    const v = SmartView(name: 'Work stuff', status: 'unread', tags: ['work'], sort: 'title');
    await a.store.setFields('smart_views', 'work stuff', {'view': v.toJson()});
    await a.sync.sync();
    await b.sync.sync();
    var views = decodeViews(await b.store.state('smart_views'));
    expect((views.single.name, views.single.status, views.single.sort), ('Work stuff', 'unread', 'title'));
    expect(views.single.tags, ['work']);

    await a.store.setFields('smart_views', 'work stuff', {'view': const SmartView(name: 'Work stuff', tags: ['work', 'safety']).toJson()});
    await a.sync.sync();
    await b.sync.sync();
    views = decodeViews(await b.store.state('smart_views'));
    expect(views.single.tags, ['work', 'safety'], reason: 'changed in place, not duplicated');

    await a.store.setFields('smart_views', 'work stuff', {'view': null});
    await a.sync.sync();
    await b.sync.sync();
    expect(decodeViews(await b.store.state('smart_views')), isEmpty);
  });

  test('drawings: a page drawn on A appears on B; erasing everything removes the row there; the other pages are untouched', () async {
    final a = await Dev.create(server, 'devA', now);
    final b = await Dev.create(server, 'devB', now);
    final s1 = encodeStrokes([const Stroke(1, 0.004, [0.1, 0.1, 0.5, 0.5])]);
    final s2 = encodeStrokes([const Stroke(2, 0.002, [0.2, 0.2])]);
    await a.store.setFields('page_ink', 'book1:3', {'strokes': s1});
    await a.store.setFields('page_ink', 'book1:4', {'strokes': s2});
    await a.sync.sync();
    await b.sync.sync();
    var rows = await b.db.select(b.db.pageInk).get();
    expect({for (final r in rows) r.page: r.bookId}, {3: 'book1', 4: 'book1'});
    expect(decodeStrokes(rows.firstWhere((r) => r.page == 3).strokes).single.color, 1);

    await a.store.setFields('page_ink', 'book1:3', {'strokes': null});
    await a.sync.sync();
    await b.sync.sync();
    rows = await b.db.select(b.db.pageInk).get();
    expect(rows.map((r) => r.page), [4]);
  });

  test('things made before sync existed are queued once, the first time the device syncs', () async {
    final a = await Dev.create(server, 'devA', now);
    final b = await Dev.create(server, 'devB', now);
    // old data, written the old way (no sync record)
    await a.store.setState('tag_colors', '{"work":3}');
    await a.store.setState('smart_views', encodeViews([const SmartView(name: 'Old view', tags: ['x'])]));
    await a.db.into(a.db.pageInk).insert(PageInkCompanion.insert(bookId: 'bk', page: 7, strokes: Value(encodeStrokes([const Stroke(0, 0.004, [0.3, 0.3])]))));
    expect(await a.sync.pendingCount(), 0);
    await a.sync.sync();
    expect(await a.store.state('extras_backfilled'), '1');
    await b.sync.sync();
    expect(decodeTagColors(await b.store.state('tag_colors')), {'work': 3});
    expect(decodeViews(await b.store.state('smart_views')).single.name, 'Old view');
    expect((await b.db.select(b.db.pageInk).get()).single.page, 7);
    // and only once
    await a.sync.sync();
    expect(await a.sync.pendingCount(), 0);
    expect(jsonDecode(await a.store.state('tag_colors') ?? '{}'), {'work': 3});
  });
}
