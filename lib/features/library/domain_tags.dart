import 'dart:convert';

const maxTags = 20;
const maxTagLength = 30;

/// Reads the stored JSON list; anything unreadable gives no tags.
List<String> decodeTags(String json) {
  try {
    return [
      for (final t in jsonDecode(json) as List)
        if (t is String && t.trim().isNotEmpty) t,
    ];
  } catch (_) {
    return const [];
  }
}

String encodeTags(List<String> tags) => jsonEncode(tags);

/// Turns what the user typed ("Work, to read  #safety") into clean tags: split on commas / newlines / `#`,
/// trimmed, inner spaces collapsed, no duplicates ignoring case (first spelling wins), at most [maxTags],
/// each cut to [maxTagLength].
List<String> normalizeTags(String input) {
  final seen = <String>{};
  final out = <String>[];
  for (final raw in input.split(RegExp(r'[,\n#]'))) {
    var t = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (t.isEmpty) continue;
    if (t.length > maxTagLength) t = t.substring(0, maxTagLength).trim();
    if (seen.add(t.toLowerCase())) out.add(t);
    if (out.length == maxTags) break;
  }
  return out;
}

String tagsToText(List<String> tags) => tags.join(', ');
