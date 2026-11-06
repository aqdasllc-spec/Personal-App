import 'package:flutter/material.dart';
import 'package:tracker_engine/tracker_engine.dart' as te;

import '../../../design_system/option_colors.dart';
import '../../../design_system/tokens.dart';

class OptionPill extends StatelessWidget {
  const OptionPill({super.key, required this.label, required this.color, this.removed = false});
  final String label;
  final String color;
  final bool removed;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = OptionColors.of(removed ? 'gray' : color, Theme.of(context).brightness);
    return Container(
      margin: const EdgeInsets.only(right: Space.s4),
      padding: const EdgeInsets.symmetric(horizontal: Space.s8, vertical: 1),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(Radii.pill)),
      child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w500)),
    );
  }
}

/// Read-only rendering of one cell. Text shown is always `Values.format`, so tables, cards and
/// exports agree. [titles] resolves relation targets to their titles.
class CellDisplay extends StatelessWidget {
  const CellDisplay({super.key, required this.def, required this.value, this.titles = const {}});
  final te.PropertyDef def;
  final te.CellValue value;
  final Map<String, String> titles;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final v = value;
    if (v is te.FormulaError) {
      return Tooltip(message: v.detail ?? v.code, child: Text(v.code, style: TextStyle(color: c.danger, fontSize: 12)));
    }
    if (te.Values.isEmpty(v) && def.type != te.PropertyType.checkbox) return const SizedBox.shrink();
    switch (def.type) {
      case te.PropertyType.select:
      case te.PropertyType.status:
        final o = def.option(v as String);
        return Align(alignment: Alignment.centerLeft, child: OptionPill(label: o?.label ?? '(removed)', color: o?.color ?? 'gray', removed: o == null));
      case te.PropertyType.multiSelect:
        return ClipRect(
          child: Row(children: [
            for (final id in v as List)
              OptionPill(label: def.option(id as String)?.label ?? '(removed)', color: def.option(id)?.color ?? 'gray', removed: def.option(id) == null)
          ]),
        );
      case te.PropertyType.checkbox:
        return Align(
          alignment: Alignment.centerLeft,
          child: Icon(v == true ? Icons.check_box : Icons.check_box_outline_blank, size: 20, color: v == true ? c.accent : c.textMuted, semanticLabel: v == true ? 'Checked' : 'Unchecked'),
        );
      case te.PropertyType.progress:
        return _Bar(value: (v as num).toDouble() / 100, label: '${v.round()}%');
      case te.PropertyType.rollup:
      case te.PropertyType.formula:
        if (v is List) return Text(v.join(', '), maxLines: 1, overflow: TextOverflow.ellipsis);
        if (v is num) return Align(alignment: Alignment.centerRight, child: Text(_num(v), maxLines: 1));
        if (v is bool) return Text(v ? '✓' : '✗');
        return Text(_fmtMaybeDate(v.toString()), maxLines: 1, overflow: TextOverflow.ellipsis);
      case te.PropertyType.relation:
        return ClipRect(child: Row(children: [for (final id in v as List) OptionPill(label: titles[id.toString()] ?? 'Untitled', color: 'purple')]));
      case te.PropertyType.number:
      case te.PropertyType.currency:
      case te.PropertyType.percent:
        return Align(alignment: Alignment.centerRight, child: Text(te.Values.format(def, v), maxLines: 1));
      case te.PropertyType.url:
      case te.PropertyType.email:
      case te.PropertyType.phone:
        final ok = te.Values.isWellFormed(def, v);
        return Text(v.toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: ok ? c.accent : c.warn, decoration: ok ? TextDecoration.underline : TextDecoration.lineThrough));
      case te.PropertyType.createdTime:
      case te.PropertyType.lastEditedTime:
        return Text(_fmtMaybeDate(v.toString()), maxLines: 1);
      case te.PropertyType.richText:
        return Text(v.toString().replaceAll('\n', ' '), maxLines: 1, overflow: TextOverflow.ellipsis);
      case te.PropertyType.person:
      case te.PropertyType.files:
      case te.PropertyType.image:
        return Text((v as List).join(', '), maxLines: 1, overflow: TextOverflow.ellipsis);
      default:
        return Text(te.Values.format(def, v), maxLines: 1, overflow: TextOverflow.ellipsis);
    }
  }

  static String _num(num n) => n == n.roundToDouble() ? n.toInt().toString() : n.toStringAsFixed(2);
  static String _fmtMaybeDate(String s) => RegExp(r'^\d{4}-\d{2}-\d{2}T').hasMatch(s) ? s.substring(0, 10) : s;
}

class _Bar extends StatelessWidget {
  const _Bar({required this.value, required this.label});
  final double value;
  final String label;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(children: [
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Radii.pill),
          child: LinearProgressIndicator(value: value.clamp(0, 1), minHeight: 6, backgroundColor: c.surface2, color: c.accent),
        ),
      ),
      const SizedBox(width: Space.s8),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ]);
  }
}
