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

const _languages = {
  'en': 'English', 'hi': 'Hindi', 'ur': 'Urdu', 'ar': 'Arabic', 'bn': 'Bengali', 'ta': 'Tamil', 'te': 'Telugu',
  'mr': 'Marathi', 'gu': 'Gujarati', 'pa': 'Punjabi', 'fr': 'French', 'de': 'German', 'es': 'Spanish',
  'pt': 'Portuguese', 'it': 'Italian', 'nl': 'Dutch', 'ru': 'Russian', 'tr': 'Turkish', 'zh': 'Chinese',
  'ja': 'Japanese', 'ko': 'Korean', 'id': 'Indonesian', 'fa': 'Persian', 'pl': 'Polish', 'sv': 'Swedish',
};
const _regions = {
  'US': 'United States', 'GB': 'United Kingdom', 'IN': 'India', 'AU': 'Australia', 'CA': 'Canada', 'PK': 'Pakistan',
  'FR': 'France', 'DE': 'Germany', 'ES': 'Spain', 'MX': 'Mexico', 'BR': 'Brazil', 'PT': 'Portugal', 'IE': 'Ireland',
  'ZA': 'South Africa', 'SA': 'Saudi Arabia', 'EG': 'Egypt', 'CN': 'China', 'TW': 'Taiwan', 'JP': 'Japan', 'KR': 'Korea',
};

/// "en-US" / "en_GB" -> "English (United States)"; codes we do not know are shown as they are.
String localeLabel(String locale) {
  final parts = locale.replaceAll('_', '-').split('-');
  final lang = _languages[parts.first.toLowerCase()] ?? parts.first;
  if (parts.length < 2 || parts[1].isEmpty) return lang;
  final region = _regions[parts[1].toUpperCase()] ?? parts[1];
  return '$lang ($region)';
}

/// The language part of a locale ("en-US" -> "en").
String languageOf(String locale) => locale.replaceAll('_', '-').split('-').first.toLowerCase();
