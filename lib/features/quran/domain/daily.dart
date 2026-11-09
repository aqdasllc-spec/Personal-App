import '../data/quran_data.dart';

/// Well-known ayahs that read well on their own (a few short ones are kept together, e.g. 94:5-6). Only the
/// references are listed here: the words always come from the bundled Quran text.
const dailyAyahRefs = <(int, int, int)>[
  (2, 152, 152), (2, 153, 153), (2, 155, 156), (2, 186, 186), (2, 201, 201), (2, 255, 255), (2, 286, 286),
  (3, 8, 8), (3, 26, 26), (3, 31, 31), (3, 92, 92), (3, 103, 103), (3, 110, 110), (3, 134, 134), (3, 139, 139),
  (3, 159, 159), (3, 173, 173), (3, 185, 185), (3, 190, 190), (3, 191, 191), (3, 200, 200),
  (4, 36, 36), (4, 58, 58), (4, 110, 110), (4, 135, 135), (5, 8, 8), (6, 59, 59), (6, 162, 162),
  (7, 23, 23), (7, 56, 56), (7, 199, 199), (8, 2, 2), (9, 51, 51), (9, 129, 129), (10, 57, 57), (11, 6, 6),
  (11, 114, 114), (12, 87, 87), (13, 11, 11), (13, 28, 28), (14, 7, 7), (14, 34, 34), (14, 41, 41),
  (16, 90, 90), (16, 97, 97), (16, 125, 125), (16, 128, 128), (17, 23, 24), (17, 80, 80), (18, 10, 10),
  (18, 46, 46), (20, 25, 28), (20, 114, 114), (21, 35, 35), (21, 83, 83), (21, 87, 87), (21, 107, 107),
  (22, 46, 46), (23, 1, 3), (24, 22, 22), (25, 63, 63), (25, 74, 74), (28, 24, 24), (29, 2, 2), (29, 45, 45),
  (29, 69, 69), (31, 17, 17), (31, 18, 19), (33, 21, 21), (33, 41, 41), (35, 2, 2), (39, 9, 9), (39, 10, 10),
  (39, 53, 53), (40, 44, 44), (40, 60, 60), (41, 34, 34), (42, 30, 30), (42, 36, 36), (49, 10, 10),
  (49, 11, 11), (49, 12, 12), (49, 13, 13), (50, 16, 16), (51, 56, 56), (55, 13, 13), (55, 26, 27),
  (55, 60, 60), (57, 4, 4), (57, 20, 20), (58, 11, 11), (59, 18, 18), (59, 22, 22), (59, 23, 23), (59, 24, 24),
  (64, 11, 11), (66, 8, 8), (67, 2, 2), (87, 14, 15), (93, 3, 5), (94, 5, 6), (94, 7, 8), (103, 1, 3),
  (112, 1, 4),
];

/// Days since 1 Jan 1970 for the local calendar date (so the choice changes at local midnight).
int dayNumber(DateTime d) => DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;

/// The day's ayah (or short group of ayahs).
class DailyAyah {
  const DailyAyah({required this.surah, required this.from, required this.to, required this.arabic, required this.english, required this.urdu});
  final Surah surah;
  final int from, to;
  final List<String> arabic, english, urdu;

  String get ref => from == to ? '${surah.number}:$from' : '${surah.number}:$from-$to';
}

DailyAyah dailyAyah(QuranData q, DateTime date) {
  final (s, from, to) = dailyAyahRefs[dayNumber(date) % dailyAyahRefs.length];
  final i = q.indexOf(s, from), j = q.indexOf(s, to);
  return DailyAyah(
    surah: q.surah(s),
    from: from,
    to: to,
    arabic: q.arabic.sublist(i, j + 1),
    english: q.english.sublist(i, j + 1),
    urdu: q.urdu.sublist(i, j + 1),
  );
}

/// The day's hadith: walks through the whole collection in a fixed, spread-out order (a new one every day).
Hadith dailyHadith(HadithData h, DateTime date) {
  final n = h.items.length;
  // 7919 is prime and shares no factor with the collection size (checked in the tests), so consecutive days land far
  // apart and every hadith comes up once before any repeats.
  return h.items[(dayNumber(date) * 7919) % n];
}
