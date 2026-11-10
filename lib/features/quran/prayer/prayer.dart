import 'dart:convert';

import 'package:adhan/adhan.dart' as adhan;
import 'package:hijri/hijri_calendar.dart';

import '../../planner/domain/reminders.dart';

/// The five prayers, and sunrise (shown, never reminded: the time Fajr ends).
enum Prayer {
  fajr('Fajr', 'فجر', 'Salat-ul-Fajr', 'نمازِ فجر'),
  sunrise('Sunrise', 'طلوعِ آفتاب', '', ''),
  dhuhr('Dhuhr', 'ظہر', 'Salat-ul-Zuhr', 'نمازِ ظہر'),
  asr('Asr', 'عصر', 'Salat-ul-Asr', 'نمازِ عصر'),
  maghrib('Maghrib', 'مغرب', 'Salat-ul-Maghrib', 'نمازِ مغرب'),
  isha('Isha', 'عشاء', 'Salat-ul-Isha', 'نمازِ عشاء');

  const Prayer(this.english, this.urdu, this.salah, this.salahUrdu);
  final String english, urdu;

  /// The prayer's name as said in a reminder ("Salat-ul-Fajr", "نمازِ فجر").
  final String salah, salahUrdu;
  bool get isPrayer => this != sunrise;

  /// On Fridays the midday prayer is Jumu'ah.
  String salahOn(DateTime d) => this == dhuhr && d.weekday == DateTime.friday ? "Salat-ul-Jumu'ah" : salah;
  String salahUrduOn(DateTime d) => this == dhuhr && d.weekday == DateTime.friday ? 'نمازِ جمعہ' : salahUrdu;
}

/// How a prayer reminder sounds.
enum PrayerTone {
  notification('Phone notification sound'),
  alarm('Phone alarm sound (loud)'),
  ringtone('Phone ringtone'),
  vibrate('Vibrate only');

  const PrayerTone(this.label);
  final String label;
}

/// Calculation methods (the angles and rules each authority uses). Karachi is the usual choice in Pakistan and India.
enum PrayerMethod {
  karachi('University of Islamic Sciences, Karachi', adhan.CalculationMethod.karachi),
  mwl('Muslim World League', adhan.CalculationMethod.muslim_world_league),
  ummAlQura('Umm al-Qura, Makkah', adhan.CalculationMethod.umm_al_qura),
  egyptian('Egyptian General Authority', adhan.CalculationMethod.egyptian),
  northAmerica('ISNA (North America)', adhan.CalculationMethod.north_america),
  dubai('Dubai', adhan.CalculationMethod.dubai),
  kuwait('Kuwait', adhan.CalculationMethod.kuwait),
  qatar('Qatar', adhan.CalculationMethod.qatar),
  singapore('Singapore', adhan.CalculationMethod.singapore),
  turkey('Turkey (Diyanet)', adhan.CalculationMethod.turkey),
  moonSighting('Moonsighting Committee', adhan.CalculationMethod.moon_sighting_committee);

  const PrayerMethod(this.label, this.method);
  final String label;
  final adhan.CalculationMethod method;
}

/// Everything the prayer times depend on. Stored on this device only.
class PrayerSettings {
  const PrayerSettings({
    this.lat,
    this.lng,
    this.place = '',
    this.method = PrayerMethod.karachi,
    this.hanafi = true,
    this.hijriOffset = 0,
    this.alerts = const {},
    this.tone = PrayerTone.notification,
    this.secondAfterSeconds = 0,
    this.secondFajrOnly = true,
    this.secondTone = PrayerTone.alarm,
    this.secondKeepRinging = true,
  });

  /// The reminder at the prayer time.
  final PrayerTone tone;

  /// A second reminder this long after the prayer time ("get up now"); 0 = none.
  final int secondAfterSeconds;

  /// The second reminder for Fajr only (true) or for every prayer with a bell (false).
  final bool secondFajrOnly;
  final PrayerTone secondTone;

  /// The second reminder keeps ringing until you open it.
  final bool secondKeepRinging;

  final double? lat, lng;

  /// What the user calls the place (optional).
  final String place;
  final PrayerMethod method;

  /// Asr time: Hanafi (shadow twice the length) or the majority / Shafi'i (once).
  final bool hanafi;

  /// Days to add to the Umm al-Qura Hijri date, for local moon sighting (-2 .. +2; in Pakistan often -1).
  final int hijriOffset;

  /// Prayers that get a reminder at their time.
  final Set<Prayer> alerts;

  bool get hasLocation => lat != null && lng != null;

  PrayerSettings copyWith({
    double? lat,
    double? lng,
    String? place,
    PrayerMethod? method,
    bool? hanafi,
    int? hijriOffset,
    Set<Prayer>? alerts,
    PrayerTone? tone,
    int? secondAfterSeconds,
    bool? secondFajrOnly,
    PrayerTone? secondTone,
    bool? secondKeepRinging,
  }) => PrayerSettings(
    lat: lat ?? this.lat,
    lng: lng ?? this.lng,
    place: place ?? this.place,
    method: method ?? this.method,
    hanafi: hanafi ?? this.hanafi,
    hijriOffset: hijriOffset ?? this.hijriOffset,
    alerts: alerts ?? this.alerts,
    tone: tone ?? this.tone,
    secondAfterSeconds: secondAfterSeconds ?? this.secondAfterSeconds,
    secondFajrOnly: secondFajrOnly ?? this.secondFajrOnly,
    secondTone: secondTone ?? this.secondTone,
    secondKeepRinging: secondKeepRinging ?? this.secondKeepRinging,
  );

  String encode() => jsonEncode({
    'lat': lat,
    'lng': lng,
    'place': place,
    'method': method.name,
    'hanafi': hanafi,
    'hijri': hijriOffset,
    'alerts': [for (final p in alerts) p.name],
    'tone': tone.name,
    'second': secondAfterSeconds,
    'secondFajr': secondFajrOnly,
    'secondTone': secondTone.name,
    'insistent': secondKeepRinging,
  });

  static PrayerSettings? decode(String raw) {
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return PrayerSettings(
        lat: (j['lat'] as num?)?.toDouble(),
        lng: (j['lng'] as num?)?.toDouble(),
        place: (j['place'] as String?) ?? '',
        method: PrayerMethod.values.where((m) => m.name == j['method']).firstOrNull ?? PrayerMethod.karachi,
        hanafi: j['hanafi'] as bool? ?? true,
        hijriOffset: ((j['hijri'] as num?) ?? 0).toInt().clamp(-2, 2),
        alerts: {for (final a in (j['alerts'] as List? ?? const [])) ...Prayer.values.where((p) => p.name == a)},
        tone: PrayerTone.values.where((t) => t.name == j['tone']).firstOrNull ?? PrayerTone.notification,
        secondAfterSeconds: ((j['second'] as num?) ?? 0).toInt().clamp(0, 3599),
        secondFajrOnly: j['secondFajr'] as bool? ?? true,
        secondTone: PrayerTone.values.where((t) => t.name == j['secondTone']).firstOrNull ?? PrayerTone.alarm,
        secondKeepRinging: j['insistent'] as bool? ?? true,
      );
    } catch (_) {
      return null;
    }
  }
}

/// One day's times, in local time.
class PrayerDay {
  const PrayerDay(this.date, this.times);
  final DateTime date;
  final Map<Prayer, DateTime> times;
}

/// Calculates a day's times on the phone (no internet), with the adhan library (checked against an independent
/// implementation of the same astronomical formulas: within a minute).
PrayerDay prayerDay(PrayerSettings s, DateTime date) {
  final params = s.method.method.getParameters()..madhab = s.hanafi ? adhan.Madhab.hanafi : adhan.Madhab.shafi;
  final t = adhan.PrayerTimes(adhan.Coordinates(s.lat!, s.lng!), adhan.DateComponents(date.year, date.month, date.day), params);
  return PrayerDay(DateTime(date.year, date.month, date.day), {
    Prayer.fajr: t.fajr.toLocal(),
    Prayer.sunrise: t.sunrise.toLocal(),
    Prayer.dhuhr: t.dhuhr.toLocal(),
    Prayer.asr: t.asr.toLocal(),
    Prayer.maghrib: t.maghrib.toLocal(),
    Prayer.isha: t.isha.toLocal(),
  });
}

/// The prayer whose time it is now (Isha lasts until Fajr; null between sunrise and Dhuhr) and the next one.
({Prayer? current, Prayer next, DateTime nextAt}) prayerNow(PrayerSettings s, DateTime now) {
  final today = prayerDay(s, now);
  Prayer? current;
  for (final p in Prayer.values) {
    final at = today.times[p]!;
    if (!at.isAfter(now)) {
      current = p;
    } else {
      final cur = current == null ? Prayer.isha : (current == Prayer.sunrise ? null : current);
      return (current: cur, next: p, nextAt: at);
    }
  }
  final tomorrow = prayerDay(s, now.add(const Duration(days: 1)));
  return (current: Prayer.isha, next: Prayer.fajr, nextAt: tomorrow.times[Prayer.fajr]!);
}

/// "10 min", "2 min 30 s", "45 s".
String minSec(int seconds) {
  final m = seconds ~/ 60, s = seconds % 60;
  return [if (m > 0) '$m min', if (s > 0 || m == 0) '$s s'].join(' ');
}

/// Reminders for the chosen prayers over the next [days] days (from [now] on): one at the prayer time, and, if set,
/// a second one a little later ("get up now").
List<Reminder> prayerAlarms(PrayerSettings s, DateTime now, {int days = 7}) {
  if (!s.hasLocation || s.alerts.isEmpty) return const [];
  final out = <Reminder>[];
  for (var d = 0; d < days; d++) {
    final date = DateTime(now.year, now.month, now.day + d);
    final day = prayerDay(s, date);
    final dayNo = DateTime.utc(date.year, date.month, date.day).millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;
    final base = prayerNotificationIds + (dayNo % 4000) * 16; // 16 ids a day: 0-5 at the time, 8-13 the second
    for (final p in Prayer.values) {
      if (!p.isPrayer || !s.alerts.contains(p)) continue;
      final at = day.times[p]!;
      final name = p.salahOn(date), nameUrdu = p.salahUrduOn(date);
      if (at.isAfter(now)) {
        out.add(
          Reminder(
            id: base + p.index,
            at: at,
            title: '$name · $nameUrdu',
            body: 'It is time for $name. · $nameUrdu کا وقت ہو گیا ہے۔',
            payload: 'prayer:${p.name}',
            tone: s.tone.name,
          ),
        );
      }
      if (s.secondAfterSeconds > 0 && (!s.secondFajrOnly || p == Prayer.fajr)) {
        final later = at.add(Duration(seconds: s.secondAfterSeconds));
        if (later.isAfter(now)) {
          out.add(
            Reminder(
              id: base + 8 + p.index,
              at: later,
              title: 'Get up for $name · اٹھیں، $nameUrdu ادا کریں',
              body: 'Its time began ${minSec(s.secondAfterSeconds)} ago. Pray now. · وقت شروع ہوئے ${minSec(s.secondAfterSeconds)} ہو گئے، ابھی ادا کریں۔',
              payload: 'prayer-again:${p.name}',
              tone: s.secondTone.name,
              insistent: s.secondKeepRinging,
            ),
          );
        }
      }
    }
  }
  out.sort((a, b) => a.at.compareTo(b.at));
  return out;
}

const hijriMonthsEnglish = [
  'Muharram', 'Safar', "Rabi' al-Awwal", "Rabi' al-Thani", 'Jumada al-Ula', 'Jumada al-Akhirah', //
  'Rajab', "Sha'ban", 'Ramadan', 'Shawwal', "Dhu al-Qa'dah", 'Dhu al-Hijjah',
];
const hijriMonthsUrdu = [
  'محرم', 'صفر', 'ربیع الاول', 'ربیع الثانی', 'جمادی الاول', 'جمادی الثانی', //
  'رجب', 'شعبان', 'رمضان', 'شوال', 'ذوالقعدہ', 'ذوالحجہ',
];

/// The Hijri date (Umm al-Qura calendar, moved by [offset] days for local moon sighting).
({int day, int month, int year}) hijriDate(DateTime date, int offset) {
  final h = HijriCalendar.fromDate(DateTime(date.year, date.month, date.day).add(Duration(days: offset)));
  return (day: h.hDay, month: h.hMonth, year: h.hYear);
}

String hijriEnglish(DateTime date, int offset) {
  final h = hijriDate(date, offset);
  return '${h.day} ${hijriMonthsEnglish[h.month - 1]} ${h.year} AH';
}

String hijriUrdu(DateTime date, int offset, String Function(int) digits) {
  final h = hijriDate(date, offset);
  return '${digits(h.day)} ${hijriMonthsUrdu[h.month - 1]} ${digits(h.year)} ھ';
}
