import 'dart:convert';
import 'dart:io' show gzip;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// One surah's details (from the bundled data; see tool/quran/build_assets.py for the sources).
@immutable
class Surah {
  const Surah({
    required this.number,
    required this.name,
    required this.english,
    required this.arabic,
    required this.revelation,
    required this.ayahCount,
    required this.firstIndex,
  });

  final int number;

  /// Transliterated name, e.g. "Al-Faatiha".
  final String name;

  /// Meaning in English, e.g. "The Opening".
  final String english;

  /// Name in Arabic script.
  final String arabic;

  /// "Meccan" or "Medinan".
  final String revelation;
  final int ayahCount;

  /// Position of this surah's first ayah in the whole Quran (0-based).
  final int firstIndex;

  String get revelationUrdu => revelation == 'Meccan' ? 'مکی' : 'مدنی';
}

/// The whole Quran: Arabic (Uthmani Hafs), English (Saheeh International) and Urdu (Fateh Muhammad Jalandhry),
/// aligned ayah by ayah (6236 ayahs). Read only; the texts are shown exactly as published.
class QuranData {
  QuranData({
    required this.surahs,
    required this.arabic,
    required this.english,
    required this.urdu,
    required this.juzStarts,
    required this.sajdas,
  }) : assert(arabic.length == english.length && english.length == urdu.length);

  final List<Surah> surahs;
  final List<String> arabic, english, urdu;

  /// Where each of the 30 juz begins: (surah, ayah).
  final List<(int, int)> juzStarts;

  /// Ayahs with a prostration of recitation: (surah, ayah).
  final Set<(int, int)> sajdas;

  int get ayahCount => arabic.length;

  Surah surah(int number) => surahs[number - 1];

  /// 0-based position of surah:ayah in the whole Quran (also the audio file number minus one).
  int indexOf(int surah, int ayah) => surahs[surah - 1].firstIndex + ayah - 1;

  /// surah:ayah of a 0-based position.
  (int, int) refOf(int index) {
    var lo = 0, hi = surahs.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (surahs[mid].firstIndex <= index) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return (surahs[lo].number, index - surahs[lo].firstIndex + 1);
  }

  /// The juz (1-30) an ayah belongs to.
  int juzOf(int surah, int ayah) {
    final i = indexOf(surah, ayah);
    var j = 1;
    for (var k = 0; k < juzStarts.length; k++) {
      if (indexOf(juzStarts[k].$1, juzStarts[k].$2) <= i) j = k + 1;
    }
    return j;
  }

  bool valid(int surah, int ayah) => surah >= 1 && surah <= surahs.length && ayah >= 1 && ayah <= surahs[surah - 1].ayahCount;

  /// The opening "In the name of Allah…" exactly as Al-Fatiha 1:1 has it (shown above every surah except 1 and 9).
  String get bismillah => arabic[0];

  static QuranData fromJson(Map<String, dynamic> j) {
    final surahs = <Surah>[];
    var first = 0;
    for (final s in (j['surahs'] as List)) {
      final r = s as List;
      surahs.add(
        Surah(
          number: r[0] as int,
          name: r[1] as String,
          english: r[2] as String,
          arabic: r[3] as String,
          revelation: r[4] as String,
          ayahCount: r[5] as int,
          firstIndex: first,
        ),
      );
      first += r[5] as int;
    }
    List<String> texts(String k) => [for (final t in (j[k] as List)) t as String];
    (int, int) pair(Object? p) => ((p as List)[0] as int, p[1] as int);
    return QuranData(
      surahs: surahs,
      arabic: texts('ar'),
      english: texts('en'),
      urdu: texts('ur'),
      juzStarts: [for (final p in (j['juz'] as List)) pair(p)],
      sajdas: {for (final p in (j['sajda'] as List)) pair(p)},
    );
  }
}

/// A hadith from Sahih al-Bukhari, in Arabic, English and Urdu.
@immutable
class Hadith {
  const Hadith({
    required this.number,
    required this.book,
    required this.inBook,
    required this.arabic,
    required this.english,
    required this.urdu,
    this.sayingStart = 0,
  });
  final num number;
  final int book, inBook;
  final String arabic, english, urdu;

  /// Where the Prophet's words begin in [urdu] (after the chain of narrators).
  final int sayingStart;

  /// The Urdu from the Prophet's words on, exactly as written, after "…" (the card shows this; the full text has
  /// the chain of narrators too).
  String get urduSaying => sayingStart > 0 && sayingStart < urdu.length ? '…${urdu.substring(sayingStart)}' : urdu;

  String get reference => 'Sahih al-Bukhari ${_n(number)}';
  String get referenceUrdu => 'صحیح بخاری، حدیث ${_n(number)}';
  static String _n(num n) => n == n.roundToDouble() ? '${n.toInt()}' : '$n';
}

class HadithData {
  HadithData(this.items);
  final List<Hadith> items;

  static HadithData fromJson(Map<String, dynamic> j) => HadithData([
    for (final r in (j['items'] as List))
      Hadith(
        number: (r as List)[0] as num,
        book: r[1] as int,
        inBook: r[2] as int,
        arabic: r[3] as String,
        english: r[4] as String,
        urdu: r[5] as String,
        sayingStart: r.length > 6 ? r[6] as int : 0,
      ),
  ]);
}

Map<String, dynamic> _gunzipJson(Uint8List bytes) => jsonDecode(utf8.decode(gzip.decode(bytes))) as Map<String, dynamic>;

Future<Map<String, dynamic>> _loadAsset(String path) async {
  final data = await rootBundle.load(path);
  final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  return compute(_gunzipJson, bytes); // a few MB of JSON: decoded off the UI thread
}

Future<QuranData> loadQuranAsset() async => QuranData.fromJson(await _loadAsset('assets/quran/quran.json.gz'));
Future<HadithData> loadHadithAsset() async => HadithData.fromJson(await _loadAsset('assets/quran/hadith.json.gz'));
