import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/data/local/app_database.dart';
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

/// Three books: Zebra (not started, tags work+safety), Apple (reading, tag work), Mango (finished, tag fiction).
Future<(TestEnv, Map<String, String>)> open(WidgetTester t, {String? savedSort}) async {
  t.view.physicalSize = const Size(411, 890);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final env = await TestEnv.create();
  addTearDown(env.db.close);
  final ids = <String, String>{};
  await t.runAsync(() async {
    final repo = LibraryRepository(env.db, directory: env.libraryDir, inspector: FakePdfInspector());
    Future<void> add(String title, int pages, String tags, int last) async {
      final b = (await repo.importPdf(await env.writePdf('$title.pdf', pages))).book!;
      await repo.updateDetails(b.id, title: title);
      await repo.setTags(b.id, tags);
      if (last > 0) await repo.saveProgress(b.id, last);
      ids[title] = b.id;
    }

    await add('Zebra', 10, 'work, safety', 0);
    await add('Apple', 20, 'work', 5);
    await add('Mango', 30, 'fiction', 30);
    ids['#shelf'] = (await repo.createShelf('Work')).id; // a shelf to move books to
    if (savedSort != null) await env.store.setState('library_sort', savedSort);
  });
  await t.pumpWidget(env.app);
  await io(t);
  await t.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Library')));
  await io(t);
  await t.tap(find.byTooltip('List'));
  await io(t);
  return (env, ids);
}

/// Titles top to bottom as shown in the list view.
List<String> shown(WidgetTester t, Map<String, String> ids) {
  final found = <(String, double)>[];
  ids.forEach((title, id) {
    if (title.startsWith('#')) return;
    final f = find.byKey(Key('book-$id'));
    if (f.evaluate().isNotEmpty) found.add((title, t.getTopLeft(f).dy));
  });
  found.sort((a, b) => a.$2.compareTo(b.$2));
  return [for (final f in found) f.$1];
}

Future<void> openSheet(WidgetTester t) async {
  await t.tap(find.byKey(const Key('library-filter')));
  await io(t);
}

Future<void> closeSheet(WidgetTester t) async {
  // dismiss the bottom sheet like the Back button / a swipe down would
  Navigator.of(t.element(find.byKey(const Key('sort-title')))).pop();
  await io(t);
}

void main() {
  testWidgets('sort: choose Title A-Z -> the list reorders and the choice is remembered', (t) async {
    final (env, ids) = await open(t);
    expect(shown(t, ids), ['Mango', 'Apple', 'Zebra'], reason: 'default: newest added first');
    await openSheet(t);
    await t.tap(find.byKey(const Key('sort-title')));
    await io(t);
    await closeSheet(t);
    expect(shown(t, ids), ['Apple', 'Mango', 'Zebra']);
    expect(await t.runAsync(() => env.store.state('library_sort')), 'title');
    await openSheet(t);
    await t.tap(find.byKey(const Key('sort-pages')));
    await io(t);
    await closeSheet(t);
    expect(shown(t, ids), ['Mango', 'Apple', 'Zebra'], reason: 'longest first');
    await end(t);
  });

  testWidgets('a saved sort order is applied when the app starts', (t) async {
    final (_, ids) = await open(t, savedSort: 'title');
    await io(t, rounds: 4);
    expect(shown(t, ids), ['Apple', 'Mango', 'Zebra']);
    await end(t);
  });

  testWidgets('status filter: shows a badge and a removable chip; Clear filters resets', (t) async {
    final (_, ids) = await open(t);
    expect(find.byType(Badge), findsWidgets);
    await openSheet(t);
    await t.tap(find.byKey(const Key('status-reading')));
    await io(t);
    await closeSheet(t);
    expect(shown(t, ids), ['Apple']);
    expect(find.byKey(const Key('active-status')), findsOneWidget);
    expect(find.text('Reading'), findsWidgets);

    await t.tap(find.descendant(of: find.byKey(const Key('active-status')), matching: find.byTooltip('Remove filter')));
    await io(t);
    expect(shown(t, ids).length, 3);
    expect(find.byKey(const Key('active-filters')), findsNothing);

    await openSheet(t);
    await t.tap(find.byKey(const Key('status-unread')));
    await io(t);
    await closeSheet(t);
    expect(shown(t, ids), ['Zebra']);
    await t.tap(find.byKey(const Key('clear-filters')));
    await io(t);
    expect(shown(t, ids).length, 3);
    await end(t);
  });

  testWidgets('tag filter: chips list every tag with counts; choosing several narrows (AND); no match is explained', (t) async {
    final (_, ids) = await open(t);
    await openSheet(t);
    expect(find.byKey(const Key('tag-filter-work')), findsOneWidget);
    expect(find.text('work · 2'), findsOneWidget);
    expect(find.text('safety · 1'), findsOneWidget);
    await t.tap(find.byKey(const Key('tag-filter-work')));
    await io(t);
    await closeSheet(t);
    expect(shown(t, ids), ['Apple', 'Zebra']);
    expect(find.byKey(const Key('active-tag-work')), findsOneWidget);

    await openSheet(t);
    await t.tap(find.byKey(const Key('tag-filter-safety')));
    await io(t);
    await closeSheet(t);
    expect(shown(t, ids), ['Zebra']);

    await openSheet(t);
    await t.tap(find.byKey(const Key('status-finished')));
    await io(t);
    await closeSheet(t);
    expect(find.textContaining('No book matches these filters'), findsOneWidget);
    await t.tap(find.byKey(const Key('clear-filters')));
    await io(t);
    expect(shown(t, ids).length, 3);
    await end(t);
  });

  testWidgets('edit details: tags are typed comma separated, cleaned up, searchable, and shown on the preview card', (t) async {
    final (env, ids) = await open(t);
    await t.longPress(find.byKey(Key('book-${ids['Mango']}')));
    await io(t);
    await t.tap(find.byKey(const Key('peek-more')));
    await io(t);
    await t.tap(find.byKey(const Key('book-edit')));
    await io(t);
    expect((t.widget<TextField>(find.byKey(const Key('details-tags'))).controller!.text), 'fiction');
    await t.enterText(find.byKey(const Key('details-tags')), '  Novel, #fiction ,novel, to read ');
    await t.tap(find.byKey(const Key('details-save')));
    await io(t);
    final row = (await t.runAsync(() => env.db.select(env.db.books).get()))!.firstWhere((b) => b.title == 'Mango');
    expect(row.tags, '["Novel","fiction","to read"]');
    Navigator.of(t.element(find.byKey(const Key('book-edit')))).pop(); // close the book sheet
    await io(t);

    await t.enterText(find.byKey(const Key('library-search')), 'to read');
    await io(t);
    expect(shown(t, ids), ['Mango'], reason: 'search matches tags');
    await t.longPress(find.byKey(Key('book-${ids['Mango']}')));
    await io(t);
    expect(find.byKey(const Key('peek-tags')), findsOneWidget);
    expect(find.text('#to read'), findsOneWidget);
    await end(t);
  });

  group('select several books', () {
    Future<void> tapBook(WidgetTester t, Map<String, String> ids, String title) async {
      await t.tap(find.byKey(Key('book-${ids[title]}')));
      await io(t, rounds: 3);
    }

    Future<List<BookRow>> rows(WidgetTester t, TestEnv env) async => (await t.runAsync(() => env.db.select(env.db.books).get()))!;

    testWidgets('selection mode: taps select instead of opening; the bar counts; Select all; Done leaves', (t) async {
      final (_, ids) = await open(t);
      await t.tap(find.byKey(const Key('library-select')));
      await io(t, rounds: 3);
      expect(find.text('Tap books to select'), findsOneWidget);
      expect(find.byKey(Key('unsel-${ids['Apple']}')), findsOneWidget, reason: 'an empty ring shows that books can be picked');
      expect(t.widget<TextButton>(find.byKey(const Key('bulk-tags'))).onPressed, isNull, reason: 'nothing chosen yet');
      await tapBook(t, ids, 'Apple');
      await tapBook(t, ids, 'Zebra');
      expect(find.text('2 selected'), findsOneWidget);
      expect(find.byKey(Key('sel-${ids['Apple']}')), findsOneWidget);
      expect(find.text('PDF view page 0'), findsNothing, reason: 'tapping a book while selecting does not open it');
      await tapBook(t, ids, 'Apple'); // tap again = deselect
      expect(find.text('1 selected'), findsOneWidget);
      await t.tap(find.byKey(const Key('selection-all')));
      await io(t, rounds: 3);
      expect(find.text('3 selected'), findsOneWidget);
      await t.longPress(find.byKey(Key('book-${ids['Mango']}')));
      await io(t, rounds: 3);
      expect(find.byKey(Key('peek-${ids['Mango']}')), findsNothing, reason: 'no preview card while selecting');
      await t.tap(find.byKey(const Key('selection-close')));
      await io(t, rounds: 3);
      expect(find.byKey(const Key('selection-bar')), findsNothing);
      expect(find.byKey(Key('sel-${ids['Apple']}')), findsNothing);
      await end(t);
    });

    testWidgets('Select all only takes the books that are shown (respects filters)', (t) async {
      final (_, ids) = await open(t);
      await openSheet(t);
      await t.tap(find.byKey(const Key('tag-filter-work')));
      await io(t);
      await closeSheet(t);
      await t.tap(find.byKey(const Key('library-select')));
      await io(t, rounds: 3);
      await t.tap(find.byKey(const Key('selection-all')));
      await io(t, rounds: 3);
      expect(find.text('2 selected'), findsOneWidget, reason: 'Mango is hidden by the filter');
      expect(shown(t, ids), ['Apple', 'Zebra']);
      await end(t);
    });

    testWidgets('Tag: adds tags to all selected books and leaves selection mode', (t) async {
      final (env, ids) = await open(t);
      await t.tap(find.byKey(const Key('library-select')));
      await io(t, rounds: 3);
      await tapBook(t, ids, 'Apple');
      await tapBook(t, ids, 'Mango');
      await t.tap(find.byKey(const Key('bulk-tags')));
      await io(t, rounds: 3);
      await t.enterText(find.byKey(const Key('name-field')), 'to read, #urgent');
      await t.tap(find.byKey(const Key('name-ok')));
      await io(t);
      final r = {for (final b in await rows(t, env)) b.title: b.tags};
      expect(r['Apple'], '["work","to read","urgent"]');
      expect(r['Mango'], '["fiction","to read","urgent"]');
      expect(r['Zebra'], '["work","safety"]', reason: 'not selected, not touched');
      expect(find.byKey(const Key('selection-bar')), findsNothing);
      expect(find.textContaining('Added #to read #urgent to 2 books'), findsOneWidget);
      await end(t);
    });

    testWidgets('Shelf moves the selection; Favourite toggles (all favourite -> Unfavourite)', (t) async {
      final (env, ids) = await open(t);
      await t.tap(find.byKey(const Key('library-select')));
      await io(t, rounds: 3);
      await tapBook(t, ids, 'Zebra');
      await tapBook(t, ids, 'Apple');
      await t.tap(find.byKey(const Key('bulk-shelf')));
      await io(t, rounds: 3);
      await t.tap(find.byKey(Key('bulk-shelf-${ids['#shelf']}')));
      await io(t);
      var r = {for (final b in await rows(t, env)) b.title: b};
      expect((r['Zebra']!.shelfId, r['Apple']!.shelfId, r['Mango']!.shelfId), (ids['#shelf'], ids['#shelf'], null));

      await t.tap(find.byKey(const Key('library-select')));
      await io(t, rounds: 3);
      await tapBook(t, ids, 'Zebra');
      await t.tap(find.byKey(const Key('bulk-favorite')));
      await io(t);
      r = {for (final b in await rows(t, env)) b.title: b};
      expect(r['Zebra']!.favorite, 1);
      await t.tap(find.byKey(const Key('library-select')));
      await io(t, rounds: 3);
      await tapBook(t, ids, 'Zebra');
      expect(find.text('Unfavourite'), findsOneWidget);
      await t.tap(find.byKey(const Key('bulk-favorite')));
      await io(t);
      r = {for (final b in await rows(t, env)) b.title: b};
      expect(r['Zebra']!.favorite, 0);
      await end(t);
    });
  });

  group('manage tags', () {
    testWidgets('rename updates every book and an active filter on it; merging combines tags', (t) async {
      final (env, ids) = await open(t);
      await openSheet(t);
      await t.tap(find.byKey(const Key('tag-filter-work')));
      await io(t);
      await t.tap(find.byKey(const Key('manage-tags')));
      await io(t);
      await t.tap(find.byKey(const Key('tag-rename-work')));
      await io(t, rounds: 3);
      await t.enterText(find.byKey(const Key('name-field')), 'Job');
      await t.tap(find.byKey(const Key('name-ok')));
      await io(t);
      final rows1 = (await t.runAsync(() => env.db.select(env.db.books).get()))!;
      expect({for (final b in rows1) b.title: b.tags}['Apple'], '["Job"]');
      expect({for (final b in rows1) b.title: b.tags}['Zebra'], '["Job","safety"]');
      expect(find.byKey(const Key('tag-row-Job')), findsOneWidget);
      expect(find.byKey(const Key('tag-row-work')), findsNothing);

      // merge "safety" into "Job"
      await t.tap(find.byKey(const Key('tag-rename-safety')));
      await io(t, rounds: 3);
      await t.enterText(find.byKey(const Key('name-field')), 'job');
      await t.tap(find.byKey(const Key('name-ok')));
      await io(t);
      final zebra = (await t.runAsync(() => env.db.select(env.db.books).get()))!.firstWhere((b) => b.title == 'Zebra');
      expect(zebra.tags, '["Job"]');
      expect(find.text('2 books'), findsOneWidget);
      expect(find.byKey(const Key('tag-row-safety')), findsNothing);
      // the screen behind still shows the books that carry the renamed tag (the filter followed the rename)
      Navigator.of(t.element(find.byKey(const Key('tag-row-Job')))).pop();
      await io(t);
      Navigator.of(t.element(find.byKey(const Key('sort-title')))).pop();
      await io(t);
      expect(find.byKey(const Key('active-tag-Job')), findsOneWidget);
      expect(shown(t, ids), ['Apple', 'Zebra']);
      await end(t);
    });

    testWidgets('delete asks first, then removes the tag from all books (and from the active filter)', (t) async {
      final (env, ids) = await open(t);
      await openSheet(t);
      await t.tap(find.byKey(const Key('tag-filter-fiction')));
      await io(t);
      await t.tap(find.byKey(const Key('manage-tags')));
      await io(t);
      await t.tap(find.byKey(const Key('tag-delete-fiction')));
      await io(t, rounds: 3);
      expect(find.text('Remove #fiction?'), findsOneWidget);
      await t.tap(find.text('Cancel'));
      await io(t, rounds: 3);
      expect((await t.runAsync(() => env.db.select(env.db.books).get()))!.firstWhere((b) => b.title == 'Mango').tags, '["fiction"]');
      await t.tap(find.byKey(const Key('tag-delete-fiction')));
      await io(t, rounds: 3);
      await t.tap(find.byKey(const Key('tag-delete-confirm')));
      await io(t);
      expect((await t.runAsync(() => env.db.select(env.db.books).get()))!.firstWhere((b) => b.title == 'Mango').tags, '[]');
      expect(find.byKey(const Key('tag-row-fiction')), findsNothing);
      Navigator.of(t.element(find.byKey(const Key('tag-row-work')))).pop();
      await io(t);
      Navigator.of(t.element(find.byKey(const Key('sort-title')))).pop();
      await io(t);
      expect(find.byKey(const Key('active-filters')), findsNothing, reason: 'the deleted tag is no longer a filter');
      expect(shown(t, ids).length, 3);
      await end(t);
    });
  });
}
