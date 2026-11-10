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
    final all = prayerAlarms(s, now, days: days);
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
  }

  int _generation = 0;

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
  }
}

final prayerLogProvider = NotifierProvider<PrayerLogController, PrayerLog>(PrayerLogController.new);
