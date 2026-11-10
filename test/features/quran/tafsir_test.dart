import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/app/app.dart';
import 'package:folio/features/quran/application/quran_downloads.dart' show fileFetcherProvider;
import 'package:folio/features/quran/data/tafsir.dart';

import '../../helpers.dart';

void main() {
  test('a surah\'s tafsir file in either shape; ayahs explained together are found', () {
    final a = SurahTafsir.parse(
      jsonEncode([
        {'surah': 2, 'ayah': 1, 'text': 'one'},
        {'surah': 2, 'ayah': 2, 'text': 'two and three'},
        {'surah': 2, 'ayah': 3, 'text': 'two and three'},
        {'surah': 2, 'ayah': 4, 'text': ''},
      ]),
    );
    expect(a.of(1), (text: 'one', from: 1, to: 1));
    expect(a.of(3), (text: 'two and three', from: 2, to: 3));
    expect(a.of(4), isNull);
    final b = SurahTafsir.parse(
      jsonEncode({
        'ayahs': [
          {'surah': 1, 'ayah': 1, 'text': 'x'},
        ],
      }),
    );
    expect(b.of(1)!.text, 'x');
    expect(() => SurahTafsir.parse('"nope"'), throwsFormatException);
    expect(
      tafsirUrls('ur-tafsir-bayan-ul-quran', 2).last.toString(),
      'https://raw.githubusercontent.com/spa5k/tafsir_api/main/tafsir/ur-tafsir-bayan-ul-quran/2.json',
    );
  });

  Future<void> wait(WidgetTester t, [int rounds = 8]) async {
    for (var i = 0; i < rounds; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  /// Until the tafsir has loaded (file work happens outside the test's clock).
  Future<void> loaded(WidgetTester t) async {
    for (
      var i = 0;
      i < 60 && find.descendant(of: find.byKey(const Key('tafsir-sheet')), matching: find.byType(CircularProgressIndicator)).evaluate().isNotEmpty;
      i++
    ) {
      await wait(t, 1);
    }
  }

  testWidgets('tafsir under an ayah: fetched once (CDN, then GitHub if that fails), kept on the phone, edition switch remembered', (t) async {
    t.view.physicalSize = const Size(411, 1400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final env = await TestEnv.create();
    addTearDown(env.db.close);
    final dir = await t.runAsync(() => Directory.systemTemp.createTemp('tafsir'));
    addTearDown(() => dir!.delete(recursive: true));
    final fetched = <Uri>[];
    var offline = false;
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          ...env.overrides,
          tafsirDirProvider.overrideWith((_) async => dir!),
          fileFetcherProvider.overrideWithValue((url, into) async {
            fetched.add(url);
            if (offline || url.host == 'cdn.jsdelivr.net') throw const SocketException('down');
            final slug = url.pathSegments[url.pathSegments.length - 2];
            final urdu = slug.startsWith('ur');
            await into.writeAsString(
              jsonEncode([
                for (var a = 1; a <= 7; a++)
                  {
                    'surah': 1,
                    'ayah': a,
                    'text': a == 2 || a == 3
                        ? (urdu ? 'دو اور تین کی تفسیر' : 'Two and three.')
                        : (urdu ? 'آیت $a کی تفسیر' : 'Ayah $a explained.\nالْحَمْدُ لِلَّهِ\nMore.'),
                  },
              ]),
            );
          }),
        ],
        child: const FolioApp(),
      ),
    );
    await wait(t, 14);
    await t.tap(find.byKey(const Key('quran-open')));
    await wait(t, 10);
    await t.tap(find.byKey(const Key('surah-1')));
    await wait(t, 8);
    await t.tap(find.byKey(const Key('tafsir-1-3')));
    await wait(t, 4);
    await loaded(t);
    expect(find.byKey(const Key('tafsir-sheet')), findsOneWidget);
    if (find.byKey(const Key('tafsir-error')).evaluate().isNotEmpty) fail(t.widget<Text>(find.byKey(const Key('tafsir-error'))).data!);
    expect(find.text('دو اور تین کی تفسیر'), findsOneWidget, reason: 'Urdu Ibn Kathir by default');
    expect(find.byKey(const Key('tafsir-together')), findsOneWidget);
    expect(fetched.map((u) => u.host), ['cdn.jsdelivr.net', 'raw.githubusercontent.com']);

    // English Ibn Kathir: its Arabic quotations are set in Arabic type
    await t.tap(find.byKey(const Key('tafsir-edition')));
    await wait(t, 3);
    await t.tap(find.textContaining('Tafsir Ibn Kathir — Hafiz Ibn Kathir (English').last);
    await wait(t, 4);
    await loaded(t);
    expect(find.text('Two and three.'), findsOneWidget);
    expect(await t.runAsync(() => env.store.state('quran_tafsir')), 'en-tafisr-ibn-kathir');
    await t.tapAt(const Offset(200, 40)); // close the sheet
    await wait(t, 4);

    // offline now: what was fetched is still there
    offline = true;
    final before = fetched.length;
    await t.tap(find.byKey(const Key('tafsir-1-5')));
    await wait(t, 4);
    await loaded(t);
    expect(find.text('Ayah 5 explained.'), findsOneWidget);
    expect(find.text('الْحَمْدُ لِلَّهِ'), findsOneWidget);
    expect(fetched.length, before, reason: 'read from the phone');
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('no internet the first time: says so, and Try again works once it is back', (t) async {
    t.view.physicalSize = const Size(411, 1400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final env = await TestEnv.create();
    addTearDown(env.db.close);
    final dir = await t.runAsync(() => Directory.systemTemp.createTemp('tafsir'));
    addTearDown(() => dir!.delete(recursive: true));
    var offline = true;
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          ...env.overrides,
          tafsirDirProvider.overrideWith((_) async => dir!),
          fileFetcherProvider.overrideWithValue((url, into) async {
            if (offline) throw const SocketException('no network');
            await into.writeAsString(
              jsonEncode([
                for (var a = 1; a <= 7; a++) {'surah': 1, 'ayah': a, 'text': 'تفسیر $a'},
              ]),
            );
          }),
        ],
        child: const FolioApp(),
      ),
    );
    await wait(t, 14);
    await t.tap(find.byKey(const Key('quran-open')));
    await wait(t, 10);
    await t.tap(find.byKey(const Key('surah-1')));
    await wait(t, 8);
    await t.tap(find.byKey(const Key('tafsir-1-1')));
    await wait(t, 4);
    await loaded(t);
    expect(t.widget<Text>(find.byKey(const Key('tafsir-error'))).data, contains('needs the internet the first time'));
    offline = false;
    await t.tap(find.byKey(const Key('tafsir-retry')));
    await wait(t, 4);
    await loaded(t);
    expect(find.text('تفسیر 1'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  });
}
