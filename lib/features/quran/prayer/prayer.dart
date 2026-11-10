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

/// How a prayer reminder sounds. The first three speak or play a sound through an alarm that sounds even in silent
/// mode and keeps going (if chosen) until "I'm up" is tapped; the rest are ordinary notifications.
enum PrayerTone {
  spoken('Says the prayer name', 'نماز کا نام بولے'),
  voice('Says your own words', 'آپ کے الفاظ بولے'),
  own('Your own sound (e.g. an Azan)', 'اپنی آواز (مثلاً اذان)'),
  alarm('Phone alarm sound', 'فون کا الارم'),
  ringtone('Phone ringtone', 'فون کی رنگ ٹون'),
  notification('Phone notification sound', 'نوٹیفکیشن کی آواز'),
  vibrate('Vibrate only', 'صرف وائبریشن');

  const PrayerTone(this.label, this.urdu);
  final String label, urdu;

  /// Rung by the alarm (speech or a sound file) rather than shown as a notification.
  bool get rings => this == spoken || this == voice || this == own;
}

/// The words the second reminder says by default; {prayer} becomes the prayer's name.
const defaultGetUpWords = 'Get up now, otherwise {prayer} will be missed.';

/// A prayer's name the way a voice should say it ("Salat ul Fajr").
String spokenName(Prayer p, DateTime d) => p.salahOn(d).replaceAll('-', ' ');

/// [words] with {prayer} replaced, ready to be said.
String getUpSpeech(String words, Prayer p, DateTime d) {
  final w = words.trim().isEmpty ? defaultGetUpWords : words.trim();
  return w.replaceAll('{prayer}', spokenName(p, d));
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
    this.tones = const {},
    this.sounds = const {},
    this.firstKeepRinging = false,
    this.secondAfterSeconds = 0,
    this.secondFajrOnly = false,
    this.secondTone = PrayerTone.voice,
    this.secondKeepRinging = true,
    this.secondWords = defaultGetUpWords,
    this.secondSound,
    this.offsets = const {},
  });

  /// How the reminder at each prayer's time sounds (not set = it says the prayer's name).
  final Map<Prayer, PrayerTone> tones;
  PrayerTone toneOf(Prayer p) => tones[p] ?? PrayerTone.spoken;

  /// The user's own sound for each prayer ([PrayerTone.own]): a file in the app's documents folder.
  final Map<Prayer, String> sounds;

  /// The reminder at the time keeps sounding until "I'm up" (spoken / own sound).
  final bool firstKeepRinging;

  /// What the second reminder says ([PrayerTone.voice]); {prayer} becomes the prayer's name.
  final String secondWords;

  /// The second reminder's own sound ([PrayerTone.own]).
  final String? secondSound;

  /// Minutes added to (or taken from) each calculated time, to match the local mosque.
  final Map<Prayer, int> offsets;

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
    Map<Prayer, PrayerTone>? tones,
    Map<Prayer, String>? sounds,
    bool? firstKeepRinging,
    int? secondAfterSeconds,
    bool? secondFajrOnly,
    PrayerTone? secondTone,
    bool? secondKeepRinging,
    String? secondWords,
    String? secondSound,
    Map<Prayer, int>? offsets,
  }) => PrayerSettings(
    lat: lat ?? this.lat,
    lng: lng ?? this.lng,
    place: place ?? this.place,
    method: method ?? this.method,
    hanafi: hanafi ?? this.hanafi,
    hijriOffset: hijriOffset ?? this.hijriOffset,
    alerts: alerts ?? this.alerts,
    tones: tones ?? this.tones,
    sounds: sounds ?? this.sounds,
    firstKeepRinging: firstKeepRinging ?? this.firstKeepRinging,
    secondAfterSeconds: secondAfterSeconds ?? this.secondAfterSeconds,
    secondFajrOnly: secondFajrOnly ?? this.secondFajrOnly,
    secondTone: secondTone ?? this.secondTone,
    secondKeepRinging: secondKeepRinging ?? this.secondKeepRinging,
    secondWords: secondWords ?? this.secondWords,
    secondSound: secondSound ?? this.secondSound,
    offsets: offsets ?? this.offsets,
  );

  /// One prayer's tone changed (and, for [PrayerTone.own], its file).
  PrayerSettings withTone(Prayer p, PrayerTone t, {String? sound}) =>
      copyWith(tones: {...tones, p: t}, sounds: sound == null ? null : {...sounds, p: sound});

  String encode() => jsonEncode({
    'lat': lat,
    'lng': lng,
    'place': place,
    'method': method.name,
    'hanafi': hanafi,
    'hijri': hijriOffset,
    'alerts': [for (final p in alerts) p.name],
    'tones': {for (final e in tones.entries) e.key.name: e.value.name},
    'sounds': {for (final e in sounds.entries) e.key.name: e.value},
    'firstLoop': firstKeepRinging,
    'second': secondAfterSeconds,
    'secondFajr': secondFajrOnly,
    'secondTone': secondTone.name,
    'insistent': secondKeepRinging,
    'words': secondWords,
    'secondSound': secondSound,
    'offsets': {for (final e in offsets.entries) e.key.name: e.value},
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
        tones: _byPrayer(j['tones'], (v) => PrayerTone.values.where((t) => t.name == v).firstOrNull),
        sounds: _byPrayer(j['sounds'], (v) => v is String && v.isNotEmpty ? v : null),
        firstKeepRinging: j['firstLoop'] as bool? ?? false,
        secondAfterSeconds: ((j['second'] as num?) ?? 0).toInt().clamp(0, 3599),
        secondFajrOnly: j['secondFajr'] as bool? ?? false,
        secondTone: PrayerTone.values.where((t) => t.name == j['secondTone']).firstOrNull ?? PrayerTone.voice,
        secondKeepRinging: j['insistent'] as bool? ?? true,
        secondWords: (j['words'] as String?) ?? defaultGetUpWords,
        secondSound: j['secondSound'] as String?,
        offsets: _byPrayer(j['offsets'], (v) => v is num ? v.toInt().clamp(-60, 60) : null),
      );
    } catch (_) {
      return null;
    }
  }
}

Map<Prayer, T> _byPrayer<T>(Object? j, T? Function(Object?) read) {
  if (j is! Map) return const {};
  return {for (final p in Prayer.values) p: ?read(j[p.name])};
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
  DateTime at(Prayer p, DateTime utc) => utc.toLocal().add(Duration(minutes: s.offsets[p] ?? 0));
  return PrayerDay(DateTime(date.year, date.month, date.day), {
    Prayer.fajr: at(Prayer.fajr, t.fajr),
    Prayer.sunrise: at(Prayer.sunrise, t.sunrise),
    Prayer.dhuhr: at(Prayer.dhuhr, t.dhuhr),
    Prayer.asr: at(Prayer.asr, t.asr),
    Prayer.maghrib: at(Prayer.maghrib, t.maghrib),
    Prayer.isha: at(Prayer.isha, t.isha),
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
            tone: s.toneOf(p).name,
            insistent: s.toneOf(p).rings && s.firstKeepRinging,
            speech: s.toneOf(p) == PrayerTone.spoken ? spokenName(p, date) : null,
            sound: s.toneOf(p) == PrayerTone.own ? s.sounds[p] : null,
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
              speech: s.secondTone == PrayerTone.voice
                  ? getUpSpeech(s.secondWords, p, date)
                  : (s.secondTone == PrayerTone.spoken ? spokenName(p, date) : null),
              sound: s.secondTone == PrayerTone.own ? s.secondSound : null,
            ),
          );
        }
      }
    }
  }
  out.sort((a, b) => a.at.compareTo(b.at));
  return out;
}

/// How far ahead prayer reminders are set on Android (each visit to Folio moves the window forward).
const prayerScheduleDays = 21;

/// If Folio is not opened for almost [days] days, the reminders would run out: two days before, a notification asks
/// to open it once (which sets the next weeks).
Reminder prayerRenewalNudge(DateTime now, int days) {
  final at = DateTime(now.year, now.month, now.day + days - 2, 21, 30);
  return Reminder(
    id: prayerNotificationIds + 0xffe0,
    at: at,
    title: 'Keep your prayer reminders coming · نماز کی یاد دہانیاں جاری رکھیں',
    body: 'Open Folio once so the next weeks are set. · اگلے ہفتوں کے لیے فولیو ایک بار کھولیں۔',
    payload: 'prayer-renew',
  );
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

/// Times beyond the five prayers, worked out from the day's prayer times (so mosque adjustments carry through).
/// The fixed minutes are the common rule of thumb, shown as approximate.
class ExtraTimes {
  const ExtraTimes({
    required this.sehriEnds,
    required this.iftar,
    required this.ishraq,
    required this.zawalFrom,
    required this.zawalTo,
    required this.sunriseFrom,
    required this.sunriseTo,
    required this.sunsetFrom,
    required this.sunsetTo,
    required this.midnight,
    required this.lastThird,
    required this.nextFajr,
    required this.ramadan,
  });

  /// Eating stops at Fajr; the fast opens at Maghrib.
  final DateTime sehriEnds, iftar;

  /// Ishraq / Chasht (Duha) begin when the sun is well up: about 20 minutes after sunrise.
  final DateTime ishraq;

  /// Prayer is disliked while the sun rises, at its height and while it sets.
  final DateTime sunriseFrom, sunriseTo, zawalFrom, zawalTo, sunsetFrom, sunsetTo;

  /// The night (Maghrib to the next Fajr): its middle, and the start of its last third (best for Tahajjud).
  final DateTime midnight, lastThird, nextFajr;

  /// The Hijri month is Ramadan (Sehri and Iftar are shown then).
  final bool ramadan;
}

ExtraTimes extraTimes(PrayerSettings s, DateTime date) {
  final d = prayerDay(s, date), next = prayerDay(s, DateTime(date.year, date.month, date.day + 1));
  final sunrise = d.times[Prayer.sunrise]!, dhuhr = d.times[Prayer.dhuhr]!, maghrib = d.times[Prayer.maghrib]!;
  final fajr2 = next.times[Prayer.fajr]!;
  final night = fajr2.difference(maghrib);
  return ExtraTimes(
    sehriEnds: d.times[Prayer.fajr]!,
    iftar: maghrib,
    ishraq: sunrise.add(const Duration(minutes: 20)),
    sunriseFrom: sunrise,
    sunriseTo: sunrise.add(const Duration(minutes: 20)),
    zawalFrom: dhuhr.subtract(const Duration(minutes: 10)),
    zawalTo: dhuhr,
    sunsetFrom: maghrib.subtract(const Duration(minutes: 20)),
    sunsetTo: maghrib,
    midnight: maghrib.add(night ~/ 2),
    lastThird: maghrib.add(night * 2 ~/ 3),
    nextFajr: fajr2,
    ramadan: hijriDate(date, s.hijriOffset).month == 9,
  );
}

/// The direction of the Kaaba from [lat], [lng]: degrees clockwise from true north.
double qiblaBearing(double lat, double lng) => adhan.Qibla(adhan.Coordinates(lat, lng)).direction;

/// Whether each prayer was prayed, day by day, and the qaza (missed prayers still to make up).
class PrayerLog {
  const PrayerLog({this.days = const {}, this.pastOwed = const {}, this.madeUp = const {}});

  /// 'yyyy-mm-dd' -> prayer -> true (prayed) / false (missed).
  final Map<String, Map<Prayer, bool>> days;

  /// Missed prayers from before the log, entered by hand.
  final Map<Prayer, int> pastOwed;

  /// Qaza prayers made up so far.
  final Map<Prayer, int> madeUp;

  static String dayKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  bool? on(DateTime d, Prayer p) => days[dayKey(d)]?[p];

  /// Marks [p] on [d] as prayed (true), missed (false) or not marked (null).
  PrayerLog mark(DateTime d, Prayer p, bool? prayed) {
    final k = dayKey(d);
    final day = {...?days[k]};
    if (prayed == null) {
      day.remove(p);
    } else {
      day[p] = prayed;
    }
    final all = {...days};
    if (day.isEmpty) {
      all.remove(k);
    } else {
      all[k] = day;
    }
    return PrayerLog(days: all, pastOwed: pastOwed, madeUp: madeUp);
  }

  int missedInLog(Prayer p) => days.values.where((d) => d[p] == false).length;

  /// Still to make up for [p] (never below zero).
  int owed(Prayer p) => (missedInLog(p) + (pastOwed[p] ?? 0) - (madeUp[p] ?? 0)).clamp(0, 1 << 30);
  int get owedTotal => Prayer.values.where((p) => p.isPrayer).fold(0, (n, p) => n + owed(p));

  PrayerLog makeUp(Prayer p, [int n = 1]) =>
      PrayerLog(days: days, pastOwed: pastOwed, madeUp: {...madeUp, p: ((madeUp[p] ?? 0) + n).clamp(0, 1 << 30)});

  PrayerLog addPast(Prayer p, int n) =>
      PrayerLog(days: days, pastOwed: {...pastOwed, p: ((pastOwed[p] ?? 0) + n).clamp(0, 1 << 30)}, madeUp: madeUp);

  /// Days in a row, up to [today], with every one of the five prayers marked prayed (today counts once complete).
  int streak(DateTime today) {
    bool full(DateTime d) => Prayer.values.where((p) => p.isPrayer).every((p) => on(d, p) == true);
    var d = DateTime(today.year, today.month, today.day);
    if (!full(d)) d = DateTime(d.year, d.month, d.day - 1);
    var n = 0;
    while (full(d)) {
      n++;
      d = DateTime(d.year, d.month, d.day - 1);
    }
    return n;
  }

  String encode() => jsonEncode({
    for (final e in days.entries) e.key: {for (final x in e.value.entries) x.key.name: x.value ? 1 : 0},
    '_past': {for (final e in pastOwed.entries) e.key.name: e.value},
    '_made': {for (final e in madeUp.entries) e.key.name: e.value},
  });

  static PrayerLog decode(String? raw) {
    if (raw == null || raw.isEmpty) return const PrayerLog();
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final days = <String, Map<Prayer, bool>>{};
      for (final e in j.entries) {
        if (e.key.startsWith('_') || e.value is! Map) continue;
        days[e.key] = _byPrayer(e.value, (v) => v is num ? v == 1 : null);
      }
      int? count(Object? v) => v is num && v >= 0 ? v.toInt() : null;
      return PrayerLog(days: days, pastOwed: _byPrayer(j['_past'], count), madeUp: _byPrayer(j['_made'], count));
    } catch (_) {
      return const PrayerLog();
    }
  }
}
