import 'dart:math' as math;

import 'formula.dart';
import 'property.dart';
import 'records.dart';
import 'values.dart';

/// Computes formula / rollup / created / last-edited values on demand, memoised per instance.
/// Computed values are never stored or synced: every device derives them from synced inputs.
class Computed {
  Computed(this.snapshot, {DateTime? now, this.depth = 0}) : now = now ?? DateTime.now().toUtc();

  final TrackerSnapshot snapshot;
  final DateTime now;
  final int depth; // guards against relation/rollup loops across trackers
  static const maxDepth = 6;
  final _memo = <String, CellValue>{};
  final _inProgress = <String>{};

  /// CellValue of [def] for [r] in display/storage form (strings, numbers, bools, lists, [FormulaError]).
  CellValue valueOf(TrackerRecord r, PropertyDef def) {
    switch (def.type) {
      case PropertyType.createdTime:
        return r.createdAt.toUtc().toIso8601String();
      case PropertyType.lastEditedTime:
        return r.updatedAt.toUtc().toIso8601String();
      case PropertyType.relation:
        final ids = snapshot.links[def.id]?[r.id];
        return ids == null || ids.isEmpty ? null : List<String>.of(ids);
      case PropertyType.formula:
        final key = '${r.id}/${def.id}';
        if (_memo.containsKey(key)) return _memo[key];
        if (!_inProgress.add(key)) return const FormulaError('#REF', 'Circular reference');
        try {
          Object? res;
          try {
            res = evaluateFormula(def.formulaSource, _Ctx(this, r));
          } on _Propagate catch (p) {
            res = p.error;
          }
          return _memo[key] = _toStorageForm(res);
        } finally {
          _inProgress.remove(key);
        }
      case PropertyType.rollup:
        final key = '${r.id}/${def.id}';
        if (_memo.containsKey(key)) return _memo[key];
        return _memo[key] = _rollup(r, def);
      default:
        return r.cells[def.id];
    }
  }

  CellValue _rollup(TrackerRecord r, PropertyDef def) {
    if (depth >= maxDepth) return const FormulaError('#LIMIT', 'Rollups nested too deeply');
    final relId = def.rollupRelationId;
    final rel = relId == null ? null : snapshot.property(relId);
    if (rel == null || rel.type != PropertyType.relation) return const FormulaError('#REF', 'Rollup needs a relation');
    final targetTracker = rel.relationTargetTrackerId;
    final target = targetTracker == null ? null : (targetTracker == snapshot.trackerId ? snapshot : snapshot.others[targetTracker]);
    if (target == null) return const FormulaError('#REF', 'Related tracker not available');
    final targetDef = def.rollupTargetId == null ? null : target.property(def.rollupTargetId!);
    final aggregate = def.rollupAggregate;
    final needsTarget = !const {'count'}.contains(aggregate);
    if (needsTarget && targetDef == null) return const FormulaError('#REF', 'Rollup needs a property to summarise');

    final inner = identical(target, snapshot) ? this : Computed(target, now: now, depth: depth + 1);
    final related = <TrackerRecord>[
      for (final id in snapshot.links[rel.id]?[r.id] ?? const <String>[])
        if (target.record(id) case final rec? when !rec.archived) rec
    ];
    final vals = targetDef == null ? const <CellValue>[] : [for (final rec in related) inner.valueOf(rec, targetDef)];
    return aggregateValues(aggregate, related.length, vals, targetDef);
  }
}

/// Aggregates for rollups. [count] is the number of related records, [vals] the target property values.
CellValue aggregateValues(String aggregate, int count, List<CellValue> vals, PropertyDef? targetDef) {
  for (final v in vals) {
    if (v is FormulaError) return v;
  }
  final nonEmpty = vals.where((v) => !Values.isEmpty(v)).toList();
  List<num> nums() => [for (final v in nonEmpty) if (v is num) v];
  switch (aggregate) {
    case 'count':
      return count;
    case 'countNotEmpty':
      return nonEmpty.length;
    case 'countEmpty':
      return vals.length - nonEmpty.length;
    case 'countUnique':
      return nonEmpty.map((v) => v is List ? v.join('\u0000') : '$v').toSet().length;
    case 'sum':
      return nums().fold<num>(0, (a, b) => a + b);
    case 'avg':
      final n = nums();
      return n.isEmpty ? null : n.reduce((a, b) => a + b) / n.length;
    case 'min':
      final n = nums();
      return n.isEmpty ? null : n.reduce(math.min);
    case 'max':
      final n = nums();
      return n.isEmpty ? null : n.reduce(math.max);
    case 'median':
      final n = nums()..sort();
      if (n.isEmpty) return null;
      final m = n.length ~/ 2;
      return n.length.isOdd ? n[m] : (n[m - 1] + n[m]) / 2;
    case 'percentChecked':
      return vals.isEmpty ? null : vals.where((v) => v == true).length * 100 / vals.length;
    case 'percentComplete':
      // status property: share of related records whose status is in the "complete" group
      if (vals.isEmpty || targetDef == null) return null;
      final done = vals.where((v) => v is String && targetDef.option(v)?.group == StatusGroup.complete).length;
      return done * 100 / vals.length;
    case 'earliest':
    case 'latest':
      final dates = [for (final v in nonEmpty) if (v is String) v]..sort();
      if (dates.isEmpty) return null;
      return aggregate == 'earliest' ? dates.first : dates.last;
    case 'showOriginal':
      if (targetDef == null) return null;
      final l = [for (final v in nonEmpty) Values.format(targetDef, v)];
      return l.isEmpty ? null : l;
    default:
      return const FormulaError('#NAME', 'Unknown rollup type');
  }
}

CellValue _toStorageForm(Object? v) {
  if (v is DateTime) return v.toUtc().toIso8601String();
  if (v is double && v.isFinite && v == v.roundToDouble() && v.abs() < 1e15) return v.toInt();
  if (v is double && !v.isFinite) return const FormulaError('#TYPE', 'Not a finite number');
  return v;
}

class _Ctx implements FormulaContext {
  _Ctx(this.c, this.r);
  final Computed c;
  final TrackerRecord r;
  @override
  DateTime get now => c.now;
  @override
  bool knows(String id) => c.snapshot.property(id) != null;
  @override
  Object? read(String id) {
    final def = c.snapshot.property(id)!;
    final v = c.valueOf(r, def);
    if (v is FormulaError) throw _Propagate(v);
    return _toFormulaValue(def, v);
  }
}

class _Propagate implements Exception {
  _Propagate(this.error);
  final FormulaError error;
}

/// Convert a stored/computed value into what formulas operate on.
Object? _toFormulaValue(PropertyDef def, CellValue v) {
  if (v == null) return null;
  switch (def.type) {
    case PropertyType.date:
    case PropertyType.createdTime:
    case PropertyType.lastEditedTime:
      return v is String ? parseDate(v) : v;
    case PropertyType.dateRange:
      return v is Map ? parseDate(v['start'] as String) : null;
    case PropertyType.currency:
      final minor = v as int;
      var f = 1;
      for (var i = 0; i < def.decimals; i++) {
        f *= 10;
      }
      return minor / f;
    case PropertyType.select:
    case PropertyType.status:
      return def.option(v as String)?.label;
    case PropertyType.multiSelect:
      return [for (final id in v as List) def.option(id as String)?.label ?? id];
    case PropertyType.formula:
    case PropertyType.rollup:
      // computed results are already in storage form; dates come back as ISO strings
      return v is String && RegExp(r'^\d{4}-\d{2}-\d{2}T').hasMatch(v) ? (parseDate(v) ?? v) : v;
    default:
      return v;
  }
}
