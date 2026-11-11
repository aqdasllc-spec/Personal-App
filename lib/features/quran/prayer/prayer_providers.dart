import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../app/providers.dart';
import '../../planner/application/planner_controller.dart' show reminderSchedulerProvider;
import '../../planner/domain/reminders.dart';
import 'battery.dart';
import 'prayer.dart';
import 'prayer_ringer.dart';
import 'islamic.dart';
import '../../planner/data/notification_answers.dart' show takeNotificationAnswers;

/// Prayer-time settings, remembered on this device.
class PrayerSettingsController extends Notifier<PrayerSettings> {
  static const key = 'prayer_settings';
  @override
  PrayerSettings build() {
    Future<void> load() async {
      try {
        final raw = await ref.read(syncedStoreProvider).state(key);
        final s = raw == null ? null : PrayerSettings.decode(raw);
        if (s != null) state = s;
        resync();
      } catch (_) {}
    }

    Future.microtask(load);
    reloadOnRemote(ref, key, load);
    return const PrayerSettings();
  }

  void set(PrayerSettings s) {
    state = s;
    try {
      ref.read(syncedStoreProvider).setState(key, s.encode());
    } catch (_) {}
    resync();
  }

  /// Schedules the reminders for the coming days (called on every change and whenever Home shows the cabinet, so
  /// they keep rolling forward while the app is used). Spoken / own-sound reminders are rung by the alarm; the rest
  /// are notifications. If the alarm cannot be used, those become loud notifications instead.
  void resync() {
    final android = defaultTargetPlatform == TargetPlatform.android;
    final days = android ? prayerScheduleDays : 1; // iOS allows only 64 pending in all
    final now = DateTime.now();
    final s = state;
    final all = [...prayerAlarms(s, now, days: days), ..._tests.where((r) => r.at.isAfter(now))]..sort((a, b) => a.at.compareTo(b.at));
    bool rings(Reminder r) => PrayerTone.values.where((t) => t.name == r.tone).firstOrNull?.rings ?? false;
    final ringing = all.where(rings).toList(), quiet = all.where((r) => !rings(r)).toList();
    final nudge = [if (android && s.alerts.isNotEmpty && s.hasLocation) prayerRenewalNudge(now, days)];
    final sched = ref.read(reminderSchedulerProvider);
    final ringer = ref.read(prayerRingerProvider);
    final gen = ++_generation;
    if (s.hasLocation) {
      final times = [
        for (var d = 0; d < days + 1; d++)
          for (final e in prayerDay(s, DateTime(now.year, now.month, now.day + d)).times.entries)
            if (e.key.isPrayer && e.value.isAfter(now)) (at: e.value, english: e.key.salahOn(e.value), urdu: e.key.salahUrduOn(e.value)),
      ];
      unawaited(ref.read(prayerWidgetUpdaterProvider)(widgetLines(times)));
    }
    unawaited(() async {
      final r = await ringer.replace(ringing).catchError((Object _) => const RingResult(ok: false));
      if (gen != _generation) return;
      final fallback = r.ok ? const <Reminder>[] : [for (final a in ringing) _asNotification(a)];
      await sched.replacePrayerAlarms([...quiet, ...fallback, ...nudge]).catchError((Object _) {});
      if (!ref.mounted) return;
      ref.read(prayerRingProblemProvider.notifier).set(
        r.ok ? r.problem : (ringing.isEmpty ? null : 'Spoken reminders could not be set on this phone, so they come as loud alarm notifications.'),
      );
      ref.read(prayerScheduledUntilProvider.notifier).set(all.isEmpty ? null : all.last.at);
    }());
    ref.read(islamicRemindersProvider.notifier).resync(); // "Did you pray?" follows the prayer times
  }

  int _generation = 0;
  List<Reminder> _tests = const [];

  /// A full test through the same path as the real reminders: the reminder at the time in 2 minutes, and the second
  /// reminder a minute after it, each with the sound chosen for them.
  List<Reminder> fullTest({DateTime? now}) {
    final t = now ?? DateTime.now();
    final s = state;
    final n = prayerNow(s, t);
    final p = n.next == Prayer.sunrise ? Prayer.dhuhr : n.next;
    final at = DateTime(t.year, t.month, t.day, t.hour, t.minute).add(const Duration(minutes: 2));
    final first = s.toneOf(p), second = s.secondTone;
    _tests = [
      Reminder(
        id: prayerNotificationIds + 0xfff2,
        at: at,
        title: 'Test: ${p.salahOn(at)} · ${p.salahUrduOn(at)}',
        body: 'This is how the reminder at the prayer time comes.',
        payload: 'prayer:test',
        tone: first.name,
        insistent: first.rings && s.firstKeepRinging,
        speech: first == PrayerTone.spoken ? spokenName(p, at) : null,
        sound: first == PrayerTone.own ? s.sounds[p] : null,
      ),
      Reminder(
        id: prayerNotificationIds + 0xfff3,
        at: at.add(const Duration(minutes: 1)),
        title: 'Test: get up for ${p.salahOn(at)} · اٹھیں، ${p.salahUrduOn(at)} ادا کریں',
        body: 'This is how the second reminder comes.',
        payload: 'prayer-again:test',
        tone: second.name,
        insistent: s.secondKeepRinging,
        speech: second == PrayerTone.voice ? getUpSpeech(s.secondWords, p, at) : (second == PrayerTone.spoken ? spokenName(p, at) : null),
        sound: second == PrayerTone.own ? s.secondSound : null,
      ),
    ];
    resync();
    return _tests;
  }

  static Reminder _asNotification(Reminder r) =>
      Reminder(id: r.id, at: r.at, title: r.title, body: r.body, payload: r.payload, tone: PrayerTone.alarm.name, insistent: r.insistent);
}

/// When the last reminder now set will come (null = none).
class ScheduledUntil extends Notifier<DateTime?> {
  @override
  DateTime? build() => null;
  void set(DateTime? v) => state = v;
}

final prayerScheduledUntilProvider = NotifierProvider<ScheduledUntil, DateTime?>(ScheduledUntil.new);

final prayerSettingsProvider = NotifierProvider<PrayerSettingsController, PrayerSettings>(PrayerSettingsController.new);

/// Where the phone is (for prayer times). An interface so tests need no GPS.
abstract class LocationPort {
  /// The position, or a sentence saying why there is none.
  Future<({double lat, double lng})?> current(void Function(String why) onProblem);
}

class GeolocatorLocation implements LocationPort {
  @override
  Future<({double lat, double lng})?> current(void Function(String why) onProblem) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        onProblem('Location is switched off on this phone. Turn it on in the quick settings, or enter the place by hand.');
        return null;
      }
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
      if (p == LocationPermission.denied || p == LocationPermission.deniedForever) {
        onProblem('Folio may not use your location. You can allow it in the phone\'s settings, or enter the place by hand.');
        return null;
      }
      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 20)),
        );
      } catch (_) {
        pos = await Geolocator.getLastKnownPosition();
      }
      if (pos == null) {
        onProblem('The phone could not find where you are just now. Try again near a window or outside, or type your city.');
        return null;
      }
      return (lat: pos.latitude, lng: pos.longitude);
    } catch (_) {
      onProblem('The phone could not find where you are just now. Try again near a window or outside, or type your city.');
      return null;
    }
  }
}

final locationPortProvider = Provider<LocationPort>((_) => GeolocatorLocation());

/// Which prayers were prayed, and the qaza still to make up. Synced and backed up.
class PrayerLogController extends Notifier<PrayerLog> {
  static const key = 'prayer_log';
  @override
  PrayerLog build() {
    Future<void> load() async {
      try {
        state = PrayerLog.decode(await ref.read(syncedStoreProvider).state(key));
      } catch (_) {}
    }

    Future.microtask(load);
    reloadOnRemote(ref, key, load);
    return const PrayerLog();
  }

  void set(PrayerLog v) {
    state = v;
    try {
      ref.read(syncedStoreProvider).setState(key, v.encode());
    } catch (_) {}
    ref.read(islamicRemindersProvider.notifier).resync(); // no "Did you pray?" for what is marked now
  }
}

final prayerLogProvider = NotifierProvider<PrayerLogController, PrayerLog>(PrayerLogController.new);


/// The Sunnah surahs, Jumu'ah, "Did you pray?" and Islamic-date reminders: their settings (synced) and scheduling.
class IslamicRemindersController extends Notifier<IslamicSettings> {
  static const key = 'islamic_reminders';
  @override
  IslamicSettings build() {
    Future<void> load() async {
      try {
        state = IslamicSettings.decode(await ref.read(syncedStoreProvider).state(key));
        resync();
      } catch (_) {}
    }

    Future.microtask(load);
    reloadOnRemote(ref, key, load);
    return const IslamicSettings();
  }

  Future<void> set(IslamicSettings v) async {
    final asking = v.askPrayed && !state.askPrayed;
    state = v;
    try {
      ref.read(syncedStoreProvider).setState(key, v.encode());
    } catch (_) {}
    if (asking || v.kahf || v.mulk || v.jumuah || v.monThu || v.whiteDays) {
      final s = ref.read(reminderSchedulerProvider);
      if (!await s.hasPermission()) await s.requestPermission();
    }
    resync();
  }

  /// The coming reminders: three weeks of Sunnah / Jumu'ah, a week of "Did you pray?", a month of Islamic dates.
  void resync({DateTime? now}) {
    final t = now ?? DateTime.now();
    final s = state;
    final p = ref.read(prayerSettingsProvider);
    final all = [
      ...sunnahReminders(s, t),
      ...prayedChecks(p, s, t, log: ref.read(prayerLogProvider)),
      ...islamicDateReminders(s, p.hijriOffset, t),
    ];
    unawaited(ref.read(reminderSchedulerProvider).replaceIslamicReminders(all).catchError((Object _) {}));
  }
}

final islamicRemindersProvider = NotifierProvider<IslamicRemindersController, IslamicSettings>(IslamicRemindersController.new);

/// Where answers given with notification buttons come from (a function so tests can give their own).
final notificationAnswersProvider = Provider<Future<List<(String, String)>> Function()>((_) => takeNotificationAnswers);

/// Puts the "Did you pray?" answers (Prayed / Missed, possibly given while the app was closed) into the prayer log.
/// Returns how many were applied.
Future<int> applyPrayerAnswers(Ref ref) async {
  final answers = await ref.read(notificationAnswersProvider)().catchError((Object _) => const <(String, String)>[]);
  var n = 0;
  var log = ref.read(prayerLogProvider);
  for (final (action, payload) in answers) {
    final p = payload.split(':');
    if (p.length != 3 || p[0] != 'check' || (action != 'prayed' && action != 'missed')) continue;
    final prayer = Prayer.values.where((x) => x.name == p[1] && x.isPrayer).firstOrNull;
    final d = DateTime.tryParse(p[2]);
    if (prayer == null || d == null) continue;
    log = log.mark(d, prayer, action == 'prayed');
    n++;
  }
  if (n > 0) {
    ref.read(prayerLogProvider.notifier).set(log);
    ref.read(islamicRemindersProvider.notifier).resync();
  }
  return n;
}

/// Lets widgets call [applyPrayerAnswers].
final applyPrayerAnswersProvider = Provider<Future<int> Function()>((ref) => () => applyPrayerAnswers(ref));
