import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/app/app.dart';
import 'package:folio/features/quran/application/quran_downloads.dart';
import 'package:folio/features/quran/data/quran_data.dart';

import '../../helpers.dart';

void main() {
  Future<void> wait(WidgetTester t, [int rounds = 8]) async {
    for (var i = 0; i < rounds; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('a para: Listen recites it across surahs; Download keeps its files for listening offline', (t) async {
    t.view.physicalSize = const Size(411, 1200);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final env = await TestEnv.create();
    addTearDown(env.db.close);
    final dir = (await t.runAsync(() => Directory.systemTemp.createTemp('para')))!;
    addTearDown(() => dir.delete(recursive: true));
    final fetched = <Uri>[];
    await t.pumpWidget(ProviderScope(
      overrides: [
        ...env.overrides,
        quranAudioDirProvider.overrideWith((_) async => dir),
        onMobileDataProvider.overrideWithValue(() async => false),
        fileFetcherProvider.overrideWithValue((url, into) async {
          fetched.add(url);
          await into.writeAsBytes([1, 2, 3]);
        }),
      ],
      child: const FolioApp(),
    ));
    await wait(t, 14);
    await t.tap(find.byKey(const Key('quran-open')));
    await wait(t, 10);
    await t.tap(find.byKey(const Key('quran-tab-juz')));
    await wait(t, 6);
    final q = (await t.runAsync(loadQuranAsset))!.view(script: QuranScript.indopak);
    final (from, to) = q.paraRange(1);
    expect((from, to), (0, q.indexOf(2, 141)), reason: 'para 1: Al-Fatiha and Al-Baqarah to 2:141');
    await t.tap(find.byKey(const Key('para-listen-1')));
    await wait(t, 4);
    expect(env.ayahPlayer.queue.length, to - from + 1);
    expect(env.ayahPlayer.queue.last.pathSegments.last, '${to + 1}.mp3');
    // it moves on from Al-Fatiha into Al-Baqarah
    for (var i = 0; i < 7; i++) {
      env.ayahPlayer.finishCurrent();
    }
    await wait(t, 3);
    expect(find.byKey(const Key('quran-audio-bar')), findsNothing, reason: 'the bar lives in the surah page');

    await t.tap(find.byKey(const Key('para-download-1')));
    for (var i = 0; i < 300 && fetched.length < to - from + 1; i++) {
      await wait(t, 1);
    }
    expect(fetched.length, to - from + 1);
    expect(fetched.map((u) => u.pathSegments.last).toSet(), {for (var i = from; i <= to; i++) '${i + 1}.mp3'});
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('Tilawat: Listen and follow recites from the page on screen to the end of its para and lights up the ayah', (t) async {
    t.view.physicalSize = const Size(411, 890);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final env = await TestEnv.create();
    addTearDown(env.db.close);
    await t.pumpWidget(env.app);
    await wait(t, 14);
    await t.tap(find.byKey(const Key('quran-open')));
    await wait(t, 10);
    await t.tap(find.byKey(const Key('surah-2')));
    await wait(t, 8);
    await t.tap(find.byKey(const Key('tilawat-open')));
    await wait(t, 10);
    await t.tap(find.byKey(const Key('tilawat-listen')));
    await wait(t, 4);
    final q = (await t.runAsync(loadQuranAsset))!.view(script: QuranScript.indopak);
    expect(env.ayahPlayer.queue.first.pathSegments.last, '${q.indexOf(2, 1) + 1}.mp3', reason: 'page 2 starts at 2:1');
    expect(env.ayahPlayer.queue.length, q.indexOf(2, 141) - q.indexOf(2, 1) + 1, reason: 'to the end of para 1');
    for (var i = 0; i < 3; i++) {
      env.ayahPlayer.finishCurrent();
    }
    await wait(t, 6);
    final lit = find.byWidgetPredicate((w) {
      if (w is! RichText) return false;
      var found = false;
      w.text.visitChildren((s) {
        if (s is TextSpan && s.style?.backgroundColor != null && s.text == q.arabic[q.indexOf(2, 4)]) found = true;
        return !found;
      });
      return found;
    });
    expect(lit, findsOneWidget, reason: '2:4 is being recited');
    await t.tap(find.byKey(const Key('tilawat-listen')));
    await wait(t, 2);
    expect(env.ayahPlayer.playing, isFalse, reason: 'paused');
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  });
}
