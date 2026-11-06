/// Fractional indexing for ordering rows/columns/views: reordering one item writes one key.
/// Keys are base-62 strings; lexicographic (byte) order == logical order. Always use [between].
const _digits = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
const _min = 0, _max = 61;

/// Returns a key strictly between [a] and [b] (either may be null for open ends).
/// Throws if `a >= b`.
String between(String? a, String? b) {
  if (a != null && b != null && a.compareTo(b) >= 0) throw ArgumentError('a ($a) must be < b ($b)');
  final out = StringBuffer();
  var i = 0;
  var bounded = b != null; // still constrained by upper bound
  while (true) {
    final da = (a != null && i < a.length) ? _digits.indexOf(a[i]) : _min;
    final db = bounded ? (i < b!.length ? _digits.indexOf(b[i]) : _max + 1) : _max + 1;
    if (da == db) {
      out.write(_digits[da]);
      i++;
      continue;
    }
    if (db - da > 1) {
      out.write(_digits[(da + db) ~/ 2]);
      return out.toString();
    }
    // adjacent digits: keep a's digit and continue unbounded above
    out.write(_digits[da]);
    bounded = false;
    i++;
    if (a == null || i >= a.length) {
      // fell off the end of a: any larger tail works
      out.write(_digits[(_min + _max + 1) ~/ 2]);
      return out.toString();
    }
  }
}

/// [count] ascending keys after [after] (or from scratch), for bulk inserts/imports.
List<String> keysAfter(String? after, int count) {
  final keys = <String>[];
  var prev = after;
  for (var i = 0; i < count; i++) {
    prev = between(prev, null);
    keys.add(prev);
  }
  return keys;
}
