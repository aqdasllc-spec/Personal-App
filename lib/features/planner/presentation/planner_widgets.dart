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
  });
  final AgendaItem item;
  final VoidCallback onOpen;
  final bool showDate;
  final bool dense;

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
              padding: EdgeInsets.symmetric(vertical: widget.dense ? 0 : Space.s4),
              child: Row(
                children: [
                  Checkbox(
                    key: Key('done-${item.id}'),
                    value: item.done,
                    visualDensity: widget.dense ? VisualDensity.compact : VisualDensity.standard,
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
                            decoration: item.done ? TextDecoration.lineThrough : null,
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
                        padding: const EdgeInsets.symmetric(horizontal: Space.s8, vertical: Space.s4),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(allDone ? Icons.checklist_rtl : Icons.checklist, size: 16, color: allDone ? c.ok : c.textMuted),
                          const SizedBox(width: Space.s4),
                          Text('${item.checkDone}/$total', style: t.bodySmall?.copyWith(color: allDone ? c.ok : c.textMuted)),
                          Icon(_open ? Icons.expand_less : Icons.expand_more, size: 16, color: c.textMuted),
                        ]),
                      ),
                    ),
                  if (item.repeats)
                    Padding(
                      padding: const EdgeInsets.only(left: Space.s4),
                      child: Icon(Icons.repeat, size: 16, color: c.textMuted, semanticLabel: 'Repeats'),
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
                      child: Row(children: [
                        Checkbox(
                          visualDensity: VisualDensity.compact,
                          value: sc.done,
                          onChanged: (_) => ctrl.toggleChecklistItem(item.id, sc.id),
                        ),
                        Expanded(
                          child: Text(
                            sc.title,
                            style: t.bodyMedium?.copyWith(
                              decoration: sc.done ? TextDecoration.lineThrough : null,
                              color: sc.done ? c.textMuted : c.text,
                            ),
                          ),
                        ),
                      ]),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 24-hour-style timeline with blocks laid out side by side when they overlap.
class DayTimeline extends StatelessWidget {
  const DayTimeline({
    super.key,
    required this.day,
    required this.agenda,
    required this.today,
    required this.onOpen,
    this.hourHeight = 56,
  });
  final DateTime day;
  final DayAgenda agenda;
  final DateTime today;
  final ValueChanged<AgendaItem> onOpen;
  final double hourHeight;

  @override
  Widget build(BuildContext context) {
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
    const labelW = 48.0;
    final height = (endH - startH) * hourHeight;

    return SizedBox(
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
                  child: _Block(item: b.item, onTap: () => onOpen(b.item)),
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
            ],
          );
        },
      ),
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
