import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker_engine/tracker_engine.dart' as te;
import 'package:two_dimensional_scrollables/two_dimensional_scrollables.dart';

import '../../../design_system/tokens.dart';
import '../application/tracker_controller.dart';
import 'cell_display.dart';
import 'cell_editors.dart';
import 'property_dialog.dart';

double defaultWidth(te.PropertyDef p, {bool title = false}) {
  if (title) return 280;
  return switch (p.type) {
    te.PropertyType.checkbox => 96,
    te.PropertyType.number || te.PropertyType.currency || te.PropertyType.percent => 130,
    te.PropertyType.progress => 150,
    te.PropertyType.date || te.PropertyType.dateRange || te.PropertyType.createdTime || te.PropertyType.lastEditedTime => 150,
    te.PropertyType.richText || te.PropertyType.formula || te.PropertyType.rollup || te.PropertyType.relation => 200,
    _ => 170,
  };
}

/// Text shown when editing a cell inline (raw, not display-formatted).
String rawEditText(te.PropertyDef def, te.CellValue v) {
  if (v == null) return '';
  if (def.type == te.PropertyType.currency) {
    var f = 1;
    for (var i = 0; i < def.decimals; i++) {
      f *= 10;
    }
    return ((v as int) / f).toStringAsFixed(def.decimals);
  }
  if (def.type == te.PropertyType.dateRange) {
    final m = v as Map;
    return m['end'] == null ? m['start'] as String : '${m['start']} to ${m['end']}';
  }
  if (v is List) return v.join(', ');
  return v.toString();
}

/// Spreadsheet-style grid: sticky header and title column, virtualised rows/columns,
/// click-to-edit cells, keyboard navigation, multi-select and context menus.
class TrackerTable extends ConsumerStatefulWidget {
  const TrackerTable({super.key, required this.state, required this.onOpenRecord});
  final TrackerScreenState state;
  final ValueChanged<String> onOpenRecord;

  @override
  ConsumerState<TrackerTable> createState() => _TrackerTableState();
}

class _TrackerTableState extends ConsumerState<TrackerTable> {
  final _focus = FocusNode(debugLabel: 'tracker-grid');
  final _drag = <String, double>{}; // live column widths while resizing

  TrackerScreenState get s => widget.state;
  TrackerController get ctrl => ref.read(trackerControllerProvider(s.trackerId).notifier);
  List<te.PropertyDef> get cols => s.visibleProperties;

  double _w(te.PropertyDef p) => _drag[p.id] ?? s.effectiveView.widths[p.id] ?? defaultWidth(p, title: p.id == s.titleProperty?.id);

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final mod = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    if (mod && k == LogicalKeyboardKey.keyZ) {
      shift ? ctrl.redo() : ctrl.undo();
      return KeyEventResult.handled;
    }
    if (mod && k == LogicalKeyboardKey.keyY) {
      ctrl.redo();
      return KeyEventResult.handled;
    }
    if (s.editing) {
      if (k == LogicalKeyboardKey.escape) {
        ctrl.stopEditing();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored; // the text field owns everything else
    }
    final a = s.active;
    if (mod && k == LogicalKeyboardKey.keyA) {
      ctrl.selectAll();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.escape) {
      a == null ? ctrl.clearSelection() : ctrl.setActive(null);
      return KeyEventResult.handled;
    }
    if (a == null || s.records.isEmpty || cols.isEmpty) return KeyEventResult.ignored;
    var r = s.records.indexWhere((x) => x.id == a.recordId);
    var c = cols.indexWhere((x) => x.id == a.propertyId);
    if (r < 0 || c < 0) return KeyEventResult.ignored;
    void move(int dr, int dc) {
      r = (r + dr).clamp(0, s.records.length - 1);
      c = (c + dc).clamp(0, cols.length - 1);
      ctrl.setActive(ActiveCell(s.records[r].id, cols[c].id));
    }

    if (k == LogicalKeyboardKey.arrowDown) {
      move(1, 0);
    } else if (k == LogicalKeyboardKey.arrowUp) {
      move(-1, 0);
    } else if (k == LogicalKeyboardKey.arrowRight || (k == LogicalKeyboardKey.tab && !shift)) {
      move(0, 1);
    } else if (k == LogicalKeyboardKey.arrowLeft || (k == LogicalKeyboardKey.tab && shift)) {
      move(0, -1);
    } else if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.f2) {
      _activate(s.records[r], cols[c], force: true);
    } else if (k == LogicalKeyboardKey.delete || k == LogicalKeyboardKey.backspace) {
      final d = cols[c];
      if (d.type.isStored) ctrl.setCell(s.records[r].id, d.id, null);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  /// Click on a cell. First click selects (checkboxes toggle at once); clicking the active cell edits.
  void _activate(te.TrackerRecord r, te.PropertyDef d, {bool force = false}) {
    final cell = ActiveCell(r.id, d.id);
    final wasActive = s.active == cell;
    if (!isEditable(d)) {
      ctrl.setActive(cell);
      return;
    }
    if (d.type == te.PropertyType.checkbox) {
      ctrl.setActive(cell);
      ctrl.setCell(r.id, d.id, r.cells[d.id] == true ? false : true);
      return;
    }
    if (!wasActive && !force) {
      ctrl.setActive(cell);
      return;
    }
    ctrl.setActive(cell);
    if (usesPicker(d.type)) {
      openPicker(context, ref, s, r, d);
    } else {
      ctrl.startEditing();
    }
  }

  Future<void> _rowMenu(te.TrackerRecord r, Offset global) async {
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(global.dx, global.dy, global.dx, global.dy),
      items: [
        const PopupMenuItem(value: 'open', child: Text('Open record')),
        const PopupMenuItem(value: 'dup', child: Text('Duplicate')),
        const PopupMenuItem(value: 'below', child: Text('Insert row below')),
        PopupMenuItem(value: 'archive', child: Text(r.archived ? 'Unarchive' : 'Archive')),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: context.colors.danger))),
      ],
    );
    switch (choice) {
      case 'open':
        widget.onOpenRecord(r.id);
      case 'dup':
        await ctrl.duplicateRecord(r.id);
      case 'below':
        await ctrl.addRecord(afterRecordId: r.id);
      case 'archive':
        await ctrl.archiveRecords([r.id], !r.archived);
      case 'delete':
        await ctrl.deleteRecords([r.id]);
    }
  }

  Future<void> _headerMenu(te.PropertyDef d, Offset global) async {
    final v = s.effectiveView;
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(global.dx, global.dy, global.dx, global.dy),
      items: const [
        PopupMenuItem(value: 'edit', child: Text('Edit property')),
        PopupMenuItem(value: 'asc', child: Text('Sort ascending')),
        PopupMenuItem(value: 'desc', child: Text('Sort descending')),
        PopupMenuItem(value: 'hide', child: Text('Hide in this view')),
        PopupMenuDivider(),
        PopupMenuItem(value: 'delete', child: Text('Delete property')),
      ],
    );
    if (!mounted) return;
    switch (choice) {
      case 'edit':
        await showPropertyDialog(context, ref, s, existing: d);
      case 'asc':
        await ctrl.updateView(v.copyWith(sorts: [te.SortKey(d.id)]));
      case 'desc':
        await ctrl.updateView(v.copyWith(sorts: [te.SortKey(d.id, descending: true)]));
      case 'hide':
        await ctrl.updateView(v.copyWith(visibleProperties: [for (final p in cols) if (p.id != d.id) p.id]));
      case 'delete':
        await ctrl.deleteProperty(d.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final compact = s.effectiveView.compact;
    final rowH = compact ? 32.0 : 40.0;
    const headerH = 36.0, gutterW = 84.0, addW = 56.0;
    final frozen = s.effectiveView.frozenColumns.clamp(0, cols.length);
    final nCols = 1 + cols.length + 1;
    final nRows = 1 + s.records.length + 1;

    return Focus(
      focusNode: _focus,
      autofocus: false,
      onKeyEvent: _onKey,
      child: TableView.builder(
        pinnedRowCount: 1,
        pinnedColumnCount: 1 + frozen,
        rowCount: nRows,
        columnCount: nCols,
        columnBuilder: (i) => TableSpan(extent: FixedTableSpanExtent(i == 0 ? gutterW : (i == nCols - 1 ? addW : _w(cols[i - 1])))),
        rowBuilder: (i) => TableSpan(extent: FixedTableSpanExtent(i == 0 ? headerH : rowH)),
        cellBuilder: (context, v) {
          final col = v.column, row = v.row;
          final isAddCol = col == nCols - 1;
          final bg = row == 0 ? c.surface2 : c.surface;
          Widget wrap(Widget child, {Color? color, Alignment align = Alignment.centerLeft, EdgeInsets pad = const EdgeInsets.symmetric(horizontal: Space.s8)}) => Container(
                alignment: align,
                padding: pad,
                decoration: BoxDecoration(color: color ?? bg, border: Border(right: BorderSide(color: c.border), bottom: BorderSide(color: c.border))),
                child: child,
              );

          // ---- header row
          if (row == 0) {
            if (col == 0) {
              return TableViewCell(child: wrap(Checkbox(
                    tristate: true,
                    value: s.selected.isEmpty ? false : (s.selected.length == s.records.length ? true : null),
                    onChanged: (_) => s.selected.isEmpty ? ctrl.selectAll() : ctrl.clearSelection(),
                  ), align: Alignment.center, pad: EdgeInsets.zero));
            }
            if (isAddCol) {
              return TableViewCell(child: wrap(IconButton(tooltip: 'Add property', icon: const Icon(Icons.add), onPressed: () => showPropertyDialog(context, ref, s)), align: Alignment.center, pad: EdgeInsets.zero));
            }
            final d = cols[col - 1];
            return TableViewCell(
              child: wrap(
                Row(children: [
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: (t) => _headerMenu(d, t.globalPosition),
                      child: Semantics(
                        button: true,
                        label: '${d.name} column menu',
                        child: Row(children: [
                          Icon(_glyph(d.type), size: 14, color: c.textMuted),
                          const SizedBox(width: Space.s4),
                          Expanded(child: Text(d.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.textMuted, fontWeight: FontWeight.w500))),
                        ]),
                      ),
                    ),
                  ),
                  MouseRegion(
                    cursor: SystemMouseCursors.resizeColumn,
                    child: GestureDetector(
                      key: Key('resize-${d.id}'),
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragUpdate: (u) => setState(() => _drag[d.id] = ((_drag[d.id] ?? _w(d)) + u.delta.dx).clamp(60, 800)),
                      onHorizontalDragEnd: (_) {
                        final w = _drag.remove(d.id);
                        if (w != null) ctrl.updateView(s.effectiveView.copyWith(widths: {...s.effectiveView.widths, d.id: w}));
                      },
                      child: const SizedBox(width: 10, height: double.infinity),
                    ),
                  ),
                ]),
              ),
            );
          }

          // ---- footer row ("new row")
          if (row == nRows - 1) {
            if (col == 1 && !isAddCol) {
              return TableViewCell(
                child: wrap(TextButton.icon(key: const Key('new-row'), onPressed: () async {
                      final id = await ctrl.addRecord();
                      if (id != null && cols.isNotEmpty) ctrl.setActive(ActiveCell(id, cols.first.id));
                    }, icon: const Icon(Icons.add, size: 18), label: const Text('New row'))),
              );
            }
            return TableViewCell(child: wrap(const SizedBox.shrink()));
          }

          // ---- record rows
          final r = s.records[row - 1];
          final selected = s.selected.contains(r.id);
          final rowColor = selected ? c.accentSoft : c.surface;
          if (col == 0) {
            return TableViewCell(
              child: GestureDetector(
                onSecondaryTapUp: (t) => _rowMenu(r, t.globalPosition),
                onLongPressStart: (t) => _rowMenu(r, t.globalPosition),
                child: wrap(
                  Row(children: [
                    Checkbox(
                      key: Key('select-${r.id}'),
                      value: selected,
                      visualDensity: VisualDensity.compact,
                      onChanged: (_) => HardwareKeyboard.instance.isShiftPressed ? ctrl.selectRange(r.id) : ctrl.toggleSelected(r.id),
                    ),
                    Expanded(child: Text('$row', style: Theme.of(context).textTheme.bodySmall)),
                    Tooltip(message: 'Open record', child: InkWell(onTap: () => widget.onOpenRecord(r.id), child: Padding(padding: const EdgeInsets.all(4), child: Icon(Icons.open_in_full, size: 14, color: c.textMuted)))),
                  ]),
                  color: rowColor,
                  pad: const EdgeInsets.only(left: Space.s4, right: Space.s8),
                ),
              ),
            );
          }
          if (isAddCol) return TableViewCell(child: wrap(const SizedBox.shrink(), color: rowColor));

          final d = cols[col - 1];
          final value = s.valueOf(r, d);
          final active = s.active == ActiveCell(r.id, d.id);
          final editing = active && s.editing && !usesPicker(d.type) && d.type != te.PropertyType.checkbox && isEditable(d);
          final calc = !d.type.isStored && d.type != te.PropertyType.relation;
          final inner = editing
              ? _InlineEditor(
                  key: ValueKey('edit-${r.id}-${d.id}'),
                  initial: rawEditText(d, value),
                  numeric: const {te.PropertyType.number, te.PropertyType.currency, te.PropertyType.percent, te.PropertyType.progress}.contains(d.type),
                  onCommit: (text, {bool moveRight = false}) async {
                    final ok = await ctrl.setCellFromText(r.id, d.id, text);
                    if (ok) {
                      ctrl.stopEditing();
                      if (moveRight) {
                        final ci = cols.indexOf(d);
                        if (ci + 1 < cols.length) ctrl.setActive(ActiveCell(r.id, cols[ci + 1].id));
                      }
                      _focus.requestFocus();
                    }
                  },
                  onCancel: () {
                    ctrl.stopEditing();
                    _focus.requestFocus();
                  },
                )
              : CellDisplay(def: d, value: value, titles: s.titles);
          return TableViewCell(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                _focus.requestFocus();
                _activate(r, d);
              },
              // No onDoubleTap on purpose: a double-tap recogniser delays every single tap by ~300 ms.
              // Clicking the already-selected cell edits it, which covers double-click too.
              onSecondaryTapUp: (t) => _rowMenu(r, t.globalPosition),
              onLongPressStart: (t) => _rowMenu(r, t.globalPosition),
              child: Semantics(
                label: '${d.name}: ${te.Values.format(d, value is te.FormulaError ? null : value)}',
                selected: active,
                child: Container(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: Space.s8),
                  decoration: BoxDecoration(
                    color: calc ? Color.alphaBlend(c.surface2.withValues(alpha: .45), rowColor) : rowColor,
                    border: active ? Border.all(color: c.accent, width: 2) : Border(right: BorderSide(color: c.border), bottom: BorderSide(color: c.border)),
                  ),
                  child: DefaultTextStyle.merge(
                    style: TextStyle(fontWeight: d.id == s.titleProperty?.id ? FontWeight.w600 : null, decoration: r.archived ? TextDecoration.lineThrough : null),
                    child: inner,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  IconData _glyph(te.PropertyType t) => switch (t) {
        te.PropertyType.text || te.PropertyType.richText => Icons.text_fields,
        te.PropertyType.number || te.PropertyType.percent || te.PropertyType.progress => Icons.tag,
        te.PropertyType.currency => Icons.attach_money,
        te.PropertyType.checkbox => Icons.check_box_outlined,
        te.PropertyType.date || te.PropertyType.dateRange || te.PropertyType.createdTime || te.PropertyType.lastEditedTime => Icons.event,
        te.PropertyType.url => Icons.link,
        te.PropertyType.email => Icons.alternate_email,
        te.PropertyType.phone => Icons.phone_outlined,
        te.PropertyType.select || te.PropertyType.status => Icons.arrow_drop_down_circle_outlined,
        te.PropertyType.multiSelect => Icons.checklist,
        te.PropertyType.person => Icons.person_outline,
        te.PropertyType.files || te.PropertyType.image => Icons.attach_file,
        te.PropertyType.relation => Icons.swap_horiz,
        te.PropertyType.rollup => Icons.functions,
        te.PropertyType.formula => Icons.functions,
      };
}

class _InlineEditor extends StatefulWidget {
  const _InlineEditor({super.key, required this.initial, required this.numeric, required this.onCommit, required this.onCancel});
  final String initial;
  final bool numeric;
  final Future<void> Function(String text, {bool moveRight}) onCommit;
  final VoidCallback onCancel;
  @override
  State<_InlineEditor> createState() => _InlineEditorState();
}

class _InlineEditorState extends State<_InlineEditor> {
  late final _c = TextEditingController(text: widget.initial)..selection = TextSelection(baseOffset: 0, extentOffset: widget.initial.length);
  final _f = FocusNode();
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _f.addListener(() {
      if (!_f.hasFocus && !_done) _commit(); // clicking elsewhere commits
    });
  }

  @override
  void dispose() {
    _c.dispose();
    _f.dispose();
    super.dispose();
  }

  Future<void> _commit({bool moveRight = false}) async {
    if (_done) return;
    _done = true;
    if (_c.text == widget.initial) {
      widget.onCancel(); // nothing changed
      return;
    }
    await widget.onCommit(_c.text, moveRight: moveRight);
    if (mounted) _done = false; // validation failed: stay in edit mode so nothing is lost
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: (n, e) {
        if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape) {
          _done = true;
          widget.onCancel();
          return KeyEventResult.handled;
        }
        if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.tab) {
          _commit(moveRight: true);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: TextField(
        key: const Key('cell-editor'),
        controller: _c,
        focusNode: _f,
        autofocus: true,
        keyboardType: widget.numeric ? const TextInputType.numberWithOptions(decimal: true, signed: true) : TextInputType.text,
        decoration: const InputDecoration(isDense: true, border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, filled: false, contentPadding: EdgeInsets.zero),
        onSubmitted: (_) => _commit(),
      ),
    );
  }
}
