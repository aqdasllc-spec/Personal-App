import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../data/local/app_database.dart';

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
  }) : _now = now ?? DateTime.now,
       _newId = newId ?? (() => const Uuid().v4());

  final AppDatabase _db;
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
  Future<void> addDownloaded({required String id, required String title, required String author, required int pages, required int size, required String sha256}) =>
      _db.into(_db.books).insert(BooksCompanion.insert(
            id: id,
            addedAt: _now().millisecondsSinceEpoch,
            title: Value(title),
            author: Value(author),
            fileName: Value('$title.pdf'),
            pageCount: Value(pages),
            sizeBytes: Value(size),
            sha256: Value(sha256),
            cloudState: const Value('synced'),
          ));

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

  /// Permanently deletes removed books and their files. Returns how many were purged.
  Future<int> purge() async {
    final gone = await (_db.select(
      _db.books,
    )..where((b) => b.deletedAt.isNotNull())).get();
    for (final b in gone) {
      final f = fileOf(b);
      if (await f.exists()) await f.delete();
      await (_db.delete(_db.books)..where((x) => x.id.equals(b.id))).go();
    }
    return gone.length;
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
