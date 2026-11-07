import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../app/providers.dart';
import '../../../data/local/app_database.dart';
import '../data/library_repository.dart';
import '../domain_highlights.dart';
import '../domain_tags.dart';
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
  ReaderControl control,
);

/// Lets the reader page ask the (native) PDF view to jump to a page, e.g. from a bookmark.
class ReaderControl {
  void Function(int page)? goTo;

  // text search inside the PDF
  void Function(String query)? startSearch;
  void Function()? nextMatch, prevMatch, stopSearch;
  final search = ValueNotifier<ReaderSearch>(const ReaderSearch());

  // highlights: the reader page feeds the saved ones in; the PDF view reports new ones out
  final highlights = ValueNotifier<List<HighlightRow>>(const []);
  Future<void> Function(HighlightDraft draft)? onHighlight;
}

class ReaderSearch {
  const ReaderSearch({
    this.query = '',
    this.count = 0,
    this.index,
    this.searching = false,
  });
  final String query;

  /// Matches found so far.
  final int count;

  /// The match currently shown (0-based), or null before the first one is reached.
  final int? index;

  /// Still scanning pages for more matches.
  final bool searching;
}

final pdfViewBuilderProvider = Provider<PdfViewBuilder>((ref) => buildPdfView);

final highlightsProvider = StreamProvider.family<List<HighlightRow>, String>(
  (ref, bookId) => ref.watch(libraryRepositoryProvider).watchHighlights(bookId),
);

final bookmarksProvider = StreamProvider.family<List<BookmarkRow>, String>(
  (ref, bookId) => ref.watch(libraryRepositoryProvider).watchBookmarks(bookId),
);

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
  bool operator ==(Object other) => other is AllBooks;
  @override
  int get hashCode => 1;
}

class Favorites extends LibraryFilter {
  const Favorites();
  @override
  bool operator ==(Object other) => other is Favorites;
  @override
  int get hashCode => 2;
}

class ShelfFilter extends LibraryFilter {
  const ShelfFilter(this.shelfId);
  final String shelfId;
  @override
  bool operator ==(Object other) =>
      other is ShelfFilter && other.shelfId == shelfId;
  @override
  int get hashCode => shelfId.hashCode;
}

/// How the list is ordered.
enum LibrarySort {
  added('Recently added'),
  manual('My order'),
  read('Recently read'),
  title('Title A–Z'),
  author('Author A–Z'),
  pages('Longest first');

  const LibrarySort(this.label);
  final String label;
}

/// Reading status filter.
enum ReadStatus {
  all('All'),
  unread('Not started'),
  reading('Reading'),
  finished('Finished');

  const ReadStatus(this.label);
  final String label;
}

/// A book counts as finished once 95 % of its pages are behind you.
ReadStatus statusOf(BookRow b) {
  if (b.lastPage <= 0) return ReadStatus.unread;
  return readingProgress(b) >= 0.95 ? ReadStatus.finished : ReadStatus.reading;
}

class LibraryUi {
  const LibraryUi({
    this.view = LibraryView.shelf,
    this.filter = const AllBooks(),
    this.query = '',
    this.sort = LibrarySort.added,
    this.status = ReadStatus.all,
    this.tags = const {},
  });
  final LibraryView view;
  final LibraryFilter filter;
  final String query;
  final LibrarySort sort;
  final ReadStatus status;

  /// Only books that have ALL of these tags (compared ignoring case).
  final Set<String> tags;

  /// Number of narrowing filters on top of the shelf choice (status + tags).
  int get activeFilters => (status == ReadStatus.all ? 0 : 1) + tags.length;

  LibraryUi copyWith({
    LibraryView? view,
    LibraryFilter? filter,
    String? query,
    LibrarySort? sort,
    ReadStatus? status,
    Set<String>? tags,
  }) => LibraryUi(
    view: view ?? this.view,
    filter: filter ?? this.filter,
    query: query ?? this.query,
    sort: sort ?? this.sort,
    status: status ?? this.status,
    tags: tags ?? this.tags,
  );
}

const _sortKey = 'library_sort';
const _viewKey = 'library_view';

class LibraryUiController extends Notifier<LibraryUi> {
  @override
  LibraryUi build() {
    // restore what the user chose last time (sort and view), without delaying the first frame
    Future.microtask(_restore);
    return const LibraryUi();
  }

  Future<void> _restore() async {
    try {
      final store = ref.read(syncedStoreProvider);
      final savedSort = await store.state(_sortKey);
      final savedView = await store.state(_viewKey);
      final sort = LibrarySort.values.where((v) => v.name == savedSort).firstOrNull;
      final view = LibraryView.values.where((v) => v.name == savedView).firstOrNull;
      if (sort != null || view != null) state = state.copyWith(sort: sort, view: view);
    } catch (_) {
      // preferences are a convenience only
    }
  }

  void _save(String key, String value) {
    try {
      ref.read(syncedStoreProvider).setState(key, value);
    } catch (_) {}
  }

  void setView(LibraryView v) {
    state = state.copyWith(view: v);
    _save(_viewKey, v.name);
  }

  void setFilter(LibraryFilter f) => state = state.copyWith(filter: f);
  void setQuery(String q) => state = state.copyWith(query: q);

  void setSort(LibrarySort s) {
    state = state.copyWith(sort: s);
    _save(_sortKey, s.name);
  }

  void setStatus(ReadStatus s) => state = state.copyWith(status: s);

  void toggleTag(String tag) {
    final lower = tag.toLowerCase();
    final has = state.tags.any((t) => t.toLowerCase() == lower);
    state = state.copyWith(
      tags: has ? {for (final t in state.tags) if (t.toLowerCase() != lower) t} : {...state.tags, tag},
    );
  }

  void clearFilters() => state = state.copyWith(status: ReadStatus.all, tags: const {});

  /// A tag was renamed / merged everywhere: keep a filter on it working.
  void renameFilterTag(String from, String to) {
    final f = from.toLowerCase();
    if (!state.tags.any((t) => t.toLowerCase() == f)) return;
    state = state.copyWith(tags: {for (final t in state.tags) t.toLowerCase() == f ? to : t});
  }

  /// A tag was deleted everywhere: stop filtering by it.
  void dropFilterTag(String tag) {
    final f = tag.toLowerCase();
    state = state.copyWith(tags: {for (final t in state.tags) if (t.toLowerCase() != f) t});
  }
}

/// Rearrange mode (the pen button): books wiggle and can be dragged to a new place or onto a shelf.
class ShelfEditController extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool on) => state = on;
}

final shelfEditProvider = NotifierProvider<ShelfEditController, bool>(ShelfEditController.new);

/// The book picked in rearrange mode to be moved with the arrow buttons (null = none).
class MoveSelectionController extends Notifier<String?> {
  @override
  String? build() => null;
  void toggle(String id) => state = state == id ? null : id;
  void clear() => state = null;
}

final moveSelectionProvider = NotifierProvider<MoveSelectionController, String?>(MoveSelectionController.new);

/// Where [dragged] ends up when dropped on [target]: it takes the target's place (the others shift over).
List<String> reorderIds(List<String> ids, String dragged, String target) {
  final from = ids.indexOf(dragged), to = ids.indexOf(target);
  if (from < 0 || to < 0 || from == to) return ids;
  final out = [...ids]..removeAt(from);
  out.insert(to, dragged);
  return out;
}

/// Moves [id] one place earlier (-1) or later (+1).
List<String> nudgeId(List<String> ids, String id, int delta) {
  final i = ids.indexOf(id);
  final j = i + delta;
  if (i < 0 || j < 0 || j >= ids.length) return ids;
  final out = [...ids];
  out.removeAt(i);
  out.insert(j, id);
  return out;
}

/// Selection mode: null = off, otherwise the chosen book ids.
class SelectionController extends Notifier<Set<String>?> {
  @override
  Set<String>? build() => null;
  void start([String? firstId]) => state = {?firstId};
  void toggle(String id) {
    final cur = state;
    if (cur == null) return;
    state = cur.contains(id) ? ({...cur}..remove(id)) : {...cur, id};
  }

  /// Selects or deselects [id] (used by drag-select); does nothing outside selection mode.
  void setSelected(String id, bool on) {
    final cur = state;
    if (cur == null || cur.contains(id) == on) return;
    state = on ? {...cur, id} : ({...cur}..remove(id));
  }

  void selectAll(Iterable<String> ids) => state = {...ids};
  void clear() => state = null;
}

final selectionProvider = NotifierProvider<SelectionController, Set<String>?>(SelectionController.new);

final libraryUiProvider = NotifierProvider<LibraryUiController, LibraryUi>(
  LibraryUiController.new,
);

/// Every tag used in the library (first spelling wins), alphabetical, with how many books carry it.
List<(String tag, int count)> tagCounts(List<BookRow> all) {
  final spelling = <String, String>{};
  final counts = <String, int>{};
  for (final b in all) {
    for (final t in decodeTags(b.tags)) {
      final k = t.toLowerCase();
      spelling.putIfAbsent(k, () => t);
      counts[k] = (counts[k] ?? 0) + 1;
    }
  }
  final keys = counts.keys.toList()..sort();
  return [for (final k in keys) (spelling[k]!, counts[k]!)];
}

int _cmpText(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());

/// Orders [books] (a copy) as chosen. Ties fall back to newest-added so the order is stable.
List<BookRow> sortBooks(List<BookRow> books, LibrarySort sort) {
  int byAdded(BookRow a, BookRow b) => b.addedAt.compareTo(a.addedAt);
  final out = [...books];
  out.sort(switch (sort) {
    LibrarySort.added => byAdded,
    LibrarySort.manual => (a, b) {
        final c = a.sortPos.compareTo(b.sortPos);
        return c != 0 ? c : byAdded(a, b);
      },
    LibrarySort.read => (a, b) {
        final x = a.lastOpenedAt, y = b.lastOpenedAt;
        if (x == null && y == null) return byAdded(a, b);
        if (x == null) return 1; // never opened: after everything that was
        if (y == null) return -1;
        return y.compareTo(x);
      },
    LibrarySort.title => (a, b) {
        final c = _cmpText(a.title, b.title);
        return c != 0 ? c : byAdded(a, b);
      },
    LibrarySort.author => (a, b) {
        if (a.author.trim().isEmpty != b.author.trim().isEmpty) return a.author.trim().isEmpty ? 1 : -1; // unknown authors last
        final c = _cmpText(a.author, b.author);
        if (c != 0) return c;
        final t = _cmpText(a.title, b.title);
        return t != 0 ? t : byAdded(a, b);
      },
    LibrarySort.pages => (a, b) {
        final c = b.pageCount.compareTo(a.pageCount);
        return c != 0 ? c : byAdded(a, b);
      },
  });
  return out;
}

/// Pure filtering + ordering so it can be tested directly.
List<BookRow> filterBooks(List<BookRow> all, LibraryUi ui) {
  final q = ui.query.trim().toLowerCase();
  final wanted = {for (final t in ui.tags) t.toLowerCase()};
  final out = all.where((b) {
    final f = ui.filter;
    if (f is Favorites && b.favorite != 1) return false;
    if (f is ShelfFilter && b.shelfId != f.shelfId) return false;
    if (ui.status != ReadStatus.all && statusOf(b) != ui.status) return false;
    final tags = decodeTags(b.tags);
    if (wanted.isNotEmpty) {
      final have = {for (final t in tags) t.toLowerCase()};
      if (!wanted.every(have.contains)) return false;
    }
    if (q.isEmpty) return true;
    return b.title.toLowerCase().contains(q) ||
        b.author.toLowerCase().contains(q) ||
        b.fileName.toLowerCase().contains(q) ||
        tags.any((t) => t.toLowerCase().contains(q));
  }).toList();
  return sortBooks(out, ui.sort);
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
