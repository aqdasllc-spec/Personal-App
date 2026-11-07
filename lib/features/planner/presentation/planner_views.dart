import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/tokens.dart';
import '../application/planner_controller.dart';
import '../domain/agenda.dart';
import 'format.dart';
import 'planner_editors.dart';
import 'planner_widgets.dart';

void _open(BuildContext context, PlannerState s, AgendaItem item) {
  if (item.kind == ItemKind.task) {
    openTaskEditor(context, task: s.tasks.firstWhere((t) => t.id == item.id));
  } else {
    openEventEditor(
      context,
      event: s.events.firstWhere((e) => e.id == item.id),
    );
  }
}

// ======================================================================== week
class WeekView extends ConsumerStatefulWidget {
  const WeekView({super.key, required this.state});
  final PlannerState state;

  @override
  ConsumerState<WeekView> createState() => _WeekViewState();
}

class _WeekViewState extends ConsumerState<WeekView> {
  final _scroll = ScrollController();
  final _areaKey = GlobalKey();
  late final _auto = EdgeAutoScroller(controller: _scroll, areaKey: _areaKey);

  @override
  void dispose() {
    _auto.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final s = state;
    final c = context.colors;
    final monday = startOfWeek(s.day);
    final days = [
      for (var i = 0; i < 7; i++)
        DateTime(monday.year, monday.month, monday.day + i),
    ];
    final agendas = [
      for (final d in days) dayAgenda(d, s.tasks, s.events, today: s.today),
    ];
    final ctrl = ref.read(plannerControllerProvider.notifier);
    final wide = MediaQuery.sizeOf(context).width >= 760;

    Widget dayBody(int i, {required bool dense}) {
      final a = agendas[i];
      final items = <Widget>[
        for (final e in [
          ...a.allDay,
          ...a.timed.where((x) => x.kind == ItemKind.event),
        ])
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: InkWell(
              key: Key('week-event-${days[i].day}-${e.id}'),
              onTap: () => _open(context, s, e),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: c.accentSoft,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${e.allDay ? '' : '${timeLabel(e.start!)} '}${e.title}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: c.text),
                ),
              ),
            ),
          ),
        for (final t in a.tasks)
          DraggableTask(
            item: t,
            fromDay: days[i],
            child: TaskTile(item: t, dense: true, onOpen: () => _open(context, s, t)),
          ),
      ];
      return items.isEmpty
          ? [Text('—', style: Theme.of(context).textTheme.bodySmall)].first
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: items,
            );
    }

    /// A day (column or section) that tasks can be dropped on.
    Widget dropTarget(int i, Widget Function(bool hovering) builder) => DragTarget<TaskDrag>(
      key: Key('week-drop-${days[i].day}'),
      onWillAcceptWithDetails: (d) => d.data.fromDay == null || !sameDay(d.data.fromDay!, days[i]),
      onAcceptWithDetails: (d) => ctrl.moveTaskToDay(d.data.id, days[i], fromDay: d.data.fromDay),
      builder: (context, candidates, _) => builder(candidates.isNotEmpty),
    );

    Widget header(int i) {
      final d = days[i];
      final isToday = sameDay(d, s.today);
      return InkWell(
        key: Key('week-day-${d.day}'),
        onTap: () => ctrl.openDay(d),
        child: Container(
          padding: const EdgeInsets.symmetric(
            vertical: Space.s4,
            horizontal: Space.s8,
          ),
          decoration: BoxDecoration(
            color: isToday ? c.accentSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '${weekdayShort(d.weekday)} ${d.day}',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: isToday ? c.accent : c.text,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }

    if (wide) {
      return Padding(
        padding: const EdgeInsets.all(Space.s8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: dropTarget(
                  i,
                  (hovering) => Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    padding: const EdgeInsets.all(Space.s4),
                    decoration: BoxDecoration(
                      color: hovering ? c.accentSoft : null,
                      border: Border.all(color: hovering ? c.accent : c.border, width: hovering ? 2 : 1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        header(i),
                        const SizedBox(height: Space.s4),
                        Expanded(child: SingleChildScrollView(child: dayBody(i, dense: true))),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }
    // phone: the days are stacked; the list scrolls by itself while a dragged task is held near an edge
    return DragScope(
      onMove: _auto.move,
      onEnd: _auto.end,
      child: ListView(
        key: _areaKey,
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(Space.s16, Space.s8, Space.s16, 96),
        children: [
          for (var i = 0; i < 7; i++)
            dropTarget(
              i,
              (hovering) => Container(
                margin: const EdgeInsets.only(bottom: Space.s4),
                decoration: BoxDecoration(
                  color: hovering ? c.accentSoft : null,
                  borderRadius: BorderRadius.circular(8),
                  border: hovering ? Border.all(color: c.accent, width: 2) : null,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    header(i),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(Space.s8, Space.s4, 0, Space.s12),
                      child: dayBody(i, dense: false),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ======================================================================= month
class MonthView extends ConsumerWidget {
  const MonthView({super.key, required this.state});
  final PlannerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = state;
    final c = context.colors;
    final first = DateTime(s.day.year, s.day.month, 1);
    final daysInMonth = DateTime(first.year, first.month + 1, 0).day;
    final weeks = ((first.weekday - 1) + daysInMonth + 6) ~/ 7;
    final gridStart = startOfWeek(first);
    final gridEnd = DateTime(
      gridStart.year,
      gridStart.month,
      gridStart.day + weeks * 7,
    );
    final counts = rangeCounts(gridStart, gridEnd, s.tasks, s.events);
    final ctrl = ref.read(plannerControllerProvider.notifier);
    final t = Theme.of(context).textTheme;

    return LayoutBuilder(builder: (context, outer) {
    // the tasks of the picked day (drag source) need room: only on screens tall enough
    final showPanel = outer.maxHeight >= 460;
    return Padding(
      padding: const EdgeInsets.all(Space.s8),
      child: Column(
        children: [
          Row(
            children: [
              for (var i = 1; i <= 7; i++)
                Expanded(
                  child: Center(
                    child: Text(weekdayShort(i), style: t.bodySmall),
                  ),
                ),
            ],
          ),
          const SizedBox(height: Space.s4),
          for (var w = 0; w < weeks; w++)
            Expanded(
              child: Row(
                children: [
                  for (var i = 0; i < 7; i++)
                    Expanded(
                      child: Builder(
                        builder: (context) {
                          final d = DateTime(
                            gridStart.year,
                            gridStart.month,
                            gridStart.day + w * 7 + i,
                          );
                          final inMonth = d.month == first.month;
                          final isToday = sameDay(d, s.today);
                          final isSel = sameDay(d, s.day);
                          final n = counts[d];
                          final cell = Semantics(
                            button: true,
                            label:
                                '${dayTitle(d)}${n == null ? ', nothing planned' : ', ${n.events} events, ${n.open} open tasks'}',
                            child: InkWell(
                              key: Key('month-${d.month}-${d.day}'),
                              onTap: () => ctrl.openDay(d),
                              child: Container(
                                margin: const EdgeInsets.all(1.5),
                                padding: const EdgeInsets.all(3),
                                decoration: BoxDecoration(
                                  color: isSel
                                      ? c.accentSoft
                                      : (inMonth
                                            ? c.surface
                                            : Colors.transparent),
                                  border: Border.all(
                                    color: isToday ? c.accent : c.border,
                                    width: isToday ? 2 : 1,
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: LayoutBuilder(
                                  builder: (context, box) {
                                    final number = Text(
                                      '${d.day}',
                                      style: t.bodySmall?.copyWith(
                                        color: inMonth ? c.text : c.textMuted,
                                        fontWeight: isToday
                                            ? FontWeight.w800
                                            : null,
                                      ),
                                    );
                                    if (box.maxHeight < 56) {
                                      // short cells (landscape phones): number and tiny dots on ONE line
                                      return Row(
                                        children: [
                                          number,
                                          const Spacer(),
                                          if (n != null && n.events > 0)
                                            _Dot(
                                              c.accent,
                                              key: Key(
                                                'month-ev-${d.month}-${d.day}',
                                              ),
                                            ),
                                          if (n != null && n.open > 0)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                left: 2,
                                              ),
                                              child: _Dot(
                                                c.brass,
                                                key: Key(
                                                  'month-task-${d.month}-${d.day}',
                                                ),
                                              ),
                                            ),
                                        ],
                                      );
                                    }
                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        number,
                                        const Spacer(),
                                        if (n != null)
                                          Wrap(
                                            spacing: 2,
                                            runSpacing: 2,
                                            children: [
                                              if (n.events > 0)
                                                _Pill(
                                                  '${n.events}',
                                                  c.accentSoft,
                                                  c.accent,
                                                  key: Key(
                                                    'month-ev-${d.month}-${d.day}',
                                                  ),
                                                ),
                                              if (n.open > 0)
                                                _Pill(
                                                  '${n.open}',
                                                  Color.alphaBlend(
                                                    c.brass.withValues(
                                                      alpha: .25,
                                                    ),
                                                    c.surface,
                                                  ),
                                                  c.text,
                                                  key: Key(
                                                    'month-task-${d.month}-${d.day}',
                                                  ),
                                                ),
                                              if (n.done > 0 && n.open == 0)
                                                _Pill(
                                                  '✓',
                                                  c.surface2,
                                                  c.textMuted,
                                                ),
                                            ],
                                          ),
                                      ],
                                    );
                                  },
                                ),
                              ),
                            ),
                          );
                          return DragTarget<TaskDrag>(
                            key: Key('month-drop-${d.month}-${d.day}'),
                            onWillAcceptWithDetails: (x) => x.data.fromDay == null || !sameDay(x.data.fromDay!, d),
                            onAcceptWithDetails: (x) => ctrl.moveTaskToDay(x.data.id, d, fromDay: x.data.fromDay),
                            builder: (context, candidates, _) => candidates.isEmpty
                                ? cell
                                : DecoratedBox(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: c.accent, width: 3),
                                    ),
                                    child: cell,
                                  ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          if (showPanel) _MonthDayPanel(state: s),
        ],
      ),
    );
    });
  }
}

/// The tasks of the day shown in the month view, to be dragged onto any day of the grid above.
class _MonthDayPanel extends ConsumerWidget {
  const _MonthDayPanel({required this.state});
  final PlannerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = state;
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final ctrl = ref.read(plannerControllerProvider.notifier);
    final tasks = dayAgenda(s.day, s.tasks, s.events, today: s.today).tasks;
    final open = tasks.where((x) => !x.done).length;
    return Container(
      key: const Key('month-panel'),
      margin: const EdgeInsets.only(top: Space.s8),
      padding: const EdgeInsets.all(Space.s8),
      decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border), borderRadius: BorderRadius.circular(8)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                key: const Key('month-panel-prev'),
                tooltip: 'Previous day',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.chevron_left),
                onPressed: () => ctrl.setDay(addDays(s.day, -1)),
              ),
              Expanded(
                child: Text(
                  '${dayTitle(s.day)} · ${tasks.isEmpty ? 'no tasks' : '$open open'}',
                  key: const Key('month-panel-title'),
                  style: t.titleSmall,
                  textAlign: TextAlign.center,
                ),
              ),
              IconButton(
                key: const Key('month-panel-next'),
                tooltip: 'Next day',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.chevron_right),
                onPressed: () => ctrl.setDay(addDays(s.day, 1)),
              ),
            ],
          ),
          if (tasks.isEmpty)
            Padding(
              padding: const EdgeInsets.all(Space.s8),
              child: Text('Nothing to move. Use the arrows to look at another day.', style: t.bodySmall),
            )
          else ...[
            Text(
              DraggableTask.isTouch ? 'Press and hold a task, then drop it on a day above.' : 'Drag a task onto a day above to move it.',
              style: t.bodySmall?.copyWith(color: c.textMuted),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 150),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final i in tasks)
                    DraggableTask(
                      item: i,
                      fromDay: s.day,
                      child: TaskTile(item: i, dense: true, onOpen: () => _open(context, s, i)),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot(this.color, {super.key});
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, this.bg, this.fg, {super.key});
  final String text;
  final Color bg, fg;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 11,
        height: 1.2,
        fontWeight: FontWeight.w700,
        color: fg,
      ),
    ),
  );
}

// ======================================================================== year
class YearView extends ConsumerWidget {
  const YearView({super.key, required this.state});
  final PlannerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = state;
    final c = context.colors;
    final year = s.day.year;
    final counts = rangeCounts(
      DateTime(year),
      DateTime(year + 1),
      s.tasks,
      s.events,
    );
    final ctrl = ref.read(plannerControllerProvider.notifier);
    final width = MediaQuery.sizeOf(context).width;
    final cols = width >= 900 ? 4 : (width >= 560 ? 3 : 2);

    Color heat(int n) => n == 0
        ? Colors.transparent
        : (n == 1
              ? c.accentSoft
              : (n <= 3
                    ? Color.alphaBlend(
                        c.accent.withValues(alpha: .45),
                        c.surface,
                      )
                    : c.accent));

    Widget mini(int month) {
      final first = DateTime(year, month, 1);
      final days = DateTime(year, month + 1, 0).day;
      final lead = first.weekday - 1;
      final rows = (lead + days + 6) ~/ 7;
      return InkWell(
        key: Key('year-month-$month'),
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          ctrl.setDay(first);
          ctrl.setMode(PlannerMode.month);
        },
        child: Container(
          padding: const EdgeInsets.all(Space.s8),
          decoration: BoxDecoration(
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(10),
            color: c.surface,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                monthLong(month),
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: Space.s4),
              for (var r = 0; r < rows; r++)
                Row(
                  children: [
                    for (var i = 0; i < 7; i++)
                      Expanded(
                        child: Builder(
                          builder: (context) {
                            final dayNum = r * 7 + i - lead + 1;
                            if (dayNum < 1 || dayNum > days) {
                              return const SizedBox(height: 14);
                            }
                            final d = DateTime(year, month, dayNum);
                            final n = counts[d]?.total ?? 0;
                            return Container(
                              height: 14,
                              margin: const EdgeInsets.all(1),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: heat(n),
                                borderRadius: BorderRadius.circular(3),
                                border: sameDay(d, s.today)
                                    ? Border.all(color: c.accent, width: 1.5)
                                    : null,
                              ),
                              child: Text(
                                '$dayNum',
                                style: TextStyle(
                                  fontSize: 8,
                                  height: 1,
                                  color: n >= 4 ? c.onAccent : c.textMuted,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      );
    }

    return GridView.count(
      padding: const EdgeInsets.all(Space.s12),
      crossAxisCount: cols,
      crossAxisSpacing: Space.s8,
      mainAxisSpacing: Space.s8,
      childAspectRatio: 1.15,
      children: [for (var m = 1; m <= 12; m++) mini(m)],
    );
  }
}
