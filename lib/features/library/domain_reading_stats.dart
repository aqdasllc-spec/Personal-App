/// One day of reading: pages read and seconds with a book open.
class DayStat {
  const DayStat(this.day, this.pages, this.seconds);
  final String day; // local date, YYYY-MM-DD
  final int pages, seconds;
}

String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime _dayOf(String key) {
  final p = key.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

/// A day counts as a reading day when at least one page was read.
Set<String> readingDays(Iterable<DayStat> stats) => {
  for (final s in stats)
    if (s.pages > 0) s.day,
};

/// Days in a row with reading, ending today. If today has none yet the streak is still alive (it counts back from yesterday).
int currentStreak(Set<String> days, DateTime today) {
  var d = DateTime(today.year, today.month, today.day);
  if (!days.contains(dayKey(d))) d = d.subtract(const Duration(days: 1));
  // DateTime(y, m, d - 1) keeps this right across daylight-saving changes
  var n = 0;
  while (days.contains(dayKey(d))) {
    n++;
    d = DateTime(d.year, d.month, d.day - 1);
  }
  return n;
}

/// The longest run of consecutive reading days ever.
int bestStreak(Set<String> days) {
  final sorted = days.toList()..sort();
  var best = 0, run = 0;
  DateTime? prev;
  for (final k in sorted) {
    final d = _dayOf(k);
    run = prev != null && DateTime(prev.year, prev.month, prev.day + 1) == d ? run + 1 : 1;
    if (run > best) best = run;
    prev = d;
  }
  return best;
}

/// Pages per day for the last [n] days, oldest first, ending today.
List<int> lastDays(Iterable<DayStat> stats, DateTime today, {int n = 7}) {
  final by = {for (final s in stats) s.day: s.pages};
  return [
    for (var i = n - 1; i >= 0; i--) by[dayKey(DateTime(today.year, today.month, today.day - i))] ?? 0,
  ];
}

/// Seconds read in the last [n] days (including today).
int secondsInLast(Iterable<DayStat> stats, DateTime today, {int n = 7}) {
  final keys = {for (var i = 0; i < n; i++) dayKey(DateTime(today.year, today.month, today.day - i))};
  return stats.where((s) => keys.contains(s.day)).fold(0, (a, s) => a + s.seconds);
}

const defaultReadGoal = 10;
const maxReadGoal = 500;

/// "1 h 05 min", "42 min", "under a minute".
String readingTimeLabel(int seconds) {
  final m = seconds ~/ 60;
  if (m < 1) return 'under a minute';
  if (m < 60) return '$m min';
  return '${m ~/ 60} h ${(m % 60).toString().padLeft(2, '0')} min';
}
