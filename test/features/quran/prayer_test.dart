import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/app/app.dart';
import 'package:folio/features/planner/application/planner_controller.dart' show reminderSchedulerProvider;
import 'package:folio/features/planner/data/reminder_scheduler.dart';
import 'package:folio/features/planner/domain/reminders.dart';
import 'package:folio/features/quran/prayer/prayer.dart';
import 'package:folio/features/quran/prayer/prayer_page.dart' show urduClock;
import 'package:folio/features/quran/prayer/prayer_providers.dart';

import '../../helpers.dart';

/// Lahore, 10 Nov 2026, Karachi method, Hanafi Asr. Reference times (Pakistan time, UTC+5) from an independent
/// implementation of the standard formulas (PrayTimes / NOAA): Fajr 05:02, Sunrise 06:26, Dhuhr 11:46, Asr 15:30,
/// Maghrib 17:07, Isha 18:30. A minute either way is rounding.
const lahore = PrayerSettings(lat: 31.5204, lng: 74.3587, place: 'Lahore');

DateTime pkt(DateTime t) => t.toUtc().add(const Duration(hours: 5));
int minutes(DateTime t) => pkt(t).hour * 60 + pkt(t).minute;

class _Scheduler extends NoopReminderScheduler {
  List<Reminder> prayer = [];
  final tests = <Reminder>[];
  @override
  Future<bool> testPrayerAlarm(Reminder r) async {
    tests.add(r);
    return true;
  }

  bool asked = false;
  @override
  Future<bool> hasPermission() async => asked;
  @override
  Future<bool> requestPermission() async => asked = true;
  @override
  Future<void> replacePrayerAlarms(List<Reminder> alarms) async => prayer = alarms;
}

class _Location implements LocationPort {
  _Location(this.result, [this.problem]);
  final ({double lat, double lng})? result;
  final String? problem;
  @override
  Future<({double lat, double lng})?> current(void Function(String why) onProblem) async {
    if (problem != null) onProblem(problem!);
    return result;
  }
}

void main() {
  group('calculation', () {
    test('Lahore times match an independent calculation within a minute', () {
      final d = prayerDay(lahore, DateTime(2026, 11, 10));
      final want = {Prayer.fajr: 5 * 60 + 2, Prayer.sunrise: 6 * 60 + 26, Prayer.dhuhr: 11 * 60 + 46, Prayer.asr: 15 * 60 + 30, Prayer.maghrib: 17 * 60 + 7, Prayer.isha: 18 * 60 + 30};
      for (final e in want.entries) {
        expect((minutes(d.times[e.key]!) - e.value).abs(), lessThanOrEqualTo(1), reason: e.key.english);
      }
    });

    test('Shafi\'i Asr is earlier than Hanafi; other methods change Fajr and Isha', () {
      final h = prayerDay(lahore, DateTime(2026, 11, 10));
      final s = prayerDay(lahore.copyWith(hanafi: false), DateTime(2026, 11, 10));
      expect(s.times[Prayer.asr]!.isBefore(h.times[Prayer.asr]!), isTrue);
      expect(s.times[Prayer.dhuhr], h.times[Prayer.dhuhr]);
      final u = prayerDay(lahore.copyWith(method: PrayerMethod.ummAlQura), DateTime(2026, 11, 10));
      expect(u.times[Prayer.isha]!.difference(u.times[Prayer.maghrib]!).inMinutes, 90, reason: 'Umm al-Qura: Isha 90 min after Maghrib');
    });

    test('the next prayer: before Fajr, between prayers, and after Isha (tomorrow\'s Fajr)', () {
      final d = prayerDay(lahore, DateTime(2026, 11, 10));
      final early = prayerNow(lahore, d.times[Prayer.fajr]!.subtract(const Duration(minutes: 10)));
      expect(early.next, Prayer.fajr);
      expect(early.current, Prayer.isha, reason: 'Isha lasts until Fajr');
      final morning = prayerNow(lahore, d.times[Prayer.sunrise]!.add(const Duration(minutes: 30)));
      expect(morning.current, isNull, reason: 'no prayer between sunrise and Dhuhr');
      expect(morning.next, Prayer.dhuhr);
      final midday = prayerNow(lahore, d.times[Prayer.dhuhr]!.add(const Duration(minutes: 5)));
      expect(midday.current, Prayer.dhuhr);
      expect(midday.next, Prayer.asr);
      final night = prayerNow(lahore, d.times[Prayer.isha]!.add(const Duration(hours: 1)));
      expect(night.current, Prayer.isha);
      expect(night.next, Prayer.fajr);
      expect(night.nextAt.day, isNot(d.times[Prayer.fajr]!.day));
    });

    test('reminders: only the chosen prayers, only future ones, ids in the prayer range and unique', () {
      final s = lahore.copyWith(alerts: {Prayer.fajr, Prayer.maghrib});
      final now = prayerDay(lahore, DateTime(2026, 11, 10)).times[Prayer.dhuhr]!;
      final a = prayerAlarms(s, now, days: 7);
      expect(a.length, 13, reason: "today's Maghrib, then Fajr and Maghrib for 6 more days");
      expect(a.every((r) => r.at.isAfter(now)), isTrue);
      expect(a.map((r) => r.id).toSet().length, a.length);
      expect(a.every((r) => r.id >= prayerNotificationIds && r.id < prayerNotificationIds + 0x10000), isTrue);
      expect(a.first.title, contains('Maghrib'));
      expect(prayerAlarms(lahore, now), isEmpty, reason: 'no prayer chosen');
      expect(prayerAlarms(const PrayerSettings(alerts: {Prayer.fajr}), now), isEmpty, reason: 'no place');
    });

    test('reminders say the prayer\'s name (Salat-ul-Fajr, نمازِ فجر); on Fridays Zuhr is Jumu\'ah', () {
      final s = lahore.copyWith(alerts: {Prayer.fajr, Prayer.dhuhr});
      final a = prayerAlarms(s, DateTime(2026, 11, 9), days: 7); // Monday 9 Nov .. Sunday 15 Nov
      expect(a.first.title, 'Salat-ul-Fajr · نمازِ فجر');
      expect(a.first.body, contains('It is time for Salat-ul-Fajr'));
      final friday = a.where((r) => r.at.weekday == DateTime.friday && r.payload == 'prayer:dhuhr').single;
      expect(friday.title, "Salat-ul-Jumu'ah · نمازِ جمعہ");
      final monday = a.where((r) => r.at.weekday == DateTime.monday && r.payload == 'prayer:dhuhr').single;
      expect(monday.title, 'Salat-ul-Zuhr · نمازِ ظہر');
    });

    test('second reminder: minutes and seconds after the time, Fajr only or every prayer, its own tone, keeps ringing', () {
      final s = lahore.copyWith(alerts: {Prayer.fajr, Prayer.asr}, secondAfterSeconds: 10 * 60 + 30, tone: PrayerTone.notification, secondTone: PrayerTone.alarm);
      final now = DateTime(2026, 11, 10);
      final day = prayerDay(lahore, now);
      final a = prayerAlarms(s, now, days: 1);
      expect(a.length, 3, reason: 'Fajr, Fajr again, Asr');
      final again = a.singleWhere((r) => r.payload == 'prayer-again:fajr');
      expect(again.at, day.times[Prayer.fajr]!.add(const Duration(minutes: 10, seconds: 30)));
      expect(again.title, 'Get up for Salat-ul-Fajr · اٹھیں، نمازِ فجر ادا کریں');
      expect(again.body, contains('10 min 30 s ago'));
      expect((again.tone, again.insistent), ('alarm', true));
      final first = a.singleWhere((r) => r.payload == 'prayer:fajr');
      expect((first.tone, first.insistent), ('notification', false));
      expect(a.map((r) => r.id).toSet().length, a.length);
      final all = prayerAlarms(s.copyWith(secondFajrOnly: false, secondKeepRinging: false), now, days: 1);
      expect(all.length, 4);
      expect(all.where((r) => r.payload.startsWith('prayer-again')).every((r) => !r.insistent), isTrue);
      final ids = prayerAlarms(s.copyWith(secondFajrOnly: false), now, days: 7).map((r) => r.id).toList();
      expect(ids.toSet().length, ids.length, reason: 'unique over a week');
      expect(ids.every((i) => i >= prayerNotificationIds && i < prayerNotificationIds + 0x10000), isTrue);
    });

    test('minutes and seconds in words', () {
      expect(minSec(600), '10 min');
      expect(minSec(150), '2 min 30 s');
      expect(minSec(45), '45 s');
    });

    test('planner reminder ids never fall in the prayer range', () {
      for (var i = 0; i < 5000; i++) {
        expect(stableId('task:$i:${i * 7919}'), lessThan(reservedNotificationIds));
      }
    });

    test('Hijri date (Umm al-Qura, checked against another converter) and the moon-sighting adjustment', () {
      expect(hijriDate(DateTime(2026, 11, 10), 0), (day: 30, month: 5, year: 1448));
      expect(hijriEnglish(DateTime(2026, 11, 10), 0), '30 Jumada al-Ula 1448 AH');
      expect(hijriDate(DateTime(2026, 11, 10), -1).day, 29);
      expect(hijriUrdu(DateTime(2026, 11, 10), 0, (n) => '$n'), '30 جمادی الاول 1448 ھ');
    });

    test('Urdu clock: 12-hour with the part of the day', () {
      expect(urduClock(DateTime(2026, 1, 1, 5, 2)), '۵:۰۲ صبح');
      expect(urduClock(DateTime(2026, 1, 1, 12, 15)), '۱۲:۱۵ دوپہر');
      expect(urduClock(DateTime(2026, 1, 1, 17, 7)), '۵:۰۷ شام');
      expect(urduClock(DateTime(2026, 1, 1, 20, 30)), '۸:۳۰ رات');
    });

    test('settings survive saving', () {
      final s = lahore.copyWith(method: PrayerMethod.mwl, hanafi: false, hijriOffset: -1, alerts: {Prayer.isha}, tone: PrayerTone.ringtone, secondAfterSeconds: 95, secondFajrOnly: false, secondTone: PrayerTone.vibrate, secondKeepRinging: false);
      final back = PrayerSettings.decode(s.encode())!;
      expect((back.tone, back.secondAfterSeconds, back.secondFajrOnly, back.secondTone, back.secondKeepRinging), (PrayerTone.ringtone, 95, false, PrayerTone.vibrate, false));
      expect((back.lat, back.lng, back.place, back.method, back.hanafi, back.hijriOffset), (s.lat, s.lng, s.place, s.method, s.hanafi, s.hijriOffset));
      expect(back.alerts, s.alerts);
      expect(PrayerSettings.decode('not json'), isNull);
    });
  });

  group('on Home and the prayer page', () {
    Future<void> wait(WidgetTester t, [int rounds = 10]) async {
      for (var i = 0; i < rounds; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    Future<(TestEnv, _Scheduler)> open(WidgetTester t, {LocationPort? location}) async {
      t.view.physicalSize = const Size(411, 1200);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final env = await TestEnv.create();
      addTearDown(env.db.close);
      final sched = _Scheduler();
      await t.pumpWidget(ProviderScope(
        overrides: [
          ...env.overrides,
          reminderSchedulerProvider.overrideWithValue(sched),
          locationPortProvider.overrideWithValue(location ?? _Location((lat: 31.5204, lng: 74.3587))),
        ],
        child: const FolioApp(),
      ));
      await wait(t, 12);
      return (env, sched);
    }

    Future<void> endIt(WidgetTester t) async {
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
    }

    testWidgets('no place yet: the strip asks for it; Use my location fills the times; a bell schedules reminders', (t) async {
      final (env, sched) = await open(t);
      expect(find.byKey(const Key('prayer-strip-setup')), findsOneWidget);
      expect(find.byKey(const Key('prayer-strip-hijri')), findsOneWidget);
      await t.tap(find.byKey(const Key('prayer-strip')));
      await wait(t, 6);
      expect(find.byKey(const Key('prayer-page')), findsOneWidget);
      await t.tap(find.byKey(const Key('prayer-locate')));
      await wait(t, 6);
      for (final p in Prayer.values) {
        expect(find.byKey(Key('prayer-time-${p.name}')), findsOneWidget);
      }
      expect(await t.runAsync(() => env.store.state('prayer_settings')), contains('31.5204'));

      await t.tap(find.byKey(const Key('prayer-alert-asr')));
      await wait(t, 4);
      expect(sched.asked, isTrue, reason: 'notification permission asked when the first reminder is turned on');
      expect(sched.prayer, isNotEmpty);
      expect(sched.prayer.every((r) => r.title.contains('Asr')), isTrue);

      // the second reminder: 2 min 15 s after Fajr, alarm sound, keeps ringing; try it
      await t.ensureVisible(find.byKey(const Key('prayer-second')));
      await t.tap(find.byKey(const Key('prayer-second')));
      await wait(t, 3);
      await t.ensureVisible(find.byKey(const Key('second-min')));
      await t.tap(find.byKey(const Key('second-min')));
      await wait(t, 4);
      await t.tap(find.text('2').last);
      await wait(t, 4);
      await t.tap(find.byKey(const Key('second-sec')));
      await wait(t, 4);
      await t.tap(find.text('15').last);
      await wait(t, 4);
      expect(t.widget<Text>(find.byKey(const Key('second-summary'))).data, '2 min 15 s after the prayer time.');
      expect(await t.runAsync(() => env.store.state('prayer_settings')), contains('"second":135'));
      await t.scrollUntilVisible(find.byKey(const Key('prayer-alert-fajr')), -200, scrollable: find.descendant(of: find.byKey(const Key('prayer-page')), matching: find.byType(Scrollable)).first);
      await wait(t, 2);
      await t.tap(find.byKey(const Key('prayer-alert-fajr')));
      await wait(t, 3);
      expect(sched.prayer.any((r) => r.payload == 'prayer-again:fajr' && r.tone == 'alarm' && r.insistent), isTrue);
      await t.ensureVisible(find.byKey(const Key('prayer-test-second')));
      await t.tap(find.byKey(const Key('prayer-test-second')));
      await wait(t, 3);
      expect(sched.tests.single.insistent, isTrue);
      expect(sched.tests.single.tone, 'alarm');
      expect(sched.tests.single.at.difference(DateTime.now()).inSeconds, lessThanOrEqualTo(5));

      await t.pageBack();
      await wait(t, 6);
      expect(find.byKey(const Key('prayer-strip-next')), findsOneWidget);
      await endIt(t);
    });

    testWidgets('location refused: says why; entering the place by hand works; bad numbers are explained', (t) async {
      await open(t, location: _Location(null, 'Folio may not use your location.'));
      await t.tap(find.byKey(const Key('prayer-strip')));
      await wait(t, 6);
      await t.tap(find.byKey(const Key('prayer-locate')));
      await wait(t, 4);
      expect(find.byKey(const Key('prayer-problem')), findsOneWidget);
      await t.tap(find.byKey(const Key('prayer-manual')));
      await wait(t, 4);
      await t.enterText(find.byKey(const Key('place-name')), 'Karachi');
      await t.enterText(find.byKey(const Key('place-lat')), '124');
      await t.enterText(find.byKey(const Key('place-lng')), '67');
      await t.tap(find.byKey(const Key('place-save')));
      await wait(t, 3);
      expect(find.textContaining('Latitude is -90 to 90'), findsOneWidget);
      await t.enterText(find.byKey(const Key('place-lat')), '24,86');
      await t.tap(find.byKey(const Key('place-save')));
      await wait(t, 4);
      expect(find.text('Karachi'), findsOneWidget);
      expect(find.byKey(const Key('prayer-time-fajr')), findsOneWidget);

      // Hijri adjustment
      final before = t.widget<Text>(find.byKey(const Key('prayer-hijri'))).data;
      final page = find.descendant(of: find.byKey(const Key('prayer-page')), matching: find.byType(Scrollable)).first;
      await t.scrollUntilVisible(find.byKey(const Key('hijri-minus')), 200, scrollable: page);
      await wait(t, 2);
      await t.tap(find.byKey(const Key('hijri-minus')));
      await wait(t, 3);
      expect(t.widget<Text>(find.byKey(const Key('hijri-offset'))).data, '-1');
      await t.scrollUntilVisible(find.byKey(const Key('prayer-hijri')), -300, scrollable: page);
      await wait(t, 2);
      expect(t.widget<Text>(find.byKey(const Key('prayer-hijri'))).data, isNot(before));
      await endIt(t);
    });
  });
}
