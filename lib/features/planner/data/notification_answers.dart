import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Answers given with a notification's buttons (e.g. "Prayed" on "Did you pray?") are kept here until the app reads
/// them, because a button may be tapped while the app is closed (then only a small background task runs).
const _key = 'folio_notification_answers';

/// Keeps one answer: the notification's payload and the button's id.
Future<void> keepNotificationAnswer(String? payload, String? action) async {
  if (payload == null || payload.isEmpty || action == null || action.isEmpty) return;
  final p = await SharedPreferences.getInstance();
  await p.reload();
  final list = p.getStringList(_key) ?? <String>[];
  list.add('$action|$payload');
  await p.setStringList(_key, list);
}

/// The answers kept so far, oldest first, as (action, payload); they are removed once taken.
Future<List<(String, String)>> takeNotificationAnswers() async {
  final p = await SharedPreferences.getInstance();
  await p.reload();
  final list = p.getStringList(_key) ?? const <String>[];
  if (list.isEmpty) return const [];
  await p.remove(_key);
  return [
    for (final e in list)
      if (e.indexOf('|') case final i when i > 0) (e.substring(0, i), e.substring(i + 1)),
  ];
}

/// Runs in a background isolate when a notification button that does not open the app is tapped.
@pragma('vm:entry-point')
Future<void> folioNotificationBackground(NotificationResponse r) async {
  DartPluginRegistrant.ensureInitialized();
  await keepNotificationAnswer(r.payload, r.actionId);
}
