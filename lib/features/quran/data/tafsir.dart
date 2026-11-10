import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../app/providers.dart';
import '../application/quran_downloads.dart' show fileFetcherProvider;

/// A tafsir (commentary) the reader can open under any ayah. The texts come from the open Tafsir API
/// (github.com/spa5k/tafsir_api, taken from quran.com / the Quranic Universal Library), fetched a surah at a time the
/// first time it is opened, then kept on the phone.
class TafsirEdition {
  const TafsirEdition(this.slug, this.name, this.author, {required this.urdu});
  final String slug, name, author;
  final bool urdu;
}

const tafsirEditions = <TafsirEdition>[
  TafsirEdition('ur-tafseer-ibn-e-kaseer', 'تفسیر ابن کثیر', 'Hafiz Ibn Kathir (Urdu)', urdu: true),
  TafsirEdition('ur-tafsir-bayan-ul-quran', 'بیان القرآن', 'Dr. Israr Ahmad (Urdu)', urdu: true),
  TafsirEdition('en-tafisr-ibn-kathir', 'Tafsir Ibn Kathir', 'Hafiz Ibn Kathir (English, abridged)', urdu: false),
  TafsirEdition('en-tafsir-maarif-ul-quran', "Ma'ariful Qur'an", 'Mufti Muhammad Shafi (English)', urdu: false),
];

/// One surah's tafsir: the text for each ayah. Several ayahs explained together share the same text.
class SurahTafsir {
  const SurahTafsir(this.byAyah);
  final Map<int, String> byAyah;

  /// The text for [ayah] and the ayahs it is explained together with (first..last).
  ({String text, int from, int to})? of(int ayah) {
    final text = byAyah[ayah];
    if (text == null || text.trim().isEmpty) return null;
    var from = ayah, to = ayah;
    while (byAyah[from - 1] == text) {
      from--;
    }
    while (byAyah[to + 1] == text) {
      to++;
    }
    return (text: text, from: from, to: to);
  }

  /// Reads the API's file: a list of {ayah, text}, or {"ayahs": [...]}.
  static SurahTafsir parse(String raw) {
    final j = jsonDecode(raw);
    final list = j is Map ? j['ayahs'] : j;
    if (list is! List) throw const FormatException('Not a tafsir file');
    return SurahTafsir({
      for (final e in list)
        if (e is Map && e['ayah'] is int && e['text'] is String) e['ayah'] as int: e['text'] as String,
    });
  }
}

/// Where tafsir files are kept: `app support/tafsir/<edition>/<surah>.json`.
final tafsirDirProvider = FutureProvider<Directory>((ref) async {
  final d = Directory('${(await getApplicationSupportDirectory()).path}/tafsir');
  await d.create(recursive: true);
  return d;
});

/// The chosen tafsir (remembered, and synced). Urdu Ibn Kathir to begin with.
class TafsirChoice extends Notifier<TafsirEdition> {
  static const key = 'quran_tafsir';
  @override
  TafsirEdition build() {
    Future<void> load() async {
      try {
        final v = await ref.read(syncedStoreProvider).state(key);
        final e = tafsirEditions.where((e) => e.slug == v).firstOrNull;
        if (e != null) state = e;
      } catch (_) {}
    }

    Future.microtask(load);
    reloadOnRemote(ref, key, load);
    return tafsirEditions.first;
  }

  void set(TafsirEdition e) {
    state = e;
    try {
      ref.read(syncedStoreProvider).setState(key, e.slug);
    } catch (_) {}
  }
}

final tafsirChoiceProvider = NotifierProvider<TafsirChoice, TafsirEdition>(TafsirChoice.new);

/// The two places the files can come from (a fast CDN first, GitHub itself if that fails).
List<Uri> tafsirUrls(String slug, int surah) => [
  Uri.parse('https://cdn.jsdelivr.net/gh/spa5k/tafsir_api@main/tafsir/$slug/$surah.json'),
  Uri.parse('https://raw.githubusercontent.com/spa5k/tafsir_api/main/tafsir/$slug/$surah.json'),
];

/// One surah of one tafsir: from the phone if it is there, otherwise downloaded (and kept).
final surahTafsirProvider = FutureProvider.family<SurahTafsir, (String, int)>((ref, key) async {
  final (slug, surah) = key;
  final dir = await ref.watch(tafsirDirProvider.future);
  final file = File('${dir.path}/$slug/$surah.json');
  if (await file.exists()) {
    try {
      return SurahTafsir.parse(await file.readAsString());
    } catch (_) {
      await file.delete(); // damaged: fetch again
    }
  }
  await file.parent.create(recursive: true);
  final fetch = ref.read(fileFetcherProvider);
  Object? last;
  for (final url in tafsirUrls(slug, surah)) {
    try {
      await fetch(url, file);
      return SurahTafsir.parse(await file.readAsString());
    } catch (e) {
      last = e;
      if (await file.exists()) await file.delete();
    }
  }
  throw TafsirUnavailable('$last');
}, retry: (_, _) => null); // no silent retries: the sheet says what happened and offers Try again

class TafsirUnavailable implements Exception {
  const TafsirUnavailable(this.why);
  final String why;
  @override
  String toString() => 'The tafsir could not be downloaded ($why). It needs the internet the first time; after that it is kept on the phone.';
}

/// Space the kept tafsir files take, in bytes.
Future<int> tafsirBytes(Directory dir) async {
  var n = 0;
  if (!await dir.exists()) return 0;
  await for (final f in dir.list(recursive: true)) {
    if (f is File) n += await f.length();
  }
  return n;
}
