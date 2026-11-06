import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker_engine/tracker_engine.dart' as te;

import '../../../design_system/tokens.dart';
import '../application/tracker_controller.dart';

String opLabel(te.FilterOp op) => switch (op) {
      te.FilterOp.contains => 'contains',
      te.FilterOp.notContains => 'does not contain',
      te.FilterOp.startsWith => 'starts with',
      te.FilterOp.endsWith => 'ends with',
      te.FilterOp.eq => 'is',
      te.FilterOp.neq => 'is not',
      te.FilterOp.isEmpty => 'is empty',
      te.FilterOp.isNotEmpty => 'is not empty',
      te.FilterOp.gt => '>',
      te.FilterOp.gte => '≥',
      te.FilterOp.lt => '<',
      te.FilterOp.lte => '≤',
      te.FilterOp.before => 'is before',
      te.FilterOp.after => 'is after',
      te.FilterOp.onOrBefore => 'is on or before',
      te.FilterOp.onOrAfter => 'is on or after',
      te.FilterOp.inLastDays => 'in the last (days)',
      te.FilterOp.inNextDays => 'in the next (days)',
      te.FilterOp.isAnyOf => 'is any of',
      te.FilterOp.isNoneOf => 'is none of',
      te.FilterOp.hasAny => 'has any of',
      te.FilterOp.hasNone => 'has none of',
      te.FilterOp.isChecked => 'is checked',
      te.FilterOp.isUnchecked => 'is unchecked',
    };

bool _noOperand(te.FilterOp op) => const {te.FilterOp.isEmpty, te.FilterOp.isNotEmpty, te.FilterOp.isChecked, te.FilterOp.isUnchecked}.contains(op);

/// Properties the engine can group by.
bool canGroupBy(te.PropertyDef p) => const {
      te.PropertyType.select, te.PropertyType.status, te.PropertyType.checkbox, te.PropertyType.date, te.PropertyType.text,
      te.PropertyType.number, te.PropertyType.currency, te.PropertyType.percent, te.PropertyType.progress,
    }.contains(p.type);

Future<void> showViewOptions(BuildContext context, WidgetRef ref, TrackerScreenState s) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 720),
    builder: (_) => _ViewOptions(state: s),
  );
}

class _ViewOptions extends ConsumerStatefulWidget {
  const _ViewOptions({required this.state});
  final TrackerScreenState state;
  @override
  ConsumerState<_ViewOptions> createState() => _ViewOptionsState();
}

class _ViewOptionsState extends ConsumerState<_ViewOptions> {
  late te.ViewConfig _v = widget.state.effectiveView;
  List<te.PropertyDef> get _props => widget.state.properties;
  te.PropertyDef? _def(String id) => _props.where((p) => p.id == id).firstOrNull;

  // ---- editing helpers on the TOP-LEVEL filter group (nested groups are kept as they are)
  void _setChildren(List<te.FilterNode> c) => setState(() => _v = _v.copyWith(filter: te.FilterGroup(and: _v.filter.and, children: c)));

  te.FilterCondition _newCondition() {
    final p = _props.firstWhere((p) => te.opsFor(p.type).isNotEmpty, orElse: () => _props.first);
    return te.FilterCondition(propertyId: p.id, op: _opsFor(p).first);
  }

  List<te.FilterOp> _opsFor(te.PropertyDef p) =>
      te.opsFor(p.type).where((o) => !(p.type == te.PropertyType.relation && (o == te.FilterOp.hasAny || o == te.FilterOp.hasNone))).toList();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final children = _v.filter.children;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .85,
      maxChildSize: .95,
      builder: (context, scroll) => Column(children: [
        Expanded(
          child: ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(Space.s24, 0, Space.s24, Space.s16), children: [
            Text('View options', style: t.titleLarge),
            const SizedBox(height: Space.s16),
            Row(children: [
              Text('Filters', style: t.titleMedium),
              const Spacer(),
              if (children.length > 1)
                SegmentedButton<bool>(
                  segments: const [ButtonSegment(value: true, label: Text('All')), ButtonSegment(value: false, label: Text('Any'))],
                  selected: {_v.filter.and},
                  onSelectionChanged: (s) => setState(() => _v = _v.copyWith(filter: te.FilterGroup(and: s.first, children: children))),
                ),
            ]),
            for (var i = 0; i < children.length; i++)
              switch (children[i]) {
                te.FilterCondition c => _ConditionRow(
                    key: ValueKey('cond-$i-${c.propertyId}'),
                    props: _props,
                    cond: c,
                    opsFor: _opsFor,
                    onChanged: (n) => _setChildren([...children]..[i] = n),
                    onRemove: () => _setChildren([...children]..removeAt(i)),
                  ),
                te.FilterGroup g => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('Group of ${g.children.length} conditions'),
                    subtitle: const Text('Kept as is — editing nested groups isn\'t supported yet.'),
                    trailing: IconButton(tooltip: 'Remove group', icon: const Icon(Icons.close), onPressed: () => _setChildren([...children]..removeAt(i))),
                  ),
              },
            TextButton.icon(key: const Key('add-filter'), onPressed: _props.isEmpty ? null : () => _setChildren([...children, _newCondition()]), icon: const Icon(Icons.add), label: const Text('Add filter')),
            const Divider(height: Space.s32),
            Text('Sort', style: t.titleMedium),
            for (var i = 0; i < _v.sorts.length; i++)
              Row(key: ValueKey('sort-$i'), children: [
                Expanded(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: _def(_v.sorts[i].propertyId) == null ? null : _v.sorts[i].propertyId,
                    items: [for (final p in _props) DropdownMenuItem(value: p.id, child: Text(p.name))],
                    onChanged: (id) => setState(() => _v = _v.copyWith(sorts: [..._v.sorts]..[i] = te.SortKey(id!, descending: _v.sorts[i].descending))),
                  ),
                ),
                IconButton(
                  tooltip: _v.sorts[i].descending ? 'Descending' : 'Ascending',
                  icon: Icon(_v.sorts[i].descending ? Icons.arrow_downward : Icons.arrow_upward),
                  onPressed: () => setState(() => _v = _v.copyWith(sorts: [..._v.sorts]..[i] = te.SortKey(_v.sorts[i].propertyId, descending: !_v.sorts[i].descending))),
                ),
                IconButton(tooltip: 'Remove sort', icon: const Icon(Icons.close), onPressed: () => setState(() => _v = _v.copyWith(sorts: [..._v.sorts]..removeAt(i)))),
              ]),
            TextButton.icon(key: const Key('add-sort'), onPressed: _props.isEmpty ? null : () => setState(() => _v = _v.copyWith(sorts: [..._v.sorts, te.SortKey(_props.first.id)])), icon: const Icon(Icons.add), label: const Text('Add sort')),
            const Divider(height: Space.s32),
            Text('Group', style: t.titleMedium),
            DropdownButton<String?>(
              key: const Key('group-by'),
              isExpanded: true,
              value: _v.groupBy != null && _def(_v.groupBy!.propertyId) != null ? _v.groupBy!.propertyId : null,
              items: [const DropdownMenuItem<String?>(value: null, child: Text('No grouping')), for (final p in _props.where(canGroupBy)) DropdownMenuItem(value: p.id, child: Text(p.name))],
              onChanged: (id) => setState(() => _v = id == null ? _v.copyWith(clearGroup: true) : _v.copyWith(groupBy: te.GroupBy(id, hideEmpty: _v.groupBy?.hideEmpty ?? false))),
            ),
            if (_v.groupBy != null)
              SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Hide empty groups'), value: _v.groupBy!.hideEmpty, onChanged: (h) => setState(() => _v = _v.copyWith(groupBy: te.GroupBy(_v.groupBy!.propertyId, hideEmpty: h)))),
            const Divider(height: Space.s32),
            Text('Show properties', style: t.titleMedium),
            for (final p in _props)
              CheckboxListTile(
                key: ValueKey('vis-${p.id}'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(p.name),
                value: _v.visibleProperties?.contains(p.id) ?? true,
                onChanged: (on) {
                  final cur = [...(_v.visibleProperties ?? [for (final x in _props) x.id])];
                  on == true ? cur.add(p.id) : cur.remove(p.id);
                  setState(() => _v = _v.copyWith(visibleProperties: [for (final x in _props) if (cur.contains(x.id)) x.id]));
                },
              ),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Show archived rows'), value: _v.showArchived, onChanged: (x) => setState(() => _v = _v.copyWith(showArchived: x))),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Compact rows'), value: _v.compact, onChanged: (x) => setState(() => _v = _v.copyWith(compact: x))),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(Space.s16),
          child: Row(children: [
            TextButton(onPressed: () => setState(() => _v = _v.copyWith(filter: te.FilterGroup(), sorts: const [], clearGroup: true)), child: const Text('Reset')),
            const Spacer(),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            const SizedBox(width: Space.s8),
            FilledButton(
              key: const Key('apply-view'),
              onPressed: () async {
                await ref.read(trackerControllerProvider(widget.state.trackerId).notifier).updateView(_v);
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Apply'),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _ConditionRow extends StatelessWidget {
  const _ConditionRow({super.key, required this.props, required this.cond, required this.opsFor, required this.onChanged, required this.onRemove});
  final List<te.PropertyDef> props;
  final te.FilterCondition cond;
  final List<te.FilterOp> Function(te.PropertyDef) opsFor;
  final ValueChanged<te.FilterCondition> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final def = props.where((p) => p.id == cond.propertyId).firstOrNull;
    if (def == null) {
      return ListTile(dense: true, contentPadding: EdgeInsets.zero, title: const Text('A property used here was deleted'), subtitle: const Text('This filter is ignored.'), trailing: IconButton(icon: const Icon(Icons.close), onPressed: onRemove));
    }
    final ops = opsFor(def);
    final op = ops.contains(cond.op) ? cond.op : ops.first;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.s4),
      child: Wrap(spacing: Space.s8, runSpacing: Space.s4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SizedBox(
          width: 150,
          child: DropdownButton<String>(
            key: const Key('cond-prop'),
            isExpanded: true,
            value: def.id,
            items: [for (final p in props) DropdownMenuItem(value: p.id, child: Text(p.name, overflow: TextOverflow.ellipsis))],
            onChanged: (id) {
              final np = props.firstWhere((p) => p.id == id);
              onChanged(te.FilterCondition(propertyId: np.id, op: opsFor(np).first));
            },
          ),
        ),
        SizedBox(
          width: 170,
          child: DropdownButton<te.FilterOp>(
            key: const Key('cond-op'),
            isExpanded: true,
            value: op,
            items: [for (final o in ops) DropdownMenuItem(value: o, child: Text(opLabel(o), overflow: TextOverflow.ellipsis))],
            onChanged: (o) => onChanged(te.FilterCondition(propertyId: def.id, op: o!, value: null)),
          ),
        ),
        if (!_noOperand(op)) SizedBox(width: 190, child: _Operand(def: def, op: op, value: cond.value, onChanged: (v) => onChanged(te.FilterCondition(propertyId: def.id, op: op, value: v)))),
        IconButton(tooltip: 'Remove filter', icon: const Icon(Icons.close, size: 18), onPressed: onRemove),
      ]),
    );
  }
}

class _Operand extends StatelessWidget {
  const _Operand({required this.def, required this.op, required this.value, required this.onChanged});
  final te.PropertyDef def;
  final te.FilterOp op;
  final Object? value;
  final ValueChanged<Object?> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = def.type;
    if ((t == te.PropertyType.select || t == te.PropertyType.status) && (op == te.FilterOp.eq || op == te.FilterOp.neq)) {
      return DropdownButton<String>(
        isExpanded: true,
        value: def.option(value is String ? value as String : null) == null ? null : value as String,
        hint: const Text('Choose…'),
        items: [for (final o in def.options) DropdownMenuItem(value: o.id, child: Text(o.label))],
        onChanged: onChanged,
      );
    }
    if (op == te.FilterOp.isAnyOf || op == te.FilterOp.isNoneOf || op == te.FilterOp.hasAny || op == te.FilterOp.hasNone) {
      final sel = {...((value as List?) ?? const []).cast<String>()};
      return Wrap(spacing: 4, children: [
        for (final o in def.options)
          FilterChip(
            label: Text(o.label),
            selected: sel.contains(o.id),
            onSelected: (on) => onChanged([for (final x in def.options) if ((x.id == o.id) ? on : sel.contains(x.id)) x.id]),
          ),
      ]);
    }
    if (t == te.PropertyType.currency && op != te.FilterOp.isEmpty && op != te.FilterOp.isNotEmpty) {
      // users type major units ("5"); cells store minor units (500), so convert both ways
      var f = 1;
      for (var i = 0; i < def.decimals; i++) {
        f *= 10;
      }
      return TextFormField(
        key: Key('operand-${op.name}'),
        initialValue: value is num ? ((value as num) / f).toString() : '',
        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
        decoration: InputDecoration(isDense: true, hintText: def.currencySymbol),
        onChanged: (v) {
          final n = num.tryParse(v.replaceAll(',', '.'));
          onChanged(n == null ? null : (n * f).round());
        },
      );
    }
    final numeric = const {te.PropertyType.number, te.PropertyType.percent, te.PropertyType.progress}.contains(t) || op == te.FilterOp.inLastDays || op == te.FilterOp.inNextDays;
    final isDate = (t == te.PropertyType.date || t == te.PropertyType.dateRange) && !(op == te.FilterOp.inLastDays || op == te.FilterOp.inNextDays);
    return TextFormField(
      key: Key('operand-${op.name}'),
      initialValue: value?.toString() ?? '',
      keyboardType: numeric ? const TextInputType.numberWithOptions(decimal: true, signed: true) : TextInputType.text,
      decoration: InputDecoration(isDense: true, hintText: isDate ? 'YYYY-MM-DD' : 'value'),
      onChanged: (v) => onChanged(numeric ? (num.tryParse(v.replaceAll(',', '.')) ?? (v.isEmpty ? null : v)) : (v.isEmpty ? null : v)),
    );
  }
}
