import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design_system/tokens.dart';
import '../planner/application/planner_controller.dart';
import '../planner/presentation/format.dart';

/// Shows what the OS is really doing with reminders, and lets the user prove delivery works.
/// Silent failure was the problem: this makes every failure visible.
class NotificationsTiles extends ConsumerWidget {
  const NotificationsTiles({super.key});

  void _say(BuildContext context, String m) => ScaffoldMessenger.of(context)
      .showSnackBar(
        SnackBar(content: Text(m), behavior: SnackBarBehavior.floating),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final diag = ref.watch(reminderDiagnosticsProvider);
    final upcoming = ref.watch(upcomingRemindersProvider);
    final scheduler = ref.read(reminderSchedulerProvider);

    return diag.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(Space.s16),
        child: LinearProgressIndicator(),
      ),
      error: (e, _) => ListTile(
        title: const Text('Couldn\'t check notifications'),
        subtitle: Text('$e'),
      ),
      data: (d) {
        final next = upcoming.value?.firstOrNull;
        void refresh() {
          ref.invalidate(reminderDiagnosticsProvider);
          ref.invalidate(upcomingRemindersProvider);
        }

        if (!d.supported) {
          return const ListTile(
            title: Text('Reminders'),
            subtitle: Text(
              'Reminders are saved, but this device or platform can\'t show notifications from Folio yet.',
            ),
          );
        }
        return Column(
          children: [
            ListTile(
              key: const Key('notif-status'),
              title: const Text('Notifications'),
              subtitle: Text(
                d.permissionGranted
                    ? 'Allowed'
                    : 'Blocked — reminders can\'t appear until you allow them.',
              ),
              trailing: Icon(
                d.permissionGranted
                    ? Icons.notifications_active_outlined
                    : Icons.notifications_off_outlined,
                color: d.permissionGranted ? c.ok : c.danger,
              ),
            ),
            if (!d.permissionGranted)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.s16,
                  0,
                  Space.s16,
                  Space.s8,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton(
                    key: const Key('notif-allow'),
                    onPressed: () async {
                      final ok = await scheduler.requestPermission();
                      refresh();
                      if (!ok && context.mounted) {
                        _say(
                          context,
                          'Still blocked. Open Android Settings → Apps → Folio → Notifications and turn them on.',
                        );
                      }
                    },
                    child: const Text('Allow notifications'),
                  ),
                ),
              ),
            if (d.exactAlarms != null)
              ListTile(
                key: const Key('notif-exact'),
                title: const Text('Timing'),
                subtitle: Text(
                  d.exactAlarms!
                      ? 'Exact — reminders fire at the chosen minute.'
                      : 'Approximate — Android may delay reminders by several minutes.',
                ),
              ),
            ListTile(
              key: const Key('notif-pending'),
              title: const Text('Scheduled reminders'),
              subtitle: Text(
                '${d.pendingCount} waiting in Android${next == null ? '' : '\nNext: ${next.title} — ${dateLabel(next.at)} ${timeLabel(next.at)}'}${upcoming.value != null && upcoming.value!.isNotEmpty && d.pendingCount == 0 && d.permissionGranted ? '\n⚠ Folio has reminders to schedule but Android has none queued.' : ''}',
              ),
            ),
            if (d.lastError != null)
              ListTile(
                key: const Key('notif-error'),
                title: Text('Last problem', style: TextStyle(color: c.danger)),
                subtitle: Text(d.lastError!),
              ),
            Padding(
              padding: const EdgeInsets.all(Space.s16),
              child: Wrap(
                spacing: Space.s8,
                runSpacing: Space.s8,
                children: [
                  OutlinedButton.icon(
                    key: const Key('notif-test-now'),
                    icon: const Icon(Icons.notifications_none),
                    label: const Text('Send a test now'),
                    onPressed: () async {
                      final ok = await scheduler.sendTestNow();
                      refresh();
                      if (context.mounted) {
                        _say(
                          context,
                          ok
                              ? 'Sent. Check your notification shade.'
                              : 'Couldn\'t send it. See "Last problem" above.',
                        );
                      }
                    },
                  ),
                  OutlinedButton.icon(
                    key: const Key('notif-test-later'),
                    icon: const Icon(Icons.schedule_send_outlined),
                    label: const Text('Test in 1 minute'),
                    onPressed: () async {
                      final ok = await scheduler.scheduleTest(
                        const Duration(minutes: 1),
                      );
                      refresh();
                      if (context.mounted) {
                        _say(
                          context,
                          ok
                              ? 'Scheduled. Close Folio and wait about a minute.'
                              : 'Couldn\'t schedule it. See "Last problem" above.',
                        );
                      }
                    },
                  ),
                  TextButton(onPressed: refresh, child: const Text('Refresh')),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
