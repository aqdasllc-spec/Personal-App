import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../data/local/app_database.dart';
import '../domain_highlights.dart';
import '../domain_tags.dart';
import '../../../data/sync/synced_store.dart';
import '../domain_ink.dart';
import '../domain_reading_stats.dart';
import '../domain_ocr.dart';
import 'ocr.dart';

/// What we learn about a PDF before accepting it.
class PdfInfo {
  const PdfInfo({required this.pageCount, this.title = ''});
  final int pageCount;
  final String title;
}

/// Opens a PDF just far enough to count pages. Returns null if it is not a readable PDF.
/// (An interface so tests need no native PDF engine.)
abstract class PdfInspector {
  Future<PdfInfo?> inspect(String path);
}

enum ImportStatus { added, duplicate, unreadable, missing }

/// How long a removed book stays in the bin before it is deleted for good.
const binRetention = Duration(days: 30);

/// Whole days left before a book removed at [deletedAtMs] is deleted for good (0 = less than a day).
int binDaysLeft(int deletedAtMs, DateTime now) {
  final used = now
      .difference(DateTime.fromMillisecondsSinceEpoch(deletedAtMs))
      .inDays;
  return (binRetention.inDays - used).clamp(0, binRetention.inDays);
}

class StorageReport {
  const StorageReport({
    required this.bookCount,
    required this.bookBytes,
    required this.removedCount,
    required this.removedBytes,
    required this.cloudCount,
    required this.cloudBytes,
    required this.coverBytes,
    required this.largest,
  });
  final int bookCount,
      bookBytes,
      removedCount,
      removedBytes,
      cloudCount,
      cloudBytes,
      coverBytes;

  /// The biggest books, largest first.
  final List<BookRow> largest;
}

class ImportResult {
  const ImportResult(this.status, this.fileName, [this.book]);
  final ImportStatus status;
  final String fileName;
  final BookRow? book;
}

/// Library data: copies PDFs into the app's private folder (originals are never touched), keeps
/// metadata, shelves, favourites and reading position.
class LibraryRepository {
  LibraryRepository(
    this._db, {
    required this.directory,
    required this.inspector,
    DateTime Function()? now,
    String Function()? newId,
    SyncedStore? store,
  // ignore: prefer_initializing_formals
  }) : _store = store,
       _now = now ?? DateTime.now,
       _newId = newId ?? (() => const Uuid().v4());

  final AppDatabase _db;

  /// When given, drawings are saved through it so they sync; without it (tests, tools) they are saved locally only.
  final SyncedStore? _store;
  final Directory directory;
  final PdfInspector inspector;
  final DateTime Function() _now;
  final String Function() _newId;

  File fileOf(BookRow b) => File(p.join(directory.path, '${b.id}.pdf'));

  Future<ImportResult> importPdf(String sourcePath, {String? shelfId}) async {
    final name = p.basename(sourcePath);
    final src = File(sourcePath);
    if (!await src.exists()) return ImportResult(ImportStatus.missing, name);
    final hash = (await sha256.bind(src.openRead()).first).toString();
    final dup =
        await (_db.select(_db.books)
              ..where((b) => b.sha256.equals(hash) & b.deletedAt.isNull()))
            .getSingleOrNull();
    if (dup != null) return ImportResult(ImportStatus.duplicate, name, dup);
    // the same PDF is sitting in the bin: bring that one back (with its bookmarks, highlights and reading place)
    final binned =
        await (_db.select(_db.books)
              ..where((b) => b.sha256.equals(hash) & b.deletedAt.isNotNull())
              ..limit(1))
            .getSingleOrNull();
    if (binned != null && await fileOf(binned).exists()) {
      await restore(binned.id);
      if (shelfId != null) await moveToShelf(binned.id, shelfId);
      return ImportResult(ImportStatus.added, name, await book(binned.id));
    }
    final info = await inspector.inspect(sourcePath);
    if (info == null) return ImportResult(ImportStatus.unreadable, name);
    final id = _newId();
    await directory.create(recursive: true);
    final dest = File(p.join(directory.path, '$id.pdf'));
    try {
      await src.copy(dest.path);
      final base = p
          .basenameWithoutExtension(name)
          .replaceAll(RegExp(r'[_]+'), ' ')
          .trim();
      final title = info.title.trim().isNotEmpty ? info.title.trim() : base;
      final row = BooksCompanion.insert(
        id: id,
        addedAt: _now().millisecondsSinceEpoch,
        title: Value(title),
        fileName: Value(name),
        pageCount: Value(info.pageCount),
        sizeBytes: Value(await dest.length()),
        sha256: Value(hash),
        shelfId: Value(shelfId),
      );
      await _db.into(_db.books).insert(row);
    } catch (_) {
      if (await dest.exists()) await dest.delete();
      rethrow;
    }
    return ImportResult(ImportStatus.added, name, await book(id));
  }

  /// Registers a PDF that was downloaded from the cloud into [directory] (already verified).
  Future<void> addDownloaded({
    required String id,
    required String title,
    required String author,
    required int pages,
    required int size,
    required String sha256,
  }) => _db
      .into(_db.books)
      .insert(
        BooksCompanion.insert(
          id: id,
          addedAt: _now().millisecondsSinceEpoch,
          title: Value(title),
          author: Value(author),
          fileName: Value('$title.pdf'),
          pageCount: Value(pages),
          sizeBytes: Value(size),
          sha256: Value(sha256),
          cloudState: const Value('synced'),
        ),
      );

  Future<BookRow?> book(String id) =>
      (_db.select(_db.books)..where((b) => b.id.equals(id))).getSingleOrNull();

  Stream<List<BookRow>> watchBooks() =>
      (_db.select(_db.books)
            ..where((b) => b.deletedAt.isNull())
            ..orderBy([(b) => OrderingTerm.desc(b.addedAt)]))
          .watch();

  Stream<List<ShelfRow>> watchShelves() => (_db.select(
    _db.shelves,
  )..orderBy([(s) => OrderingTerm.asc(s.createdAt)])).watch();

  Future<void> updateDetails(String id, {String? title, String? author}) async {
    final t = title?.trim();
    if (t != null && t.isEmpty) throw ArgumentError('A book needs a title.');
    await (_db.update(_db.books)..where((b) => b.id.equals(id))).write(
      BooksCompanion(
        title: t == null ? const Value.absent() : Value(t),
        author: author == null ? const Value.absent() : Value(author.trim()),
      ),
    );
  }

  /// Saves the user's own order: [ids] get positions 0, 1, 2... (books not listed keep theirs).
  Future<void> setOrder(List<String> ids) => _db.transaction(() async {
    for (var i = 0; i < ids.length; i++) {
      await (_db.update(_db.books)..where((b) => b.id.equals(ids[i]))).write(
        BooksCompanion(sortPos: Value(i)),
      );
    }
  });

  /// Replaces the book's tags with the cleaned-up version of [input] (see [normalizeTags]).
  Future<List<String>> setTags(String id, String input) async {
    final tags = normalizeTags(input);
    await (_db.update(_db.books)..where((b) => b.id.equals(id))).write(
      BooksCompanion(tags: Value(encodeTags(tags))),
    );
    return tags;
  }

  // ------------------------------------------------------------ bulk / tag management
  /// Applies [change] to the tag list of every book (removed books included, so Undo never brings back an old name).
  /// Returns how many books changed.
  Future<int> _rewriteTags(
    List<String> Function(List<String> tags) change, {
    Set<String>? onlyIds,
  }) async {
    var changed = 0;
    await _db.transaction(() async {
      for (final b in await _db.select(_db.books).get()) {
        if (onlyIds != null && !onlyIds.contains(b.id)) continue;
        final before = decodeTags(b.tags);
        final after = _dedupe(change(before));
        if (encodeTags(after) == encodeTags(before)) continue;
        await (_db.update(_db.books)..where((x) => x.id.equals(b.id))).write(
          BooksCompanion(tags: Value(encodeTags(after))),
        );
        changed++;
      }
    });
    return changed;
  }

  static List<String> _dedupe(List<String> tags) {
    final seen = <String>{};
    return [
      for (final t in tags)
        if (seen.add(t.toLowerCase())) t,
    ].take(maxTags).toList();
  }

  /// Renames a tag on every book. Renaming to a tag that already exists merges the two.
  Future<int> renameTag(String from, String to) async {
    final target = normalizeTags(to).firstOrNull;
    if (target == null) throw ArgumentError('A tag needs a name.');
    final f = from.toLowerCase();
    return await _rewriteTags(
      (tags) => [for (final t in tags) t.toLowerCase() == f ? target : t],
    );
  }

  /// Removes a tag from every book.
  Future<int> deleteTag(String tag) {
    final f = tag.toLowerCase();
    return _rewriteTags(
      (tags) => [
        for (final t in tags)
          if (t.toLowerCase() != f) t,
      ],
    );
  }

  /// Adds the tags typed in [input] to each of [ids] (existing tags are kept).
  Future<int> addTagsToBooks(Iterable<String> ids, String input) {
    final add = normalizeTags(input);
    if (add.isEmpty) return Future.value(0);
    return _rewriteTags((tags) => [...tags, ...add], onlyIds: ids.toSet());
  }

  Future<void> moveBooksToShelf(Iterable<String> ids, String? shelfId) =>
      (_db.update(_db.books)..where((b) => b.id.isIn(ids.toList()))).write(
        BooksCompanion(shelfId: Value(shelfId)),
      );

  Future<void> setFavorites(Iterable<String> ids, bool fav) =>
      (_db.update(_db.books)..where((b) => b.id.isIn(ids.toList()))).write(
        BooksCompanion(favorite: Value(fav ? 1 : 0)),
      );

  Future<void> setFavorite(String id, bool fav) =>
      (_db.update(_db.books)..where((b) => b.id.equals(id))).write(
        BooksCompanion(favorite: Value(fav ? 1 : 0)),
      );

  Future<void> moveToShelf(String id, String? shelfId) =>
      (_db.update(_db.books)..where((b) => b.id.equals(id))).write(
        BooksCompanion(shelfId: Value(shelfId)),
      );

  /// Records that the reader is on [page] now (also marks the book as recently opened).
  Future<void> saveProgress(String id, int page) =>
      (_db.update(_db.books)..where((b) => b.id.equals(id))).write(
        BooksCompanion(
          lastPage: Value(page),
          lastOpenedAt: Value(_now().millisecondsSinceEpoch),
        ),
      );

  Future<void> markOpened(String id) =>
      (_db.update(_db.books)..where((b) => b.id.equals(id))).write(
        BooksCompanion(lastOpenedAt: Value(_now().millisecondsSinceEpoch)),
      );

  /// Soft delete: the row hides at once; the file is removed by [purge].
  Future<void> remove(String id) =>
      (_db.update(_db.books)..where((b) => b.id.equals(id))).write(
        BooksCompanion(deletedAt: Value(_now().millisecondsSinceEpoch)),
      );

  Future<void> restore(String id) =>
      (_db.update(_db.books)..where((b) => b.id.equals(id))).write(
        const BooksCompanion(deletedAt: Value(null)),
      );

  /// What the library takes up on this device and in the cloud.
  Future<StorageReport> storageReport() async {
    final all = await _db.select(_db.books).get();
    final live = all.where((b) => b.deletedAt == null).toList();
    final removed = all.where((b) => b.deletedAt != null).toList();
    final synced = live.where((b) => b.cloudState == 'synced').toList();
    var cover = 0;
    final coverDir = Directory(p.join(directory.path, 'covers'));
    if (await coverDir.exists()) {
      await for (final e in coverDir.list()) {
        if (e is File) cover += await e.length();
      }
    }
    final largest = [...live]
      ..sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
    return StorageReport(
      bookCount: live.length,
      bookBytes: live.fold(0, (n, b) => n + b.sizeBytes),
      removedCount: removed.length,
      removedBytes: removed.fold(0, (n, b) => n + b.sizeBytes),
      cloudCount: synced.length,
      cloudBytes: synced.fold(0, (n, b) => n + b.sizeBytes),
      coverBytes: cover,
      largest: largest.take(5).toList(),
    );
  }

  /// Deletes the cached first-page images (they are rendered again when needed). Returns the bytes freed.
  Future<int> clearCovers() async {
    final dir = Directory(p.join(directory.path, 'covers'));
    if (!await dir.exists()) return 0;
    var freed = 0;
    await for (final e in dir.list()) {
      if (e is File) {
        freed += await e.length();
        await e.delete();
      }
    }
    return freed;
  }

  /// Permanently deletes removed books (and their files, covers, bookmarks and highlights) that have been in the
  /// bin for at least [keep]. The default deletes everything in the bin. Returns how many were purged.
  Future<int> purge({Duration keep = Duration.zero}) async {
    final cutoff = _now().millisecondsSinceEpoch - keep.inMilliseconds;
    final gone =
        await (_db.select(_db.books)..where(
              (b) =>
                  b.deletedAt.isNotNull() &
                  b.deletedAt.isSmallerOrEqualValue(cutoff),
            ))
            .get();
    for (final b in gone) {
      await _eraseBook(b);
    }
    return gone.length;
  }

  /// Deletes one removed book for good (from the bin).
  Future<void> deletePermanently(String id) async {
    final b =
        await (_db.select(_db.books)
              ..where((x) => x.id.equals(id) & x.deletedAt.isNotNull()))
            .getSingleOrNull();
    if (b != null) await _eraseBook(b);
  }

  Future<void> _eraseBook(BookRow b) async {
    final f = fileOf(b);
    if (await f.exists()) await f.delete();
    final cover = File(p.join(directory.path, 'covers', '${b.id}.png'));
    if (await cover.exists()) await cover.delete();
    await (_db.delete(_db.bookmarks)..where((x) => x.bookId.equals(b.id))).go();
    await (_db.delete(_db.pageTexts)..where((x) => x.bookId.equals(b.id))).go();
    await (_db.delete(_db.pageInk)..where((x) => x.bookId.equals(b.id))).go();
    await (_db.delete(
      _db.highlights,
    )..where((x) => x.bookId.equals(b.id))).go();
    await (_db.delete(_db.books)..where((x) => x.id.equals(b.id))).go();
  }

  /// The bin: removed books, most recently removed first.
  Stream<List<BookRow>> watchRemoved() =>
      (_db.select(_db.books)
            ..where((b) => b.deletedAt.isNotNull())
            ..orderBy([(b) => OrderingTerm.desc(b.deletedAt)]))
          .watch();

  // ------------------------------------------------------- scanned PDFs (OCR)
  Future<void> setTextState(String id, String state) =>
      (_db.update(_db.books)..where((b) => b.id.equals(id))).write(
        BooksCompanion(textState: Value(state)),
      );

  Future<void> savePageText(String bookId, int page, RecognizedPage p) => _db
      .into(_db.pageTexts)
      .insertOnConflictUpdate(
        PageTextsCompanion.insert(
          bookId: bookId,
          page: page,
          body: Value(p.text),
          boxes: Value(encodeLines(p.lines)),
        ),
      );

  Future<Set<int>> recognisedPages(String bookId) async => {
    for (final r in await (_db.select(
      _db.pageTexts,
    )..where((t) => t.bookId.equals(bookId))).get())
      r.page,
  };

  Future<List<PageTextRow>> pageTexts(String bookId) =>
      (_db.select(_db.pageTexts)..where((t) => t.bookId.equals(bookId))).get();

  Future<PageTextRow?> pageText(String bookId, int page) =>
      (_db.select(_db.pageTexts)
            ..where((t) => t.bookId.equals(bookId) & t.page.equals(page)))
          .getSingleOrNull();

  Stream<int> watchRecognisedCount(String bookId) => (_db.select(
    _db.pageTexts,
  )..where((t) => t.bookId.equals(bookId))).watch().map((r) => r.length);

  /// Forgets the recognised text of a book (e.g. to run recognition again).
  Future<void> clearPageTexts(String bookId) async {
    await (_db.delete(
      _db.pageTexts,
    )..where((t) => t.bookId.equals(bookId))).go();
    await setTextState(bookId, 'scanned');
  }

  // ------------------------------------------------------- reading statistics
  /// Counts [page] of [bookId] as read today (once per day, however often it is shown).
  Future<void> markPageRead(String bookId, int page) => _db
      .into(_db.readPages)
      .insert(ReadPagesCompanion.insert(day: dayKey(_now()), bookId: bookId, page: page), mode: InsertMode.insertOrIgnore);

  /// Adds [seconds] of reading time to today.
  Future<void> addReadingSeconds(int seconds) async {
    if (seconds <= 0) return;
    final day = dayKey(_now());
    await _db.customStatement(
      'INSERT INTO read_time (day, seconds) VALUES (?, ?) ON CONFLICT(day) DO UPDATE SET seconds = seconds + excluded.seconds',
      [day, seconds],
    );
    _db.notifyUpdates({TableUpdate.onTable(_db.readTime, kind: UpdateKind.insert)});
  }

  /// Pages and time per day (days with any reading), live.
  Stream<List<DayStat>> watchReadingStats() => _db
      .customSelect(
        'SELECT d.day AS day, COALESCE(p.n, 0) AS pages, COALESCE(t.seconds, 0) AS seconds '
        'FROM (SELECT day FROM read_pages UNION SELECT day FROM read_time) d '
        'LEFT JOIN (SELECT day, COUNT(*) AS n FROM read_pages GROUP BY day) p ON p.day = d.day '
        'LEFT JOIN read_time t ON t.day = d.day ORDER BY d.day',
        readsFrom: {_db.readPages, _db.readTime},
      )
      .watch()
      .map((rows) => [for (final r in rows) DayStat(r.read<String>('day'), r.read<int>('pages'), r.read<int>('seconds'))]);

  // ------------------------------------------------------------- pen drawings
  /// Saves the strokes of a page; an empty list removes the row.
  Future<void> saveInk(String bookId, int page, List<Stroke> strokes) async {
    final store = _store;
    if (store != null) {
      await store.setFields('page_ink', '$bookId:$page', {'strokes': strokes.isEmpty ? null : encodeStrokes(strokes)});
      return;
    }
    if (strokes.isEmpty) {
      await (_db.delete(_db.pageInk)..where((t) => t.bookId.equals(bookId) & t.page.equals(page))).go();
      return;
    }
    await _db.into(_db.pageInk).insertOnConflictUpdate(PageInkCompanion.insert(bookId: bookId, page: page, strokes: Value(encodeStrokes(strokes))));
  }

  Stream<List<PageInkRow>> watchInk(String bookId) => (_db.select(_db.pageInk)..where((t) => t.bookId.equals(bookId))).watch();

  // ---------------------------------------------------------------- highlights
  /// Every highlight in every (not removed) book, newest first.
  Stream<List<HighlightRow>> watchAllHighlights() => (_db.select(_db.highlights)..orderBy([(h) => OrderingTerm.desc(h.createdAt)])).watch();

  Stream<List<HighlightRow>> watchHighlights(String bookId) =>
      (_db.select(_db.highlights)
            ..where((h) => h.bookId.equals(bookId))
            ..orderBy([
              (h) => OrderingTerm.asc(h.page),
              (h) => OrderingTerm.asc(h.createdAt),
            ]))
          .watch();

  Future<String> addHighlight(
    String bookId,
    HighlightDraft d, {
    String color = 'yellow',
  }) async {
    final id = _newId();
    final store = _store;
    if (store != null) {
      await store.setFields('highlights', id, {
        'body': {'b': bookId, 'p': d.page, 'r': encodeRects(d.rects), 's': d.text, 'at': _now().millisecondsSinceEpoch},
        'color': color,
        'note': '',
      });
      return id;
    }
    await _db
        .into(_db.highlights)
        .insert(
          HighlightsCompanion.insert(
            id: id,
            bookId: bookId,
            page: d.page,
            createdAt: _now().millisecondsSinceEpoch,
            rects: Value(encodeRects(d.rects)),
            snippet: Value(d.text),
            color: Value(color),
          ),
        );
    return id;
  }

  Future<void> setHighlightNote(String id, String note) {
    final store = _store;
    if (store != null) return store.setFields('highlights', id, {'note': note.trim()});
    return _setHighlightNoteLocal(id, note);
  }

  Future<void> _setHighlightNoteLocal(String id, String note) =>
      (_db.update(_db.highlights)..where((h) => h.id.equals(id))).write(
        HighlightsCompanion(note: Value(note.trim())),
      );

  Future<void> setHighlightColor(String id, String color) {
    final store = _store;
    if (store != null) return store.setFields('highlights', id, {'color': color});
    return _setHighlightColorLocal(id, color);
  }

  Future<void> _setHighlightColorLocal(String id, String color) =>
      (_db.update(_db.highlights)..where((h) => h.id.equals(id))).write(
        HighlightsCompanion(color: Value(color)),
      );

  Future<void> removeHighlight(String id) {
    final store = _store;
    if (store != null) return store.setFields('highlights', id, {'gone': true});
    return _removeHighlightLocal(id);
  }

  Future<void> _removeHighlightLocal(String id) =>
      (_db.delete(_db.highlights)..where((h) => h.id.equals(id))).go();

  // ----------------------------------------------------------------- bookmarks
  Stream<List<BookmarkRow>> watchBookmarks(String bookId) =>
      (_db.select(_db.bookmarks)
            ..where((b) => b.bookId.equals(bookId))
            ..orderBy([(b) => OrderingTerm.asc(b.page)]))
          .watch();

  /// Adds a bookmark on [page], or removes it if that page is already marked. Returns true if it is marked now.
  Future<bool> toggleBookmark(String bookId, int page) async {
    final existing = await (_db.select(
      _db.bookmarks,
    )..where((b) => b.bookId.equals(bookId) & b.page.equals(page))).get();
    final store = _store;
    if (store != null) {
      // one synced row per marked page: a mark, or null to take it off
      await store.setFields('bookmarks', '$bookId:$page', {
        'mark': existing.isNotEmpty ? null : {'l': '', 'at': _now().millisecondsSinceEpoch},
      });
      return existing.isEmpty;
    }
    if (existing.isNotEmpty) {
      await (_db.delete(
        _db.bookmarks,
      )..where((b) => b.bookId.equals(bookId) & b.page.equals(page))).go();
      return false;
    }
    await _db
        .into(_db.bookmarks)
        .insert(
          BookmarksCompanion.insert(
            id: _newId(),
            bookId: bookId,
            page: page,
            createdAt: _now().millisecondsSinceEpoch,
          ),
        );
    return true;
  }

  Future<void> removeBookmark(String id) async {
    final store = _store;
    final row = store == null ? null : await (_db.select(_db.bookmarks)..where((b) => b.id.equals(id))).getSingleOrNull();
    if (store != null && row != null) {
      await store.setFields('bookmarks', '${row.bookId}:${row.page}', {'mark': null});
      return;
    }
    await (_db.delete(_db.bookmarks)..where((b) => b.id.equals(id))).go();
  }

  Future<void> renameBookmark(String id, String label) async {
    final store = _store;
    final row = store == null ? null : await (_db.select(_db.bookmarks)..where((b) => b.id.equals(id))).getSingleOrNull();
    if (store != null && row != null) {
      await store.setFields('bookmarks', '${row.bookId}:${row.page}', {
        'mark': {'l': label.trim(), 'at': row.createdAt},
      });
      return;
    }
    await (_db.update(_db.bookmarks)..where((b) => b.id.equals(id))).write(
      BookmarksCompanion(label: Value(label.trim())),
    );
  }

  Future<ShelfRow> createShelf(String name) async {
    final n = name.trim();
    if (n.isEmpty) throw ArgumentError('A shelf needs a name.');
    final row = ShelvesCompanion.insert(
      id: _newId(),
      name: n,
      createdAt: _now().millisecondsSinceEpoch,
    );
    await _db.into(_db.shelves).insert(row);
    return (_db.select(
      _db.shelves,
    )..where((s) => s.id.equals(row.id.value))).getSingle();
  }

  Future<void> renameShelf(String id, String name) {
    final n = name.trim();
    if (n.isEmpty) throw ArgumentError('A shelf needs a name.');
    return (_db.update(
      _db.shelves,
    )..where((s) => s.id.equals(id))).write(ShelvesCompanion(name: Value(n)));
  }

  /// Deleting a shelf keeps its books (they go back to "All books").
  Future<void> deleteShelf(String id) => _db.transaction(() async {
    await (_db.update(_db.books)..where((b) => b.shelfId.equals(id))).write(
      const BooksCompanion(shelfId: Value(null)),
    );
    await (_db.delete(_db.shelves)..where((s) => s.id.equals(id))).go();
  });
}
