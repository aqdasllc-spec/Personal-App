import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:pdfrx/pdfrx.dart';

/// One recognised line of text and where it sits on the page (fractions 0..1 of the page image).
class OcrLine {
  const OcrLine(this.text, this.left, this.top, this.right, this.bottom);
  final String text;
  final double left, top, right, bottom;
}

class RecognizedPage {
  const RecognizedPage(this.lines);
  final List<OcrLine> lines;
  String get text => lines.map((l) => l.text).join('\n');
}

/// Reads the text off a picture of a page (scanned documents). An interface so tests need no native engine.
abstract class PageRecognizer {
  /// Recognises page [page] (1-based) of [pdf]. Null = this page could not be read.
  Future<RecognizedPage?> recognize(File pdf, int page);

  /// Frees native resources.
  Future<void> close();
}

/// Decides whether a PDF has real, selectable text.
abstract class TextProbe {
  /// true = has text, false = looks scanned (pages are pictures), null = could not tell.
  Future<bool?> hasText(File pdf);
}

/// Real probe: asks PDFium for the text of a few pages spread over the document.
class PdfrxTextProbe implements TextProbe {
  @override
  Future<bool?> hasText(File pdf) async {
    PdfDocument? doc;
    try {
      await pdfrxFlutterInitialize();
      doc = await PdfDocument.openFile(pdf.path);
      final n = doc.pages.length;
      if (n == 0) return null;
      final picks = <int>{
        1,
        if (n > 1) n,
        if (n > 2) (n / 2).ceil(),
        if (n > 4) (n / 4).ceil(),
        if (n > 4) (3 * n / 4).ceil(),
      };
      var chars = 0;
      for (final p in picks) {
        final text = await doc.pages[p - 1].loadText();
        chars += text?.fullText.replaceAll(RegExp(r'\s'), '').length ?? 0;
        if (chars >= 40) return true;
      }
      return false;
    } catch (_) {
      return null;
    } finally {
      await doc?.dispose();
    }
  }
}

/// Real recogniser: renders the page with PDFium and reads it with Google ML Kit (on the phone, offline,
/// Latin script: English and most European languages; printed text works best, handwriting often does not).
class MlKitPageRecognizer implements PageRecognizer {
  MlKitPageRecognizer({Directory? scratch, this.width = 1600})
    : _scratch = scratch ?? Directory.systemTemp;
  final Directory _scratch;
  final int width;
  final _recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  PdfDocument? _doc;
  String? _docPath;

  Future<PdfDocument> _open(File pdf) async {
    if (_docPath == pdf.path && _doc != null) return _doc!;
    await _doc?.dispose();
    await pdfrxFlutterInitialize();
    _doc = await PdfDocument.openFile(pdf.path);
    _docPath = pdf.path;
    return _doc!;
  }

  @override
  Future<RecognizedPage?> recognize(File pdf, int page) async {
    ui.Image? image;
    File? tmp;
    try {
      final doc = await _open(pdf);
      if (page < 1 || page > doc.pages.length) return null;
      final p = doc.pages[page - 1];
      final w = width,
          h = (width * p.height / p.width).round().clamp(1, width * 3);
      image = await p.renderForDisplay(
        fullWidth: w.toDouble(),
        fullHeight: h.toDouble(),
      );
      if (image == null) return null;
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) return null;
      tmp = File(
        '${_scratch.path}/folio-ocr-${DateTime.now().microsecondsSinceEpoch}.png',
      );
      await tmp.writeAsBytes(png.buffer.asUint8List(), flush: true);
      final result = await _recognizer.processImage(
        InputImage.fromFilePath(tmp.path),
      );
      final iw = image.width.toDouble(), ih = image.height.toDouble();
      final lines = <OcrLine>[];
      for (final b in result.blocks) {
        for (final l in b.lines) {
          final r = l.boundingBox;
          if (l.text.trim().isEmpty) continue;
          lines.add(
            OcrLine(
              l.text.trim(),
              (r.left / iw).clamp(0.0, 1.0),
              (r.top / ih).clamp(0.0, 1.0),
              (r.right / iw).clamp(0.0, 1.0),
              (r.bottom / ih).clamp(0.0, 1.0),
            ),
          );
        }
      }
      // reading order: top to bottom, then left to right
      lines.sort(
        (a, b) => (a.top - b.top).abs() < 0.008
            ? a.left.compareTo(b.left)
            : a.top.compareTo(b.top),
      );
      return RecognizedPage(lines);
    } catch (_) {
      return null;
    } finally {
      image?.dispose();
      try {
        if (tmp != null && await tmp.exists()) await tmp.delete();
      } catch (_) {}
    }
  }

  @override
  Future<void> close() async {
    await _doc?.dispose();
    _doc = null;
    await _recognizer.close();
  }
}

/// The phone's text recogniser, or null where none exists (desktop builds).
PageRecognizer? createPageRecognizer() {
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
      return MlKitPageRecognizer();
    default:
      return null;
  }
}
