import '../data/quran_data.dart';

final _marks = RegExp('[ؐ-ًؚ-ٰٟۖ-ۭ࣓-ࣿـ‌‍‏‎]');

/// Arabic and Urdu text for matching: vowel and Quranic marks removed, letter variants made one (alef forms, yeh,
/// kaf, heh / teh marbuta), spaces collapsed. Applied the same way to the text and to what is typed.
String foldArabic(String s) {
  final b = StringBuffer();
  for (final r in s.replaceAll(_marks, '').runes) {
    b.writeCharCode(switch (r) {
      0x0622 || 0x0623 || 0x0625 || 0x0671 || 0x0672 || 0x0673 => 0x0627, // آ أ إ ٱ -> ا
      0x0649 || 0x06CC || 0x06D2 || 0x0626 => 0x064A, // ى ی ے ئ -> ي
      0x06A9 => 0x0643, // ک -> ك
      0x06C1 || 0x06BE || 0x0629 || 0x06C3 || 0x06C0 => 0x0647, // ہ ھ ة ۃ ۀ -> ه
      0x0624 => 0x0648, // ؤ -> و
      _ => r,
    });
  }
  return b.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// English for matching: lower case, apostrophes and punctuation ignored.
String foldEnglish(String s) => s.toLowerCase().replaceAll(RegExp(r"[^a-z0-9 ]"), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

bool isArabicScript(String s) => RegExp('[؀-ۿ]').hasMatch(s);

/// Which text matched.
enum SearchField { arabic, urdu, english }

class QuranHit {
  const QuranHit(this.index, this.field);
  final int index;
  final SearchField field;
}

/// Prepared once (folding 3 x 6236 texts): matching each query is then a quick scan.
class QuranSearchIndex {
  QuranSearchIndex._(this.arabic, this.urdu, this.english);
  final List<String> arabic, urdu, english;

  factory QuranSearchIndex.of(QuranData q) => QuranSearchIndex._(
    [for (final t in (q.searchArabic.isNotEmpty ? q.searchArabic : q.arabic)) foldArabic(t)],
    [for (final t in q.urdu) foldArabic(t)],
    [for (final t in q.english) ' ${foldEnglish(t)} '],
  );

  /// Ayahs containing [query] (Arabic-script queries search the Arabic and the Urdu; others the English), in order.
  /// An English word matches whole words at its start ("pray" finds "prayer" but not "spray").
  List<QuranHit> find(String query, {int max = 300}) {
    final out = <QuranHit>[];
    if (isArabicScript(query)) {
      final q = foldArabic(query);
      if (q.length < 2) return out;
      for (var i = 0; i < arabic.length && out.length < max; i++) {
        if (arabic[i].contains(q)) {
          out.add(QuranHit(i, SearchField.arabic));
        } else if (urdu[i].contains(q)) {
          out.add(QuranHit(i, SearchField.urdu));
        }
      }
    } else {
      final q = foldEnglish(query);
      if (q.length < 2) return out;
      final needle = ' $q';
      for (var i = 0; i < english.length && out.length < max; i++) {
        if (english[i].contains(needle)) out.add(QuranHit(i, SearchField.english));
      }
    }
    return out;
  }
}
