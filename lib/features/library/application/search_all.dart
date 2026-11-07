import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../data/local/app_database.dart';
import '../domain_search_all.dart';
import 'library_controller.dart';
import 'read_aloud.dart' show pageTextReaderProvider;

const maxHitsPerBook = 20;
const maxHitsTotal = 300;

class SearchAllState {
  const SearchAllState({this.query = '', this.running = false, this.booksDone = 0, this.booksTotal = 0, this.hits = const [], this.truncated = false});
  final String query;
  final bool running, truncated;
  final int booksDone, booksTotal;
  final List<BookHit> hits;

  SearchAllState copyWith({String? query, bool? running, int? booksDone, int? booksTotal, List<BookHit>? hits, bool? truncated}) => SearchAllState(
    query: query ?? this.query,
    running: running ?? this.running,
    booksDone: booksDone ?? this.booksDone,
    booksTotal: booksTotal ?? this.booksTotal,
    hits: hits ?? this.hits,
    truncated: truncated ?? this.truncated,
  );
}

/// Searches the text inside every book (and the text recognised on scans), one book at a time, showing hits as they come.
class SearchAll extends Notifier<SearchAllState> {
  int _token = 0;

  @override
  SearchAllState build() {
    ref.onDispose(() => _token++);
    return const SearchAllState();
  }

  void stop() {
    _token++;
    state = state.copyWith(running: false);
  }

  Future<void> start(String raw) async {
    final query = raw.trim();
    final token = ++_token;
    if (query.length < 2) {
      state = SearchAllState(query: query);
      return;
    }
    final repo = ref.read(libraryRepositoryProvider);
    final books = [...(ref.read(booksProvider).value ?? const <BookRow>[])]..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    state = SearchAllState(query: query, running: true, booksTotal: books.length);
    final reader = ref.read(pageTextReaderProvider);
    final hits = <BookHit>[];
    var truncated = false;
    for (var i = 0; i < books.length; i++) {
      final b = books[i];
      var perBook = 0;
      final scanned = b.textState == 'scanned' || b.textState == 'ocr';
      if (scanned) {
        final rows = await repo.pageTexts(b.id);
        if (token != _token) return;
        for (final r in rows..sort((x, y) => x.page.compareTo(y.page))) {
          for (final s in snippetsIn(r.body, query, max: 1)) {
            if (perBook < maxHitsPerBook) hits.add(BookHit(bookId: b.id, title: b.title, page: r.page, snippet: s));
            perBook++;
          }
        }
      }
      if (!scanned) {
        final file = repo.fileOf(b);
        for (var p = 1; p <= b.pageCount && perBook < maxHitsPerBook; p++) {
          final text = await reader.textOf(file, p);
          if (token != _token) return;
          if (text == null || text.isEmpty) continue;
          for (final s in snippetsIn(text, query, max: 1)) {
            hits.add(BookHit(bookId: b.id, title: b.title, page: p, snippet: s));
            perBook++;
          }
          if (p % 10 == 0) await Future<void>.delayed(Duration.zero); // let the screen breathe
        }
      }
      if (hits.length >= maxHitsTotal) {
        truncated = true;
        hits.removeRange(maxHitsTotal, hits.length);
      }
      if (token != _token) return;
      state = state.copyWith(booksDone: i + 1, hits: List.of(hits), truncated: truncated);
      if (truncated) break;
    }
    if (token == _token) state = state.copyWith(running: false);
  }
}

final searchAllProvider = NotifierProvider.autoDispose<SearchAll, SearchAllState>(SearchAll.new);

/// Every highlight, newest first.
final allHighlightsProvider = StreamProvider.autoDispose<List<HighlightRow>>(
  (ref) => ref.watch(libraryRepositoryProvider).watchAllHighlights(),
);

/// What each highlight colour means to the user ("yellow = important"). Remembered on this device.
class HighlightMeanings extends Notifier<Map<String, String>> {
  static const key = 'highlight_meanings';
  @override
  Map<String, String> build() {
    Future.microtask(() async {
      try {
        final raw = await ref.read(syncedStoreProvider).state(key);
        if (raw == null || raw.isEmpty) return;
        final m = (jsonDecode(raw) as Map).cast<String, Object?>();
        state = {
          for (final e in m.entries)
            if (highlightColorNames.containsKey(e.key) && e.value is String && (e.value as String).trim().isNotEmpty) e.key: (e.value as String).trim(),
          ...state,
        };
      } catch (_) {}
    });
    return const {};
  }

  /// Empty text removes the meaning.
  void set(String color, String meaning) {
    final m = {...state};
    final t = meaning.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (t.isEmpty) {
      m.remove(color);
    } else {
      m[color] = t.length > 30 ? t.substring(0, 30) : t;
    }
    state = m;
    try {
      ref.read(syncedStoreProvider).setState(key, jsonEncode(m));
    } catch (_) {}
  }
}

final highlightMeaningsProvider = NotifierProvider<HighlightMeanings, Map<String, String>>(HighlightMeanings.new);
