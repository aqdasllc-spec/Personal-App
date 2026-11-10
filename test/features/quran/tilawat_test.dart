import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/features/library/application/reader_prefs.dart' show ReaderOrientation;
import 'package:folio/features/quran/presentation/tilawat_page.dart';

import '../../helpers.dart';

void main() {
  test('Tilawat settings are remembered; speed stays 1-20; faster speed scrolls more', () {
    const s = TilawatSettings(speed: 9, night: false, translation: true, orientation: ReaderOrientation.landscape);
    final back = TilawatSettings.decode(s.encode());
    expect((back.speed, back.night, back.translation, back.orientation), (9, false, true, ReaderOrientation.landscape));
    expect(TilawatSettings.decode('99,1,0,auto').speed, 20);
    expect(TilawatSettings.decode(null).speed, 5);
    expect(const TilawatSettings(speed: 10).pixelsPerSecond, greaterThan(const TilawatSettings(speed: 2).pixelsPerSecond));
  });

  Future<void> wait(WidgetTester t, [int rounds = 8]) async {
    for (var i = 0; i < rounds; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('from a surah: full screen and awake; it scrolls by itself, faster when asked; rotation and night; closing puts it all back', (t) async {
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
    expect(find.byKey(const Key('tilawat-page')), findsOneWidget);
    expect(env.readerSystem.immersive.last, isTrue);
    expect(env.awake.last, isTrue);
    expect(find.byKey(const Key('tilawat-page-2')), findsOneWidget, reason: 'Al-Baqarah begins on page 2');
    expect(t.widget<Text>(find.byKey(const Key('tilawat-where'))).data, 'Page 2 of 604 · Juz 1');

    final scroll = t.widget<Scrollable>(find.descendant(of: find.byKey(const Key('tilawat-scroll')), matching: find.byType(Scrollable)).first);
    double offset() => scroll.controller!.offset;
    final before = offset();
    await t.tap(find.byKey(const Key('tilawat-play')));
    for (var i = 0; i < 20; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    final slow = offset() - before;
    expect(slow, greaterThan(20), reason: 'about 19 px a second at speed 5');
    for (var i = 0; i < 15; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const Key('tilawat-play')).hitTestable(), findsNothing, reason: 'controls hide while it scrolls');

    // tap to bring the controls back, then faster
    await t.tapAt(const Offset(200, 450));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    for (var i = 0; i < 5; i++) {
      await t.tap(find.byKey(const Key('tilawat-faster')));
      await t.pump(const Duration(milliseconds: 50));
    }
    expect(t.widget<Text>(find.byKey(const Key('tilawat-speed-label'))).data, 'Speed 10');
    final mid = offset();
    for (var i = 0; i < 20; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(offset() - mid, greaterThan(slow * 1.5));

    if (find.byKey(const Key('tilawat-play')).hitTestable().evaluate().isEmpty) {
      await t.tapAt(const Offset(200, 450));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
    }
    await t.tap(find.byKey(const Key('tilawat-play'))); // pause
    await t.pump(const Duration(milliseconds: 300));
    final paused = offset();
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(offset(), paused);

    await t.tap(find.byKey(const Key('tilawat-rotate')));
    await wait(t, 3);
    await t.tap(find.byKey(const Key('tilawat-rotate-landscape')));
    await wait(t, 3);
    expect(env.readerSystem.orientations.last, ReaderOrientation.landscape);
    await t.tap(find.byKey(const Key('tilawat-night')));
    await wait(t, 3);
    expect(await t.runAsync(() => env.store.state('quran_tilawat')), '10,0,0,landscape');

    await t.tap(find.byKey(const Key('tilawat-close')));
    await wait(t, 6);
    expect(find.byKey(const Key('tilawat-page')), findsNothing);
    expect(env.readerSystem.immersive.last, isFalse);
    expect(env.awake.last, isFalse);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  });
}
