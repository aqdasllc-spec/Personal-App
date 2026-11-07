import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/tokens.dart';
import '../application/planner_controller.dart';
import '../domain/agenda.dart';
import '../domain/models.dart';
import 'format.dart';

Color priorityColor(BuildContext context, Priority p) {
  final c = context.colors;
  return switch (p) {
    Priority.high => c.danger,
    Priority.medium => c.warn,
    Priority.low => c.info,
    Priority.none => c.textMuted,
  };
}

/// One checklist row: checkbox, title, time, priority, repeat, and a sub-task counter that expands the
/// sub-tasks in place. Tap opens the editor.
class TaskTile extends ConsumerStatefulWidget {
  const TaskTile({
    super.key,
    required this.item,
    required this.onOpen,
    this.showDate = false,
    this.dense = false,
    this.onPickTime,
  });
  final AgendaItem item;
  final VoidCallback onOpen;
  final bool showDate;
  final bool dense;

  /// Shows a clock button that lets the user pick the time for this task (opens a time picker).
  final VoidCallback? onPickTime;

  @override
  ConsumerState<TaskTile> createState() => _TaskTileState();
}

class _TaskTileState extends ConsumerState<TaskTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final ctrl = ref.read(plannerControllerProvider.notifier);
    final sub = <String>[
      if (widget.showDate && item.start != null)
        '${weekdayShort(item.start!.weekday)} ${item.start!.day} ${monthShort(item.start!.month)}',
      if (item.hasTime && item.start != null) timeLabel(item.start!),
    ].join(' · ');
    final total = item.checklist.length;
    final allDone = total > 0 && item.checkDone == total;
    return Semantics(
      label:
          '${item.title}${item.done ? ', done' : ''}${sub.isEmpty ? '' : ', $sub'}${total == 0 ? '' : ', ${item.checkDone} of $total sub-tasks done'}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            key: Key('task-${item.id}'),
            onTap: widget.onOpen,
            child: Padding(
              padding: EdgeInsets.symmetric(
                vertical: widget.dense ? 0 : Space.s4,
              ),
              child: Row(
                children: [
                  Checkbox(
                    key: Key('done-${item.id}'),
                    value: item.done,
                    visualDensity: widget.dense
                        ? VisualDensity.compact
                        : VisualDensity.standard,
                    onChanged: (_) => ctrl.toggleDone(item.id),
                  ),
                  if (item.priority != Priority.none)
                    Padding(
                      padding: const EdgeInsets.only(right: Space.s8),
                      child: Icon(
                        Icons.flag,
                        size: 14,
                        color: priorityColor(context, item.priority),
                        semanticLabel: '${item.priority.label} priority',
                      ),
                    ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: t.bodyMedium?.copyWith(
                            decoration: item.done
                                ? TextDecoration.lineThrough
                                : null,
                            color: item.done ? c.textMuted : c.text,
                          ),
                        ),
                        if (sub.isNotEmpty) Text(sub, style: t.bodySmall),
                      ],
                    ),
                  ),
                  if (total > 0)
                    // sub-task counter: tap to show / hide them right here
                    InkWell(
                      key: Key('subtasks-${item.id}'),
                      borderRadius: BorderRadius.circular(Radii.pill),
                      onTap: () => setState(() => _open = !_open),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Space.s8,
                          vertical: Space.s4,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              allDone ? Icons.checklist_rtl : Icons.checklist,
                              size: 16,
                              color: allDone ? c.ok : c.textMuted,
                            ),
                            const SizedBox(width: Space.s4),
                            Text(
                              '${item.checkDone}/$total',
                              style: t.bodySmall?.copyWith(
                                color: allDone ? c.ok : c.textMuted,
                              ),
                            ),
                            Icon(
                              _open ? Icons.expand_less : Icons.expand_more,
                              size: 16,
                              color: c.textMuted,
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (widget.onPickTime != null && !item.done)
                    IconButton(
                      key: Key('schedule-${item.id}'),
                      tooltip: item.start != null && item.hasTime
                          ? 'Change time'
                          : 'Pick a time',
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        Icons.schedule,
                        size: 20,
                        color: item.hasTime ? c.accent : c.textMuted,
                      ),
                      onPressed: widget.onPickTime,
                    ),
                  if (item.repeats)
                    Padding(
                      padding: const EdgeInsets.only(left: Space.s4),
                      child: Icon(
                        Icons.repeat,
                        size: 16,
                        color: c.textMuted,
                        semanticLabel: 'Repeats',
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.only(left: Space.s32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final sc in item.checklist)
                    InkWell(
                      key: Key('sub-${sc.id}'),
                      onTap: () => ctrl.toggleChecklistItem(item.id, sc.id),
                      child: Row(
                        children: [
                          Checkbox(
                            visualDensity: VisualDensity.compact,
                            value: sc.done,
                            onChanged: (_) =>
                                ctrl.toggleChecklistItem(item.id, sc.id),
                          ),
                          Expanded(
                            child: Text(
                              sc.title,
                              style: t.bodyMedium?.copyWith(
                                decoration: sc.done
                                    ? TextDecoration.lineThrough
                                    : null,
                                color: sc.done ? c.textMuted : c.text,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// What is carried while a task is dragged to the timeline.
class TaskDrag {
  const TaskDrag(this.id, this.title, {this.fromDay});
  final String id, title;

  /// The day column the task was picked up from (week view); null from the day view.
  final DateTime? fromDay;
}

/// Lets a scrolling parent (the phone day view) follow a drag: it is told where the pointer is and when
/// the drag ends, so it can scroll while the pointer is near an edge.
class DragScope extends InheritedWidget {
  const DragScope({
    super.key,
    required this.onMove,
    required this.onEnd,
    required super.child,
  });
  final void Function(Offset globalPosition) onMove;
  final VoidCallback onEnd;

  static DragScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DragScope>();

  @override
  bool updateShouldNotify(DragScope old) => false;
}

/// Makes an open task draggable: press-and-hold on touch screens (so scrolling still works), plain drag with a
/// mouse. Drop it on the day timeline to give it a time block.
class DraggableTask extends StatelessWidget {
  const DraggableTask({
    super.key,
    required this.item,
    required this.child,
    this.fromDay,
  });
  final AgendaItem item;
  final Widget child;

  /// Set by the week view: which day the dragged tile belongs to.
  final DateTime? fromDay;

  static bool get isTouch =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.fuchsia;

  @override
  Widget build(BuildContext context) {
    if (item.done || item.kind != ItemKind.task) return child;
    final c = context.colors;
    final data = TaskDrag(item.id, item.title, fromDay: fromDay);
    final feedback = Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(Radii.input),
      color: c.surface,
      child: Container(
        width: 220,
        padding: const EdgeInsets.symmetric(
          horizontal: Space.s12,
          vertical: Space.s8,
        ),
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: c.brass, width: 3)),
          borderRadius: BorderRadius.circular(Radii.input),
        ),
        child: Text(
          item.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
    final dim = Opacity(opacity: .35, child: child);
    final scope = DragScope.maybeOf(context);
    void move(DragUpdateDetails d) => scope?.onMove(d.globalPosition);
    void end(DraggableDetails _) => scope?.onEnd();
    return isTouch
        ? LongPressDraggable<TaskDrag>(
            key: Key('drag-${item.id}'),
            data: data,
            dragAnchorStrategy: pointerDragAnchorStrategy,
            feedback: feedback,
            childWhenDragging: dim,
            onDragUpdate: move,
            onDragEnd: end,
            child: child,
          )
        : Draggable<TaskDrag>(
            key: Key('drag-${item.id}'),
            data: data,
            dragAnchorStrategy: pointerDragAnchorStrategy,
            feedback: feedback,
            childWhenDragging: dim,
            onDragUpdate: move,
            onDragEnd: end,
            child: child,
          );
  }
}

/// 24-hour-style timeline with blocks laid out side by side when they overlap.
class DayTimeline extends StatefulWidget {
  const DayTimeline({
    super.key,
    required this.day,
    required this.agenda,
    required this.today,
    required this.onOpen,
    this.hourHeight = 56,
    this.onSchedule,
  });
  final DateTime day;
  final DayAgenda agenda;
  final DateTime today;
  final ValueChanged<AgendaItem> onOpen;
  final double hourHeight;

  /// Called when a task is dropped on the timeline: its id and the (15-minute snapped) start time.
  final void Function(String taskId, DateTime start)? onSchedule;

  @override
  State<DayTimeline> createState() => _DayTimelineState();
}

class _DayTimelineState extends State<DayTimeline> {
  final _areaKey = GlobalKey();
  int _startH = 7;
  int? _hoverMinute;

  /// Minutes since midnight under [global] (the pointer), snapped to 15.
  int? _minuteAt(Offset global) {
    final box = _areaKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached) return null;
    final local = box.globalToLocal(global);
    final raw = _startH * 60 + local.dy / widget.hourHeight * 60;
    return ((raw / 15).round() * 15).clamp(0, 24 * 60 - 15);
  }

  @override
  Widget build(BuildContext context) {
    final day = widget.day,
        agenda = widget.agenda,
        today = widget.today,
        hourHeight = widget.hourHeight;
    final c = context.colors;
    final blocks = layoutBlocks(agenda.timed, day);
    final nowMin = sameDay(day, today)
        ? DateTime.now().difference(dateOnly(day)).inMinutes
        : null;
    // show from 7:00 (or earlier if something starts earlier) to 21:00 (or later if needed)
    var startH = 7, endH = 21;
    for (final b in blocks) {
      startH = startH < b.startMinute ~/ 60 ? startH : b.startMinute ~/ 60;
      endH = endH > (b.endMinute + 59) ~/ 60 ? endH : (b.endMinute + 59) ~/ 60;
    }
    if (nowMin != null) {
      startH = startH < nowMin ~/ 60 ? startH : nowMin ~/ 60;
      endH = endH > nowMin ~/ 60 + 1 ? endH : nowMin ~/ 60 + 1;
    }
    endH = endH.clamp(startH + 1, 24);
    _startH = startH;
    const labelW = 48.0;
    final height = (endH - startH) * hourHeight;

    final grid = SizedBox(
      key: _areaKey,
      height: height,
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth - labelW;
          return Stack(
            children: [
              for (var h = startH; h <= endH; h++)
                Positioned(
                  top: (h - startH) * hourHeight,
                  left: 0,
                  right: 0,
                  child: Row(
                    children: [
                      SizedBox(
                        width: labelW,
                        child: Text(
                          '${two(h % 24)}:00',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      Expanded(child: Divider(height: 1, color: c.border)),
                    ],
                  ),
                ),
              for (final b in blocks)
                Positioned(
                  top: (b.startMinute / 60 - startH) * hourHeight + 1,
                  left: labelW + b.column * (w / b.columns),
                  width: w / b.columns - 3,
                  height: ((b.endMinute - b.startMinute) / 60 * hourHeight - 2)
                      .clamp(22, double.infinity),
                  child: DraggableTask(
                    item: b.item,
                    child: _Block(
                      item: b.item,
                      onTap: () => widget.onOpen(b.item),
                    ),
                  ),
                ),
              if (nowMin != null &&
                  nowMin >= startH * 60 &&
                  nowMin <= endH * 60)
                Positioned(
                  top: (nowMin / 60 - startH) * hourHeight,
                  left: labelW - 4,
                  right: 0,
                  child: Container(
                    key: const Key('now-line'),
                    height: 2,
                    color: c.danger,
                  ),
                ),
              if (_hoverMinute != null)
                Positioned(
                  top: (_hoverMinute! / 60 - startH) * hourHeight - 1,
                  left: 0,
                  right: 0,
                  child: Row(
                    key: const Key('drop-line'),
                    children: [
                      Container(
                        width: labelW,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        color: c.accent,
                        child: Text(
                          timeLabel(
                            dateOnly(day).add(Duration(minutes: _hoverMinute!)),
                          ),
                          key: const Key('drop-time'),
                          style: TextStyle(
                            color: c.onAccent,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Expanded(child: Container(height: 3, color: c.accent)),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );

    if (widget.onSchedule == null) return grid;
    return DragTarget<TaskDrag>(
      onWillAcceptWithDetails: (_) => true,
      onMove: (d) {
        final m = _minuteAt(d.offset);
        if (m != _hoverMinute) setState(() => _hoverMinute = m);
      },
      onLeave: (_) {
        if (_hoverMinute != null) setState(() => _hoverMinute = null);
      },
      onAcceptWithDetails: (d) {
        final m = _minuteAt(d.offset);
        setState(() => _hoverMinute = null);
        if (m != null) {
          widget.onSchedule!(
            d.data.id,
            dateOnly(day).add(Duration(minutes: m)),
          );
        }
      },
      builder: (context, candidates, rejected) => grid,
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({required this.item, required this.onTap});
  final AgendaItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isTask = item.kind == ItemKind.task;
    final bg = isTask
        ? Color.alphaBlend(c.brass.withValues(alpha: .22), c.surface)
        : c.accentSoft;
    final edge = isTask ? c.brass : c.accent;
    return Semantics(
      button: true,
      label:
          '${isTask ? 'Task' : 'Event'}: ${item.title}, ${timeLabel(item.start!)}${item.end == null ? '' : ' to ${timeLabel(item.end!)}'}',
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          key: Key('block-${item.kind.name}-${item.id}'),
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: edge, width: 3)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '${timeLabel(item.start!)}  ${item.title}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: c.text,
                decoration: item.done ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Scrolls a list by itself while a dragged item is held near its top or bottom edge. Feed it the pointer
/// position (global) on every move and tell it when the drag ends.
class EdgeAutoScroller {
  EdgeAutoScroller({required this.controller, required this.areaKey});
  final ScrollController controller;

  /// A key on the visible scroll area (its box is the "screen" the edges are measured on).
  final GlobalKey areaKey;
  Timer? _timer;
  double _velocity = 0;

  void move(Offset global) {
    final box = areaKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !controller.hasClients) return;
    final y = box.globalToLocal(global).dy;
    final h = box.size.height;
    const edge = 90.0, top = 18.0;
    _velocity = y < edge
        ? -(edge - y).clamp(0, edge) / edge * top
        : (y > h - edge ? (y - (h - edge)).clamp(0, edge) / edge * top : 0);
    if (_velocity != 0) {
      _timer ??= Timer.periodic(const Duration(milliseconds: 16), (_) {
        if (!controller.hasClients || _velocity == 0) return;
        final p = controller.position;
        controller.jumpTo(
          (p.pixels + _velocity).clamp(p.minScrollExtent, p.maxScrollExtent),
        );
      });
    }
  }

  void end() {
    _velocity = 0;
    _timer?.cancel();
    _timer = null;
  }

  void dispose() => end();
}
