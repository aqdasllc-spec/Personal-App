import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:pdfrx/pdfrx.dart';

/// Renders the first page of a PDF as PNG bytes (used for the book preview).
/// An interface so tests need no native PDF engine.
abstract class CoverRenderer {
  Future<Uint8List?> renderFirstPage(File pdf, {int width = 420});
}

class PdfrxCoverRenderer implements CoverRenderer {
  @override
  Future<Uint8List?> renderFirstPage(File pdf, {int width = 420}) async {
    PdfDocument? doc;
    ui.Image? image;
    try {
      await pdfrxFlutterInitialize();
      doc = await PdfDocument.openFile(pdf.path);
      if (doc.pages.isEmpty) return null;
      final page = doc.pages.first;
      final height = (width * page.height / page.width).round().clamp(
        1,
        width * 3,
      );
      image = await page.renderForDisplay(
        fullWidth: width.toDouble(),
        fullHeight: height.toDouble(),
      );
      if (image == null) return null;
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List();
    } catch (_) {
      return null;
    } finally {
      image?.dispose();
      await doc?.dispose();
    }
  }
}
