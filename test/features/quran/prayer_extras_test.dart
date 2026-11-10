import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/app/app.dart';
import 'package:folio/app/router.dart';
import 'package:folio/design_system/theme.dart';
import 'package:folio/features/quran/prayer/prayer_cards.dart';
import 'package:folio/features/quran/prayer/prayer_providers.dart';
import 'package:go_router/go_router.dart';

import '../../helpers.dart';
import 'package:folio/features/quran/prayer/prayer.dart';
import 'package:folio/features/quran/prayer/qibla_page.dart';

void main() {
  const lahore = PrayerSettings(lat: 31.5204, lng: 74.3587, place: 'Lahore');

  test('Qibla from Lahore: about 260° (west, a little south), as an independent great-circle calculation gives', () {
    expect(qiblaBearing(31.5204, 74.3587), closeTo(260.37, .2));
    expect(compassPoint(260.37), 'W');
    expect(compassPoint(359), 'N');
  });

  test('compass heading from the sensors: flat, top to the north = 0°, to the east = 90°; tilt does not change it', () {
    expect(headingFrom([0, 0, 9.8], [0, 20, -40]), closeTo(0, .01));
    expect(headingFrom([0, 0, 9.8], [-20, 0, -40]), closeTo(90, .01));
    expect(headingFrom([0, 0, 9.8], [20, 0, -40]), closeTo(270, .01));
    // tilted forward 30°, still pointing north
    expect(headingFrom([0, 4.9, 8.49], [0, 20 * 0.866 + 40 * .5, -40 * .866 + 20 * .5]), closeTo(0, .5));
    expect(headingFrom([0, 0, 0], [0, 20, -40]), isNull);
  });

  test('more times: Tahajjud is the last third of the night (Maghrib to next Fajr), Ishraq 20 min after sunrise, zawal before Dhuhr', () {
    final d = DateTime(2026, 11, 10);
    final x = extraTimes(lahore, d);
    final day = prayerDay(lahore, d), next = prayerDay(lahore, DateTime(2026, 11, 11));
    final night = next.times[Prayer.fajr]!.difference(day.times[Prayer.maghrib]!);
    expect(x.lastThird, day.times[Prayer.maghrib]!.add(night * 2 ~/ 3));
    expect(x.midnight, day.times[Prayer.maghrib]!.add(night ~/ 2));
    expect(x.nextFajr, next.times[Prayer.fajr]);
    expect(x.ishraq, day.times[Prayer.sunrise]!.add(const Duration(minutes: 20)));
    expect((x.zawalTo, x.zawalTo.difference(x.zawalFrom)), (day.times[Prayer.dhuhr], const Duration(minutes: 10)));
    expect((x.sehriEnds, x.iftar), (day.times[Prayer.fajr], day.times[Prayer.maghrib]));
    expect(x.ramadan, isFalse, reason: '10 Nov 2026 is in Jumada al-Ula');
    // 1 Ramadan 1448 is around 10 Feb 2027 (Umm al-Qura)
    expect(extraTimes(lahore, DateTime(2027, 2, 20)).ramadan, isTrue);
  });

  group('prayer log and qaza', () {
    final d = DateTime(2026, 11, 10);
    test('mark prayed / missed / nothing; missed ones are qaza until made up', () {
      var l = const PrayerLog().mark(d, Prayer.fajr, false).mark(d, Prayer.dhuhr, true);
      expect((l.on(d, Prayer.fajr), l.on(d, Prayer.dhuhr), l.on(d, Prayer.asr)), (false, true, null));
      expect(l.owed(Prayer.fajr), 1);
      l = l.makeUp(Prayer.fajr);
      expect(l.owed(Prayer.fajr), 0);
      l = l.makeUp(Prayer.fajr);
      expect(l.owed(Prayer.fajr), 0, reason: 'never below zero');
      l = l.addPast(Prayer.isha, 354).mark(d, Prayer.dhuhr, null);
      expect((l.owed(Prayer.isha), l.owedTotal, l.on(d, Prayer.dhuhr)), (354, 354, null));
      expect(l.days.containsKey('2026-11-10'), isTrue);
      expect(l.mark(d, Prayer.fajr, null).days, isEmpty, reason: 'an empty day is dropped');
    });

    test('days in a row with all five prayed (today counts once complete)', () {
      var l = const PrayerLog();
      for (var i = 1; i <= 3; i++) {
        for (final p in Prayer.values.where((p) => p.isPrayer)) {
          l = l.mark(DateTime(2026, 11, 10 - i), p, true);
        }
      }
      expect(l.streak(d), 3);
      for (final p in [Prayer.fajr, Prayer.dhuhr, Prayer.asr, Prayer.maghrib]) {
        l = l.mark(d, p, true);
      }
      expect(l.streak(d), 3, reason: 'today not complete yet');
      expect(l.mark(d, Prayer.isha, true).streak(d), 4);
      expect(l.mark(DateTime(2026, 11, 8), Prayer.asr, false).streak(d), 1);
    });

    test('saved and read back; rubbish reads as empty', () {
      final l = const PrayerLog().mark(d, Prayer.fajr, true).mark(d, Prayer.isha, false).addPast(Prayer.asr, 7).makeUp(Prayer.asr, 2);
      final back = PrayerLog.decode(l.encode());
      expect((back.on(d, Prayer.fajr), back.on(d, Prayer.isha), back.owed(Prayer.asr), back.owed(Prayer.isha)), (true, false, 5, 1));
      expect(PrayerLog.decode('nonsense').days, isEmpty);
      expect(PrayerLog.decode(null).owedTotal, 0);
    });
  });

  group('on screen', () {
    Future<void> wait(WidgetTester t, [int rounds = 6]) async {
      for (var i = 0; i < rounds; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('log: tap Fajr once = prayed, twice = missed (qaza 1); Isha not yet; qaza sheet makes it up and adds past days', (t) async {
      t.view.physicalSize = const Size(411, 1400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final env = await TestEnv.create();
      addTearDown(env.db.close);
      final now = DateTime(2026, 11, 10, 8); // after Fajr, before Isha (Lahore times, in the test's time zone)
      await t.pumpWidget(ProviderScope(
        overrides: env.overrides,
        child: MaterialApp(theme: buildTheme(Brightness.light), home: Scaffold(body: ListView(children: [PrayerLogCard(settings: lahore, now: now)]))),
      ));
      await wait(t);
      final at = prayerDay(lahore, now).times;
      final asrBegun = !at[Prayer.asr]!.isAfter(now);
      await t.tap(find.byKey(const Key('log-fajr')));
      await wait(t, 2);
      final c = ProviderScope.containerOf(t.element(find.byType(PrayerLogCard)));
      expect(c.read(prayerLogProvider).on(now, Prayer.fajr), isTrue);
      await t.tap(find.byKey(const Key('log-fajr')));
      await wait(t, 2);
      expect(c.read(prayerLogProvider).on(now, Prayer.fajr), isFalse);
      expect(find.text('1 prayers'), findsOneWidget);
      await t.tap(find.byKey(const Key('log-isha')));
      await wait(t, 2);
      expect(c.read(prayerLogProvider).on(now, Prayer.isha), isNull, reason: 'its time has not come');
      expect(asrBegun || c.read(prayerLogProvider).on(now, Prayer.asr) == null, isTrue);
      expect(await t.runAsync(() => env.store.state('prayer_log')), contains('2026-11-10'));

      await t.tap(find.byKey(const Key('qaza-open')));
      await wait(t, 4);
      expect(t.widget<Text>(find.byKey(const Key('qaza-fajr'))).data, '1 to make up');
      await t.tap(find.byKey(const Key('qaza-made-fajr')));
      await wait(t, 2);
      expect(t.widget<Text>(find.byKey(const Key('qaza-fajr'))).data, '0 to make up');
      await t.tap(find.byKey(const Key('qaza-past')));
      await wait(t, 3);
      await t.enterText(find.byKey(const Key('qaza-past-n')), '2');
      await t.tap(find.text('Years'));
      await wait(t, 2);
      expect(find.text('Adds 708 of each prayer.'), findsOneWidget);
      await t.tap(find.byKey(const Key('qaza-past-add')));
      await wait(t, 3);
      expect(t.widget<Text>(find.byKey(const Key('qaza-asr'))).data, '708 to make up');
      expect(c.read(prayerLogProvider).owedTotal, 708 * 5);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('mosque times: +10 for Isha moves its time; the Qibla page shows the bearing and turns you to it', (t) async {
      t.view.physicalSize = const Size(411, 1400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final env = await TestEnv.create();
      addTearDown(env.db.close);
      await t.runAsync(() => env.store.setState('prayer_settings', lahore.encode()));
      final headings = StreamController<Heading>.broadcast();
      await t.pumpWidget(ProviderScope(
        overrides: [...env.overrides, headingStreamProvider.overrideWithValue(headings.stream)],
        child: const FolioApp(),
      ));
      await wait(t, 12);
      unawaited(GoRouter.of(t.element(find.byType(Scaffold).first)).push(Routes.prayer));
      await wait(t, 8);
      final before = t.widget<Text>(find.byKey(const Key('prayer-time-isha'))).data;
      await t.scrollUntilVisible(find.byKey(const Key('mosque-times')), 300, scrollable: find.descendant(of: find.byKey(const Key('prayer-page')), matching: find.byType(Scrollable)).first);
      await t.tap(find.byKey(const Key('mosque-times')));
      await wait(t, 3);
      for (var i = 0; i < 10; i++) {
        await t.tap(find.byKey(const Key('offset-plus-isha')));
        await t.pump();
      }
      expect(t.widget<Text>(find.byKey(const Key('offset-isha'))).data, '+10');
      await t.tap(find.byKey(const Key('offset-save')));
      await wait(t, 4);
      expect(find.text('Isha +10 min'), findsOneWidget);
      await t.scrollUntilVisible(find.byKey(const Key('prayer-time-isha')), -300, scrollable: find.descendant(of: find.byKey(const Key('prayer-page')), matching: find.byType(Scrollable)).first);
      expect(t.widget<Text>(find.byKey(const Key('prayer-time-isha'))).data, isNot(before));

      await t.tap(find.byKey(const Key('qibla-open')));
      await wait(t, 6);
      expect(t.widget<Text>(find.byKey(const Key('qibla-bearing'))).data, 'The Kaaba is 260° from north (W)');
      headings.add((degrees: 260.4, field: 45));
      await wait(t, 2);
      expect(t.widget<Text>(find.byKey(const Key('qibla-hint'))).data, 'You are facing the Qibla');
      for (var i = 0; i < 40; i++) {
        headings.add((degrees: 200, field: 45));
      }
      await wait(t, 3);
      expect(t.widget<Text>(find.byKey(const Key('qibla-hint'))).data, startsWith('Turn right'));
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
    });
  });
}
