import 'dart:convert';

import '../data/quran_data.dart';

/// A goal to read the whole Quran (a khatm) in [days] days from [start], counted in pages of the Madinah mushaf.
class KhatmPlan {
  const KhatmPlan({required this.start, required this.days, this.startPage = 1, required this.donePage});

  /// The first day of the plan (a date; the time is ignored).
  final DateTime start;
  final int days;

  /// Where the plan begins (1 = from Al-Fatiha).
  final int startPage;

  /// The furthest page read so far (startPage - 1 = nothing yet). Reading an earlier page again never lowers it.
  final int donePage;

  int get totalPages => QuranData.pageCount - startPage + 1;

  /// Day of the plan [now] falls on (1 = the first day; past the end stays at the last day).
  int dayOf(DateTime now) {
    final d = DateTime(now.year, now.month, now.day).difference(DateTime(start.year, start.month, start.day)).inDays + 1;
    return d.clamp(1, days);
  }

  /// The page you should have reached by the end of plan day [d] (0 = before the start).
  int expectedBy(int d) {
    if (d <= 0) return startPage - 1;
    return startPage - 1 + (totalPages * d / days).ceil().clamp(0, totalPages);
  }

  bool get finished => donePage >= QuranData.pageCount;

  /// Fraction of the plan's pages read.
  double get progress => ((donePage - startPage + 1) / totalPages).clamp(0.0, 1.0);

  KhatmPlan withDone(int page) => page <= donePage ? this : KhatmPlan(start: start, days: days, startPage: startPage, donePage: page.clamp(0, QuranData.pageCount));

  String encode() => jsonEncode({'start': start.millisecondsSinceEpoch, 'days': days, 'from': startPage, 'done': donePage});

  static KhatmPlan? decode(String raw) {
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final days = (j['days'] as num).toInt(), from = (j['from'] as num).toInt();
      if (days < 1 || from < 1 || from > QuranData.pageCount) return null;
      return KhatmPlan(start: DateTime.fromMillisecondsSinceEpoch((j['start'] as num).toInt()), days: days, startPage: from, donePage: (j['done'] as num).toInt());
    } catch (_) {
      return null;
    }
  }
}

/// Where today stands.
enum KhatmStatus { doneToday, onTrack, behind, finished }

class KhatmToday {
  const KhatmToday({required this.day, required this.from, required this.to, required this.status, required this.behindBy});

  /// Day of the plan (1-based).
  final int day;

  /// Today's portion: pages [from]..[to] (when behind, it starts where you are, so it includes the catch-up).
  final int from, to;
  final KhatmStatus status;

  /// Pages still to read from earlier days.
  final int behindBy;
}

KhatmToday khatmToday(KhatmPlan p, DateTime now) {
  final d = p.dayOf(now);
  final endYesterday = p.expectedBy(d - 1), endToday = p.expectedBy(d);
  final from = (p.donePage + 1).clamp(p.startPage, QuranData.pageCount);
  final status = p.finished
      ? KhatmStatus.finished
      : (p.donePage >= endToday ? KhatmStatus.doneToday : (p.donePage >= endYesterday ? KhatmStatus.onTrack : KhatmStatus.behind));
  return KhatmToday(
    day: d,
    from: status == KhatmStatus.doneToday ? endYesterday + 1 : from,
    to: endToday,
    status: status,
    behindBy: (endYesterday - p.donePage).clamp(0, QuranData.pageCount),
  );
}
