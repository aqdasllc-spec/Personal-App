import 'property.dart';

/// Cell value representation (JSON-friendly):
///  text, richText, url, email, phone: String.  number, percent, progress: num.
///  currency: int (minor units).  checkbox: bool.
///  date: String (YYYY-MM-DD or ISO-8601 UTC).  dateRange: map with start and optional end.
///  select, status: String (option id).  multiSelect, person, files, image: List of String.
///  null always means "empty".
typedef Value = Object?;

/// How a value is laid out in the `cells` columns so SQL can filter/sort it.
class CellStorage {
  const CellStorage({this.text, this.num, this.intVal, this.json, this.sort, this.day});

  /// Canonical text (strings, option ids, ISO dates).
  final String? text;

  /// Sortable/aggregatable number (numbers, currency minor units, date epoch ms).
  final double? num;
  final int? intVal;

  /// JSON text for list/map values.
  final String? json;

  /// Normalised text for case/diacritic-insensitive sorting and `contains` (see [foldText]).
  final String? sort;

  /// UTC day number (epoch ms ~/ 86400000, floored) for dates, so day-level filters are indexable.
  final int? day;
}

class ParseResult {
  const ParseResult.ok(this.value)
      : error = null,
        newOptionLabel = null;
  const ParseResult.error(this.error)
      : value = null,
        newOptionLabel = null;

  /// Text matched no option; caller may offer to create one.
  const ParseResult.newOption(this.newOptionLabel)
      : value = null,
        error = null;
  final Value value;
  final String? error;
  final String? newOptionLabel;
  bool get isOk => error == null && newOptionLabel == null;
}

const _diacritics = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'ç': 'c', 'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ñ': 'n', 'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ù': 'u',
  'ú': 'u', 'û': 'u', 'ü': 'u', 'ý': 'y', 'ÿ': 'y', 'ß': 'ss',
};

/// Case- and (common Latin) diacritic-insensitive form used by BOTH the in-memory reference and
/// the SQL layer, so ordering and `contains` agree by construction.
String foldText(String s) {
  final lower = s.toLowerCase();
  final b = StringBuffer();
  for (final r in lower.runes) {
    final ch = String.fromCharCode(r);
    b.write(_diacritics[ch] ?? ch);
  }
  return b.toString();
}

DateTime? parseDate(String s) {
  final t = s.trim();
  final dateOnly = RegExp(r'^\d{4}-\d{2}-\d{2}$');
  if (dateOnly.hasMatch(t)) {
    final d = DateTime.tryParse('${t}T00:00:00Z');
    // reject overflow such as 2026-02-31 (DateTime normalises silently)
    if (d == null || d.toIso8601String().substring(0, 10) != t) return null;
    return d;
  }
  final d = DateTime.tryParse(t);
  return d?.toUtc();
}

/// UTC day number of an epoch-milliseconds instant (floored, correct for pre-1970 dates).
int dayNumber(int epochMs) => (epochMs / 86400000).floor();

abstract final class Values {
  static bool isEmpty(Value v) => v == null || (v is String && v.isEmpty) || (v is List && v.isEmpty);

  /// Returns an error message (plain language) or null when [v] may be written to [def].
  static String? validate(PropertyDef def, Value v) {
    if (v == null) return null;
    final t = def.type;
    switch (t) {
      case PropertyType.text:
      case PropertyType.richText:
        if (v is! String) return 'Expected text.';
        return v.length > 10000 ? 'Text is too long (max 10,000 characters).' : null;
      case PropertyType.url:
      case PropertyType.email:
      case PropertyType.phone:
        if (v is! String) return 'Expected text.';
        return v.length > 2000 ? 'Value is too long.' : null; // malformed values are kept but flagged (isWellFormed)
      case PropertyType.number:
      case PropertyType.percent:
        if (v is! num || v.isNaN || v.isInfinite) return 'Enter a valid number.';
        return null;
      case PropertyType.progress:
        if (v is! num || v.isNaN || v < 0 || v > 100) return 'Progress must be between 0 and 100.';
        return null;
      case PropertyType.currency:
        return v is int ? null : 'Enter a valid amount.';
      case PropertyType.checkbox:
        return v is bool ? null : 'Expected checked or unchecked.';
      case PropertyType.date:
        return v is String && parseDate(v) != null ? null : 'Enter a valid date.';
      case PropertyType.dateRange:
        if (v is! Map) return 'Expected a date range.';
        final s = v['start'], e = v['end'];
        if (s is! String || parseDate(s) == null) return 'Enter a valid start date.';
        if (e != null) {
          if (e is! String || parseDate(e) == null) return 'Enter a valid end date.';
          if (parseDate(e)!.isBefore(parseDate(s)!)) return 'The end date can\'t be before the start date.';
        }
        return null;
      case PropertyType.select:
      case PropertyType.status:
        if (v is! String) return 'Expected an option.';
        return def.option(v) == null ? 'That option no longer exists.' : null;
      case PropertyType.multiSelect:
        if (v is! List || v.any((e) => e is! String)) return 'Expected a list of options.';
        if (v.toSet().length != v.length) return 'Duplicate options.';
        return v.every((id) => def.option(id as String) != null) ? null : 'One of those options no longer exists.';
      case PropertyType.person:
      case PropertyType.files:
      case PropertyType.image:
        if (v is! List || v.any((e) => e is! String)) return 'Expected a list.';
        return v.toSet().length == v.length ? null : 'Duplicate entries.';
      case PropertyType.relation:
      case PropertyType.rollup:
      case PropertyType.formula:
      case PropertyType.createdTime:
      case PropertyType.lastEditedTime:
        return 'This property is calculated and can\'t be edited directly.';
    }
  }

  /// Canonical form: trims text, drops duplicates, coerces ints. Call before [validate]/storage.
  static Value normalize(PropertyDef def, Value v) {
    if (v == null) return null;
    switch (def.type) {
      case PropertyType.text:
      case PropertyType.url:
      case PropertyType.email:
      case PropertyType.phone:
        if (v is! String) return v;
        final s = v.trim();
        return s.isEmpty ? null : s;
      case PropertyType.richText:
        return v is String && v.trim().isEmpty ? null : v;
      case PropertyType.multiSelect:
      case PropertyType.person:
      case PropertyType.files:
      case PropertyType.image:
        if (v is! List) return v;
        final seen = <Object?>{};
        final out = [for (final e in v) if (seen.add(e)) e];
        return out.isEmpty ? null : out;
      case PropertyType.number:
      case PropertyType.percent:
      case PropertyType.progress:
        return v is num && v == v.roundToDouble() && v.abs() < 1e15 ? v.toInt() : v;
      case PropertyType.date:
        if (v is! String) return v;
        final d = parseDate(v);
        if (d == null) return v;
        return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v.trim()) ? v.trim() : d.toIso8601String();
      default:
        return v;
    }
  }

  static bool isWellFormed(PropertyDef def, Value v) {
    if (v is! String || v.isEmpty) return true;
    switch (def.type) {
      case PropertyType.url:
        final u = Uri.tryParse(v);
        return u != null && (u.scheme == 'http' || u.scheme == 'https') && u.host.isNotEmpty;
      case PropertyType.email:
        return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(v);
      case PropertyType.phone:
        return RegExp(r'^\+?[0-9 ()\-.]{5,25}$').hasMatch(v);
      default:
        return true;
    }
  }

  /// Parse user/CSV/paste text into a value for [def].
  static ParseResult parseText(PropertyDef def, String input) {
    final s = input.trim();
    if (s.isEmpty) return const ParseResult.ok(null);
    switch (def.type) {
      case PropertyType.text:
      case PropertyType.richText:
      case PropertyType.url:
      case PropertyType.email:
      case PropertyType.phone:
        return ParseResult.ok(s);
      case PropertyType.number:
      case PropertyType.percent:
      case PropertyType.progress:
        final n = _parseNumber(s.replaceAll('%', ''));
        if (n == null) return ParseResult.error('"$s" is not a number.');
        var v = n;
        if (def.type == PropertyType.percent && def.percentIsFraction && s.contains('%')) v = n / 100;
        return ParseResult.ok(normalize(def, v));
      case PropertyType.currency:
        final n = _parseNumber(s.replaceAll(RegExp(r'[^\d,.\-]'), ''));
        if (n == null) return ParseResult.error('"$s" is not an amount.');
        var f = 1;
        for (var i = 0; i < def.decimals; i++) {
          f *= 10;
        }
        return ParseResult.ok((n * f).round());
      case PropertyType.checkbox:
        final l = s.toLowerCase();
        if (const {'true', 'yes', 'y', '1', 'x', '✓', 'checked', 'done'}.contains(l)) return const ParseResult.ok(true);
        if (const {'false', 'no', 'n', '0', 'unchecked'}.contains(l)) return const ParseResult.ok(false);
        return ParseResult.error('"$s" is not yes/no.');
      case PropertyType.date:
        final d = _parseLooseDate(s);
        return d == null ? ParseResult.error('"$s" is not a date.') : ParseResult.ok(d);
      case PropertyType.dateRange:
        final parts = s.split(RegExp(r'\s*(?:→|–|—|to|\.\.)\s*'));
        final a = _parseLooseDate(parts.first);
        final b = parts.length > 1 ? _parseLooseDate(parts[1]) : null;
        if (a == null || (parts.length > 1 && b == null)) return ParseResult.error('"$s" is not a date range.');
        return ParseResult.ok({'start': a, 'end': ?b});
      case PropertyType.select:
      case PropertyType.status:
        final o = _optionByLabel(def, s);
        return o != null ? ParseResult.ok(o.id) : ParseResult.newOption(s);
      case PropertyType.multiSelect:
        final ids = <String>[];
        for (final part in s.split(RegExp(r'\s*[,;|]\s*')).where((p) => p.isNotEmpty)) {
          final o = _optionByLabel(def, part);
          if (o == null) return ParseResult.newOption(part);
          if (!ids.contains(o.id)) ids.add(o.id);
        }
        return ParseResult.ok(ids.isEmpty ? null : ids);
      default:
        return ParseResult.error('This property can\'t be imported.');
    }
  }

  static SelectOption? _optionByLabel(PropertyDef def, String label) {
    final f = foldText(label.trim());
    for (final o in def.options) {
      if (foldText(o.label) == f) return o;
    }
    return null;
  }

  /// Accepts 1,234.56 · 1.234,56 · 1234,5 · -12
  static double? _parseNumber(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return null;
    final lastDot = s.lastIndexOf('.'), lastComma = s.lastIndexOf(',');
    if (lastDot >= 0 && lastComma >= 0) {
      if (lastComma > lastDot) {
        s = s.replaceAll('.', '').replaceAll(',', '.');
      } else {
        s = s.replaceAll(',', '');
      }
    } else if (lastComma >= 0) {
      final after = s.length - lastComma - 1;
      s = (after == 3 && !s.startsWith('0') && s.indexOf(',') == lastComma && s.length > 4)
          ? s.replaceAll(',', '') // 1,234 -> thousands
          : s.replaceAll(',', '.');
    }
    final n = double.tryParse(s);
    return (n == null || n.isNaN || n.isInfinite) ? null : n;
  }

  static String? _parseLooseDate(String s) {
    final t = s.trim();
    final iso = parseDate(t);
    if (iso != null) return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(t) ? t : iso.toIso8601String();
    final m = RegExp(r'^(\d{1,2})[/.](\d{1,2})[/.](\d{4})$').firstMatch(t); // D/M/Y (day first)
    if (m != null) {
      final d = '${m[3]}-${m[2]!.padLeft(2, '0')}-${m[1]!.padLeft(2, '0')}';
      return parseDate(d) == null ? null : d;
    }
    return null;
  }

  /// Display text for the table / detail panel.
  static String format(PropertyDef def, Value v) {
    if (isEmpty(v)) return '';
    switch (def.type) {
      case PropertyType.number:
        return '${def.prefix}${_fixed(v as num, def.decimals)}${def.suffix}';
      case PropertyType.percent:
        final n = v as num;
        return '${_fixed(def.percentIsFraction ? n * 100 : n, def.decimals)}%';
      case PropertyType.progress:
        return '${_fixed(v as num, 0)}%';
      case PropertyType.currency:
        final minor = v as int;
        var f = 1;
        for (var i = 0; i < def.decimals; i++) {
          f *= 10;
        }
        final neg = minor < 0;
        return '${neg ? '-' : ''}${def.currencySymbol}${_fixed(minor.abs() / f, def.decimals)}';
      case PropertyType.checkbox:
        return v == true ? '✓' : '';
      case PropertyType.date:
        return _fmtDate(v as String, def.includeTime);
      case PropertyType.dateRange:
        final m = v as Map;
        final s = _fmtDate(m['start'] as String, def.includeTime);
        return m['end'] == null ? s : '$s → ${_fmtDate(m['end'] as String, def.includeTime)}';
      case PropertyType.select:
      case PropertyType.status:
        return def.option(v as String)?.label ?? '(removed)';
      case PropertyType.multiSelect:
        return (v as List).map((id) => def.option(id as String)?.label ?? '(removed)').join(', ');
      case PropertyType.person:
      case PropertyType.files:
      case PropertyType.image:
        return '${(v as List).length}';
      default:
        return v.toString();
    }
  }

  static String _fixed(num n, int decimals) {
    final s = n.toStringAsFixed(decimals);
    final parts = s.split('.');
    final neg = parts[0].startsWith('-');
    final digits = neg ? parts[0].substring(1) : parts[0];
    final grouped = digits.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
    return '${neg ? '-' : ''}$grouped${parts.length > 1 ? '.${parts[1]}' : ''}';
  }

  static String _fmtDate(String iso, bool time) {
    final d = parseDate(iso);
    if (d == null) return iso;
    final day = '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    if (!time || RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(iso)) return day;
    return '$day ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  /// Map a (validated) value to storage columns. Returns null for empty/computed/relation.
  static CellStorage? toStorage(PropertyDef def, Value v) {
    if (v == null || !def.type.isStored) return null;
    switch (def.type) {
      case PropertyType.text:
      case PropertyType.richText:
      case PropertyType.url:
      case PropertyType.email:
      case PropertyType.phone:
        return CellStorage(text: v as String, sort: foldText(v));
      case PropertyType.number:
      case PropertyType.percent:
      case PropertyType.progress:
        return CellStorage(num: (v as num).toDouble());
      case PropertyType.currency:
        return CellStorage(intVal: v as int, num: v.toDouble());
      case PropertyType.checkbox:
        return CellStorage(intVal: (v as bool) ? 1 : 0);
      case PropertyType.date:
        final ms = parseDate(v as String)!.millisecondsSinceEpoch;
        return CellStorage(text: v, num: ms.toDouble(), day: dayNumber(ms));
      case PropertyType.dateRange:
        final m = v as Map;
        final ms = parseDate(m['start'] as String)!.millisecondsSinceEpoch;
        return CellStorage(json: _json(m), num: ms.toDouble(), day: dayNumber(ms));
      case PropertyType.select:
      case PropertyType.status:
        // Option rank is NOT stored (options can be reordered); queries derive it from the current options.
        return CellStorage(text: v as String);
      case PropertyType.multiSelect:
        final l = (v as List).cast<String>();
        return CellStorage(json: _json(l));
      case PropertyType.person:
      case PropertyType.files:
      case PropertyType.image:
        return CellStorage(json: _json(v));
      default:
        return null;
    }
  }

  static String _json(Object o) => _enc(o);

  static String _enc(Object? o) {
    if (o == null) return 'null';
    if (o is String) {
      final b = StringBuffer('"');
      for (final r in o.runes) {
        switch (r) {
          case 0x22: b.write(r'\"');
          case 0x5c: b.write(r'\\');
          case 0x0a: b.write(r'\n');
          case 0x0d: b.write(r'\r');
          case 0x09: b.write(r'\t');
          default:
            if (r < 0x20) {
              b.write('\\u${r.toRadixString(16).padLeft(4, '0')}');
            } else {
              b.writeCharCode(r);
            }
        }
      }
      return (b..write('"')).toString();
    }
    if (o is num || o is bool) return o.toString();
    if (o is List) return '[${o.map(_enc).join(',')}]';
    if (o is Map) return '{${o.entries.map((e) => '${_enc(e.key.toString())}:${_enc(e.value)}').join(',')}}';
    throw ArgumentError('Unsupported ${o.runtimeType}');
  }
}
