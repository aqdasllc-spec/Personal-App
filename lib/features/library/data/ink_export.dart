import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart' as rx;

import '../domain_ink.dart';

/// Draws a page of a PDF as a picture (PNG bytes). An interface so tests need no PDF engine.
abstract class PageImager {
  Future<Uint8List?> png(File pdf, int page, {int width = 1100});
  Future<void> close();
}

class PdfrxPageImager implements PageImager {
  rx.PdfDocument? _doc;
  String? _path;

  @override
  Future<Uint8List?> png(File pdf, int page, {int width = 1100}) async {
    ui.Image? image;
    try {
      if (_path != pdf.path || _doc == null) {
        await _doc?.dispose();
        await rx.pdfrxFlutterInitialize();
        _doc = await rx.PdfDocument.openFile(pdf.path);
        _path = pdf.path;
      }
      final d = _doc!;
      if (page < 1 || page > d.pages.length) return null;
      final p = d.pages[page - 1];
      final h = (width * p.height / p.width).round().clamp(1, width * 3);
      image = await p.renderForDisplay(fullWidth: width.toDouble(), fullHeight: h.toDouble());
      final data = await image?.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List();
    } catch (_) {
      return null;
    } finally {
      image?.dispose();
    }
  }

  @override
  Future<void> close() async {
    await _doc?.dispose();
    _doc = null;
  }
}

/// Width and height from a PNG header (null when it is not a PNG).
({int w, int h})? pngSize(Uint8List b) {
  if (b.length < 24 || b[0] != 0x89 || b[1] != 0x50 || b[2] != 0x4E || b[3] != 0x47) return null;
  int u32(int o) => (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];
  return (w: u32(16), h: u32(20));
}

/// Builds a PDF with the given [pages] of [source] as pictures, the pen drawings on top as crisp lines.
/// Returns the bytes, or null when no page could be drawn. [onProgress] gets (done, total).
Future<Uint8List?> buildInkPdf({
  required File source,
  required List<int> pages,
  required Map<int, List<Stroke>> ink,
  required PageImager imager,
  void Function(int done, int total)? onProgress,
}) async {
  final doc = pw.Document();
  var made = 0;
  for (var i = 0; i < pages.length; i++) {
    final page = pages[i];
    final bytes = await imager.png(source, page);
    onProgress?.call(i + 1, pages.length);
    final size = bytes == null ? null : pngSize(bytes);
    if (bytes == null || size == null) continue;
    const width = 595.0; // A4 width in PDF points; the height follows the page's own shape
    final height = width * size.h / size.w;
    final strokes = ink[page] ?? const <Stroke>[];
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(width, height),
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Stack(
          children: [
            pw.Positioned.fill(child: pw.Image(pw.MemoryImage(bytes), fit: pw.BoxFit.fill)),
            if (strokes.isNotEmpty)
              pw.Positioned.fill(
                child: pw.CustomPaint(
                  painter: (canvas, area) {
                    for (final s in strokes) {
                      _drawStroke(canvas, area, s);
                    }
                  },
                ),
              ),
          ],
        ),
      ),
    );
    made++;
  }
  if (made == 0) return null;
  return doc.save();
}

void _drawStroke(PdfGraphics g, PdfPoint area, Stroke s) {
  final c = penColors[s.color].$2;
  g.saveContext();
  if (s.highlighter) g.setGraphicState(PdfGraphicState(strokeOpacity: 0.4));
  g
    ..setStrokeColor(PdfColor.fromInt(c))
    ..setLineCap(s.highlighter ? PdfLineCap.square : PdfLineCap.round)
    ..setLineJoin(PdfLineJoin.round)
    ..setLineWidth((s.width * area.x).clamp(0.5, 20.0));
  final p = s.points;
  double x(int i) => p[i] * area.x;
  double y(int i) => (1 - p[i + 1]) * area.y; // PDF counts up from the bottom
  if (p.length == 2) {
    // a dot: a zero-length line with a round cap
    g
      ..moveTo(x(0), y(0))
      ..lineTo(x(0) + 0.01, y(0))
      ..strokePath()
      ..restoreContext();
    return;
  }
  g.moveTo(x(0), y(0));
  for (var i = 2; i < p.length; i += 2) {
    g.lineTo(x(i), y(i));
  }
  g
    ..strokePath()
    ..restoreContext();
}
