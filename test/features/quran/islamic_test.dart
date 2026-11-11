import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/features/quran/prayer/islamic.dart';
import 'package:folio/features/quran/prayer/prayer.dart';
import 'package:folio/features/quran/prayer/prayer_providers.dart';

import '../../helpers.dart';

void main() {
  const lahore = PrayerSettings(lat: 31.5204, lng: 74.3587, alerts: {Prayer.fajr});
  final now = DateTime(2026, 11, 11, 10); // a Wednesday

  test('settings survive saving; rubbish gives the defaults', () {
    const s = IslamicSettings(kahf: true, kahfAt: (hour: 7, minute: 15), askPrayed: true, askAfterMinutes: 45, jumuah: true, khutbahAt: (hour: 13, minute: 15), jumuahBefore: 20, dates: false, monThu: true, whiteDays: true, eveningAt: (hour: 20, minute: 30));
    final b = IslamicSettings.decode(s.encode());
    expect((b.kahf, b.kahfAt, b.askPrayed, b.askAfterMinutes, b.jumuah, b.khutbahAt, b.jumuahBefore, b.dates, b.monThu, b.whiteDays, b.eveningAt), (true, (hour: 7, minute: 15), true, 45, true, (hour: 13, minute: 15), 20, false, true, true, (hour: 20, minute: 30)));
    expect(IslamicSettings.decode('x').dates, isTrue);
    expect(IslamicSettings.decode(null).askPrayed, isFalse);
  });

  test("Sunnah: Al-Kahf on Fridays, Al-Mulk every night, Jumu'ah before the khutbah", () {
    const s = IslamicSettings(kahf: true, mulk: true, jumuah: true, khutbahAt: (hour: 13, minute: 30), jumuahBefore: 30);
    final r = sunnahReminders(s, now, days: 7);
    final kahf = r.where((x) => x.payload == 'ayah:18:1').toList();
    expect(kahf.single.at, DateTime(2026, 11, 13, 9), reason: 'Friday 13 November');
    expect(r.where((x) => x.payload == 'ayah:67:1').length, 7);
    final j = r.singleWhere((x) => x.title.startsWith("Jumu'ah"));
    expect(j.at, DateTime(2026, 11, 13, 13));
    expect(r.map((x) => x.id).toSet().length, r.length);
    expect(sunnahReminders(const IslamicSettings(), now), isEmpty, reason: 'all off by default');
  });

  test('"Did you pray?": after each prayer, before the next one begins; not for prayers already marked', () {
    const s = IslamicSettings(askPrayed: true, askAfterMinutes: 120);
    final r = prayedChecks(lahore, s, now, days: 2);
    final day = prayerDay(lahore, DateTime(2026, 11, 12));
    final fajr = r.singleWhere((x) => x.payload == 'check:fajr:2026-11-12');
    expect(fajr.at, day.times[Prayer.sunrise]!.subtract(const Duration(minutes: 10)), reason: 'Fajr ends at sunrise: asked before');
    final dhuhr = r.singleWhere((x) => x.payload == 'check:dhuhr:2026-11-12');
    expect(dhuhr.at, day.times[Prayer.dhuhr]!.add(const Duration(minutes: 120)));
    final asr = r.singleWhere((x) => x.payload == 'check:asr:2026-11-12');
    expect(asr.at, day.times[Prayer.maghrib]!.subtract(const Duration(minutes: 10)), reason: 'Asr ends at Maghrib: asked before');
    expect(r.where((x) => x.payload.endsWith('2026-11-11')).every((x) => x.at.isAfter(now)), isTrue);
    final log = const PrayerLog().mark(DateTime(2026, 11, 12), Prayer.asr, true);
    expect(prayedChecks(lahore, s, now, days: 2, log: log).any((x) => x.payload == 'check:asr:2026-11-12'), isFalse);
    expect(prayedChecks(const PrayerSettings(), s, now), isEmpty, reason: 'no place, no times');
  });

  test('Islamic dates: the year in order, each on its Hijri date; Ramadan, both Eids and Arafah are there', () {
    final list = upcomingIslamicDates(now, 0, days: 400);
    for (final e in list) {
      final h = hijriDate(e.date, 0);
      expect((h.month, h.day), (e.day.month, e.day.day));
    }
    for (final d in [IslamicDay.ramadan, IslamicDay.eidFitr, IslamicDay.arafah, IslamicDay.eidAdha, IslamicDay.ashura, IslamicDay.shabEBarat, IslamicDay.qadr]) {
      expect(list.any((e) => e.day == d), isTrue, reason: d.english);
    }
    final ramadan = list.firstWhere((e) => e.day == IslamicDay.ramadan).date;
    final eid = list.firstWhere((e) => e.day == IslamicDay.eidFitr).date;
    expect(eid.difference(ramadan).inDays, inInclusiveRange(29, 30));
    // the moon-sighting adjustment moves them
    expect(upcomingIslamicDates(now, -1, days: 400).firstWhere((e) => e.day == IslamicDay.ramadan).date, ramadan.add(const Duration(days: 1)));
  });

  test('date reminders: the evening before; nights say "Tonight"; fasts not in Ramadan or on Eid', () {
    final ramadan = upcomingIslamicDates(now, 0).firstWhere((e) => e.day == IslamicDay.ramadan).date;
    final from = ramadan.subtract(const Duration(days: 3));
    const s = IslamicSettings(monThu: true, whiteDays: true, eveningAt: (hour: 21, minute: 0));
    final r = islamicDateReminders(s, 0, from, days: 40);
    final rem = r.firstWhere((x) => x.title.contains('Ramadan begins'));
    expect(rem.at, DateTime(ramadan.year, ramadan.month, ramadan.day - 1, 21));
    expect(rem.title, startsWith('Tomorrow'));
    expect(r.any((x) => x.title.startsWith('Tonight: Laylat al-Qadr')), isTrue);
    final fasts = r.where((x) => x.title.startsWith('Fast tomorrow')).map((x) => DateTime(x.at.year, x.at.month, x.at.day + 1));
    for (final d in fasts) {
      expect(hijriDate(d, 0).month, isNot(9), reason: 'not in Ramadan');
      expect(fastingForbidden(d, 0), isFalse);
    }
    expect(fastingForbidden(upcomingIslamicDates(now, 0).firstWhere((e) => e.day == IslamicDay.eidFitr).date, 0), isTrue);
    expect(r.map((x) => x.id).toSet().length, r.length);
  });

  test('Prayed / Missed answers (given while the app was closed) go into the prayer log', () async {
    final env = await TestEnv.create();
    addTearDown(env.db.close);
    final c = ProviderContainer(overrides: env.overrides);
    addTearDown(c.dispose);
    env.answers.addAll([('prayed', 'check:fajr:2026-11-11'), ('missed', 'check:asr:2026-11-11'), ('prayed', 'nonsense'), ('other', 'check:isha:2026-11-11')]);
    final n = await c.read(applyPrayerAnswersProvider)();
    expect(n, 2);
    final log = c.read(prayerLogProvider);
    final d = DateTime(2026, 11, 11);
    expect((log.on(d, Prayer.fajr), log.on(d, Prayer.asr), log.on(d, Prayer.isha)), (true, false, null));
    expect(log.owed(Prayer.asr), 1, reason: 'a missed prayer is qaza');
    expect(await c.read(applyPrayerAnswersProvider)(), 0, reason: 'taken once');
    await Future<void>.delayed(const Duration(milliseconds: 300)); // let the saves finish before the database closes
  });

  test('turning on "Did you pray?" and the fasts is remembered', () async {
    final env = await TestEnv.create();
    addTearDown(env.db.close);
    final c = ProviderContainer(overrides: env.overrides);
    addTearDown(c.dispose);
    await c.read(islamicRemindersProvider.notifier).set(const IslamicSettings(askPrayed: true, monThu: true));
    expect(await env.store.state('islamic_reminders'), contains('"ask":true'));
    expect(c.read(islamicRemindersProvider).monThu, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 300));
  });
}
