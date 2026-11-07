import 'dart:async';

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

  // phone layout: scroll by itself while a task is dragged near the top / bottom edge
  final _scroll = ScrollController();
  final _areaKey = GlobalKey();
  Timer? _autoScroll;
  double _velocity = 0;
  final _focus = FocusNode();

  @override
  void dispose() {
    _autoScroll?.cancel();
    _scroll.dispose();
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

  void _dragMoved(Offset global) {
    final box = _areaKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !_scroll.hasClients) return;
    final y = box.globalToLocal(global).dy;
    final h = box.size.height;
    const edge = 90.0, max = 18.0;
    _velocity = y < edge
        ? -(edge - y).clamp(0, edge) / edge * max
        : (y > h - edge ? (y - (h - edge)).clamp(0, edge) / edge * max : 0);
    if (_velocity != 0) {
      _autoScroll ??= Timer.periodic(const Duration(milliseconds: 16), (_) {
        if (!_scroll.hasClients || _velocity == 0) return;
        final p = _scroll.position;
        _scroll.jumpTo(
          (p.pixels + _velocity).clamp(p.minScrollExtent, p.maxScrollExtent),
        );
      });
    }
  }

  void _dragEnded() {
    _velocity = 0;
    _autoScroll?.cancel();
    _autoScroll = null;
  }

  /// "Pick a time" button: choose a time for [item] on the day being shown.
  Future<void> _pickTime(AgendaItem item) async {
    final day = widget.state.day;
    final picked = await showTimePicker(
      context: context,
      helpText: 'Time for "${item.title}"',
      initialTime: item.plannedAt != null
          ? TimeOfDay.fromDateTime(item.plannedAt!)
          : const TimeOfDay(hour: 9, minute: 0),
    );
    if (picked == null || !mounted) return;
    await ref
        .read(plannerControllerProvider.notifier)
        .scheduleTask(
          item.id,
          DateTime(day.year, day.month, day.day, picked.hour, picked.minute),
        );
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
          DraggableTask(
            item: i,
            child: TaskTile(
              item: i,
              showDate: true,
              onOpen: () => _open(i),
              onPickTime: () => _pickTime(i),
            ),
          ),
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
        for (final i in a.tasks)
          DraggableTask(
            item: i,
            child: TaskTile(
              item: i,
              onOpen: () => _open(i),
              onPickTime: () => _pickTime(i),
            ),
          ),
    ];

    final canSchedule = a.tasks.any((x) => !x.done) || a.overdue.isNotEmpty;
    final timelineGrid = DayTimeline(
      day: s.day,
      agenda: a,
      today: s.today,
      onOpen: _open,
      onSchedule: (id, start) =>
          ref.read(plannerControllerProvider.notifier).scheduleTask(id, start),
    );
    final timeline = a.timed.isEmpty && !canSchedule
        ? Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.s16),
            child: Text(
              'Nothing scheduled at a particular time. Add an event, or give a task a time block, and it appears here.',
              style: t.bodySmall,
            ),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (a.timed.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.s8),
                  child: Text(
                    DraggableTask.isTouch
                        ? 'Nothing scheduled yet. Press and hold a task, then drop it here to give it a time.'
                        : 'Nothing scheduled yet. Drag a task here to give it a time.',
                    key: const Key('schedule-hint'),
                    style: t.bodySmall,
                  ),
                ),
              timelineGrid,
            ],
          );

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
    return DragScope(
      onMove: _dragMoved,
      onEnd: _dragEnded,
      child: ListView(
        key: _areaKey,
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(Space.s16, Space.s8, Space.s16, 96),
        children: [
          quickAdd,
          ...checklist,
          const SizedBox(height: Space.s16),
          const _Section(title: 'Schedule'),
          timeline,
        ],
      ),
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
