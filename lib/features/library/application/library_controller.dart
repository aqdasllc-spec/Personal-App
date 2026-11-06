import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../app/providers.dart';
import '../../../data/local/app_database.dart';
import '../data/library_repository.dart';
import '../data/pdf_inspector.dart';

/// Where PDFs are stored. Overridden in tests with a temp folder.
final libraryDirectoryProvider = Provider<Directory>(
  (ref) =>
      throw UnimplementedError('libraryDirectoryProvider must be overridden'),
);

/// Real directory, resolved once at start-up (main.dart).
Future<Directory> resolveLibraryDirectory() async => Directory(
  p.join((await getApplicationDocumentsDirectory()).path, 'library'),
);

final pdfInspectorProvider = Provider<PdfInspector>((ref) => PdfrxInspector());

final libraryRepositoryProvider = Provider<LibraryRepository>(
  (ref) => LibraryRepository(
    ref.watch(databaseProvider),
    directory: ref.watch(libraryDirectoryProvider),
    inspector: ref.watch(pdfInspectorProvider),
  ),
);

/// Opens the system file picker and returns chosen PDF paths. Overridden in tests.
final pdfPickerProvider = Provider<Future<List<String>> Function()>(
  (ref) => pickPdfPaths,
);

/// Builds the PDF page view. Overridden in tests (the real one needs the native PDF engine).
typedef PdfViewBuilder = Widget Function(
  BuildContext context,
  File file,
  int initialPage,
  void Function(int page) onPage,
);
final pdfViewBuilderProvider = Provider<PdfViewBuilder>((ref) => buildPdfView);

final booksProvider = StreamProvider<List<BookRow>>(
  (ref) => ref.watch(libraryRepositoryProvider).watchBooks(),
);
final shelvesProvider = StreamProvider<List<ShelfRow>>(
  (ref) => ref.watch(libraryRepositoryProvider).watchShelves(),
);

enum LibraryView { shelf, grid, list }

/// Which books are listed: everything, favourites, recently opened, or one shelf.
sealed class LibraryFilter {
  const LibraryFilter();
}

class AllBooks extends LibraryFilter {
  const AllBooks();
  @override
  bool operator ==(Object o) => o is AllBooks;
  @override
  int get hashCode => 1;
}

class Favorites extends LibraryFilter {
  const Favorites();
  @override
  bool operator ==(Object o) => o is Favorites;
  @override
  int get hashCode => 2;
}

class ShelfFilter extends LibraryFilter {
  const ShelfFilter(this.shelfId);
  final String shelfId;
  @override
  bool operator ==(Object o) => o is ShelfFilter && o.shelfId == shelfId;
  @override
  int get hashCode => shelfId.hashCode;
}

class LibraryUi {
  const LibraryUi({
    this.view = LibraryView.shelf,
    this.filter = const AllBooks(),
    this.query = '',
  });
  final LibraryView view;
  final LibraryFilter filter;
  final String query;
  LibraryUi copyWith({
    LibraryView? view,
    LibraryFilter? filter,
    String? query,
  }) => LibraryUi(
    view: view ?? this.view,
    filter: filter ?? this.filter,
    query: query ?? this.query,
  );
}

class LibraryUiController extends Notifier<LibraryUi> {
  @override
  LibraryUi build() => const LibraryUi();
  void setView(LibraryView v) => state = state.copyWith(view: v);
  void setFilter(LibraryFilter f) => state = state.copyWith(filter: f);
  void setQuery(String q) => state = state.copyWith(query: q);
}

final libraryUiProvider = NotifierProvider<LibraryUiController, LibraryUi>(
  LibraryUiController.new,
);

/// Pure filtering so it can be tested directly.
List<BookRow> filterBooks(List<BookRow> all, LibraryUi ui) {
  final q = ui.query.trim().toLowerCase();
  final out = all.where((b) {
    final f = ui.filter;
    if (f is Favorites && b.favorite != 1) return false;
    if (f is ShelfFilter && b.shelfId != f.shelfId) return false;
    if (q.isEmpty) return true;
    return b.title.toLowerCase().contains(q) ||
        b.author.toLowerCase().contains(q) ||
        b.fileName.toLowerCase().contains(q);
  }).toList();
  return out;
}

final visibleBooksProvider = Provider<AsyncValue<List<BookRow>>>((ref) {
  final ui = ref.watch(libraryUiProvider);
  return ref.watch(booksProvider).whenData((b) => filterBooks(b, ui));
});

/// Most recently opened first, only books that were opened.
List<BookRow> recentBooks(List<BookRow> all, {int limit = 8}) {
  final r = all.where((b) => b.lastOpenedAt != null).toList()
    ..sort((a, b) => b.lastOpenedAt!.compareTo(a.lastOpenedAt!));
  return r.take(limit).toList();
}

double readingProgress(BookRow b) =>
    b.pageCount <= 0 ? 0 : (b.lastPage / b.pageCount).clamp(0.0, 1.0);
