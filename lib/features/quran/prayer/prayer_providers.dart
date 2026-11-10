import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../app/providers.dart';
import '../../planner/application/planner_controller.dart' show reminderSchedulerProvider;
import 'prayer.dart';

/// Prayer-time settings, remembered on this device.
class PrayerSettingsController extends Notifier<PrayerSettings> {
  static const key = 'prayer_settings';
  @override
  PrayerSettings build() {
    Future.microtask(() async {
      try {
        final raw = await ref.read(syncedStoreProvider).state(key);
        final s = raw == null ? null : PrayerSettings.decode(raw);
        if (s != null) state = s;
        resync();
      } catch (_) {}
    });
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
  /// they keep rolling forward while the app is used).
  void resync() {
    final days = defaultTargetPlatform == TargetPlatform.android ? 7 : 1; // iOS allows only 64 pending in all
    final alarms = prayerAlarms(state, DateTime.now(), days: days);
    unawaited(ref.read(reminderSchedulerProvider).replacePrayerAlarms(alarms).catchError((Object _) {}));
  }
}

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
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 20)),
      ).catchError((Object _) async => (await Geolocator.getLastKnownPosition())!);
      return (lat: pos.latitude, lng: pos.longitude);
    } catch (e) {
      onProblem('Could not find your location ($e). Try again outside, or enter the place by hand.');
      return null;
    }
  }
}

final locationPortProvider = Provider<LocationPort>((_) => GeolocatorLocation());
