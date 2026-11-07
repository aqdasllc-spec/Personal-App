import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/speech.dart';
import '../domain_speech.dart';

/// The phone's voice. Overridden in tests.
final speechEngineProvider = Provider<SpeechEngine>((ref) {
  final e = FlutterTtsEngine();
  ref.onDispose(e.dispose);
  return e;
});

/// Where page text comes from for books that are not scans. Overridden in tests.
final pageTextReaderProvider = Provider<PageTextReader>((ref) => PdfrxPageTextReader());

class AloudState {
  const AloudState({this.active = false, this.playing = false, this.page = 1, this.rate = 1.0, this.message});
  final bool active, playing;
  final int page;
  final double rate;

  /// Why reading stopped (no text, reached the end...), shown in the bar.
  final String? message;

  AloudState copyWith({bool? active, bool? playing, int? page, double? rate, String? message, bool clearMessage = false}) => AloudState(
    active: active ?? this.active,
    playing: playing ?? this.playing,
    page: page ?? this.page,
    rate: rate ?? this.rate,
    message: clearMessage ? null : (message ?? this.message),
  );
}

/// Reads a book aloud page after page, turning the page as it goes.
class ReadAloud {
  ReadAloud({required this.engine, required this.textOf, required this.goTo, required this.pageCount});
  final SpeechEngine engine;

  /// The text of a page (1-based); null or blank = nothing to read there.
  final Future<String?> Function(int page) textOf;
  final void Function(int page) goTo;
  final int Function() pageCount;
  final state = ValueNotifier<AloudState>(const AloudState());
  int _token = 0;
  bool _disposed = false;

  void _set(AloudState s) {
    if (!_disposed) state.value = s;
  }

  /// Starts (or restarts) reading at [page].
  Future<void> start(int page) async {
    final token = ++_token;
    await engine.stop();
    if (token != _token) return;
    _set(state.value.copyWith(active: true, playing: true, page: page, clearMessage: true));
    var blanks = 0;
    var p = page;
    while (p <= pageCount() && token == _token) {
      final text = await textOf(p);
      if (token != _token) return;
      final pieces = chunkText(text ?? '');
      if (pieces.isEmpty) {
        // pages without text (pictures, blank): skip a few, then give up
        if (++blanks >= 3) {
          _set(state.value.copyWith(
            playing: false,
            message: blanks == 3 && p - page < 3
                ? 'No text to read here. For a scan, choose "Make searchable" first.'
                : 'No more text to read.',
          ));
          return;
        }
        p++;
        continue;
      }
      blanks = 0;
      _set(state.value.copyWith(page: p));
      goTo(p);
      for (final piece in pieces) {
        await engine.speak(piece);
        if (token != _token) return;
      }
      p++;
    }
    if (token == _token) _set(state.value.copyWith(playing: false, message: 'Finished the book.'));
  }

  Future<void> pause() async {
    _token++;
    await engine.stop();
    _set(state.value.copyWith(playing: false));
  }

  Future<void> resume() => start(state.value.page);

  /// Closes the voice bar.
  Future<void> stop() async {
    _token++;
    await engine.stop();
    _set(const AloudState().copyWith(rate: state.value.rate));
  }

  Future<void> setRate(double r) async {
    _set(state.value.copyWith(rate: r));
    await engine.setRate(r);
    // a voice keeps the speed it started with: carry on from this page at the new one
    if (state.value.playing) await start(state.value.page);
  }

  /// The reader moved to [page] (by the user or by us): when the user jumped elsewhere while reading, follow them.
  void pageChanged(int page) {
    final s = state.value;
    if (s.active && s.playing && page != s.page) start(page);
  }

  void dispose() {
    _token++;
    _disposed = true;
    engine.stop();
    state.dispose();
  }
}
