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

const _stop = <String, Set<String>>{
  'en': {'the', 'and', 'of', 'to', 'is', 'in', 'that', 'it', 'was', 'for', 'with', 'as', 'are', 'this', 'be', 'on', 'have', 'not', 'by', 'from'},
  'fr': {'le', 'la', 'les', 'des', 'et', 'est', 'une', 'un', 'que', 'pour', 'dans', 'qui', 'pas', 'sur', 'avec', 'au', 'du', 'ce', 'il', 'sont'},
  'de': {'der', 'die', 'und', 'das', 'ist', 'nicht', 'ein', 'eine', 'mit', 'den', 'von', 'zu', 'auf', 'für', 'sich', 'dem', 'auch', 'es', 'dass', 'wird'},
  'es': {'el', 'la', 'de', 'que', 'y', 'en', 'los', 'del', 'las', 'por', 'con', 'una', 'para', 'es', 'se', 'no', 'su', 'al', 'lo', 'como'},
  'pt': {'o', 'a', 'de', 'que', 'e', 'do', 'da', 'em', 'um', 'para', 'com', 'não', 'uma', 'os', 'no', 'se', 'na', 'por', 'mais', 'as'},
  'it': {'il', 'di', 'che', 'e', 'la', 'un', 'per', 'in', 'non', 'una', 'con', 'del', 'le', 'si', 'da', 'sono', 'come', 'più', 'ma', 'gli'},
  'nl': {'de', 'het', 'een', 'van', 'en', 'in', 'is', 'dat', 'op', 'te', 'niet', 'met', 'voor', 'zijn', 'ook', 'aan', 'er', 'maar', 'om', 'als'},
};

/// Guesses the language (two-letter code) of [text] from its letters and common words; null when there is too little to go on.
/// Latin text defaults to English when no other language stands out. A guess, not a promise: names and quotes can fool it.
String? guessLanguage(String text) {
  final sample = text.length > 3000 ? text.substring(0, 3000) : text;
  final counts = <String, int>{};
  var letters = 0;
  void add(String k) => counts[k] = (counts[k] ?? 0) + 1;
  for (final r in sample.runes) {
    if (r >= 0x0900 && r <= 0x097F) {
      add('hi');
    } else if (r >= 0x0980 && r <= 0x09FF) {
      add('bn');
    } else if (r >= 0x0A00 && r <= 0x0A7F) {
      add('pa');
    } else if (r >= 0x0A80 && r <= 0x0AFF) {
      add('gu');
    } else if (r >= 0x0B80 && r <= 0x0BFF) {
      add('ta');
    } else if (r >= 0x0C00 && r <= 0x0C7F) {
      add('te');
    } else if ((r >= 0x0600 && r <= 0x06FF) || (r >= 0x0750 && r <= 0x077F) || (r >= 0xFB50 && r <= 0xFDFF) || (r >= 0xFE70 && r <= 0xFEFF)) {
      add('arabic');
    } else if (r >= 0x0400 && r <= 0x04FF) {
      add('ru');
    } else if (r >= 0x3040 && r <= 0x30FF) {
      add('ja');
    } else if (r >= 0x4E00 && r <= 0x9FFF) {
      add('zh');
    } else if (r >= 0xAC00 && r <= 0xD7AF) {
      add('ko');
    } else if ((r >= 0x41 && r <= 0x5A) || (r >= 0x61 && r <= 0x7A) || (r >= 0xC0 && r <= 0x24F)) {
      add('latin');
    } else {
      continue;
    }
    letters++;
  }
  if (letters < 20) return null;
  final top = counts.entries.reduce((a, b) => a.value >= b.value ? a : b);
  if (top.value < letters * 0.2) return null;
  var key = top.key;
  if (key == 'zh' && (counts['ja'] ?? 0) > 0) key = 'ja'; // kanji with kana is Japanese
  if (key == 'arabic') {
    if (RegExp('[\u0679\u0688\u0691\u06BA\u06D2]').hasMatch(sample)) return 'ur';
    if (RegExp('[\u067E\u0686\u0698\u06AF]').hasMatch(sample)) return 'fa';
    return 'ar';
  }
  if (key != 'latin') return key;
  final words = RegExp(r"[\p{L}']+", unicode: true).allMatches(sample.toLowerCase()).map((m) => m.group(0)!);
  final score = <String, int>{for (final k in _stop.keys) k: 0};
  for (final w in words) {
    for (final e in _stop.entries) {
      if (e.value.contains(w)) score[e.key] = score[e.key]! + 1;
    }
  }
  final best = score.entries.reduce((a, b) => a.value >= b.value ? a : b);
  return best.value >= 3 ? best.key : 'en';
}

/// The best installed voice for [language] (two-letter code): [preferred] when it already speaks it, else the first one.
/// [voices] are (name, locale) pairs.
({String name, String locale})? voiceFor(String language, List<({String name, String locale})> voices, {({String name, String locale})? preferred}) {
  if (preferred != null && languageOf(preferred.locale) == language) return preferred;
  for (final v in voices) {
    if (languageOf(v.locale) == language) return v;
  }
  return null;
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
