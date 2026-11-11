import 'dart:convert';

import '../../planner/domain/reminders.dart';
import 'prayer.dart';

// Ids from islamicNotificationIds (planner/domain/reminders.dart): Sunnah surahs and Jumu'ah, "Did you pray?", and
// Islamic dates / fasts, each kind in its own block of 0x2000.
int _id(int kind, DateTime day, int sub) {
  final dayNo = DateTime.utc(day.year, day.month, day.day).millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;
  return islamicNotificationIds + kind * 0x2000 + (dayNo % 0x400) * 8 + sub;
}

/// A time of day, "21:30".
typedef Clock = ({int hour, int minute});

Clock? _clock(Object? v) {
  if (v is! String) return null;
  final p = v.split(':');
  final h = p.length == 2 ? int.tryParse(p[0]) : null, m = p.length == 2 ? int.tryParse(p[1]) : null;
  return h == null || m == null ? null : (hour: h.clamp(0, 23), minute: m.clamp(0, 59));
}

String clockText(Clock c) => '${c.hour.toString().padLeft(2, '0')}:${c.minute.toString().padLeft(2, '0')}';

/// The reminders around the day's worship, each one off until turned on (Islamic dates are on).
class IslamicSettings {
  const IslamicSettings({
    this.kahf = false,
    this.kahfAt = (hour: 9, minute: 0),
    this.mulk = false,
    this.mulkAt = (hour: 21, minute: 30),
    this.askPrayed = false,
    this.askAfterMinutes = 60,
    this.jumuah = false,
    this.khutbahAt = (hour: 13, minute: 30),
    this.jumuahBefore = 30,
    this.dates = true,
    this.monThu = false,
    this.whiteDays = false,
    this.eveningAt = (hour: 21, minute: 0),
  });

  /// Surah Al-Kahf on Fridays, and Surah Al-Mulk every night.
  final bool kahf, mulk;
  final Clock kahfAt, mulkAt;

  /// "Did you pray?" this long after each prayer time, with Prayed / Missed buttons that fill in the prayer log.
  final bool askPrayed;
  final int askAfterMinutes;

  /// A reminder before the Friday khutbah at the mosque.
  final bool jumuah;
  final Clock khutbahAt;
  final int jumuahBefore;

  /// Reminders the evening before the year's Islamic dates, and before the voluntary fasts chosen.
  final bool dates, monThu, whiteDays;
  final Clock eveningAt;

  IslamicSettings copyWith({
    bool? kahf,
    Clock? kahfAt,
    bool? mulk,
    Clock? mulkAt,
    bool? askPrayed,
    int? askAfterMinutes,
    bool? jumuah,
    Clock? khutbahAt,
    int? jumuahBefore,
    bool? dates,
    bool? monThu,
    bool? whiteDays,
    Clock? eveningAt,
  }) => IslamicSettings(
    kahf: kahf ?? this.kahf,
    kahfAt: kahfAt ?? this.kahfAt,
    mulk: mulk ?? this.mulk,
    mulkAt: mulkAt ?? this.mulkAt,
    askPrayed: askPrayed ?? this.askPrayed,
    askAfterMinutes: askAfterMinutes ?? this.askAfterMinutes,
    jumuah: jumuah ?? this.jumuah,
    khutbahAt: khutbahAt ?? this.khutbahAt,
    jumuahBefore: jumuahBefore ?? this.jumuahBefore,
    dates: dates ?? this.dates,
    monThu: monThu ?? this.monThu,
    whiteDays: whiteDays ?? this.whiteDays,
    eveningAt: eveningAt ?? this.eveningAt,
  );

  String encode() => jsonEncode({
    'kahf': kahf,
    'kahfAt': clockText(kahfAt),
    'mulk': mulk,
    'mulkAt': clockText(mulkAt),
    'ask': askPrayed,
    'askAfter': askAfterMinutes,
    'jumuah': jumuah,
    'khutbah': clockText(khutbahAt),
    'before': jumuahBefore,
    'dates': dates,
    'monThu': monThu,
    'white': whiteDays,
    'evening': clockText(eveningAt),
  });

  static IslamicSettings decode(String? raw) {
    const d = IslamicSettings();
    if (raw == null || raw.isEmpty) return d;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return IslamicSettings(
        kahf: j['kahf'] as bool? ?? d.kahf,
        kahfAt: _clock(j['kahfAt']) ?? d.kahfAt,
        mulk: j['mulk'] as bool? ?? d.mulk,
        mulkAt: _clock(j['mulkAt']) ?? d.mulkAt,
        askPrayed: j['ask'] as bool? ?? d.askPrayed,
        askAfterMinutes: ((j['askAfter'] as num?) ?? d.askAfterMinutes).toInt().clamp(10, 180),
        jumuah: j['jumuah'] as bool? ?? d.jumuah,
        khutbahAt: _clock(j['khutbah']) ?? d.khutbahAt,
        jumuahBefore: ((j['before'] as num?) ?? d.jumuahBefore).toInt().clamp(5, 120),
        dates: j['dates'] as bool? ?? d.dates,
        monThu: j['monThu'] as bool? ?? d.monThu,
        whiteDays: j['white'] as bool? ?? d.whiteDays,
        eveningAt: _clock(j['evening']) ?? d.eveningAt,
      );
    } catch (_) {
      return d;
    }
  }
}

DateTime _at(DateTime day, Clock c) => DateTime(day.year, day.month, day.day, c.hour, c.minute);

/// Surah Al-Kahf on Fridays, Surah Al-Mulk at night, and the Jumu'ah reminder, over the next [days] days.
List<Reminder> sunnahReminders(IslamicSettings s, DateTime now, {int days = 21}) {
  final out = <Reminder>[];
  for (var d = 0; d < days; d++) {
    final day = DateTime(now.year, now.month, now.day + d);
    final friday = day.weekday == DateTime.friday;
    if (s.kahf && friday) {
      out.add(Reminder(
        id: _id(0, day, 0),
        at: _at(day, s.kahfAt),
        title: 'Surah Al-Kahf · سورۃ الکہف',
        body: "It's Friday: read Surah Al-Kahf today. · آج جمعہ ہے: سورۃ الکہف پڑھیں۔",
        payload: 'ayah:18:1',
      ));
    }
    if (s.mulk) {
      out.add(Reminder(
        id: _id(0, day, 1),
        at: _at(day, s.mulkAt),
        title: 'Surah Al-Mulk · سورۃ الملک',
        body: 'Before sleeping: read Surah Al-Mulk. · سونے سے پہلے سورۃ الملک پڑھیں۔',
        payload: 'ayah:67:1',
      ));
    }
    if (s.jumuah && friday) {
      final khutbah = _at(day, s.khutbahAt);
      out.add(Reminder(
        id: _id(0, day, 2),
        at: khutbah.subtract(Duration(minutes: s.jumuahBefore)),
        title: "Jumu'ah · جمعہ",
        body: 'The khutbah begins in ${s.jumuahBefore} min: time to get ready. · خطبہ ${s.jumuahBefore} منٹ میں شروع ہوگا، تیاری کریں۔',
        payload: 'prayer:dhuhr',
        tone: 'alarm',
      ));
    }
  }
  return [for (final r in out) if (r.at.isAfter(now)) r];
}

/// "Did you pray?" after each of the five prayers over the next [days] days (asked before the next prayer begins).
List<Reminder> prayedChecks(PrayerSettings p, IslamicSettings s, DateTime now, {int days = 7, PrayerLog? log}) {
  if (!s.askPrayed || !p.hasLocation) return const [];
  final out = <Reminder>[];
  for (var d = 0; d < days; d++) {
    final day = DateTime(now.year, now.month, now.day + d);
    final t = prayerDay(p, day).times;
    final next = prayerDay(p, DateTime(day.year, day.month, day.day + 1)).times;
    const order = [Prayer.fajr, Prayer.dhuhr, Prayer.asr, Prayer.maghrib, Prayer.isha];
    for (final pr in order) {
      final start = t[pr]!;
      // the prayer's time ends at the next one (Fajr at sunrise, Isha at the next Fajr): ask before that
      final end = switch (pr) {
        Prayer.fajr => t[Prayer.sunrise]!,
        Prayer.dhuhr => t[Prayer.asr]!,
        Prayer.asr => t[Prayer.maghrib]!,
        Prayer.maghrib => t[Prayer.isha]!,
        _ => next[Prayer.fajr]!,
      };
      var at = start.add(Duration(minutes: s.askAfterMinutes));
      final latest = end.subtract(const Duration(minutes: 10));
      if (at.isAfter(latest)) at = latest;
      if (!at.isAfter(start) || !at.isAfter(now)) continue;
      if (log?.on(day, pr) != null) continue; // already marked: no need to ask
      final name = pr.salahOn(day);
      out.add(Reminder(
        id: _id(1, day, pr.index),
        at: at,
        title: 'Did you pray $name? · کیا آپ نے ${pr.salahUrduOn(day)} ادا کی؟',
        body: 'Tap Prayed or Missed: it goes into your prayer log. · ادا کی یا قضا ہوئی؟',
        payload: 'check:${pr.name}:${dayKeyOf(day)}',
      ));
    }
  }
  return out;
}

String dayKeyOf(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// The year's Islamic dates, by the Hijri date (Umm al-Qura, moved by the moon-sighting adjustment).
enum IslamicDay {
  newYear(1, 1, 'Islamic New Year', 'اسلامی نیا سال', false),
  ashura9(1, 9, '9 Muharram (fast with Ashura)', '۹ محرم (عاشورہ کے ساتھ روزہ)', true),
  ashura(1, 10, 'Ashura', 'یوم عاشورہ', true),
  shabEBarat(8, 15, "Shab-e-Barat (the night of 15 Sha'ban)", 'شب برات', false, night: true),
  ramadan(9, 1, 'Ramadan begins', 'رمضان المبارک کا آغاز', true),
  lastTen(9, 21, 'The last ten nights of Ramadan', 'رمضان کا آخری عشرہ', false, night: true),
  qadr(9, 27, 'Laylat al-Qadr (the 27th night; seek it in the odd nights)', 'لیلۃ القدر (۲۷ویں شب)', false, night: true),
  eidFitr(10, 1, 'Eid al-Fitr', 'عید الفطر', false),
  arafah(12, 9, 'Day of Arafah (fast)', 'یوم عرفہ (روزہ)', true),
  eidAdha(12, 10, 'Eid al-Adha', 'عید الاضحیٰ', false);

  const IslamicDay(this.month, this.day, this.english, this.urdu, this.fast, {this.night = false});
  final int month, day;
  final String english, urdu;

  /// A recommended fast that day.
  final bool fast;

  /// Its night (the evening before) is the time to remember.
  final bool night;
}

/// An Islamic date on the calendar: the Gregorian day it falls on.
typedef IslamicDate = ({DateTime date, IslamicDay day, int hijriYear});

/// The Islamic dates from [from] for [days] days, in order.
List<IslamicDate> upcomingIslamicDates(DateTime from, int offset, {int days = 400}) {
  final out = <IslamicDate>[];
  for (var d = 0; d < days; d++) {
    final date = DateTime(from.year, from.month, from.day + d);
    final h = hijriDate(date, offset);
    for (final e in IslamicDay.values) {
      if (h.month == e.month && h.day == e.day) out.add((date: date, day: e, hijriYear: h.year));
    }
  }
  return out;
}

/// Days on which fasting is not allowed: the two Eids and the days of Tashreeq.
bool fastingForbidden(DateTime date, int offset) {
  final h = hijriDate(date, offset);
  return (h.month == 10 && h.day == 1) || (h.month == 12 && h.day >= 10 && h.day <= 13);
}

/// Reminders the evening before each Islamic date (and before the chosen voluntary fasts) over the next [days] days.
/// Mondays/Thursdays and the 13th-15th are not reminded in Ramadan (every day is a fast) or on forbidden days.
List<Reminder> islamicDateReminders(IslamicSettings s, int offset, DateTime now, {int days = 30}) {
  final out = <Reminder>[];
  if (s.dates) {
    for (final e in upcomingIslamicDates(now, offset, days: days + 1)) {
      final eve = DateTime(e.date.year, e.date.month, e.date.day - 1);
      final fast = e.day.fast ? ' Sehri before Fajr if you fast. · روزہ رکھیں تو سحری فجر سے پہلے۔' : '';
      out.add(Reminder(
        id: _id(2, e.date, 0),
        at: _at(eve, s.eveningAt),
        title: e.day.night ? 'Tonight: ${e.day.english} · ${e.day.urdu}' : 'Tomorrow: ${e.day.english} · ${e.day.urdu}',
        body: 'By the Hijri calendar (it can move a day with the moon sighting).$fast',
        payload: 'prayer:islamic',
      ));
    }
  }
  for (var d = 1; d <= days; d++) {
    final day = DateTime(now.year, now.month, now.day + d);
    final h = hijriDate(day, offset);
    if (h.month == 9 || fastingForbidden(day, offset)) continue;
    final white = s.whiteDays && h.day >= 13 && h.day <= 15;
    final monThu = s.monThu && (day.weekday == DateTime.monday || day.weekday == DateTime.thursday);
    if (!white && !monThu) continue;
    if (IslamicDay.values.any((e) => e.fast && e.month == h.month && e.day == h.day) && s.dates) continue; // already reminded
    final eve = DateTime(day.year, day.month, day.day - 1);
    final why = white ? 'the ${h.day}th of the month (the white days)' : (day.weekday == DateTime.monday ? 'Monday' : 'Thursday');
    out.add(Reminder(
      id: _id(2, day, 1),
      at: _at(eve, s.eveningAt),
      title: 'Fast tomorrow? · کل نفلی روزہ',
      body: 'Tomorrow is $why, a day the Prophet ﷺ used to fast. Sehri ends at Fajr.',
      payload: 'prayer:islamic',
    ));
  }
  return [for (final r in out) if (r.at.isAfter(now)) r]..sort((a, b) => a.at.compareTo(b.at));
}
