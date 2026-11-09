import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart' as ja;

import '../../library/application/read_aloud.dart' show mediaControlsProvider;
import '../data/quran_data.dart';
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
    await _p.setAudioSources([for (final u in urls) ja.AudioSource.uri(u)], initialIndex: start);
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

/// What is being recited.
class QuranAudioState {
  const QuranAudioState({this.surah, this.ayah, this.lastAyah, this.phase = PlayerPhase.idle, this.translationTurn = false, this.error});
  final int? surah, ayah;

  /// Where playback stops (the end of the surah, or of the day's ayahs).
  final int? lastAyah;
  final PlayerPhase phase;

  /// True while the spoken translation of [ayah] (not the recitation) is playing.
  final bool translationTurn;
  final String? error;

  bool get active => surah != null && phase != PlayerPhase.idle && phase != PlayerPhase.finished;
  bool get playing => phase == PlayerPhase.playing || phase == PlayerPhase.loading;
}

/// Plays a surah (or a few ayahs) ayah by ayah with the chosen reciter, optionally followed by each ayah's spoken
/// translation; reports which ayah is playing so the reader can mark it and scroll to it.
class QuranAudio extends Notifier<QuranAudioState> {
  AyahPlayer? _player;
  final _subs = <StreamSubscription<Object?>>[];
  int _from = 1, _per = 1;

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
    if (i == null || state.surah == null) return;
    state = QuranAudioState(
      surah: state.surah,
      ayah: _from + i ~/ _per,
      lastAyah: state.lastAyah,
      phase: state.phase,
      translationTurn: _per > 1 && i % _per == 1,
    );
    _showControls();
  }

  void _onPhase(PlayerPhase p) {
    if (state.surah == null) return;
    state = QuranAudioState(
      surah: state.surah,
      ayah: state.ayah,
      lastAyah: state.lastAyah,
      phase: p,
      translationTurn: state.translationTurn,
      error: p == PlayerPhase.failed ? 'Could not play the recitation. Check the internet connection and try again.' : null,
    );
    if (p == PlayerPhase.finished || p == PlayerPhase.failed) {
      unawaited(ref.read(mediaControlsProvider).hide());
    } else {
      _showControls();
    }
  }

  /// Recites [surah] from [ayah] to [to] (default: the end of the surah).
  Future<void> playFrom(QuranData q, int surah, int ayah, {int? to}) async {
    final last = to ?? q.surah(surah).ayahCount;
    final reciter = ref.read(reciterProvider);
    final voice = ref.read(spokenTranslationProvider).voice;
    _from = ayah;
    _per = voice == null ? 1 : 2;
    final urls = <Uri>[
      for (var a = ayah; a <= last; a++) ...[
        reciter.ayahUrl(q.indexOf(surah, a) + 1),
        if (voice != null) voice.ayahUrl(q.indexOf(surah, a) + 1),
      ],
    ];
    state = QuranAudioState(surah: surah, ayah: ayah, lastAyah: last, phase: PlayerPhase.loading);
    final p = _ensure();
    try {
      await p.setQueue(urls);
      await p.play();
    } catch (_) {
      state = QuranAudioState(surah: surah, ayah: ayah, lastAyah: last, phase: PlayerPhase.failed, error: 'Could not play the recitation. Check the internet connection and try again.');
    }
  }

  Future<void> pause() async => _player?.pause();
  Future<void> resume() async => _player?.play();

  Future<void> toggle() async => state.playing ? pause() : resume();

  Future<void> next() async {
    final a = state.ayah, last = state.lastAyah;
    if (a == null || last == null || a >= last) return;
    await _player?.seekToIndex((a + 1 - _from) * _per);
  }

  Future<void> previous() async {
    final a = state.ayah;
    if (a == null || a <= _from) return;
    await _player?.seekToIndex((a - 1 - _from) * _per);
  }

  Future<void> stop() async {
    await _player?.stop();
    state = const QuranAudioState();
    await ref.read(mediaControlsProvider).hide();
  }

  /// Changing the reciter or the spoken translation restarts at the same ayah.
  Future<void> restart(QuranData q) async {
    final s = state.surah, a = state.ayah, last = state.lastAyah;
    if (s == null || a == null || !state.active) return;
    await playFrom(q, s, a, to: last);
  }

  void _showControls() {
    final s = state.surah, a = state.ayah;
    if (s == null || a == null) return;
    final r = ref.read(reciterProvider);
    unawaited(
      ref.read(mediaControlsProvider).show(
        title: 'Quran $s:$a',
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
