import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/features/library/application/reader_prefs.dart';
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

Future<(TestEnv, BookRow)> openReader(WidgetTester t, {String? savedPrefs, int pages = 50}) async {
  t.view.physicalSize = const Size(411, 890);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final env = await TestEnv.create();
  addTearDown(env.db.close);
  late BookRow b;
  await t.runAsync(() async {
    final repo = LibraryRepository(env.db, directory: env.libraryDir, inspector: FakePdfInspector());
    b = (await repo.importPdf(await env.writePdf('x.pdf', pages))).book!;
    if (savedPrefs != null) await env.store.setState('reader_prefs', savedPrefs);
  });
  await t.pumpWidget(env.app);
  await io(t);
  await t.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Library')));
  await io(t);
  await t.tap(find.byKey(Key('book-${b.id}')));
  await io(t);
  return (env, b);
}

Future<void> openSheet(WidgetTester t) async {
  await t.tap(find.byKey(const Key('reader-settings')));
  await io(t, rounds: 3);
}

void main() {
  group('preferences', () {
    test('defaults, round trip, and forgiving parsing', () {
      const d = ReaderPrefs();
      expect((d.theme, d.dim, d.warmth, d.scroll, d.tapTurn, d.keepAwake, d.orientation), (ReaderTheme.normal, 0.0, 0.0, ReaderScroll.vertical, true, true, ReaderOrientation.auto));
      const p = ReaderPrefs(theme: ReaderTheme.sepia, dim: 0.3, warmth: 0.6, scroll: ReaderScroll.horizontal, tapTurn: false, keepAwake: false, orientation: ReaderOrientation.landscape);
      expect(ReaderPrefs.fromJson(p.toJson()), p);
      expect(ReaderPrefs.fromJson(null), const ReaderPrefs());
      expect(ReaderPrefs.fromJson('not json'), const ReaderPrefs());
      expect(ReaderPrefs.fromJson('{"theme":"neon","dim":9,"warmth":-3,"tapTurn":"x"}'), const ReaderPrefs(dim: 0.7), reason: 'unknown values fall back, numbers are clamped');
    });

    test('dim and warmth are clamped; every theme except Original filters the page', () {
      expect(const ReaderPrefs().copyWith(dim: 5, warmth: -1).dim, 0.7);
      expect(const ReaderPrefs().copyWith(dim: 5, warmth: -1).warmth, 0.0);
      expect(ReaderTheme.normal.filter, isNull);
      for (final t in ReaderTheme.values.where((t) => t != ReaderTheme.normal)) {
        expect(t.filter, isNotNull, reason: t.label);
      }
    });
  });

  testWidgets('settings sheet: pick a colour scheme, dim, warm light - applied at once and remembered', (t) async {
    final (env, _) = await openReader(t);
    expect(find.byKey(const Key('reader-dim-overlay')), findsNothing);
    await openSheet(t);
    await t.tap(find.byKey(const Key('reader-theme-night')));
    await io(t, rounds: 3);
    expect(find.text('prefs night vertical'), findsOneWidget, reason: 'the PDF view was told');
    expect(t.widget<ColorFiltered>(find.byKey(const Key('reader-filter'))).colorFilter, ReaderTheme.night.filter);
    await t.drag(find.byKey(const Key('reader-dim')), const Offset(120, 0));
    await t.drag(find.byKey(const Key('reader-warmth')), const Offset(150, 0));
    await io(t, rounds: 3);
    expect(find.byKey(const Key('reader-dim-overlay')), findsOneWidget);
    expect(find.byKey(const Key('reader-warm-overlay')), findsOneWidget);
    final saved = ReaderPrefs.fromJson(await t.runAsync<String?>(() => env.store.state('reader_prefs')));
    expect((saved.theme, saved.dim > 0, saved.warmth > 0), (ReaderTheme.night, true, true));

    await t.ensureVisible(find.byKey(const Key('reader-reset')));
    await t.pump();
    await t.tap(find.byKey(const Key('reader-reset')));
    await io(t, rounds: 3);
    expect(find.byKey(const Key('reader-dim-overlay')), findsNothing);
    expect(find.text('prefs normal vertical'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('saved preferences are used the next time a book is opened', (t) async {
    await openReader(t, savedPrefs: const ReaderPrefs(theme: ReaderTheme.sepia, scroll: ReaderScroll.horizontal).toJson());
    await io(t, rounds: 4);
    expect(find.text('prefs sepia horizontal'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('swipe sideways option reaches the viewer', (t) async {
    await openReader(t);
    await openSheet(t);
    await t.tap(find.text('Swipe sideways'));
    await io(t, rounds: 3);
    expect(find.text('prefs normal horizontal'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('tap zones: right edge = next page, left edge = previous, centre hides / shows the toolbar and system bars', (t) async {
    final (env, _) = await openReader(t);
    expect(find.byKey(const Key('reader-pagebar')), findsOneWidget);
    await t.tap(find.text('tap right'));
    await io(t, rounds: 3);
    expect(env.jumps, [2]);
    await t.tap(find.text('tap left'));
    await io(t, rounds: 3);
    expect(env.jumps, [2, 1]);
    await t.tap(find.text('tap left'));
    await io(t, rounds: 3);
    expect(env.jumps, [2, 1], reason: 'already on the first page');

    await t.tap(find.text('tap center'));
    await io(t, rounds: 3);
    expect(find.byKey(const Key('reader-settings')), findsNothing, reason: 'toolbar hidden');
    expect(find.byKey(const Key('reader-pagebar')), findsNothing);
    expect(env.readerSystem.immersive.last, isTrue);
    await t.tap(find.text('tap center'));
    await io(t, rounds: 3);
    expect(find.byKey(const Key('reader-settings')), findsOneWidget);
    expect(env.readerSystem.immersive.last, isFalse);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('with tap-to-turn switched off the edges do nothing (the centre still hides the toolbar)', (t) async {
    final (env, _) = await openReader(t, savedPrefs: const ReaderPrefs(tapTurn: false).toJson());
    await io(t, rounds: 3);
    await t.tap(find.text('tap right'));
    await io(t, rounds: 3);
    expect(env.jumps, isEmpty);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('orientation lock and keep-awake follow the settings and are released when leaving', (t) async {
    final (env, _) = await openReader(t);
    expect(env.awake, [true], reason: 'screen stays on while reading by default');
    await openSheet(t);
    await t.ensureVisible(find.text('Landscape'));
    await t.pump();
    await t.tap(find.text('Landscape'));
    await io(t, rounds: 3);
    expect(env.readerSystem.orientations.last, ReaderOrientation.landscape);
    await t.tap(find.byKey(const Key('reader-awake')));
    await io(t, rounds: 3);
    expect(env.awake.last, isFalse);
    await t.tap(find.byKey(const Key('reader-awake')));
    await io(t, rounds: 3);
    expect(env.awake.last, isTrue);
    Navigator.of(t.element(find.byKey(const Key('reader-reset')))).pop(); // close the sheet
    await io(t, rounds: 3);
    await t.pageBack();
    await io(t, rounds: 4);
    expect(env.awake.last, isFalse, reason: 'released on leaving the book');
    expect(env.readerSystem.immersive.last, isFalse);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('page slider: drag to jump to a page', (t) async {
    final (env, _) = await openReader(t);
    await t.drag(find.byKey(const Key('reader-slider')), const Offset(120, 0));
    await io(t, rounds: 4);
    expect(env.jumps, isNotEmpty);
    expect(env.jumps.last, greaterThan(10));
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('a one-page document has no slider', (t) async {
    await openReader(t, pages: 1);
    expect(find.byKey(const Key('reader-pagebar')), findsNothing);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  });
}
