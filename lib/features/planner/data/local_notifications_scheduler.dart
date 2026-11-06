import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart' as fln;
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../domain/reminders.dart';
import 'reminder_scheduler.dart';

/// Platforms whose notification plugin setup we have wired (Android, iOS, macOS).
/// Windows/Linux fall back to [NoopReminderScheduler] until they are set up and tested there.
ReminderScheduler createReminderScheduler() {
  if (kIsWeb) return NoopReminderScheduler();
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
      return LocalNotificationsScheduler();
    default:
      return NoopReminderScheduler();
  }
}

/// OS notifications via flutter_local_notifications.
///
/// Scheduling mode is *inexact while idle*: no special "exact alarm" permission is needed, but Android may
/// deliver a reminder a few minutes late while the device is dozing. Everything is wrapped so a plugin
/// failure degrades to "no reminders" and never breaks the planner.
class LocalNotificationsScheduler implements ReminderScheduler {
  LocalNotificationsScheduler([fln.FlutterLocalNotificationsPlugin? plugin]) : _plugin = plugin ?? fln.FlutterLocalNotificationsPlugin();
  final fln.FlutterLocalNotificationsPlugin _plugin;
  bool _ready = false;

  static const _channel = fln.AndroidNotificationDetails(
    'planner_reminders',
    'Planner reminders',
    channelDescription: 'Reminders for tasks and events in your planner',
    importance: fln.Importance.high,
    priority: fln.Priority.high,
  );
  static const _details = fln.NotificationDetails(android: _channel, iOS: fln.DarwinNotificationDetails(), macOS: fln.DarwinNotificationDetails());

  Future<bool> _init() async {
    if (_ready) return true;
    try {
      tzdata.initializeTimeZones();
      const darwin = fln.DarwinInitializationSettings(requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false);
      await _plugin.initialize(
        settings: const fln.InitializationSettings(android: fln.AndroidInitializationSettings('@mipmap/ic_launcher'), iOS: darwin, macOS: darwin),
      );
      _ready = true;
    } catch (e) {
      debugPrint('Notifications unavailable: $e');
    }
    return _ready;
  }

  @override
  Future<bool> hasPermission() async {
    if (!await _init()) return false;
    try {
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          return await _plugin.resolvePlatformSpecificImplementation<fln.AndroidFlutterLocalNotificationsPlugin>()?.areNotificationsEnabled() ?? false;
        case TargetPlatform.iOS:
          return (await _plugin.resolvePlatformSpecificImplementation<fln.IOSFlutterLocalNotificationsPlugin>()?.checkPermissions())?.isEnabled ?? false;
        case TargetPlatform.macOS:
          return (await _plugin.resolvePlatformSpecificImplementation<fln.MacOSFlutterLocalNotificationsPlugin>()?.checkPermissions())?.isEnabled ?? false;
        default:
          return false;
      }
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> requestPermission() async {
    if (!await _init()) return false;
    try {
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          return await _plugin.resolvePlatformSpecificImplementation<fln.AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission() ?? false;
        case TargetPlatform.iOS:
          return await _plugin.resolvePlatformSpecificImplementation<fln.IOSFlutterLocalNotificationsPlugin>()?.requestPermissions(alert: true, badge: true, sound: true) ?? false;
        case TargetPlatform.macOS:
          return await _plugin.resolvePlatformSpecificImplementation<fln.MacOSFlutterLocalNotificationsPlugin>()?.requestPermissions(alert: true, badge: true, sound: true) ?? false;
        default:
          return false;
      }
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> replaceAll(List<Reminder> reminders) async {
    if (!await _init()) return;
    await _plugin.cancelAll();
    for (final r in reminders) {
      await _plugin.zonedSchedule(
        id: r.id,
        title: r.title,
        body: r.body,
        // an absolute instant: computed from local wall-clock time already, so UTC is just a container
        scheduledDate: tz.TZDateTime.from(r.at, tz.UTC),
        notificationDetails: _details,
        androidScheduleMode: fln.AndroidScheduleMode.inexactAllowWhileIdle,
        payload: r.payload,
      );
    }
  }
}
