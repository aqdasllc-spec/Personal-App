import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/features/auth/auth_repository.dart';
import 'package:folio/features/library/data/library_repository.dart';

import '../../helpers.dart';

Future<void> io(WidgetTester t, {int rounds = 6}) async {
  for (var i = 0; i < rounds; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    for (var k = 0; k < 3; k++) {
      await t.pump(const Duration(milliseconds: 60));
    }
  }
  await t.pump(const Duration(milliseconds: 300));
}

Future<void> end(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 1));
}

/// Four books in the list view (newest first): Delta, Charlie, Bravo, Alpha. [syncedTitles] have a cloud copy.
Future<(TestEnv, Map<String, String>, FakeCloudBooks)> open(WidgetTester t, {List<String> syncedTitles = const []}) async {
  t.view.physicalSize = const Size(411, 890);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final cloud = FakeCloudBooks();
  final env = await TestEnv.create(session: const SignedInSession(userId: 'u', email: 'a@b.co'));
  addTearDown(env.db.close);
  env.cloud = cloud;
  final ids = <String, String>{};
  await t.runAsync(() async {
    final repo = LibraryRepository(env.db, directory: env.libraryDir, inspector: FakePdfInspector());
    var n = 10; // different page counts = different file contents (identical PDFs are rejected as duplicates)
    for (final title in ['Alpha', 'Bravo', 'Charlie', 'Delta']) {
      final b = (await repo.importPdf(await env.writePdf('$title.pdf', n++))).book!;
      await Future<void>.delayed(const Duration(milliseconds: 3)); // distinct addedAt so the order is stable
      await repo.updateDetails(b.id, title: title);
      ids[title] = b.id;
      if (syncedTitles.contains(title)) {
        cloud.files[b.id] = [1];
        await (env.db.update(env.db.books)..where((x) => x.id.equals(b.id))).write(const BooksCompanion(cloudState: Value('synced')));
      }
    }
  });
  await t.pumpWidget(env.app);
  await io(t);
  await t.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Library')));
  await io(t);
  await t.tap(find.byTooltip('List'));
  await io(t);
  return (env, ids, cloud);
}

Future<List<BookRow>> rows(WidgetTester t, TestEnv e) async => (await t.runAsync(() => e.db.select(e.db.books).get()))!;
Set<String> removedTitles(List<BookRow> r) => {for (final b in r) if (b.deletedAt != null) b.title};

Future<void> select(WidgetTester t, Map<String, String> ids, List<String> titles) async {
  await t.tap(find.byKey(const Key('library-select')));
  await io(t, rounds: 3);
  for (final title in titles) {
    await t.tap(find.byKey(Key('book-${ids[title]}')));
    await io(t, rounds: 2);
  }
}

void main() {
  group('remove several books', () {
    testWidgets('confirm, then they are gone with an Undo; Cancel keeps everything', (t) async {
      final (env, ids, _) = await open(t);
      await select(t, ids, ['Alpha', 'Charlie']);
      await t.tap(find.byKey(const Key('bulk-remove')));
      await io(t, rounds: 3);
      expect(find.text('Remove 2 books?'), findsOneWidget);
      await t.tap(find.byKey(const Key('bulk-remove-cancel')));
      await io(t, rounds: 3);
      expect(removedTitles(await rows(t, env)), isEmpty);
      expect(find.text('2 selected'), findsOneWidget, reason: 'still selecting after Cancel');

      await t.tap(find.byKey(const Key('bulk-remove')));
      await io(t, rounds: 3);
      await t.tap(find.byKey(const Key('bulk-remove-confirm')));
      await io(t);
      expect(removedTitles(await rows(t, env)), {'Alpha', 'Charlie'});
      expect(find.byKey(Key('book-${ids['Alpha']}')), findsNothing);
      expect(find.byKey(Key('book-${ids['Bravo']}')), findsOneWidget);
      expect(find.byKey(const Key('selection-bar')), findsNothing);
      expect(find.text('Removed 2 books'), findsOneWidget);

      await t.tap(find.text('Undo'));
      await io(t);
      expect(removedTitles(await rows(t, env)), isEmpty);
      expect(find.byKey(Key('book-${ids['Alpha']}')), findsOneWidget);
      await end(t);
    });

    testWidgets('books with a cloud copy lose it too; the dialog says so', (t) async {
      final (env, ids, cloud) = await open(t, syncedTitles: ['Bravo', 'Delta']);
      await select(t, ids, ['Bravo', 'Alpha']);
      await t.tap(find.byKey(const Key('bulk-remove')));
      await io(t, rounds: 3);
      expect(find.textContaining('1 of them has a cloud copy'), findsOneWidget);
      await t.tap(find.byKey(const Key('bulk-remove-confirm')));
      await io(t);
      expect(removedTitles(await rows(t, env)), {'Bravo', 'Alpha'});
      expect(cloud.files.keys, {ids['Delta']}, reason: 'only the removed book\'s cloud copy was deleted');
      await end(t);
    });

    testWidgets('if a cloud copy cannot be deleted that book is kept and reported; the others are removed', (t) async {
      final (env, ids, cloud) = await open(t, syncedTitles: ['Bravo']);
      await select(t, ids, ['Alpha', 'Bravo', 'Charlie']);
      await t.tap(find.byKey(const Key('bulk-remove')));
      await io(t, rounds: 3);
      cloud.failWith = 'offline'; // the first cloud call (Bravo's delete) fails
      await t.tap(find.byKey(const Key('bulk-remove-confirm')));
      await io(t);
      expect(removedTitles(await rows(t, env)), {'Alpha', 'Charlie'});
      expect(find.byKey(const Key('bulk-remove-failed')), findsOneWidget);
      expect(find.textContaining('"Bravo"'), findsOneWidget);
      expect(cloud.files.keys, {ids['Bravo']}, reason: 'nothing was deleted from the cloud for the kept book');
      await t.tap(find.text('OK'));
      await io(t, rounds: 3);
      expect(find.byKey(Key('book-${ids['Bravo']}')), findsOneWidget);
      await end(t);
    });
  });

  group('drag to select', () {
    Future<void> hold(WidgetTester t, Finder from, Finder to) async {
      final g = await t.startGesture(t.getCenter(from));
      await t.pump(const Duration(milliseconds: 700)); // press and hold
      final a = t.getCenter(from), b = t.getCenter(to);
      for (var k = 1; k <= 8; k++) {
        await g.moveTo(Offset.lerp(a, b, k / 8)!);
        await t.pump(const Duration(milliseconds: 40));
      }
      await g.up();
      await io(t, rounds: 2);
    }

    testWidgets('press and hold a book, slide over others: all of them are selected', (t) async {
      final (_, ids, _) = await open(t);
      await t.tap(find.byKey(const Key('library-select')));
      await io(t, rounds: 3);
      // newest first: Delta, Charlie, Bravo, Alpha
      await hold(t, find.byKey(Key('book-${ids['Delta']}')), find.byKey(Key('book-${ids['Bravo']}')));
      expect(find.text('3 selected'), findsOneWidget);
      expect(find.byKey(Key('sel-${ids['Charlie']}')), findsOneWidget, reason: 'the book in between is included');
      expect(find.byKey(Key('sel-${ids['Alpha']}')), findsNothing);
      await end(t);
    });

    testWidgets('starting on a selected book deselects what you slide over', (t) async {
      final (_, ids, _) = await open(t);
      await select(t, ids, ['Delta', 'Charlie', 'Bravo', 'Alpha']);
      expect(find.text('4 selected'), findsOneWidget);
      await hold(t, find.byKey(Key('book-${ids['Charlie']}')), find.byKey(Key('book-${ids['Alpha']}')));
      expect(find.text('1 selected'), findsOneWidget);
      expect(find.byKey(Key('sel-${ids['Delta']}')), findsOneWidget);
      await end(t);
    });

    testWidgets('a plain tap still toggles one book (drag-select does not break taps)', (t) async {
      final (_, ids, _) = await open(t);
      await select(t, ids, ['Bravo']);
      expect(find.text('1 selected'), findsOneWidget);
      await end(t);
    });
  });
}
