/// Splits [text] into pieces of at most [max] characters, cutting after a sentence end (or a space) where it can,
/// because phone voices refuse very long input. Empty / blank text gives no pieces.
List<String> chunkText(String text, {int max = 3000}) {
  final clean = text.replaceAll(RegExp(r'[ \t]+'), ' ').replaceAll(RegExp(r'\s*\n\s*'), '\n').trim();
  if (clean.isEmpty) return const [];
  final out = <String>[];
  var rest = clean;
  while (rest.length > max) {
    var cut = _lastBreak(rest, max);
    if (cut <= 0) cut = max;
    out.add(rest.substring(0, cut).trim());
    rest = rest.substring(cut).trim();
  }
  if (rest.isNotEmpty) out.add(rest);
  return out;
}

int _lastBreak(String s, int max) {
  final window = s.substring(0, max);
  for (final re in [RegExp('[.!?][\\u0022\\u0027)\\]]*\\s'), RegExp(r'\n'), RegExp(r'\s')]) {
    final m = re.allMatches(window).lastOrNull;
    if (m != null && m.end > max ~/ 4) return m.end;
  }
  return -1;
}

/// Reading speeds offered in the voice bar.
const speechRates = <double>[0.75, 1.0, 1.25, 1.5, 2.0];

String rateLabel(double r) => '${r == r.roundToDouble() ? r.round() : r}x';
