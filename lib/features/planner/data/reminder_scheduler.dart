import '../domain/reminders.dart';

/// Schedules OS notifications. The planner only ever asks for "make exactly these reminders pending".
abstract interface class ReminderScheduler {
  Future<bool> hasPermission();

  /// Asks the user (Android 13+, iOS, macOS). Returns whether notifications are now allowed.
  Future<bool> requestPermission();

  /// Cancels everything we scheduled and schedules [reminders] (already limited to the platform cap).
  Future<void> replaceAll(List<Reminder> reminders);
}

/// Used where notifications aren't available (tests, unsupported platforms).
class NoopReminderScheduler implements ReminderScheduler {
  @override
  Future<bool> hasPermission() async => false;
  @override
  Future<bool> requestPermission() async => false;
  @override
  Future<void> replaceAll(List<Reminder> reminders) async {}
}
