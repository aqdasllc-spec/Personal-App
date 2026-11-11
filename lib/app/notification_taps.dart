import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/planner/application/planner_controller.dart' show reminderSchedulerProvider;
import '../features/quran/prayer/prayer_providers.dart' show applyPrayerAnswersProvider;
import 'router.dart';

/// Where a tapped notification leads: a prayer reminder to the prayer times, the ayah of the day to that ayah,
/// a planner reminder to the planner. Null = just open the app.
String? routeForNotification(String payload) {
  final p = payload.split(':');
  switch (p.first) {
    case 'prayer' || 'prayer-again' || 'prayer-test' || 'prayer-renew' || 'check':
      return Routes.prayer;
    case 'ayah':
      final s = p.length > 1 ? int.tryParse(p[1]) : null, a = p.length > 2 ? int.tryParse(p[2]) : null;
      if (s == null || s < 1 || s > 114) return Routes.quran;
      return a == null ? '${Routes.quran}/$s' : '${Routes.quran}/$s?ayah=$a';
    case 'task' || 'event':
      return Routes.planner;
  }
  return null;
}

/// Follows notification taps (and the one that started the app) to their screen.
void followNotificationTaps(WidgetRef ref) {
  final sched = ref.read(reminderSchedulerProvider);
  void go(String payload) {
    if (payload.startsWith('answer:')) {
      // Prayed / Missed tapped while the app runs: put it into the prayer log now
      unawaited(ref.read(applyPrayerAnswersProvider)().catchError((Object _) => 0));
      return;
    }
    final to = routeForNotification(payload);
    if (to != null) ref.read(routerProvider).go(to);
  }

  sched.takeLaunchPayload().then((p) {
    if (p != null) go(p);
  }).catchError((Object _) {});
  sched.taps.listen(go);
}
