import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/features/library/data/library_repository.dart';
import 'package:folio/features/library/data/ocr.dart';
import 'package:folio/features/library/domain_ocr.dart';

import '../../helpers.dart';
import 'reader_settings_test.dart' show io;

PageTextRow row(int page, List<OcrLine> lines) => PageTextRow(
  bookId: 'b',
  page: page,
  body: lines.map((l) => l.text).join('\n'),
  boxes: encodeLines(lines),
);

Future<(TestEnv, BookRow)> openScan(
  WidgetTester t, {
  bool? probe = false,
  FakeRecognizer? rec,
  String? textState,
  Future<void> Function(LibraryRepository, BookRow)? seed,
  int pages = 3,
}) async {
  t.view.physicalSize = const Size(411, 890);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final env = await TestEnv.create();
  addTearDown(env.db.close);
  env.probeResult = probe;
  env.recognizer = rec;
  late BookRow b;
  await t.runAsync(() async {
    final repo = LibraryRepository(
      env.db,
      directory: env.libraryDir,
      inspector: FakePdfInspector(),
    );
    b = (await repo.importPdf(await env.writePdf('scan.pdf', pages))).book!;
    if (textState != null) await repo.setTextState(b.id, textState);
    if (seed != null) await seed(repo, b);
  });
  await t.pumpWidget(env.app);
  await io(t);
  await t.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Library'),
    ),
  );
  await io(t);
  await t.tap(find.byKey(Key('book-${b.id}')));
  await io(t);
  return (env, b);
}

Future<String> stateOf(WidgetTester t, TestEnv env, String id) async =>
    (await t.runAsync(
      () => (env.db.select(env.db.books)..where((x) => x.id.equals(id))).getSingle(),
    ))!.textState;

const l1 = OcrLine('Dear Sir, the permit is attached', 0.1, 0.2, 0.9, 0.25);
const l2 = OcrLine('Nothing here', 0.1, 0.4, 0.5, 0.45);
const l3 = OcrLine('Second permit note', 0.1, 0.1, 0.6, 0.15);

void scanTest(String name, Future<void> Function(WidgetTester) body) =>
    testWidgets(name, (t) async {
      await body(t);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
    });

void main() {
  group('searching recognised text', () {
    test('case and spacing do not matter, hits come in page order', () {
      final hits = searchPages([
        row(3, [l3]),
        row(1, [l2, l1]),
      ], '  PERMIT ');
      expect(hits.map((h) => h.page), [1, 3]);
      expect(hits.first.line.text, l1.text);
    });

    test('a phrase wrapped over two lines is found once', () {
      const a = OcrLine('the building per', 0.1, 0.1, 0.9, 0.15);
      const b = OcrLine('mit was approved', 0.1, 0.16, 0.9, 0.2);
      final hits = searchPages([row(1, [a, b])], 'per mit');
      expect(hits.length, 1);
      expect(searchPages([row(1, [a, b])], 'approved was'), isEmpty);
      expect(searchPages([row(1, [a])], ''), isEmpty);
    });

    test('damaged stored data gives no lines instead of an error', () {
      expect(decodeLines('nonsense'), isEmpty);
      expect(decodeLines('[{"t":1},{"t":"ok","r":[0,0,1,1]}]').length, 1);
    });
  });

  group('repository', () {
    test('page text is saved, replaced, counted and cleared', () async {
      final env = await TestEnv.create();
      addTearDown(env.db.close);
      final repo = LibraryRepository(
        env.db,
        directory: env.libraryDir,
        inspector: FakePdfInspector(),
      );
      final b = (await repo.importPdf(await env.writePdf('a.pdf', 3))).book!;
      await repo.savePageText(b.id, 1, const RecognizedPage([l1]));
      await repo.savePageText(b.id, 1, const RecognizedPage([l2]));
      await repo.savePageText(b.id, 2, const RecognizedPage([]));
      expect(await repo.recognisedPages(b.id), {1, 2});
      expect((await repo.pageText(b.id, 1))!.body, l2.text);
      await repo.setTextState(b.id, 'ocr');
      await repo.clearPageTexts(b.id);
      expect(await repo.recognisedPages(b.id), isEmpty);
    });

    test('erasing a book also erases its page text', () async {
      final env = await TestEnv.create();
      addTearDown(env.db.close);
      final repo = LibraryRepository(
        env.db,
        directory: env.libraryDir,
        inspector: FakePdfInspector(),
      );
      final b = (await repo.importPdf(await env.writePdf('a.pdf', 3))).book!;
      await repo.savePageText(b.id, 1, const RecognizedPage([l1]));
      await repo.remove(b.id);
      await repo.deletePermanently(b.id);
      expect(await repo.pageTexts(b.id), isEmpty);
    });
  });

  group('reader', () {
    scanTest('a book with real text shows no scan banner and is marked as text', (t) async {
      final (env, b) = await openScan(t, probe: true, rec: FakeRecognizer({}));
      expect(find.byKey(const Key('ocr-banner')), findsNothing);
      expect(await stateOf(t, env, b.id), 'text');
    });

    scanTest('a scan offers "Make searchable" and reads every page', (t) async {
      final rec = FakeRecognizer({1: [l2], 2: [l1], 3: [l3]});
      final (env, b) = await openScan(t, rec: rec);
      expect(await stateOf(t, env, b.id), 'scanned');
      expect(find.byKey(const Key('ocr-start')), findsOneWidget);
      await t.tap(find.byKey(const Key('ocr-start')));
      await io(t, rounds: 10);
      expect(rec.asked, [1, 2, 3]);
      expect(await stateOf(t, env, b.id), 'ocr');
      expect(find.byKey(const Key('ocr-banner')), findsNothing);
    });

    scanTest('Stop keeps what was read and a second run carries on', (t) async {
      final rec = FakeRecognizer({1: [l2], 2: [l1], 3: [l3]});
      final gate = Completer<void>();
      rec.gate = gate; // hold the first page so there is time to press Stop
      final (env, b) = await openScan(t, rec: rec);
      await t.tap(find.byKey(const Key('ocr-start')));
      await io(t, rounds: 2);
      await t.tap(find.byKey(const Key('ocr-stop')));
      await t.runAsync(() async => gate.complete());
      rec.gate = null;
      await io(t, rounds: 10);
      final done = rec.asked.length;
      expect(done, 1, reason: 'stopped after the page in progress');
      expect(await stateOf(t, env, b.id), 'scanned', reason: 'not finished');
      expect(find.byKey(const Key('ocr-start')), findsOneWidget);
      await t.tap(find.byKey(const Key('ocr-start')));
      await io(t, rounds: 10);
      expect(rec.asked.toSet(), {1, 2, 3});
      expect(rec.asked.length, 3, reason: 'the page read before the stop is not read again');
      expect(await stateOf(t, env, b.id), 'ocr');
    });

    scanTest('on a device without a recogniser the banner explains', (t) async {
      await openScan(t);
      expect(find.textContaining('works on phones'), findsOneWidget);
      expect(find.byKey(const Key('ocr-start')), findsNothing);
    });

    scanTest('search uses the recognised text: count, next/prev wrap, jumps to the page', (t) async {
      final rec = FakeRecognizer({});
      final (env, _) = await openScan(
        t,
        rec: rec,
        textState: 'ocr',
        seed: (repo, b) async {
          await repo.savePageText(b.id, 1, const RecognizedPage([l2]));
          await repo.savePageText(b.id, 2, const RecognizedPage([l1]));
          await repo.savePageText(b.id, 3, const RecognizedPage([l3]));
        },
      );
      await t.tap(find.byKey(const Key('reader-search')));
      await io(t, rounds: 2);
      await t.enterText(find.byKey(const Key('reader-search-field')), 'permit');
      await io(t, rounds: 8);
      expect(find.text('1 / 2'), findsOneWidget);
      expect(env.jumps.last, 2);
      await t.tap(find.byKey(const Key('reader-search-next')));
      await io(t, rounds: 2);
      expect(find.text('2 / 2'), findsOneWidget);
      expect(env.jumps.last, 3);
      await t.tap(find.byKey(const Key('reader-search-next')));
      await io(t, rounds: 2);
      expect(find.text('1 / 2'), findsOneWidget, reason: 'wraps around');
      await t.tap(find.byKey(const Key('reader-search-prev')));
      await io(t, rounds: 2);
      expect(find.text('2 / 2'), findsOneWidget);
      await t.enterText(find.byKey(const Key('reader-search-field')), 'zebra');
      await io(t, rounds: 8);
      expect(find.text('No matches'), findsOneWidget);
    });

    scanTest('"Text of this page" shows the recognised text', (t) async {
      await openScan(
        t,
        rec: FakeRecognizer({}),
        textState: 'ocr',
        seed: (repo, b) => repo.savePageText(b.id, 1, const RecognizedPage([l1, l2])),
      );
      await t.tap(find.byKey(const Key('reader-more')));
      await io(t, rounds: 2);
      await t.tap(find.text('Text of this page'));
      await io(t, rounds: 4);
      expect(find.textContaining('the permit is attached'), findsOneWidget);
      expect(find.byKey(const Key('page-text-copy')), findsOneWidget);
    });

    scanTest('a text book can still be made searchable by hand (handwriting)', (t) async {
      final rec = FakeRecognizer({1: [l1]});
      final (env, b) = await openScan(t, probe: true, rec: rec, pages: 1);
      await t.tap(find.byKey(const Key('reader-more')));
      await io(t, rounds: 2);
      await t.tap(find.text('Make searchable (scans, handwriting)'));
      await io(t, rounds: 8);
      expect(rec.asked, [1]);
      expect(await stateOf(t, env, b.id), 'ocr');
    });
  });
}
