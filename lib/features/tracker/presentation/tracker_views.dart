import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker_engine/tracker_engine.dart' as te;

import '../../../design_system/components.dart';
import '../../../design_system/tokens.dart';
import '../application/tracker_controller.dart';
import 'cell_display.dart';

String titleOf(TrackerScreenState s, te.TrackerRecord r) {
  final t = s.titleProperty;
  final v = t == null ? null : r.cells[t.id];
  return v is String && v.isNotEmpty ? v : 'Untitled';
}

/// Properties summarised on cards: the view's `cardProperties` option, else the first few non-title ones.
List<te.PropertyDef> cardProps(TrackerScreenState s, {String? exclude, int max = 3}) {
  final chosen = (s.effectiveView.layoutOptions['cardProperties'] as List?)?.cast<String>();
  final base = chosen != null ? [for (final id in chosen) ...s.properties.where((p) => p.id == id)] : s.visibleProperties;
  return [for (final p in base) if (p.id != s.titleProperty?.id && p.id != exclude) p].take(max).toList();
}

/// Board grouped by a Select/Status property. Drag a card to another column to change its value.
class KanbanView extends ConsumerWidget {
  const KanbanView({super.key, required this.state, required this.onOpenRecord});
  final TrackerScreenState state;
  final ValueChanged<String> onOpenRecord;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = state;
    final groups = s.groups;
    final gid = s.groupPropertyId;
    final gdef = s.properties.where((p) => p.id == gid).firstOrNull;
    if (groups == null || gdef == null || !(gdef.type == te.PropertyType.select || gdef.type == te.PropertyType.status)) {
      return const EmptyState(icon: Icons.view_kanban_outlined, title: 'Nothing to group by yet', message: 'A board needs a Status or Select property. Add one with the + button in the table view.');
    }
    final ctrl = ref.read(trackerControllerProvider(s.trackerId).notifier);
    final c = context.colors;
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(Space.s16),
      itemCount: groups.length,
      separatorBuilder: (_, __) => const SizedBox(width: Space.s12),
      itemBuilder: (context, i) {
        final g = groups[i];
        final opt = g.key == null ? null : gdef.option(g.key!);
        return DragTarget<String>(
          key: Key('column-${g.key ?? 'none'}'),
          onWillAcceptWithDetails: (d) => true,
          onAcceptWithDetails: (d) => ctrl.setCell(d.data, gdef.id, g.key),
          builder: (context, candidates, _) => Container(
            width: 280,
            decoration: BoxDecoration(color: candidates.isNotEmpty ? c.accentSoft : c.surface2, borderRadius: BorderRadius.circular(Radii.sheet)),
            padding: const EdgeInsets.all(Space.s8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.s4, Space.s4, Space.s4, Space.s8),
                child: Row(children: [
                  OptionPill(label: opt?.label ?? (g.key == null ? 'No value' : '(removed)'), color: opt?.color ?? 'gray'),
                  Text('${g.records.length}', style: Theme.of(context).textTheme.bodySmall),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Add to ${opt?.label ?? 'this column'}',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.add, size: 18),
                    onPressed: () => ctrl.addRecord(values: g.key == null ? const {} : {gdef.id: g.key}),
                  ),
                ]),
              ),
              Expanded(
                child: ListView(children: [
                  for (final r in g.records) _Card(state: s, record: r, groupProp: gdef, onOpen: onOpenRecord),
                  if (g.records.isEmpty) Padding(padding: const EdgeInsets.all(Space.s16), child: Text('No records', style: Theme.of(context).textTheme.bodySmall)),
                ]),
              ),
            ]),
          ),
        );
      },
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.state, required this.record, required this.groupProp, required this.onOpen});
  final TrackerScreenState state;
  final te.TrackerRecord record;
  final te.PropertyDef groupProp;
  final ValueChanged<String> onOpen;

  Widget _body(BuildContext context, {bool lifted = false}) {
    final c = context.colors;
    final props = cardProps(state, exclude: groupProp.id);
    return Container(
      width: 264,
      margin: const EdgeInsets.only(bottom: Space.s8),
      padding: const EdgeInsets.all(Space.s12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: c.border),
        boxShadow: lifted ? [BoxShadow(color: Colors.black.withValues(alpha: .25), blurRadius: 18, offset: const Offset(0, 8))] : null,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(titleOf(state, record), style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
        for (final p in props)
          if (!te.Values.isEmpty(state.valueOf(record, p)))
            Padding(padding: const EdgeInsets.only(top: Space.s8), child: SizedBox(height: 22, child: CellDisplay(def: p, value: state.valueOf(record, p), titles: state.titles))),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LongPressDraggable<String>(
      data: record.id,
      feedback: Material(color: Colors.transparent, child: Transform.rotate(angle: .03, child: _body(context, lifted: true))),
      childWhenDragging: Opacity(opacity: .35, child: _body(context)),
      child: InkWell(key: Key('card-${record.id}'), borderRadius: BorderRadius.circular(Radii.card), onTap: () => onOpen(record.id), child: _body(context)),
    );
  }
}

/// Compact list: checkbox-style rows with a few summary properties.
class RecordListView extends ConsumerWidget {
  const RecordListView({super.key, required this.state, required this.onOpenRecord});
  final TrackerScreenState state;
  final ValueChanged<String> onOpenRecord;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = state;
    if (s.records.isEmpty) return const EmptyState(icon: Icons.list_alt, title: 'No records', message: 'Nothing matches this view. Add a record or change the filters.');
    final c = context.colors;
    final done = s.properties.where((p) => p.type == te.PropertyType.checkbox).firstOrNull;
    final ctrl = ref.read(trackerControllerProvider(s.trackerId).notifier);
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: Space.s8),
      itemCount: s.records.length,
      separatorBuilder: (_, __) => Divider(color: c.border),
      itemBuilder: (context, i) {
        final r = s.records[i];
        return ListTile(
          key: Key('list-${r.id}'),
          dense: true,
          leading: done == null
              ? null
              : Checkbox(value: r.cells[done.id] == true, onChanged: (v) => ctrl.setCell(r.id, done.id, v == true ? true : false)),
          title: Text(titleOf(s, r), style: TextStyle(decoration: r.archived ? TextDecoration.lineThrough : null)),
          trailing: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              for (final p in cardProps(s, exclude: done?.id, max: 3))
                if (!te.Values.isEmpty(s.valueOf(r, p))) Flexible(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 140), child: CellDisplay(def: p, value: s.valueOf(r, p), titles: s.titles))),
            ]),
          ),
          onTap: () => onOpenRecord(r.id),
        );
      },
    );
  }
}
