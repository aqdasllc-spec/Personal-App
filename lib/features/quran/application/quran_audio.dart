import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart' as ja;

import '../../library/application/read_aloud.dart' show mediaControlsProvider;
import '../data/quran_data.dart';
import 'quran_downloads.dart';
import 'quran_providers.dart';

/// What the player reports. [index] is the position in the queue that is playing.
enum PlayerPhase { idle, loading, playing, paused, finished, failed }

/// The sound side, behind an interface so tests need no audio device.
abstract class AyahPlayer {
  Future<void> setQueue(List<Uri> urls, {int start = 0});
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seekToIndex(int i);
  Stream<int?> get index;
  Stream<PlayerPhase> get phase;
  Future<void> dispose();
}

/// Streams the recordings over the internet with just_audio (one file per ayah, played back to back).
class JustAudioAyahPlayer implements AyahPlayer {
  final _p = ja.AudioPlayer();
  final _phase = StreamController<PlayerPhase>.broadcast();
  StreamSubscription<ja.PlayerState>? _sub;

  JustAudioAyahPlayer() {
    _sub = _p.playerStateStream.listen(
      (s) => _phase.add(switch (s.processingState) {
        ja.ProcessingState.idle => PlayerPhase.idle,
        ja.ProcessingState.loading || ja.ProcessingState.buffering => PlayerPhase.loading,
        ja.ProcessingState.ready => s.playing ? PlayerPhase.playing : PlayerPhase.paused,
        ja.ProcessingState.completed => PlayerPhase.finished,
      }),
      onError: (Object _) => _phase.add(PlayerPhase.failed),
    );
  }

  @override
  Future<void> setQueue(List<Uri> urls, {int start = 0}) async {
    await _p.setAudioSources([
      for (final u in urls)
        u.scheme == 'silence' ? ja.SilenceAudioSource(duration: Duration(milliseconds: int.tryParse(u.path) ?? 0)) : ja.AudioSource.uri(u),
    ], initialIndex: start);
  }

  @override
  Future<void> play() async {
    unawaited(_p.play().catchError((Object _) => _phase.add(PlayerPhase.failed)));
  }

  @override
  Future<void> pause() => _p.pause();
  @override
  Future<void> stop() => _p.stop();
  @override
  Future<void> seekToIndex(int i) => _p.seek(Duration.zero, index: i);
  @override
  Stream<int?> get index => _p.currentIndexStream;
  @override
  Stream<PlayerPhase> get phase => _phase.stream;

  @override
  Future<void> dispose() async {
    await _sub?.cancel();
    await _phase.close();
    await _p.dispose();
  }
}

final ayahPlayerFactoryProvider = Provider<AyahPlayer Function()>((_) => JustAudioAyahPlayer.new);

/// Where the recording of ayah [n] (1-6236) by [r] comes from: the internet, or a downloaded file.
final ayahUriResolverProvider = Provider<Uri Function(Reciter r, int n)>((ref) {
  final dir = ref.watch(quranAudioDirProvider).value;
  return (r, n) {
    if (dir != null) {
      final f = File('${dir.path}/${r.id}/$n.mp3');
      if (f.existsSync()) return Uri.file(f.path);
    }
    return r.ayahUrl(n);
  };
});

/// A short silence in the queue (Hifz pauses): `silence:<milliseconds>`.
Uri silenceUri(Duration d) => Uri(scheme: 'silence', path: '${d.inMilliseconds}');

/// What one queue entry plays.
class _Entry {
  const _Entry(this.surah, this.ayah, this.pos, {this.translation = false, this.silence = false, this.repeat = 1, this.round = 1});
  final int surah, ayah, repeat, round;

  /// Position of the ayah in the whole Quran (0-6235).
  final int pos;
  final bool translation, silence;
}

/// How to repeat while memorising (Hifz). The default plays everything once.
class RepeatPlan {
  const RepeatPlan({this.eachAyah = 1, this.rounds = 1, this.pause = Duration.zero});
  final int eachAyah, rounds;
  final Duration pause;
  bool get isPlain => eachAyah == 1 && rounds == 1;
}

/// What is being recited.
class QuranAudioState {
  const QuranAudioState({
    this.surah,
    this.ayah,
    this.firstAyah,
    this.lastAyah,
    this.phase = PlayerPhase.idle,
    this.translationTurn = false,
    this.error,
    this.repeat = 1,
    this.repeats = 1,
    this.round = 1,
    this.rounds = 1,
  });
  final int? surah, ayah;

  /// The ayahs being played (the rest of the surah, the day's ayahs, or a Hifz selection).
  final int? firstAyah, lastAyah;
  final PlayerPhase phase;

  /// True while the spoken translation of [ayah] (not the recitation) is playing.
  final bool translationTurn;
  final String? error;

  /// Hifz: which repetition of the ayah, and which round of the selection, is playing.
  final int repeat, repeats, round, rounds;

  bool get active => surah != null && phase != PlayerPhase.idle && phase != PlayerPhase.finished;
  bool get playing => phase == PlayerPhase.playing || phase == PlayerPhase.loading;

  QuranAudioState copy({int? surah, int? ayah, PlayerPhase? phase, bool? translationTurn, String? error, int? repeat, int? round, bool clearError = false}) => QuranAudioState(
    surah: surah ?? this.surah,
    ayah: ayah ?? this.ayah,
    firstAyah: firstAyah,
    lastAyah: lastAyah,
    phase: phase ?? this.phase,
    translationTurn: translationTurn ?? this.translationTurn,
    error: clearError ? null : (error ?? this.error),
    repeat: repeat ?? this.repeat,
    repeats: repeats,
    round: round ?? this.round,
    rounds: rounds,
  );
}

const _failed = 'Could not play the recitation. Check the internet connection and try again.';

/// Plays a surah (or a few ayahs) ayah by ayah with the chosen reciter, optionally followed by each ayah's spoken
/// translation, optionally repeating (Hifz); reports which ayah is playing so the reader can mark it and follow it.
class QuranAudio extends Notifier<QuranAudioState> {
  AyahPlayer? _player;
  final _subs = <StreamSubscription<Object?>>[];
  List<_Entry> _queue = const [];
  int _index = 0;

  /// The longest queue built (a selection of 10 ayahs x 10 repeats x 10 rounds with pauses stays below this).
  static const maxQueue = 4000;

  @override
  QuranAudioState build() {
    ref.onDispose(_release);
    return const QuranAudioState();
  }

  AyahPlayer _ensure() {
    final p = _player;
    if (p != null) return p;
    final n = ref.read(ayahPlayerFactoryProvider)();
    _player = n;
    _subs
      ..add(n.index.listen(_onIndex))
      ..add(n.phase.listen(_onPhase));
    return n;
  }

  void _onIndex(int? i) {
    if (i == null || state.surah == null || i >= _queue.length) return;
    _index = i;
    final e = _queue[i];
    state = state.copy(surah: e.surah, ayah: e.ayah, translationTurn: e.translation, repeat: e.repeat, round: e.round);
    _showControls();
  }

  void _onPhase(PlayerPhase p) {
    if (state.surah == null) return;
    state = state.copy(phase: p, error: p == PlayerPhase.failed ? _failed : null, clearError: p != PlayerPhase.failed);
    if (p == PlayerPhase.finished || p == PlayerPhase.failed) {
      unawaited(ref.read(mediaControlsProvider).hide());
    } else {
      _showControls();
    }
  }

  /// Recites [surah] from [ayah] to [to] (default: the end of the surah), repeating as [repeat] says.
  Future<void> playFrom(QuranData q, int surah, int ayah, {int? to, RepeatPlan repeat = const RepeatPlan()}) async {
    final last = to ?? q.surah(surah).ayahCount;
    final reciter = ref.read(reciterProvider);
    final voice = ref.read(spokenTranslationProvider).voice;
    final source = ref.read(ayahUriResolverProvider);
    final entries = <_Entry>[];
    final urls = <Uri>[];
    for (var round = 1; round <= repeat.rounds; round++) {
      for (var a = ayah; a <= last; a++) {
        final n = q.indexOf(surah, a) + 1;
        for (var r = 1; r <= repeat.eachAyah; r++) {
          entries.add(_Entry(surah, a, n - 1, repeat: r, round: round));
          urls.add(source(reciter, n));
          final lastOne = round == repeat.rounds && a == last && r == repeat.eachAyah && voice == null;
          if (repeat.pause > Duration.zero && !lastOne) {
            entries.add(_Entry(surah, a, n - 1, silence: true, repeat: r, round: round));
            urls.add(silenceUri(repeat.pause));
          }
        }
        if (voice != null) {
          entries.add(_Entry(surah, a, n - 1, translation: true, repeat: repeat.eachAyah, round: round));
          urls.add(source(voice, n));
        }
        if (urls.length > maxQueue) break;
      }
    }
    _rangeTo = null;
    _queue = entries;
    _index = 0;
    state = QuranAudioState(
      surah: surah,
      ayah: ayah,
      firstAyah: ayah,
      lastAyah: last,
      phase: PlayerPhase.loading,
      repeats: repeat.eachAyah,
      rounds: repeat.rounds,
    );
    final p = _ensure();
    try {
      await p.setQueue(urls);
      await p.play();
    } catch (_) {
      state = state.copy(phase: PlayerPhase.failed, error: _failed);
    }
  }

  /// The end (position in the whole Quran) of a range being played across surahs, e.g. a para.
  int? _rangeTo;

  /// Recites positions [from]..[to] of the whole Quran (e.g. a para), across surahs, each ayah once (followed by its
  /// spoken translation if one is chosen).
  Future<void> playRange(QuranData q, int from, int to) async {
    final reciter = ref.read(reciterProvider);
    final voice = ref.read(spokenTranslationProvider).voice;
    final source = ref.read(ayahUriResolverProvider);
    final entries = <_Entry>[];
    final urls = <Uri>[];
    for (var i = from; i <= to && urls.length < maxQueue; i++) {
      final (s, a) = q.refOf(i);
      entries.add(_Entry(s, a, i));
      urls.add(source(reciter, i + 1));
      if (voice != null) {
        entries.add(_Entry(s, a, i, translation: true));
        urls.add(source(voice, i + 1));
      }
    }
    if (entries.isEmpty) return;
    _rangeTo = to;
    _queue = entries;
    _index = 0;
    final (s, a) = q.refOf(from);
    state = QuranAudioState(surah: s, ayah: a, phase: PlayerPhase.loading);
    final p = _ensure();
    try {
      await p.setQueue(urls);
      await p.play();
    } catch (_) {
      state = state.copy(phase: PlayerPhase.failed, error: _failed);
    }
  }

  /// Position (in the whole Quran) of the ayah being recited, or null.
  int? get position => _queue.isEmpty || _index >= _queue.length ? null : _queue[_index].pos;

  Future<void> pause() async => _player?.pause();
  Future<void> resume() async => _player?.play();

  Future<void> toggle() async => state.playing ? pause() : resume();

  /// The first recitation of the next ayah (in this round).
  Future<void> next() async {
    final cur = _queue.isEmpty ? null : _queue[_index];
    if (cur == null) return;
    final j = _queue.indexWhere((e) => e.round == cur.round && e.pos == cur.pos + 1 && !e.silence && !e.translation, _index);
    if (j >= 0) await _player?.seekToIndex(j);
  }

  /// The first recitation of the previous ayah (in this round).
  Future<void> previous() async {
    final cur = _queue.isEmpty ? null : _queue[_index];
    if (cur == null) return;
    final j = _queue.indexWhere((e) => e.round == cur.round && e.pos == cur.pos - 1 && !e.silence && !e.translation);
    if (j >= 0) await _player?.seekToIndex(j);
  }

  Future<void> stop() async {
    await _player?.stop();
    _queue = const [];
    state = const QuranAudioState();
    await ref.read(mediaControlsProvider).hide();
  }

  /// Changing the reciter or the spoken translation restarts at the same ayah (plain listening, to the same end).
  Future<void> restart(QuranData q) async {
    final s = state.surah, a = state.ayah, last = state.lastAyah;
    if (s == null || a == null || !state.active) return;
    final to = _rangeTo;
    if (to != null) return playRange(q, q.indexOf(s, a), to);
    await playFrom(q, s, a, to: last);
  }

  void _showControls() {
    final s = state.surah, a = state.ayah;
    if (s == null || a == null) return;
    final r = ref.read(reciterProvider);
    unawaited(
      ref.read(mediaControlsProvider).show(
        title: 'Quran $s:$a${state.repeats > 1 ? ' (${state.repeat}/${state.repeats})' : ''}',
        subtitle: r.name,
        playing: state.playing,
        onPlay: resume,
        onPause: pause,
        onStop: stop,
        onNext: next,
        onPrevious: previous,
      ),
    );
  }

  void _release() {
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _subs.clear();
    final p = _player;
    _player = null;
    if (p != null) unawaited(p.dispose());
  }
}

final quranAudioProvider = NotifierProvider<QuranAudio, QuranAudioState>(QuranAudio.new);
