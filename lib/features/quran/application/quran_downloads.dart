import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../data/quran_data.dart';
import '../../../app/providers.dart';
import 'quran_providers.dart';

/// Where downloaded recitations live: `app support/quran_audio/reciter id/ayah number (1-6236).mp3`.
final quranAudioDirProvider = FutureProvider<Directory>((ref) async {
  final d = Directory('${(await getApplicationSupportDirectory()).path}/quran_audio');
  await d.create(recursive: true);
  return d;
});

/// Fetches one file. An interface so tests need no internet.
typedef FileFetcher = Future<void> Function(Uri url, File into);

Future<void> httpFetch(Uri url, File into) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  try {
    final req = await client.getUrl(url);
    final res = await req.close().timeout(const Duration(seconds: 60));
    if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}', uri: url);
    final part = File('${into.path}.part');
    final sink = part.openWrite();
    await res.timeout(const Duration(seconds: 60)).pipe(sink);
    await part.rename(into.path); // only a complete file gets the real name
  } finally {
    client.close(force: true);
  }
}

final fileFetcherProvider = Provider<FileFetcher>((_) => httpFetch);

/// A download in progress (or finished, or stopped by an error).
class DownloadJob {
  const DownloadJob({required this.reciterId, required this.label, required this.done, required this.total, this.running = true, this.error});
  final String reciterId, label;
  final int done, total;
  final bool running;
  final String? error;
  double get fraction => total == 0 ? 1 : done / total;
}

/// True when the phone is on mobile data only (no Wi-Fi or cable). A function so tests need no network.
final onMobileDataProvider = Provider<Future<bool> Function()>((_) => () async {
  try {
    final c = await Connectivity().checkConnectivity();
    return c.contains(ConnectivityResult.mobile) && !c.contains(ConnectivityResult.wifi) && !c.contains(ConnectivityResult.ethernet);
  } catch (_) {
    return false;
  }
});

/// Downloads on Wi-Fi only (the default): a download on mobile data needs a yes first, and one running pauses when
/// Wi-Fi is lost. Remembered on this device.
class WifiOnly extends Notifier<bool> {
  static const key = 'quran_wifi_only';
  @override
  bool build() {
    Future.microtask(() async {
      try {
        final v = await ref.read(syncedStoreProvider).state(key);
        if (v != null) state = v != '0';
      } catch (_) {}
    });
    return true;
  }

  void set(bool v) {
    state = v;
    try {
      ref.read(syncedStoreProvider).setState(key, v ? '1' : '0');
    } catch (_) {}
  }
}

final wifiOnlyProvider = NotifierProvider<WifiOnly, bool>(WifiOnly.new);

/// Downloads recitations for listening without internet: one surah, or the whole Quran, for one reciter.
/// Four files at a time; files already there are skipped, so a stopped download continues where it was.
class QuranDownloads extends Notifier<DownloadJob?> {
  int _token = 0;

  @override
  DownloadJob? build() => null;

  Future<Directory> _dir(String reciterId) async {
    final base = await ref.read(quranAudioDirProvider.future);
    final d = Directory('${base.path}/$reciterId');
    await d.create(recursive: true);
    return d;
  }

  /// How many of the ayahs [from]..[to] (positions, inclusive) are on the phone for [r].
  Future<int> countHere(Reciter r, int from, int to) async {
    final d = await _dir(r.id);
    var n = 0;
    for (var i = from; i <= to; i++) {
      if (File('${d.path}/${i + 1}.mp3').existsSync()) n++;
    }
    return n;
  }

  /// Space the downloaded files of [r] take, in bytes.
  Future<int> bytesHere(Reciter r) async {
    final d = await _dir(r.id);
    var total = 0;
    await for (final f in d.list()) {
      if (f is File && f.path.endsWith('.mp3')) total += await f.length();
    }
    return total;
  }

  /// [mobileOk]: the user agreed to use mobile data for this download (otherwise, with Wi-Fi only on, it pauses
  /// when the phone is on mobile data).
  Future<void> downloadSurah(QuranData q, Reciter r, int surah, {bool mobileOk = false}) {
    final s = q.surah(surah);
    return _download(r, '${s.name} ($surah)', s.firstIndex, s.firstIndex + s.ayahCount - 1, mobileOk: mobileOk);
  }

  Future<void> downloadAll(QuranData q, Reciter r, {bool mobileOk = false}) =>
      _download(r, 'the whole Quran', 0, q.ayahCount - 1, mobileOk: mobileOk);

  Future<void> _download(Reciter r, String label, int from, int to, {bool mobileOk = false}) async {
    final onMobile = ref.read(onMobileDataProvider);
    final guard = !mobileOk && ref.read(wifiOnlyProvider);
    var checked = 0;
    final token = ++_token;
    final dir = await _dir(r.id);
    final todo = [for (var i = from; i <= to; i++) if (!File('${dir.path}/${i + 1}.mp3').existsSync()) i];
    final total = to - from + 1;
    var done = total - todo.length;
    state = DownloadJob(reciterId: r.id, label: label, done: done, total: total);
    final fetch = ref.read(fileFetcherProvider);
    var next = 0;
    String? error;
    Future<void> worker() async {
      while (token == _token && error == null && next < todo.length) {
        // Wi-Fi only: look at the connection every 20 files
        if (guard && checked++ % 20 == 0 && await onMobile()) {
          error = 'Paused: the phone is on mobile data and downloads are set to Wi-Fi only. Tap Download on Wi-Fi to continue.';
          return;
        }
        final i = todo[next++];
        var tries = 0;
        while (true) {
          try {
            await fetch(r.ayahUrl(i + 1), File('${dir.path}/${i + 1}.mp3'));
            break;
          } catch (e) {
            if (++tries >= 3) {
              error = 'Stopped: could not download ayah ${i + 1} ($e). Check the internet and tap Download again: it continues where it stopped.';
              return;
            }
            await Future<void>.delayed(Duration(seconds: tries));
          }
        }
        if (token != _token) return;
        done++;
        state = DownloadJob(reciterId: r.id, label: label, done: done, total: total);
      }
    }

    await Future.wait([for (var w = 0; w < 4; w++) worker()]);
    if (token != _token) return;
    state = DownloadJob(reciterId: r.id, label: label, done: done, total: total, running: false, error: error);
  }

  /// Stops the download in progress (what is downloaded stays).
  void cancel() {
    _token++;
    final s = state;
    if (s != null) state = DownloadJob(reciterId: s.reciterId, label: s.label, done: s.done, total: s.total, running: false);
  }

  /// Removes the downloaded files of [r].
  Future<void> deleteAll(Reciter r) async {
    cancel();
    final d = await _dir(r.id);
    if (d.existsSync()) await d.delete(recursive: true);
    state = null;
  }
}

final quranDownloadsProvider = NotifierProvider<QuranDownloads, DownloadJob?>(QuranDownloads.new);

/// Rough size of a reciter's whole Quran, shown before downloading. Measured: 63 ayahs spread through the Quran
/// (Alafasy, 128 kbps) average 261 KB, so about 1.6 GB in all; other bit rates scale with it (reciters differ in pace).
/// Measured: all 6236 ayahs at 128 kbps are about 1625 MB; other bit rates scale with it.
double wholeQuranBytes(Reciter r) => 1625e6 * r.bitrate / 128;

String wholeQuranSize(Reciter r) {
  final mb = wholeQuranBytes(r) / 1e6;
  return mb >= 1000 ? 'about ${(mb / 1000).toStringAsFixed(1)} GB' : 'about ${mb.round()} MB';
}
