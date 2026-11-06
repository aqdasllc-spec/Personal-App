import 'package:tracker_engine/tracker_engine.dart';

const statusOpts = [
  SelectOption(id: 'todo', label: 'Not started', group: StatusGroup.todo),
  SelectOption(id: 'doing', label: 'In progress', color: 'blue', group: StatusGroup.inProgress),
  SelectOption(id: 'done', label: 'Done', color: 'green', group: StatusGroup.complete),
];

/// Tasks tracker (child of Projects via relation `project`).
final taskProps = <PropertyDef>[
  const PropertyDef(id: 'name', name: 'Name', type: PropertyType.text),
  PropertyDef(id: 'status', name: 'Status', type: PropertyType.status, config: Cfg.options(statusOpts)),
  const PropertyDef(id: 'hours', name: 'Hours', type: PropertyType.number, config: {'decimals': 1}),
  const PropertyDef(id: 'due', name: 'Due', type: PropertyType.date),
  PropertyDef(id: 'tags', name: 'Tags', type: PropertyType.multiSelect, config: Cfg.options(const [
    SelectOption(id: 't1', label: 'Urgent', color: 'red'),
    SelectOption(id: 't2', label: 'Home'),
    SelectOption(id: 't3', label: 'Work'),
  ])),
  const PropertyDef(id: 'done', name: 'Done?', type: PropertyType.checkbox),
  const PropertyDef(id: 'daysLeft', name: 'Days left', type: PropertyType.formula, config: {'formula': 'dateBetween(prop("due"), today(), "days")'}),
];

TrackerRecord task(String id, String name, {String? status, num? hours, String? due, List<String>? tags, bool? done, bool archived = false, String key = ''}) => TrackerRecord(
      id: id,
      trackerId: 'tasks',
      sortKey: key.isEmpty ? id : key,
      archived: archived,
      cells: {'name': name, 'status': status, 'hours': hours, 'due': due, 'tags': tags, 'done': done}..removeWhere((_, v) => v == null),
    );

final now = DateTime.utc(2026, 11, 6, 9);

List<TrackerRecord> sampleTasks() => [
      task('t1', 'Write intro', status: 'doing', hours: 3.5, due: '2026-11-08', tags: ['t3'], done: false),
      task('t2', 'Éclair recipe', status: 'todo', hours: 1, due: '2026-11-06', tags: ['t2', 't1']),
      task('t3', 'File taxes', status: 'done', hours: 2, due: '2026-10-30', tags: ['t1'], done: true),
      task('t4', 'Plan trip', status: 'doing', due: '2026-12-01'),
      task('t5', 'Call dentist'),
      task('t6', 'old stuff', status: 'done', hours: 9, archived: true),
    ];

TrackerSnapshot tasksSnapshot([List<TrackerRecord>? records]) => TrackerSnapshot(trackerId: 'tasks', properties: taskProps, records: records ?? sampleTasks());

List<String> ids(QueryResult r) => [for (final x in r.records) x.id];
