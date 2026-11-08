import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/features/library/data/library_repository.dart';
import 'package:folio/features/library/data/ocr.dart';
import 'package:folio/features/library/domain_highlights.dart';
import 'package:folio/features/library/domain_search_all.dart';

import '../../helpers.dart';
import 'reader_settings_test.dart' show io;

void main() {
  group('snippetsIn', () {
    test('text around the match, spacing and case ignored, with ellipses where cut', () {
      const text = 'The building PERMIT was approved on Monday after a long review by the committee of the town council members.';
      final s = snippetsIn(text, '  permit ', radius: 12);
      expect(s, ['…he building PERMIT was approve…']);
      expect(snippetsIn('a permit here', 'permit', radius: 50), ['a permit here'], reason: 'nothing cut: no ellipsis');
    });

    test('several matches are separate unless they are close; max is respected; blank query finds nothing', () {
      final text = 'permit ${'x' * 200} permit ${'y' * 200} permit';
      expect(snippetsIn(text, 'permit', max: 2).length, 2);
      expect(snippetsIn('permit permit permit', 'permit').length, 1, reason: 'the same stretch is reported once');
      expect(snippetsIn('anything', '  '), isEmpty);
      expect(snippetsIn('line one\n\n  line   two', 'one line'), ['line one line two']);
    });
  });

  group('screen', () {
    late List<BookRow> books;

    Future<TestEnv> open(WidgetTester t, {Future<void> Function(TestEnv, LibraryRepository, List<BookRow>)? seed}) async {
      t.view.physicalSize = const Size(411, 890);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final env = await TestEnv.create();
      addTearDown(env.db.close);
      await t.runAsync(() async {
        final repo = LibraryRepository(env.db, directory: env.libraryDir, inspector: FakePdfInspector());
        books = [];
        // Different page counts, so the three files differ (identical files are one book).
        for (final (title, pages) in [('Alpha', 12), ('Beta', 13), ('Gamma', 14)]) {
          final b = (await repo.importPdf(await env.writePdf('$title.pdf', pages))).book!;
          await repo.updateDetails(b.id, title: title);
          books.add(b);
        }
        env.pageTextsByBook[books[0].id] = {3: 'The building permit was approved on Monday.', 9: 'Second PERMIT mention on this page.'};
        env.pageTextsByBook[books[1].id] = {5: 'Nothing about it here.'};
        env.pageTextsByBook[books[2].id] = {}; // a scan: only searchable after "Make searchable"
        await repo.setTextState(books[2].id, 'ocr');
        await repo.savePageText(books[2].id, 4, const RecognizedPage([OcrLine('Scanned permit application form', 0.1, 0.1, 0.9, 0.2)]));
        if (seed != null) await seed(env, repo, books);
      });
      await t.pumpWidget(env.app);
      await io(t);
      await t.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Library')));
      await io(t);
      return env;
    }

    Future<void> endIt(WidgetTester t) async {
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
    }

    testWidgets('search all books: hits from text books and scanned books, grouped; a hit opens the reader at that page with the search ready', (t) async {
      await open(t);
      await t.tap(find.byKey(const Key('library-search-all')));
      await io(t, rounds: 3);
      expect(find.text('Search and notes'), findsOneWidget);
      await t.enterText(find.byKey(const Key('search-all-field')), 'permit');
      await t.testTextInput.receiveAction(TextInputAction.search);
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await io(t, rounds: 6);
      expect(find.byKey(const Key('search-all-status')), findsOneWidget);
      expect(find.text('3 places in 2 books'), findsOneWidget, reason: 'status was: ${t.widget<Text>(find.byKey(const Key('search-all-status'))).data}');
      expect(find.byKey(Key('hit-${books[0].id}-3')), findsOneWidget);
      expect(find.byKey(Key('hit-${books[0].id}-9')), findsOneWidget);
      expect(find.byKey(Key('hit-${books[2].id}-4')), findsOneWidget, reason: 'recognised text of a scan');
      expect(find.textContaining('PERMIT mention'), findsOneWidget);
      expect(find.text('Beta'), findsNothing, reason: 'no hits, no heading');

      await t.tap(find.byKey(Key('hit-${books[0].id}-9')));
      await io(t, rounds: 4);
      expect(find.text('PDF view page 9'), findsOneWidget, reason: 'opened at the hit page');
      expect(t.widget<TextField>(find.byKey(const Key('reader-search-field'))).controller!.text, 'permit');
      await t.pump(const Duration(seconds: 1));
      await endIt(t);
    });

    testWidgets('too short a query, and a query with no hits, are explained', (t) async {
      await open(t);
      await t.tap(find.byKey(const Key('library-search-all')));
      await io(t, rounds: 3);
      await t.enterText(find.byKey(const Key('search-all-field')), 'p');
      await t.testTextInput.receiveAction(TextInputAction.search);
      await io(t, rounds: 3);
      expect(find.textContaining('at least two letters'), findsOneWidget);
      await t.enterText(find.byKey(const Key('search-all-field')), 'zebra');
      await t.testTextInput.receiveAction(TextInputAction.search);
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await io(t, rounds: 6);
      expect(find.text('Nothing found for "zebra".'), findsOneWidget);
      await endIt(t);
    });

    testWidgets('highlights tab: all highlights with colour filters and counts, tap opens the book at the page, long-press names a colour', (t) async {
      final env = await open(t, seed: (env, repo, books) async {
        await repo.addHighlight(books[0].id, const HighlightDraft(page: 3, rects: [[0, 0, 1, 1]], text: 'first yellow passage'), color: 'yellow');
        await repo.addHighlight(books[1].id, const HighlightDraft(page: 5, rects: [[0, 0, 1, 1]], text: 'a green passage'), color: 'green');
        final id = await repo.addHighlight(books[1].id, const HighlightDraft(page: 6, rects: [[0, 0, 1, 1]], text: 'second yellow passage'), color: 'yellow');
        await repo.setHighlightNote(id, 'check this later');
      });
      await t.tap(find.byKey(const Key('library-search-all')));
      await io(t, rounds: 3);
      await t.tap(find.byKey(const Key('tab-all-highlights')));
      await io(t, rounds: 3);
      expect(find.text('All (3)'), findsOneWidget);
      expect(find.text('Yellow (2)'), findsOneWidget);
      expect(find.text('Green (1)'), findsOneWidget);
      expect(find.text('Blue (0)'), findsOneWidget);
      expect(find.text('first yellow passage'), findsOneWidget);
      expect(find.textContaining('check this later'), findsOneWidget);

      await t.tap(find.byKey(const Key('hl-filter-green')));
      await io(t, rounds: 2);
      expect(find.text('a green passage'), findsOneWidget);
      expect(find.text('first yellow passage'), findsNothing);
      await t.tap(find.byKey(const Key('hl-filter-blue')));
      await io(t, rounds: 2);
      expect(find.byKey(const Key('hl-empty')), findsOneWidget);

      // name a colour
      await t.longPress(find.byKey(const Key('hl-filter-yellow')));
      await io(t, rounds: 3);
      await t.enterText(find.byKey(const Key('meaning-field')), 'Important');
      await t.tap(find.byKey(const Key('meaning-save')));
      await io(t, rounds: 3);
      expect(find.text('Important (2)'), findsOneWidget);
      expect(await t.runAsync(() => env.store.state('highlight_meanings')), '{"yellow":"Important"}');

      // copy what is shown
      await t.tap(find.byKey(const Key('hl-filter-yellow')));
      await io(t, rounds: 2);
      String? copied;
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
        return null;
      });
      addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await t.tap(find.byKey(const Key('hl-copy')));
      await io(t, rounds: 2);
      expect(copied, contains('first yellow passage'));
      expect(copied, contains('Alpha, p. 3'));
      expect(copied, contains('Note: check this later'));
      expect(copied, isNot(contains('green passage')));

      await t.tap(find.text('first yellow passage'));
      await io(t, rounds: 4);
      expect(find.text('PDF view page 3'), findsOneWidget);
      await t.pump(const Duration(seconds: 1));
      await endIt(t);
    });
  });
}
