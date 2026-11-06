import 'formula.dart';
import 'property.dart';
import 'view_config.dart';

/// Templates are DATA (docs/03 §2.4): applying one creates ordinary trackers/properties/views with
/// fresh ids. Keys below are template-local, globally unique inside one template; relation targets,
/// rollups, formulas and views refer to keys and are rewritten to the new ids on instantiation.
class TemplateProperty {
  const TemplateProperty(this.key, this.name, this.type, [this.config = const {}]);
  final String key;
  final String name;
  final PropertyType type;
  final Map<String, Object?> config;
}

class TemplateView {
  const TemplateView(this.name, this.config);
  final String name;
  final ViewConfig config;
}

class TemplateTracker {
  const TemplateTracker({required this.key, required this.name, required this.icon, this.color = 'teal', required this.properties, required this.views});
  final String key;
  final String name;
  final String icon;
  final String color;
  final List<TemplateProperty> properties;
  final List<TemplateView> views;
}

class TrackerTemplate {
  const TrackerTemplate({required this.id, required this.name, required this.description, required this.trackers});
  final String id;
  final String name;
  final String description;
  final List<TemplateTracker> trackers;
}

class NewView {
  NewView(this.id, this.name, this.config);
  final String id;
  final String name;
  final ViewConfig config;
}

class NewTracker {
  NewTracker({required this.id, required this.name, required this.icon, required this.color, required this.properties, required this.views});
  final String id;
  final String name;
  final String icon;
  final String color;
  final List<PropertyDef> properties;
  final List<NewView> views;
}

const _propIdKeys = {'groupPropertyId', 'datePropertyId', 'startPropertyId', 'endPropertyId', 'dependencyPropertyId', 'coverPropertyId'};

/// Rewrites every property id inside a view config through [m] (unknown ids are kept as-is).
ViewConfig remapViewConfig(ViewConfig v, String Function(String) m) {
  FilterNode mapNode(FilterNode n) => switch (n) {
        FilterCondition c => FilterCondition(propertyId: m(c.propertyId), op: c.op, value: c.value),
        FilterGroup g => FilterGroup(and: g.and, children: [for (final x in g.children) mapNode(x)]),
      };
  final opts = <String, Object?>{
    for (final e in v.layoutOptions.entries)
      e.key: _propIdKeys.contains(e.key) && e.value is String
          ? m(e.value! as String)
          : (e.key == 'cardProperties' && e.value is List ? [for (final x in e.value! as List) m(x as String)] : e.value)
  };
  return ViewConfig(
    layout: v.layout,
    filter: mapNode(v.filter) as FilterGroup,
    sorts: [for (final s in v.sorts) SortKey(m(s.propertyId), descending: s.descending)],
    groupBy: v.groupBy == null ? null : GroupBy(m(v.groupBy!.propertyId), descending: v.groupBy!.descending, hideEmpty: v.groupBy!.hideEmpty),
    visibleProperties: v.visibleProperties == null ? null : [for (final p in v.visibleProperties!) m(p)],
    widths: {for (final e in v.widths.entries) m(e.key): e.value},
    frozenColumns: v.frozenColumns,
    compact: v.compact,
    showArchived: v.showArchived,
    layoutOptions: opts,
  );
}

/// Creates new trackers from [t]. [newId] must return a unique id each call.
List<NewTracker> instantiateTemplate(TrackerTemplate t, String Function() newId) {
  final trackerIds = {for (final tr in t.trackers) tr.key: newId()};
  final propIds = {for (final tr in t.trackers) for (final p in tr.properties) p.key: newId()};
  String mapProp(String k) => propIds[k] ?? k;

  return [
    for (final tr in t.trackers)
      NewTracker(
        id: trackerIds[tr.key]!,
        name: tr.name,
        icon: tr.icon,
        color: tr.color,
        properties: [
          for (final p in tr.properties)
            PropertyDef(id: propIds[p.key]!, name: p.name, type: p.type, config: _remapConfig(p, trackerIds, mapProp))
        ],
        views: [for (final v in tr.views) NewView(newId(), v.name, remapViewConfig(v.config, mapProp))],
      ),
  ];
}

Map<String, Object?> _remapConfig(TemplateProperty p, Map<String, String> trackerIds, String Function(String) mapProp) {
  final c = Map<String, Object?>.of(p.config);
  switch (p.type) {
    case PropertyType.relation:
      c['targetTrackerId'] = trackerIds[c['targetTrackerId']] ?? c['targetTrackerId'];
      if (c['pairPropertyId'] is String) c['pairPropertyId'] = mapProp(c['pairPropertyId']! as String);
    case PropertyType.rollup:
      if (c['relationPropertyId'] is String) c['relationPropertyId'] = mapProp(c['relationPropertyId']! as String);
      if (c['targetPropertyId'] is String) c['targetPropertyId'] = mapProp(c['targetPropertyId']! as String);
    case PropertyType.formula:
      c['formula'] = remapFormulaRefs((c['formula'] as String?) ?? '', mapProp);
    default:
  }
  return c;
}

// ---------------------------------------------------------------- built-ins
const _statusOptions = [
  SelectOption(id: 'todo', label: 'Not started', color: 'gray', group: StatusGroup.todo),
  SelectOption(id: 'doing', label: 'In progress', color: 'blue', group: StatusGroup.inProgress),
  SelectOption(id: 'blocked', label: 'Blocked', color: 'orange', group: StatusGroup.inProgress),
  SelectOption(id: 'done', label: 'Done', color: 'green', group: StatusGroup.complete),
];

Map<String, Object?> _opts(List<SelectOption> o) => Cfg.options(o);

ViewConfig _table([List<SortKey> sorts = const [], GroupBy? group]) => ViewConfig(sorts: sorts, groupBy: group);
ViewConfig _kanban(String statusKey) =>
    ViewConfig(layout: ViewLayout.kanban, groupBy: GroupBy(statusKey), layoutOptions: {'groupPropertyId': statusKey});
ViewConfig _calendar(String dateKey) => ViewConfig(layout: ViewLayout.calendar, layoutOptions: {'datePropertyId': dateKey});

final TrackerTemplate blankTemplate = TrackerTemplate(
  id: 'blank',
  name: 'Blank tracker',
  description: 'Start from scratch: one Name column, add whatever you need.',
  trackers: [
    TemplateTracker(
      key: 't',
      name: 'Untitled tracker',
      icon: 'table',
      properties: const [TemplateProperty('t.name', 'Name', PropertyType.text, {'isTitle': true})],
      views: [TemplateView('Table', _table())],
    ),
  ],
);

final TrackerTemplate goalsProjectsTasks = TrackerTemplate(
  id: 'goals_projects_tasks',
  name: 'Goals · Projects · Tasks',
  description: 'Three linked trackers. Progress rolls up from tasks to projects to goals. Edit or delete anything.',
  trackers: [
    TemplateTracker(
      key: 'goals',
      name: 'Goals',
      icon: 'target',
      properties: [
        const TemplateProperty('goal.name', 'Goal', PropertyType.text, {'isTitle': true}),
        TemplateProperty('goal.status', 'Status', PropertyType.status, _opts(_statusOptions)),
        TemplateProperty('goal.horizon', 'Horizon', PropertyType.select, _opts(const [
          SelectOption(id: 'long', label: 'Long-term', color: 'purple'),
          SelectOption(id: 'annual', label: 'Annual', color: 'blue'),
          SelectOption(id: 'monthly', label: 'Monthly', color: 'teal'),
          SelectOption(id: 'weekly', label: 'Weekly', color: 'green'),
        ])),
        const TemplateProperty('goal.due', 'Target date', PropertyType.date),
        const TemplateProperty('goal.projects', 'Projects', PropertyType.relation, {'targetTrackerId': 'projects', 'many': true, 'pairPropertyId': 'project.goal'}),
        const TemplateProperty('goal.progress', 'Progress', PropertyType.rollup, {'relationPropertyId': 'goal.projects', 'targetPropertyId': 'project.progress', 'aggregate': 'avg'}),
        const TemplateProperty('goal.notes', 'Notes', PropertyType.richText),
      ],
      views: [TemplateView('All goals', _table()), TemplateView('Board', _kanban('goal.status')), TemplateView('By horizon', _table(const [], const GroupBy('goal.horizon')))],
    ),
    TemplateTracker(
      key: 'projects',
      name: 'Projects',
      icon: 'folder',
      color: 'blue',
      properties: [
        const TemplateProperty('project.name', 'Project', PropertyType.text, {'isTitle': true}),
        TemplateProperty('project.status', 'Status', PropertyType.status, _opts(_statusOptions)),
        const TemplateProperty('project.start', 'Start', PropertyType.date),
        const TemplateProperty('project.due', 'Due', PropertyType.date),
        const TemplateProperty('project.goal', 'Goal', PropertyType.relation, {'targetTrackerId': 'goals', 'many': false, 'pairPropertyId': 'goal.projects'}),
        const TemplateProperty('project.tasks', 'Tasks', PropertyType.relation, {'targetTrackerId': 'tasks', 'many': true, 'pairPropertyId': 'task.project'}),
        const TemplateProperty('project.progress', 'Progress', PropertyType.rollup, {'relationPropertyId': 'project.tasks', 'targetPropertyId': 'task.status', 'aggregate': 'percentComplete'}),
      ],
      views: [
        TemplateView('All projects', _table()),
        TemplateView('Board', _kanban('project.status')),
        TemplateView('Timeline', ViewConfig(layout: ViewLayout.timeline, layoutOptions: {'startPropertyId': 'project.start', 'endPropertyId': 'project.due'})),
        TemplateView('Gantt', ViewConfig(layout: ViewLayout.gantt, layoutOptions: {'startPropertyId': 'project.start', 'endPropertyId': 'project.due'})),
      ],
    ),
    TemplateTracker(
      key: 'tasks',
      name: 'Tasks',
      icon: 'check',
      color: 'green',
      properties: [
        const TemplateProperty('task.name', 'Task', PropertyType.text, {'isTitle': true}),
        TemplateProperty('task.status', 'Status', PropertyType.status, _opts(_statusOptions)),
        TemplateProperty('task.priority', 'Priority', PropertyType.select, _opts(const [
          SelectOption(id: 'high', label: 'High', color: 'red'),
          SelectOption(id: 'med', label: 'Medium', color: 'yellow'),
          SelectOption(id: 'low', label: 'Low', color: 'gray'),
        ])),
        const TemplateProperty('task.due', 'Due', PropertyType.date),
        const TemplateProperty('task.project', 'Project', PropertyType.relation, {'targetTrackerId': 'projects', 'many': false, 'pairPropertyId': 'project.tasks'}),
        const TemplateProperty('task.milestone', 'Milestone', PropertyType.checkbox),
        const TemplateProperty('task.hours', 'Estimate (h)', PropertyType.number, {'decimals': 1}),
        const TemplateProperty('task.daysLeft', 'Days left', PropertyType.formula, {'formula': 'if(isEmpty(prop("task.due")), "", dateBetween(prop("task.due"), today(), "days"))'}),
      ],
      views: [
        TemplateView('All tasks', _table([const SortKey('task.due')])),
        TemplateView('Board', _kanban('task.status')),
        TemplateView('Calendar', _calendar('task.due')),
        TemplateView('Milestones', ViewConfig(filter: FilterGroup(children: [FilterCondition(propertyId: 'task.milestone', op: FilterOp.isChecked)]))),
      ],
    ),
  ],
);

final TrackerTemplate readingLog = TrackerTemplate(
  id: 'reading_log',
  name: 'Reading log',
  description: 'Track books you want to read, are reading, and have finished.',
  trackers: [
    TemplateTracker(
      key: 'books',
      name: 'Reading log',
      icon: 'book',
      color: 'brown',
      properties: [
        const TemplateProperty('b.title', 'Title', PropertyType.text, {'isTitle': true}),
        const TemplateProperty('b.author', 'Author', PropertyType.text),
        TemplateProperty('b.status', 'Status', PropertyType.status, _opts(const [
          SelectOption(id: 'want', label: 'Want to read', group: StatusGroup.todo),
          SelectOption(id: 'reading', label: 'Reading', color: 'blue', group: StatusGroup.inProgress),
          SelectOption(id: 'finished', label: 'Finished', color: 'green', group: StatusGroup.complete),
        ])),
        const TemplateProperty('b.pages', 'Pages', PropertyType.number),
        const TemplateProperty('b.progress', 'Progress', PropertyType.progress),
        TemplateProperty('b.rating', 'Rating', PropertyType.select, _opts(const [
          SelectOption(id: '1', label: '★'), SelectOption(id: '2', label: '★★'), SelectOption(id: '3', label: '★★★'),
          SelectOption(id: '4', label: '★★★★'), SelectOption(id: '5', label: '★★★★★'),
        ])),
        const TemplateProperty('b.started', 'Started', PropertyType.date),
        const TemplateProperty('b.finished', 'Finished', PropertyType.date),
        TemplateProperty('b.genre', 'Genre', PropertyType.multiSelect, _opts(const [SelectOption(id: 'fic', label: 'Fiction'), SelectOption(id: 'non', label: 'Non-fiction'), SelectOption(id: 'ref', label: 'Reference')])),
        const TemplateProperty('b.link', 'Link', PropertyType.url),
      ],
      views: [TemplateView('All books', _table()), TemplateView('Shelf', _kanban('b.status')), TemplateView('Gallery', ViewConfig(layout: ViewLayout.gallery))],
    ),
  ],
);

final TrackerTemplate habitTracker = TrackerTemplate(
  id: 'habits',
  name: 'Habit tracker',
  description: 'Daily habits with a streak counter.',
  trackers: [
    TemplateTracker(
      key: 'habits',
      name: 'Habits',
      icon: 'repeat',
      color: 'green',
      properties: [
        const TemplateProperty('h.name', 'Habit', PropertyType.text, {'isTitle': true}),
        TemplateProperty('h.freq', 'Frequency', PropertyType.select, _opts(const [SelectOption(id: 'daily', label: 'Daily', color: 'green'), SelectOption(id: 'weekly', label: 'Weekly', color: 'blue')])),
        const TemplateProperty('h.today', 'Done today', PropertyType.checkbox),
        const TemplateProperty('h.streak', 'Streak', PropertyType.number),
        const TemplateProperty('h.last', 'Last done', PropertyType.date),
        const TemplateProperty('h.since', 'Days since', PropertyType.formula, {'formula': 'if(isEmpty(prop("h.last")), "", dateBetween(today(), prop("h.last"), "days"))'}),
      ],
      views: [TemplateView('Habits', _table()), TemplateView('List', ViewConfig(layout: ViewLayout.list))],
    ),
  ],
);

final TrackerTemplate financeTracker = TrackerTemplate(
  id: 'finance',
  name: 'Budget',
  description: 'Income and expenses by category.',
  trackers: [
    TemplateTracker(
      key: 'tx',
      name: 'Transactions',
      icon: 'wallet',
      color: 'yellow',
      properties: [
        const TemplateProperty('x.item', 'Item', PropertyType.text, {'isTitle': true}),
        const TemplateProperty('x.amount', 'Amount', PropertyType.currency),
        TemplateProperty('x.type', 'Type', PropertyType.select, _opts(const [SelectOption(id: 'in', label: 'Income', color: 'green'), SelectOption(id: 'out', label: 'Expense', color: 'red')])),
        TemplateProperty('x.cat', 'Category', PropertyType.select, _opts(const [
          SelectOption(id: 'home', label: 'Home', color: 'blue'), SelectOption(id: 'food', label: 'Food', color: 'orange'),
          SelectOption(id: 'travel', label: 'Travel', color: 'purple'), SelectOption(id: 'other', label: 'Other'),
        ])),
        const TemplateProperty('x.date', 'Date', PropertyType.date),
        const TemplateProperty('x.paid', 'Paid', PropertyType.checkbox),
      ],
      views: [
        TemplateView('All', _table([const SortKey('x.date', descending: true)])),
        TemplateView('By category', _table(const [], const GroupBy('x.cat'))),
        TemplateView('Calendar', _calendar('x.date')),
      ],
    ),
  ],
);

final List<TrackerTemplate> builtInTemplates = [blankTemplate, goalsProjectsTasks, readingLog, habitTracker, financeTracker];
