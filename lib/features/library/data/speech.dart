import 'dart:io';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:pdfrx/pdfrx.dart';

/// Speaks text out loud. An interface so tests need no phone voice.
abstract class SpeechEngine {
  /// Speaks [text]; the future completes when it has been spoken or [stop] was called.
  Future<void> speak(String text);
  Future<void> stop();

  /// 1.0 = normal speed.
  Future<void> setRate(double factor);
  Future<void> dispose();
}

class FlutterTtsEngine implements SpeechEngine {
  final _tts = FlutterTts();
  bool _ready = false;

  Future<void> _init() async {
    if (_ready) return;
    _ready = true;
    await _tts.awaitSpeakCompletion(true);
  }

  @override
  Future<void> speak(String text) async {
    await _init();
    await _tts.speak(text);
  }

  @override
  Future<void> stop() async {
    await _tts.stop();
  }

  @override
  Future<void> setRate(double factor) async {
    await _init();
    // the phone's scale: 0.5 is normal speed
    await _tts.setSpeechRate((0.5 * factor).clamp(0.1, 1.0));
  }

  @override
  Future<void> dispose() async {
    await _tts.stop();
  }
}

/// The text of a PDF page as the PDF itself holds it (null = none / could not read).
abstract class PageTextReader {
  Future<String?> textOf(File pdf, int page);
}

class PdfrxPageTextReader implements PageTextReader {
  PdfDocument? _doc;
  String? _path;

  @override
  Future<String?> textOf(File pdf, int page) async {
    try {
      if (_path != pdf.path || _doc == null) {
        await _doc?.dispose();
        await pdfrxFlutterInitialize();
        _doc = await PdfDocument.openFile(pdf.path);
        _path = pdf.path;
      }
      final d = _doc!;
      if (page < 1 || page > d.pages.length) return null;
      final t = await d.pages[page - 1].loadText();
      return t?.fullText;
    } catch (_) {
      return null;
    }
  }
}
