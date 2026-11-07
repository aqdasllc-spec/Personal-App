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


/// Does the point (x, y), as fractions of the page, touch the stroke? [tol] is the reach around the line.
bool strokeTouches(Stroke s, double x, double y, {double tol = 0.025}) {
  final p = s.points;
  final r = tol + s.width / 2;
  if (p.length == 2) return (p[0] - x) * (p[0] - x) + (p[1] - y) * (p[1] - y) <= r * r;
  for (var i = 0; i + 3 < p.length; i += 2) {
    if (_segDist2(x, y, p[i], p[i + 1], p[i + 2], p[i + 3]) <= r * r) return true;
  }
  return false;
}

double _segDist2(double px, double py, double ax, double ay, double bx, double by) {
  final dx = bx - ax, dy = by - ay;
  final len2 = dx * dx + dy * dy;
  var t = len2 == 0 ? 0.0 : ((px - ax) * dx + (py - ay) * dy) / len2;
  t = t.clamp(0.0, 1.0);
  final cx = ax + t * dx - px, cy = ay + t * dy - py;
  return cx * cx + cy * cy;
}

/// The strokes left after rubbing out at (x, y).
List<Stroke> eraseAt(List<Stroke> strokes, double x, double y, {double tol = 0.025}) =>
    [for (final s in strokes) if (!strokeTouches(s, x, y, tol: tol)) s];
