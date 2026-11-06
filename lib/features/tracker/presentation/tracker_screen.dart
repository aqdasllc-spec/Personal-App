import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker_engine/tracker_engine.dart' as te;

import '../../../design_system/components.dart';
import '../../../design_system/tokens.dart';
import '../application/tracker_controller.dart';
import 'prompt_dialog.dart';
import 'property_dialog.dart';
import 'record_detail.dart';
import 'tracker_table.dart';
import 'tracker_views.dart';
import 'view_options_sheet.dart';

const _implementedLayouts = {te.ViewLayout.table, te.ViewLayout.kanban, te.ViewLayout.list};

String _layoutLabel(te.ViewLayout l) => switch (l) {
      te.ViewLayout.table => 'Table',
      te.ViewLayout.kanban => 'Board',
      te.ViewLayout.list => 'List',
      te.ViewLayout.calendar => 'Calendar',
      te.ViewLayout.timeline => 'Timeline',
      te.ViewLayout.gantt => 'Gantt',
      te.ViewLayout.gallery => 'Gallery',
    };

class TrackerScreen extends ConsumerStatefulWidget {
  const TrackerScreen({super.key, required this.trackerId, required this.name, this.onBack});
  final String trackerId;
  final String name;
  final VoidCallback? onBack;
  @override
  ConsumerState<TrackerScreen> createState() => _TrackerScreenState();
}

class _TrackerScreenState extends ConsumerState<TrackerScreen> {
  String? _open; // record shown in the detail panel
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  TrackerController get _ctrl => ref.read(trackerControllerProvider(widget.trackerId).notifier);

  void _openRecord(String id) {
    final wide = MediaQuery.sizeOf(context).width >= 1100;
    if (wide) {
      setState(() => _open = id);
    } else {
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _NarrowDetail(trackerId: widget.trackerId, name: widget.name, initialId: id)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(trackerControllerProvider(widget.trackerId));
    ref.listen(trackerControllerProvider(widget.trackerId), (prev, next) {
      final m = next.value?.message;
      if (m != null && m != prev?.value?.message) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));
        _ctrl.clearMessage();
      }
    });
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => EmptyState(icon: Icons.error_outline, title: 'Couldn\'t open this tracker', message: 'Your data is safe. Try again, or restart the app.', actionLabel: 'Retry', onAction: () => ref.invalidate(trackerControllerProvider(widget.trackerId))),
      data: _content,
    );
  }

  Widget _content(TrackerScreenState s) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final wide = MediaQuery.sizeOf(context).width >= 1100;
    final layout = s.effectiveView.layout;
    final v = s.effectiveView;
    final activeFilters = v.filter.children.length + v.sorts.length + (v.groupBy != null ? 1 : 0);

    Widget body;
    if (!_implementedLayouts.contains(layout)) {
      body = EmptyState(
        icon: Icons.construction_outlined,
        title: '${_layoutLabel(layout)} view is coming',
        message: 'This layout is planned for Phase 3. Your records are safe; switch to Table, Board or List to keep working.',
        actionLabel: 'Switch to ${_layoutLabel(te.ViewLayout.table)}',
        onAction: () => _ctrl.updateView(v.copyWith(layout: te.ViewLayout.table)),
      );
    } else if (layout == te.ViewLayout.kanban) {
      body = KanbanView(state: s, onOpenRecord: _openRecord);
    } else if (layout == te.ViewLayout.list) {
      body = RecordListView(state: s, onOpenRecord: _openRecord);
    } else if (s.properties.isEmpty) {
      body = EmptyState(icon: Icons.view_column_outlined, title: 'No properties yet', message: 'Add the first column to start tracking.', actionLabel: 'Add property', onAction: () => showPropertyDialog(context, ref, s));
    } else {
      final table = TrackerTable(state: s, onOpenRecord: _openRecord);
      final blank = s.records.isEmpty && s.search.isEmpty && activeFilters == 0;
      // headers stay visible so a new tracker can be designed right away; the hint sits under them
      body = blank
          ? Stack(children: [
              Positioned.fill(child: table),
              Positioned(
                left: 0,
                right: 0,
                top: 140,
                child: IgnorePointer(
                  child: Column(children: [
                    Text('No rows yet', style: t.titleMedium),
                    const SizedBox(height: Space.s4),
                    Text('Click “New row” to add the first one, then click any cell to edit it.', style: t.bodySmall, textAlign: TextAlign.center),
                  ]),
                ),
              ),
            ])
          : table;
    }

    final main = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(Space.s16, Space.s12, Space.s16, 0),
        child: Row(children: [
          if (widget.onBack != null) IconButton(tooltip: 'Back to trackers', onPressed: widget.onBack, icon: const Icon(Icons.arrow_back)),
          Expanded(child: Text(widget.name, style: t.headlineSmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
          Chip(label: Text('${s.total} record${s.total == 1 ? '' : 's'}'), visualDensity: VisualDensity.compact),
          IconButton(tooltip: s.undoLabel == null ? 'Undo' : 'Undo: ${s.undoLabel}', onPressed: s.canUndo ? _ctrl.undo : null, icon: const Icon(Icons.undo)),
          IconButton(tooltip: 'Redo', onPressed: s.canRedo ? _ctrl.redo : null, icon: const Icon(Icons.redo)),
        ]),
      ),
      SizedBox(
        height: 44,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: Space.s12), children: [
          for (final e in s.views)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.s4, vertical: Space.s4),
              child: GestureDetector(
                onLongPress: () => _viewMenu(e),
                onSecondaryTap: () => _viewMenu(e),
                child: ChoiceChip(key: Key('view-${e.name}'), label: Text(e.name), selected: e.id == s.activeViewId, onSelected: (_) => _ctrl.setActiveView(e.id)),
              ),
            ),
          PopupMenuButton<te.ViewLayout>(
            key: const Key('new-view'),
            tooltip: 'Add a view',
            icon: const Icon(Icons.add),
            onSelected: (l) => _ctrl.createView(_layoutLabel(l), l),
            itemBuilder: (_) => [
              for (final l in te.ViewLayout.values) PopupMenuItem(value: l, enabled: _implementedLayouts.contains(l), child: Text(_implementedLayouts.contains(l) ? _layoutLabel(l) : '${_layoutLabel(l)} (Phase 3)')),
            ],
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(Space.s16, Space.s4, Space.s16, Space.s8),
        child: LayoutBuilder(builder: (context, box) {
          final narrow = box.maxWidth < 640;
          final options = OutlinedButton.icon(
            key: const Key('view-options'),
            onPressed: () => showViewOptions(context, ref, s),
            icon: const Icon(Icons.tune, size: 18),
            label: Text(activeFilters == 0 ? (narrow ? 'Options' : 'Filter · Sort · Group') : (narrow ? 'Options ($activeFilters)' : 'Filter · Sort · Group ($activeFilters)')),
          );
          final search = TextField(
            key: const Key('tracker-search'),
            controller: _search,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search this tracker',
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: s.search.isEmpty ? null : IconButton(tooltip: 'Clear search', icon: const Icon(Icons.close, size: 18), onPressed: () { _search.clear(); _ctrl.setSearch(''); }),
            ),
            onChanged: (x) => _ctrl.setSearch(x),
          );
          final add = FilledButton.icon(
            key: const Key('add-record'),
            onPressed: () async {
              final id = await _ctrl.addRecord();
              if (id != null && s.titleProperty != null) _ctrl.setActive(ActiveCell(id, s.titleProperty!.id));
            },
            icon: const Icon(Icons.add, size: 18),
            label: const Text('New'),
          );
          if (narrow) {
            return Column(children: [
              Row(children: [
                Flexible(child: options),
                // the table's own "+" column is off-screen on a phone, so offer it here too
                IconButton(tooltip: 'Add property', onPressed: () => showPropertyDialog(context, ref, s), icon: const Icon(Icons.view_column_outlined)),
                const Spacer(),
                add,
              ]),
              const SizedBox(height: Space.s8),
              search,
            ]);
          }
          return Row(children: [options, const SizedBox(width: Space.s8), Expanded(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 320), child: search)), const Spacer(), add]);
        }),
      ),
      Expanded(child: Stack(children: [
        Positioned.fill(child: body),
        if (s.selected.isNotEmpty) Positioned(left: 0, right: 0, bottom: Space.s16, child: Center(child: _BulkBar(state: s))),
      ])),
      if (s.total > s.records.length)
        Padding(padding: const EdgeInsets.all(Space.s8), child: Text('Showing the first ${s.records.length} of ${s.total} records. Use filters or search to narrow down.', style: t.bodySmall, textAlign: TextAlign.center)),
    ]);

    if (wide && _open != null) {
      return Row(children: [
        Expanded(child: main),
        SizedBox(width: 400, child: DecoratedBox(decoration: BoxDecoration(border: Border(left: BorderSide(color: c.border))), child: RecordDetail(state: s, recordId: _open!, onClose: () => setState(() => _open = null), onOpenRecord: (id) => setState(() => _open = id)))),
      ]);
    }
    return main;
  }

  Future<void> _viewMenu(ViewEntry e) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(title: Text(e.name), children: [
        SimpleDialogOption(onPressed: () => Navigator.pop(dialogContext, 'rename'), child: const Text('Rename view')),
        SimpleDialogOption(onPressed: () => Navigator.pop(dialogContext, 'delete'), child: const Text('Delete view')),
      ]),
    );
    if (!mounted) return;
    if (choice == 'delete') await _ctrl.deleteView(e.id);
    if (choice == 'rename') {
      if (!mounted) return;
      final name = await promptText(context, title: 'Rename view', initial: e.name, action: 'Rename');
      if (name != null) await _ctrl.renameView(e.id, name);
    }
  }
}

class _BulkBar extends ConsumerWidget {
  const _BulkBar({required this.state});
  final TrackerScreenState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final ctrl = ref.read(trackerControllerProvider(state.trackerId).notifier);
    final ids = state.selected.toList();
    final style = TextStyle(color: c.bg);
    return Material(
      color: c.text,
      elevation: 6,
      borderRadius: BorderRadius.circular(Radii.sheet),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.s12, vertical: Space.s4),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('${ids.length} selected', key: const Key('selected-count'), style: style),
          const SizedBox(width: Space.s8),
          TextButton(onPressed: () => showDialog<void>(context: context, builder: (_) => _BulkSetDialog(state: state)), child: Text('Set value…', style: style)),
          TextButton(onPressed: () => ctrl.archiveRecords(ids, true), child: Text('Archive', style: style)),
          TextButton(key: const Key('bulk-delete'), onPressed: () => ctrl.deleteRecords(ids), child: Text('Delete', style: style)),
          IconButton(tooltip: 'Clear selection', onPressed: ctrl.clearSelection, icon: Icon(Icons.close, color: c.bg, size: 18)),
        ]),
      ),
    );
  }
}

class _BulkSetDialog extends ConsumerStatefulWidget {
  const _BulkSetDialog({required this.state});
  final TrackerScreenState state;
  @override
  ConsumerState<_BulkSetDialog> createState() => _BulkSetDialogState();
}

class _BulkSetDialogState extends ConsumerState<_BulkSetDialog> {
  te.PropertyDef? _prop;
  String? _option;
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final props = [for (final p in widget.state.properties) if (p.type.isStored && p.type != te.PropertyType.person && p.type != te.PropertyType.files && p.type != te.PropertyType.image) p];
    final p = _prop;
    return AlertDialog(
      title: Text('Set value for ${widget.state.selected.length} rows'),
      content: SizedBox(
        width: 360,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<te.PropertyDef>(
            key: const Key('bulk-property'),
            initialValue: p,
            decoration: const InputDecoration(labelText: 'Property'),
            items: [for (final x in props) DropdownMenuItem(value: x, child: Text(x.name))],
            onChanged: (x) => setState(() {
              _prop = x;
              _option = null;
              _text.clear();
            }),
          ),
          const SizedBox(height: Space.s12),
          if (p != null && (p.type == te.PropertyType.select || p.type == te.PropertyType.status))
            DropdownButtonFormField<String?>(
              key: const Key('bulk-option'),
              initialValue: _option,
              decoration: const InputDecoration(labelText: 'Value'),
              items: [const DropdownMenuItem(value: null, child: Text('(empty)')), for (final o in p.options) DropdownMenuItem(value: o.id, child: Text(o.label))],
              onChanged: (x) => setState(() => _option = x),
            )
          else if (p != null)
            TextField(key: const Key('bulk-text'), controller: _text, decoration: InputDecoration(labelText: 'Value', helperText: p.type == te.PropertyType.checkbox ? 'yes / no' : null)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          key: const Key('bulk-apply'),
          onPressed: p == null
              ? null
              : () async {
                  final ctrl = ref.read(trackerControllerProvider(widget.state.trackerId).notifier);
                  te.CellValue value;
                  if (p.type == te.PropertyType.select || p.type == te.PropertyType.status) {
                    value = _option;
                  } else {
                    final r = te.Values.parseText(p, _text.text);
                    if (r.error != null || r.newOptionLabel != null) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r.error ?? 'That isn\'t one of the options.')));
                      return;
                    }
                    value = r.value;
                  }
                  await ctrl.setCellForSelected(p.id, value);
                  if (context.mounted) Navigator.pop(context);
                },
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

/// Full-screen record editor for narrow windows. Follows links to parent/subtask records in place.
class _NarrowDetail extends ConsumerStatefulWidget {
  const _NarrowDetail({required this.trackerId, required this.name, required this.initialId});
  final String trackerId;
  final String name;
  final String initialId;
  @override
  ConsumerState<_NarrowDetail> createState() => _NarrowDetailState();
}

class _NarrowDetailState extends ConsumerState<_NarrowDetail> {
  late String _id = widget.initialId;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(trackerControllerProvider(widget.trackerId)).value;
    return Scaffold(
      appBar: AppBar(title: Text(widget.name)),
      body: s == null
          ? const Center(child: CircularProgressIndicator())
          : RecordDetail(state: s, recordId: _id, onClose: () => Navigator.of(context).maybePop(), onOpenRecord: (x) => setState(() => _id = x)),
    );
  }
}
