import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

/// A chapter (or section) in a PDF's own table of contents.
class PdfChapter {
  const PdfChapter(this.title, this.page, this.depth);
  final String title;

  /// 1-based page number.
  final int page;

  /// 0 = a chapter, 1 = a section of it, ...
  final int depth;
}

/// Flattens the PDF's outline tree into a list in reading order (entries without a page are left out).
List<PdfChapter> flattenOutline(List<PdfOutlineNode> nodes, [int depth = 0]) => [
  for (final n in nodes) ...[
    if (n.dest != null && n.title.trim().isNotEmpty) PdfChapter(n.title.trim(), n.dest!.pageNumber, depth),
    ...flattenOutline(n.children, depth + 1),
  ],
];

/// Reads the table of contents of the PDF at a path. A function so tests need no PDF engine.
final pdfOutlineReaderProvider = Provider<Future<List<PdfChapter>> Function(String path)>((_) => (path) async {
  final doc = await PdfDocument.openFile(path);
  try {
    return flattenOutline(await doc.loadOutline());
  } finally {
    await doc.dispose();
  }
});

/// The chapters of the PDF at [path] (empty when it has none, or cannot be read).
final pdfChaptersProvider = FutureProvider.family<List<PdfChapter>, String>((ref, path) async {
  try {
    return await ref.watch(pdfOutlineReaderProvider)(path);
  } catch (_) {
    return const [];
  }
});
