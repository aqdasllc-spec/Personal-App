import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/app_database.dart';
import '../../backup/backup_controller.dart';
import '../data/highlights_export.dart' show safeFileName;
import '../data/ink_export.dart';
import '../domain_ink.dart';
import 'export_notes.dart' show shareFileProvider;
import 'library_controller.dart';

/// Draws PDF pages as pictures for the "with my drawings" export. Overridden in tests.
final pageImagerProvider = Provider<PageImager>((ref) {
  final i = PdfrxPageImager();
  ref.onDispose(i.close);
  return i;
});

/// Whole-book export draws every page as a picture, so it is only offered for books up to this many pages.
const maxWholeBookExportPages = 60;

enum InkExportScope { thisPage, drawnPages, wholeBook }

/// Pages that have drawings, in order.
List<int> drawnPages(Map<int, List<Stroke>> ink) =>
    [for (final e in ink.entries) if (e.value.isNotEmpty) e.key]..sort();

/// Builds a PDF of the chosen pages with the pen drawings on top and shares it. Returns a message for the user.
Future<String> exportBookWithInk(
  WidgetRef ref,
  BookRow book, {
  required InkExportScope scope,
  required int currentPage,
  void Function(int done, int total)? onProgress,
}) async {
  final repo = ref.read(libraryRepositoryProvider);
  final rows = await repo.watchInk(book.id).first;
  final ink = {for (final r in rows) r.page: decodeStrokes(r.strokes)};
  final pages = switch (scope) {
    InkExportScope.thisPage => [currentPage],
    InkExportScope.drawnPages => drawnPages(ink),
    InkExportScope.wholeBook => [for (var p = 1; p <= book.pageCount; p++) p],
  };
  if (pages.isEmpty) return 'No drawings yet: use Draw to write on a page first.';
  final bytes = await buildInkPdf(
    source: repo.fileOf(book),
    pages: pages,
    ink: ink,
    imager: ref.read(pageImagerProvider),
    onProgress: onProgress,
  );
  if (bytes == null) return 'Could not draw the pages of this PDF.';
  final dir = await ref.read(backupTempDirProvider)();
  await dir.create(recursive: true);
  final file = File('${dir.path}/${safeFileName('${book.title} with drawings', suffix: '.pdf')}');
  await file.writeAsBytes(bytes, flush: true);
  final shared = await ref.read(shareFileProvider)(file, '${book.title} - with my drawings');
  return shared ? 'PDF ready to share (${pages.length} ${pages.length == 1 ? 'page' : 'pages'}).' : 'Sharing cancelled.';
}
