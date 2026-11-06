import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/data/local/app_database.dart';

import '../../helpers.dart';

void _size(WidgetTester t, double w, double h) {
  t.view.physicalSize = Size(w, h);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

/// Real file/database work happens outside the fake clock; give it time, then draw frames.
Future<void> io(WidgetTester t) async {
  for (var i = 0; i < 300; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
    // Drift's stream timers live in the fake clock: several frames per round let them fire.
    for (var k = 0; k < 4; k++) {
      await t.pump(const Duration(milliseconds: 40));
    }
    if (i >= 2 && find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
  }
  await t.pumpAndSettle();
}

Future<TestEnv> open(WidgetTester t, {double w = 411, double h = 890}) async {
  _size(t, w, h);
  final env = await TestEnv.create();
  addTearDown(env.db.close);
  await t.pumpWidget(env.app);
  await t.pumpAndSettle();
  await t.tap(w < 600 ? find.descendant(of: find.byType(NavigationBar), matching: find.text('Library')) : (w < 900 ? find.byTooltip('Library') : find.text('Library')));
  await io(t);
  return env;
}

String makePdf(String name, int pages) {
  final f = File('${Directory.systemTemp.createTempSync('pick').path}/$name')..writeAsStringSync('pages=$pages');
  return f.path;
}

Future<List<BookRow>> books(WidgetTester t, TestEnv e) async => (await t.runAsync(() => e.db.select(e.db.books).get()))!;

Future<void> addBooks(WidgetTester t, TestEnv e, List<String> paths) async {
  e.picked = paths;
  await t.tap(find.byKey(const Key('library-add')));
  await io(t);
}

void main() {
  testWidgets('empty library invites you to add PDFs', (t) async {
    await open(t);
    expect(find.text('Your library is empty'), findsOneWidget);
    expect(find.text('Add PDFs'), findsWidgets);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('adding PDFs shows spines, reports duplicates and unreadable files', (t) async {
    final e = await open(t);
    final a = makePdf('Atomic_Habits.pdf', 300);
    final broken = File('${Directory.systemTemp.createTempSync('pick').path}/bad.pdf')..writeAsStringSync('nope');
    await addBooks(t, e, [a, a, broken.path]);
    final rows = await books(t, e);
    expect(rows.length, 1);
    expect(rows.single.title, 'Atomic Habits');
    expect(find.byKey(Key('book-${rows.single.id}')), findsOneWidget);
    expect(find.textContaining('Added 1 book'), findsOneWidget);
    expect(find.textContaining('1 already in your library'), findsOneWidget);
    expect(find.textContaining('couldn\'t read bad.pdf'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('search, grid and list views, favourites filter', (t) async {
    final e = await open(t);
    await addBooks(t, e, [makePdf('Alpha.pdf', 10), makePdf('Beta_Guide.pdf', 20)]);
    final rows = await books(t, e);
    expect(rows.length, 2);
    await t.tap(find.byTooltip('List'));
    await t.pumpAndSettle();
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta Guide'), findsOneWidget);
    await t.enterText(find.byKey(const Key('library-search')), 'beta');
    await t.pumpAndSettle();
    expect(find.text('Alpha'), findsNothing);
    expect(find.text('Beta Guide'), findsOneWidget);
    await t.enterText(find.byKey(const Key('library-search')), 'zzz');
    await t.pumpAndSettle();
    expect(find.textContaining('No book matches'), findsOneWidget);
    await t.tap(find.byTooltip('Clear search'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Grid'));
    await t.pumpAndSettle();
    expect(find.text('Alpha'), findsOneWidget);
    await t.tap(find.text('Favourites'));
    await t.pumpAndSettle();
    expect(find.text('Star a book to find it here.'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('book menu: favourite, edit details, shelf, remove with undo', (t) async {
    final e = await open(t);
    await addBooks(t, e, [makePdf('Alpha.pdf', 10)]);
    final id = (await books(t, e)).single.id;
    await t.tap(find.byTooltip('List'));
    await t.pumpAndSettle();
    await t.longPress(find.byKey(Key('book-$id')));
    await io(t);
    await t.tap(find.byKey(const Key('peek-more')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('book-favorite')));
    await io(t);
    expect((await books(t, e)).single.favorite, 1);

    await t.tap(find.byKey(const Key('book-edit')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('details-title')), 'Alpha Prime');
    await t.enterText(find.byKey(const Key('details-author')), 'A. Writer');
    await t.tap(find.byKey(const Key('details-save')));
    await io(t);
    expect((await books(t, e)).single.title, 'Alpha Prime');
    expect((await books(t, e)).single.author, 'A. Writer');

    await t.tap(find.byKey(const Key('book-remove')));
    await io(t);
    expect(find.text('Your library is empty'), findsOneWidget);
    await t.tap(find.text('Undo'));
    await io(t);
    expect(find.text('Alpha Prime'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('a new shelf is created and selected; adding while on it files the book there', (t) async {
    final e = await open(t);
    await t.tap(find.byKey(const Key('library-new-shelf')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('name-field')), 'Work');
    await t.tap(find.byKey(const Key('name-ok')));
    await io(t);
    expect(find.widgetWithText(ChoiceChip, 'Work', skipOffstage: false), findsOneWidget);
    await addBooks(t, e, [makePdf('Spec.pdf', 5)]);
    final b = (await books(t, e)).single;
    expect(b.shelfId, isNotNull);
    await t.tap(find.text('All books'));
    await t.pumpAndSettle();
    expect(find.byKey(Key('book-${b.id}')), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('opening a book shows the reader at the saved page, saves progress, and Back returns', (t) async {
    final e = await open(t);
    await addBooks(t, e, [makePdf('Alpha.pdf', 40)]);
    final id = (await books(t, e)).single.id;
    await t.tap(find.byKey(Key('book-$id')));
    await io(t);
    expect(find.text('PDF view page 0'), findsOneWidget, reason: 'never opened: starts at the beginning');
    await t.tap(find.text('go to page 7'));
    await t.pump();
    expect(find.byKey(const Key('reader-page')), findsOneWidget);
    await t.pageBack();
    await io(t);
    expect(find.byKey(Key('book-$id')), findsOneWidget);
    expect((await books(t, e)).single.lastPage, 7);
    expect((await books(t, e)).single.lastOpenedAt, isNotNull);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('wide and landscape layouts have no overflow', (t) async {
    for (final s in [const Size(1200, 800), const Size(850, 390)]) {
            final e = await open(t, w: s.width, h: s.height);
      await addBooks(t, e, [for (var i = 0; i < 14; i++) makePdf('Book_$i.pdf', 30 + i * 20)]);
      for (final tip in ['Shelf', 'Grid', 'List']) {
        await t.tap(find.byTooltip(tip));
        await t.pumpAndSettle();
      }
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
    }
  });
}
