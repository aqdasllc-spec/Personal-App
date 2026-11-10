import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/features/library/presentation/reader_page.dart';

import '../../helpers.dart';

Future<void> io(WidgetTester t, {int rounds = 8}) async {
  for (var i = 0; i < rounds; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    for (var k = 0; k < 3; k++) {
      await t.pump(const Duration(milliseconds: 60));
    }
  }
  await t.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('"Open with Folio": the PDF is added to the Library and opened; again later: the same book, not a copy; the cache copy is removed', (t) async {
    t.view.physicalSize = const Size(411, 890);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final env = await TestEnv.create();
    addTearDown(env.db.close);
    final first = (await t.runAsync(() => env.writePdf('Handed over.pdf', 12)))!;
    env.openWith.first = first;
    await t.pumpWidget(env.app);
    await io(t, rounds: 14);
    expect(find.byType(ReaderPage), findsOneWidget);
    final books = (await t.runAsync(() => env.db.select(env.db.books).get()))!;
    expect(books.map((b) => b.title), ['Handed over']);
    expect(await t.runAsync(() => File(first).exists()), isFalse, reason: 'the Library keeps its own copy');

    await t.pageBack();
    await io(t);
    final again = (await t.runAsync(() => env.writePdf('Handed over.pdf', 12)))!;
    env.openWith.hand(again);
    await io(t, rounds: 10);
    expect(find.byType(ReaderPage), findsOneWidget);
    expect(find.textContaining('already in your Library'), findsOneWidget);
    expect((await t.runAsync(() => env.db.select(env.db.books).get()))!.length, 1);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('a file that is not a PDF is not added, and it says so', (t) async {
    t.view.physicalSize = const Size(411, 890);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final env = await TestEnv.create();
    addTearDown(env.db.close);
    await t.pumpWidget(env.app);
    await io(t, rounds: 10);
    final bad = (await t.runAsync(() async {
      final d = await Directory.systemTemp.createTemp('bad');
      final f = File('${d.path}/notes.pdf');
      await f.writeAsString('not a pdf at all');
      return f.path;
    }))!;
    env.openWith.hand(bad);
    await io(t, rounds: 20);
    expect(find.byType(ReaderPage), findsNothing);
    expect(find.textContaining('not a readable PDF'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  });
}
