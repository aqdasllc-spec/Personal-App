import 'dart:io';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:pdfrx/pdfrx.dart';

/// One voice the phone can speak with.
class VoiceInfo {
  const VoiceInfo(this.name, this.locale);
  final String name, locale;

  Map<String, String> toJson() => {'name': name, 'locale': locale};
  static VoiceInfo? fromJson(Object? j) {
    if (j is Map && j['name'] is String && j['locale'] is String && (j['name'] as String).isNotEmpty) {
      return VoiceInfo(j['name'] as String, j['locale'] as String);
    }
    return null;
  }

  @override
  bool operator ==(Object other) => other is VoiceInfo && other.name == name && other.locale == locale;
  @override
  int get hashCode => Object.hash(name, locale);
}

/// Speaks text out loud. An interface so tests need no phone voice.
abstract class SpeechEngine {
  /// Speaks [text]; the future completes when it has been spoken or [stop] was called.
  Future<void> speak(String text);
  Future<void> stop();

  /// 1.0 = normal speed.
  Future<void> setRate(double factor);
  /// The voices installed on the phone (may be empty).
  Future<List<VoiceInfo>> voices();

  /// Speaks with [voice] from now on; null = the phone's own default.
  Future<void> setVoice(VoiceInfo? voice);
  Future<void> dispose();
}

class FlutterTtsEngine implements SpeechEngine {
  FlutterTts _tts = FlutterTts();
  bool _ready = false;
  double _rate = 1.0;

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
  Future<List<VoiceInfo>> voices() async {
    try {
      final raw = await _tts.getVoices as List?;
      final out = <VoiceInfo>[
        for (final v in raw ?? const []) ?VoiceInfo.fromJson(v),
      ]..sort((a, b) => a.locale != b.locale ? a.locale.compareTo(b.locale) : a.name.compareTo(b.name));
      return out;
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> setVoice(VoiceInfo? voice) async {
    try {
      if (voice == null) {
        // there is no "back to default" call: start with a fresh engine
        await _tts.stop();
        _tts = FlutterTts();
        _ready = false;
        await setRate(_rate);
        return;
      }
      await _init();
      await _tts.setVoice(voice.toJson());
    } catch (_) {}
  }

  @override
  Future<void> setRate(double factor) async {
    _rate = factor;
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
