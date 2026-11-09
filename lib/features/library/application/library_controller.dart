import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../app/providers.dart';
import '../../../data/local/app_database.dart';
import '../data/library_repository.dart';
import '../domain_highlights.dart';
import 'reader_prefs.dart';
import '../domain_ink.dart';
import '../domain_reading_stats.dart';
import '../domain_smart_views.dart';
import '../domain_tag_colors.dart';
import '../domain_tags.dart';
import '../data/pdf_inspector.dart';
import '../presentation/page_thumbs.dart';

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
    store: ref.watch(syncedStoreProvider),
  ),
);

/// Opens the system file picker and returns chosen PDF paths. Overridden in tests.
final pdfPickerProvider = Provider<Future<List<String>> Function()>(
  (ref) => pickPdfPaths,
);

/// Builds the grid of page pictures in the "Pages" sheet. Overridden in tests (the real one needs the PDF engine).
final pageThumbsBuilderProvider = Provider<PageThumbsBuilder>((ref) => buildPageThumbs);

/// Opens the system folder picker. Overridden in tests.
final pdfFolderPickerProvider = Provider<Future<String?> Function()>(
  (ref) => pickPdfFolder,
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

  // reading preferences (page theme, scroll direction...) and taps on the page
  final prefs = ValueNotifier<ReaderPrefs>(const ReaderPrefs());

  /// A single tap on the page: which third of the width it landed in.
  void Function(TapZone zone)? onZoneTap;

  // pen drawings: the tool, the strokes per page, and a new stroke coming from the page
  final pen = ValueNotifier<PenState>(const PenState());
  final ink = ValueNotifier<Map<int, List<Stroke>>>(const {});
  Future<void> Function(int page, Stroke stroke)? onStroke;
  Future<void> Function(int page, double x, double y)? onErase;

  // recognised text of scanned pages: boxes to highlight (search hits)
  final ocrBoxes = ValueNotifier<List<OcrHit>>(const []);

  // highlights: the reader page feeds the saved ones in; the PDF view reports new ones out
  final highlights = ValueNotifier<List<HighlightRow>>(const []);
  Future<void> Function(HighlightDraft draft)? onHighlight;

  /// "Look up" chosen on selected text.
  Future<void> Function(String text)? onLookUp;
}

enum TapZone { left, center, right }

/// The pen tool: on/off, colour (index in [penColors]), width (index in [penWidths]), eraser mode, highlighter mode
/// and "stylus only" (fingers then scroll and zoom as usual, only a stylus draws).
class PenState {
  const PenState({this.on = false, this.color = 0, this.width = 1, this.erase = false, this.highlighter = false, this.stylusOnly = false});
  final bool on, erase, highlighter, stylusOnly;
  final int color, width;
  PenState copyWith({bool? on, int? color, int? width, bool? erase, bool? highlighter, bool? stylusOnly}) => PenState(
    on: on ?? this.on,
    color: color ?? this.color,
    width: width ?? this.width,
    erase: erase ?? this.erase,
    highlighter: highlighter ?? this.highlighter,
    stylusOnly: stylusOnly ?? this.stylusOnly,
  );
  @override
  bool operator ==(Object other) =>
      other is PenState &&
      other.on == on &&
      other.color == color &&
      other.width == width &&
      other.erase == erase &&
      other.highlighter == highlighter &&
      other.stylusOnly == stylusOnly;
  @override
  int get hashCode => Object.hash(on, color, width, erase, highlighter, stylusOnly);
}

/// One search hit on a scanned page: the page and the line's rectangle as fractions (0..1) of the page.
class OcrHit {
  const OcrHit(this.page, this.left, this.top, this.right, this.bottom);
  final int page;
  final double left, top, right, bottom;
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

/// Pages and time per day for the Home statistics.
final readingStatsProvider = StreamProvider<List<DayStat>>(
  (ref) => ref.watch(libraryRepositoryProvider).watchReadingStats(),
);

/// Pages per day the user wants to read (Home shows progress towards it). Remembered on this device.
class ReadGoal extends Notifier<int> {
  static const key = 'read_goal';
  @override
  int build() {
    Future.microtask(() async {
      try {
        final v = int.tryParse(await ref.read(syncedStoreProvider).state(key) ?? '');
        if (v != null && v >= 1 && v <= maxReadGoal) state = v;
      } catch (_) {}
    });
    return defaultReadGoal;
  }

  void set(int v) {
    state = v.clamp(1, maxReadGoal);
    try {
      ref.read(syncedStoreProvider).setState(key, '$state');
    } catch (_) {}
  }
}

final readGoalProvider = NotifierProvider<ReadGoal, int>(ReadGoal.new);

final inkProvider = StreamProvider.family<List<PageInkRow>, String>(
  (ref, bookId) => ref.watch(libraryRepositoryProvider).watchInk(bookId),
);

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

/// Books that are on no shelf (the "Unsorted" cabinet).
class NoShelf extends LibraryFilter {
  const NoShelf();
  @override
  bool operator ==(Object other) => other is NoShelf;
  @override
  int get hashCode => 3;
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
      final sort = LibrarySort.values
          .where((v) => v.name == savedSort)
          .firstOrNull;
      final view = LibraryView.values
          .where((v) => v.name == savedView)
          .firstOrNull;
      if (sort != null || view != null) {
        state = state.copyWith(sort: sort, view: view);
      }
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
      tags: has
          ? {
              for (final t in state.tags)
                if (t.toLowerCase() != lower) t,
            }
          : {...state.tags, tag},
    );
  }

  /// Shows the books a saved view describes.
  void applyView(SmartView v) {
    final status = ReadStatus.values.where((x) => x.name == v.status).firstOrNull ?? ReadStatus.all;
    final sort = LibrarySort.values.where((x) => x.name == v.sort).firstOrNull;
    state = state.copyWith(status: status, tags: {...v.tags}, sort: sort);
    if (sort != null) _save(_sortKey, sort.name);
  }

  void clearFilters() =>
      state = state.copyWith(status: ReadStatus.all, tags: const {});

  /// A tag was renamed / merged everywhere: keep a filter on it working.
  void renameFilterTag(String from, String to) {
    final f = from.toLowerCase();
    if (!state.tags.any((t) => t.toLowerCase() == f)) return;
    state = state.copyWith(
      tags: {for (final t in state.tags) t.toLowerCase() == f ? to : t},
    );
  }

  /// A tag was deleted everywhere: stop filtering by it.
  void dropFilterTag(String tag) {
    final f = tag.toLowerCase();
    state = state.copyWith(
      tags: {
        for (final t in state.tags)
          if (t.toLowerCase() != f) t,
      },
    );
  }
}

/// Rearrange mode (the pen button): books wiggle and can be dragged to a new place or onto a shelf.
class ShelfEditController extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool on) => state = on;
}

final shelfEditProvider = NotifierProvider<ShelfEditController, bool>(
  ShelfEditController.new,
);

/// The book picked in rearrange mode to be moved with the arrow buttons (null = none).
class MoveSelectionController extends Notifier<String?> {
  @override
  String? build() => null;
  void toggle(String id) => state = state == id ? null : id;
  void clear() => state = null;
}

final moveSelectionProvider =
    NotifierProvider<MoveSelectionController, String?>(
      MoveSelectionController.new,
    );

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

final selectionProvider = NotifierProvider<SelectionController, Set<String>?>(
  SelectionController.new,
);

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
      if (a.author.trim().isEmpty != b.author.trim().isEmpty) {
        return a.author.trim().isEmpty ? 1 : -1; // unknown authors last
      }
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
    if (f is NoShelf && b.shelfId != null) return false;
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

/// Books you have started (opened or read into), for Home. [mine] puts them in the user's own order ("My order");
/// otherwise the most recently opened come first.
List<BookRow> readingBooks(
  List<BookRow> all, {
  required bool mine,
  int limit = 8,
}) {
  final started = all
      .where((b) => b.lastOpenedAt != null || b.lastPage > 0)
      .toList();
  if (!mine) return recentBooks(started, limit: limit);
  return sortBooks(started, LibrarySort.manual).take(limit).toList();
}

/// Home's "Continue reading" order: 'recent' (default) or 'mine'. Remembered.
class HomeReadingOrder extends Notifier<String> {
  static const key = 'home_reading_order';
  @override
  String build() {
    Future.microtask(() async {
      try {
        final v = await ref.read(syncedStoreProvider).state(key);
        if (v == 'mine' || v == 'recent') state = v!;
      } catch (_) {}
    });
    return 'recent';
  }

  void set(String v) {
    state = v;
    try {
      ref.read(syncedStoreProvider).setState(key, v);
    } catch (_) {}
  }
}

final homeReadingOrderProvider = NotifierProvider<HomeReadingOrder, String>(
  HomeReadingOrder.new,
);

/// How the Library's Shelf view looks. Chosen in Settings, remembered on this device.
enum ShelfStyle {
  classic('Classic', 'Rows of spines on open shelves'),
  turning('Turning books', 'Tap a spine and the book turns to show its cover'),
  cabinets('Glass cabinets', 'Each shelf is a glass cabinet; tap one to open its doors'),
  carousel('Cover carousel', 'Covers stand in a 3D row; swipe and the middle one faces you');

  const ShelfStyle(this.label, this.description);
  final String label, description;
}

class ShelfStyleController extends Notifier<ShelfStyle> {
  static const key = 'shelf_style';
  @override
  ShelfStyle build() {
    Future.microtask(() async {
      try {
        final v = await ref.read(syncedStoreProvider).state(key);
        final s = ShelfStyle.values.where((x) => x.name == v).firstOrNull;
        if (s != null) state = s;
      } catch (_) {}
    });
    return ShelfStyle.classic;
  }

  void set(ShelfStyle s) {
    state = s;
    try {
      ref.read(syncedStoreProvider).setState(key, s.name);
    } catch (_) {}
  }
}

final shelfStyleProvider = NotifierProvider<ShelfStyleController, ShelfStyle>(ShelfStyleController.new);

/// An on/off choice for the Library's look, remembered on this device (on unless turned off).
class _LookSwitch extends Notifier<bool> {
  _LookSwitch(this.key);
  final String key;
  @override
  bool build() {
    Future.microtask(() async {
      try {
        final v = await ref.read(syncedStoreProvider).state(key);
        if (v == '0') state = false;
      } catch (_) {}
    });
    return true;
  }

  void set(bool on) {
    state = on;
    try {
      ref.read(syncedStoreProvider).setState(key, on ? '1' : '0');
    } catch (_) {}
  }
}

/// Searching on the shelf dims the other books and lights up the matches where they stand (instead of hiding the rest).
final spotlightProvider = NotifierProvider<_LookSwitch, bool>(() => _LookSwitch('shelf_spotlight'));

/// Spines show a ribbon at the reading position, dust on books not opened for months, a gold band when finished.
final ribbonsProvider = NotifierProvider<_LookSwitch, bool>(() => _LookSwitch('shelf_ribbons'));

/// How dusty a book looks: 0 (opened in the last 45 days) up to 0.5 (untouched for about a year).
double dustOf(BookRow b, DateTime now) {
  final last = b.lastOpenedAt ?? b.addedAt;
  final days = (now.millisecondsSinceEpoch - last) / Duration.millisecondsPerDay;
  return ((days - 45) / 640).clamp(0.0, 0.5);
}

double readingProgress(BookRow b) =>
    b.pageCount <= 0 ? 0 : (b.lastPage / b.pageCount).clamp(0.0, 1.0);

/// A colour per tag (tag name, ignoring case -> palette index). Syncs between devices (one synced row per tag).
class TagColors extends Notifier<Map<String, int>> {
  static const key = 'tag_colors';
  @override
  Map<String, int> build() {
    Future.microtask(_reload);
    // another device changed something: read it
    ref.listen(syncControllerProvider.select((s) => s.lastSync), (_, _) => _reload());
    return const {};
  }

  Future<void> _reload() async {
    try {
      final v = decodeTagColors(await ref.read(syncedStoreProvider).state(key));
      if (v.isNotEmpty || state.isNotEmpty) state = v;
    } catch (_) {}
  }

  void _push(String tag, int? index) {
    try {
      ref.read(syncedStoreProvider).setFields(key, tagKey(tag), {'color': index});
    } catch (_) {}
  }

  /// [index] null = no colour.
  void set(String tag, int? index) {
    final m = {...state};
    if (index == null) {
      m.remove(tagKey(tag));
    } else {
      m[tagKey(tag)] = index;
    }
    state = m;
    _push(tag, index);
  }

  /// A renamed tag keeps its colour (when merging into a coloured tag, the target's colour wins).
  void rename(String from, String to) {
    final c = state[tagKey(from)];
    if (c == null || tagKey(from) == tagKey(to)) return;
    set(from, null);
    if (!state.containsKey(tagKey(to))) set(to, c);
  }
}

final tagColorsProvider = NotifierProvider<TagColors, Map<String, int>>(
  TagColors.new,
);

/// Saved Library views ("smart collections"). Sync between devices (one synced row per view).
class SmartViews extends Notifier<List<SmartView>> {
  static const key = 'smart_views';
  @override
  List<SmartView> build() {
    Future.microtask(_reload);
    ref.listen(syncControllerProvider.select((s) => s.lastSync), (_, _) => _reload());
    return const [];
  }

  Future<void> _reload() async {
    try {
      final v = decodeViews(await ref.read(syncedStoreProvider).state(key));
      if (v.isNotEmpty || state.isNotEmpty) state = v;
    } catch (_) {}
  }

  /// Makes [next] the list: every view that was added or changed, and every one that went, is sent as its own change.
  void _commit(List<SmartView> next) {
    final before = {for (final v in state) v.name.toLowerCase(): jsonEncode(v.toJson())};
    final after = {for (final v in next) v.name.toLowerCase(): v};
    state = next;
    try {
      final store = ref.read(syncedStoreProvider);
      after.forEach((k, v) {
        if (before[k] != jsonEncode(v.toJson())) store.setFields(key, k, {'view': v.toJson()});
      });
      for (final k in before.keys) {
        if (!after.containsKey(k)) store.setFields(key, k, {'view': null});
      }
    } catch (_) {}
  }

  /// Saves what the Library currently shows (status, tags, sort) under [name].
  void saveCurrent(String name, LibraryUi ui) {
    if (name.trim().isEmpty) return;
    _commit(withView(state, SmartView(name: name, status: ui.status.name, tags: ui.tags.toList(), sort: ui.sort.name)));
  }

  void remove(String name) => _commit([for (final v in state) if (v.name != name) v]);

  void tagRenamed(String from, String to) => _commit(renameTagInViews(state, from, to));

  void tagDeleted(String tag) => _commit(dropTagFromViews(state, tag));
}

final smartViewsProvider = NotifierProvider<SmartViews, List<SmartView>>(SmartViews.new);
