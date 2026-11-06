import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:tracker_engine/tracker_engine.dart' as te;

import '../../../data/local/app_database.dart';
import '../../../data/sync/cell_sync.dart';
import '../../../data/sync/synced_store.dart';
import 'tracker_query.dart';

class CellValidationException implements Exception {
  CellValidationException(this.message);
  final String message;
  @override
  String toString() => message;
}

class QueryPage {
  QueryPage({required this.records, required this.total, required this.usedSql, this.groups});
  final List<te.TrackerRecord> records;

  /// Number of records matching the view (all pages).
  final int total;

  /// false when the in-memory reference path produced the result.
  final bool usedSql;
  final List<te.RecordGroup>? groups;
}

/// The only way tracker data is written or read. Every write goes through [SyncedStore] (one
/// transaction: data + field clock + outbox), so nothing here can bypass sync.
class TrackerRepository {
  TrackerRepository(this.store);
  final SyncedStore store;
  AppDatabase get db => store.db;

  // ------------------------------------------------------------------ trackers
  Stream<List<Tracker>> watchTrackers() => (db.select(db.trackers)
        ..where((t) => t.deletedAt.isNull() & t.archivedAt.isNull())
        ..orderBy([(t) => OrderingTerm.asc(t.sortKey), (t) => OrderingTerm.asc(t.id)]))
      .watch();

  Future<String> createTracker({required String name, String icon = 'table', String color = 'teal', bool withDefaults = true}) {
    return db.transaction(() async {
      final id = store.newId();
      await store.setFields('trackers', id, {'name': name.trim().isEmpty ? 'Untitled' : name.trim(), 'icon': icon, 'color': color, 'sort_key': await _nextKey('trackers')});
      if (withDefaults) {
        await addProperty(id, 'Name', te.PropertyType.text, config: {'isTitle': true});
        await createView(id, 'Table', te.ViewConfig());
      }
      return id;
    });
  }

  Future<void> updateTracker(String id, {String? name, String? icon, String? color}) =>
      store.setFields('trackers', id, {'name': ?name, 'icon': ?icon, 'color': ?color});

  Future<void> archiveTracker(String id, bool archived) => store.setFields('trackers', id, {'archived_at': archived ? store.nowMs : null});
  Future<void> deleteTracker(String id) => store.setFields('trackers', id, {'deleted_at': store.nowMs});

  /// Creates every tracker in [template] (ids remapped). Returns the new tracker ids in order.
  Future<List<String>> createFromTemplate(te.TrackerTemplate template) {
    return db.transaction(() async {
      final trackers = te.instantiateTemplate(template, store.newId);
      final ids = <String>[];
      for (final t in trackers) {
        await store.setFields('trackers', t.id, {'name': t.name, 'icon': t.icon, 'color': t.color, 'sort_key': await _nextKey('trackers')});
        var prev = '';
        for (final p in t.properties) {
          final key = te.between(prev.isEmpty ? null : prev, null);
          prev = key;
          await store.setFields('properties', p.id, {'tracker_id': t.id, 'name': p.name, 'type': p.type.name, 'config_json': jsonEncode(p.config), 'sort_key': key});
        }
        prev = '';
        for (final v in t.views) {
          final key = te.between(prev.isEmpty ? null : prev, null);
          prev = key;
          await store.setFields('views', v.id, {'tracker_id': t.id, 'name': v.name, 'config_json': jsonEncode(v.config.toJson()), 'sort_key': key});
        }
        ids.add(t.id);
      }
      return ids;
    });
  }

  // ---------------------------------------------------------------- properties
  Stream<List<te.PropertyDef>> watchProperties(String trackerId) => _propsQuery(trackerId).watch().map(_defs);

  Future<List<te.PropertyDef>> properties(String trackerId) async => _defs(await _propsQuery(trackerId).get());

  SimpleSelectStatement<$PropertiesTable, PropertyRow> _propsQuery(String trackerId) => db.select(db.properties)
    ..where((p) => p.trackerId.equals(trackerId) & p.deletedAt.isNull())
    ..orderBy([(p) => OrderingTerm.asc(p.sortKey), (p) => OrderingTerm.asc(p.id)]);

  List<te.PropertyDef> _defs(List<PropertyRow> rows) => [for (final r in rows) ?propertyDefFromRow(r)];

  Future<String> addProperty(String trackerId, String name, te.PropertyType type, {Map<String, Object?> config = const {}, String? afterPropertyId}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw CellValidationException('Give the property a name.');
    if (type == te.PropertyType.formula) _checkFormula(await properties(trackerId), null, (config['formula'] as String?) ?? '');
    final id = store.newId();
    final key = await _keyAfter('properties', 'tracker_id', trackerId, afterPropertyId);
    await store.setFields('properties', id, {'tracker_id': trackerId, 'name': trimmed, 'type': type.name, 'config_json': jsonEncode(config), 'sort_key': key});
    return id;
  }

  /// Creates two relation properties that point at each other (two-way relation).
  Future<(String, String)> addRelationPair({required String trackerA, required String nameA, required String trackerB, required String nameB, bool manyA = true, bool manyB = true}) {
    return db.transaction(() async {
      final a = await addProperty(trackerA, nameA, te.PropertyType.relation, config: {'targetTrackerId': trackerB, 'many': manyA});
      final b = await addProperty(trackerB, nameB, te.PropertyType.relation, config: {'targetTrackerId': trackerA, 'many': manyB, 'pairPropertyId': a});
      final rowA = await _propRow(a);
      final cfgA = Map<String, Object?>.from(jsonDecode(rowA.configJson) as Map)..['pairPropertyId'] = b;
      await store.setFields('properties', a, {'config_json': jsonEncode(cfgA)});
      return (a, b);
    });
  }

  Future<void> updateProperty(String id, {String? name, Map<String, Object?>? config}) async {
    final row = await _propRow(id);
    if (name != null && name.trim().isEmpty) throw CellValidationException('Give the property a name.');
    if (config != null && row.type == te.PropertyType.formula.name) {
      _checkFormula(await properties(row.trackerId), id, (config['formula'] as String?) ?? '');
    }
    await store.setFields('properties', id, {'name': ?name?.trim(), if (config != null) 'config_json': jsonEncode(config)});
  }

  /// Soft delete: cells are kept, so the property (and its data) can be restored.
  Future<void> deleteProperty(String id) => store.setFields('properties', id, {'deleted_at': store.nowMs});
  Future<void> restoreProperty(String id) => store.setFields('properties', id, {'deleted_at': null});

  Future<void> moveProperty(String id, {String? afterPropertyId}) async {
    final row = await _propRow(id);
    await store.setFields('properties', id, {'sort_key': await _keyAfter('properties', 'tracker_id', row.trackerId, afterPropertyId, excludeId: id)});
  }

  Future<PropertyRow> _propRow(String id) => (db.select(db.properties)..where((p) => p.id.equals(id))).getSingle();

  void _checkFormula(List<te.PropertyDef> existing, String? selfId, String source) {
    try {
      te.parseFormula(source);
    } on te.FormulaSyntaxException catch (e) {
      throw CellValidationException('Formula error: ${e.message}');
    }
    final probe = [
      for (final d in existing) if (d.id != selfId) d,
      te.PropertyDef(id: selfId ?? '__new__', name: '__f', type: te.PropertyType.formula, config: {'formula': source}),
    ];
    try {
      te.formulaOrder(probe);
    } on te.FormulaCycleException catch (e) {
      throw CellValidationException(e.toString());
    }
  }

  // ------------------------------------------------------------------- records
  Future<String> createRecord(String trackerId, {Map<String, te.CellValue> values = const {}, String? parentId, String? afterRecordId}) {
    return db.transaction(() async {
      final defs = {for (final d in await properties(trackerId)) d.id: d};
      final clean = <String, te.CellValue>{};
      for (final e in values.entries) {
        final d = defs[e.key];
        if (d == null) continue;
        clean[e.key] = _checked(d, e.value);
      }
      final id = store.newId();
      final key = await _keyAfter('records', 'tracker_id', trackerId, afterRecordId, parentId: parentId);
      await store.setFields('records', id, {'tracker_id': trackerId, 'parent_id': parentId, 'sort_key': key});
      for (final e in clean.entries) {
        if (e.value != null) await store.setFields('cells', '$id:${e.key}', {'value': e.value});
      }
      return id;
    });
  }

  te.CellValue _checked(te.PropertyDef d, te.CellValue v) {
    if (!d.type.isStored) throw CellValidationException('"${d.name}" is calculated and can\'t be edited.');
    final n = te.Values.normalize(d, v);
    final err = te.Values.validate(d, n);
    if (err != null) throw CellValidationException(err);
    return n;
  }

  /// Sets one cell. Returns the previous value (for undo). Throws [CellValidationException]
  /// with a plain-language message; the stored value is untouched on failure.
  Future<te.CellValue> setCell(String recordId, String propertyId, te.CellValue value) async {
    final def = propertyDefFromRow(await _propRow(propertyId));
    if (def == null) throw CellValidationException('This property can\'t be edited in this version of the app.');
    final n = _checked(def, value);
    final prev = await cellValue(recordId, propertyId);
    if (_same(prev, n)) return prev;
    await store.setFields('cells', '$recordId:$propertyId', {'value': n});
    return prev;
  }

  /// Applies the same value to many records atomically (bulk edit). Returns previous values.
  Future<Map<String, te.CellValue>> setCellForRecords(List<String> recordIds, String propertyId, te.CellValue value) {
    return db.transaction(() async => {for (final r in recordIds) r: await setCell(r, propertyId, value)});
  }

  bool _same(te.CellValue a, te.CellValue b) => jsonEncode(a) == jsonEncode(b);

  Future<te.CellValue> cellValue(String recordId, String propertyId) async {
    final row = await (db.select(db.cells)..where((c) => c.recordId.equals(recordId) & c.propertyId.equals(propertyId))).getSingleOrNull();
    return row == null ? null : jsonDecode(row.raw);
  }

  Future<void> deleteRecords(List<String> ids) => db.transaction(() async {
        for (final id in ids) {
          await store.setFields('records', id, {'deleted_at': store.nowMs});
        }
      });

  Future<void> restoreRecords(List<String> ids) => db.transaction(() async {
        for (final id in ids) {
          await store.setFields('records', id, {'deleted_at': null});
        }
      });

  Future<void> archiveRecords(List<String> ids, bool archived) => db.transaction(() async {
        for (final id in ids) {
          await store.setFields('records', id, {'archived_at': archived ? store.nowMs : null});
        }
      });

  /// Copies cells and relation links (not subtasks). The copy appears right after the original.
  Future<String> duplicateRecord(String id) {
    return db.transaction(() async {
      final src = await (db.select(db.records)..where((r) => r.id.equals(id))).getSingle();
      final copy = await createRecord(src.trackerId, parentId: src.parentId, afterRecordId: id);
      final cells = await (db.select(db.cells)..where((c) => c.recordId.equals(id))).get();
      for (final c in cells) {
        await store.setFields('cells', '$copy:${c.propertyId}', {'value': jsonDecode(c.raw)});
      }
      final links = await (db.select(db.recordLinks)..where((l) => l.fromRecordId.equals(id) & l.deletedAt.isNull())).get();
      final byProp = <String, List<String>>{};
      for (final l in links) {
        byProp.putIfAbsent(l.relationPropertyId, () => []).add(l.toRecordId);
      }
      for (final e in byProp.entries) {
        await setLinks(e.key, copy, e.value);
      }
      return copy;
    });
  }

  Future<void> moveRecord(String id, {String? afterRecordId}) async {
    final r = await (db.select(db.records)..where((x) => x.id.equals(id))).getSingle();
    await store.setFields('records', id, {'sort_key': await _keyAfter('records', 'tracker_id', r.trackerId, afterRecordId, parentId: r.parentId, excludeId: id)});
  }

  // --------------------------------------------------------------------- links
  /// Replace the set of records linked from [fromRecordId] through relation [relationPropertyId].
  /// Two-way relations also write the reverse edges. Removed edges are soft-deleted.
  Future<void> setLinks(String relationPropertyId, String fromRecordId, List<String> toIds) {
    return db.transaction(() async {
      final rel = propertyDefFromRow(await _propRow(relationPropertyId));
      if (rel == null || rel.type != te.PropertyType.relation) throw CellValidationException('That isn\'t a relation property.');
      if (!rel.relationAllowsMany && toIds.length > 1) throw CellValidationException('"${rel.name}" can link to only one record.');
      final target = rel.relationTargetTrackerId;
      for (final t in toIds) {
        final row = await (db.select(db.records)..where((r) => r.id.equals(t))).getSingleOrNull();
        if (row == null || row.deletedAt != null) throw CellValidationException('One of the linked records no longer exists.');
        if (row.trackerId != target) throw CellValidationException('That record belongs to a different tracker.');
      }
      final pair = rel.config['pairPropertyId'] as String?;
      final before = await _activeTargets(relationPropertyId, fromRecordId); // must be read BEFORE syncing
      await _syncEdges(relationPropertyId, fromRecordId, toIds);
      if (pair != null) {
        // reverse direction: every target that gained OR lost the link updates its edge back to fromRecordId
        final all = {...toIds, ...before};
        for (final t in all) {
          final back = await _activeTargets(pair, t);
          final want = toIds.contains(t) ? {...back, fromRecordId} : back.where((x) => x != fromRecordId).toSet();
          await _syncEdges(pair, t, want.toList());
        }
      }
    });
  }

  Future<Set<String>> _activeTargets(String prop, String from) async => {
        for (final l in await (db.select(db.recordLinks)..where((l) => l.relationPropertyId.equals(prop) & l.fromRecordId.equals(from) & l.deletedAt.isNull())).get()) l.toRecordId
      };

  Future<void> _syncEdges(String prop, String from, List<String> want) async {
    final have = await _activeTargets(prop, from);
    final now = store.nowMs;
    var order = 0;
    for (final to in want) {
      final id = '$prop:$from:$to';
      if (!have.contains(to)) {
        await store.setFields('record_links', id, {'relation_property_id': prop, 'from_record_id': from, 'to_record_id': to, 'sort_key': '${order.toString().padLeft(6, '0')}', 'deleted_at': null});
      }
      order++;
    }
    for (final to in have.where((t) => !want.contains(t))) {
      await store.setFields('record_links', '$prop:$from:$to', {'deleted_at': now});
    }
  }

  Future<List<String>> links(String relationPropertyId, String fromRecordId) async => [
        for (final l in await (db.select(db.recordLinks)
                  ..where((l) => l.relationPropertyId.equals(relationPropertyId) & l.fromRecordId.equals(fromRecordId) & l.deletedAt.isNull())
                  ..orderBy([(l) => OrderingTerm.asc(l.sortKey), (l) => OrderingTerm.asc(l.id)]))
                .get())
          l.toRecordId
      ];

  // --------------------------------------------------------------------- views
  Stream<List<(String, String, te.ViewConfig)>> watchViews(String trackerId) => (db.select(db.trackerViews)
        ..where((v) => v.trackerId.equals(trackerId) & v.deletedAt.isNull())
        ..orderBy([(v) => OrderingTerm.asc(v.sortKey), (v) => OrderingTerm.asc(v.id)]))
      .watch()
      .map((rows) => [for (final r in rows) (r.id, r.name, _viewConfig(r.configJson))]);

  te.ViewConfig _viewConfig(String json) {
    try {
      return te.ViewConfig.fromJson(Map<String, Object?>.from(jsonDecode(json) as Map));
    } catch (_) {
      return te.ViewConfig();
    }
  }

  Future<String> createView(String trackerId, String name, te.ViewConfig config) async {
    final id = store.newId();
    await store.setFields('views', id, {
      'tracker_id': trackerId,
      'name': name.trim().isEmpty ? 'View' : name.trim(),
      'config_json': jsonEncode(config.toJson()),
      'sort_key': await _keyAfter('views', 'tracker_id', trackerId, null),
    });
    return id;
  }

  Future<void> updateView(String id, {String? name, te.ViewConfig? config}) =>
      store.setFields('views', id, {'name': ?name?.trim(), if (config != null) 'config_json': jsonEncode(config.toJson())});

  /// A tracker always keeps at least one view.
  Future<void> deleteView(String id) async {
    final row = await (db.select(db.trackerViews)..where((v) => v.id.equals(id))).getSingle();
    final n = await (db.selectOnly(db.trackerViews)
          ..addColumns([db.trackerViews.id.count()])
          ..where(db.trackerViews.trackerId.equals(row.trackerId) & db.trackerViews.deletedAt.isNull()))
        .map((r) => r.read(db.trackerViews.id.count())!)
        .getSingle();
    if (n <= 1) throw CellValidationException('A tracker needs at least one view.');
    await store.setFields('views', id, {'deleted_at': store.nowMs});
  }

  // ---------------------------------------------------------------------- read
  /// Emits whenever anything that can change a tracker's rows changes.
  Stream<void> watchData() => db.tableUpdates(TableUpdateQuery.onAllTables([db.records, db.cells, db.recordLinks, db.properties])).map((_) {});

  /// All reachable trackers (through relations) loaded in memory. Used for rollups, computed
  /// filters/sorts, grouping, and as the reference for the SQL path.
  Future<te.TrackerSnapshot> loadSnapshot(String trackerId) async {
    final snaps = <String, te.TrackerSnapshot>{};
    final shared = <String, te.TrackerSnapshot>{};
    final queue = [trackerId];
    while (queue.isNotEmpty) {
      final id = queue.removeLast();
      if (snaps.containsKey(id)) continue;
      final props = await properties(id);
      final recs = await (db.select(db.records)
            ..where((r) => r.trackerId.equals(id) & r.deletedAt.isNull())
            ..orderBy([(r) => OrderingTerm.asc(r.sortKey), (r) => OrderingTerm.asc(r.id)]))
          .get();
      final cellRows = await (db.select(db.cells).join([innerJoin(db.records, db.records.id.equalsExp(db.cells.recordId))])
            ..where(db.records.trackerId.equals(id) & db.records.deletedAt.isNull()))
          .map((r) => r.readTable(db.cells))
          .get();
      final cellsBy = <String, Map<String, te.CellValue>>{};
      final storedIds = {for (final p in props) if (p.type.isStored) p.id};
      for (final c in cellRows) {
        if (!storedIds.contains(c.propertyId)) continue; // cells of deleted/unknown properties stay hidden
        (cellsBy[c.recordId] ??= {})[c.propertyId] = jsonDecode(c.raw);
      }
      final links = <String, Map<String, List<String>>>{};
      for (final p in props.where((p) => p.type == te.PropertyType.relation)) {
        final rows = await (db.select(db.recordLinks)
              ..where((l) => l.relationPropertyId.equals(p.id) & l.deletedAt.isNull())
              ..orderBy([(l) => OrderingTerm.asc(l.sortKey), (l) => OrderingTerm.asc(l.id)]))
            .get();
        final m = <String, List<String>>{};
        for (final l in rows) {
          m.putIfAbsent(l.fromRecordId, () => []).add(l.toRecordId);
        }
        links[p.id] = m;
        final target = p.relationTargetTrackerId;
        if (target != null) queue.add(target);
      }
      snaps[id] = te.TrackerSnapshot(
        trackerId: id,
        properties: props,
        records: [
          for (final r in recs)
            te.TrackerRecord(
              id: r.id,
              trackerId: r.trackerId,
              parentId: r.parentId,
              sortKey: r.sortKey,
              cells: cellsBy[r.id] ?? {},
              createdAt: DateTime.fromMillisecondsSinceEpoch(r.createdAt, isUtc: true),
              updatedAt: DateTime.fromMillisecondsSinceEpoch(r.updatedAt > r.createdAt ? r.updatedAt : r.createdAt, isUtc: true),
              archived: r.archivedAt != null,
            )
        ],
        links: links,
        others: shared,
      );
    }
    shared.addAll(snaps);
    return snaps[trackerId]!;
  }

  /// One page of a view. Uses SQL (indexed) when the view can be translated exactly, otherwise
  /// the in-memory reference. [forceReference] is for tests.
  Future<QueryPage> queryPage(String trackerId, te.ViewConfig view, {String search = '', int limit = 100, int offset = 0, DateTime? now, bool forceReference = false}) async {
    final t = (now ?? DateTime.now()).toUtc();
    if (!forceReference && search.trim().isEmpty && view.groupBy == null) {
      final props = await properties(trackerId);
      final plan = buildSqlPlan(trackerId: trackerId, properties: props, view: view, now: t, limit: limit, offset: offset);
      if (plan != null) {
        final idRows = await db.customSelect(plan.idsSql, variables: plan.idsVars, readsFrom: {db.records, db.cells, db.recordLinks}).get();
        final total = (await db.customSelect(plan.countSql, variables: plan.countVars, readsFrom: {db.records, db.cells, db.recordLinks}).getSingle()).read<int>('n');
        return QueryPage(records: await _hydrate([for (final r in idRows) r.read<String>('id')], props), total: total, usedSql: true);
      }
    }
    final snap = await loadSnapshot(trackerId);
    final res = te.runQuery(snap, view, now: t, search: search);
    final end = (offset + limit) > res.records.length ? res.records.length : offset + limit;
    final page = offset >= res.records.length ? <te.TrackerRecord>[] : res.records.sublist(offset, end);
    return QueryPage(records: page, total: res.records.length, usedSql: false, groups: res.groups);
  }

  Future<List<te.TrackerRecord>> _hydrate(List<String> ids, List<te.PropertyDef> props) async {
    if (ids.isEmpty) return [];
    final recs = {for (final r in await (db.select(db.records)..where((r) => r.id.isIn(ids))).get()) r.id: r};
    final storedIds = {for (final p in props) if (p.type.isStored) p.id};
    final cellsBy = <String, Map<String, te.CellValue>>{};
    for (final c in await (db.select(db.cells)..where((c) => c.recordId.isIn(ids))).get()) {
      if (storedIds.contains(c.propertyId)) (cellsBy[c.recordId] ??= {})[c.propertyId] = jsonDecode(c.raw);
    }
    return [
      for (final id in ids)
        if (recs[id] case final r?)
          te.TrackerRecord(
            id: r.id,
            trackerId: r.trackerId,
            parentId: r.parentId,
            sortKey: r.sortKey,
            cells: cellsBy[id] ?? {},
            createdAt: DateTime.fromMillisecondsSinceEpoch(r.createdAt, isUtc: true),
            updatedAt: DateTime.fromMillisecondsSinceEpoch(r.updatedAt > r.createdAt ? r.updatedAt : r.createdAt, isUtc: true),
            archived: r.archivedAt != null,
          )
    ];
  }

  // ------------------------------------------------------------------ ordering
  Future<String> _nextKey(String table) => _keyAfter(table, null, null, null);

  /// Sort key placing an item right after [afterId] (or at the end when null) among its siblings.
  Future<String> _keyAfter(String table, String? scopeColumn, String? scopeValue, String? afterId, {String? parentId, String? excludeId}) async {
    final where = <String>['deleted_at IS NULL'];
    final vars = <Variable<Object>>[];
    if (scopeColumn != null) {
      where.add('$scopeColumn = ?');
      vars.add(Variable.withString(scopeValue!));
    }
    if (table == 'records') {
      where.add(parentId == null ? 'parent_id IS NULL' : 'parent_id = ?');
      if (parentId != null) vars.add(Variable.withString(parentId));
    }
    final rows = await db.customSelect('SELECT id, sort_key FROM $table WHERE ${where.join(' AND ')} ORDER BY sort_key, id', variables: vars).get();
    final keys = [for (final r in rows) if (r.read<String>('id') != excludeId) (r.read<String>('id'), r.read<String>('sort_key'))];
    String? lo, hi;
    if (afterId == null) {
      lo = keys.isEmpty ? null : keys.last.$2;
    } else {
      final i = keys.indexWhere((k) => k.$1 == afterId);
      if (i < 0) {
        lo = keys.isEmpty ? null : keys.last.$2;
      } else {
        lo = keys[i].$2;
        if (i + 1 < keys.length) hi = keys[i + 1].$2;
      }
    }
    if (lo != null && lo.isEmpty) lo = null; // legacy empty keys sort first
    if (lo != null && hi != null && lo.compareTo(hi) >= 0) {
      // duplicate keys (concurrent inserts on two devices): keep order stable by extending lo
      return te.between(lo, null);
    }
    return te.between(lo, hi);
  }
}
