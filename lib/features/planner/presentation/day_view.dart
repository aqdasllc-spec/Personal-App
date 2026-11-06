import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/components.dart';
import '../../../design_system/tokens.dart';
import '../application/planner_controller.dart';
import '../domain/agenda.dart';
import 'format.dart';
import 'planner_editors.dart';
import 'planner_widgets.dart';

class DayView extends ConsumerStatefulWidget {
  const DayView({super.key, required this.state});
  final PlannerState state;
  @override
  ConsumerState<DayView> createState() => _DayViewState();
}

class _DayViewState extends ConsumerState<DayView> {
  final _quick = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _quick.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _quick.text;
    if (text.trim().isEmpty) return;
    final id = await ref
        .read(plannerControllerProvider.notifier)
        .quickAdd(text);
    if (id != null) {
      _quick.clear();
      _focus.requestFocus();
    }
  }

  void _open(AgendaItem item) {
    final s = widget.state;
    if (item.kind == ItemKind.task) {
      openTaskEditor(context, task: s.tasks.firstWhere((t) => t.id == item.id));
    } else {
      openEventEditor(
        context,
        event: s.events.firstWhere((e) => e.id == item.id),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final a = s.agenda;
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final wide = MediaQuery.sizeOf(context).width >= 900;

    final quickAdd = Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.s8),
      child: TextField(
        key: const Key('planner-quick-add'),
        controller: _quick,
        focusNode: _focus,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          isDense: true,
          hintText: sameDay(s.day, s.today)
              ? 'Add a task for today…'
              : 'Add a task for ${weekdayShort(s.day.weekday)} ${s.day.day} ${monthShort(s.day.month)}…',
          prefixIcon: const Icon(Icons.add),
          suffixIcon: IconButton(
            key: const Key('planner-quick-add-go'),
            tooltip: 'Add task',
            icon: const Icon(Icons.keyboard_return),
            onPressed: _submit,
          ),
        ),
        onSubmitted: (_) => _submit(),
      ),
    );

    final checklist = <Widget>[
      if (a.overdue.isNotEmpty) ...[
        _Section(title: 'Overdue', color: c.danger, count: a.overdue.length),
        for (final i in a.overdue)
          TaskTile(item: i, showDate: true, onOpen: () => _open(i)),
        const SizedBox(height: Space.s8),
      ],
      if (a.allDay.isNotEmpty) ...[
        const _Section(title: 'All day'),
        Wrap(
          spacing: Space.s8,
          runSpacing: Space.s4,
          children: [
            for (final i in a.allDay)
              ActionChip(
                key: Key('allday-${i.id}'),
                avatar: const Icon(Icons.event, size: 16),
                label: Text(i.title),
                onPressed: () => _open(i),
              ),
          ],
        ),
        const SizedBox(height: Space.s8),
      ],
      _Section(title: 'Tasks', count: a.tasks.isEmpty ? null : a.tasks.length),
      if (a.tasks.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.s8),
          child: Text('No tasks for this day.', style: t.bodySmall),
        )
      else
        for (final i in a.tasks) TaskTile(item: i, onOpen: () => _open(i)),
    ];

    final timeline = a.timed.isEmpty
        ? Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.s16),
            child: Text(
              'Nothing scheduled at a particular time. Add an event, or give a task a time block, and it appears here.',
              style: t.bodySmall,
            ),
          )
        : DayTimeline(day: s.day, agenda: a, today: s.today, onOpen: _open);

    if (a.isEmpty && s.tasks.isEmpty && s.events.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(Space.s16),
        children: [
          quickAdd,
          const SizedBox(height: Space.s24),
          EmptyState(
            icon: Icons.calendar_month_outlined,
            title: 'Plan your day',
            message: 'Add a task above, or create an event. Tasks can repeat, get a time block and remind you.',
            actionLabel: 'New event',
            onAction: () => openEventEditor(context, day: s.day),
          ),
        ],
      );
    }

    if (wide) {
      return Padding(
        padding: const EdgeInsets.all(Space.s16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 5,
              child: ListView(children: [quickAdd, ...checklist]),
            ),
            const SizedBox(width: Space.s24),
            Expanded(
              flex: 4,
              child: ListView(
                children: [
                  const _Section(title: 'Schedule'),
                  timeline,
                ],
              ),
            ),
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(Space.s16, Space.s8, Space.s16, 96),
      children: [
        quickAdd,
        ...checklist,
        const SizedBox(height: Space.s16),
        const _Section(title: 'Schedule'),
        timeline,
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, this.color, this.count});
  final String title;
  final Color? color;
  final int? count;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Space.s8, bottom: Space.s4),
    child: Text(
      count == null ? title : '$title · $count',
      style: Theme.of(context).textTheme.titleMedium?.copyWith(color: color),
    ),
  );
}
