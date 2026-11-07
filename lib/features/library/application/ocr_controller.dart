import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/library_repository.dart';
import '../data/ocr.dart';

/// The phone's text recogniser (null on desktop). Overridden in tests with a fake.
final pageRecognizerProvider = Provider<PageRecognizer?>((ref) {
  final r = createPageRecognizer();
  if (r != null) ref.onDispose(r.close);
  return r;
});

/// Tells real text from scanned pictures. Overridden in tests.
final textProbeProvider = Provider<TextProbe>((ref) => PdfrxTextProbe());

class OcrProgress {
  const OcrProgress({this.running = false, this.done = 0, this.total = 0});
  final bool running;
  final int done, total;
}

/// Reads the pages of one scanned book, one at a time, saving each result so a stop (or a crash) loses nothing.
class OcrRunner {
  OcrRunner(this.repo, this.recognizer, this.probe);
  final LibraryRepository repo;
  final PageRecognizer? recognizer;
  final TextProbe probe;
  final progress = ValueNotifier<OcrProgress>(const OcrProgress());
  bool _cancel = false;
  bool _disposed = false;

  bool get supported => recognizer != null;

  /// First time a book is opened: does it have real text or is it a scan? Returns the state.
  Future<String> probeBook(String bookId, String current, File file) async {
    if (current != 'unknown') return current;
    final has = await probe.hasText(file);
    if (has == null) return current;
    final s = has ? 'text' : 'scanned';
    await repo.setTextState(bookId, s);
    return s;
  }

  /// Reads every page that has not been read yet. Safe to call again after a stop: it carries on.
  Future<void> run(String bookId, File file, int pageCount) async {
    final r = recognizer;
    if (r == null || progress.value.running || pageCount < 1) return;
    _cancel = false;
    final have = await repo.recognisedPages(bookId);
    var done = have.length;
    _set(OcrProgress(running: true, done: done, total: pageCount));
    var finished = true;
    for (var p = 1; p <= pageCount; p++) {
      if (have.contains(p)) continue;
      if (_cancel || _disposed) {
        finished = false;
        break;
      }
      final page = await r.recognize(file, p);
      // a page that can't be read is stored empty so it isn't retried over and over
      await repo.savePageText(bookId, p, page ?? const RecognizedPage([]));
      done++;
      _set(OcrProgress(running: true, done: done, total: pageCount));
    }
    if (finished) await repo.setTextState(bookId, 'ocr');
    _set(OcrProgress(done: done, total: pageCount));
  }

  void stop() => _cancel = true;

  void _set(OcrProgress p) {
    if (!_disposed) progress.value = p;
  }

  void dispose() {
    _cancel = true;
    _disposed = true;
    progress.dispose();
  }
}
