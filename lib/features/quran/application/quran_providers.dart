import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../data/quran_data.dart';

/// The bundled Quran (Arabic + English + Urdu). Loaded once, on first use.
final quranLoaderProvider = Provider<Future<QuranData> Function()>((_) => loadQuranAsset);
final quranDataProvider = FutureProvider<QuranData>((ref) => ref.watch(quranLoaderProvider)());

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
    Future.microtask(() async {
      try {
        final v = await ref.read(syncedStoreProvider).state(key);
        final d = v == null ? null : decode(v);
        if (d != null) state = d;
      } catch (_) {}
    });
    return initial;
  }

  void set(T v) {
    state = v;
    try {
      ref.read(syncedStoreProvider).setState(key, encode(v));
    } catch (_) {}
  }
}

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
