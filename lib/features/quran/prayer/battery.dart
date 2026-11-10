import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the phone may hold Folio's alarms back to save battery, and the way to the setting that stops it.
abstract class BatteryPort {
  /// True when Folio is exempt (or the phone has no such limit); null when unknown.
  Future<bool?> isUnrestricted();

  /// Opens the phone's battery setting for Folio. False if no screen could be opened.
  Future<bool> askUnrestricted();

  /// Opens Folio's page in the phone's settings (for "Autostart" and similar on some brands).
  Future<bool> openAppSettings();
}

class AndroidBattery implements BatteryPort {
  static const _ch = MethodChannel('folio/battery');
  bool get _android => defaultTargetPlatform == TargetPlatform.android && !kIsWeb;

  @override
  Future<bool?> isUnrestricted() async {
    if (!_android) return true;
    try {
      return await _ch.invokeMethod<bool>('isUnrestricted');
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> askUnrestricted() async {
    if (!_android) return false;
    try {
      return await _ch.invokeMethod<bool>('askUnrestricted') ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> openAppSettings() async {
    if (!_android) return false;
    try {
      return await _ch.invokeMethod<bool>('openAppSettings') ?? false;
    } catch (_) {
      return false;
    }
  }
}

final batteryPortProvider = Provider<BatteryPort>((_) => AndroidBattery());

/// Re-read after coming back from the settings screen.
final batteryUnrestrictedProvider = FutureProvider.autoDispose<bool?>((ref) => ref.watch(batteryPortProvider).isUnrestricted());

/// What the home-screen widget is given: one line per coming prayer, "epochMillis|English|Urdu".
String widgetLines(List<({DateTime at, String english, String urdu})> times) =>
    [for (final t in times) '${t.at.millisecondsSinceEpoch}|${t.english.replaceAll('|', ' ')}|${t.urdu.replaceAll('|', ' ')}'].join('\n');

/// Sends the coming prayer times to the Android home-screen widget (nothing elsewhere).
final prayerWidgetUpdaterProvider = Provider<Future<void> Function(String lines)>((_) => (lines) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  try {
    await const MethodChannel('folio/battery').invokeMethod<bool>('widget', {'lines': lines});
  } catch (_) {}
});
