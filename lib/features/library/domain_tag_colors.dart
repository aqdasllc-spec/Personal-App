import 'dart:convert';

import 'package:flutter/painting.dart';

/// The colours a tag can have. The index is what is stored, so keep the order.
const tagPalette = <(String, Color)>[
  ('Red', Color(0xFFE5484D)),
  ('Orange', Color(0xFFF76B15)),
  ('Yellow', Color(0xFFE5B800)),
  ('Green', Color(0xFF30A46C)),
  ('Teal', Color(0xFF12A594)),
  ('Blue', Color(0xFF3E63DD)),
  ('Purple', Color(0xFF8E4EC6)),
  ('Pink', Color(0xFFD6409F)),
];

String tagKey(String tag) => tag.trim().toLowerCase();

/// Reads the stored JSON map {tag: palette index}; anything unreadable or out of range is dropped.
Map<String, int> decodeTagColors(String? json) {
  if (json == null || json.isEmpty) return const {};
  try {
    final out = <String, int>{};
    (jsonDecode(json) as Map).forEach((k, v) {
      if (k is String && v is int && v >= 0 && v < tagPalette.length) out[tagKey(k)] = v;
    });
    return out;
  } catch (_) {
    return const {};
  }
}

String encodeTagColors(Map<String, int> m) => jsonEncode(m);

/// The tag's colour, or null when it has none.
Color? colorOfTag(Map<String, int> colors, String tag) {
  final i = colors[tagKey(tag)];
  return i == null ? null : tagPalette[i].$2;
}

String? colorNameOfTag(Map<String, int> colors, String tag) {
  final i = colors[tagKey(tag)];
  return i == null ? null : tagPalette[i].$1;
}
