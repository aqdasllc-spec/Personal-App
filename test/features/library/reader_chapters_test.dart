import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/app/app.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/features/library/data/library_repository.dart';
import 'package:folio/features/library/data/pdf_outline.dart';
import 'package:pdfrx/pdfrx.dart' show PdfDest, PdfDestCommand, PdfOutlineNode;

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

void main() {
  test('the outline tree is flattened in reading order with its depth; entries without a page are left out', () {
    PdfOutlineNode n(String title, int? page, [List<PdfOutlineNode> kids = const []]) =>
        PdfOutlineNode(title: title, dest: page == null ? null : PdfDest(page, PdfDestCommand.unknown, null), children: kids);
    final flat = flattenOutline([
      n('Preface', 3),
      n('Part I', null, [n('1. Beginnings', 7, [n('1.1 First steps', 9)]), n('2. Middle', 20)]),
      n('  ', 30),
    ]);
    expect([for (final c in flat) (c.title, c.page, c.depth)], [
      ('Preface', 3, 0),
      ('1. Beginnings', 7, 1),
      ('1.1 First steps', 9, 2),
      ('2. Middle', 20, 1),
    ]);
  });

  Future<(TestEnv, BookRow)> open(WidgetTester t, List<PdfChapter> chapters) async {
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
    await t.pumpWidget(ProviderScope(
      overrides: [...env.overrides, pdfOutlineReaderProvider.overrideWithValue((_) async => chapters)],
      child: const FolioApp(),
    ));
    await io(t);
    await t.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Library')));
    await io(t);
    await t.tap(find.byKey(Key('book-${b.id}')));
    await io(t);
    return (env, b);
  }

  testWidgets('Contents opens on the PDF\'s chapters; the one you are in is marked; tapping one goes there', (t) async {
    final (env, _) = await open(t, const [PdfChapter('Introduction', 1, 0), PdfChapter('Chapter 1', 5, 0), PdfChapter('A section', 8, 1), PdfChapter('Chapter 2', 30, 0)]);
    await t.tap(find.text('go to page 7'));
    await t.pump();
    await io(t, rounds: 2);
    await t.tap(find.byKey(const Key('reader-bookmarks')));
    await io(t);
    expect(find.byKey(const Key('chapter-list')), findsOneWidget);
    expect(find.text('Chapters (4)'), findsOneWidget);
    final current = t.widget<ListTile>(find.byKey(const Key('chapter-1')));
    expect(current.leading, isNotNull, reason: 'page 7 is in Chapter 1');
    expect(t.widget<ListTile>(find.byKey(const Key('chapter-2'))).leading, isNull);
    await t.tap(find.byKey(const Key('chapter-3')));
    await io(t);
    expect(env.jumps.last, 30);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('a PDF without a table of contents: Contents opens on bookmarks, and Chapters says so', (t) async {
    await open(t, const []);
    await t.tap(find.byKey(const Key('reader-bookmarks')));
    await io(t);
    expect(find.byKey(const Key('chapter-list')), findsNothing);
    await t.tap(find.byKey(const Key('tab-chapters')));
    await io(t);
    expect(find.textContaining('no table of contents'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  });
}
