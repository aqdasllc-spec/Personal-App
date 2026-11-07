import 'dart:convert';


/// Pen colours: black first, then the tag palette.
const penColors = <(String, int)>[
  ('Black', 0xFF202124),
  ('Red', 0xFFE5484D),
  ('Blue', 0xFF3E63DD),
  ('Green', 0xFF30A46C),
  ('Orange', 0xFFF76B15),
  ('Purple', 0xFF8E4EC6),
];

/// Pen widths as a fraction of the page width.
const penWidths = <(String, double)>[
  ('Fine', 0.002),
  ('Medium', 0.004),
  ('Thick', 0.008),
];

/// One pen stroke: points are x, y pairs as fractions (0..1) of the page.
class Stroke {
  const Stroke(this.color, this.width, this.points);
  final int color; // index into [penColors]
  final double width;
  final List<double> points;

  Map<String, Object> toJson() => {'c': color, 'w': width, 'p': points};
}

String encodeStrokes(List<Stroke> s) => jsonEncode([for (final x in s) x.toJson()]);

/// Forgiving: unreadable data or a bad stroke is skipped.
List<Stroke> decodeStrokes(String json) {
  try {
    final out = <Stroke>[];
    for (final e in jsonDecode(json) as List) {
      if (e is! Map) continue;
      final c = e['c'], w = e['w'], p = e['p'];
      if (c is! int || c < 0 || c >= penColors.length) continue;
      if (w is! num || w <= 0 || w > 0.1) continue;
      if (p is! List || p.length < 2 || p.length.isOdd || !p.every((v) => v is num)) continue;
      out.add(Stroke(c, w.toDouble(), [for (final v in p) (v as num).toDouble().clamp(0.0, 1.0)]));
    }
    return out;
  } catch (_) {
    return const [];
  }
}

/// Thins a dragged line: drops points closer than [minStep] to the last kept one (always keeps the last).
List<double> simplify(List<double> pts, {double minStep = 0.0015}) {
  if (pts.length <= 4) return pts;
  final out = <double>[pts[0], pts[1]];
  for (var i = 2; i < pts.length - 2; i += 2) {
    final dx = pts[i] - out[out.length - 2], dy = pts[i + 1] - out[out.length - 1];
    if (dx * dx + dy * dy >= minStep * minStep) out.addAll([pts[i], pts[i + 1]]);
  }
  out.addAll([pts[pts.length - 2], pts[pts.length - 1]]);
  return out;
}

/// Colour name of a pen colour (kept next to the palette so labels stay in sync).
String penColorName(int i) => penColors[i].$1;

