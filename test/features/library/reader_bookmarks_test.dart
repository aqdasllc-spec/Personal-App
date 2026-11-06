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

Future<(TestEnv, BookRow)> openReader(WidgetTester t) async {
  t.view.physicalSize = const Size(411, 890);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final env = await TestEnv.create();
  addTearDown(env.db.close);
  late BookRow b;
  await t.runAsync(() async {
    final repo = LibraryRepository(env.db, directory: env.libraryDir, inspector: FakePdfInspector());
    b = (await repo.importPdf(await env.writePdf('x.pdf', 50))).book!;
  });
  await t.pumpWidget(env.app);
  await io(t);
  await t.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Library')));
  await io(t);
  await t.tap(find.byKey(Key('book-${b.id}')));
  await io(t);
  return (env, b);
}

Future<List<int>> pages(WidgetTester t, TestEnv e) async => (await t.runAsync(() => e.db.select(e.db.bookmarks).get()))!.map((m) => m.page).toList()..sort();

void main() {
  testWidgets('bookmark the current page, see it marked, list and jump to it, remove it', (t) async {
    final (env, _) = await openReader(t);
    expect(find.byIcon(Icons.bookmark_border), findsOneWidget);
    await t.tap(find.byKey(const Key('reader-bookmark')));
    await io(t);
    expect(await pages(t, env), [1]);
    expect(find.byIcon(Icons.bookmark), findsOneWidget, reason: 'the current page is marked');

    await t.tap(find.text('go to page 7'));
    await t.pump();
    await io(t, rounds: 2);
    expect(find.byIcon(Icons.bookmark_border), findsOneWidget, reason: 'page 7 is not marked');
    await t.tap(find.byKey(const Key('reader-bookmark')));
    await io(t);
    expect(await pages(t, env), [1, 7]);

    await t.tap(find.byKey(const Key('reader-bookmarks')));
    await io(t);
    expect(find.text('Page 1'), findsOneWidget);
    expect(find.text('Page 7'), findsOneWidget);
    await t.tap(find.byKey(const Key('bookmark-1')));
    await io(t);
    expect(env.jumps, [1], reason: 'tapping a bookmark jumps the reader to that page');

    await t.tap(find.byKey(const Key('reader-bookmarks')));
    await io(t);
    await t.tap(find.byKey(const Key('bookmark-delete-7')));
    await io(t);
    expect(await pages(t, env), [1]);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('with no bookmarks the list explains how to add one; tapping the mark twice removes it', (t) async {
    final (env, _) = await openReader(t);
    await t.tap(find.byKey(const Key('reader-bookmarks')));
    await io(t);
    expect(find.textContaining('No bookmarks yet'), findsOneWidget);
    await t.tapAt(const Offset(10, 10));
    await io(t);
    await t.tap(find.byKey(const Key('reader-bookmark')));
    await io(t);
    await t.tap(find.byKey(const Key('reader-bookmark')));
    await io(t);
    expect(await pages(t, env), isEmpty);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('search in the PDF: type, see the count, step through matches (wrapping), no matches, close', (t) async {
    final (env, _) = await openReader(t);
    await t.tap(find.byKey(const Key('reader-search')));
    await io(t);
    expect(find.byKey(const Key('reader-search-field')), findsOneWidget);
    await t.enterText(find.byKey(const Key('reader-search-field')), 'permit');
    await io(t, rounds: 3);
    expect(env.searches, ['permit']);
    expect(find.text('1 / 3'), findsOneWidget);

    await t.tap(find.byKey(const Key('reader-search-next')));
    await io(t, rounds: 2);
    expect(find.text('2 / 3'), findsOneWidget);
    await t.tap(find.byKey(const Key('reader-search-next')));
    await t.tap(find.byKey(const Key('reader-search-next')));
    await io(t, rounds: 2);
    expect(find.text('1 / 3'), findsOneWidget, reason: 'wraps from the last match to the first');
    await t.tap(find.byKey(const Key('reader-search-prev')));
    await io(t, rounds: 2);
    expect(find.text('3 / 3'), findsOneWidget, reason: 'and back');

    await t.enterText(find.byKey(const Key('reader-search-field')), 'zebra');
    await io(t, rounds: 3);
    expect(find.text('No matches'), findsOneWidget);
    final next = t.widget<IconButton>(find.byKey(const Key('reader-search-next')));
    expect(next.onPressed, isNull, reason: 'nothing to step through');

    await t.tap(find.byKey(const Key('reader-search-close')));
    await io(t);
    expect(env.searches.last, '<stop>');
    expect(find.byKey(const Key('reader-search-field')), findsNothing);
    expect(find.byKey(const Key('reader-bookmark')), findsOneWidget, reason: 'normal toolbar is back');
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('highlights: created from a selection, listed with the text, painted, recoloured, noted, jumped to, removed', (t) async {
    final (env, b) = await openReader(t);
    expect(find.text('painting 0 highlights'), findsOneWidget);
    await t.tap(find.text('select and highlight'));
    await io(t);
    final rows = (await t.runAsync(() => env.db.select(env.db.highlights).get()))!;
    expect(rows.length, 1);
    expect((rows.single.bookId, rows.single.page, rows.single.snippet, rows.single.color), (b.id, 3, 'an important passage', 'yellow'));
    expect(find.text('painting 1 highlights'), findsOneWidget, reason: 'handed to the PDF view for painting');
    expect(find.textContaining('Highlighted'), findsOneWidget);

    await t.tap(find.byKey(const Key('reader-bookmarks')));
    await io(t);
    await t.tap(find.byKey(const Key('tab-highlights')));
    await io(t);
    final id = rows.single.id;
    expect(find.text('an important passage'), findsOneWidget);
    expect(find.text('Page 3'), findsOneWidget);

    await t.tap(find.byKey(Key('hl-color-$id')));
    await io(t);
    expect((await t.runAsync(() => env.db.select(env.db.highlights).get()))!.single.color, 'green');

    await t.tap(find.byKey(Key('hl-note-$id')));
    await io(t);
    await t.enterText(find.byKey(const Key('note-field')), '  Check this with Ana ');
    await t.tap(find.byKey(const Key('note-save')));
    await io(t);
    expect((await t.runAsync(() => env.db.select(env.db.highlights).get()))!.single.note, 'Check this with Ana');
    expect(find.textContaining('Check this with Ana'), findsOneWidget);

    await t.tap(find.byKey(Key('highlight-$id')));
    await io(t);
    expect(env.jumps, [3], reason: 'tapping a highlight jumps to its page');

    await t.tap(find.byKey(const Key('reader-bookmarks')));
    await io(t);
    await t.tap(find.byKey(const Key('tab-highlights')));
    await io(t);
    await t.tap(find.byKey(Key('hl-delete-$id')));
    await io(t);
    expect(await t.runAsync(() => env.db.select(env.db.highlights).get()), isEmpty);
    expect(find.textContaining('No highlights yet'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  });
}
