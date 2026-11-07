import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/tokens.dart';
import '../application/planner_controller.dart';
import '../data/planner_repository.dart';
import '../domain/agenda.dart';
import '../domain/models.dart';
import '../domain/recurrence.dart';
import 'format.dart';

Future<void> openTaskEditor(
  BuildContext context, {
  PlannerTask? task,
  DateTime? day,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => TaskEditorPage(task: task, day: day),
  ),
);

Future<void> openEventEditor(
  BuildContext context, {
  PlannerEvent? event,
  DateTime? day,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => EventEditorPage(event: event, day: day),
  ),
);

/// Editable form of a repeat rule.
class RepeatSpec {
  RepeatSpec({
    this.freq,
    this.interval = 1,
    Set<int>? weekdays,
    this.endKind = 0,
    this.count = 10,
    DateTime? until,
  }) : weekdays = weekdays ?? {},
       until = until ?? DateTime.now().add(const Duration(days: 90));

  Freq? freq; // null = does not repeat
  int interval;
  Set<int> weekdays;

  /// 0 = never, 1 = after [count] times, 2 = on [until]
  int endKind;
  int count;
  DateTime until;

  factory RepeatSpec.fromRule(String rule) {
    final r = Recurrence.parse(rule);
    if (r == null) return RepeatSpec();
    return RepeatSpec(
      freq: r.freq,
      interval: r.interval,
      weekdays: {...r.byWeekday},
      endKind: r.count != null ? 1 : (r.until != null ? 2 : 0),
      count: r.count ?? 10,
      until: r.until,
    );
  }

  String toRule() => freq == null
      ? ''
      : Recurrence(
          freq: freq!,
          interval: interval,
          byWeekday: freq == Freq.weekly ? weekdays : const {},
          count: endKind == 1 ? count : null,
          until: endKind == 2 ? dateOnly(until) : null,
        ).toRule();
}

class _RepeatEditor extends StatefulWidget {
  const _RepeatEditor({required this.spec, required this.onChanged});
  final RepeatSpec spec;
  final VoidCallback onChanged;
  @override
  State<_RepeatEditor> createState() => _RepeatEditorState();
}

class _RepeatEditorState extends State<_RepeatEditor> {
  RepeatSpec get s => widget.spec;
  void _change(VoidCallback f) {
    setState(f);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final unit = switch (s.freq) {
      Freq.daily => 'day',
      Freq.weekly => 'week',
      Freq.monthly => 'month',
      Freq.yearly => 'year',
      null => '',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<Freq?>(
          key: const Key('repeat-freq'),
          isExpanded: true,
          initialValue: s.freq,
          decoration: const InputDecoration(labelText: 'Repeat'),
          items: const [
            DropdownMenuItem(value: null, child: Text('Does not repeat')),
            DropdownMenuItem(value: Freq.daily, child: Text('Daily')),
            DropdownMenuItem(value: Freq.weekly, child: Text('Weekly')),
            DropdownMenuItem(value: Freq.monthly, child: Text('Monthly')),
            DropdownMenuItem(value: Freq.yearly, child: Text('Yearly')),
          ],
          onChanged: (f) => _change(() => s.freq = f),
        ),
        if (s.freq != null) ...[
          const SizedBox(height: Space.s8),
          Row(
            children: [
              Text(
                'Every ${s.interval == 1 ? unit : '${s.interval} ${unit}s'}',
              ),
              const Spacer(),
              IconButton(
                key: const Key('interval-less'),
                tooltip: 'Less often',
                onPressed: s.interval > 1
                    ? () => _change(() => s.interval--)
                    : null,
                icon: const Icon(Icons.remove),
              ),
              IconButton(
                key: const Key('interval-more'),
                tooltip: 'More often',
                onPressed: s.interval < 99
                    ? () => _change(() => s.interval++)
                    : null,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          if (s.freq == Freq.weekly)
            Wrap(
              spacing: Space.s4,
              children: [
                for (var d = 1; d <= 7; d++)
                  FilterChip(
                    key: Key('weekday-$d'),
                    label: Text(weekdayShort(d)),
                    selected: s.weekdays.contains(d),
                    onSelected: (on) => _change(
                      () => on ? s.weekdays.add(d) : s.weekdays.remove(d),
                    ),
                  ),
              ],
            ),
          const SizedBox(height: Space.s8),
          DropdownButtonFormField<int>(
            key: const Key('repeat-end'),
            isExpanded: true,
            initialValue: s.endKind,
            decoration: const InputDecoration(labelText: 'Ends'),
            items: const [
              DropdownMenuItem(value: 0, child: Text('Never')),
              DropdownMenuItem(
                value: 1,
                child: Text('After a number of times'),
              ),
              DropdownMenuItem(value: 2, child: Text('On a date')),
            ],
            onChanged: (v) => _change(() => s.endKind = v ?? 0),
          ),
          if (s.endKind == 1)
            Row(
              children: [
                Text('${s.count} times'),
                const Spacer(),
                IconButton(
                  tooltip: 'Fewer',
                  onPressed: s.count > 1
                      ? () => _change(() => s.count--)
                      : null,
                  icon: const Icon(Icons.remove),
                ),
                IconButton(
                  tooltip: 'More',
                  onPressed: s.count < 999
                      ? () => _change(() => s.count++)
                      : null,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          if (s.endKind == 2)
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.event, size: 18),
                label: Text('Until ${dateLabel(s.until)}'),
                onPressed: () async {
                  final p = await showDatePicker(
                    context: context,
                    initialDate: s.until,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2200),
                  );
                  if (p != null) _change(() => s.until = p);
                },
              ),
            ),
        ],
      ],
    );
  }
}

class _DateTimeRow extends StatelessWidget {
  const _DateTimeRow({
    required this.label,
    required this.date,
    required this.time,
    required this.onDate,
    this.onTime,
    this.keyPrefix = '',
  });
  final String label;
  final DateTime date;
  final TimeOfDay? time;
  final ValueChanged<DateTime> onDate;
  final ValueChanged<TimeOfDay>? onTime;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: Space.s8,
    runSpacing: Space.s4,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      SizedBox(
        width: 64,
        child: Text(label, style: Theme.of(context).textTheme.bodySmall),
      ),
      OutlinedButton.icon(
        key: Key('$keyPrefix-date'),
        icon: const Icon(Icons.event, size: 18),
        label: Text(dateLabel(date)),
        onPressed: () async {
          final p = await showDatePicker(
            context: context,
            initialDate: date,
            firstDate: DateTime(2000),
            lastDate: DateTime(2200),
          );
          if (p != null) onDate(p);
        },
      ),
      if (time != null && onTime != null)
        OutlinedButton.icon(
          key: Key('$keyPrefix-time'),
          icon: const Icon(Icons.schedule, size: 18),
          label: Text('${two(time!.hour)}:${two(time!.minute)}'),
          onPressed: () async {
            final p = await showTimePicker(
              context: context,
              initialTime: time!,
              builder: (c, w) => MediaQuery(
                data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true),
                child: w!,
              ),
            );
            if (p != null) onTime!(p);
          },
        ),
    ],
  );
}

DateTime _combine(DateTime d, TimeOfDay t) =>
    DateTime(d.year, d.month, d.day, t.hour, t.minute);

class _ReminderField extends StatelessWidget {
  const _ReminderField({
    required this.value,
    required this.onChanged,
    this.allDayNote = false,
  });
  final int? value;
  final ValueChanged<int?> onChanged;
  final bool allDayNote;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      DropdownButtonFormField<int?>(
        key: const Key('reminder'),
        isExpanded: true,
        initialValue: reminderChoices.contains(value) ? value : null,
        decoration: const InputDecoration(labelText: 'Reminder'),
        items: [
          for (final m in reminderChoices)
            DropdownMenuItem(value: m, child: Text(reminderLabel(m))),
        ],
        onChanged: onChanged,
      ),
      if (allDayNote && value != null)
        Padding(
          padding: const EdgeInsets.only(top: Space.s4),
          child: Text(
            'Items without a time remind you at 09:00.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
    ],
  );
}

// ===================================================================== task editor
class TaskEditorPage extends ConsumerStatefulWidget {
  const TaskEditorPage({super.key, this.task, this.day});
  final PlannerTask? task;
  final DateTime? day;
  @override
  ConsumerState<TaskEditorPage> createState() => _TaskEditorPageState();
}

class _TaskEditorPageState extends ConsumerState<TaskEditorPage> {
  late final _title = TextEditingController(text: widget.task?.title ?? '');
  late final _notes = TextEditingController(text: widget.task?.notes ?? '');
  late Priority _priority = widget.task?.priority ?? Priority.none;
  late bool _hasDue =
      widget.task?.due != null || (widget.task == null && widget.day != null);
  late DateTime _due = widget.task?.due != null
      ? dateOnly(widget.task!.due!)
      : dateOnly(widget.day ?? DateTime.now());
  late bool _dueTime = widget.task?.dueHasTime ?? false;
  late TimeOfDay _dueTod = widget.task?.due != null && widget.task!.dueHasTime
      ? TimeOfDay.fromDateTime(widget.task!.due!)
      : const TimeOfDay(hour: 9, minute: 0);
  late bool _hasBlock = widget.task?.planned != null;
  late DateTime _blockDate = widget.task?.planned != null
      ? dateOnly(widget.task!.planned!)
      : dateOnly(widget.day ?? DateTime.now());
  late TimeOfDay _blockTod = widget.task?.planned != null
      ? TimeOfDay.fromDateTime(widget.task!.planned!)
      : const TimeOfDay(hour: 9, minute: 0);
  late int _blockMinutes = widget.task?.plannedMinutes ?? 60;
  late final RepeatSpec _repeat = RepeatSpec.fromRule(widget.task?.rrule ?? '');
  late int? _remind = widget.task?.remindMinutes;
  late List<ChecklistItem> _items = [...?widget.task?.checklist];
  final _newItem = TextEditingController();
  // one controller per sub-task so each title can be edited in place
  final _itemControllers = <String, TextEditingController>{};
  bool _busy = false;

  bool get _editing => widget.task != null;

  TextEditingController _controllerFor(ChecklistItem i) => _itemControllers.putIfAbsent(i.id, () => TextEditingController(text: i.title));

  void _addItem() {
    final text = _newItem.text.trim();
    if (text.isEmpty) return;
    if (_items.length >= maxChecklistItems) return;
    setState(() {
      _items = [..._items, ChecklistItem(id: const Uuid().v4(), title: text)];
      _newItem.clear();
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    _newItem.dispose();
    for (final c in _itemControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TaskInput _input() => TaskInput(
    title: _title.text,
    notes: _notes.text,
    priority: _priority,
    due: _hasDue ? (_dueTime ? _combine(_due, _dueTod) : _due) : null,
    dueHasTime: _hasDue && _dueTime,
    planned: _hasBlock ? _combine(_blockDate, _blockTod) : null,
    plannedMinutes: _hasBlock ? _blockMinutes : null,
    rrule: _repeat.toRule(),
    remindMinutes: _remind,
    checklist: [
      // an item typed but not yet added with + still counts
      for (final i in _items) i.copyWith(title: _controllerFor(i).text),
      if (_newItem.text.trim().isNotEmpty) ChecklistItem(id: const Uuid().v4(), title: _newItem.text.trim()),
    ],
  );

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await ref
        .read(plannerControllerProvider.notifier)
        .saveTask(_input(), id: widget.task?.id);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(
        () => _busy = false,
      ); // the planner shows why (snackbar); nothing the user typed is lost
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Edit task' : 'New task'),
        actions: [
          if (_editing)
            IconButton(
              key: const Key('delete'),
              tooltip: 'Delete task',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final nav = Navigator.of(context);
                await ref
                    .read(plannerControllerProvider.notifier)
                    .deleteTask(widget.task!.id);
                nav.pop();
              },
            ),
          TextButton(
            key: const Key('save'),
            onPressed: _busy ? null : _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(Space.s16),
        children: [
          TextField(
            key: const Key('title'),
            controller: _title,
            autofocus: !_editing,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          const SizedBox(height: Space.s12),
          TextField(
            key: const Key('notes'),
            controller: _notes,
            minLines: 2,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: 'Notes',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: Space.s16),
          Text('Priority', style: t.bodySmall),
          const SizedBox(height: Space.s4),
          Wrap(
            key: const Key('priority'),
            spacing: Space.s8,
            children: [
              for (final p in Priority.values)
                ChoiceChip(
                  key: Key('priority-${p.name}'),
                  label: Text(p.label),
                  selected: _priority == p,
                  onSelected: (_) => setState(() => _priority = p),
                ),
            ],
          ),
          const SizedBox(height: Space.s16),
          Text('Sub-tasks', style: t.bodySmall),
          // Sub-tasks can be dragged into any order by their handle (screen readers get "move up / down" actions).
          ReorderableListView.builder(
            key: const Key('subtask-list'),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: _items.length,
            onReorderItem: (from, to) => setState(() {
              final list = [..._items];
              list.insert(to, list.removeAt(from));
              _items = list;
            }),
            itemBuilder: (context, index) {
              final i = _items[index];
              return Row(
                key: Key('item-${i.id}'),
                children: [
                  ReorderableDragStartListener(
                    index: index,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Space.s8, vertical: Space.s8),
                      child: Icon(Icons.drag_indicator, key: Key('item-handle-${i.id}'), size: 20, semanticLabel: 'Drag to reorder'),
                    ),
                  ),
                  Checkbox(
                    key: Key('item-done-${i.id}'),
                    value: i.done,
                    onChanged: (v) => setState(() => _items = [for (final x in _items) x.id == i.id ? x.copyWith(done: v ?? false) : x]),
                  ),
                  Expanded(
                    child: TextField(
                      key: Key('item-title-${i.id}'),
                      controller: _controllerFor(i),
                      decoration: const InputDecoration(isDense: true, border: InputBorder.none),
                      style: i.done ? const TextStyle(decoration: TextDecoration.lineThrough) : null,
                    ),
                  ),
                  IconButton(
                    key: Key('item-delete-${i.id}'),
                    tooltip: 'Remove sub-task',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() {
                      _items = [for (final x in _items) if (x.id != i.id) x];
                      _itemControllers.remove(i.id)?.dispose();
                    }),
                  ),
                ],
              );
            },
          ),
          TextField(
            key: const Key('new-subtask'),
            controller: _newItem,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _addItem(),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Add a sub-task',
              prefixIcon: const Icon(Icons.add),
              suffixIcon: IconButton(key: const Key('add-subtask'), tooltip: 'Add sub-task', icon: const Icon(Icons.keyboard_return), onPressed: _addItem),
            ),
          ),
          const Divider(height: Space.s32),
          SwitchListTile(
            key: const Key('has-due'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Due date'),
            value: _hasDue,
            onChanged: (v) => setState(() => _hasDue = v),
          ),
          if (_hasDue) ...[
            _DateTimeRow(
              label: 'Due',
              keyPrefix: 'due',
              date: _due,
              time: _dueTime ? _dueTod : null,
              onDate: (d) => setState(() => _due = d),
              onTime: (x) => setState(() => _dueTod = x),
            ),
            SwitchListTile(
              key: const Key('due-has-time'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Specific time'),
              value: _dueTime,
              onChanged: (v) => setState(() => _dueTime = v),
            ),
          ],
          SwitchListTile(
            key: const Key('has-block'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Plan a time block'),
            subtitle: const Text('Reserve time on a day to work on it'),
            value: _hasBlock,
            onChanged: (v) => setState(() => _hasBlock = v),
          ),
          if (_hasBlock) ...[
            _DateTimeRow(
              label: 'Work on',
              keyPrefix: 'block',
              date: _blockDate,
              time: _blockTod,
              onDate: (d) => setState(() => _blockDate = d),
              onTime: (x) => setState(() => _blockTod = x),
            ),
            const SizedBox(height: Space.s8),
            DropdownButtonFormField<int>(
              key: const Key('block-minutes'),
              isExpanded: true,
              initialValue:
                  const [
                    15,
                    30,
                    45,
                    60,
                    90,
                    120,
                    180,
                    240,
                  ].contains(_blockMinutes)
                  ? _blockMinutes
                  : 60,
              decoration: const InputDecoration(labelText: 'Length'),
              items: [
                for (final m in const [15, 30, 45, 60, 90, 120, 180, 240])
                  DropdownMenuItem(value: m, child: Text(durationLabel(m))),
              ],
              onChanged: (v) => setState(() => _blockMinutes = v ?? 60),
            ),
          ],
          const Divider(height: Space.s32),
          _RepeatEditor(spec: _repeat, onChanged: () => setState(() {})),
          if (_repeat.freq != null)
            Padding(
              padding: const EdgeInsets.only(top: Space.s4),
              child: Text(
                'Completing it moves it to the next time (${Recurrence.parse(_repeat.toRule())?.describe() ?? ''}).',
                style: t.bodySmall,
              ),
            ),
          const SizedBox(height: Space.s16),
          _ReminderField(
            value: _remind,
            onChanged: (v) => setState(() => _remind = v),
            allDayNote: !(_dueTime && _hasDue) && !_hasBlock,
          ),
        ],
      ),
    );
  }
}

// ==================================================================== event editor
class EventEditorPage extends ConsumerStatefulWidget {
  const EventEditorPage({super.key, this.event, this.day});
  final PlannerEvent? event;
  final DateTime? day;
  @override
  ConsumerState<EventEditorPage> createState() => _EventEditorPageState();
}

class _EventEditorPageState extends ConsumerState<EventEditorPage> {
  late final _title = TextEditingController(text: widget.event?.title ?? '');
  late final _notes = TextEditingController(text: widget.event?.notes ?? '');
  late bool _allDay = widget.event?.allDay ?? false;
  late DateTime _startDate = dateOnly(
    widget.event?.start ?? widget.day ?? DateTime.now(),
  );
  late TimeOfDay _startTod = widget.event != null && !widget.event!.allDay
      ? TimeOfDay.fromDateTime(widget.event!.start)
      : const TimeOfDay(hour: 9, minute: 0);
  // for all-day events the form shows the LAST day (inclusive); storage uses the exclusive next midnight
  late DateTime _endDate = widget.event == null
      ? dateOnly(widget.day ?? DateTime.now())
      : (widget.event!.allDay
            ? dateOnly(widget.event!.end).subtract(const Duration(days: 1))
            : dateOnly(widget.event!.end));
  late TimeOfDay _endTod = widget.event != null && !widget.event!.allDay
      ? TimeOfDay.fromDateTime(widget.event!.end)
      : const TimeOfDay(hour: 10, minute: 0);
  late final RepeatSpec _repeat = RepeatSpec.fromRule(
    widget.event?.rrule ?? '',
  );
  late int? _remind = widget.event?.remindMinutes;
  bool _busy = false;

  bool get _editing => widget.event != null;

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  EventInput _input() {
    final start = _allDay ? _startDate : _combine(_startDate, _startTod);
    final end = _allDay
        ? DateTime(_endDate.year, _endDate.month, _endDate.day + 1)
        : _combine(_endDate, _endTod);
    return EventInput(
      title: _title.text,
      notes: _notes.text,
      start: start,
      end: end,
      allDay: _allDay,
      rrule: _repeat.toRule(),
      remindMinutes: _remind,
    );
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await ref
        .read(plannerControllerProvider.notifier)
        .saveEvent(_input(), id: widget.event?.id);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Edit event' : 'New event'),
        actions: [
          if (_editing)
            IconButton(
              key: const Key('delete'),
              tooltip: 'Delete event',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final nav = Navigator.of(context);
                await ref
                    .read(plannerControllerProvider.notifier)
                    .deleteEvent(widget.event!.id);
                nav.pop();
              },
            ),
          TextButton(
            key: const Key('save'),
            onPressed: _busy ? null : _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(Space.s16),
        children: [
          TextField(
            key: const Key('title'),
            controller: _title,
            autofocus: !_editing,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          const SizedBox(height: Space.s12),
          TextField(
            key: const Key('notes'),
            controller: _notes,
            minLines: 2,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: 'Notes',
              alignLabelWithHint: true,
            ),
          ),
          SwitchListTile(
            key: const Key('all-day'),
            contentPadding: EdgeInsets.zero,
            title: const Text('All day'),
            value: _allDay,
            onChanged: (v) => setState(() => _allDay = v),
          ),
          _DateTimeRow(
            label: 'Starts',
            keyPrefix: 'start',
            date: _startDate,
            time: _allDay ? null : _startTod,
            onDate: (d) => setState(() {
              _startDate = d;
              if (_endDate.isBefore(d)) _endDate = d;
            }),
            onTime: (x) => setState(() => _startTod = x),
          ),
          const SizedBox(height: Space.s8),
          _DateTimeRow(
            label: 'Ends',
            keyPrefix: 'end',
            date: _endDate,
            time: _allDay ? null : _endTod,
            onDate: (d) => setState(() => _endDate = d),
            onTime: (x) => setState(() => _endTod = x),
          ),
          const Divider(height: Space.s32),
          _RepeatEditor(spec: _repeat, onChanged: () => setState(() {})),
          const SizedBox(height: Space.s16),
          _ReminderField(
            value: _remind,
            onChanged: (v) => setState(() => _remind = v),
            allDayNote: _allDay,
          ),
        ],
      ),
    );
  }
}
