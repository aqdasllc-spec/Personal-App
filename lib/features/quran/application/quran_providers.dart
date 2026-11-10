import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show TargetPlatform, compute, defaultTargetPlatform;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../planner/application/planner_controller.dart' show reminderSchedulerProvider;
import '../../planner/domain/reminders.dart';
import '../data/quran_data.dart';
import '../presentation/quran_style.dart' show activeQuranScript;
import '../domain/daily.dart';
import '../domain/khatm.dart';
import '../domain/quran_search.dart';

/// The bundled Quran (Arabic + English + Urdu). Loaded once, on first use.
final quranLoaderProvider = Provider<Future<QuranData> Function()>((_) => loadQuranAsset);
final quranBaseProvider = FutureProvider<QuranData>((ref) => ref.watch(quranLoaderProvider)());

/// Loads one of the other Urdu translations (a function so tests can give their own).
final urduTranslationLoaderProvider = Provider<Future<List<String>> Function(String id)>((_) => loadUrduTranslation);
final _urduTextsProvider = FutureProvider.family<List<String>, String>((ref, id) => ref.watch(urduTranslationLoaderProvider)(id));

/// The Quran as chosen to be shown: in the chosen script, with the chosen Urdu translation.
final quranDataProvider = FutureProvider<QuranData>((ref) async {
  final base = await ref.watch(quranBaseProvider.future);
  final script = ref.watch(quranScriptProvider);
  final tr = ref.watch(urduTranslationProvider);
  List<String>? urdu;
  if (tr.id != urduTranslations.first.id) {
    try {
      final t = await ref.watch(_urduTextsProvider(tr.id).future);
      if (t.length == base.ayahCount) urdu = t;
    } catch (_) {} // unreadable: Jalandhry stays
  }
  final q = base.view(script: script, urdu: urdu, urduName: urdu == null ? null : tr.name, urduRtl: urdu == null ? null : tr.rtl);
  activeQuranScript = q.script;
  return q;
});

/// The bundled Sahih al-Bukhari selection (Arabic + English + Urdu).
final hadithLoaderProvider = Provider<Future<HadithData> Function()>((_) => loadHadithAsset);
final hadithDataProvider = FutureProvider<HadithData>((ref) => ref.watch(hadithLoaderProvider)());

/// A remembered choice (this device only), restored after start-up without delaying the first frame.
class _Pref<T> extends Notifier<T> {
  _Pref(this.key, this.initial, this.decode, this.encode);
  final String key;
  final T initial;
  final T? Function(String) decode;
  final String Function(T) encode;

  @override
  T build() {
    Future<void> load() async {
      try {
        final v = await ref.read(syncedStoreProvider).state(key);
        final d = v == null ? null : decode(v);
        if (d != null) state = d;
      } catch (_) {}
    }

    Future.microtask(load);
    reloadOnRemote(ref, key, load);
    return initial;
  }

  void set(T v) {
    state = v;
    try {
      ref.read(syncedStoreProvider).setState(key, encode(v));
    } catch (_) {}
  }
}

/// The script the Arabic is shown in (Indo-Pak to begin with). Synced.
final quranScriptProvider = NotifierProvider<_Pref<QuranScript>, QuranScript>(
  () => _Pref('quran_script', QuranScript.indopak, (v) => QuranScript.values.where((s) => s.name == v).firstOrNull, (v) => v.name),
);

/// The Urdu translation shown (Jalandhry to begin with). Synced.
final urduTranslationProvider = NotifierProvider<_Pref<UrduTranslation>, UrduTranslation>(
  () => _Pref('quran_urdu', urduTranslations.first, (v) => urduTranslations.where((t) => t.id == v).firstOrNull, (v) => v.id),
);

/// Which translation the Home card shows: Urdu or English.
enum DailyLang { urdu, english }

final dailyLangProvider = NotifierProvider<_Pref<DailyLang>, DailyLang>(
  () => _Pref('quran_daily_lang', DailyLang.urdu, (v) => v == 'en' ? DailyLang.english : DailyLang.urdu, (v) => v == DailyLang.english ? 'en' : 'ur'),
);

/// What the Quran reader shows under the Arabic.
enum TranslationMode {
  urdu('اردو', 'Urdu'),
  english('English', 'English'),
  both('Both', 'Urdu and English'),
  none('Arabic only', 'Arabic only');

  const TranslationMode(this.label, this.description);
  final String label, description;
  bool get showUrdu => this == urdu || this == both;
  bool get showEnglish => this == english || this == both;
}

final translationModeProvider = NotifierProvider<_Pref<TranslationMode>, TranslationMode>(
  () => _Pref(
    'quran_translation',
    TranslationMode.urdu,
    (v) => TranslationMode.values.where((m) => m.name == v).firstOrNull,
    (v) => v.name,
  ),
);

/// Size of the Arabic text in the reader (1 = normal).
final quranTextScaleProvider = NotifierProvider<_Pref<double>, double>(
  () => _Pref('quran_text_scale', 1.0, (v) => double.tryParse(v)?.clamp(.8, 1.8), (v) => v.toStringAsFixed(2)),
);

/// Where you stopped reading: (surah, ayah).
final quranLastReadProvider = NotifierProvider<_Pref<(int, int)?>, (int, int)?>(
  () => _Pref<(int, int)?>('quran_last_read', null, (v) {
    final p = v.split(':');
    final s = p.length == 2 ? int.tryParse(p[0]) : null, a = p.length == 2 ? int.tryParse(p[1]) : null;
    return s == null || a == null ? null : (s, a);
  }, (v) => v == null ? '' : '${v.$1}:${v.$2}'),
);

/// A voice for listening. [id] and [bitrate] name the recordings on cdn.islamic.network (each checked to exist for
/// the first, last and several ayahs in between).
class Reciter {
  const Reciter(this.id, this.name, this.arabic, this.bitrate, {this.style = ''});
  final String id, name, arabic, style;
  final int bitrate;

  /// The recording of ayah number [n] in the whole Quran (1-6236).
  Uri ayahUrl(int n) => Uri.parse('https://cdn.islamic.network/quran/audio/$bitrate/$id/$n.mp3');
}

const reciters = <Reciter>[
  Reciter('ar.alafasy', 'Mishary Rashid Alafasy', 'مشاري راشد العفاسي', 128),
  Reciter('ar.abdulsamad', 'Abdul Basit Abdul Samad', 'عبد الباسط عبد الصمد', 64),
  Reciter('ar.husary', 'Mahmoud Khalil Al-Husary', 'محمود خليل الحصري', 128),
  Reciter('ar.husarymujawwad', 'Al-Husary (Mujawwad)', 'الحصري (مجوّد)', 128, style: 'Mujawwad'),
  Reciter('ar.abdurrahmaansudais', 'Abdurrahman As-Sudais', 'عبد الرحمن السديس', 192),
  Reciter('ar.saoodshuraym', 'Saud Ash-Shuraym', 'سعود الشريم', 64),
  Reciter('ar.mahermuaiqly', 'Maher Al-Muaiqly', 'ماهر المعيقلي', 128),
  Reciter('ar.hudhaify', 'Ali Al-Hudhaify', 'علي الحذيفي', 128),
  Reciter('ar.ahmedajamy', 'Ahmed Al-Ajamy', 'أحمد العجمي', 128),
  Reciter('ar.shaatree', 'Abu Bakr Ash-Shatri', 'أبو بكر الشاطري', 128),
  Reciter('ar.abdullahbasfar', 'Abdullah Basfar', 'عبد الله بصفر', 192),
  Reciter('ar.muhammadayyoub', 'Muhammad Ayyub', 'محمد أيوب', 128),
  Reciter('ar.muhammadjibreel', 'Muhammad Jibreel', 'محمد جبريل', 128),
  Reciter('ar.hanirifai', 'Hani Ar-Rifai', 'هاني الرفاعي', 192),
];

/// Spoken translations that can follow each recited ayah.
const urduVoice = Reciter('ur.khan', 'Urdu: Shamshad Ali Khan', 'اردو ترجمہ: شمشاد علی خان', 64);
const englishVoice = Reciter('en.walk', 'English: Ibrahim Walk', 'English: Ibrahim Walk', 192);

final reciterProvider = NotifierProvider<_Pref<Reciter>, Reciter>(
  () => _Pref('quran_reciter', reciters.first, (v) => reciters.where((r) => r.id == v).firstOrNull, (v) => v.id),
);

/// After each recited ayah: nothing, or its spoken Urdu / English translation.
enum SpokenTranslation {
  none('Recitation only'),
  urdu('Then Urdu translation'),
  english('Then English translation');

  const SpokenTranslation(this.label);
  final String label;
  Reciter? get voice => switch (this) {
    none => null,
    urdu => urduVoice,
    english => englishVoice,
  };
}

final spokenTranslationProvider = NotifierProvider<_Pref<SpokenTranslation>, SpokenTranslation>(
  () => _Pref(
    'quran_spoken_translation',
    SpokenTranslation.none,
    (v) => SpokenTranslation.values.where((m) => m.name == v).firstOrNull,
    (v) => v.name,
  ),
);

/// The khatm goal (null = none). Remembered on this device; follows your reading place forward by itself.
class KhatmController extends Notifier<KhatmPlan?> {
  static const key = 'quran_khatm';

  @override
  KhatmPlan? build() {
    Future<void> load() async {
      try {
        final raw = await ref.read(syncedStoreProvider).state(key);
        state = raw == null || raw.isEmpty ? null : KhatmPlan.decode(raw);
      } catch (_) {}
    }

    Future.microtask(load);
    reloadOnRemote(ref, key, load);
    // reading moves the plan forward: a page counts as read once the next ayah you reach is on a later page
    ref.listen<(int, int)?>(quranLastReadProvider, (_, last) {
      final q = ref.read(quranDataProvider).value;
      final p = state;
      if (q == null || p == null || last == null || !q.valid(last.$1, last.$2)) return;
      final i = q.indexOf(last.$1, last.$2);
      final done = i + 1 >= q.ayahCount ? QuranData.pageCount : q.pageOf(i + 1) - 1;
      if (done > p.donePage) _save(p.withDone(done));
    });
    return null;
  }

  void _save(KhatmPlan? p) {
    state = p;
    try {
      ref.read(syncedStoreProvider).setState(key, p?.encode() ?? '');
    } catch (_) {}
  }

  /// A new goal: [days] days, from the beginning or from the page you are on.
  void start({required int days, required int fromPage, DateTime? today}) {
    final t = today ?? DateTime.now();
    _save(KhatmPlan(start: DateTime(t.year, t.month, t.day), days: days, startPage: fromPage, donePage: fromPage - 1));
  }

  void stop() => _save(null);
}

final khatmProvider = NotifierProvider<KhatmController, KhatmPlan?>(KhatmController.new);

/// Hifz (memorising) settings: how to repeat, and whether the Arabic is hidden until tapped. Remembered.
class HifzSettings {
  const HifzSettings({this.eachAyah = 3, this.rounds = 1, this.pauseSeconds = 0, this.hideArabic = false});
  final int eachAyah, rounds, pauseSeconds;
  final bool hideArabic;

  HifzSettings copyWith({int? eachAyah, int? rounds, int? pauseSeconds, bool? hideArabic}) => HifzSettings(
    eachAyah: eachAyah ?? this.eachAyah,
    rounds: rounds ?? this.rounds,
    pauseSeconds: pauseSeconds ?? this.pauseSeconds,
    hideArabic: hideArabic ?? this.hideArabic,
  );
}

class HifzController extends Notifier<HifzSettings> {
  static const key = 'quran_hifz';
  @override
  HifzSettings build() {
    Future<void> load() async {
      try {
        final raw = await ref.read(syncedStoreProvider).state(key);
        if (raw == null) return;
        final p = raw.split(',').map(int.tryParse).toList();
        if (p.length == 4 && p.every((x) => x != null)) {
          state = HifzSettings(eachAyah: p[0]!.clamp(1, 10), rounds: p[1]!.clamp(1, 10), pauseSeconds: p[2]!.clamp(0, 10), hideArabic: p[3] == 1);
        }
      } catch (_) {}
    }

    Future.microtask(load);
    reloadOnRemote(ref, key, load);
    return const HifzSettings();
  }

  void set(HifzSettings s) {
    state = s;
    try {
      ref.read(syncedStoreProvider).setState(key, '${s.eachAyah},${s.rounds},${s.pauseSeconds},${s.hideArabic ? 1 : 0}');
    } catch (_) {}
  }
}

final hifzProvider = NotifierProvider<HifzController, HifzSettings>(HifzController.new);

/// A saved ayah with an optional note.
class QuranBookmark {
  const QuranBookmark(this.surah, this.ayah, {this.note = '', required this.at});
  final int surah, ayah;
  final String note;
  final DateTime at;

  Map<String, Object> toJson() => {'s': surah, 'a': ayah, 'n': note, 't': at.millisecondsSinceEpoch};
  static QuranBookmark? fromJson(Object? j) {
    if (j is! Map) return null;
    final s = j['s'], a = j['a'];
    if (s is! int || a is! int) return null;
    return QuranBookmark(s, a, note: (j['n'] as String?) ?? '', at: DateTime.fromMillisecondsSinceEpoch((j['t'] as int?) ?? 0));
  }
}

/// Bookmarked ayahs with notes, newest first. Remembered on this device.
class QuranBookmarks extends Notifier<List<QuranBookmark>> {
  static const key = 'quran_bookmarks';
  @override
  List<QuranBookmark> build() {
    Future<void> load() async {
      try {
        final raw = await ref.read(syncedStoreProvider).state(key);
        if (raw == null) return;
        state = raw.isEmpty ? const [] : [for (final j in (jsonDecode(raw) as List)) ?QuranBookmark.fromJson(j)];
      } catch (_) {}
    }

    Future.microtask(load);
    reloadOnRemote(ref, key, load);
    return const [];
  }

  QuranBookmark? of(int surah, int ayah) => state.where((b) => b.surah == surah && b.ayah == ayah).firstOrNull;

  void save(int surah, int ayah, String note) {
    final rest = state.where((b) => !(b.surah == surah && b.ayah == ayah));
    _set([QuranBookmark(surah, ayah, note: note.trim(), at: DateTime.now()), ...rest]);
  }

  void remove(int surah, int ayah) => _set(state.where((b) => !(b.surah == surah && b.ayah == ayah)).toList());

  void _set(List<QuranBookmark> v) {
    state = v;
    try {
      ref.read(syncedStoreProvider).setState(key, jsonEncode([for (final b in v) b.toJson()]));
    } catch (_) {}
  }
}

final quranBookmarksProvider = NotifierProvider<QuranBookmarks, List<QuranBookmark>>(QuranBookmarks.new);

QuranSearchIndex _buildIndex(QuranData q) => QuranSearchIndex.of(q);

/// Built once, off the main thread, the first time you search.
final quranSearchIndexProvider = FutureProvider<QuranSearchIndex>((ref) async {
  final q = await ref.watch(quranDataProvider.future);
  return compute(_buildIndex, q);
});

/// The morning "ayah of the day" notification: the time it comes (null = off). Remembered on this device.
class DailyAyahNotify extends Notifier<({int hour, int minute})?> {
  static const key = 'quran_daily_notify';

  @override
  ({int hour, int minute})? build() {
    Future<void> load() async {
      try {
        final raw = await ref.read(syncedStoreProvider).state(key);
        final p = (raw ?? '').split(':');
        final h = p.length == 2 ? int.tryParse(p[0]) : null, m = p.length == 2 ? int.tryParse(p[1]) : null;
        state = h != null && m != null ? (hour: h.clamp(0, 23), minute: m.clamp(0, 59)) : null;
        await resync();
      } catch (_) {}
    }

    Future.microtask(load);
    reloadOnRemote(ref, key, load);
    return null;
  }

  Future<void> set(({int hour, int minute})? at) async {
    state = at;
    try {
      ref.read(syncedStoreProvider).setState(key, at == null ? '' : '${at.hour}:${at.minute}');
    } catch (_) {}
    if (at != null) {
      final s = ref.read(reminderSchedulerProvider);
      if (!await s.hasPermission()) await s.requestPermission();
    }
    await resync();
  }

  /// The next three weeks' notifications (Android; one week elsewhere), each with that day's ayah in the Home card's language.
  Future<void> resync({DateTime? now}) async {
    final at = state;
    final sched = ref.read(reminderSchedulerProvider);
    if (at == null) {
      await sched.replaceDailyAyahAlarms(const []).catchError((Object _) {});
      return;
    }
    final q = await ref.read(quranDataProvider.future);
    final urdu = ref.read(dailyLangProvider) == DailyLang.urdu;
    final t = now ?? DateTime.now();
    final out = <Reminder>[];
    final days = defaultTargetPlatform == TargetPlatform.android ? 21 : 7; // iOS allows only 64 pending in all
    for (var d = 0; d < days; d++) {
      final when = DateTime(t.year, t.month, t.day + d, at.hour, at.minute);
      if (!when.isAfter(t)) continue;
      final a = dailyAyah(q, when);
      final text = (urdu ? a.urdu : a.english).join(' ');
      out.add(
        Reminder(
          id: dailyAyahNotificationIds + dayNumber(when) % 8000,
          at: when,
          title: urdu ? 'آج کی آیت · ${a.surah.arabic}' : 'Ayah of the day · ${a.surah.name} ${a.ref}',
          body: text.length > 240 ? '${text.substring(0, 237)}…' : text,
          payload: 'ayah:${a.surah.number}:${a.from}',
        ),
      );
    }
    await sched.replaceDailyAyahAlarms(out).catchError((Object _) {});
  }
}

final dailyAyahNotifyProvider = NotifierProvider<DailyAyahNotify, ({int hour, int minute})?>(DailyAyahNotify.new);
