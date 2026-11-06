import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracker_engine/tracker_engine.dart' as te;

import 'tracker_helpers.dart';

/// SQL path vs in-memory reference. Scale up locally: DIFF_SCENARIOS=300 flutter test <this file>
final _scenarios = int.tryParse(Platform.environment['DIFF_SCENARIOS'] ?? '') ?? 25;
final _start = int.tryParse(Platform.environment['DIFF_START'] ?? '') ?? 0;
final _now = DateTime.utc(2026, 11, 6, 9);

const _texts = ['Éclair', 'eclair', 'ÉCLAIR', 'banana', 'Banana split', 'a_b%c', "it's", 'ünïcode ß', 'x', 'zebra', '日本語'];
const _numbers = [-1, 0, 0.5, 1, 2, 2, 3.5, 100];
const _dates = ['1969-12-31', '1970-01-01', '2026-11-05', '2026-11-06', '2026-11-06T23:59:59.000Z', '2026-11-07', '2026-11-20', '2025-01-01'];

T pick<T>(Random r, List<T> l) => l[r.nextInt(l.length)];

Object? valueFor(Random r, te.PropertyDef d) {
  switch (d.type) {
    case te.PropertyType.text:
    case te.PropertyType.richText:
    case te.PropertyType.url:
    case te.PropertyType.email:
    case te.PropertyType.phone:
      return pick(r, _texts);
    case te.PropertyType.number:
    case te.PropertyType.percent:
      return pick(r, _numbers);
    case te.PropertyType.progress:
      return pick(r, [0, 25, 50, 100]);
    case te.PropertyType.currency:
      return pick(r, [-500, 0, 199, 250, 250, 10000]);
    case te.PropertyType.checkbox:
      return r.nextBool();
    case te.PropertyType.date:
      return pick(r, _dates);
    case te.PropertyType.dateRange:
      final s = pick(r, _dates);
      return r.nextBool() ? {'start': s} : {'start': s, 'end': '2026-12-31'};
    case te.PropertyType.select:
    case te.PropertyType.status:
      return pick(r, d.options).id;
    case te.PropertyType.multiSelect:
      final ids = [for (final o in d.options) o.id]..shuffle(r);
      return ids.take(1 + r.nextInt(3)).toList();
    case te.PropertyType.person:
    case te.PropertyType.files:
      return [pick(r, ['p1', 'p2', 'p3'])];
    default:
      return null;
  }
}

Object? operandFor(Random r, te.PropertyDef d, te.FilterOp op, List<String> otherRecords) {
  // occasionally use an operand of the "wrong" type: the engine has defined behaviour for it
  if (r.nextInt(12) == 0) return pick<Object?>(r, [null, 5, 'zzz', ['a'], true]);
  switch (op) {
    case te.FilterOp.isEmpty:
    case te.FilterOp.isNotEmpty:
    case te.FilterOp.isChecked:
    case te.FilterOp.isUnchecked:
      return null;
    case te.FilterOp.inLastDays:
    case te.FilterOp.inNextDays:
      return pick(r, [0, 1, 7, 30]);
    case te.FilterOp.isAnyOf:
    case te.FilterOp.isNoneOf:
      return [for (final o in d.options) if (r.nextBool()) o.id];
    case te.FilterOp.hasAny:
    case te.FilterOp.hasNone:
      if (d.type == te.PropertyType.relation) return [for (final id in otherRecords) if (r.nextBool()) id];
      if (d.type.isOptionBased) return [for (final o in d.options) if (r.nextBool()) o.id];
      return [for (final x in ['p1', 'p2', 'p3', 'zz']) if (r.nextBool()) x];
    default:
  }
  if (d.type.isTextLike) return pick(r, [..._texts, 'ecl', 'AN', 'b%', '_', '']);
  if (d.type == te.PropertyType.select || d.type == te.PropertyType.status) return pick(r, d.options).id;
  if (d.type == te.PropertyType.date || d.type == te.PropertyType.dateRange) return pick(r, _dates);
  return pick(r, [..._numbers, 199, 250, 50]);
}

te.FilterNode randomFilter(Random r, List<te.PropertyDef> props, List<String> others, int depth) {
  if (depth > 0 && r.nextInt(3) == 0) {
    return te.FilterGroup(and: r.nextBool(), children: [for (var i = 0; i < 1 + r.nextInt(3); i++) randomFilter(r, props, others, depth - 1)]);
  }
  final d = pick(r, props);
  final ops = te.opsFor(d.type);
  final op = pick(r, ops);
  return te.FilterCondition(propertyId: r.nextInt(40) == 0 ? 'deleted-prop' : d.id, op: op, value: operandFor(r, d, op, others));
}

void main() {
  test('SQL path and in-memory reference return identical rows and totals ($_scenarios scenarios)', () async {
    var compared = 0, viaSql = 0;
    final opsSeen = <te.FilterOp>{};
    for (var seed = _start; seed < _start + _scenarios; seed++) {
      final r = Random(seed);
      final e = await Env.create(device: 'd$seed');
      try {
        final tracker = await e.repo.createTracker(name: 'T');
        final other = await e.repo.createTracker(name: 'Other');
        final props = <te.PropertyDef>[];
        Future<void> add(String name, te.PropertyType t, [Map<String, Object?> cfg = const {}]) async {
          final id = await e.repo.addProperty(tracker, name, t, config: cfg);
          props.add((await e.repo.properties(tracker)).firstWhere((p) => p.id == id));
        }

        for (final t in [
          te.PropertyType.text, te.PropertyType.richText, te.PropertyType.url, te.PropertyType.number, te.PropertyType.currency,
          te.PropertyType.percent, te.PropertyType.progress, te.PropertyType.checkbox, te.PropertyType.date, te.PropertyType.dateRange,
          te.PropertyType.person,
        ]) {
          await add(t.name, t);
        }
        final opts = te.Cfg.options([for (final id in ['o1', 'o2', 'o3', 'o4']) te.SelectOption(id: id, label: 'Label $id')]);
        await add('sel', te.PropertyType.select, opts);
        await add('stat', te.PropertyType.status, opts);
        await add('multi', te.PropertyType.multiSelect, opts);
        await add('f', te.PropertyType.formula, {'formula': 'length(concat("x", 1))'});
        final (rel, _) = await e.repo.addRelationPair(trackerA: tracker, nameA: 'rel', trackerB: other, nameB: 'back');
        props.add((await e.repo.properties(tracker)).firstWhere((p) => p.id == rel));

        final otherIds = [for (var i = 0; i < 6; i++) await e.repo.createRecord(other)];
        final ids = <String>[];
        for (var i = 0, n = 25 + r.nextInt(40); i < n; i++) {
          final vals = <String, Object?>{};
          for (final d in props.where((d) => d.type.isStored)) {
            if (r.nextInt(10) < 6) vals[d.id] = valueFor(r, d);
          }
          final id = await e.repo.createRecord(tracker, values: {for (final en in vals.entries) en.key: en.value}, afterRecordId: ids.isEmpty || r.nextBool() ? null : pick(r, ids));
          ids.add(id);
          if (r.nextInt(3) == 0) await e.repo.setLinks(rel, id, [for (final o in otherIds) if (r.nextInt(4) == 0) o]);
        }
        await e.repo.archiveRecords([for (final id in ids) if (r.nextInt(8) == 0) id], true);
        await e.repo.deleteRecords([for (final id in ids) if (r.nextInt(10) == 0) id]);
        // reorder + remove an option AFTER data exists: ranks must follow the CURRENT options
        final sel = props.firstWhere((p) => p.name == 'sel');
        await e.repo.updateProperty(sel.id, config: te.Cfg.options([
          const te.SelectOption(id: 'o3', label: 'C'), const te.SelectOption(id: 'o1', label: 'A'), const te.SelectOption(id: 'o4', label: 'D'),
        ]));
        final live = await e.repo.properties(tracker);

        for (var v = 0; v < 22; v++) {
          final filter = te.FilterGroup(and: r.nextBool(), children: [if (r.nextInt(5) != 0) for (var i = 0; i < 1 + r.nextInt(3); i++) randomFilter(r, live, otherIds, 2)]);
          final sorts = [for (var i = 0; i < r.nextInt(4); i++) te.SortKey(pick(r, live).id, descending: r.nextBool())];
          final view = te.ViewConfig(filter: filter, sorts: sorts, showArchived: r.nextInt(4) == 0);
          void walk(te.FilterNode n) => n is te.FilterCondition ? opsSeen.add(n.op) : (n as te.FilterGroup).children.forEach(walk);
          walk(filter);

          final sql = await e.repo.queryPage(tracker, view, limit: 1000, now: _now);
          final ref = await e.repo.queryPage(tracker, view, limit: 1000, now: _now, forceReference: true);
          compared++;
          if (sql.usedSql) viaSql++;
          final names = {for (final d in live) d.id: '${d.name}:${d.type.name}'};
          final desc = 'seed $seed view $v\nprops=$names\nfilter=${filter.toJson()}\nsorts=${[for (final s in sorts) '${names[s.propertyId]}${s.descending ? ' desc' : ''}']} archived=${view.showArchived}';
          if (sql.records.map((x) => x.id).join() != ref.records.map((x) => x.id).join()) {
            String row(dynamic te_record) => '${te_record.id.substring(24)} key=${te_record.sortKey} ${[for (final s in sorts) '${names[s.propertyId]}=${te_record.cells[s.propertyId]}'].join(' ')}';
            // ignore: avoid_print
            print('SQL: ${sql.records.take(6).map(row).join('\n     ')}\nREF: ${ref.records.take(6).map(row).join('\n     ')}');
          }
          expect(sql.records.map((x) => x.id).toList(), ref.records.map((x) => x.id).toList(), reason: desc);
          expect(sql.total, ref.total, reason: desc);

          if (sql.usedSql && ref.total > 6) {
            final off = r.nextInt(ref.total - 3), lim = 1 + r.nextInt(5);
            final paged = await e.repo.queryPage(tracker, view, limit: lim, offset: off, now: _now);
            expect(paged.records.map((x) => x.id).toList(), ref.records.skip(off).take(lim).map((x) => x.id).toList(), reason: 'pagination $desc');
            expect(paged.total, ref.total);
          }
        }
      } finally {
        await e.close();
      }
    }
    // the SQL path must actually be exercised (not silently always falling back)
    expect(viaSql / compared, greaterThan(0.6), reason: 'only $viaSql of $compared used SQL');
    // and every filter operator that the SQL layer claims to support was generated at least once
    expect(opsSeen.length, greaterThanOrEqualTo(20), reason: 'operators covered: $opsSeen');
    // ignore: avoid_print
    print('compared $compared views ($viaSql via SQL), operators covered: ${opsSeen.length}');
  }, timeout: const Timeout(Duration(minutes: 20)));
}
