import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/components.dart';
import '../../../design_system/tokens.dart';
import '../application/planner_controller.dart';
import '../domain/agenda.dart';
import 'day_view.dart';
import 'format.dart';
import 'planner_editors.dart';
import 'planner_views.dart';

class PlannerPage extends ConsumerStatefulWidget {
  const PlannerPage({super.key});
  @override
  ConsumerState<PlannerPage> createState() => _PlannerPageState();
}

class _PlannerPageState extends ConsumerState<PlannerPage>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // "today" may have rolled over while the app was in the background
    if (state == AppLifecycleState.resumed &&
        ref.read(plannerControllerProvider).hasValue) {
      ref.read(plannerControllerProvider.notifier).refresh();
    }
  }

  String _title(PlannerState s) => switch (s.mode) {
    PlannerMode.day => dayTitle(s.day),
    PlannerMode.week => weekTitle(startOfWeek(s.day)),
    PlannerMode.month => monthTitle(s.day),
    PlannerMode.year => '${s.day.year}',
  };

  @override
  Widget build(BuildContext context) {
    final ctrl = ref.read(plannerControllerProvider.notifier);
    ref.listen(plannerControllerProvider, (prev, next) {
      final n = next.value, p = prev?.value;
      if (n == null) return;
      final messenger = ScaffoldMessenger.of(context);
      if (n.message != null && n.message != p?.message) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(n.message!),
            behavior: SnackBarBehavior.floating,
          ),
        );
        ctrl.clearMessage();
      } else if (n.undoLabel != null && n.undoLabel != p?.undoLabel) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(n.undoLabel!),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 5),
              action: SnackBarAction(label: 'Undo', onPressed: ctrl.undo),
            ),
          );
        ctrl.acknowledgeUndo();
      }
    });

    final async = ref.watch(plannerControllerProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => EmptyState(
        icon: Icons.error_outline,
        title: 'Couldn\'t open the planner',
        message: 'Your data is safe. Try again, or restart the app.',
        actionLabel: 'Retry',
        onAction: () => ref.invalidate(plannerControllerProvider),
      ),
      data: (s) => _content(context, s, ctrl),
    );
  }

  Widget _content(
    BuildContext context,
    PlannerState s,
    PlannerController ctrl,
  ) {
    final c = context.colors;
    final size = MediaQuery.sizeOf(context);
    final single = size.width >= 760; // one header row when there is room

    final nav = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          key: const Key('planner-prev'),
          tooltip: 'Previous',
          onPressed: () => ctrl.shift(-1),
          icon: const Icon(Icons.chevron_left),
        ),
        IconButton(
          key: const Key('planner-next'),
          tooltip: 'Next',
          onPressed: () => ctrl.shift(1),
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
    final today = TextButton(
      key: const Key('planner-today'),
      onPressed: ctrl.goToday,
      child: const Text('Today'),
    );
    final add = PopupMenuButton<String>(
      key: const Key('planner-add-menu'),
      tooltip: 'Add',
      icon: const Icon(Icons.add_circle_outline),
      onSelected: (v) => v == 'task'
          ? openTaskEditor(context, day: s.day)
          : openEventEditor(context, day: s.day),
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'task', child: Text('New task')),
        PopupMenuItem(value: 'event', child: Text('New event')),
      ],
    );
    final title = Expanded(
      child: Text(
        _title(s),
        key: const Key('planner-title'),
        style: Theme.of(context).textTheme.titleLarge,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
    final modes = SegmentedButton<PlannerMode>(
      key: const Key('planner-mode'),
      showSelectedIcon: false,
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      segments: const [
        ButtonSegment(value: PlannerMode.day, label: Text('Day')),
        ButtonSegment(value: PlannerMode.week, label: Text('Week')),
        ButtonSegment(value: PlannerMode.month, label: Text('Month')),
        ButtonSegment(value: PlannerMode.year, label: Text('Year')),
      ],
      selected: {s.mode},
      onSelectionChanged: (m) => ctrl.setMode(m.first),
    );

    final header = single
        ? Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.s16,
              Space.s8,
              Space.s8,
              0,
            ),
            child: Row(
              children: [
                nav,
                title,
                const SizedBox(width: Space.s8),
                modes,
                const SizedBox(width: Space.s8),
                today,
                add,
              ],
            ),
          )
        : Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.s8,
                  Space.s8,
                  Space.s4,
                  0,
                ),
                child: Row(children: [nav, title, today, add]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.s16,
                  0,
                  Space.s16,
                  Space.s4,
                ),
                child: SizedBox(width: double.infinity, child: modes),
              ),
            ],
          );

    final body = switch (s.mode) {
      PlannerMode.day => DayView(key: ValueKey('day-${s.day}'), state: s),
      PlannerMode.week => WeekView(state: s),
      PlannerMode.month => MonthView(state: s),
      PlannerMode.year => YearView(state: s),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        if (s.notificationsDenied)
          Container(
            key: const Key('notifications-denied'),
            margin: const EdgeInsets.symmetric(
              horizontal: Space.s16,
              vertical: Space.s4,
            ),
            padding: const EdgeInsets.all(Space.s8),
            decoration: BoxDecoration(
              color: Color.alphaBlend(c.warn.withValues(alpha: .18), c.surface),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.notifications_off_outlined, size: 18, color: c.warn),
                const SizedBox(width: Space.s8),
                const Expanded(
                  child: Text(
                    'Notifications are off for Folio, so reminders can\'t appear. Turn them on in the system settings.',
                  ),
                ),
              ],
            ),
          ),
        Expanded(child: body),
      ],
    );
  }
}
