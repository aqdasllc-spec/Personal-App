import 'property.dart';

enum ViewLayout { table, kanban, calendar, timeline, gantt, gallery, list }

enum FilterOp {
  // text-like
  contains, notContains, startsWith, endsWith,
  // any
  eq, neq, isEmpty, isNotEmpty,
  // numbers & dates (dates compare by UTC day)
  gt, gte, lt, lte,
  before, after, onOrBefore, onOrAfter, inLastDays, inNextDays,
  // options
  isAnyOf, isNoneOf,
  // multi-valued (multi-select, person, relation, files)
  hasAny, hasNone,
  // checkbox
  isChecked, isUnchecked;

  static FilterOp parse(String s) => FilterOp.values.firstWhere((o) => o.name == s, orElse: () => throw FormatException('Unknown filter operator', s));
}

/// Operators the UI offers for a property type (and the only ones the engine accepts).
List<FilterOp> opsFor(PropertyType t) {
  switch (t) {
    case PropertyType.text:
    case PropertyType.richText:
    case PropertyType.url:
    case PropertyType.email:
    case PropertyType.phone:
      return const [FilterOp.contains, FilterOp.notContains, FilterOp.eq, FilterOp.neq, FilterOp.startsWith, FilterOp.endsWith, FilterOp.isEmpty, FilterOp.isNotEmpty];
    case PropertyType.number:
    case PropertyType.currency:
    case PropertyType.percent:
    case PropertyType.progress:
      return const [FilterOp.eq, FilterOp.neq, FilterOp.gt, FilterOp.gte, FilterOp.lt, FilterOp.lte, FilterOp.isEmpty, FilterOp.isNotEmpty];
    case PropertyType.checkbox:
      return const [FilterOp.isChecked, FilterOp.isUnchecked];
    case PropertyType.date:
    case PropertyType.dateRange:
    case PropertyType.createdTime:
    case PropertyType.lastEditedTime:
      return const [FilterOp.eq, FilterOp.before, FilterOp.after, FilterOp.onOrBefore, FilterOp.onOrAfter, FilterOp.inLastDays, FilterOp.inNextDays, FilterOp.isEmpty, FilterOp.isNotEmpty];
    case PropertyType.select:
    case PropertyType.status:
      return const [FilterOp.eq, FilterOp.neq, FilterOp.isAnyOf, FilterOp.isNoneOf, FilterOp.isEmpty, FilterOp.isNotEmpty];
    case PropertyType.multiSelect:
    case PropertyType.person:
    case PropertyType.files:
    case PropertyType.image:
    case PropertyType.relation:
      return const [FilterOp.hasAny, FilterOp.hasNone, FilterOp.isEmpty, FilterOp.isNotEmpty];
    case PropertyType.formula:
    case PropertyType.rollup:
      return const [FilterOp.eq, FilterOp.neq, FilterOp.gt, FilterOp.gte, FilterOp.lt, FilterOp.lte, FilterOp.contains, FilterOp.isEmpty, FilterOp.isNotEmpty];
  }
}

sealed class FilterNode {
  Map<String, Object?> toJson();
  static FilterNode fromJson(Map<String, Object?> j) {
    if (j.containsKey('children')) {
      return FilterGroup(
        and: (j['op'] ?? 'and') != 'or',
        children: [for (final c in (j['children'] as List)) FilterNode.fromJson(Map<String, Object?>.from(c as Map))],
      );
    }
    return FilterCondition(propertyId: j['property']! as String, op: FilterOp.parse(j['op']! as String), value: j['value']);
  }
}

class FilterCondition extends FilterNode {
  FilterCondition({required this.propertyId, required this.op, this.value});
  final String propertyId;
  final FilterOp op;

  /// Operand: string, number or list of strings depending on the operator; null for isEmpty, isChecked, etc.
  final Object? value;
  @override
  Map<String, Object?> toJson() => {'property': propertyId, 'op': op.name, if (value != null) 'value': value};
}

class FilterGroup extends FilterNode {
  FilterGroup({this.and = true, this.children = const []});
  final bool and;
  final List<FilterNode> children;
  bool get isEmpty => children.isEmpty;
  @override
  Map<String, Object?> toJson() => {'op': and ? 'and' : 'or', 'children': [for (final c in children) c.toJson()]};
}

class SortKey {
  const SortKey(this.propertyId, {this.descending = false});
  final String propertyId;
  final bool descending;
  Map<String, Object?> toJson() => {'property': propertyId, if (descending) 'desc': true};
}

class GroupBy {
  const GroupBy(this.propertyId, {this.descending = false, this.hideEmpty = false});
  final String propertyId;
  final bool descending;
  final bool hideEmpty;
  Map<String, Object?> toJson() => {'property': propertyId, if (descending) 'desc': true, if (hideEmpty) 'hideEmpty': true};
}

/// A saved view is only a query + presentation settings; it owns no records, so creating,
/// editing or deleting views can never duplicate or fragment data.
class ViewConfig {
  ViewConfig({
    this.layout = ViewLayout.table,
    FilterGroup? filter,
    this.sorts = const [],
    this.groupBy,
    this.visibleProperties,
    this.widths = const {},
    this.frozenColumns = 1,
    this.compact = false,
    this.showArchived = false,
    this.layoutOptions = const {},
  }) : filter = filter ?? FilterGroup();

  static const version = 1;
  final ViewLayout layout;
  final FilterGroup filter;
  final List<SortKey> sorts;
  final GroupBy? groupBy;

  /// Ordered property ids; null = all properties in definition order.
  final List<String>? visibleProperties;
  final Map<String, double> widths;
  final int frozenColumns;
  final bool compact;
  final bool showArchived;

  /// Layout specific: kanban {groupPropertyId, cardProperties}, calendar {datePropertyId},
  /// timeline/gantt {startPropertyId, endPropertyId, dependencyPropertyId}, gallery {coverPropertyId}.
  final Map<String, Object?> layoutOptions;

  ViewConfig copyWith({
    ViewLayout? layout,
    FilterGroup? filter,
    List<SortKey>? sorts,
    GroupBy? groupBy,
    bool clearGroup = false,
    List<String>? visibleProperties,
    Map<String, double>? widths,
    int? frozenColumns,
    bool? compact,
    bool? showArchived,
    Map<String, Object?>? layoutOptions,
  }) =>
      ViewConfig(
        layout: layout ?? this.layout,
        filter: filter ?? this.filter,
        sorts: sorts ?? this.sorts,
        groupBy: clearGroup ? null : (groupBy ?? this.groupBy),
        visibleProperties: visibleProperties ?? this.visibleProperties,
        widths: widths ?? this.widths,
        frozenColumns: frozenColumns ?? this.frozenColumns,
        compact: compact ?? this.compact,
        showArchived: showArchived ?? this.showArchived,
        layoutOptions: layoutOptions ?? this.layoutOptions,
      );

  Map<String, Object?> toJson() => {
        'v': version,
        'layout': layout.name,
        'filter': filter.toJson(),
        if (sorts.isNotEmpty) 'sorts': [for (final s in sorts) s.toJson()],
        if (groupBy != null) 'group': groupBy!.toJson(),
        if (visibleProperties != null) 'visible': visibleProperties,
        if (widths.isNotEmpty) 'widths': widths,
        if (frozenColumns != 1) 'frozen': frozenColumns,
        if (compact) 'compact': true,
        if (showArchived) 'showArchived': true,
        if (layoutOptions.isNotEmpty) 'layoutOptions': layoutOptions,
      };

  /// Tolerant: unknown layouts/keys from newer app versions fall back to safe defaults.
  factory ViewConfig.fromJson(Map<String, Object?> j) {
    ViewLayout layout = ViewLayout.table;
    final l = j['layout'];
    if (l is String) {
      layout = ViewLayout.values.firstWhere((e) => e.name == l, orElse: () => ViewLayout.table);
    }
    FilterGroup filter = FilterGroup();
    try {
      if (j['filter'] is Map) {
        final f = FilterNode.fromJson(Map<String, Object?>.from(j['filter']! as Map));
        filter = f is FilterGroup ? f : FilterGroup(children: [f]);
      }
    } catch (_) {/* unknown operator from a newer version: show unfiltered rather than crash */}
    final g = j['group'];
    return ViewConfig(
      layout: layout,
      filter: filter,
      sorts: [
        for (final s in (j['sorts'] as List?) ?? const [])
          SortKey((s as Map)['property']! as String, descending: s['desc'] == true)
      ],
      groupBy: g is Map ? GroupBy(g['property']! as String, descending: g['desc'] == true, hideEmpty: g['hideEmpty'] == true) : null,
      visibleProperties: (j['visible'] as List?)?.cast<String>(),
      widths: {for (final e in ((j['widths'] as Map?) ?? const {}).entries) e.key as String: (e.value as num).toDouble()},
      frozenColumns: (j['frozen'] as int?) ?? 1,
      compact: j['compact'] == true,
      showArchived: j['showArchived'] == true,
      layoutOptions: Map<String, Object?>.from((j['layoutOptions'] as Map?) ?? const {}),
    );
  }
}
