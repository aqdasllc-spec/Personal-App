import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker_engine/tracker_engine.dart' as te;

import '../../../app/providers.dart';
import '../../../data/local/app_database.dart';
import '../data/tracker_repository.dart';

final trackerRepositoryProvider = Provider<TrackerRepository>((ref) => TrackerRepository(ref.watch(syncedStoreProvider)));

final trackersProvider = StreamProvider<List<Tracker>>((ref) => ref.watch(trackerRepositoryProvider).watchTrackers());

class SelectedTracker extends Notifier<String?> {
  @override
  String? build() => null;
  void select(String? id) => state = id;
}

final selectedTrackerProvider = NotifierProvider<SelectedTracker, String?>(SelectedTracker.new);

class ViewEntry {
  const ViewEntry(this.id, this.name, this.config);
  final String id;
  final String name;
  final te.ViewConfig config;
}

class ActiveCell {
  const ActiveCell(this.recordId, this.propertyId);
  final String recordId;
  final String propertyId;
  @override
  bool operator ==(Object other) => other is ActiveCell && other.recordId == recordId && other.propertyId == propertyId;
  @override
  int get hashCode => Object.hash(recordId, propertyId);
}

class TrackerScreenState {
  const TrackerScreenState({
    required this.trackerId,
    this.properties = const [],
    this.views = const [],
    this.activeViewId,
    this.view,
    this.search = '',
    this.records = const [],
    this.groups,
    this.total = 0,
    this.computed = const {},
    this.titles = const {},
    this.selected = const {},
    this.active,
    this.editing = false,
    this.message,
    this.canUndo = false,
    this.canRedo = false,
    this.undoLabel,
    this.usedSql = true,
    this.groupPropertyId,
  });

  final String trackerId;
  final List<te.PropertyDef> properties;
  final List<ViewEntry> views;
  final String? activeViewId;
  final te.ViewConfig? view;
  final String search;
  final List<te.TrackerRecord> records;
  final List<te.RecordGroup>? groups;
  final int total;

  /// recordId -> propertyId -> value of calculated properties (formula, rollup, created/edited).
  final Map<String, Map<String, te.CellValue>> computed;

  /// recordId -> display title (for relation chips and detail headers).
  final Map<String, String> titles;
  final Set<String> selected;
  final ActiveCell? active;
  final bool editing;

  /// One-shot user-facing message (validation errors etc.); cleared by [TrackerController.clearMessage].
  final String? message;
  final bool canUndo, canRedo;
  final String? undoLabel;
  final bool usedSql;

  /// The property the current grouped layout (board) actually groups by: the view's own choice, or a
  /// Status/Select property picked automatically when the view has none.
  final String? groupPropertyId;

  te.ViewConfig get effectiveView => view ?? te.ViewConfig();

  List<te.PropertyDef> get visibleProperties {
    final v = effectiveView.visibleProperties;
    if (v == null) return properties;
    return [for (final id in v) ...properties.where((p) => p.id == id)];
  }

  te.PropertyDef? get titleProperty {
    for (final p in properties) {
      if (p.config['isTitle'] == true) return p;
    }
    for (final p in properties) {
      if (p.type == te.PropertyType.text) return p;
    }
    return null;
  }

  te.CellValue valueOf(te.TrackerRecord r, te.PropertyDef p) => p.type.isStored ? r.cells[p.id] : computed[r.id]?[p.id];

  TrackerScreenState copyWith({
    List<te.PropertyDef>? properties,
    List<ViewEntry>? views,
    String? activeViewId,
    te.ViewConfig? view,
    String? search,
    List<te.TrackerRecord>? records,
    List<te.RecordGroup>? groups,
    bool clearGroups = false,
    int? total,
    Map<String, Map<String, te.CellValue>>? computed,
    Map<String, String>? titles,
    Set<String>? selected,
    Value<ActiveCell?> active = const Value.absent(),
    bool? editing,
    Value<String?> message = const Value.absent(),
    bool? canUndo,
    bool? canRedo,
    Value<String?> undoLabel = const Value.absent(),
    bool? usedSql,
    Value<String?> groupPropertyId = const Value.absent(),
  }) =>
      TrackerScreenState(
        trackerId: trackerId,
        properties: properties ?? this.properties,
        views: views ?? this.views,
        activeViewId: activeViewId ?? this.activeViewId,
        view: view ?? this.view,
        search: search ?? this.search,
        records: records ?? this.records,
        groups: clearGroups ? null : (groups ?? this.groups),
        total: total ?? this.total,
        computed: computed ?? this.computed,
        titles: titles ?? this.titles,
        selected: selected ?? this.selected,
        active: active.present ? active.value : this.active,
        editing: editing ?? this.editing,
        message: message.present ? message.value : this.message,
        canUndo: canUndo ?? this.canUndo,
        canRedo: canRedo ?? this.canRedo,
        undoLabel: undoLabel.present ? undoLabel.value : this.undoLabel,
        usedSql: usedSql ?? this.usedSql,
        groupPropertyId: groupPropertyId.present ? groupPropertyId.value : this.groupPropertyId,
      );
}

class _Command {
  _Command(this.label, this.undo, this.redo);
  final String label;
  final Future<void> Function() undo;
  final Future<void> Function() redo;
}

/// State and actions of one open tracker. Reloads itself whenever data changes (local edits or sync).
class TrackerController extends AsyncNotifier<TrackerScreenState> {
  TrackerController(this.trackerId);
  final String trackerId;

  static const pageSize = 1000;
  Timer? _debounce;
  final _undo = <_Command>[];
  final _redo = <_Command>[];
  bool _disposed = false;

  TrackerRepository get repo => ref.read(trackerRepositoryProvider);

  @override
  Future<TrackerScreenState> build() async {
    final sub = repo.watchData().listen((_) => _scheduleRefresh());
    // skip(1): the first emission is just the current rows; build() already loads them
    final vsub = repo.watchViews(trackerId).skip(1).listen((_) => _scheduleRefresh());
    ref.onDispose(() {
      _disposed = true;
      _debounce?.cancel();
      sub.cancel();
      vsub.cancel();
    });
    return _load(TrackerScreenState(trackerId: trackerId));
  }

  void _scheduleRefresh() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 60), () async {
      if (_disposed) return;
      final cur = state.value;
      if (cur == null) return;
      final next = await _load(cur);
      if (!_disposed) state = AsyncData(next);
    });
  }

  Future<TrackerScreenState> _load(TrackerScreenState cur) async {
    final props = await repo.properties(trackerId);
    final viewRows = await repo.views(trackerId);
    final views = [for (final v in viewRows) ViewEntry(v.$1, v.$2, v.$3)];
    final activeId = views.any((v) => v.id == cur.activeViewId) ? cur.activeViewId : (views.isEmpty ? null : views.first.id);
    final cfg = views.where((v) => v.id == activeId).map((v) => v.config).firstOrNull ?? te.ViewConfig();

    final needsGroups = cfg.layout == te.ViewLayout.kanban;
    var effective = cfg;
    if (needsGroups && cfg.groupBy == null) {
      final gid = cfg.layoutOptions['groupPropertyId'] as String?;
      final prop = props.where((p) => p.id == gid || (gid == null && p.type == te.PropertyType.status)).firstOrNull ?? props.where((p) => p.type == te.PropertyType.select).firstOrNull;
      if (prop != null) effective = cfg.copyWith(groupBy: te.GroupBy(prop.id));
    }
    final page = await repo.queryPage(trackerId, effective, search: cur.search, limit: pageSize);

    // calculated values for the rows on screen
    final computed = <String, Map<String, te.CellValue>>{};
    final titles = <String, String>{};
    final calc = props.where((p) => !p.type.isStored).toList();
    if (calc.isNotEmpty || props.any((p) => p.type == te.PropertyType.relation)) {
      final snap = await repo.loadSnapshot(trackerId);
      final c = te.Computed(snap);
      for (final r in page.records) {
        final full = snap.record(r.id);
        if (full == null) continue;
        computed[r.id] = {for (final p in calc) p.id: c.valueOf(full, p)};
      }
      for (final other in {snap, ...snap.others.values}) {
        final t = other.titleProperty;
        for (final r in other.records) {
          final v = t == null ? null : r.cells[t.id];
          titles[r.id] = v is String && v.isNotEmpty ? v : 'Untitled';
        }
      }
    }
    // UI state (selection, active cell, editing, search, messages) must come from the LATEST state,
    // not from the copy we started with: the user may have clicked while this load was in flight.
    final ui = state.value ?? cur;
    final ids = page.records.map((r) => r.id).toSet();
    final sel = ui.selected.where(ids.contains).toSet();
    final act = ui.active != null && ids.contains(ui.active!.recordId) && props.any((p) => p.id == ui.active!.propertyId) ? ui.active : null;

    return ui.copyWith(
      properties: props,
      views: views,
      activeViewId: activeId,
      view: cfg,
      records: page.records,
      groups: page.groups,
      clearGroups: page.groups == null,
      total: page.total,
      computed: computed,
      titles: titles,
      selected: sel,
      active: Value(act),
      editing: act == null ? false : ui.editing,
      usedSql: page.usedSql,
      groupPropertyId: Value(effective.groupBy?.propertyId),
      canUndo: _undo.isNotEmpty,
      canRedo: _redo.isNotEmpty,
      undoLabel: Value(_undo.isEmpty ? null : _undo.last.label),
    );
  }

  Future<void> reload() async => state = AsyncData(await _load(state.requireValue));

  void _set(TrackerScreenState s) => state = AsyncData(s);
  TrackerScreenState get _s => state.requireValue;

  void clearMessage() => _set(_s.copyWith(message: const Value(null)));
  void _fail(Object e) => _set(_s.copyWith(message: Value(e is CellValidationException ? e.message : 'Something went wrong. Your data is unchanged.')));

  // ----------------------------------------------------------------- undo / redo
  void _push(_Command c) {
    _undo.add(c);
    if (_undo.length > 100) _undo.removeAt(0);
    _redo.clear();
  }

  Future<void> undo() async {
    if (_undo.isEmpty) return;
    final c = _undo.removeLast();
    try {
      await c.undo();
      _redo.add(c);
    } catch (e) {
      _fail(e);
    }
    await reload();
  }

  Future<void> redo() async {
    if (_redo.isEmpty) return;
    final c = _redo.removeLast();
    try {
      await c.redo();
      _undo.add(c);
    } catch (e) {
      _fail(e);
    }
    await reload();
  }

  // ---------------------------------------------------------------- selection
  void setActive(ActiveCell? a, {bool editing = false}) => _set(_s.copyWith(active: Value(a), editing: editing));
  void startEditing() => _s.active == null ? null : _set(_s.copyWith(editing: true));
  void stopEditing() => _set(_s.copyWith(editing: false));

  void toggleSelected(String recordId, {bool only = false}) {
    final s = Set<String>.of(only ? const {} : _s.selected);
    if (!s.remove(recordId)) s.add(recordId);
    _set(_s.copyWith(selected: s));
  }

  void selectRange(String toRecordId) {
    final ids = _s.records.map((r) => r.id).toList();
    final anchor = _s.selected.isEmpty ? (_s.active?.recordId ?? toRecordId) : _s.selected.last;
    final a = ids.indexOf(anchor), b = ids.indexOf(toRecordId);
    if (a < 0 || b < 0) return;
    final range = ids.sublist(a < b ? a : b, (a < b ? b : a) + 1);
    _set(_s.copyWith(selected: {..._s.selected, ...range}));
  }

  void selectAll() => _set(_s.copyWith(selected: {for (final r in _s.records) r.id}));
  void clearSelection() => _set(_s.copyWith(selected: const {}));

  // -------------------------------------------------------------------- edits
  /// Inline cell edit. Returns false (and sets a message) when validation fails.
  Future<bool> setCell(String recordId, String propertyId, te.CellValue value) async {
    try {
      final prev = await repo.setCell(recordId, propertyId, value);
      final cur = await repo.cellValue(recordId, propertyId);
      if (jsonish(prev) != jsonish(cur)) {
        _push(_Command('Edit cell', () => repo.setCell(recordId, propertyId, prev).then((_) {}), () => repo.setCell(recordId, propertyId, cur).then((_) {})));
      }
      await reload();
      return true;
    } catch (e) {
      _fail(e);
      return false;
    }
  }

  static String jsonish(Object? o) => o == null ? 'null' : o.toString();

  /// Parse text typed by the user for [propertyId], then set it.
  Future<bool> setCellFromText(String recordId, String propertyId, String text) async {
    final def = _s.properties.firstWhere((p) => p.id == propertyId);
    final r = te.Values.parseText(def, text);
    if (r.error != null) {
      _fail(CellValidationException(r.error!));
      return false;
    }
    if (r.newOptionLabel != null) {
      _fail(CellValidationException('"${r.newOptionLabel}" isn\'t one of the options. Pick one from the list.'));
      return false;
    }
    return setCell(recordId, propertyId, r.value);
  }

  Future<String?> addRecord({String? afterRecordId, String? parentId, Map<String, te.CellValue> values = const {}}) async {
    try {
      final id = await repo.createRecord(trackerId, values: values, afterRecordId: afterRecordId, parentId: parentId);
      _push(_Command('Add row', () => repo.deleteRecords([id]), () => repo.restoreRecords([id])));
      await reload();
      return id;
    } catch (e) {
      _fail(e);
      return null;
    }
  }

  Future<void> deleteRecords(List<String> ids) async {
    if (ids.isEmpty) return;
    await repo.deleteRecords(ids);
    _push(_Command('Delete ${ids.length} row${ids.length == 1 ? '' : 's'}', () => repo.restoreRecords(ids), () => repo.deleteRecords(ids)));
    _set(_s.copyWith(selected: const {}));
    await reload();
  }

  Future<void> archiveRecords(List<String> ids, bool archived) async {
    if (ids.isEmpty) return;
    await repo.archiveRecords(ids, archived);
    _push(_Command(archived ? 'Archive' : 'Unarchive', () => repo.archiveRecords(ids, !archived), () => repo.archiveRecords(ids, archived)));
    _set(_s.copyWith(selected: const {}));
    await reload();
  }

  Future<void> duplicateRecord(String id) async {
    try {
      final copy = await repo.duplicateRecord(id);
      _push(_Command('Duplicate row', () => repo.deleteRecords([copy]), () => repo.restoreRecords([copy])));
      await reload();
    } catch (e) {
      _fail(e);
    }
  }

  /// Bulk edit: one undoable step.
  Future<void> setCellForSelected(String propertyId, te.CellValue value) async {
    final ids = _s.selected.toList();
    if (ids.isEmpty) return;
    try {
      final prev = await repo.setCellForRecords(ids, propertyId, value);
      _push(_Command('Edit ${ids.length} rows', () async {
        for (final e in prev.entries) {
          await repo.setCell(e.key, propertyId, e.value);
        }
      }, () => repo.setCellForRecords(ids, propertyId, value).then((_) {})));
      await reload();
    } catch (e) {
      _fail(e);
    }
  }

  // ---------------------------------------------------------------- properties
  Future<String?> addProperty(String name, te.PropertyType type, Map<String, Object?> config) async {
    try {
      final id = await repo.addProperty(trackerId, name, type, config: config);
      _push(_Command('Add property', () => repo.deleteProperty(id), () => repo.restoreProperty(id)));
      await reload();
      return id;
    } catch (e) {
      _fail(e);
      return null;
    }
  }

  Future<bool> updateProperty(String id, {String? name, Map<String, Object?>? config}) async {
    try {
      await repo.updateProperty(id, name: name, config: config);
      await reload();
      return true;
    } catch (e) {
      _fail(e);
      return false;
    }
  }

  Future<void> deleteProperty(String id) async {
    await repo.deleteProperty(id);
    _push(_Command('Delete property', () => repo.restoreProperty(id), () => repo.deleteProperty(id)));
    await reload();
  }

  /// Create a two-way relation to another tracker.
  Future<void> addRelation(String name, String targetTrackerId, String reverseName, {bool many = true}) async {
    try {
      await repo.addRelationPair(trackerA: trackerId, nameA: name, trackerB: targetTrackerId, nameB: reverseName, manyA: many);
      await reload();
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> setLinks(String relationPropertyId, String recordId, List<String> toIds) async {
    try {
      final prev = await repo.links(relationPropertyId, recordId);
      await repo.setLinks(relationPropertyId, recordId, toIds);
      _push(_Command('Edit links', () => repo.setLinks(relationPropertyId, recordId, prev), () => repo.setLinks(relationPropertyId, recordId, toIds)));
      await reload();
    } catch (e) {
      _fail(e);
    }
  }

  /// Add an option to a select/multi-select/status property and return its id.
  Future<String?> createOption(String propertyId, String label, {String color = 'gray'}) async {
    final def = _s.properties.firstWhere((p) => p.id == propertyId);
    final clean = label.trim();
    if (clean.isEmpty) return null;
    final existing = def.options.where((o) => te.foldText(o.label) == te.foldText(clean)).firstOrNull;
    if (existing != null) return existing.id;
    final id = repo.store.newId();
    final opts = [...def.options, te.SelectOption(id: id, label: clean, color: color, group: def.type == te.PropertyType.status ? te.StatusGroup.todo : null)];
    final ok = await updateProperty(propertyId, config: {...def.config, ...te.Cfg.options(opts)});
    return ok ? id : null;
  }

  /// Records of the tracker a relation points at (for the link picker): (id, title).
  Future<List<(String, String)>> relationCandidates(te.PropertyDef relation) async {
    final target = relation.relationTargetTrackerId;
    if (target == null) return const [];
    final snap = await repo.loadSnapshot(target);
    final title = snap.titleProperty;
    return [for (final r in snap.records) if (!r.archived) (r.id, title == null ? 'Untitled' : (r.cells[title.id] as String?) ?? 'Untitled')];
  }

  Future<List<(String, String)>> trackerChoices() async =>
      [for (final t in await repo.trackers()) if (t.id != trackerId) (t.id, t.name)];

  Future<List<te.PropertyDef>> propertiesOf(String otherTrackerId) => repo.properties(otherTrackerId);

  Future<List<String>> currentLinks(String relationPropertyId, String recordId) => repo.links(relationPropertyId, recordId);

  // --------------------------------------------------------------------- views
  Future<void> setActiveView(String id) async {
    _set(_s.copyWith(activeViewId: id, selected: const {}, active: const Value(null)));
    await reload();
  }

  /// Persist changes to the active view (filters, sorts, group, columns, widths...).
  Future<void> updateView(te.ViewConfig config) async {
    final id = _s.activeViewId;
    if (id == null) return;
    await repo.updateView(id, config: config);
    await reload();
  }

  Future<void> createView(String name, te.ViewLayout layout) async {
    final id = await repo.createView(trackerId, name, te.ViewConfig(layout: layout));
    _set(_s.copyWith(activeViewId: id));
    await reload();
  }

  Future<void> renameView(String id, String name) async {
    await repo.updateView(id, name: name);
    await reload();
  }

  Future<void> deleteView(String id) async {
    try {
      await repo.deleteView(id);
      await reload();
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> setSearch(String text) async {
    _set(_s.copyWith(search: text));
    await reload();
  }
}

final trackerControllerProvider = AsyncNotifierProvider.family<TrackerController, TrackerScreenState, String>(TrackerController.new);
