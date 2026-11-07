import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/features/library/data/library_repository.dart';

import 'package:folio/features/library/data/ocr.dart';
import 'package:folio/features/library/domain_ink.dart';
import 'package:folio/features/library/domain_lookup.dart';
import 'package:folio/features/library/data/speech.dart';

import '../../helpers.dart';
import 'reader_settings_test.dart' show io;

Future<(TestEnv, BookRow)> openIt(WidgetTester t, {Size size = const Size(411, 890), int pages = 5, String? textState, Future<void> Function(LibraryRepository, BookRow)? seed}) async {
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
    if (seed != null) await seed(repo, b); // before the app is up: database work while it runs can hang a test
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

  layoutTest('pen on: one slim bar (about 52 px) replaces the slider and tool row, and leaves most of the screen to the page', (t) async {
    await openIt(t);
    final before = t.getSize(find.byKey(const Key('reader-filter'))).height;
    await t.tap(find.byKey(const Key('reader-pen')));
    await io(t, rounds: 3);
    final bar = t.getSize(find.byKey(const Key('pen-bar')));
    expect(bar.height, lessThanOrEqualTo(60));
    expect(find.byKey(const Key('reader-slider')), findsNothing);
    expect(find.byKey(const Key('reader-tools')), findsNothing);
    final after = t.getSize(find.byKey(const Key('reader-filter'))).height;
    expect(after, greaterThanOrEqualTo(before - 4), reason: 'the page does not get smaller than with the normal bars');
    expect(after, greaterThan(890 * 0.7));
    // the bar's own buttons all fit on the screen
    for (final k in ['pen-style', 'pen-eraser', 'pen-undo', 'pen-clear', 'pen-done']) {
      final r = t.getRect(find.byKey(Key(k)));
      expect(r.right, lessThanOrEqualTo(411), reason: '$k is on screen');
      expect(r.height, greaterThanOrEqualTo(40));
    }
    await t.tap(find.byKey(const Key('pen-done')));
    await io(t, rounds: 3);
    expect(find.byKey(const Key('reader-tools')), findsOneWidget, reason: 'the normal bars come back');
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

  group('pages sheet', () {
    layoutTest('opens at the current page, marks bookmarks and drawings, a tap jumps and closes', (t) async {
      final (env, _) = await openIt(t, pages: 100, seed: (repo, b) async {
        await repo.toggleBookmark(b.id, 3);
        await repo.saveInk(b.id, 4, [const Stroke(0, 0.004, [0.1, 0.1, 0.2, 0.2])]);
        await repo.saveProgress(b.id, 60);
      });
      await t.tap(find.byKey(const Key('reader-pages')));
      await io(t, rounds: 4);
      expect(find.text('Pages (100)'), findsOneWidget);
      expect(find.byKey(const Key('page-grid')), findsOneWidget);
      expect(find.byKey(const Key('thumb-60')), findsOneWidget, reason: 'the grid opens at the page you are on');
      expect(find.byKey(const Key('thumb-1')), findsNothing, reason: 'only what is on screen is built');
      await t.tap(find.byKey(const Key('thumb-60')));
      await io(t, rounds: 3);
      expect(find.byKey(const Key('page-grid')), findsNothing, reason: 'closes after a pick');
      expect(env.jumps.last, 60);

      // markers: open again near the start
      await t.tap(find.byKey(const Key('reader-pages')));
      await io(t, rounds: 4);
      await t.drag(find.byKey(const Key('page-grid')), const Offset(0, 4000));
      await io(t, rounds: 3);
      expect(find.byKey(const Key('thumb-mark-3')), findsOneWidget);
      expect(find.byKey(const Key('thumb-ink-4')), findsOneWidget);
      expect(find.byKey(const Key('thumb-mark-4')), findsNothing);
      await t.tap(find.byKey(const Key('thumb-3')));
      await io(t, rounds: 3);
      expect(env.jumps.last, 3);
    });
  });

  group('look up', () {
    test('web addresses are built from tidy text', () {
      expect(cleanLookUp('  two\n  words  '), 'two words');
      expect(cleanLookUp('x' * 500).length, maxLookUpLength);
      expect(dictionaryUri('serendipity').toString(), 'https://www.google.com/search?q=define+serendipity');
      expect(translateUri('hello world', 'ur').toString(), 'https://translate.google.com/?sl=auto&tl=ur&text=hello+world&op=translate');
      expect(translateUri('x', '').queryParameters['tl'], 'en');
    });

    layoutTest('selected text opens a sheet; Meaning and Translate open the browser with that text', (t) async {
      final (env, _) = await openIt(t);
      await t.tap(find.text('look up selection'));
      await io(t, rounds: 3);
      expect(find.byKey(const Key('lookup-text')), findsOneWidget);
      expect(find.text('serendipity happy accident'), findsOneWidget);
      expect(find.textContaining('the selected text is sent to that website'), findsOneWidget);
      await t.tap(find.byKey(const Key('lookup-define')));
      await io(t, rounds: 3);
      expect(env.opened.single.queryParameters['q'], 'define serendipity happy accident');

      await t.tap(find.text('look up selection'));
      await io(t, rounds: 3);
      await t.tap(find.byKey(const Key('lookup-translate')));
      await io(t, rounds: 3);
      expect(env.opened.last.host, 'translate.google.com');
      expect(env.opened.last.queryParameters['text'], 'serendipity happy accident');
    });
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

    layoutTest('choose a voice: language list, pick one, it is used and remembered; "Phone default" clears it', (t) async {
      final (env, _) = await openIt(t, pages: 3);
      await t.tap(find.byKey(const Key('reader-listen')));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await io(t, rounds: 3);
      await t.tap(find.byKey(const Key('listen-voice')));
      await io(t, rounds: 4);
      expect(find.text('Voice for reading aloud'), findsOneWidget);
      expect(find.text('English (United States)'), findsWidgets);
      await t.tap(find.byKey(const Key('voice-language')));
      await io(t, rounds: 2);
      await t.tap(find.text('Hindi (India)').last);
      await io(t, rounds: 2);
      await t.tap(find.byKey(const Key('voice-hi-in-x-ccc-local')));
      await io(t, rounds: 4);
      expect(env.speech.chosen.last, const VoiceInfo('hi-in-x-ccc-local', 'hi-IN'));
      expect(await t.runAsync(() => env.store.state('tts_voice')), contains('hi-in-x-ccc-local'));

      await t.tap(find.byKey(const Key('listen-voice')));
      await io(t, rounds: 4);
      await t.tap(find.byKey(const Key('voice-default')));
      await io(t, rounds: 4);
      expect(env.speech.chosen.last, isNull);
      expect(await t.runAsync(() => env.store.state('tts_voice')), '');
    });

    layoutTest('a phone with no voices says how to add some', (t) async {
      final (env, _) = await openIt(t, pages: 3);
      env.speech.installed = const [];
      await t.tap(find.byKey(const Key('reader-listen')));
      await io(t, rounds: 3);
      await t.tap(find.byKey(const Key('listen-voice')));
      await io(t, rounds: 4);
      expect(find.byKey(const Key('voice-none')), findsOneWidget);
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
