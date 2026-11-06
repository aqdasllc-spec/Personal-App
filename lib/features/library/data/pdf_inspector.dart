import 'dart:io';

import 'package:file_picker/file_picker.dart';

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../application/library_controller.dart';
import '../domain_highlights.dart';
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
  late final _searcher = PdfTextSearcher(_controller);
  String _query = '';

  void _publish() {
    final m = _searcher.matches.length;
    widget.control.search.value = ReaderSearch(
      query: _query,
      count: m,
      index: _searcher.currentIndex,
      searching: _searcher.isSearching,
    );
  }

  @override
  void initState() {
    super.initState();
    final c = widget.control;
    c.goTo = (page) {
      if (_controller.isReady) _controller.goToPage(pageNumber: page);
    };
    _searcher.addListener(_publish);
    c.highlights.addListener(
      _controller.invalidate,
    ); // repaint when highlights change
    c.startSearch = (q) {
      _query = q.trim();
      if (_query.isEmpty) {
        _searcher.resetTextSearch();
        c.search.value = const ReaderSearch();
      } else {
        c.search.value = ReaderSearch(query: _query, searching: true);
        _searcher.startTextSearch(
          _query,
          caseInsensitive: true,
          searchImmediately: true,
        );
      }
    };
    // wrap around at both ends
    c.nextMatch = () async {
      if (_searcher.matches.isEmpty) return;
      if (await _searcher.goToNextMatch() == -1) {
        await _searcher.goToMatchOfIndex(0);
      }
    };
    c.prevMatch = () async {
      if (_searcher.matches.isEmpty) return;
      if (await _searcher.goToPrevMatch() == -1) {
        await _searcher.goToMatchOfIndex(_searcher.matches.length - 1);
      }
    };
    c.stopSearch = () {
      _query = '';
      _searcher.resetTextSearch();
      c.search.value = const ReaderSearch();
    };
  }

  @override
  void dispose() {
    final c = widget.control;
    c.highlights.removeListener(_controller.invalidate);
    c.goTo = c.startSearch = c.nextMatch = c.prevMatch = c.stopSearch = null;
    _searcher.dispose();
    super.dispose();
  }

  void _paintHighlights(ui.Canvas canvas, Rect pageRect, PdfPage page) {
    for (final h in widget.control.highlights.value) {
      if (h.page != page.pageNumber) continue;
      final paint = Paint()
        ..color = highlightColor(h.color).withValues(alpha: 0.45)
        ..blendMode = BlendMode.multiply;
      for (final r in decodeRects(h.rects)) {
        final rect = PdfRect(r[0], r[1], r[2], r[3])
            .toRect(page: page, scaledPageSize: pageRect.size)
            .translate(pageRect.left, pageRect.top);
        canvas.drawRect(rect, paint);
      }
    }
  }

  /// Adds "Highlight" to the menu that appears when text is selected.
  void _addHighlightItem(
    PdfViewerContextMenuBuilderParams params,
    List<ContextMenuButtonItem> items,
  ) {
    items.insert(
      0,
      ContextMenuButtonItem(
        label: 'Highlight',
        onPressed: () async {
          final ranges = await params.textSelectionDelegate
              .getSelectedTextRanges();
          params.dismissContextMenu();
          for (final r in ranges) {
            final chars = r.pageText.charRects
                .skip(r.start)
                .take(r.end - r.start)
                .map((c) => [c.left, c.top, c.right, c.bottom]);
            final rects = lineRectsOf(chars);
            if (rects.isEmpty) continue;
            await widget.control.onHighlight?.call(
              HighlightDraft(
                page: r.pageNumber,
                rects: rects,
                text: r.text.trim(),
              ),
            );
          }
          await params.textSelectionDelegate.clearTextSelection();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PdfViewer.file(
    widget.file.path,
    controller: _controller,
    initialPageNumber: widget.initialPage < 1 ? 1 : widget.initialPage,
    params: PdfViewerParams(
      pagePaintCallbacks: [
        _paintHighlights,
        _searcher.pageTextMatchPaintCallback,
      ],
      customizeContextMenuItems: _addHighlightItem,
      onPageChanged: (n) {
        if (n != null) widget.onPage(n);
      },
    ),
  );
}
