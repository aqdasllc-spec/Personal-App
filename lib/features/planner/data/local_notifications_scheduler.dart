import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
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

  /// Ids reserved for the test buttons; [replaceAll] never cancels these.
  static const _testNowId = 0x7ffffff0;
  static const _testLaterId = 0x7ffffff1;

  String? _lastError;
  String? _lastMode;

  fln.AndroidFlutterLocalNotificationsPlugin? get _android => _plugin.resolvePlatformSpecificImplementation<fln.AndroidFlutterLocalNotificationsPlugin>();

  /// Exact alarms are allowed on Android 12 and older by default, and on newer versions because the app
  /// declares USE_EXACT_ALARM (it is a calendar/reminder app). Anything else falls back to approximate.
  Future<bool> _canUseExact() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      return await _android?.canScheduleExactNotifications() ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _scheduleOne(int id, DateTime at, String title, String body, String? payload, bool exact) async {
    Future<void> go(fln.AndroidScheduleMode mode) => _plugin.zonedSchedule(
          id: id,
          title: title,
          body: body,
          // an absolute instant: computed from local wall-clock time already, so UTC is just a container
          scheduledDate: tz.TZDateTime.from(at, tz.UTC),
          notificationDetails: _details,
          androidScheduleMode: mode,
          payload: payload,
        );
    try {
      await go(exact ? fln.AndroidScheduleMode.exactAllowWhileIdle : fln.AndroidScheduleMode.inexactAllowWhileIdle);
      _lastMode = exact ? 'exact' : 'approximate';
    } on PlatformException catch (e) {
      if (exact && e.code == 'exact_alarms_not_permitted') {
        await go(fln.AndroidScheduleMode.inexactAllowWhileIdle); // still better than nothing
        _lastMode = 'approximate';
        return;
      }
      rethrow;
    }
  }

  @override
  Future<void> replaceAll(List<Reminder> reminders) async {
    if (!await _init()) {
      _lastError = 'Notifications are not available on this device.';
      return;
    }
    try {
      // cancel what we scheduled before, but keep the diagnostic test notifications alive
      for (final p in await _plugin.pendingNotificationRequests()) {
        if (p.id != _testNowId && p.id != _testLaterId) await _plugin.cancel(id: p.id);
      }
      final exact = await _canUseExact();
      for (final r in reminders) {
        await _scheduleOne(r.id, r.at, r.title, r.body, r.payload, exact);
      }
      _lastError = null;
    } catch (e) {
      _lastError = '$e';
      rethrow; // the planner logs it; Settings shows [_lastError]
    }
  }

  @override
  Future<ReminderDiagnostics> diagnostics() async {
    if (!await _init()) return const ReminderDiagnostics(supported: false);
    var pending = 0;
    try {
      pending = (await _plugin.pendingNotificationRequests()).where((p) => p.id != _testNowId && p.id != _testLaterId).length;
    } catch (_) {}
    return ReminderDiagnostics(
      supported: true,
      permissionGranted: await hasPermission(),
      exactAlarms: defaultTargetPlatform == TargetPlatform.android ? await _canUseExact() : null,
      pendingCount: pending,
      lastError: _lastError,
      lastMode: _lastMode,
    );
  }

  @override
  Future<bool> sendTestNow() async {
    if (!await _init()) return false;
    try {
      await _plugin.show(id: _testNowId, title: 'Folio test', body: 'If you can read this, notifications work.', notificationDetails: _details);
      return true;
    } catch (e) {
      _lastError = '$e';
      return false;
    }
  }

  @override
  Future<bool> scheduleTest(Duration after) async {
    if (!await _init()) return false;
    try {
      await _scheduleOne(_testLaterId, DateTime.now().add(after), 'Folio scheduled test', 'This arrived on schedule, even with Folio closed.', 'test', await _canUseExact());
      return true;
    } catch (e) {
      _lastError = '$e';
      return false;
    }
  }
}
