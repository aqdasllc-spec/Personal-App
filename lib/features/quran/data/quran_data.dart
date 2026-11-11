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

/// How the Arabic is written: the Indo-Pak (South Asian) script most readers in Pakistan and India learnt from, or
/// the Madinah (Uthmani) script.
enum QuranScript {
  indopak('Indo-Pak', 'انڈو پاک'),
  madinah('Madinah (Uthmani)', 'مدنی');

  const QuranScript(this.label, this.urdu);
  final String label, urdu;
}

/// The whole Quran: Arabic (Indo-Pak and Uthmani Hafs), English (Saheeh International) and Urdu (Fateh Muhammad
/// Jalandhry, or another chosen translation), aligned ayah by ayah (6236 ayahs). Read only; the texts are shown
/// exactly as published. [arabic] and [urdu] are the ones chosen to be shown (see [view]).
class QuranData {
  QuranData({
    required this.surahs,
    required this.arabic,
    required this.english,
    required this.urdu,
    required this.juzStarts,
    required this.sajdas,
    this.pages = const [],
    this.searchArabic = const [],
    List<String>? uthmani,
    this.indopak = const [],
    this.script = QuranScript.madinah,
    this.urduName = 'Fateh Muhammad Jalandhry',
    this.urduRtl = true,
    this.rukus = const [],
  }) : uthmani = uthmani ?? arabic,
       assert(arabic.length == english.length && english.length == urdu.length);

  /// The Uthmani (Madinah) text and the Indo-Pak text of every ayah (the Indo-Pak one may be missing in tests).
  final List<String> uthmani, indopak;

  /// The script [arabic] is in.
  final QuranScript script;

  /// Who translated [urdu]; false [urduRtl] = written in English letters (Roman Urdu).
  final String urduName;
  final bool urduRtl;

  /// The same Quran shown in [script] (Indo-Pak falls back to Uthmani if this data has no Indo-Pak text) and, if
  /// given, with another Urdu translation.
  QuranData view({required QuranScript script, List<String>? urdu, String? urduName, bool? urduRtl}) {
    final s = script == QuranScript.indopak && indopak.length != uthmani.length ? QuranScript.madinah : script;
    return QuranData(
      surahs: surahs,
      arabic: s == QuranScript.indopak ? indopak : uthmani,
      english: english,
      urdu: urdu ?? this.urdu,
      juzStarts: juzStarts,
      sajdas: sajdas,
      pages: pages,
      searchArabic: searchArabic,
      uthmani: uthmani,
      indopak: indopak,
      script: s,
      urduName: urduName ?? this.urduName,
      urduRtl: urduRtl ?? this.urduRtl,
      rukus: rukus,
    );
  }

  /// The ruku (section) of each ayah, numbered through the whole Quran (1-556; empty in tests without it).
  final List<int> rukus;

  /// The last ayah of its ruku (marked ع in South Asian mushafs).
  bool isRukuEnd(int index) => rukus.isNotEmpty && (index == rukus.length - 1 || rukus[index + 1] != rukus[index]);

  /// The ruku's number within its surah (1 = the surah's first), or null without ruku data.
  int? rukuInSurah(int index) {
    if (rukus.isEmpty) return null;
    final (s, _) = refOf(index);
    return rukus[index] - rukus[surahs[s - 1].firstIndex] + 1;
  }

  /// Where the Indo-Pak paras begin differently from the Madinah juz (para number -> surah, ayah). A para is named
  /// after its opening words, and these are the ayahs whose opening words are the paras' names in South Asian
  /// mushafs (e.g. para 4 "لَنۡ تَنَالُوا" at 3:92, where the Madinah juz 4 begins at 3:93).
  static const indoPakParaStarts = <int, (int, int)>{4: (3, 92), 7: (5, 83), 11: (9, 94), 14: (15, 2), 20: (27, 60), 21: (29, 45), 23: (36, 22)};

  /// How many opening words make up each para's name (para 1 is named after Al-Baqarah's opening, الٓمّٓ).
  static const _paraNameWords = [1, 1, 2, 2, 1, 3, 2, 2, 2, 1, 1, 3, 2, 1, 2, 2, 1, 2, 2, 2, 3, 2, 2, 2, 2, 1, 3, 3, 2, 1];

  /// Where each of the 30 paras begins in the script being shown: Indo-Pak paras, or the Madinah juz.
  List<(int, int)> get paraStarts => script == QuranScript.indopak && indopak.isNotEmpty
      ? [for (var i = 0; i < juzStarts.length; i++) indoPakParaStarts[i + 1] ?? juzStarts[i]]
      : juzStarts;

  /// The traditional name of para [n] (1-30): its opening words, from the Indo-Pak text (waqf signs left out).
  String paraName(int n) {
    final text = indopak.isNotEmpty ? indopak : uthmani;
    final (s, a) = n == 1 ? (2, 1) : (indoPakParaStarts[n] ?? juzStarts[n - 1]);
    final words = text[indexOf(s, a)].split(' ').where((w) => w.isNotEmpty).take(_paraNameWords[n - 1]).join(' ');
    return words.replaceAll(RegExp('[\u06D6-\u06DC\u06DE\u06E9]'), '').trim();
  }

  /// For searching only: the same ayahs in everyday spelling, without vowel marks (never shown).
  final List<String> searchArabic;

  /// The Madinah mushaf page (1-604) of each ayah, by position.
  final List<int> pages;

  static const pageCount = 604;

  /// The page an ayah is on (1 when the data has no pages).
  int pageOf(int index) => pages.isEmpty ? 1 : pages[index];

  /// Position of the first ayah on [page].
  int firstOnPage(int page) {
    var lo = 0, hi = pages.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (pages[mid] < page) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

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
    final starts = paraStarts;
    var j = 1;
    for (var k = 0; k < starts.length; k++) {
      if (indexOf(starts[k].$1, starts[k].$2) <= i) j = k + 1;
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
      pages: [for (final p in (j['page'] as List? ?? const [])) p as int],
      searchArabic: [for (final t in (j['ars'] as List? ?? const [])) t as String],
      indopak: j['ip'] == null ? const [] : texts('ip'),
      rukus: [for (final r in (j['ruku'] as List? ?? const [])) r as int],
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

/// An Urdu translation to choose from. Jalandhry ([urduTranslations].first) is inside the Quran data; the others are
/// files of their own (built and checked by tool/quran/build_assets.py).
class UrduTranslation {
  const UrduTranslation(this.id, this.name, this.urdu, {this.rtl = true});
  final String id, name, urdu;

  /// False: written in English letters (Roman Urdu).
  final bool rtl;
}

const urduTranslations = <UrduTranslation>[
  UrduTranslation('jalandhry', 'Fateh Muhammad Jalandhry', 'فتح محمد جالندھری'),
  UrduTranslation('taqiusmani', 'Mufti Muhammad Taqi Usmani', 'مفتی محمد تقی عثمانی'),
  UrduTranslation('junagarhi', 'Muhammad Junagarhi', 'محمد جوناگڑھی'),
  UrduTranslation('mahmoodulhassan', 'Shaykh-ul-Hind Mahmood-ul-Hassan', 'شیخ الہند محمود الحسن'),
  UrduTranslation('maududi', "Abul A'la Maududi", 'ابوالاعلیٰ مودودی'),
  UrduTranslation('ahmedali', 'Ahmed Ali', 'احمد علی'),
  UrduTranslation('maududiroman', "Abul A'la Maududi (Roman Urdu)", 'مودودی (رومن اردو)', rtl: false),
];

/// The texts of one of the other Urdu translations (6236, aligned with the Quran data).
Future<List<String>> loadUrduTranslation(String id) async {
  final j = await _loadAsset('assets/quran/ur_$id.json.gz');
  return [for (final t in (j['ur'] as List)) t as String];
}
