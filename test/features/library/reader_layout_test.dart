import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/features/library/data/library_repository.dart';

import 'package:folio/features/library/data/ocr.dart';

import '../../helpers.dart';
import 'reader_settings_test.dart' show io;

Future<(TestEnv, BookRow)> openIt(WidgetTester t, {Size size = const Size(411, 890), int pages = 5, String? textState}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final env = await TestEnv.create();
  addTearDown(env.db.close);
  late BookRow b;
  await t.runAsync(() async {
    final repo = LibraryRepository(env.db, directory: env.libraryDir, inspector: FakePdfInspector());
    b = (await repo.importPdf(await env.writePdf('x.pdf', pages))).book!;
    if (textState != null) await repo.setTextState(b.id, textState);
  });
  await t.pumpWidget(env.app);
  await io(t);
  final bar = find.descendant(of: find.byType(NavigationBar), matching: find.text('Library'));
  await t.tap(bar.evaluate().isNotEmpty ? bar : find.text('Library').first); // phone: bottom bar, wide screen: side rail
  await io(t);
  await t.tap(find.byKey(Key('book-${b.id}')));
  await io(t);
  return (env, b);
}

void layoutTest(String name, Future<void> Function(WidgetTester) body) => testWidgets(name, (t) async {
  await body(t);
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 1));
});

void main() {
  layoutTest('top bar: title with page counter, Search, Aa, More; tools live in a row at the bottom', (t) async {
    await openIt(t);
    expect(find.byKey(const Key('reader-search')), findsOneWidget);
    expect(find.byKey(const Key('reader-settings')), findsOneWidget);
    expect(find.byKey(const Key('reader-more')), findsOneWidget);
    expect(find.text('1 / 5'), findsOneWidget);
    // the moved tools are in the bottom row, not in the app bar
    for (final k in ['reader-bookmarks', 'reader-bookmark', 'reader-pen', 'reader-listen']) {
      final box = t.getRect(find.byKey(Key(k)));
      expect(box.top, greaterThan(t.getRect(find.byKey(const Key('reader-slider'))).top), reason: '$k sits below the slider');
      expect(box.height, greaterThanOrEqualTo(48), reason: '$k is a comfortable tap target');
    }
    final slider = t.getRect(find.byKey(const Key('reader-slider')));
    expect(slider.width, greaterThan(150));
  });

  layoutTest('bookmark button from the tool row marks the page and says so', (t) async {
    await openIt(t);
    await t.tap(find.byKey(const Key('reader-bookmark')));
    await io(t, rounds: 3);
    expect(find.text('Marked'), findsOneWidget);
    await t.tap(find.byKey(const Key('reader-bookmark')));
    await io(t, rounds: 3);
    expect(find.text('Marked'), findsNothing);
  });

  layoutTest('small landscape phone: nothing overflows and the page keeps a usable area', (t) async {
    await openIt(t, size: const Size(850, 390));
    expect(t.takeException(), isNull);
    final area = t.getSize(find.byKey(const Key('reader-filter')));
    expect(area.height, greaterThan(200), reason: 'bars leave most of a 390 px screen to the page');
    await t.tap(find.byKey(const Key('reader-pen')));
    await io(t, rounds: 3);
    expect(t.takeException(), isNull);
  });

  layoutTest('at 2x text size the bottom row and the pen bar still fit', (t) async {
    await openIt(t);
    t.platformDispatcher.textScaleFactorTestValue = 2.0; // after opening: this checks the reader, not the shelf
    addTearDown(t.platformDispatcher.clearAllTestValues);
    await io(t, rounds: 2);
    await t.tap(find.byKey(const Key('reader-pen')));
    await io(t, rounds: 3);
    expect(t.takeException(), isNull);
  });

  group('listen (voice reader)', () {
    layoutTest('Listen reads the current page, then the next ones, following with the page', (t) async {
      final (env, _) = await openIt(t, pages: 3);
      await t.tap(find.byKey(const Key('reader-listen')));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await io(t, rounds: 4);
      expect(env.speech.spoken, ['First page text.', 'Second page text.', 'Third page text.']);
      expect(env.jumps, [1, 2, 3], reason: 'the page turned as it read');
      expect(find.byKey(const Key('listen-bar')), findsOneWidget);
      expect(find.text('Finished the book.'), findsOneWidget);
    });

    layoutTest('speed menu changes the speed; the close button hides the bar', (t) async {
      final (env, _) = await openIt(t, pages: 3);
      await t.tap(find.byKey(const Key('reader-listen')));
      await io(t, rounds: 3);
      await t.tap(find.byKey(const Key('listen-speed')));
      await io(t, rounds: 2);
      await t.tap(find.text('1.5x'));
      await io(t, rounds: 3);
      expect(env.speech.rates, [1.5]);
      expect(find.text('1.5x'), findsOneWidget);
      await t.tap(find.byKey(const Key('listen-close')));
      await io(t, rounds: 2);
      expect(find.byKey(const Key('listen-bar')), findsNothing);
    });

    layoutTest('a book with no text says what to do', (t) async {
      final (env, _) = await openIt(t, pages: 3);
      env.pageTexts.clear();
      await t.tap(find.byKey(const Key('reader-listen')));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await io(t, rounds: 3);
      expect(find.textContaining('Make searchable'), findsWidgets);
      expect(env.speech.spoken, isEmpty);
    });

    layoutTest('a scanned book is read from the text we recognised', (t) async {
      final (env, b) = await openIt(t, pages: 2, textState: 'ocr');
      await t.runAsync(() async {
        final repo = LibraryRepository(env.db, directory: env.libraryDir, inspector: FakePdfInspector());
        await repo.savePageText(b.id, 1, const RecognizedPage([OcrLine('Scanned words here.', 0.1, 0.1, 0.9, 0.2)]));
      });
      await t.tap(find.byKey(const Key('reader-listen')));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await io(t, rounds: 3);
      expect(env.speech.spoken.first, 'Scanned words here.');
    });

    layoutTest('lock-screen controls follow the reading and their buttons work', (t) async {
      final (env, _) = await openIt(t, pages: 3);
      expect(env.media.log, isEmpty);
      await t.tap(find.byKey(const Key('reader-listen')));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await io(t, rounds: 4);
      expect(env.media.log.any((l) => l.startsWith('x|')), isTrue, reason: 'shows the book title');
      expect(env.media.log.any((l) => l.contains('Page 2 of 3')), isTrue);
      expect(env.media.log.last, contains('Finished the book.'));
      // pressing Play on the lock screen reads again; Stop removes the controls and the bar
      unawaited(env.media.onPlay!());
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await io(t, rounds: 3);
      unawaited(env.media.onStop!());
      await io(t, rounds: 3);
      expect(env.media.log.last, 'hide');
      expect(find.byKey(const Key('listen-bar')), findsNothing);
    });

    layoutTest('leaving the reader stops the voice', (t) async {
      final (env, _) = await openIt(t, pages: 3);
      await t.tap(find.byKey(const Key('reader-listen')));
      await io(t, rounds: 2);
      final stops = env.speech.stops;
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
      expect(env.speech.stops, greaterThan(stops));
    });
  });
}
