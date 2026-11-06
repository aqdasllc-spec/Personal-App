import 'dart:convert';
import 'dart:ui' show Color;

/// A selection the reader wants to turn into a highlight (page coordinates of the PDF, one rect per text line).
class HighlightDraft {
  const HighlightDraft({
    required this.page,
    required this.rects,
    required this.text,
  });
  final int page;
  final List<List<double>>
  rects; // [left, top, right, bottom], PDF coordinates (top > bottom)
  final String text;
}

const highlightColors = ['yellow', 'green', 'blue', 'pink'];

Color highlightColor(String name) => switch (name) {
  'green' => const Color(0xFF7BD389),
  'blue' => const Color(0xFF7DB8F0),
  'pink' => const Color(0xFFF08FB4),
  _ => const Color(0xFFFFD84D),
};

String nextHighlightColor(String current) =>
    highlightColors[(highlightColors.indexOf(current) + 1) %
        highlightColors.length];

String encodeRects(List<List<double>> rects) => jsonEncode(rects);

List<List<double>> decodeRects(String json) {
  try {
    return [
      for (final r in (jsonDecode(json) as List))
        [for (final v in (r as List)) (v as num).toDouble()],
    ].where((r) => r.length == 4).toList();
  } catch (_) {
    return const [];
  }
}

/// Merges per-character boxes (PDF coordinates, top > bottom) into one box per line of text, so a
/// highlight is a few clean bars instead of hundreds of tiny rectangles.
/// Characters without a box (spaces in some PDFs) are skipped.
List<List<double>> lineRectsOf(Iterable<List<double>> chars) {
  final lines = <List<double>>[];
  List<double>? cur;
  for (final c in chars) {
    if (c.length != 4 || c[0] >= c[2] || c[1] <= c[3]) continue;
    if (cur == null) {
      cur = [...c];
      continue;
    }
    final overlap =
        (c[1] < cur[1] ? c[1] : cur[1]) - (c[3] > cur[3] ? c[3] : cur[3]);
    final smaller = (c[1] - c[3]) < (cur[1] - cur[3])
        ? (c[1] - c[3])
        : (cur[1] - cur[3]);
    if (overlap >= smaller * 0.5) {
      cur = [
        c[0] < cur[0] ? c[0] : cur[0],
        c[1] > cur[1] ? c[1] : cur[1],
        c[2] > cur[2] ? c[2] : cur[2],
        c[3] < cur[3] ? c[3] : cur[3],
      ];
    } else {
      lines.add(cur);
      cur = [...c];
    }
  }
  if (cur != null) lines.add(cur);
  return lines;
}
