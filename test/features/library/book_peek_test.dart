import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/features/library/data/library_repository.dart';

import '../../helpers.dart';

Future<void> io(WidgetTester t, {int rounds = 8}) async {
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

const longTitle = 'The Extremely Long and Wonderfully Descriptive Title of a Very Important Book: Second Edition';

Future<(TestEnv, BookRow)> open(WidgetTester t, {double w = 411, double h = 890, bool home = false}) async {
  t.view.physicalSize = Size(w, h);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final env = await TestEnv.create();
  addTearDown(env.db.close);
  late BookRow book;
  await t.runAsync(() async {
    final repo = LibraryRepository(env.db, directory: env.libraryDir, inspector: FakePdfInspector());
    book = (await repo.importPdf(await env.writePdf('x.pdf', 100))).book!;
    await repo.updateDetails(book.id, title: longTitle, author: 'Ada Lovelace');
    await repo.saveProgress(book.id, 25);
    book = (await repo.book(book.id))!;
  });
  await t.pumpWidget(env.app);
  await io(t);
  if (!home) {
    final nav = w < 600 ? find.descendant(of: find.byType(NavigationBar), matching: find.text('Library')) : (w < 900 ? find.byTooltip('Library') : find.bySemanticsLabel('Library').first);
    await t.tap(nav);
    await io(t);
  }
  return (env, book);
}

/// Waits (real time for file/database work) until [f] is on screen.
Future<void> waitFor(WidgetTester t, Finder f) async {
  for (var i = 0; i < 150 && f.evaluate().isEmpty; i++) {
    await io(t, rounds: 1);
  }
}

void main() {
  testWidgets('long-press a book on the shelf: a card with the first page, the FULL title, author and progress floats above it', (t) async {
    final (env, b) = await open(t);
    await t.longPress(find.byKey(Key('book-${b.id}')));
    await io(t);
    expect(find.byKey(Key('peek-${b.id}')), findsOneWidget);
    expect(find.descendant(of: find.byKey(Key('peek-${b.id}')), matching: find.text(longTitle)), findsOneWidget, reason: 'the spine truncates; the card shows everything');
    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(find.textContaining('100 pages · 25% read'), findsOneWidget);
    await waitFor(t, find.byKey(const Key('peek-image')));
    expect(find.byKey(const Key('peek-image')), findsOneWidget, reason: 'first page');
    expect(env.covers.calls, 1);
    // it sits above the spine, not over it
    expect(t.getRect(find.byKey(Key('peek-${b.id}'))).bottom, lessThanOrEqualTo(t.getRect(find.byKey(Key('book-${b.id}'))).top + 1));

    await t.tap(find.byKey(const Key('peek-barrier')), warnIfMissed: false);
    await io(t);
    expect(find.byKey(Key('peek-${b.id}')), findsNothing);
    await end(t);
  });

  testWidgets('the card\'s Read opens the reader on the saved page; More opens the book menu', (t) async {
    final (_, b) = await open(t);
    await t.longPress(find.byKey(Key('book-${b.id}')));
    await io(t);
    await t.tap(find.byKey(const Key('peek-read')));
    await io(t);
    expect(find.text('PDF view page 25'), findsOneWidget);
    await t.pageBack();
    await io(t);
    await t.longPress(find.byKey(Key('book-${b.id}')));
    await io(t);
    await t.tap(find.byKey(const Key('peek-more')));
    await io(t);
    expect(find.byKey(const Key('book-open')), findsOneWidget);
    await end(t);
  });

  testWidgets('mouse hover shows the card after a short delay (no buttons), leaving hides it, clicking opens the book', (t) async {
    final (_, b) = await open(t, w: 1200, h: 800);
    final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(5, 5));
    addTearDown(mouse.removePointer);
    await mouse.moveTo(t.getCenter(find.byKey(Key('book-${b.id}'))));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.byKey(Key('peek-${b.id}')), findsNothing, reason: 'not instantly: avoids flicker while moving across the shelf');
    await io(t, rounds: 3);
    expect(find.byKey(Key('peek-${b.id}')), findsOneWidget);
    expect(find.text(longTitle), findsWidgets);
    expect(find.byKey(const Key('peek-read')), findsNothing);

    await mouse.moveTo(const Offset(700, 700));
    await io(t, rounds: 2);
    expect(find.byKey(Key('peek-${b.id}')), findsNothing);

    await mouse.moveTo(t.getCenter(find.byKey(Key('book-${b.id}'))));
    await io(t, rounds: 3);
    expect(find.byKey(Key('peek-${b.id}')), findsOneWidget);
    await mouse.down(t.getCenter(find.byKey(Key('book-${b.id}'))));
    await mouse.up();
    await io(t);
    expect(find.byKey(Key('peek-${b.id}')), findsNothing);
    expect(find.text('PDF view page 25'), findsOneWidget);
    await end(t);
  });

  testWidgets('if the first page cannot be rendered the card still shows the name and a coloured cover; the render is cached on disk', (t) async {
    final (env, b) = await open(t);
    env.covers.bytes = null;
    await t.longPress(find.byKey(Key('book-${b.id}')));
    await io(t);
    expect(find.byKey(const Key('peek-image')), findsNothing);
    expect(find.text(longTitle), findsWidgets);
    await t.tap(find.byKey(const Key('peek-barrier')), warnIfMissed: false);
    await io(t);
    expect(Directory('${env.libraryDir.path}/covers').existsSync(), isFalse);

    env.covers.bytes = fakePng;
    // a fresh start (cache empty): renders once and writes the file
    await t.tap(find.byTooltip('Grid'));
    await io(t);
    await t.longPress(find.byKey(Key('book-${b.id}')));
    await io(t);
    await waitFor(t, find.byKey(const Key('peek-image')));
    expect(find.byKey(const Key('peek-image')), findsOneWidget);
    expect(File('${env.libraryDir.path}/covers/${b.id}.png').existsSync(), isTrue, reason: 'rendered once, cached on disk');
    await end(t);
  });

  testWidgets('works in grid and list views too', (t) async {
    final (_, b) = await open(t);
    for (final view in ['Grid', 'List']) {
      await t.tap(find.byTooltip(view));
      await io(t);
      await t.longPress(find.byKey(Key('book-${b.id}')));
      await io(t);
      expect(find.byKey(Key('peek-${b.id}')), findsOneWidget, reason: view);
      await t.tap(find.byKey(const Key('peek-barrier')), warnIfMissed: false);
      await io(t);
    }
    await end(t);
  });

  testWidgets('Home: long-press a recent book shows the same card; Read resumes', (t) async {
    final (_, b) = await open(t, home: true);
    await t.longPress(find.byKey(Key('home-book-${b.id}')));
    await io(t);
    expect(find.byKey(Key('peek-${b.id}')), findsOneWidget);
    expect(find.byKey(const Key('peek-more')), findsNothing, reason: 'Home has no book menu');
    await t.tap(find.byKey(const Key('peek-read')));
    await io(t);
    expect(find.text('PDF view page 25'), findsOneWidget);
    await end(t);
  });

  testWidgets('small landscape phone: the card stays on screen', (t) async {
    final (_, b) = await open(t, w: 850, h: 390);
    await t.longPress(find.byKey(Key('book-${b.id}')));
    await io(t);
    final r = t.getRect(find.byKey(Key('peek-${b.id}')));
    expect(r.left >= 0 && r.right <= 850, isTrue);
    expect(t.takeException(), isNull);
    await end(t);
  });
}
