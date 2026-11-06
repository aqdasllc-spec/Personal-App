import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker_engine/tracker_engine.dart' as te;

import '../../../design_system/option_colors.dart';
import '../../../design_system/tokens.dart';
import '../application/tracker_controller.dart';
import 'cell_display.dart';

const _typeLabels = <te.PropertyType, String>{
  te.PropertyType.text: 'Text',
  te.PropertyType.richText: 'Long text',
  te.PropertyType.number: 'Number',
  te.PropertyType.currency: 'Currency',
  te.PropertyType.percent: 'Percentage',
  te.PropertyType.checkbox: 'Checkbox',
  te.PropertyType.date: 'Date',
  te.PropertyType.dateRange: 'Date range',
  te.PropertyType.url: 'URL',
  te.PropertyType.email: 'Email',
  te.PropertyType.phone: 'Phone',
  te.PropertyType.select: 'Select',
  te.PropertyType.multiSelect: 'Multi-select',
  te.PropertyType.status: 'Status',
  te.PropertyType.progress: 'Progress',
  te.PropertyType.person: 'People',
  te.PropertyType.files: 'Files',
  te.PropertyType.image: 'Images',
  te.PropertyType.relation: 'Relation',
  te.PropertyType.rollup: 'Rollup',
  te.PropertyType.formula: 'Formula',
  te.PropertyType.createdTime: 'Created time',
  te.PropertyType.lastEditedTime: 'Last edited',
};

String typeLabel(te.PropertyType t) => _typeLabels[t] ?? t.name;

const _aggregates = <String, String>{
  'count': 'Count of records',
  'countNotEmpty': 'Count not empty',
  'countEmpty': 'Count empty',
  'countUnique': 'Count unique values',
  'sum': 'Sum',
  'avg': 'Average',
  'min': 'Minimum',
  'max': 'Maximum',
  'median': 'Median',
  'percentChecked': 'Percent checked',
  'percentComplete': 'Percent complete (status)',
  'earliest': 'Earliest date',
  'latest': 'Latest date',
  'showOriginal': 'Show original values',
};

/// Add a property, or edit an existing one (its type is fixed after creation).
Future<void> showPropertyDialog(BuildContext context, WidgetRef ref, TrackerScreenState s, {te.PropertyDef? existing}) {
  return showDialog<void>(context: context, builder: (_) => _PropertyDialog(state: s, existing: existing));
}

class _PropertyDialog extends ConsumerStatefulWidget {
  const _PropertyDialog({required this.state, this.existing});
  final TrackerScreenState state;
  final te.PropertyDef? existing;
  @override
  ConsumerState<_PropertyDialog> createState() => _PropertyDialogState();
}

class _PropertyDialogState extends ConsumerState<_PropertyDialog> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late te.PropertyType _type = widget.existing?.type ?? te.PropertyType.text;
  late Map<String, Object?> _cfg = {...?widget.existing?.config};
  late final _formula = TextEditingController(text: widget.existing == null ? '' : te.displayFormula(widget.existing!.formulaSource, widget.state.properties));
  final _reverse = TextEditingController();
  final _prefix = TextEditingController();
  final _suffix = TextEditingController();
  final _symbol = TextEditingController();
  List<(String, String)> _trackers = const [];
  List<te.PropertyDef> _targetProps = const [];
  bool _busy = false;

  bool get _editing => widget.existing != null;
  TrackerController get _ctrl => ref.read(trackerControllerProvider(widget.state.trackerId).notifier);

  @override
  void initState() {
    super.initState();
    _prefix.text = (_cfg['prefix'] as String?) ?? '';
    _suffix.text = (_cfg['suffix'] as String?) ?? '';
    _symbol.text = (_cfg['symbol'] as String?) ?? r'$';
    _ctrl.trackerChoices().then((t) {
      if (mounted) setState(() => _trackers = t);
    });
    _loadTargetProps();
  }

  Future<void> _loadTargetProps() async {
    final relId = _cfg['relationPropertyId'] as String?;
    final rel = widget.state.properties.where((p) => p.id == relId).firstOrNull;
    final target = rel?.relationTargetTrackerId;
    if (target == null) return;
    final props = await _ctrl.propertiesOf(target);
    if (mounted) setState(() => _targetProps = props);
  }

  @override
  void dispose() {
    for (final c in [_name, _formula, _reverse, _prefix, _suffix, _symbol]) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, Object?> _finalConfig() {
    final c = {..._cfg};
    switch (_type) {
      case te.PropertyType.number:
        c['prefix'] = _prefix.text;
        c['suffix'] = _suffix.text;
      case te.PropertyType.currency:
        c['symbol'] = _symbol.text.isEmpty ? r'$' : _symbol.text;
      case te.PropertyType.formula:
        c['formula'] = te.canonicalizeFormula(_formula.text, widget.state.properties);
      default:
    }
    return c;
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    var ok = true;
    if (_editing) {
      ok = await _ctrl.updateProperty(widget.existing!.id, name: _name.text, config: _finalConfig());
    } else if (_type == te.PropertyType.relation) {
      final target = _cfg['targetTrackerId'] as String?;
      if (target == null) {
        setState(() => _busy = false);
        return;
      }
      await _ctrl.addRelation(_name.text.trim().isEmpty ? 'Relation' : _name.text, target, _reverse.text.trim().isEmpty ? 'Related' : _reverse.text, many: _cfg['many'] != false);
    } else {
      ok = await _ctrl.addProperty(_name.text, _type, _finalConfig()) != null;
    }
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
    } else {
      setState(() => _busy = false); // the screen shows the validation message
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AlertDialog(
      title: Text(_editing ? 'Edit property' : 'New property'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(controller: _name, autofocus: true, decoration: const InputDecoration(labelText: 'Name'), onSubmitted: (_) => _save()),
            const SizedBox(height: Space.s16),
            if (_editing)
              Text('Type: ${typeLabel(_type)}', style: Theme.of(context).textTheme.bodySmall)
            else
              DropdownButtonFormField<te.PropertyType>(
                key: const Key('property-type'),
                initialValue: _type,
                decoration: const InputDecoration(labelText: 'Type'),
                items: [for (final t in te.PropertyType.values) DropdownMenuItem(value: t, child: Text(typeLabel(t)))],
                onChanged: (t) => setState(() {
                  _type = t!;
                  _cfg = {};
                }),
              ),
            const SizedBox(height: Space.s16),
            ..._configFor(context, c),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _busy ? null : _save, child: Text(_editing ? 'Save' : 'Add property')),
      ],
    );
  }

  List<Widget> _configFor(BuildContext context, FolioColors c) {
    switch (_type) {
      case te.PropertyType.number:
        return [
          _intField('Decimals', 'decimals', 0, 6),
          const SizedBox(height: Space.s8),
          Row(children: [
            Expanded(child: TextField(controller: _prefix, decoration: const InputDecoration(labelText: 'Prefix'))),
            const SizedBox(width: Space.s8),
            Expanded(child: TextField(controller: _suffix, decoration: const InputDecoration(labelText: 'Suffix'))),
          ]),
        ];
      case te.PropertyType.currency:
        return [
          TextField(controller: _symbol, decoration: const InputDecoration(labelText: 'Currency symbol')),
          const SizedBox(height: Space.s8),
          _intField('Decimals', 'decimals', 0, 4, fallback: 2),
        ];
      case te.PropertyType.percent:
        return [
          _intField('Decimals', 'decimals', 0, 4),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Stored as a fraction (0–1)'), value: _cfg['fraction'] == true, onChanged: (v) => setState(() => _cfg['fraction'] = v)),
        ];
      case te.PropertyType.date:
        return [SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Include time'), value: _cfg['includeTime'] == true, onChanged: (v) => setState(() => _cfg['includeTime'] = v))];
      case te.PropertyType.select:
      case te.PropertyType.multiSelect:
      case te.PropertyType.status:
        return [_OptionsEditor(options: [for (final o in (_cfg['options'] as List? ?? const [])) te.SelectOption.fromJson(Map<String, Object?>.from(o as Map))], status: _type == te.PropertyType.status, onChanged: (o) => setState(() => _cfg = {..._cfg, ...te.Cfg.options(o)}))];
      case te.PropertyType.relation:
        if (_editing) {
          return [Text('Links to another tracker. Allow many: ${widget.existing!.relationAllowsMany ? 'yes' : 'no'}', style: Theme.of(context).textTheme.bodySmall)];
        }
        return [
          DropdownButtonFormField<String>(
            key: const Key('relation-target'),
            initialValue: _cfg['targetTrackerId'] as String?,
            decoration: const InputDecoration(labelText: 'Links to tracker'),
            items: [for (final t in _trackers) DropdownMenuItem(value: t.$1, child: Text(t.$2))],
            onChanged: (v) => setState(() => _cfg['targetTrackerId'] = v),
          ),
          if (_trackers.isEmpty) Padding(padding: const EdgeInsets.only(top: Space.s8), child: Text('Create another tracker first to link to it.', style: Theme.of(context).textTheme.bodySmall)),
          const SizedBox(height: Space.s8),
          TextField(controller: _reverse, decoration: const InputDecoration(labelText: 'Name of the matching property in the other tracker')),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Allow several links per record'), value: _cfg['many'] != false, onChanged: (v) => setState(() => _cfg['many'] = v)),
        ];
      case te.PropertyType.rollup:
        final rels = widget.state.properties.where((p) => p.type == te.PropertyType.relation).toList();
        if (rels.isEmpty) return [Text('Add a relation property first; a rollup summarises the linked records.', style: Theme.of(context).textTheme.bodySmall)];
        final agg = (_cfg['aggregate'] as String?) ?? 'count';
        return [
          DropdownButtonFormField<String>(
            key: const Key('rollup-relation'),
            initialValue: _cfg['relationPropertyId'] as String?,
            decoration: const InputDecoration(labelText: 'Relation'),
            items: [for (final r in rels) DropdownMenuItem(value: r.id, child: Text(r.name))],
            onChanged: (v) {
              setState(() {
                _cfg['relationPropertyId'] = v;
                _cfg.remove('targetPropertyId');
                _targetProps = const [];
              });
              _loadTargetProps();
            },
          ),
          const SizedBox(height: Space.s8),
          DropdownButtonFormField<String>(
            key: const Key('rollup-aggregate'),
            initialValue: agg,
            decoration: const InputDecoration(labelText: 'Calculate'),
            items: [for (final e in _aggregates.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) => setState(() => _cfg['aggregate'] = v),
          ),
          if (agg != 'count') ...[
            const SizedBox(height: Space.s8),
            DropdownButtonFormField<String>(
              key: const Key('rollup-target'),
              initialValue: _targetProps.any((p) => p.id == _cfg['targetPropertyId']) ? _cfg['targetPropertyId'] as String? : null,
              decoration: const InputDecoration(labelText: 'Property'),
              items: [for (final p in _targetProps) DropdownMenuItem(value: p.id, child: Text(p.name))],
              onChanged: (v) => setState(() => _cfg['targetPropertyId'] = v),
            ),
          ],
        ];
      case te.PropertyType.formula:
        return [
          TextField(
            key: const Key('formula-field'),
            controller: _formula,
            minLines: 2,
            maxLines: 5,
            style: const TextStyle(fontFamily: 'JetBrains Mono', fontFamilyFallback: ['Consolas', 'Menlo', 'monospace'], fontSize: 13),
            decoration: const InputDecoration(labelText: 'Formula', hintText: 'prop("Hours") * 2', alignLabelWithHint: true),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: Space.s8),
          _FormulaPreview(source: _formula.text, state: widget.state, selfId: widget.existing?.id),
        ];
      default:
        return [Text(_hint(_type), style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.textMuted))];
    }
  }

  String _hint(te.PropertyType t) => switch (t) {
        te.PropertyType.createdTime => 'Filled in automatically when a record is created.',
        te.PropertyType.lastEditedTime => 'Updated automatically whenever a record changes.',
        te.PropertyType.checkbox => 'A simple yes/no tick box.',
        te.PropertyType.progress => 'A 0–100 progress bar.',
        _ => 'No extra settings.',
      };

  Widget _intField(String label, String key, int min, int max, {int fallback = 0}) {
    final v = (_cfg[key] as int?) ?? fallback;
    return Row(children: [
      Expanded(child: Text(label)),
      IconButton(tooltip: 'Fewer', onPressed: v > min ? () => setState(() => _cfg[key] = v - 1) : null, icon: const Icon(Icons.remove)),
      SizedBox(width: 24, child: Text('$v', textAlign: TextAlign.center)),
      IconButton(tooltip: 'More', onPressed: v < max ? () => setState(() => _cfg[key] = v + 1) : null, icon: const Icon(Icons.add)),
    ]);
  }
}

class _FormulaPreview extends StatelessWidget {
  const _FormulaPreview({required this.source, required this.state, this.selfId});
  final String source;
  final TrackerScreenState state;
  final String? selfId;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (source.trim().isEmpty) return Text('Reference properties with prop("Name"). Functions: if, concat, round, dateBetween, today, sum…', style: Theme.of(context).textTheme.bodySmall);
    final canon = te.canonicalizeFormula(source, state.properties);
    try {
      te.parseFormula(canon);
    } on te.FormulaSyntaxException catch (e) {
      return Text('✗ ${e.message}', key: const Key('formula-status'), style: TextStyle(color: c.danger, fontSize: 12));
    }
    final probe = te.PropertyDef(id: selfId ?? '__preview__', name: 'preview', type: te.PropertyType.formula, config: {'formula': canon});
    final defs = [for (final d in state.properties) if (d.id != selfId) d, probe];
    try {
      te.formulaOrder(defs);
    } on te.FormulaCycleException catch (e) {
      return Text('✗ $e', key: const Key('formula-status'), style: TextStyle(color: c.danger, fontSize: 12));
    }
    final rec = state.records.firstOrNull;
    if (rec == null) return Text('✓ Valid. Add a row to see a preview.', key: const Key('formula-status'), style: TextStyle(color: c.ok, fontSize: 12));
    final snap = te.TrackerSnapshot(trackerId: state.trackerId, properties: defs, records: [rec]);
    final v = te.Computed(snap).valueOf(rec, probe);
    final shown = v is te.FormulaError ? v.toString() : (v == null ? 'empty' : v.toString());
    return Text('${v is te.FormulaError ? '⚠' : '✓'} Preview for this first row: $shown', key: const Key('formula-status'), style: TextStyle(color: v is te.FormulaError ? c.warn : c.ok, fontSize: 12));
  }
}

class _OptionsEditor extends StatelessWidget {
  const _OptionsEditor({required this.options, required this.status, required this.onChanged});
  final List<te.SelectOption> options;
  final bool status;
  final ValueChanged<List<te.SelectOption>> onChanged;

  @override
  Widget build(BuildContext context) {
    void replace(int i, te.SelectOption o) => onChanged([...options]..[i] = o);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Options', style: Theme.of(context).textTheme.labelLarge),
      for (var i = 0; i < options.length; i++)
        Padding(
          key: ValueKey('opt-${options[i].id}'),
          padding: const EdgeInsets.only(top: Space.s8),
          child: Row(children: [
            PopupMenuButton<String>(
              tooltip: 'Colour',
              onSelected: (name) => replace(i, te.SelectOption(id: options[i].id, label: options[i].label, color: name, group: options[i].group)),
              itemBuilder: (_) => [for (final n in OptionColors.names) PopupMenuItem(value: n, child: OptionPill(label: n, color: n))],
              child: CircleAvatar(radius: 9, backgroundColor: OptionColors.of(options[i].color, Theme.of(context).brightness).$2),
            ),
            const SizedBox(width: Space.s8),
            Expanded(
              child: TextFormField(
                initialValue: options[i].label,
                decoration: const InputDecoration(isDense: true),
                onChanged: (v) => replace(i, te.SelectOption(id: options[i].id, label: v, color: options[i].color, group: options[i].group)),
              ),
            ),
            if (status)
              PopupMenuButton<te.StatusGroup>(
                tooltip: 'Group',
                initialValue: options[i].group,
                onSelected: (g) => replace(i, te.SelectOption(id: options[i].id, label: options[i].label, color: options[i].color, group: g)),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: te.StatusGroup.todo, child: Text('To do')),
                  PopupMenuItem(value: te.StatusGroup.inProgress, child: Text('In progress')),
                  PopupMenuItem(value: te.StatusGroup.complete, child: Text('Complete')),
                ],
                child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Text(switch (options[i].group) { te.StatusGroup.inProgress => 'In progress', te.StatusGroup.complete => 'Complete', _ => 'To do' }, style: Theme.of(context).textTheme.bodySmall)),
              ),
            IconButton(tooltip: 'Remove option', onPressed: () => onChanged([...options]..removeAt(i)), icon: const Icon(Icons.close, size: 18)),
          ]),
        ),
      TextButton.icon(
        onPressed: () => onChanged([...options, te.SelectOption(id: 'o${DateTime.now().microsecondsSinceEpoch}', label: 'Option ${options.length + 1}', color: OptionColors.names[options.length % OptionColors.names.length], group: status ? te.StatusGroup.todo : null)]),
        icon: const Icon(Icons.add),
        label: const Text('Add option'),
      ),
    ]);
  }
}
