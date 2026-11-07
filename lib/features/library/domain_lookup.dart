/// Longest piece of text sent to a web page when looking something up.
const maxLookUpLength = 300;

/// Tidy selected text for a look-up: spaces collapsed, cut to [maxLookUpLength].
String cleanLookUp(String text) {
  final t = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return t.length > maxLookUpLength ? t.substring(0, maxLookUpLength).trim() : t;
}

/// A web search for the meaning of [text].
Uri dictionaryUri(String text) =>
    Uri.https('www.google.com', '/search', {'q': 'define ${cleanLookUp(text)}'});

/// Google Translate with [text] already filled in, translating into [targetLanguage] (a two-letter code).
Uri translateUri(String text, String targetLanguage) => Uri.https('translate.google.com', '/', {
  'sl': 'auto',
  'tl': targetLanguage.isEmpty ? 'en' : targetLanguage,
  'text': cleanLookUp(text),
  'op': 'translate',
});
