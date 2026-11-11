import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/features/quran/prayer/prayer_reminders_card.dart';
import 'package:folio/features/quran/prayer/prayer_ringer.dart';
import 'package:folio/app/router.dart';
import 'package:go_router/go_router.dart';
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
  final tapped = StreamController<String>.broadcast();
  @override
  Stream<String> get taps => tapped.stream;
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
  @override
  Future<Set<int>> pendingIds() async => {for (final r in prayer) r.id};
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

    test('spoken reminders: the name is said ("Salat ul Fajr"), the get-up reminder says your words with the prayer in them', () {
      final s = lahore.copyWith(alerts: {Prayer.fajr, Prayer.maghrib}, secondAfterSeconds: 600, secondWords: 'Get up, otherwise {prayer} will be missed');
      final a = prayerAlarms(s, DateTime(2026, 11, 13), days: 1); // a Friday
      final fajr = a.singleWhere((r) => r.payload == 'prayer:fajr');
      expect((fajr.tone, fajr.speech, fajr.insistent), ('spoken', 'Salat ul Fajr', false));
      final again = a.singleWhere((r) => r.payload == 'prayer-again:fajr');
      expect((again.tone, again.speech, again.insistent), ('voice', 'Get up, otherwise Salat ul Fajr will be missed', true));
      expect(getUpSpeech('', Prayer.dhuhr, DateTime(2026, 11, 13)), "Get up now, otherwise Salat ul Jumu'ah will be missed.");
      final own = prayerAlarms(s.withTone(Prayer.maghrib, PrayerTone.own, sound: 'prayer_sounds/1_azan.mp3').copyWith(firstKeepRinging: true), DateTime(2026, 11, 13), days: 1)
          .singleWhere((r) => r.payload == 'prayer:maghrib');
      expect((own.tone, own.sound, own.speech, own.insistent), ('own', 'prayer_sounds/1_azan.mp3', null, true));
    });

    test('an alarm that is ringing (or just rang) is never cancelled when the reminders are set again', () {
      final now = DateTime(2026, 11, 10, 5, 12);
      expect(mayCancel(now.subtract(const Duration(seconds: 30)), now), isFalse, reason: 'ringing now');
      expect(mayCancel(now.subtract(const Duration(minutes: 40)), now), isFalse, reason: 'may still be going');
      expect(mayCancel(now.add(const Duration(hours: 1)), now), isTrue, reason: 'a future one no longer wanted');
      expect(mayCancel(now.subtract(const Duration(hours: 5)), now), isTrue, reason: 'an old leftover');
    });

    test('mosque times: minutes added to or taken from a prayer move its time and its reminders', () {
      final d = DateTime(2026, 11, 10);
      final plain = prayerDay(lahore, d), moved = prayerDay(lahore.copyWith(offsets: {Prayer.isha: 15, Prayer.fajr: -2}), d);
      expect(moved.times[Prayer.isha]!.difference(plain.times[Prayer.isha]!), const Duration(minutes: 15));
      expect(moved.times[Prayer.fajr]!.difference(plain.times[Prayer.fajr]!), const Duration(minutes: -2));
      expect(moved.times[Prayer.asr], plain.times[Prayer.asr]);
    });

    test('three weeks of reminders, and a nudge two days before they run out', () {
      final now = DateTime(2026, 11, 10, 12);
      final a = prayerAlarms(lahore.copyWith(alerts: {Prayer.fajr}), now, days: prayerScheduleDays);
      expect(a.length, 20, reason: "today's Fajr has passed at noon");
      final n = prayerRenewalNudge(now, prayerScheduleDays);
      expect(n.at, DateTime(2026, 11, 29, 21, 30));
      expect(n.payload, 'prayer-renew');
      expect(a.any((r) => r.id == n.id), isFalse);
    });

    test('second reminder: minutes and seconds after the time, Fajr only or every prayer, its own tone, keeps ringing', () {
      final s = lahore.copyWith(alerts: {Prayer.fajr, Prayer.asr}, secondAfterSeconds: 10 * 60 + 30, secondFajrOnly: true, tones: {Prayer.fajr: PrayerTone.notification, Prayer.asr: PrayerTone.notification}, secondTone: PrayerTone.alarm);
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
      final s = lahore.copyWith(
        method: PrayerMethod.mwl,
        hanafi: false,
        hijriOffset: -1,
        alerts: {Prayer.isha},
        tones: {Prayer.isha: PrayerTone.own, Prayer.fajr: PrayerTone.ringtone},
        sounds: {Prayer.isha: 'prayer_sounds/1_azan.mp3'},
        firstKeepRinging: true,
        secondAfterSeconds: 95,
        secondFajrOnly: false,
        secondTone: PrayerTone.vibrate,
        secondKeepRinging: false,
        secondWords: 'Uth jao',
        secondSound: 'prayer_sounds/2_x.mp3',
        offsets: {Prayer.isha: 15, Prayer.fajr: -3},
      );
      final back = PrayerSettings.decode(s.encode())!;
      expect((back.secondAfterSeconds, back.secondFajrOnly, back.secondTone, back.secondKeepRinging), (95, false, PrayerTone.vibrate, false));
      expect((back.firstKeepRinging, back.secondWords, back.secondSound), (true, 'Uth jao', s.secondSound));
      expect(back.tones, s.tones);
      expect(back.sounds, s.sounds);
      expect(back.offsets, s.offsets);
      expect(back.toneOf(Prayer.asr), PrayerTone.spoken, reason: 'not chosen: says the name');
      final old = PrayerSettings.decode('{"lat":1,"lng":2,"tone":"alarm","secondTone":"alarm"}')!;
      expect((old.toneOf(Prayer.fajr), old.secondTone, old.secondWords), (PrayerTone.spoken, PrayerTone.alarm, defaultGetUpWords), reason: 'settings saved by the last version');
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

    Future<(TestEnv, _Scheduler)> open(WidgetTester t, {LocationPort? location, void Function(TestEnv)? before, List<Override> more = const []}) async {
      t.view.physicalSize = const Size(411, 1200);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final env = await TestEnv.create();
      addTearDown(env.db.close);
      before?.call(env);
      final sched = _Scheduler();
      await t.pumpWidget(ProviderScope(
        overrides: [
          ...env.overrides,
          reminderSchedulerProvider.overrideWithValue(sched),
          locationPortProvider.overrideWithValue(location ?? _Location((lat: 31.5204, lng: 74.3587))),
          ...more,
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

    testWidgets('tapping a reminder opens its screen: a prayer reminder the prayer times, the ayah of the day that ayah', (t) async {
      final (_, sched) = await open(t);
      sched.tapped.add('prayer-again:fajr');
      await wait(t, 8);
      expect(find.text('Prayer times'), findsWidgets);
      sched.tapped.add('ayah:2:255');
      await wait(t, 25);
      expect(find.byKey(const Key('ayah-list')), findsOneWidget);
      expect(find.byKey(const Key('mark-2-255')), findsOneWidget, reason: 'scrolled to the ayah');
      await endIt(t);
    });

    Future<void> center(WidgetTester t, Finder f) async {
      final page = find.byKey(const Key('prayer-page'));
      if (f.evaluate().isEmpty && page.evaluate().isNotEmpty) {
        // the page is a lazy list: scroll down until the item has been built
        await t.scrollUntilVisible(f, 300, scrollable: find.descendant(of: page, matching: find.byType(Scrollable)).first);
      }
      await Scrollable.ensureVisible(t.element(f), alignment: .5);
      await t.pump();
    }

    Future<void> toPrayerPageWithPlace(WidgetTester t, TestEnv env) async {
      await t.runAsync(() => env.store.setState('prayer_settings', const PrayerSettings(lat: 31.5204, lng: 74.3587, alerts: {Prayer.fajr, Prayer.isha}).encode()));
      env.store.announcePrefChange('prayer_settings');
      await wait(t, 4);
      unawaited(GoRouter.of(t.element(find.byType(Scaffold).first)).push(Routes.prayer));
      await wait(t, 8);
    }

    testWidgets('a reminder per prayer: Isha plays your own sound (an Azan file you choose), Fajr keeps saying its name', (t) async {
      var picks = 0;
      final (env, _) = await open(t, more: [
        prayerSoundPickerProvider.overrideWithValue(() async {
          picks++;
          return 'prayer_sounds/123_my azan.mp3';
        }),
      ]);
      await toPrayerPageWithPlace(t, env);
      await center(t, find.byKey(const Key('prayer-tone-isha')));
      await t.tap(find.byKey(const Key('prayer-tone-isha')));
      await wait(t, 4);
      await t.tap(find.text('Your own sound (e.g. an Azan)').last);
      await wait(t, 6);
      expect(picks, 1);
      expect(find.text('my azan.mp3'), findsOneWidget);
      final isha = env.ringer.alarms.firstWhere((r) => r.payload == 'prayer:isha');
      expect((isha.tone, isha.sound), ('own', 'prayer_sounds/123_my azan.mp3'));
      expect(env.ringer.alarms.firstWhere((r) => r.payload == 'prayer:fajr').speech, 'Salat ul Fajr');
      expect(find.text('Says “Salat ul Fajr”'), findsOneWidget);
      await endIt(t);
    });

    testWidgets('when the alarm cannot be used, spoken reminders come as loud alarm notifications and it says so', (t) async {
      final (env, sched) = await open(t, before: (e) => e.ringer.works = false);
      await toPrayerPageWithPlace(t, env);
      expect(sched.prayer.where((r) => r.payload == 'prayer:fajr').every((r) => r.tone == 'alarm'), isTrue);
      expect(sched.prayer.where((r) => r.payload == 'prayer:fajr'), isNotEmpty);
      await center(t, find.byKey(const Key('ring-problem')));
      expect(find.byKey(const Key('ring-problem')), findsOneWidget);
      await endIt(t);
    });

    testWidgets('coming reminders show as set; Full test sets a reminder in 2 minutes and the second a minute later, like real ones', (t) async {
      final (env, _) = await open(t);
      await toPrayerPageWithPlace(t, env);
      await center(t, find.byKey(const Key('prayer-coming')));
      await wait(t, 3);
      expect(find.text('set ✓'), findsWidgets);
      await center(t, find.byKey(const Key('prayer-full-test')));
      await t.tap(find.byKey(const Key('prayer-full-test')));
      await wait(t, 4);
      final tests = env.ringer.alarms.where((r) => r.payload.endsWith(':test')).toList();
      expect(tests.length, 2);
      expect(tests[1].at.difference(tests[0].at), const Duration(minutes: 1));
      expect(tests[0].at.difference(DateTime.now()).inSeconds, inInclusiveRange(55, 125));
      expect(tests[0].speech, isNotNull);
      expect((tests[1].tone, tests[1].insistent), ('voice', true));
      expect(env.ringer.alarms.where((r) => !r.payload.endsWith(':test')), isNotEmpty, reason: 'the real ones stay set');
      await endIt(t);
    });

    testWidgets('battery saving: a warning and a button to the setting; how far ahead reminders are set', (t) async {
      final (env, _) = await open(t, before: (e) => e.battery.unrestricted = false);
      await toPrayerPageWithPlace(t, env);
      await center(t, find.byKey(const Key('battery-allow')));
      expect(find.byKey(const Key('battery-warning')), findsOneWidget);
      expect(find.byKey(const Key('prayer-until')), findsOneWidget);
      await t.tap(find.byKey(const Key('battery-allow')));
      await wait(t, 2);
      expect(env.battery.asked, 1);
      await center(t, find.byKey(const Key('app-settings')));
      await t.tap(find.byKey(const Key('app-settings')));
      await wait(t, 2);
      expect(env.battery.opened, 1);
      await endIt(t);
    });

    testWidgets('a prayer alarm sounding: full screen, the prayer\'s name, and "I\'m up" stops it', (t) async {
      final (env, _) = await open(t);
      env.ringer.ring(const [RingingAlarm(prayerNotificationIds + 8, 'Get up for Salat-ul-Fajr · اٹھیں، نمازِ فجر ادا کریں', 'Its time began 10 min ago. Pray now. · وقت شروع ہوئے', 'prayer-again:fajr')]);
      await wait(t, 3);
      expect(find.byKey(const Key('prayer-ringing')), findsOneWidget);
      expect(find.text('Get up for Salat-ul-Fajr'), findsOneWidget);
      await t.tap(find.byKey(const Key('im-up')));
      await wait(t, 3);
      expect(env.ringer.stopped, [prayerNotificationIds + 8]);
      expect(find.byKey(const Key('prayer-ringing')), findsNothing);
      await endIt(t);
    });

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
      expect(env.ringer.alarms, isNotEmpty, reason: 'spoken by default: rung by the alarm');
      expect(env.ringer.alarms.every((r) => r.title.contains('Asr') && r.speech == 'Salat ul Asr'), isTrue);
      expect(sched.prayer.single.payload, 'prayer-renew', reason: 'only the "open Folio" nudge is a notification');

      // the second reminder: 2 min 15 s after Fajr, alarm sound, keeps ringing; try it
      await center(t, find.byKey(const Key('prayer-second')));
      await t.tap(find.byKey(const Key('prayer-second')));
      await wait(t, 3);
      await center(t, find.byKey(const Key('second-min')));
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
      expect(env.ringer.alarms.any((r) => r.payload == 'prayer-again:fajr' && r.tone == 'voice' && r.insistent && r.speech == 'Get up now, otherwise Salat ul Fajr will be missed.'), isTrue);
      // own words
      await center(t, find.byKey(const Key('second-words')));
      await t.enterText(find.byKey(const Key('second-words')), 'Wake up, {prayer} is waiting');
      await wait(t, 12);
      expect(t.widget<Text>(find.byKey(const Key('second-sample'))).data, 'For Fajr it says: “Wake up, Salat ul Fajr is waiting”');
      expect(env.ringer.alarms.any((r) => r.payload == 'prayer-again:fajr' && r.speech == 'Wake up, Salat ul Fajr is waiting'), isTrue);
      await center(t, find.byKey(const Key('prayer-test-second')));
      await t.tap(find.byKey(const Key('prayer-test-second')));
      await wait(t, 3);
      expect(env.ringer.tests.single.insistent, isTrue);
      expect(env.ringer.tests.single.tone, 'voice');
      expect(env.ringer.tests.single.at.difference(DateTime.now()).inSeconds, lessThanOrEqualTo(5));

      await t.pageBack();
      await wait(t, 6);
      expect(find.byKey(const Key('prayer-strip-next')), findsOneWidget);
      await endIt(t);
    });

    testWidgets('location refused: says why; entering the place by hand works; bad numbers are explained', (t) async {
      final (env, _) = await open(t, location: _Location(null, 'Folio may not use your location.'));
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
      expect(await t.runAsync(() => env.store.state('prayer_settings')), allOf(contains('"place":"Karachi"'), contains('24.86')));
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
