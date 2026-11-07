import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/data/local/database_opener.dart';
import 'package:folio/features/auth/auth_repository.dart';
import 'package:folio/features/library/data/library_repository.dart';
import 'package:folio/features/library/domain_format.dart';

import '../../helpers.dart';

/// A fake PDF of exactly [size] bytes (the fake page counter reads "pages=N" at the start).
File fakePdf(Directory dir, String name, int size, {int pages = 10}) {
  final head = 'pages=$pages ';
  return File('${dir.path}/$name')..writeAsStringSync(head + 'x' * (size - head.length));
}

void main() {
  test('formatBytes', () {
    expect(formatBytes(0), '0 B');
    expect(formatBytes(1023), '1023 B');
    expect(formatBytes(1024), '1 KB');
    expect(formatBytes(1536), '1.5 KB');
    expect(formatBytes(340 * 1024 * 1024), '340 MB');
    expect(formatBytes(1288490189), '1.2 GB');
    expect(formatBytes(1024 * 1024 * 1024), '1 GB');
  });

  group('storage report', () {
    late AppDatabase db;
    late Directory lib, src;
    late LibraryRepository repo;
    var n = 0;

    setUp(() {
      quietDrift();
      db = openInMemory();
      lib = Directory.systemTemp.createTempSync('lib');
      src = Directory.systemTemp.createTempSync('src');
      n = 0;
      repo = LibraryRepository(db, directory: lib, inspector: FakePdfInspector(), newId: () => 'b${++n}');
    });
    tearDown(() async {
      await db.close();
      lib.deleteSync(recursive: true);
      src.deleteSync(recursive: true);
    });

    test('totals, cloud copies, removed-but-not-purged, covers, and the largest first', () async {
      final big = (await repo.importPdf(fakePdf(src, 'big.pdf', 5000, pages: 1).path)).book!;
      final mid = (await repo.importPdf(fakePdf(src, 'mid.pdf', 3000, pages: 2).path)).book!;
      final small = (await repo.importPdf(fakePdf(src, 'small.pdf', 1000, pages: 3).path)).book!;
      final gone = (await repo.importPdf(fakePdf(src, 'gone.pdf', 2000, pages: 4).path)).book!;
      await (db.update(db.books)..where((b) => b.id.equals(big.id))).write(const BooksCompanion(cloudState: Value('synced')));
      await (db.update(db.books)..where((b) => b.id.equals(small.id))).write(const BooksCompanion(cloudState: Value('synced')));
      await repo.remove(gone.id);
      Directory('${lib.path}/covers').createSync();
      File('${lib.path}/covers/${big.id}.png').writeAsBytesSync(List.filled(700, 1));
      File('${lib.path}/covers/${mid.id}.png').writeAsBytesSync(List.filled(300, 1));

      final r = await repo.storageReport();
      expect((r.bookCount, r.bookBytes), (3, 9000), reason: 'removed books are not part of the library');
      expect((r.cloudCount, r.cloudBytes), (2, 6000));
      expect((r.removedCount, r.removedBytes), (1, 2000));
      expect(r.coverBytes, 1000);
      expect(r.largest.map((b) => b.title).toList(), ['big', 'mid', 'small']);
    });

    test('only the five largest are listed', () async {
      for (var i = 1; i <= 7; i++) {
        await repo.importPdf(fakePdf(src, 'f$i.pdf', 1000 + i * 100, pages: i).path);
      }
      final r = await repo.storageReport();
      expect(r.largest.length, 5);
      expect(r.largest.first.sizeBytes, 1700);
    });

    test('clearing covers frees them and an empty / missing folder is fine', () async {
      expect(await repo.clearCovers(), 0);
      Directory('${lib.path}/covers').createSync();
      File('${lib.path}/covers/a.png').writeAsBytesSync(List.filled(400, 1));
      File('${lib.path}/covers/b.png').writeAsBytesSync(List.filled(100, 1));
      expect(await repo.clearCovers(), 500);
      expect((await repo.storageReport()).coverBytes, 0);
      expect(await repo.clearCovers(), 0);
    });

    test('an empty library reports zeros', () async {
      final r = await repo.storageReport();
      expect((r.bookCount, r.bookBytes, r.cloudCount, r.removedCount, r.coverBytes), (0, 0, 0, 0, 0));
      expect(r.largest, isEmpty);
    });
  });

  group('Settings -> Storage', () {
    Future<void> io(WidgetTester t, {int rounds = 8}) async {
      for (var i = 0; i < rounds; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        for (var k = 0; k < 3; k++) {
          await t.pump(const Duration(milliseconds: 60));
        }
      }
      await t.pump(const Duration(milliseconds: 300));
    }

    Future<(TestEnv, FakeCloudBooks?)> open(WidgetTester t, {bool cloud = true}) async {
      t.view.physicalSize = const Size(411, 890);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final env = await TestEnv.create(session: const SignedInSession(userId: 'u', email: 'a@b.co'));
      addTearDown(env.db.close);
      final fake = cloud ? FakeCloudBooks() : null;
      env.cloud = fake;
      await t.runAsync(() async {
        final src = Directory.systemTemp.createTempSync('src');
        final repo = LibraryRepository(env.db, directory: env.libraryDir, inspector: FakePdfInspector());
        final sizes = {'Big': 3 * 1024 * 1024, 'Medium': 2048, 'Small': 1024};
        var p = 1;
        for (final e in sizes.entries) {
          final b = (await repo.importPdf(fakePdf(src, '${e.key}.pdf', e.value, pages: p++).path)).book!;
          await repo.updateDetails(b.id, title: e.key);
          if (e.key != 'Small' && fake != null) {
            fake.files[b.id] = [1];
            await (env.db.update(env.db.books)..where((x) => x.id.equals(b.id))).write(const BooksCompanion(cloudState: Value('synced')));
          }
        }
        final removed = (await repo.importPdf(fakePdf(src, 'Old.pdf', 4096, pages: 9).path)).book!;
        await repo.remove(removed.id);
        Directory('${env.libraryDir.path}/covers').createSync(recursive: true);
        File('${env.libraryDir.path}/covers/x.png').writeAsBytesSync(List.filled(2048, 1));
      });
      await t.pumpWidget(env.app);
      await io(t);
      await t.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Settings')));
      await io(t);
      await t.scrollUntilVisible(find.text('Storage'), 300, scrollable: find.byType(Scrollable).first);
      await io(t, rounds: 15); // the storage figures are read from disk (real time) once the section is on screen
      await t.drag(find.byType(Scrollable).first, const Offset(0, -120));
      await io(t, rounds: 4);
      return (env, fake);
    }

    testWidgets('shows phone use, cloud use with a meter, covers, removed books and the largest books', (t) async {
      final (_, cloud) = await open(t);
      expect(cloud, isNotNull);
      expect(find.textContaining('3 books ·'), findsOneWidget);
      expect(find.textContaining('2 books ·'), findsOneWidget, reason: 'two books have a cloud copy');
      expect(find.textContaining('free plan'), findsOneWidget);
      expect(find.byKey(const Key('storage-cloud-meter')), findsOneWidget);
      expect(find.textContaining('2 KB · first pages'), findsOneWidget);
      expect(find.textContaining('1 book · 4 KB'), findsOneWidget, reason: 'the removed book waiting for deletion');
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
    });

    testWidgets('Clear covers frees the cache; Delete now purges removed books', (t) async {
      final (env, _) = await open(t);
      await t.tap(find.byKey(const Key('storage-clear-covers')));
      await io(t);
      expect(find.text('Freed 2 KB.'), findsOneWidget);
      expect(File('${env.libraryDir.path}/covers/x.png').existsSync(), isFalse);
      await io(t, rounds: 15); // the figures are read again
      expect(t.widget<TextButton>(find.byKey(const Key('storage-clear-covers'))).onPressed, isNull, reason: 'nothing left to clear');

      await t.ensureVisible(find.byKey(const Key('storage-purge')));
      await t.pump();
      await t.tap(find.byKey(const Key('storage-purge')));
      await io(t);
      expect(find.text('Deleted 1 book for good.'), findsOneWidget);
      expect(find.byKey(const Key('storage-removed')), findsNothing);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
    });

    testWidgets('Remove all cloud copies: asks first, deletes them from the cloud, books stay on the phone', (t) async {
      final (env, cloud) = await open(t);
      await t.ensureVisible(find.byKey(const Key('storage-unsync-all')));
      await t.pump();
      await t.tap(find.byKey(const Key('storage-unsync-all')));
      await io(t, rounds: 3);
      expect(find.text('Remove all cloud copies?'), findsOneWidget);
      await t.tap(find.text('Cancel'));
      await io(t, rounds: 3);
      expect(cloud!.files.length, 2);

      await t.tap(find.byKey(const Key('storage-unsync-all')));
      await io(t, rounds: 3);
      await t.tap(find.byKey(const Key('storage-unsync-confirm')));
      await io(t, rounds: 12);
      expect(cloud.files, isEmpty);
      final rows = (await t.runAsync(() => env.db.select(env.db.books).get()))!.where((b) => b.deletedAt == null);
      expect(rows.every((b) => b.cloudState == 'local'), isTrue);
      expect(rows.length, 3);
      expect(find.text('Removed 2 cloud copies.'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
    });

    testWidgets('in a build without cloud sync there is no cloud line', (t) async {
      await open(t, cloud: false);
      expect(find.byKey(const Key('storage-cloud')), findsNothing);
      expect(find.byKey(const Key('storage-device')), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
    });
  });
}
