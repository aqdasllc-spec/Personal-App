import 'computed.dart';
import 'formula.dart';
import 'property.dart';
import 'records.dart';
import 'values.dart';
import 'view_config.dart';

class RecordGroup {
  RecordGroup(this.key, this.label, this.records);

  /// Option id / day / folded text; null for the "No value" group.
  final String? key;
  final String label;
  final List<TrackerRecord> records;
}

class QueryResult {
  QueryResult(this.records, this.groups);

  /// Matching records in view order (also the concatenation of [groups] when grouped).
  final List<TrackerRecord> records;
  final List<RecordGroup>? groups;
}

DateTime _day(DateTime d) => DateTime.utc(d.year, d.month, d.day);

/// Does [cell] (the property value) satisfy [op]/[operand]? Shared semantic definition: the SQL
/// translation must agree with this function (differential-tested in the app).
bool matchCondition(PropertyDef def, Value cell, FilterOp op, Object? operand, DateTime now) {
  final empty = Values.isEmpty(cell);
  switch (op) {
    case FilterOp.isEmpty:
      return empty;
    case FilterOp.isNotEmpty:
      return !empty;
    case FilterOp.isChecked:
      return cell == true;
    case FilterOp.isUnchecked:
      return cell != true;
    default:
  }
  if (cell is FormulaError) return false;
  final t = def.type;

  // ---- text-like (and formula/rollup strings)
  if (cell is String && (t.isTextLike || t == PropertyType.formula || t == PropertyType.rollup) && operand is String? && !_isDateish(t)) {
    final a = foldText(cell), b = foldText((operand ?? '').toString());
    switch (op) {
      case FilterOp.contains:
        return a.contains(b);
      case FilterOp.notContains:
        return !a.contains(b);
      case FilterOp.eq:
        return a == b;
      case FilterOp.neq:
        return a != b;
      case FilterOp.startsWith:
        return a.startsWith(b);
      case FilterOp.endsWith:
        return a.endsWith(b);
      default:
        return false;
    }
  }
  if (t.isTextLike) {
    // empty text cell
    return switch (op) {
      FilterOp.notContains => true,
      FilterOp.neq => true,
      _ => false,
    };
  }

  // ---- numbers
  if (const {PropertyType.number, PropertyType.currency, PropertyType.percent, PropertyType.progress}.contains(t) || (cell is num && !_isDateish(t))) {
    final n = cell is num ? cell.toDouble() : null;
    final o = operand is num ? operand.toDouble() : null;
    if (op == FilterOp.neq) return n == null || o == null || n != o;
    if (n == null || o == null) return false;
    return switch (op) {
      FilterOp.eq => n == o,
      FilterOp.gt => n > o,
      FilterOp.gte => n >= o,
      FilterOp.lt => n < o,
      FilterOp.lte => n <= o,
      _ => false,
    };
  }

  // ---- dates (by UTC day)
  if (_isDateish(t) || (t == PropertyType.formula || t == PropertyType.rollup) && cell is String && parseDate(cell) != null) {
    DateTime? d;
    if (cell is Map) {
      d = parseDate(cell['start'] as String);
    } else if (cell is String) {
      d = parseDate(cell);
    }
    if (d == null) return op == FilterOp.neq;
    final day = _day(d);
    final today = _day(now);
    if (op == FilterOp.inLastDays || op == FilterOp.inNextDays) {
      final n = operand is num ? operand.toInt() : 0;
      return op == FilterOp.inLastDays
          ? !day.isBefore(today.subtract(Duration(days: n))) && !day.isAfter(today)
          : !day.isBefore(today) && !day.isAfter(today.add(Duration(days: n)));
    }
    final o = operand is String ? parseDate(operand) : null;
    if (o == null) return false;
    final od = _day(o);
    return switch (op) {
      FilterOp.eq => day == od,
      FilterOp.neq => day != od,
      FilterOp.before => day.isBefore(od),
      FilterOp.after => day.isAfter(od),
      FilterOp.onOrBefore => !day.isAfter(od),
      FilterOp.onOrAfter => !day.isBefore(od),
      _ => false,
    };
  }

  // ---- options (single)
  if (t == PropertyType.select || t == PropertyType.status) {
    final id = cell as String?;
    return switch (op) {
      FilterOp.eq => id != null && id == operand,
      FilterOp.neq => id == null || id != operand,
      FilterOp.isAnyOf => id != null && operand is List && operand.contains(id),
      FilterOp.isNoneOf => id == null || operand is! List || !operand.contains(id),
      _ => false,
    };
  }

  // ---- multi-valued
  final list = cell is List ? cell : const [];
  final want = operand is List ? operand : (operand == null ? const [] : [operand]);
  switch (op) {
    case FilterOp.hasAny:
      return list.any(want.contains);
    case FilterOp.hasNone:
      return !list.any(want.contains);
    default:
      return false;
  }
}

bool _isDateish(PropertyType t) => t == PropertyType.date || t == PropertyType.dateRange || t == PropertyType.createdTime || t == PropertyType.lastEditedTime;

bool matchFilter(FilterNode node, TrackerRecord r, TrackerSnapshot s, Computed c, DateTime now) {
  switch (node) {
    case FilterCondition cond:
      final def = s.property(cond.propertyId);
      if (def == null) return true; // filter on a deleted property is ignored, never hides data
      return matchCondition(def, c.valueOf(r, def), cond.op, cond.value, now);
    case FilterGroup g:
      if (g.children.isEmpty) return true;
      return g.and ? g.children.every((x) => matchFilter(x, r, s, c, now)) : g.children.any((x) => matchFilter(x, r, s, c, now));
  }
}

/// Comparable representation for sorting; null sorts last in both directions.
Object? sortValue(PropertyDef def, Value v) {
  if (v == null || v is FormulaError) return null;
  switch (def.type) {
    case PropertyType.text:
    case PropertyType.richText:
    case PropertyType.url:
    case PropertyType.email:
    case PropertyType.phone:
      return v is String && v.isNotEmpty ? foldText(v) : null;
    case PropertyType.number:
    case PropertyType.currency:
    case PropertyType.percent:
    case PropertyType.progress:
      return v is num ? v.toDouble() : null;
    case PropertyType.checkbox:
      return v == true ? 1.0 : 0.0;
    case PropertyType.date:
    case PropertyType.createdTime:
    case PropertyType.lastEditedTime:
      return v is String ? parseDate(v)?.millisecondsSinceEpoch.toDouble() : null;
    case PropertyType.dateRange:
      return v is Map ? parseDate(v['start'] as String)?.millisecondsSinceEpoch.toDouble() : null;
    case PropertyType.select:
    case PropertyType.status:
      final o = def.options;
      final i = o.indexWhere((x) => x.id == v);
      return (i < 0 ? o.length : i).toDouble();
    case PropertyType.multiSelect:
      return v is List && v.isNotEmpty ? v.map((id) => foldText(def.option(id as String)?.label ?? id)).join(' ') : null;
    case PropertyType.formula:
    case PropertyType.rollup:
      if (v is num) return v.toDouble();
      if (v is String) return foldText(v);
      if (v is bool) return v ? 1.0 : 0.0;
      return null;
    default:
      return null;
  }
}

int _cmp(Object? a, Object? b) {
  if (a is num && b is num) return a.compareTo(b);
  if (a is String && b is String) return a.compareTo(b);
  // mixed (e.g. a formula yielding text for some rows, numbers for others): numbers first
  if (a is num) return -1;
  if (b is num) return 1;
  return 0;
}

/// Reference query: filter -> sort -> group. Archived records are hidden unless the view shows them.
QueryResult runQuery(TrackerSnapshot s, ViewConfig view, {DateTime? now, String search = ''}) {
  final t = (now ?? DateTime.now()).toUtc();
  final c = Computed(s, now: t);
  final q = foldText(search.trim());

  var rows = <TrackerRecord>[
    for (final r in s.records)
      if ((view.showArchived || !r.archived) && matchFilter(view.filter, r, s, c, t) && (q.isEmpty || _matchesSearch(r, s, c, q))) r
  ];

  final sorts = [for (final k in view.sorts) if (s.property(k.propertyId) != null) k];
  rows.sort((x, y) {
    for (final k in sorts) {
      final d = s.property(k.propertyId)!;
      final a = sortValue(d, c.valueOf(x, d)), b = sortValue(d, c.valueOf(y, d));
      if (a == null && b == null) continue;
      if (a == null) return 1; // nulls last, regardless of direction
      if (b == null) return -1;
      final r = _cmp(a, b);
      if (r != 0) return k.descending ? -r : r;
    }
    final byKey = x.sortKey.compareTo(y.sortKey);
    return byKey != 0 ? byKey : x.id.compareTo(y.id);
  });

  final g = view.groupBy;
  final gdef = g == null ? null : s.property(g.propertyId);
  if (g == null || gdef == null) return QueryResult(rows, null);

  final buckets = <String?, List<TrackerRecord>>{};
  final labels = <String?, String>{};
  for (final r in rows) {
    final key = groupKey(gdef, c.valueOf(r, gdef));
    buckets.putIfAbsent(key, () => []).add(r);
    labels[key] ??= key == null ? 'No value' : groupLabel(gdef, key);
  }
  final keys = buckets.keys.where((k) => k != null).cast<String>().toList();
  if (gdef.type.isOptionBased) {
    final order = [for (final o in gdef.options) o.id];
    // declared options first (even if empty, so Kanban columns persist), then orphans
    for (final id in order) {
      if (!keys.contains(id) && !g.hideEmpty) {
        keys.add(id);
        buckets[id] = [];
        labels[id] = groupLabel(gdef, id);
      }
    }
    keys.sort((a, b) {
      final i = order.indexOf(a), j = order.indexOf(b);
      return (i < 0 ? order.length : i).compareTo(j < 0 ? order.length : j);
    });
  } else {
    keys.sort();
  }
  if (g.descending) {
    final reversed = keys.reversed.toList();
    keys
      ..clear()
      ..addAll(reversed);
  }
  final groups = [for (final k in keys) RecordGroup(k, labels[k] ?? k, buckets[k]!)];
  if (buckets[null] != null && !g.hideEmpty) groups.add(RecordGroup(null, 'No value', buckets[null]!));
  return QueryResult([for (final x in groups) ...x.records], groups);
}

/// Groupable value -> stable key. Null = empty.
String? groupKey(PropertyDef def, Value v) {
  if (Values.isEmpty(v) || v is FormulaError) return null;
  switch (def.type) {
    case PropertyType.select:
    case PropertyType.status:
      return v as String;
    case PropertyType.checkbox:
      return v == true ? 'checked' : 'unchecked';
    case PropertyType.date:
    case PropertyType.createdTime:
    case PropertyType.lastEditedTime:
      final d = parseDate(v as String);
      return d == null ? null : _day(d).toIso8601String().substring(0, 10);
    case PropertyType.number:
    case PropertyType.currency:
    case PropertyType.percent:
    case PropertyType.progress:
      return (v as num).toString();
    default:
      return foldText(v.toString());
  }
}

String groupLabel(PropertyDef def, String key) {
  switch (def.type) {
    case PropertyType.select:
    case PropertyType.status:
      return def.option(key)?.label ?? '(removed)';
    case PropertyType.checkbox:
      return key == 'checked' ? 'Checked' : 'Unchecked';
    default:
      return key;
  }
}

bool _matchesSearch(TrackerRecord r, TrackerSnapshot s, Computed c, String foldedQuery) {
  for (final d in s.properties) {
    final v = c.valueOf(r, d);
    if (Values.isEmpty(v) || v is FormulaError) continue;
    if (foldText(Values.format(d, v)).contains(foldedQuery)) return true;
  }
  return false;
}
