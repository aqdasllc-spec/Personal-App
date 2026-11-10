import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/app/app.dart';
import 'package:folio/features/library/application/read_aloud.dart' show mediaControlsProvider;
import 'package:folio/features/quran/application/quran_audio.dart';
import 'package:folio/features/quran/application/quran_providers.dart';
import 'package:folio/features/quran/data/quran_data.dart';
import 'package:folio/features/quran/domain/daily.dart';
import 'package:folio/features/quran/presentation/quran_style.dart';

import '../../helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('bundled texts', () {
    late QuranData q;
    late HadithData h;
    setUpAll(() async {
      q = await loadQuranAsset();
      h = await loadHadithAsset();
    });

    test('Indo-Pak text for every ayah (Indo-Pak marks, no stray direction marks); a view switches the script and the Urdu', () async {
      expect(q.indopak.length, 6236);
      expect(q.indopak.every((t) => t.trim().isNotEmpty && !t.contains('\u200f')), isTrue);
      expect(q.indopak[0], startsWith('بِسۡمِ'));
      expect(q.indopak[q.indexOf(1, 7)], contains('\u08E2'), reason: 'the small ۵ over عَلَيْهِمْ, as printed Indo-Pak Qurans have it');
      final ip = q.view(script: QuranScript.indopak);
      expect((ip.script, ip.arabic[5], ip.bismillah), (QuranScript.indopak, q.indopak[5], q.indopak[0]));
      expect(q.view(script: QuranScript.madinah).arabic[5], q.uthmani[5]);
      for (final tr in urduTranslations.skip(1)) {
        final texts = await loadUrduTranslation(tr.id);
        expect(texts.length, 6236, reason: tr.name);
        expect(texts.every((t) => t.trim().isNotEmpty), isTrue, reason: tr.name);
        // no old "presentation form" letters (fonts may not draw them), no footnote numbers
        expect(texts.any((t) => RegExp(r'[\uFB50-\uFD3D\uFD40-\uFDF1\uFDF3-\uFDF9\uFDFB-\uFDFF\uFE70-\uFEFF]|\[[۰-۹0-9]+\]').hasMatch(t)), isFalse, reason: tr.name);
      }
      final roman = await loadUrduTranslation('maududiroman');
      expect(roman[0], startsWith('Allah'));
      final v = q.view(script: QuranScript.indopak, urdu: roman, urduName: 'x', urduRtl: false);
      expect((v.urdu[0], v.urduRtl), (roman[0], false));
    });

    test('the whole Quran: 114 surahs, 6236 ayahs, three languages aligned, 30 juz, 15 sajdas', () {
      expect(q.surahs.length, 114);
      expect(q.ayahCount, 6236);
      expect(q.english.length, 6236);
      expect(q.urdu.length, 6236);
      expect(q.surahs.fold<int>(0, (s, x) => s + x.ayahCount), 6236);
      expect(q.arabic.every((t) => t.trim().isNotEmpty) && q.english.every((t) => t.trim().isNotEmpty) && q.urdu.every((t) => t.trim().isNotEmpty), isTrue);
      expect(q.surah(1).name, 'Al-Faatiha');
      expect(q.surah(1).ayahCount, 7);
      expect(q.surah(2).ayahCount, 286);
      expect(q.surah(114).ayahCount, 6);
      expect(q.english[q.indexOf(1, 1)], 'In the name of Allah, the Entirely Merciful, the Especially Merciful');
      expect(q.english[q.indexOf(2, 255)], startsWith('Allah - there is no deity except Him, the Ever-Living'));
      expect(q.bismillah, q.arabic[0]);
      expect(q.juzStarts.length, 30);
      expect(q.juzOf(2, 141), 1);
      expect(q.juzOf(2, 142), 2);
      expect(q.juzOf(114, 6), 30);
      expect(q.sajdas.length, 15);
      expect(q.sajdas.contains((32, 15)), isTrue);
    });

    test('positions: surah:ayah <-> position in the whole Quran (also the audio file number)', () {
      expect(q.indexOf(1, 1), 0);
      expect(q.indexOf(2, 1), 7);
      expect(q.indexOf(2, 255) + 1, 262, reason: 'Ayat al-Kursi is ayah 262 of the Quran');
      expect(q.indexOf(114, 6), 6235);
      for (final i in [0, 6, 7, 261, 1000, 4000, 6235]) {
        final (s, a) = q.refOf(i);
        expect(q.indexOf(s, a), i);
      }
      expect(q.valid(2, 286), isTrue);
      expect(q.valid(2, 287), isFalse);
      expect(q.valid(115, 1), isFalse);
    });

    test('every daily ayah reference exists; the pick is the same all day and changes the next day', () {
      for (final (s, from, to) in dailyAyahRefs) {
        expect(q.valid(s, from) && q.valid(s, to) && to >= from, isTrue, reason: '$s:$from-$to');
      }
      final a = dailyAyah(q, DateTime(2026, 11, 9, 7));
      final b = dailyAyah(q, DateTime(2026, 11, 9, 23));
      final c = dailyAyah(q, DateTime(2026, 11, 10, 7));
      expect(a.ref, b.ref);
      expect(c.ref, isNot(a.ref));
      expect(a.arabic.length, a.to - a.from + 1);
      expect(a.english.first, q.english[q.indexOf(a.surah.number, a.from)]);
    });

    test('hadith: every one in three languages; the card text is an exact part of the Urdu; a new one each day', () {
      expect(h.items.length, greaterThan(900));
      for (final x in h.items) {
        expect(x.arabic.isNotEmpty && x.english.isNotEmpty && x.urdu.isNotEmpty, isTrue);
        expect(x.english, startsWith('Narrated '));
        expect(x.sayingStart, greaterThan(0));
        expect(x.urduSaying, startsWith('…'));
        expect(x.urdu.endsWith(x.urduSaying.substring(1)), isTrue, reason: 'verbatim excerpt of ${x.reference}');
      }
      int gcd(int a, int b) => b == 0 ? a : gcd(b, a % b);
      expect(gcd(7919, h.items.length), 1, reason: 'the daily order visits every hadith before repeating');
      final seen = {for (var d = 0; d < 60; d++) dailyHadith(h, DateTime(2026, 1, 1).add(Duration(days: d))).number};
      expect(seen.length, 60);
      expect(dailyHadith(h, DateTime(2026, 3, 3, 1)).number, dailyHadith(h, DateTime(2026, 3, 3, 22)).number);
    });
  });

  group('recitation', () {
    late QuranData q;
    setUpAll(() async => q = await loadQuranAsset());

    test('reciter URLs name the ayah by its number in the whole Quran', () {
      expect(reciters.length, greaterThanOrEqualTo(10));
      expect(reciters.map((r) => r.id).toSet().length, reciters.length);
      expect(reciters.first.ayahUrl(262).toString(), 'https://cdn.islamic.network/quran/audio/128/ar.alafasy/262.mp3');
      expect(urduVoice.ayahUrl(1).toString(), 'https://cdn.islamic.network/quran/audio/64/ur.khan/1.mp3');
    });

    test('plays from an ayah to the end; reports the ayah playing; next / previous / stop', () async {
      final player = FakeAyahPlayer();
      final media = FakeMediaControls();
      final c = ProviderContainer(overrides: [
        ayahPlayerFactoryProvider.overrideWithValue(() => player),
        mediaControlsProvider.overrideWithValue(media),
      ]);
      addTearDown(c.dispose);
      final audio = c.read(quranAudioProvider.notifier);
      await audio.playFrom(q, 2, 255, to: 257);
      await pumpEventQueue();
      expect(player.queue.map((u) => u.pathSegments.last), ['262.mp3', '263.mp3', '264.mp3']);
      expect(c.read(quranAudioProvider).ayah, 255);
      expect(c.read(quranAudioProvider).playing, isTrue);
      player.finishCurrent();
      await pumpEventQueue();
      expect(c.read(quranAudioProvider).ayah, 256);
      await audio.next();
      await pumpEventQueue();
      expect(c.read(quranAudioProvider).ayah, 257);
      await audio.next(); // already at the last ayah of the range
      await pumpEventQueue();
      expect(c.read(quranAudioProvider).ayah, 257);
      await audio.previous();
      await pumpEventQueue();
      expect(c.read(quranAudioProvider).ayah, 256);
      player.finishCurrent();
      player.finishCurrent();
      await pumpEventQueue();
      expect(c.read(quranAudioProvider).active, isFalse, reason: 'finished');
      await audio.stop();
      expect(c.read(quranAudioProvider).surah, isNull);
    });

    test('with a spoken translation, each recited ayah is followed by its translation', () async {
      final player = FakeAyahPlayer();
      final c = ProviderContainer(overrides: [
        ayahPlayerFactoryProvider.overrideWithValue(() => player),
        mediaControlsProvider.overrideWithValue(FakeMediaControls()),
      ]);
      addTearDown(c.dispose);
      c.read(spokenTranslationProvider.notifier).set(SpokenTranslation.urdu);
      final audio = c.read(quranAudioProvider.notifier);
      await audio.playFrom(q, 1, 6);
      await pumpEventQueue();
      expect(player.queue.map((u) => u.path.split('/').skip(4).join('/')), [
        'ar.alafasy/6.mp3',
        'ur.khan/6.mp3',
        'ar.alafasy/7.mp3',
        'ur.khan/7.mp3',
      ]);
      player.finishCurrent();
      await pumpEventQueue();
      expect(c.read(quranAudioProvider).ayah, 6);
      expect(c.read(quranAudioProvider).translationTurn, isTrue);
      player.finishCurrent();
      await pumpEventQueue();
      expect(c.read(quranAudioProvider).ayah, 7);
      expect(c.read(quranAudioProvider).translationTurn, isFalse);
    });
  });

  group('Home cabinet and the Quran (through the real app)', () {
    Future<void> wait(WidgetTester t, [int rounds = 10]) async {
      for (var i = 0; i < rounds; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 120)));
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    Future<TestEnv> open(WidgetTester t, {bool share = false}) async {
      t.view.physicalSize = const Size(411, 890);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final env = await TestEnv.create();
      addTearDown(env.db.close);
      await t.pumpWidget(share ? ProviderScope(overrides: [...env.overrides, ...env.shareOverrides], child: const FolioApp()) : env.app);
      await wait(t, 14);
      return env;
    }

    Future<void> endIt(WidgetTester t) async {
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
    }

    testWidgets('the cabinet is low and full width; Urdu/English and Ayah/Hadith switch; the language is remembered', (t) async {
      final env = await open(t);
      final cab = t.getRect(find.byKey(const Key('quran-cabinet')));
      expect(cab.width, closeTo(411 - 32, 1), reason: 'full width');
      // with real fonts about 250 px of 890 (the test font is wider, so lines wrap more): a band, not the page
      expect(cab.height, lessThan(340), reason: 'a band, not the whole page (Home is ${t.view.physicalSize.height} high)');
      expect(find.byKey(const Key('daily-arabic')), findsOneWidget, reason: 'the ayah is shown first');
      // Urdu by default: the translation is in Urdu script
      expect(RegExp(r'[؀-ۿ]').hasMatch(textOf(t, find.byKey(const Key('daily-translation')))), isTrue);

      await t.tap(find.byKey(const Key('daily-lang-english')));
      await wait(t, 3);
      expect(textOf(t, find.byKey(const Key('daily-translation'))), matches(RegExp(r'^[\x00-\x7F\[\]]')));
      expect(await t.runAsync(() => env.store.state('quran_daily_lang')), 'en');

      await t.tap(find.byKey(const Key('daily-tab-hadith')));
      await wait(t, 3);
      expect(find.byKey(const Key('daily-arabic')), findsNothing);
      expect(t.widget<Text>(find.byKey(const Key('daily-reference'))).data, startsWith('Sahih al-Bukhari '));
      expect(textOf(t, find.byKey(const Key('daily-translation'))), startsWith('Narrated '));

      await t.tap(find.byKey(const Key('daily-lang-urdu')));
      await wait(t, 3);
      expect(t.widget<Text>(find.byKey(const Key('daily-reference'))).data, startsWith('صحیح بخاری'));
      expect(textOf(t, find.byKey(const Key('daily-translation'))), startsWith('…'), reason: 'from the Prophet\'s words, not the chain');
      await endIt(t);
    });

    testWidgets('tapping the Quran lights the lamp and opens the contents; a surah shows Arabic with the chosen translation', (t) async {
      final env = await open(t);
      await t.tap(find.byKey(const Key('quran-open')));
      await wait(t, 10);
      expect(find.byKey(const Key('surah-list')), findsOneWidget);
      expect(find.byKey(const Key('surah-1')), findsOneWidget);

      // search
      await t.enterText(find.byKey(const Key('surah-search')), 'yasin');
      await wait(t, 2);
      expect(find.byKey(const Key('surah-36')), findsOneWidget);
      expect(find.byKey(const Key('surah-1')), findsNothing);
      await t.enterText(find.byKey(const Key('surah-search')), 'fatiha');
      await wait(t, 2);
      expect(find.byKey(const Key('surah-1')), findsOneWidget, reason: 'Al-Faatiha, spelled the usual way');
      await t.enterText(find.byKey(const Key('surah-search')), '');
      await wait(t, 2);

      await t.tap(find.byKey(const Key('surah-1')));
      await wait(t, 8);
      final q = await t.runAsync(loadQuranAsset);
      expect(find.byKey(const Key('bismillah')), findsNothing, reason: 'Al-Fatiha starts with it as its first ayah');
      expect(textOf(t, find.byKey(const Key('arabic-1-1'))), startsWith(q!.indopak[0]), reason: 'the Indo-Pak script by default');
      expect(textOf(t, find.byKey(const Key('urdu-1-1'))), q.urdu[0], reason: 'Urdu by default');
      expect(find.byKey(const Key('english-1-1')), findsNothing);

      await t.tap(find.byKey(const Key('surah-more')));
      await wait(t, 3);
      await t.tap(find.byKey(const Key('translation-menu')));
      await wait(t, 5);
      await t.tap(find.byKey(const Key('translation-both')));
      await wait(t, 3);
      expect(textOf(t, find.byKey(const Key('english-1-1'))), q.english[0]);
      expect(await t.runAsync(() => env.store.state('quran_translation')), 'both');

      // remember this place (scroll down to ayah 3 first)
      await t.dragUntilVisible(find.byKey(const Key('mark-1-3')), find.byKey(const Key('ayah-list')), const Offset(0, -150));
      await wait(t, 2);
      await t.tap(find.byKey(const Key('mark-1-3')));
      await wait(t, 3);
      expect(await t.runAsync(() => env.store.state('quran_last_read')), '1:3');
      expect(find.textContaining('Saved 1:3 as your place'), findsOneWidget);
      await t.pump(const Duration(seconds: 1)); // the message slides in…
      await t.pump(const Duration(seconds: 3)); // …stays 2 seconds and goes
      await wait(t, 4);
      expect(find.byType(SnackBar), findsNothing);

      // listen from an ayah: the reciter's files for 1:4 onwards
      await t.dragUntilVisible(find.byKey(const Key('play-1-4')), find.byKey(const Key('ayah-list')), const Offset(0, -150));
      await wait(t, 2);
      await t.tap(find.byKey(const Key('play-1-4')));
      await wait(t, 3);
      expect(env.ayahPlayer.queue.map((u) => u.pathSegments.last), ['4.mp3', '5.mp3', '6.mp3', '7.mp3']);
      expect(find.byKey(const Key('quran-audio-bar')), findsOneWidget);
      await t.tap(find.byKey(const Key('audio-stop')));
      await wait(t, 2);
      expect(find.byKey(const Key('quran-audio-bar')), findsNothing);
      await endIt(t);
    });

    testWidgets('a surah other than 1 and 9 opens with the Bismillah; Back returns; Home then offers Continue', (t) async {
      await open(t);
      await t.tap(find.byKey(const Key('quran-open')));
      await wait(t, 10);
      await t.tap(find.byKey(const Key('surah-2')));
      await wait(t, 8);
      final q = await t.runAsync(loadQuranAsset);
      expect(t.widget<Text>(find.byKey(const Key('bismillah'))).data, q!.indopak[0]);
      await t.tap(find.byKey(const Key('mark-2-2')));
      await wait(t, 3);
      await t.pageBack();
      await wait(t, 4);
      await t.pageBack();
      await wait(t, 6);
      expect(find.byKey(const Key('quran-cabinet')), findsOneWidget);
      expect(find.byKey(const Key('quran-continue-label')), findsOneWidget);
      await endIt(t);
    });

    testWidgets('Quran settings: Madinah script instead of Indo-Pak; another Urdu translation (Roman Urdu reads left to right)', (t) async {
      final env = await open(t);
      await t.tap(find.byKey(const Key('quran-open')));
      await wait(t, 10);
      await t.tap(find.byKey(const Key('surah-1')));
      await wait(t, 8);
      final q = (await t.runAsync(loadQuranAsset))!;
      expect(textOf(t, find.byKey(const Key('arabic-1-2'))), contains('\u00A0﴿۲﴾'), reason: 'Urdu digits, kept on the line of the last word');
      await t.tap(find.byKey(const Key('surah-more')));
      await wait(t, 3);
      await t.tap(find.byKey(const Key('quran-text-settings')));
      await wait(t, 6);
      await t.tap(find.byKey(const Key('script-madinah')));
      await wait(t, 6);
      final sheet = find.descendant(of: find.byKey(const Key('quran-settings-sheet')), matching: find.byType(Scrollable)).first;
      await t.scrollUntilVisible(find.byKey(const Key('urdu-translation')), 100, scrollable: sheet);
      await t.tap(find.byKey(const Key('urdu-translation')));
      await wait(t, 4);
      await t.tap(find.textContaining('Taqi Usmani').last);
      await wait(t, 10);
      expect(await t.runAsync(() => env.store.state('quran_script')), 'madinah');
      expect(await t.runAsync(() => env.store.state('quran_urdu')), 'taqiusmani');
      await t.tapAt(const Offset(200, 30)); // close the sheet
      await wait(t, 6);
      expect(textOf(t, find.byKey(const Key('arabic-1-2'))), startsWith(q.uthmani[1]));
      expect(textOf(t, find.byKey(const Key('arabic-1-2'))), endsWith('﴿٢﴾'));
      final taqi = (await t.runAsync(() => loadUrduTranslation('taqiusmani')))!;
      expect(textOf(t, find.byKey(const Key('urdu-1-1'))), taqi[0]);
      await t.runAsync(() => env.store.setState('quran_urdu', 'maududiroman'));
      env.store.announcePrefChange('quran_urdu');
      await wait(t, 10);
      final w = t.widget<QuranTranslation>(find.byKey(const Key('urdu-1-1')));
      expect(w.text, startsWith('Allah'));
      expect(w.rtl, isFalse);
      await endIt(t);
    });

    testWidgets('the full ayah of the day: both languages a tap apart, Listen plays just those ayahs, Copy copies', (t) async {
      final env = await open(t);
      await t.tap(find.byKey(const Key('daily-open')));
      await wait(t, 4);
      expect(find.byKey(const Key('daily-sheet')), findsOneWidget);
      final q = (await t.runAsync(loadQuranAsset))!.view(script: QuranScript.indopak); // shown in the Indo-Pak script
      final d = dailyAyah(q, DateTime.now());
      final sheet = find.descendant(of: find.byKey(const Key('daily-sheet')), matching: find.byType(Scrollable)).first;
      await t.scrollUntilVisible(find.byKey(const Key('sheet-translation')), 150, scrollable: sheet);
      await wait(t, 2);
      expect(textOf(t, find.byKey(const Key('sheet-translation'))), d.urdu.join(' '));
      await t.scrollUntilVisible(find.byKey(const Key('sheet-lang')), -150, scrollable: sheet);
      await wait(t, 2);
      await t.tap(find.descendant(of: find.byKey(const Key('sheet-lang')), matching: find.text('English')));
      await wait(t, 3);
      await t.scrollUntilVisible(find.byKey(const Key('sheet-translation')), 150, scrollable: sheet);
      await wait(t, 2);
      expect(textOf(t, find.byKey(const Key('sheet-translation'))), d.english.join(' '));

      await t.scrollUntilVisible(find.byKey(const Key('sheet-listen')), 150, scrollable: sheet);
      await wait(t, 2);
      await t.tap(find.byKey(const Key('sheet-listen')));
      await wait(t, 3);
      expect(env.ayahPlayer.queue.length, d.to - d.from + 1);
      expect(env.ayahPlayer.queue.first.pathSegments.last, '${q.indexOf(d.surah.number, d.from) + 1}.mp3');

      String? copied;
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
        return null;
      });
      addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await t.scrollUntilVisible(find.byKey(const Key('sheet-copy')), 150, scrollable: sheet);
      await wait(t, 2);
      await t.tap(find.byKey(const Key('sheet-copy')));
      await wait(t, 2);
      expect(copied, contains(d.english.first));
      expect(copied, contains(d.arabic.first));
      await endIt(t);
    });

    testWidgets('share the hadith of the day as a picture: parchment card, Urdu / English / both, handed to the share sheet', (t) async {
      final env = await open(t, share: true);
      await t.tap(find.byKey(const Key('daily-tab-hadith')));
      await wait(t, 3);
      await t.tap(find.byKey(const Key('daily-open')));
      await wait(t, 4);
      final sheet = find.descendant(of: find.byKey(const Key('daily-sheet')), matching: find.byType(Scrollable)).first;
      await t.scrollUntilVisible(find.byKey(const Key('sheet-share')), 150, scrollable: sheet);
      await wait(t, 2);
      await t.tap(find.byKey(const Key('sheet-share')));
      await wait(t, 6);
      expect(find.byKey(const Key('daily-share-card')), findsOneWidget);
      expect(find.byKey(const Key('daily-share-urdu')), findsOneWidget, reason: 'Urdu by default, like the Home card');
      expect(find.byKey(const Key('daily-share-english')), findsNothing);
      final h = await t.runAsync(loadHadithAsset);
      final d = dailyHadith(h!, DateTime.now());
      expect(t.widget<Text>(find.byKey(const Key('daily-share-arabic'))).data, d.arabic);
      await t.ensureVisible(find.byKey(const Key('daily-share-lang')));
      await wait(t, 1);
      await t.tap(find.descendant(of: find.byKey(const Key('daily-share-lang')), matching: find.text('Both')));
      await wait(t, 2);
      expect(t.widget<Text>(find.byKey(const Key('daily-share-english'))).data, d.english);
      expect(t.widget<Text>(find.byKey(const Key('daily-share-date'))).data, contains('AH'));
      await t.ensureVisible(find.byKey(const Key('daily-share-go')));
      await t.tap(find.byKey(const Key('daily-share-go')));
      for (var i = 0; i < 30 && env.sharedFiles.isEmpty; i++) {
        await wait(t, 1);
      }
      expect(find.textContaining('Could not make'), findsNothing);
      final (name, subject, head) = env.sharedFiles.last;
      expect((name, subject), ('hadith-of-the-day.png', 'Hadith of the day · ${d.reference}'));
      expect(head.codeUnits.take(4).toList(), [0x89, 0x50, 0x4E, 0x47]);
      await endIt(t);
    });
  });
}
