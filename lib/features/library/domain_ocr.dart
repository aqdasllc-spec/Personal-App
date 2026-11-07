import 'dart:convert';

import '../../data/local/app_database.dart';
import 'data/ocr.dart';

String encodeLines(List<OcrLine> lines) => jsonEncode([
  for (final l in lines)
    {
      't': l.text,
      'r': [l.left, l.top, l.right, l.bottom],
    },
]);

/// Forgiving: unreadable data gives no lines.
List<OcrLine> decodeLines(String json) {
  try {
    final out = <OcrLine>[];
    for (final e in jsonDecode(json) as List) {
      if (e is! Map) continue;
      final t = e['t'], r = e['r'];
      if (t is String &&
          r is List &&
          r.length == 4 &&
          r.every((v) => v is num)) {
        out.add(
          OcrLine(
            t,
            (r[0] as num).toDouble(),
            (r[1] as num).toDouble(),
            (r[2] as num).toDouble(),
            (r[3] as num).toDouble(),
          ),
        );
      }
    }
    return out;
  } catch (_) {
    return const [];
  }
}

/// A search hit in recognised text.
class OcrMatch {
  const OcrMatch(this.page, this.line);
  final int page;
  final OcrLine line;
}

String _norm(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

/// Finds [query] (case-insensitive, spaces collapsed) in the recognised lines of [pages], in page order.
/// A page's lines are also joined, so a phrase that wraps onto the next line is still found (the hit is the first line).
List<OcrMatch> searchPages(Iterable<PageTextRow> pages, String query) {
  final q = _norm(query);
  if (q.isEmpty) return const [];
  final sorted = [...pages]..sort((a, b) => a.page.compareTo(b.page));
  final out = <OcrMatch>[];
  for (final p in sorted) {
    final lines = decodeLines(p.boxes);
    final used = <int>{};
    for (var i = 0; i < lines.length; i++) {
      if (_norm(lines[i].text).contains(q)) {
        out.add(OcrMatch(p.page, lines[i]));
        used.add(i);
      }
    }
    // phrase split over two lines
    for (var i = 0; i + 1 < lines.length; i++) {
      if (used.contains(i) || used.contains(i + 1)) continue;
      if (_norm('${lines[i].text} ${lines[i + 1].text}').contains(q)) {
        out.add(OcrMatch(p.page, lines[i]));
      }
    }
  }
  out.sort(
    (a, b) => a.page != b.page
        ? a.page.compareTo(b.page)
        : a.line.top.compareTo(b.line.top),
  );
  return out;
}
