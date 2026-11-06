import 'package:drift/drift.dart' show Variable;
import 'package:tracker_engine/tracker_engine.dart';

class _Unsupported implements Exception {}

class SqlPlan {
  SqlPlan(this.idsSql, this.countSql, this.idsVars, this.countVars);
  final String idsSql;
  final String countSql;
  final List<Variable<Object>> idsVars;
  final List<Variable<Object>> countVars;
}

/// Translates a view (filter + sorts) into SQL over `records` / `cells` / `record_links`.
///
/// Every leaf is written to mirror the branches of `matchCondition` in tracker_engine exactly
/// (including how empty cells behave), and each leaf evaluates to a definite 0/1, never NULL.
/// Whatever can't be mirrored exactly (computed properties, multi-select sorting, grouping,
/// free-text search) returns null so the caller uses the in-memory reference instead.
/// `test/features/tracker/query_differential_test.dart` checks the two paths agree.
SqlPlan? buildSqlPlan({
  required String trackerId,
  required List<PropertyDef> properties,
  required ViewConfig view,
  required DateTime now,
  int? limit,
  int offset = 0,
}) {
  try {
    return _Builder(trackerId, properties, view, now).build(limit, offset);
  } on _Unsupported {
    return null;
  }
}

class _Builder {
  _Builder(this.trackerId, this.props, this.view, this.now);
  final String trackerId;
  final List<PropertyDef> props;
  final ViewConfig view;
  final DateTime now;

  final _aliases = <String, String>{};
  final _joinVars = <Variable<Object>>[];
  final _whereVars = <Variable<Object>>[];
  final _orderVars = <Variable<Object>>[];
  var _n = 0;

  PropertyDef? _def(String id) {
    for (final p in props) {
      if (p.id == id) return p;
    }
    return null;
  }

  String _alias(PropertyDef d) => _aliases.putIfAbsent(d.id, () {
        _joinVars.add(Variable.withString(d.id));
        return 'c${_n++}';
      });

  SqlPlan build(int? limit, int offset) {
    final where = StringBuffer('r.tracker_id = ? AND r.deleted_at IS NULL');
    _whereVars.add(Variable.withString(trackerId));
    if (!view.showArchived) where.write(' AND r.archived_at IS NULL');
    final f = _group(view.filter);
    if (f != '1') where.write(' AND $f');

    final order = <String>[];
    for (final k in view.sorts) {
      final d = _def(k.propertyId);
      if (d == null) continue; // sort on a deleted property is ignored (as in the reference)
      final sv = <Variable<Object>>[];
      final e = _sortExpr(d, sv);
      if (e == null) continue; // types the reference never orders by
      order.add('($e IS NULL) ASC, $e ${k.descending ? 'DESC' : 'ASC'}');
      _orderVars..addAll(sv)..addAll(sv); // the expression appears twice in the text
    }
    order..add('r.sort_key ASC')..add('r.id ASC');

    final joins = [for (final e in _aliases.entries) 'LEFT JOIN cells ${e.value} ON ${e.value}.record_id = r.id AND ${e.value}.property_id = ?'].join(' ');
    final base = 'FROM records r $joins WHERE $where';
    final ids = 'SELECT r.id $base ORDER BY ${order.join(', ')}${limit != null ? ' LIMIT ? OFFSET ?' : ''}';
    final count = 'SELECT count(*) AS n $base';
    final countVars = [..._joinVars, ..._whereVars];
    final idsVars = [...countVars, ..._orderVars, if (limit != null) Variable.withInt(limit), if (limit != null) Variable.withInt(offset)];
    return SqlPlan(ids, count, idsVars, countVars);
  }

  // ----------------------------------------------------------------- filters
  String _group(FilterGroup g) {
    if (g.children.isEmpty) return '1';
    final parts = [for (final c in g.children) _node(c)];
    return '(${parts.join(g.and ? ' AND ' : ' OR ')})';
  }

  String _node(FilterNode n) => switch (n) {
        FilterGroup g => _group(g),
        FilterCondition c => _leaf(c),
      };

  String _w(Object v, [List<Variable<Object>>? into]) {
    // helper: add a where-parameter and return its placeholder
    (into ?? _whereVars).add(v is String ? Variable.withString(v) : v is int ? Variable.withInt(v) : Variable.withReal((v as num).toDouble()));
    return '?';
  }

  String _leaf(FilterCondition c) {
    final d = _def(c.propertyId);
    if (d == null) return '1'; // filter on a deleted property never hides data
    final t = d.type;
    final op = c.op;
    if (t == PropertyType.relation) return _relation(d, c);
    if (!t.isStored) throw _Unsupported();

    final a = _alias(d);
    final absent = '$a.record_id IS NULL';
    if (op == FilterOp.isEmpty) return '($absent)';
    if (op == FilterOp.isNotEmpty) return '(NOT ($absent))';
    if (op == FilterOp.isChecked) return t == PropertyType.checkbox ? '(COALESCE($a.v_int = 1, 0))' : throw _Unsupported();
    if (op == FilterOp.isUnchecked) return t == PropertyType.checkbox ? '($absent OR $a.v_int <> 1)' : throw _Unsupported();
    final v = c.value;

    if (t.isTextLike) {
      if (v != null && v is! String) return (op == FilterOp.notContains || op == FilterOp.neq) ? '1' : '0';
      final f = foldText((v ?? '') as String);
      switch (op) {
        case FilterOp.contains:
          return f.isEmpty ? '(NOT ($absent))' : '(COALESCE(instr($a.v_sort, ${_w(f)}) > 0, 0))';
        case FilterOp.notContains:
          return f.isEmpty ? '($absent)' : '($absent OR instr($a.v_sort, ${_w(f)}) = 0)';
        case FilterOp.eq:
          return '(COALESCE($a.v_sort = ${_w(f)}, 0))';
        case FilterOp.neq:
          return '($absent OR $a.v_sort <> ${_w(f)})';
        case FilterOp.startsWith:
          if (f.isEmpty) return '(NOT ($absent))';
          return '(COALESCE(substr($a.v_sort, 1, ${_w(f.runes.length)}) = ${_w(f)}, 0))';
        case FilterOp.endsWith:
          if (f.isEmpty) return '(NOT ($absent))';
          return '(COALESCE(length($a.v_sort) >= ${_w(f.runes.length)} AND substr($a.v_sort, -${f.runes.length}) = ${_w(f)}, 0))';
        default:
          throw _Unsupported();
      }
    }

    if (const {PropertyType.number, PropertyType.currency, PropertyType.percent, PropertyType.progress}.contains(t)) {
      final o = v is num ? v.toDouble() : null;
      if (op == FilterOp.neq) return o == null ? '1' : '($absent OR $a.v_num IS NULL OR $a.v_num <> ${_w(o)})';
      const sql = {FilterOp.eq: '=', FilterOp.gt: '>', FilterOp.gte: '>=', FilterOp.lt: '<', FilterOp.lte: '<='};
      final s = sql[op];
      if (s == null) throw _Unsupported();
      return o == null ? '0' : '(COALESCE($a.v_num $s ${_w(o)}, 0))';
    }

    if (t == PropertyType.date || t == PropertyType.dateRange) {
      final today = dayNumber(DateTime.utc(now.year, now.month, now.day).millisecondsSinceEpoch);
      final missing = op == FilterOp.neq ? '1' : '0';
      String guarded(String inner) => '(CASE WHEN $a.v_day IS NULL THEN $missing ELSE $inner END)';
      if (op == FilterOp.inLastDays || op == FilterOp.inNextDays) {
        final n = v is num ? v.toInt() : 0;
        return op == FilterOp.inLastDays
            ? guarded('($a.v_day >= ${_w(today - n)} AND $a.v_day <= ${_w(today)})')
            : guarded('($a.v_day >= ${_w(today)} AND $a.v_day <= ${_w(today + n)})');
      }
      const sql = {FilterOp.eq: '=', FilterOp.neq: '<>', FilterOp.before: '<', FilterOp.after: '>', FilterOp.onOrBefore: '<=', FilterOp.onOrAfter: '>='};
      final s = sql[op];
      if (s == null) throw _Unsupported();
      final od = v is String ? parseDate(v) : null;
      if (od == null) return guarded('0');
      return guarded('($a.v_day $s ${_w(dayNumber(od.millisecondsSinceEpoch))})');
    }

    if (t == PropertyType.select || t == PropertyType.status) {
      switch (op) {
        case FilterOp.eq:
          return v is String ? '(COALESCE($a.v_text = ${_w(v)}, 0))' : '0';
        case FilterOp.neq:
          return v is String ? '($absent OR $a.v_text <> ${_w(v)})' : '1';
        case FilterOp.isAnyOf:
          if (v is! List) return '0';
          final l = v.whereType<String>().toList();
          return l.isEmpty ? '0' : '(COALESCE($a.v_text IN (${l.map(_w).join(',')}), 0))';
        case FilterOp.isNoneOf:
          if (v is! List) return '1';
          final l = v.whereType<String>().toList();
          return l.isEmpty ? '1' : '($absent OR $a.v_text NOT IN (${l.map(_w).join(',')}))';
        default:
          throw _Unsupported();
      }
    }

    if (t == PropertyType.multiSelect || t == PropertyType.person || t == PropertyType.files || t == PropertyType.image) {
      final want = (v is List ? v : (v == null ? const [] : [v])).whereType<String>().toList();
      final any = want.isEmpty ? '0' : 'COALESCE(EXISTS (SELECT 1 FROM json_each($a.raw) j WHERE j.value IN (${want.map(_w).join(',')})), 0)';
      if (op == FilterOp.hasAny) return '($any)';
      if (op == FilterOp.hasNone) return '(NOT ($any))';
      throw _Unsupported();
    }
    throw _Unsupported();
  }

  String _relation(PropertyDef d, FilterCondition c) {
    String exists([List<String> ids = const []]) {
      _whereVars.add(Variable.withString(d.id));
      final inList = ids.isEmpty ? '' : ' AND l.to_record_id IN (${ids.map(_w).join(',')})';
      return 'EXISTS (SELECT 1 FROM record_links l WHERE l.relation_property_id = ? AND l.from_record_id = r.id AND l.deleted_at IS NULL$inList)';
    }

    switch (c.op) {
      case FilterOp.isEmpty:
        return '(NOT ${exists()})';
      case FilterOp.isNotEmpty:
        return '(${exists()})';
      case FilterOp.hasAny:
      case FilterOp.hasNone:
        final v = c.value;
        final want = (v is List ? v : (v == null ? const [] : [v])).whereType<String>().toList();
        if (want.isEmpty) return c.op == FilterOp.hasAny ? '0' : '1';
        return c.op == FilterOp.hasAny ? '(${exists(want)})' : '(NOT ${exists(want)})';
      default:
        throw _Unsupported();
    }
  }

  // ------------------------------------------------------------------- sorts
  String? _sortExpr(PropertyDef d, List<Variable<Object>> vars) {
    final t = d.type;
    switch (t) {
      case PropertyType.text:
      case PropertyType.richText:
      case PropertyType.url:
      case PropertyType.email:
      case PropertyType.phone:
        return '${_alias(d)}.v_sort';
      case PropertyType.number:
      case PropertyType.currency:
      case PropertyType.percent:
      case PropertyType.progress:
      case PropertyType.date:
      case PropertyType.dateRange:
        return '${_alias(d)}.v_num';
      case PropertyType.checkbox:
        return '${_alias(d)}.v_int';
      case PropertyType.select:
      case PropertyType.status:
        // Rank comes from the CURRENT option order, so reordering options never needs a rewrite.
        final a = _alias(d);
        final opts = d.options;
        final b = StringBuffer('(CASE WHEN $a.record_id IS NULL THEN NULL');
        for (var i = 0; i < opts.length; i++) {
          vars.add(Variable.withString(opts[i].id));
          b.write(' WHEN $a.v_text = ? THEN $i');
        }
        b.write(' ELSE ${opts.length} END)');
        return b.toString();
      case PropertyType.person:
      case PropertyType.files:
      case PropertyType.image:
      case PropertyType.relation:
        return null; // the reference gives these no order
      case PropertyType.multiSelect:
      case PropertyType.formula:
      case PropertyType.rollup:
      case PropertyType.createdTime:
      case PropertyType.lastEditedTime:
        throw _Unsupported();
    }
  }
}
