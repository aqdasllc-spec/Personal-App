import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/features/library/application/export_ink.dart';
import 'package:folio/features/library/data/ink_export.dart';
import 'package:folio/features/library/data/library_repository.dart';
import 'package:folio/features/library/domain_ink.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/app/app.dart';

import '../../helpers.dart';
import 'reader_settings_test.dart' show io;

int pageCount(Uint8List pdf) => RegExp(r'/Type\s*/Page(?![a-z])').allMatches(latin1.decode(pdf, allowInvalid: true)).length;

void main() {
  final src = FakePdfInspectorFile();

  group('pngSize', () {
    test('reads the size of a PNG; anything else is null', () {
      expect(pngSize(FakePageImager.onePixel), (w: 1, h: 1));
      expect(pngSize(Uint8List.fromList([1, 2, 3])), isNull);
      expect(pngSize(Uint8List(40)), isNull);
    });
  });

  group('buildInkPdf', () {
    test('one PDF page per chosen page, drawings only where there are some; reports progress', () async {
      final progress = <(int, int)>[];
      final bytes = await buildInkPdf(
        source: src.file,
        pages: [1, 3, 5],
        ink: {
          3: [const Stroke(1, 0.004, [0.1, 0.1, 0.9, 0.9]), const Stroke(2, 0.002, [0.5, 0.5]), const Stroke(3, 0.02, [0.1, 0.5, 0.9, 0.5], highlighter: true)],
        },
        imager: FakePageImager(),
        onProgress: (d, t) => progress.add((d, t)),
      );
      expect(String.fromCharCodes(bytes!.take(5)), '%PDF-');
      expect(pageCount(bytes), 3);
      expect(progress, [(1, 3), (2, 3), (3, 3)]);
    });

    test('a page that cannot be drawn is skipped; if none can, there is no PDF', () async {
      final some = await buildInkPdf(source: src.file, pages: [1, 2, 3], ink: const {}, imager: FakePageImager(missing: {2}));
      expect(pageCount(some!), 2);
      expect(await buildInkPdf(source: src.file, pages: [1, 2], ink: const {}, imager: FakePageImager(missing: {1, 2})), isNull);
      expect(await buildInkPdf(source: src.file, pages: const [], ink: const {}, imager: FakePageImager()), isNull);
    });
  });

  test('drawnPages lists pages that have strokes, in order', () {
    expect(drawnPages({4: [const Stroke(0, 0.004, [0, 0])], 2: [const Stroke(0, 0.004, [0, 0])], 3: const []}), [2, 4]);
  });

  group('reader', () {
    Future<(TestEnv, BookRow)> open(WidgetTester t, {int pages = 6, Future<void> Function(LibraryRepository, BookRow)? seed}) async {
      t.view.physicalSize = const Size(411, 890);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final env = await TestEnv.create();
      addTearDown(env.db.close);
      late BookRow b;
      await t.runAsync(() async {
        final repo = LibraryRepository(env.db, directory: env.libraryDir, inspector: FakePdfInspector());
        b = (await repo.importPdf(await env.writePdf('My Book.pdf', pages))).book!;
        await repo.updateDetails(b.id, title: 'My Book');
        if (seed != null) await seed(repo, b);
      });
      await t.pumpWidget(ProviderScope(overrides: [...env.overrides, ...env.shareOverrides], child: const FolioApp()));
      await io(t);
      await t.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Library')));
      await io(t);
      await t.tap(find.byKey(Key('book-${b.id}')));
      await io(t);
      return (env, b);
    }

    void exportTest(String name, Future<void> Function(WidgetTester) body) => testWidgets(name, (t) async {
      await body(t);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
    });

    exportTest('no drawings: the menu has no export entry', (t) async {
      await open(t);
      await t.tap(find.byKey(const Key('reader-more')));
      await io(t, rounds: 2);
      expect(find.byKey(const Key('reader-export-ink')), findsNothing);
    });

    exportTest('with drawings: choose "pages with drawings" and a PDF is shared', (t) async {
      final (env, _) = await open(
        t,
        seed: (repo, b) async {
          await repo.saveInk(b.id, 2, [const Stroke(0, 0.004, [0.1, 0.1, 0.5, 0.5])]);
          await repo.saveInk(b.id, 5, [const Stroke(1, 0.004, [0.2, 0.2])]);
        },
      );
      await t.tap(find.byKey(const Key('reader-more')));
      await io(t, rounds: 2);
      await t.tap(find.byKey(const Key('reader-export-ink')));
      await io(t, rounds: 2);
      expect(find.text('Pages with drawings (2)'), findsOneWidget);
      expect(find.byKey(const Key('export-ink-this')), findsNothing, reason: 'page 1 has no drawings');
      await t.tap(find.byKey(const Key('export-ink-drawn')));
      await io(t, rounds: 12);
      expect(find.textContaining('PDF ready'), findsOneWidget, reason: 'message shown');
      expect(env.imager.asked, [2, 5]);
      expect(env.sharedFiles.single.$1, 'My Book with drawings.pdf');
      expect(env.sharedFiles.single.$3, '%PDF-');
      expect(find.textContaining('PDF ready to share (2 pages)'), findsOneWidget);
    });

    exportTest('the whole-book choice is greyed out for a long book', (t) async {
      await open(t, pages: 90, seed: (repo, b) => repo.saveInk(b.id, 1, [const Stroke(0, 0.004, [0.1, 0.1])]));
      await t.tap(find.byKey(const Key('reader-more')));
      await io(t, rounds: 2);
      await t.tap(find.byKey(const Key('reader-export-ink')));
      await io(t, rounds: 2);
      expect(t.widget<SimpleDialogOption>(find.byKey(const Key('export-ink-all'))).onPressed, isNull);
      expect(find.byKey(const Key('export-ink-this')), findsOneWidget, reason: 'page 1 has a drawing');
    });
  });
}

/// A stand-in file for the pure PDF builder (the fake imager never reads it).
class FakePdfInspectorFile {
  final file = File('unused.pdf');
}
