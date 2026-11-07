import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/features/library/application/library_controller.dart';
import 'package:folio/features/library/data/library_repository.dart';
import 'package:folio/features/library/presentation/book_edit.dart';

import '../../helpers.dart';

BookRow bk(String id, {int pos = 0, int added = 0, String title = 'x'}) => BookRow(
      id: id,
      title: title,
      author: '',
      fileName: '',
      pageCount: 1,
      sizeBytes: 1,
      sha256: id,
      shelfId: null,
      favorite: 0,
      cloudState: 'local',
      sortPos: pos,
      tags: '[]',
      lastPage: 0,
      addedAt: added,
    );

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

/// Four books shown newest first: Delta, Charlie, Bravo, Alpha, and one shelf "Work".
Future<(TestEnv, Map<String, String>)> open(WidgetTester t, {String view = 'List'}) async {
  t.view.physicalSize = const Size(411, 890);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final env = await TestEnv.create();
  addTearDown(env.db.close);
  final ids = <String, String>{};
  await t.runAsync(() async {
    final repo = LibraryRepository(env.db, directory: env.libraryDir, inspector: FakePdfInspector());
    var n = 10;
    for (final title in ['Alpha', 'Bravo', 'Charlie', 'Delta']) {
      final b = (await repo.importPdf(await env.writePdf('$title.pdf', n++))).book!;
      await repo.updateDetails(b.id, title: title);
      ids[title] = b.id;
      await Future<void>.delayed(const Duration(milliseconds: 3));
    }
    ids['#shelf'] = (await repo.createShelf('Work')).id;
  });
  await t.pumpWidget(env.app);
  await io(t);
  await t.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Library')));
  await io(t);
  await t.tap(find.byTooltip(view));
  await io(t);
  return (env, ids);
}

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

Future<void> drag(WidgetTester t, Finder from, Finder to) async {
  final g = await t.startGesture(t.getCenter(from));
  await t.pump(const Duration(milliseconds: 100));
  final a = t.getCenter(from), b = t.getCenter(to);
  for (var k = 1; k <= 8; k++) {
    await g.moveTo(Offset.lerp(a, b, k / 8)!);
    await t.pump(const Duration(milliseconds: 40));
  }
  await g.up();
  await io(t, rounds: 3);
}

Finder book(Map<String, String> ids, String title) => find.byKey(Key('book-${ids[title]}'));

void main() {
  group('ordering logic', () {
    test('reorderIds: the dragged book takes the target\'s place', () {
      const ids = ['a', 'b', 'c', 'd'];
      expect(reorderIds(ids, 'a', 'c'), ['b', 'c', 'a', 'd']);
      expect(reorderIds(ids, 'd', 'b'), ['a', 'd', 'b', 'c']);
      expect(reorderIds(ids, 'b', 'b'), ids);
      expect(reorderIds(ids, 'x', 'b'), ids);
      expect(reorderIds(ids, 'a', 'x'), ids);
    });

    test('nudgeId moves one place and stops at the ends', () {
      const ids = ['a', 'b', 'c'];
      expect(nudgeId(ids, 'b', -1), ['b', 'a', 'c']);
      expect(nudgeId(ids, 'b', 1), ['a', 'c', 'b']);
      expect(nudgeId(ids, 'a', -1), ids);
      expect(nudgeId(ids, 'c', 1), ids);
      expect(nudgeId(ids, 'z', 1), ids);
    });

    test('"My order" sorts by position, newest first among equals', () {
      final books = [bk('a', pos: 2, added: 1), bk('b', pos: 0, added: 2), bk('c', pos: 1, added: 3), bk('d', pos: 0, added: 9)];
      expect(sortBooks(books, LibrarySort.manual).map((b) => b.id).toList(), ['d', 'b', 'c', 'a']);
    });
  });

  testWidgets('pen button: books wiggle, the preview card is off, Done stops it', (t) async {
    final (_, ids) = await open(t);
    expect(find.byType(Wiggle), findsNothing);
    await t.tap(find.byKey(const Key('library-edit')));
    await io(t, rounds: 3);
    expect(find.byKey(const Key('edit-bar')), findsOneWidget);
    expect(find.byType(Wiggle), findsNWidgets(4), reason: 'every book wiggles');
    final angle = t.widget<Transform>(find.descendant(of: find.byType(Wiggle).first, matching: find.byType(Transform)).first).transform.entry(0, 1);
    expect(angle, isNot(0), reason: 'it is actually rotating');
    await t.longPress(book(ids, 'Delta'));
    await io(t, rounds: 3);
    expect(find.byKey(Key('peek-${ids['Delta']}')), findsNothing);

    await t.tap(find.byKey(const Key('edit-done')));
    await io(t, rounds: 3);
    expect(find.byKey(const Key('edit-bar')), findsNothing);
    expect(find.byType(Wiggle), findsNothing);
    await end(t);
  });

  testWidgets('drag a book onto another: it takes that place; the order is saved and becomes "My order"', (t) async {
    final (env, ids) = await open(t);
    expect(shown(t, ids), ['Delta', 'Charlie', 'Bravo', 'Alpha']);
    await t.tap(find.byKey(const Key('library-edit')));
    await io(t, rounds: 3);
    await drag(t, book(ids, 'Delta'), book(ids, 'Bravo'));
    expect(shown(t, ids), ['Charlie', 'Bravo', 'Delta', 'Alpha']);
    final rows = {for (final b in (await t.runAsync(() => env.db.select(env.db.books).get()))!) b.title: b.sortPos};
    expect(rows['Charlie'], 0);
    expect(rows['Bravo'], 1);
    expect(rows['Delta'], 2);
    expect(rows['Alpha'], 3);
    expect(await t.runAsync(() => env.store.state('library_sort')), 'manual');

    await drag(t, book(ids, 'Alpha'), book(ids, 'Charlie'));
    expect(shown(t, ids), ['Alpha', 'Charlie', 'Bravo', 'Delta']);
    await end(t);
  });

  testWidgets('the order is kept after leaving rearrange mode and when switching views', (t) async {
    final (_, ids) = await open(t);
    await t.tap(find.byKey(const Key('library-edit')));
    await io(t, rounds: 3);
    await drag(t, book(ids, 'Alpha'), book(ids, 'Delta'));
    await t.tap(find.byKey(const Key('edit-done')));
    await io(t, rounds: 3);
    expect(shown(t, ids), ['Alpha', 'Delta', 'Charlie', 'Bravo']);
    await t.tap(find.byTooltip('Grid'));
    await io(t, rounds: 3);
    await t.tap(find.byTooltip('List'));
    await io(t, rounds: 3);
    expect(shown(t, ids), ['Alpha', 'Delta', 'Charlie', 'Bravo']);
    await end(t);
  });

  testWidgets('drop a book on a shelf name to move it there; on All books to take it off; on Favourites to star it', (t) async {
    final (env, ids) = await open(t);
    await t.tap(find.byKey(const Key('library-edit')));
    await io(t, rounds: 3);
    await drag(t, book(ids, 'Charlie'), find.byKey(Key('chip-shelf-${ids['#shelf']}')));
    var rows = {for (final b in (await t.runAsync(() => env.db.select(env.db.books).get()))!) b.title: b};
    expect(rows['Charlie']!.shelfId, ids['#shelf']);
    expect(find.text('Moved to the shelf.'), findsOneWidget);

    await drag(t, book(ids, 'Charlie'), find.byKey(const Key('chip-all')));
    rows = {for (final b in (await t.runAsync(() => env.db.select(env.db.books).get()))!) b.title: b};
    expect(rows['Charlie']!.shelfId, isNull);

    await drag(t, book(ids, 'Bravo'), find.byKey(const Key('chip-favorites')));
    rows = {for (final b in (await t.runAsync(() => env.db.select(env.db.books).get()))!) b.title: b};
    expect(rows['Bravo']!.favorite, 1);
    await end(t);
  });

  testWidgets('while a search is active the order cannot be changed (explained), but shelf drops still work', (t) async {
    final (env, ids) = await open(t);
    await t.enterText(find.byKey(const Key('library-search')), 'a'); // Alpha, Bravo, Charlie, Delta all contain "a"
    await io(t, rounds: 3);
    await t.tap(find.byKey(const Key('library-edit')));
    await io(t, rounds: 3);
    expect(find.textContaining('Clear the search and filters'), findsOneWidget);
    await drag(t, book(ids, 'Delta'), find.byKey(Key('chip-shelf-${ids['#shelf']}')));
    final rows = {for (final b in (await t.runAsync(() => env.db.select(env.db.books).get()))!) b.title: b};
    expect(rows['Delta']!.shelfId, ids['#shelf'], reason: 'moving to a shelf still works');
    await drag(t, book(ids, 'Charlie'), book(ids, 'Bravo'));
    final after = (await t.runAsync(() => env.db.select(env.db.books).get()))!;
    expect(after.every((b) => b.sortPos == 0), isTrue, reason: 'no reordering while filtered');
    expect(await t.runAsync(() => env.store.state('library_sort')), isNot('manual'));
    await end(t);
  });

  testWidgets('screen readers get "Move earlier / Move later" on every book', (t) async {
    final sem = t.ensureSemantics();
    final (_, ids) = await open(t);
    await t.tap(find.byKey(const Key('library-edit')));
    await io(t, rounds: 3);
    final node = t.getSemantics(find.bySemanticsLabel(RegExp(r'Alpha\. Rearranging')));
    final later = node.getSemanticsData().customSemanticsActionIds!;
    expect(later.length, 2);
    final labels = later.map((id) => CustomSemanticsAction.getAction(id)!.label).toSet();
    expect(labels, {'Move earlier', 'Move later'});
    // what "Move earlier" does: ask the page to nudge this book one place up
    final scope = t.element(find.byKey(Key('drag-book-${ids['Alpha']}'))).dependOnInheritedWidgetOfExactType<EditScope>()!;
    scope.onNudge(ids['Alpha']!, -1);
    await io(t, rounds: 6);
    expect(shown(t, ids), ['Delta', 'Charlie', 'Alpha', 'Bravo']);
    sem.dispose();
    await end(t);
  });

  testWidgets('shelf view and grid view work the same way', (t) async {
    for (final view in ['Shelf', 'Grid']) {
      final (_, ids) = await open(t, view: view);
      await t.tap(find.byKey(const Key('library-edit')));
      await io(t, rounds: 3);
      expect(find.byType(Wiggle), findsNWidgets(4), reason: view);
      await drag(t, book(ids, 'Delta'), book(ids, 'Alpha'));
      await t.tap(find.byKey(const Key('edit-done')));
      await io(t, rounds: 3);
      await end(t);
    }
  });
}
