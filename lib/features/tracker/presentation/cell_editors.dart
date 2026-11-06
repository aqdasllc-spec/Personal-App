import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker_engine/tracker_engine.dart' as te;

import '../../../design_system/tokens.dart';
import '../application/tracker_controller.dart';
import 'cell_display.dart';

/// Property types edited through a popup instead of an inline text field.
bool usesPicker(te.PropertyType t) => const {
      te.PropertyType.select,
      te.PropertyType.status,
      te.PropertyType.multiSelect,
      te.PropertyType.date,
      te.PropertyType.dateRange,
      te.PropertyType.relation,
    }.contains(t);

bool isEditable(te.PropertyDef d) => d.type.isStored || d.type == te.PropertyType.relation;

/// Opens the right editor for [def] on [recordId]. Checkboxes toggle immediately; text-like
/// types are edited inline by the grid, not here.
Future<void> openPicker(BuildContext context, WidgetRef ref, TrackerScreenState s, te.TrackerRecord r, te.PropertyDef def) async {
  final ctrl = ref.read(trackerControllerProvider(s.trackerId).notifier);
  switch (def.type) {
    case te.PropertyType.select:
    case te.PropertyType.status:
      final picked = await showDialog<_Pick>(context: context, builder: (_) => _SingleOptionDialog(def: def, current: r.cells[def.id] as String?, ctrl: ctrl));
      if (picked != null) await ctrl.setCell(r.id, def.id, picked.value);
    case te.PropertyType.multiSelect:
      final cur = ((r.cells[def.id] as List?) ?? const []).cast<String>();
      final picked = await showDialog<List<String>>(context: context, builder: (_) => _MultiOptionDialog(def: def, current: cur, ctrl: ctrl));
      if (picked != null) await ctrl.setCell(r.id, def.id, picked.isEmpty ? null : picked);
    case te.PropertyType.date:
      await _pickDate(context, ctrl, r, def);
    case te.PropertyType.dateRange:
      final cur = r.cells[def.id] as Map?;
      final init = cur == null
          ? null
          : DateTimeRange(start: te.parseDate(cur['start'] as String)!, end: te.parseDate((cur['end'] ?? cur['start']) as String)!);
      final range = await showDateRangePicker(context: context, firstDate: DateTime(1900), lastDate: DateTime(2200), initialDateRange: init, helpText: def.name);
      if (range != null) {
        String d(DateTime x) => '${x.year.toString().padLeft(4, '0')}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';
        await ctrl.setCell(r.id, def.id, {'start': d(range.start), 'end': d(range.end)});
      }
    case te.PropertyType.relation:
      final cands = await ctrl.relationCandidates(def);
      final cur = await ctrl.currentLinks(def.id, r.id);
      if (!context.mounted) return;
      final picked = await showDialog<List<String>>(context: context, builder: (_) => _RelationDialog(def: def, candidates: cands, current: cur));
      if (picked != null) await ctrl.setLinks(def.id, r.id, picked);
    default:
  }
}

Future<void> _pickDate(BuildContext context, TrackerController ctrl, te.TrackerRecord r, te.PropertyDef def) async {
  final cur = r.cells[def.id] as String?;
  final init = (cur == null ? null : te.parseDate(cur)) ?? DateTime.now();
  final picked = await showDatePicker(context: context, firstDate: DateTime(1900), lastDate: DateTime(2200), initialDate: DateTime.utc(init.year, init.month, init.day), helpText: def.name);
  if (picked != null) {
    final iso = '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    await ctrl.setCell(r.id, def.id, iso);
  }
}

class _Pick {
  const _Pick(this.value);
  final String? value; // null = clear
}

class _SingleOptionDialog extends StatefulWidget {
  const _SingleOptionDialog({required this.def, required this.current, required this.ctrl});
  final te.PropertyDef def;
  final String? current;
  final TrackerController ctrl;
  @override
  State<_SingleOptionDialog> createState() => _SingleOptionDialogState();
}

class _SingleOptionDialogState extends State<_SingleOptionDialog> {
  late te.PropertyDef def = widget.def;
  final _new = TextEditingController();

  @override
  void dispose() {
    _new.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final id = await widget.ctrl.createOption(def.id, _new.text);
    if (id != null && mounted) Navigator.pop(context, _Pick(id));
  }

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: Text(def.name),
      children: [
        for (final o in def.options)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, _Pick(o.id)),
            child: Row(children: [
              OptionPill(label: o.label, color: o.color),
              const Spacer(),
              if (o.id == widget.current) const Icon(Icons.check, size: 18),
            ]),
          ),
        if (widget.current != null) SimpleDialogOption(onPressed: () => Navigator.pop(context, const _Pick(null)), child: const Text('Clear')),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.s24, Space.s8, Space.s24, Space.s8),
          child: TextField(
            controller: _new,
            decoration: const InputDecoration(hintText: 'New option…', isDense: true),
            onSubmitted: (_) => _create(),
          ),
        ),
      ],
    );
  }
}

class _MultiOptionDialog extends StatefulWidget {
  const _MultiOptionDialog({required this.def, required this.current, required this.ctrl});
  final te.PropertyDef def;
  final List<String> current;
  final TrackerController ctrl;
  @override
  State<_MultiOptionDialog> createState() => _MultiOptionDialogState();
}

class _MultiOptionDialogState extends State<_MultiOptionDialog> {
  late final Set<String> _sel = {...widget.current};
  late te.PropertyDef def = widget.def;
  final _new = TextEditingController();

  @override
  void dispose() {
    _new.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final id = await widget.ctrl.createOption(def.id, _new.text);
    if (id == null) return;
    final fresh = (await widget.ctrl.propertiesOf(widget.ctrl.trackerId)).firstWhere((p) => p.id == def.id);
    if (mounted) {
      setState(() {
        def = fresh;
        _sel.add(id);
        _new.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(def.name),
      content: SizedBox(
        width: 320,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              for (final o in def.options)
                CheckboxListTile(
                  dense: true,
                  value: _sel.contains(o.id),
                  onChanged: (v) => setState(() => v == true ? _sel.add(o.id) : _sel.remove(o.id)),
                  title: Align(alignment: Alignment.centerLeft, child: OptionPill(label: o.label, color: o.color)),
                ),
            ]),
          ),
          TextField(controller: _new, decoration: const InputDecoration(hintText: 'New option…', isDense: true), onSubmitted: (_) => _create()),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(context, [for (final o in def.options) if (_sel.contains(o.id)) o.id, for (final id in _sel) if (def.option(id) == null) id]),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

class _RelationDialog extends StatefulWidget {
  const _RelationDialog({required this.def, required this.candidates, required this.current});
  final te.PropertyDef def;
  final List<(String, String)> candidates;
  final List<String> current;
  @override
  State<_RelationDialog> createState() => _RelationDialogState();
}

class _RelationDialogState extends State<_RelationDialog> {
  late final List<String> _sel = [...widget.current];
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final many = widget.def.relationAllowsMany;
    final shown = [for (final c in widget.candidates) if (te.foldText(c.$2).contains(te.foldText(_q))) c];
    return AlertDialog(
      title: Text(widget.def.name),
      content: SizedBox(
        width: 340,
        height: 360,
        child: Column(children: [
          TextField(decoration: const InputDecoration(hintText: 'Search…', prefixIcon: Icon(Icons.search), isDense: true), onChanged: (v) => setState(() => _q = v)),
          const SizedBox(height: Space.s8),
          Expanded(
            child: shown.isEmpty
                ? const Center(child: Text('Nothing to link yet.'))
                : ListView(children: [
                    for (final c in shown)
                      CheckboxListTile(
                        dense: true,
                        value: _sel.contains(c.$1),
                        title: Text(c.$2),
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            if (!many) _sel.clear();
                            _sel.add(c.$1);
                          } else {
                            _sel.remove(c.$1);
                          }
                        }),
                      ),
                  ]),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, _sel), child: const Text('Done')),
      ],
    );
  }
}
