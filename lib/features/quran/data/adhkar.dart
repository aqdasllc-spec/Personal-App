import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';

/// When a dhikr is said: morning, evening, or both.
enum DhikrTime { both, morning, evening }

/// One dhikr of the morning / evening (Hisn al-Muslim). Either its own Arabic and English, or a passage of the Quran
/// ([quran]: surah, first ayah, last ayah), shown from the app's Quran text and translations.
class Dhikr {
  const Dhikr({
    required this.n,
    required this.time,
    required this.count,
    required this.source,
    this.virtue = '',
    this.arabic = '',
    this.english = '',
    this.translit = '',
    this.quran,
    this.before = '',
  });
  final int n, count;
  final DhikrTime time;

  /// Where it is reported (Arabic, e.g. "مسلم، 4/ 2088، برقم 2723.").
  final String source;

  /// Its virtue, from the hadith (Arabic; often empty).
  final String virtue;
  final String arabic, english, translit;
  final (int, int, int)? quran;

  /// Said before the ayahs (the seeking of refuge), if the book has it.
  final String before;

  bool forMorning() => time != DhikrTime.evening;
  bool forEvening() => time != DhikrTime.morning;

  static Dhikr fromJson(Map<String, dynamic> j) {
    final q = j['quran'];
    return Dhikr(
      n: j['n'] as int,
      time: DhikrTime.values[(j['kind'] as int).clamp(0, 2)],
      count: j['count'] as int,
      source: (j['source'] as String?) ?? '',
      virtue: (j['virtue'] as String?) ?? '',
      arabic: (j['arabic'] as String?) ?? '',
      english: (j['english'] as String?) ?? '',
      translit: (j['translit'] as String?) ?? '',
      quran: q is List && q.length == 3 ? (q[0] as int, q[1] as int, q[2] as int) : null,
      before: (j['before'] as String?) ?? '',
    );
  }
}

Future<List<Dhikr>> loadAdhkarAsset() async {
  final raw = await rootBundle.loadString('assets/quran/adhkar.json');
  return [for (final j in jsonDecode(raw) as List) Dhikr.fromJson((j as Map).cast<String, dynamic>())];
}

final adhkarLoaderProvider = Provider<Future<List<Dhikr>> Function()>((_) => loadAdhkarAsset);
final adhkarProvider = FutureProvider<List<Dhikr>>((ref) => ref.watch(adhkarLoaderProvider)());

/// Which adhkar were said today, morning and evening (ticked by hand). Kept for a few days, synced.
class AdhkarDone extends Notifier<Map<String, Set<int>>> {
  static const key = 'adhkar_done';

  static String dayKey(DateTime d, bool morning) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}${morning ? 'm' : 'e'}';

  @override
  Map<String, Set<int>> build() {
    Future<void> load() async {
      try {
        final raw = await ref.read(syncedStoreProvider).state(key);
        if (raw == null || raw.isEmpty) return;
        final j = jsonDecode(raw) as Map<String, dynamic>;
        state = {
          for (final e in j.entries) e.key: {for (final n in e.value as List) n as int},
        };
      } catch (_) {}
    }

    Future.microtask(load);
    reloadOnRemote(ref, key, load);
    return const {};
  }

  Set<int> on(DateTime d, bool morning) => state[dayKey(d, morning)] ?? const {};

  void toggle(DateTime d, bool morning, int n) {
    final k = dayKey(d, morning);
    final set = {...on(d, morning)};
    set.contains(n) ? set.remove(n) : set.add(n);
    // keep this day and the two before it
    final keep = {
      for (var i = 0; i < 3; i++)
        for (final m in [true, false]) dayKey(DateTime(d.year, d.month, d.day - i), m),
    };
    final next = {
      for (final e in state.entries)
        if (keep.contains(e.key)) e.key: e.value,
      k: set,
    };
    state = next;
    try {
      ref.read(syncedStoreProvider).setState(key, jsonEncode({for (final e in next.entries) e.key: e.value.toList()..sort()}));
    } catch (_) {}
  }
}

final adhkarDoneProvider = NotifierProvider<AdhkarDone, Map<String, Set<int>>>(AdhkarDone.new);
