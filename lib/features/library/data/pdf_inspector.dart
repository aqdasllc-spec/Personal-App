import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../application/library_controller.dart';
import 'library_repository.dart';

/// Real inspector backed by PDFium (via pdfrx).
class PdfrxInspector implements PdfInspector {
  @override
  Future<PdfInfo?> inspect(String path) async {
    PdfDocument? doc;
    try {
      await pdfrxFlutterInitialize();
      doc = await PdfDocument.openFile(path);
      final n = doc.pages.length;
      return n <= 0 ? null : PdfInfo(pageCount: n);
    } catch (_) {
      return null;
    } finally {
      await doc?.dispose();
    }
  }
}

Future<List<String>> pickPdfPaths() async {
  final files = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['pdf'],
  );
  return [
    for (final f in files)
      if (f.path != null) f.path!,
  ];
}

Widget buildPdfView(
  BuildContext context,
  File file,
  int initialPage,
  void Function(int page) onPage,
  ReaderControl control,
) => _PdfView(
  file: file,
  initialPage: initialPage,
  onPage: onPage,
  control: control,
);

class _PdfView extends StatefulWidget {
  const _PdfView({
    required this.file,
    required this.initialPage,
    required this.onPage,
    required this.control,
  });
  final File file;
  final int initialPage;
  final void Function(int page) onPage;
  final ReaderControl control;
  @override
  State<_PdfView> createState() => _PdfViewState();
}

class _PdfViewState extends State<_PdfView> {
  final _controller = PdfViewerController();

  @override
  void initState() {
    super.initState();
    widget.control.goTo = (page) {
      if (_controller.isReady) _controller.goToPage(pageNumber: page);
    };
  }

  @override
  void dispose() {
    widget.control.goTo = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PdfViewer.file(
    widget.file.path,
    controller: _controller,
    initialPageNumber: widget.initialPage < 1 ? 1 : widget.initialPage,
    params: PdfViewerParams(
      onPageChanged: (n) {
        if (n != null) widget.onPage(n);
      },
    ),
  );
}
