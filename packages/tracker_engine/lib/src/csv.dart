import 'computed.dart';
import 'formula.dart';
import 'property.dart';
import 'records.dart';
import 'values.dart';

/// RFC 4180 parser (quotes, doubled quotes, newlines inside quotes, CRLF/LF, BOM).
/// Auto-detects `,` `;` or tab unless [delimiter] is given.
List<List<String>> parseCsv(String input, {String? delimiter}) {
  var s = input.startsWith('﻿') ? input.substring(1) : input;
  final d = delimiter ?? _detectDelimiter(s);
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var inQuotes = false, wasQuoted = false, i = 0;
  void endCell() {
    row.add(cell.toString());
    cell.clear();
    wasQuoted = false;
  }

  void endRow() {
    endCell();
    if (!(row.length == 1 && row.first.isEmpty && !wasQuoted)) rows.add(row);
    row = <String>[];
  }

  while (i < s.length) {
    final ch = s[i];
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < s.length && s[i + 1] == '"') {
          cell.write('"');
          i += 2;
          continue;
        }
        inQuotes = false;
      } else {
        cell.write(ch);
      }
    } else if (ch == '"' && cell.isEmpty) {
      inQuotes = true;
      wasQuoted = true;
    } else if (ch == d) {
      endCell();
    } else if (ch == '\r' || ch == '\n') {
      if (ch == '\r' && i + 1 < s.length && s[i + 1] == '\n') i++;
      endRow();
    } else {
      cell.write(ch);
    }
    i++;
  }
  if (inQuotes) throw const FormatException('CSV has an unterminated quoted field');
  if (cell.isNotEmpty || row.isNotEmpty || wasQuoted) endRow();
  return rows;
}

String _detectDelimiter(String s) {
  final firstLine = s.split(RegExp(r'\r?\n')).first;
  var best = ',', bestN = -1;
  for (final c in const [',', ';', '\t']) {
    final n = c.allMatches(firstLine).length;
    if (n > bestN) {
      best = c;
      bestN = n;
    }
  }
  return best;
}

String writeCsv(List<List<String>> rows, {String delimiter = ',', bool bom = true}) {
  String q(String c) => (c.contains(delimiter) || c.contains('"') || c.contains('\n') || c.contains('\r')) ? '"${c.replaceAll('"', '""')}"' : c;
  return '${bom ? '﻿' : ''}${rows.map((r) => r.map(q).join(delimiter)).join('\r\n')}\r\n';
}

/// Spreadsheet apps execute cells starting with = + - @ (and tab/CR) as formulas.
/// Free-text cells get a leading apostrophe; numeric cells are written raw so values stay numbers.
String csvSafeText(String s) => s.isNotEmpty && '=+-@\t\r'.contains(s[0]) ? "'$s" : s;

/// Machine-friendly (round-trippable) text for one cell.
String csvCell(PropertyDef def, Value v, {TrackerSnapshot? snapshot}) {
  if (Values.isEmpty(v) || v is FormulaError) return '';
  switch (def.type) {
    case PropertyType.number:
    case PropertyType.percent:
    case PropertyType.progress:
      return v.toString();
    case PropertyType.currency:
      final minor = v as int;
      var f = 1;
      for (var i = 0; i < def.decimals; i++) {
        f *= 10;
      }
      return (minor / f).toStringAsFixed(def.decimals);
    case PropertyType.checkbox:
      return v == true ? 'true' : 'false';
    case PropertyType.date:
    case PropertyType.createdTime:
    case PropertyType.lastEditedTime:
      return v as String;
    case PropertyType.dateRange:
      final m = v as Map;
      return m['end'] == null ? m['start'] as String : '${m['start']} → ${m['end']}';
    case PropertyType.select:
    case PropertyType.status:
      return csvSafeText(def.option(v as String)?.label ?? '');
    case PropertyType.multiSelect:
      return csvSafeText((v as List).map((id) => def.option(id as String)?.label ?? '').where((l) => l.isNotEmpty).join('; '));
    case PropertyType.relation:
      final target = snapshot?.others[def.relationTargetTrackerId] ?? (def.relationTargetTrackerId == snapshot?.trackerId ? snapshot : null);
      final title = target?.titleProperty;
      return csvSafeText([
        for (final id in (v as List).cast<String>())
          (title != null ? (target!.record(id)?.cells[title.id] as String?) : null) ?? id
      ].join('; '));
    case PropertyType.rollup:
    case PropertyType.formula:
      return v is List ? csvSafeText(v.join('; ')) : (v is num || v is bool ? v.toString() : csvSafeText(v.toString()));
    case PropertyType.person:
    case PropertyType.files:
    case PropertyType.image:
      return csvSafeText((v as List).join('; '));
    default:
      return csvSafeText(v.toString());
  }
}

/// Export [records] with [columns] (header = property names).
String exportCsv(TrackerSnapshot s, List<PropertyDef> columns, List<TrackerRecord> records, {DateTime? now}) {
  final c = Computed(s, now: now);
  return writeCsv([
    [for (final d in columns) d.name],
    for (final r in records) [for (final d in columns) csvCell(d, c.valueOf(r, d), snapshot: s)],
  ]);
}

// ------------------------------------------------------------------ import
class ImportIssue {
  const ImportIssue(this.row, this.column, this.message);

  /// 1-based data row (header excluded).
  final int row;
  final String column;
  final String message;
  @override
  String toString() => 'Row $row, "$column": $message';
}

class ImportPlan {
  ImportPlan(this.records, this.issues, this.newOptions, this.skippedColumns);

  /// One map per importable data row: propertyId -> value. Rows with errors are still included with
  /// the bad cell left empty, so the caller can choose "import anyway" or abort.
  final List<Map<String, Value>> records;
  final List<ImportIssue> issues;

  /// propertyId -> option labels that do not exist yet (offer to create them).
  final Map<String, Set<String>> newOptions;
  final List<String> skippedColumns;
  bool get hasErrors => issues.isNotEmpty;
}

/// Dry-run import. [mapping]: CSV column index -> property id. Nothing is written here.
ImportPlan planImport({
  required List<String> headers,
  required List<List<String>> rows,
  required List<PropertyDef> properties,
  required Map<int, String> mapping,
  int maxRows = 100000,
}) {
  final byId = {for (final p in properties) p.id: p};
  final out = <Map<String, Value>>[];
  final issues = <ImportIssue>[];
  final newOpts = <String, Set<String>>{};
  final skipped = [for (var i = 0; i < headers.length; i++) if (!mapping.containsKey(i)) headers[i]];
  final n = rows.length > maxRows ? maxRows : rows.length;
  if (rows.length > maxRows) issues.add(ImportIssue(maxRows + 1, '', 'Only the first $maxRows rows can be imported at once.'));

  for (var r = 0; r < n; r++) {
    final cells = <String, Value>{};
    final row = rows[r];
    if (row.every((c) => c.trim().isEmpty)) continue;
    for (final e in mapping.entries) {
      final def = byId[e.value];
      if (def == null || !def.type.isStored || e.key >= row.length) continue;
      var text = row[e.key];
      if (text.startsWith("'") && text.length > 1 && '=+-@'.contains(text[1]) && def.type.isTextLike) text = text.substring(1); // undo export guard
      final res = Values.parseText(def, text);
      if (res.newOptionLabel != null) {
        newOpts.putIfAbsent(def.id, () => {}).add(res.newOptionLabel!);
        continue; // resolved after the caller creates the option
      }
      if (res.error != null) {
        issues.add(ImportIssue(r + 1, headers[e.key], res.error!));
        continue;
      }
      final err = Values.validate(def, res.value);
      if (err != null) {
        issues.add(ImportIssue(r + 1, headers[e.key], err));
        continue;
      }
      if (res.value != null) cells[def.id] = res.value;
    }
    out.add(cells);
  }
  return ImportPlan(out, issues, newOpts, skipped);
}

/// Guess a property type for a column from sample values (for "create property from column").
PropertyType inferType(List<String> samples) {
  final s = [for (final x in samples) x.trim()].where((x) => x.isNotEmpty).toList();
  if (s.isEmpty) return PropertyType.text;
  bool all(bool Function(String) f) => s.every(f);
  const bools = {'true', 'false', 'yes', 'no'};
  if (all((x) => bools.contains(x.toLowerCase()))) return PropertyType.checkbox;
  if (all((x) => parseDate(x) != null && RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(x))) return PropertyType.date;
  if (all((x) => RegExp(r'^-?\d+([.,]\d+)?$').hasMatch(x))) return PropertyType.number;
  if (all((x) => RegExp(r'^https?://').hasMatch(x))) return PropertyType.url;
  if (all((x) => RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(x))) return PropertyType.email;
  final unique = s.toSet();
  if (s.length >= 6 && unique.length <= 8 && unique.length * 2 <= s.length && all((x) => x.length <= 30)) return PropertyType.select;
  return PropertyType.text;
}
