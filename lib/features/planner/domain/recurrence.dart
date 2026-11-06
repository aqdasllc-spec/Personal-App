/// Repeat rules - a deliberately small, well-tested subset of RFC 5545:
///   FREQ=DAILY|WEEKLY|MONTHLY|YEARLY  ;INTERVAL=n  ;BYDAY=MO,TU,...  (weekly only)  ;COUNT=n  ;UNTIL=yyyymmdd
///
/// All maths is on LOCAL wall-clock time: "every day at 09:00" stays 09:00 across daylight-saving changes
/// because occurrences are built from local date components, never by adding 24 h of elapsed time.
/// Monthly/yearly rules on a day that doesn't exist in a month (31st, 29 Feb) fall on the LAST day of
/// that month instead of being skipped (what people expect from a calendar app; RFC 5545 would skip).
enum Freq { daily, weekly, monthly, yearly }

const _weekdayCodes = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];

class Recurrence {
  const Recurrence({required this.freq, this.interval = 1, this.byWeekday = const {}, this.until, this.count});

  final Freq freq;
  final int interval;

  /// 1 = Monday … 7 = Sunday (same as [DateTime.weekday]); only used for weekly rules.
  final Set<int> byWeekday;

  /// Last day (inclusive, local date) on which an occurrence may start.
  final DateTime? until;

  /// Total number of occurrences including the first.
  final int? count;

  /// Parses a rule; returns null for '' or anything we don't understand (never throws).
  static Recurrence? parse(String? rule) {
    if (rule == null || rule.trim().isEmpty) return null;
    final parts = <String, String>{};
    for (final p in rule.split(';')) {
      final i = p.indexOf('=');
      if (i > 0) parts[p.substring(0, i).trim().toUpperCase()] = p.substring(i + 1).trim();
    }
    final freq = switch (parts['FREQ']?.toUpperCase()) {
      'DAILY' => Freq.daily,
      'WEEKLY' => Freq.weekly,
      'MONTHLY' => Freq.monthly,
      'YEARLY' => Freq.yearly,
      _ => null,
    };
    if (freq == null) return null;
    final interval = (int.tryParse(parts['INTERVAL'] ?? '') ?? 1).clamp(1, 999);
    final days = <int>{};
    if (freq == Freq.weekly) {
      for (final d in (parts['BYDAY'] ?? '').split(',')) {
        final i = _weekdayCodes.indexOf(d.trim().toUpperCase());
        if (i >= 0) days.add(i + 1);
      }
    }
    DateTime? until;
    final u = parts['UNTIL'];
    if (u != null && RegExp(r'^\d{8}').hasMatch(u)) {
      until = DateTime(int.parse(u.substring(0, 4)), int.parse(u.substring(4, 6)), int.parse(u.substring(6, 8)));
    }
    final count = int.tryParse(parts['COUNT'] ?? '');
    return Recurrence(freq: freq, interval: interval, byWeekday: days, until: until, count: count != null && count > 0 ? count : null);
  }

  String toRule() {
    final b = StringBuffer('FREQ=${freq.name.toUpperCase()}');
    if (interval != 1) b.write(';INTERVAL=$interval');
    if (freq == Freq.weekly && byWeekday.isNotEmpty) {
      final sorted = byWeekday.toList()..sort();
      b.write(';BYDAY=${sorted.map((d) => _weekdayCodes[d - 1]).join(',')}');
    }
    if (count != null) b.write(';COUNT=$count');
    if (until != null) b.write(';UNTIL=${until!.year.toString().padLeft(4, '0')}${until!.month.toString().padLeft(2, '0')}${until!.day.toString().padLeft(2, '0')}');
    return b.toString();
  }

  /// Human description, e.g. "Every 2 weeks on Mon, Wed".
  String describe() {
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final unit = switch (freq) { Freq.daily => 'day', Freq.weekly => 'week', Freq.monthly => 'month', Freq.yearly => 'year' };
    var s = interval == 1 ? (freq == Freq.daily ? 'Every day' : 'Every $unit') : 'Every $interval ${unit}s';
    if (freq == Freq.weekly && byWeekday.isNotEmpty) {
      final sorted = byWeekday.toList()..sort();
      s += ' on ${sorted.map((d) => names[d - 1]).join(', ')}';
    }
    if (count != null) s += ', $count times';
    if (until != null) s += ', until ${until!.year}-${until!.month.toString().padLeft(2, '0')}-${until!.day.toString().padLeft(2, '0')}';
    return s;
  }

  static const _maxYear = 2200;
  static const _maxSteps = 200000;

  /// Occurrence start times in order, beginning with [start] itself (when it matches the rule).
  Iterable<DateTime> occurrences(DateTime start) sync* {
    var emitted = 0;
    var steps = 0;
    DateTime at(int y, int m, int d) => DateTime(y, m, d, start.hour, start.minute, start.second);
    int lastDay(int y, int m) => DateTime(y, m + 1, 0).day;
    bool ok(DateTime d) => (until == null || !DateTime(d.year, d.month, d.day).isAfter(until!)) && d.year <= _maxYear;

    switch (freq) {
      case Freq.daily:
        for (var k = 0;; k++) {
          if (++steps > _maxSteps) return;
          final d = at(start.year, start.month, start.day + k * interval);
          if (!ok(d) || (count != null && emitted >= count!)) return;
          emitted++;
          yield d;
        }
      case Freq.weekly:
        final days = (byWeekday.isEmpty ? {start.weekday} : byWeekday).toList()..sort();
        // Monday of the week containing [start]
        final monday = DateTime(start.year, start.month, start.day - (start.weekday - 1));
        for (var w = 0;; w++) {
          for (final wd in days) {
            if (++steps > _maxSteps) return;
            final d = at(monday.year, monday.month, monday.day + w * 7 * interval + (wd - 1));
            if (d.isBefore(start)) continue;
            if (!ok(d) || (count != null && emitted >= count!)) return;
            emitted++;
            yield d;
          }
        }
      case Freq.monthly:
        for (var k = 0;; k++) {
          if (++steps > _maxSteps) return;
          final m0 = start.month - 1 + k * interval;
          final y = start.year + m0 ~/ 12, m = m0 % 12 + 1;
          final d = at(y, m, start.day > lastDay(y, m) ? lastDay(y, m) : start.day);
          if (!ok(d) || (count != null && emitted >= count!)) return;
          emitted++;
          yield d;
        }
      case Freq.yearly:
        for (var k = 0;; k++) {
          if (++steps > _maxSteps) return;
          final y = start.year + k * interval;
          final d = at(y, start.month, start.day > lastDay(y, start.month) ? lastDay(y, start.month) : start.day);
          if (!ok(d) || (count != null && emitted >= count!)) return;
          emitted++;
          yield d;
        }
    }
  }

  /// Occurrence starts within [from, to), at most [limit] of them.
  List<DateTime> between(DateTime start, DateTime from, DateTime to, {int limit = 5000}) {
    final out = <DateTime>[];
    for (final o in occurrences(start)) {
      if (!o.isBefore(to)) break;
      if (!o.isBefore(from)) {
        out.add(o);
        if (out.length >= limit) break;
      }
    }
    return out;
  }

  /// The first occurrence strictly after [after], or null when the rule has ended.
  DateTime? nextAfter(DateTime start, DateTime after) {
    for (final o in occurrences(start)) {
      if (o.isAfter(after)) return o;
    }
    return null;
  }
}
