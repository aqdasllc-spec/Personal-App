import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/app/app.dart';
import 'package:folio/features/quran/data/quran_data.dart';
import 'package:folio/features/quran/domain/quran_search.dart';

import '../../helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('search', () {
    late QuranData q;
    late QuranSearchIndex ix;
    setUpAll(() async {
      q = await loadQuranAsset();
      ix = QuranSearchIndex.of(q);
    });

    List<String> refs(List<QuranHit> hits) => [for (final h in hits) '${q.refOf(h.index).$1}:${q.refOf(h.index).$2}'];

    test('Arabic in everyday spelling finds the Uthmani ayah (الصلاة is written ٱلصَّلَوٰةَ)', () {
      final r = refs(ix.find('الصلاة'));
      expect(r, contains('2:3'));
      expect(r, contains('2:43'));
      expect(refs(ix.find('صَبْر')).isNotEmpty, isTrue, reason: 'vowel marks in the query are ignored');
    });

    test('English matches words from their start; case and punctuation do not matter', () {
      final r = refs(ix.find('PATIENCE'));
      expect(r, containsAll(['2:45', '2:153']));
      final pray = ix.find('pray');
      expect(pray, isNotEmpty);
      expect(pray.every((h) => q.english[h.index].toLowerCase().contains(RegExp(r'\bpray'))), isTrue);
      expect(ix.find('x'), isEmpty, reason: 'at least two letters');
    });

    test('Arabic script also searches the Urdu translation; letter variants are folded', () {
      final hits = ix.find('صبر');
      expect(hits, isNotEmpty);
      expect(foldArabic('الْكِتَابُ'), 'الكتاب', reason: 'vowel marks go');
      expect(foldArabic('إِنَّ'), foldArabic('ان'), reason: 'alef forms are one');
      expect(foldArabic('ی ک ہ'), foldArabic('ي ك ه'));
      final urduOnly = ix.find('پرہیزگار'); // an Urdu word (not Arabic)
      expect(urduOnly, isNotEmpty);
      expect(urduOnly.every((h) => h.field == SearchField.urdu), isTrue);
    });
  });

  group('bookmarks and sharing (through the real app)', () {
    Future<void> wait(WidgetTester t, [int rounds = 8]) async {
      for (var i = 0; i < rounds; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 120)));
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    Future<TestEnv> open(WidgetTester t) async {
      t.view.physicalSize = const Size(411, 1400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final env = await TestEnv.create();
      addTearDown(env.db.close);
      await t.pumpWidget(ProviderScope(overrides: [...env.overrides, ...env.shareOverrides], child: const FolioApp()));
      await wait(t, 14);
      await t.tap(find.byKey(const Key('quran-open')));
      await wait(t, 10);
      return env;
    }

    Future<void> endIt(WidgetTester t) async {
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
    }

    testWidgets('search page: type, see the count, open a result at its ayah', (t) async {
      await open(t);
      await t.tap(find.byKey(const Key('quran-find')));
      await wait(t, 10);
      await t.enterText(find.byKey(const Key('quran-find-field')), 'patience');
      await wait(t, 4);
      expect(t.widget<Text>(find.byKey(const Key('quran-find-count'))).data, endsWith('ayahs'));
      await t.tap(find.byKey(const Key('find-2-45')));
      await wait(t, 8);
      expect(find.byKey(const Key('arabic-2-45')), findsOneWidget);
      await endIt(t);
    });

    testWidgets('bookmark an ayah with a note; it is listed in Bookmarks; edit and remove it', (t) async {
      final env = await open(t);
      await t.tap(find.byKey(const Key('surah-1')));
      await wait(t, 8);
      await t.tap(find.byKey(const Key('bm-1-2')));
      await wait(t, 4);
      await t.enterText(find.byKey(const Key('bookmark-note')), 'All praise');
      await t.tap(find.byKey(const Key('bookmark-save')));
      await wait(t, 4);
      expect(await t.runAsync(() => env.store.state('quran_bookmarks')), contains('All praise'));
      expect(t.widget<Icon>(find.descendant(of: find.byKey(const Key('bm-1-2')), matching: find.byType(Icon))).icon, Icons.bookmark);
      await t.pageBack();
      await wait(t, 4);
      await t.tap(find.byKey(const Key('quran-tab-bookmarks')));
      await wait(t, 10); // the tab slides in
      expect(find.byKey(const Key('bookmark-1-2')), findsOneWidget);
      expect(find.text('All praise'), findsOneWidget);
      await t.tap(find.byKey(const Key('bookmark-1-2')));
      await wait(t, 8);
      await t.tap(find.byKey(const Key('bm-1-2')));
      await wait(t, 4);
      await t.tap(find.byKey(const Key('bookmark-remove')));
      await wait(t, 4);
      expect(await t.runAsync(() => env.store.state('quran_bookmarks')), '[]');
      await endIt(t);
    });

    testWidgets('share an ayah: a picture card is made and handed to the share sheet; copy copies the text', (t) async {
      final env = await open(t);
      await t.tap(find.byKey(const Key('surah-1')));
      await wait(t, 8);
      await t.tap(find.byKey(const Key('share-1-1')));
      await wait(t, 4);
      expect(find.byKey(const Key('share-card')), findsOneWidget);
      await t.tap(find.byKey(const Key('share-mode-both')));
      await wait(t, 2);
      await t.tap(find.byKey(const Key('share-picture')));
      await wait(t, 12);
      expect(env.sharedFiles, isNotEmpty);
      final (name, subject, head) = env.sharedFiles.last;
      expect(name, 'quran-1-1.png');
      expect(subject, 'Quran 1:1');
      expect(head.codeUnits.take(4).toList(), [0x89, 0x50, 0x4E, 0x47], reason: 'a PNG');
      await endIt(t);
    });
  });
}
