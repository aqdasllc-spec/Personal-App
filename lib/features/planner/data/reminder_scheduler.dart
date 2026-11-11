import '../domain/reminders.dart';

/// What the OS and plugin are currently doing, for the Settings → Notifications panel.
class ReminderDiagnostics {
  const ReminderDiagnostics({
    this.supported = false,
    this.permissionGranted = false,
    this.exactAlarms,
    this.pendingCount = 0,
    this.lastError,
    this.lastMode,
  });

  /// This platform can show scheduled notifications at all.
  final bool supported;
  final bool permissionGranted;

  /// Android only: whether exact alarms are allowed (null = not applicable / unknown).
  final bool? exactAlarms;

  /// Notifications currently pending in the OS.
  final int pendingCount;

  /// The last scheduling problem, if any (otherwise failures would be invisible).
  final String? lastError;

  /// How the last reminders were scheduled: 'exact' or 'approximate'.
  final String? lastMode;
}

/// Schedules OS notifications. The planner only ever asks for "make exactly these reminders pending".
abstract interface class ReminderScheduler {
  Future<bool> hasPermission();

  /// Asks the user (Android 13+, iOS, macOS). Returns whether notifications are now allowed.
  Future<bool> requestPermission();

  /// Cancels everything we scheduled and schedules [reminders] (already limited to the platform cap).
  Future<void> replaceAll(List<Reminder> reminders);

  Future<ReminderDiagnostics> diagnostics();

  /// Shows a notification immediately. Returns false if it could not be shown.
  Future<bool> sendTestNow();

  /// Schedules a notification [after] from now - proves scheduled delivery works with the app closed.
  Future<bool> scheduleTest(Duration after);

  /// Cancels the prayer-time reminders scheduled before and schedules [alarms] (ids from [prayerNotificationIds]).
  /// Planner reminders are not touched, and [replaceAll] does not touch these.
  Future<void> replacePrayerAlarms(List<Reminder> alarms);

  /// The same for the morning ayah-of-the-day notifications (ids from [dailyAyahNotificationIds]).
  Future<void> replaceDailyAyahAlarms(List<Reminder> alarms);

  /// Shows a prayer reminder at [Reminder.at] (a few seconds from now) with its tone, to hear how it sounds.
  Future<bool> testPrayerAlarm(Reminder r);

  /// The payload of each notification the user taps while the app runs.
  Stream<String> get taps;

  /// The payload of the notification that started the app, once (null when it was started another way).
  Future<String?> takeLaunchPayload();

  /// The ids of the notifications now waiting to be shown (to show that reminders are really set).
  Future<Set<int>> pendingIds();
}

/// Used where notifications aren't available (tests, unsupported platforms).
class NoopReminderScheduler implements ReminderScheduler {
  @override
  Future<bool> hasPermission() async => false;
  @override
  Future<bool> requestPermission() async => false;
  @override
  Future<void> replaceAll(List<Reminder> reminders) async {}
  @override
  Future<void> replacePrayerAlarms(List<Reminder> alarms) async {}
  @override
  Future<void> replaceDailyAyahAlarms(List<Reminder> alarms) async {}
  @override
  Future<bool> testPrayerAlarm(Reminder r) async => false;
  @override
  Future<ReminderDiagnostics> diagnostics() async =>
      const ReminderDiagnostics();
  @override
  Future<bool> sendTestNow() async => false;
  @override
  Future<bool> scheduleTest(Duration after) async => false;
  @override
  Stream<String> get taps => const Stream.empty();
  @override
  Future<String?> takeLaunchPayload() async => null;
  @override
  Future<Set<int>> pendingIds() async => const {};
}
