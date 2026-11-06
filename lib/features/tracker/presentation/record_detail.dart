import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker_engine/tracker_engine.dart' as te;

import '../../../design_system/tokens.dart';
import '../application/tracker_controller.dart';
import 'cell_display.dart';
import 'cell_editors.dart';
import 'property_dialog.dart';
import 'tracker_table.dart' show rawEditText;
import 'tracker_views.dart';

/// Full record editor: every property, subtasks. Opened from the grid, a card or a list row.
class RecordDetail extends ConsumerWidget {
  const RecordDetail({super.key, required this.state, required this.recordId, required this.onClose, this.onOpenRecord});
  final TrackerScreenState state;
  final String recordId;
  final VoidCallback onClose;
  final ValueChanged<String>? onOpenRecord;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = state;
    final r = s.records.where((x) => x.id == recordId).firstOrNull;
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    if (r == null) {
      return Padding(padding: const EdgeInsets.all(Space.s24), child: Column(children: [Align(alignment: Alignment.topRight, child: IconButton(onPressed: onClose, icon: const Icon(Icons.close))), const Text('This record is no longer in the current view.')]));
    }
    final ctrl = ref.read(trackerControllerProvider(s.trackerId).notifier);
    final title = s.titleProperty;
    final children = [for (final x in s.records) if (x.parentId == r.id) x];

    return Material(
      color: c.surface,
      child: ListView(padding: const EdgeInsets.all(Space.s24), children: [
        Row(children: [
          Expanded(child: Text(titleOf(s, r), style: t.headlineSmall, maxLines: 2, overflow: TextOverflow.ellipsis)),
          IconButton(tooltip: 'Close', onPressed: onClose, icon: const Icon(Icons.close)),
        ]),
        const SizedBox(height: Space.s16),
        for (final p in s.properties)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.s4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              SizedBox(width: 120, child: Text(p.name, style: t.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
              Expanded(child: _Field(state: s, record: r, def: p, isTitle: p.id == title?.id)),
            ]),
          ),
        const Divider(height: Space.s32),
        Row(children: [
          Expanded(child: Text(children.isEmpty ? 'Subtasks' : 'Subtasks · ${children.length}', style: t.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis)),
          TextButton.icon(key: const Key('add-subtask'), onPressed: () => ctrl.addRecord(parentId: r.id), icon: const Icon(Icons.add, size: 18), label: const Text('Add subtask')),
        ]),
        for (final ch in children)
          ListTile(dense: true, contentPadding: EdgeInsets.zero, title: Text(titleOf(s, ch)), onTap: () => onOpenRecord?.call(ch.id)),
        if (r.parentId != null) ...[
          const Divider(height: Space.s32),
          ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: const Icon(Icons.subdirectory_arrow_left), title: const Text('Parent record'), onTap: () => onOpenRecord?.call(r.parentId!)),
        ],
        const SizedBox(height: Space.s24),
        Wrap(spacing: Space.s8, children: [
          OutlinedButton.icon(onPressed: () => ctrl.duplicateRecord(r.id), icon: const Icon(Icons.copy, size: 16), label: const Text('Duplicate')),
          OutlinedButton.icon(onPressed: () async { await ctrl.archiveRecords([r.id], !r.archived); }, icon: const Icon(Icons.inventory_2_outlined, size: 16), label: Text(r.archived ? 'Unarchive' : 'Archive')),
          OutlinedButton.icon(
            onPressed: () async {
              onClose();
              await ctrl.deleteRecords([r.id]);
            },
            icon: Icon(Icons.delete_outline, size: 16, color: c.danger),
            label: Text('Delete', style: TextStyle(color: c.danger)),
          ),
        ]),
      ]),
    );
  }
}

class _Field extends ConsumerWidget {
  const _Field({required this.state, required this.record, required this.def, required this.isTitle});
  final TrackerScreenState state;
  final te.TrackerRecord record;
  final te.PropertyDef def;
  final bool isTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(trackerControllerProvider(state.trackerId).notifier);
    final v = state.valueOf(record, def);
    if (def.type == te.PropertyType.checkbox) {
      return Align(alignment: Alignment.centerLeft, child: Switch(value: v == true, onChanged: (x) => ctrl.setCell(record.id, def.id, x)));
    }
    if (!isEditable(def)) return CellDisplay(def: def, value: v, titles: state.titles);
    if (usesPicker(def.type)) {
      return InkWell(
        key: Key('field-${def.id}'),
        onTap: () => openPicker(context, ref, state, record, def),
        child: Container(
          constraints: const BoxConstraints(minHeight: 36),
          alignment: Alignment.centerLeft,
          child: te.Values.isEmpty(v) ? Text('Empty', style: Theme.of(context).textTheme.bodySmall) : CellDisplay(def: def, value: v, titles: state.titles),
        ),
      );
    }
    return _TextField(key: ValueKey('tf-${record.id}-${def.id}-${rawEditText(def, v)}'), def: def, initial: rawEditText(def, v), onCommit: (text) => ctrl.setCellFromText(record.id, def.id, text), multiline: def.type == te.PropertyType.richText);
  }
}

class _TextField extends StatefulWidget {
  const _TextField({super.key, required this.def, required this.initial, required this.onCommit, this.multiline = false});
  final te.PropertyDef def;
  final String initial;
  final Future<bool> Function(String) onCommit;
  final bool multiline;
  @override
  State<_TextField> createState() => _TextFieldState();
}

class _TextFieldState extends State<_TextField> {
  late final _c = TextEditingController(text: widget.initial);
  final _f = FocusNode();

  @override
  void initState() {
    super.initState();
    _f.addListener(() {
      if (!_f.hasFocus) _commit();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    _f.dispose();
    super.dispose();
  }

  Future<void> _commit() async {
    if (_c.text == widget.initial) return;
    final ok = await widget.onCommit(_c.text);
    if (!ok && mounted) _c.text = widget.initial; // rejected: show what is actually stored
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _c,
        focusNode: _f,
        minLines: 1,
        maxLines: widget.multiline ? 6 : 1,
        decoration: const InputDecoration(isDense: true),
        onSubmitted: (_) => _commit(),
      );
}

Future<void> showAddProperty(BuildContext context, WidgetRef ref, TrackerScreenState s) => showPropertyDialog(context, ref, s);
