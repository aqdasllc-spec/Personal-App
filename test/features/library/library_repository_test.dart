import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/data/local/database_opener.dart';
import 'package:folio/features/library/data/library_repository.dart';
import 'package:folio/features/library/domain_highlights.dart';
import 'package:folio/features/library/domain_tags.dart';

import '../../helpers.dart';

void main() {
  late AppDatabase db;
  late Directory lib, src;
  late LibraryRepository repo;
  var n = 0;
  var clock = DateTime(2026, 11, 6, 10);

  String pdf(String name, {int pages = 12, String extra = ''}) {
    final f = File('${src.path}/$name')..writeAsStringSync('pages=$pages $extra');
    return f.path;
  }

  setUp(() {
    quietDrift();
    db = openInMemory();
    lib = Directory.systemTemp.createTempSync('lib');
    src = Directory.systemTemp.createTempSync('src');
    n = 0;
    clock = DateTime(2026, 11, 6, 10);
    repo = LibraryRepository(db, directory: lib, inspector: FakePdfInspector(), now: () => clock, newId: () => 'b${++n}');
  });
  tearDown(() async {
    await db.close();
    lib.deleteSync(recursive: true);
    src.deleteSync(recursive: true);
  });

  test('importing copies the file, reads the page count and builds a readable title', () async {
    final path = pdf('deep_work_notes.pdf', pages: 321);
    final r = await repo.importPdf(path);
    expect(r.status, ImportStatus.added);
    final b = r.book!;
    expect((b.title, b.pageCount, b.fileName, b.lastPage, b.favorite), ('deep work notes', 321, 'deep_work_notes.pdf', 0, 0));
    expect(repo.fileOf(b).existsSync(), isTrue);
    expect(File(path).existsSync(), isTrue, reason: 'the original is never touched or moved');
    expect(repo.fileOf(b).readAsStringSync(), File(path).readAsStringSync());
  });

  test('the same file twice is recognised by content, even under another name', () async {
    await repo.importPdf(pdf('a.pdf'));
    final r = await repo.importPdf(pdf('copy of a.pdf'));
    expect(r.status, ImportStatus.duplicate);
    expect((await repo.watchBooks().first).length, 1);
    expect(lib.listSync().length, 1);
  });

  test('a file that is not a readable PDF, or has vanished, is refused and leaves nothing behind', () async {
    final bad = File('${src.path}/notes.pdf')..writeAsStringSync('hello');
    expect((await repo.importPdf(bad.path)).status, ImportStatus.unreadable);
    expect((await repo.importPdf('${src.path}/nope.pdf')).status, ImportStatus.missing);
    expect(await repo.watchBooks().first, isEmpty);
    expect(lib.listSync(), isEmpty);
  });

  test('progress is remembered and marks the book as recently opened', () async {
    final b = (await repo.importPdf(pdf('a.pdf'))).book!;
    clock = DateTime(2026, 11, 7, 8);
    await repo.saveProgress(b.id, 5);
    final r = (await repo.book(b.id))!;
    expect((r.lastPage, r.lastOpenedAt), (5, clock.millisecondsSinceEpoch));
  });

  test('details: titles cannot be blanked; favourite and shelf changes stick', () async {
    final b = (await repo.importPdf(pdf('a.pdf'))).book!;
    await expectLater(repo.updateDetails(b.id, title: '  '), throwsArgumentError);
    await repo.updateDetails(b.id, title: ' Atomic Habits ', author: ' James Clear ');
    await repo.setFavorite(b.id, true);
    final s = await repo.createShelf('  To read ');
    await repo.moveToShelf(b.id, s.id);
    final r = (await repo.book(b.id))!;
    expect((r.title, r.author, r.favorite, r.shelfId, s.name), ('Atomic Habits', 'James Clear', 1, s.id, 'To read'));
    await expectLater(repo.createShelf(' '), throwsArgumentError);
  });

  test('deleting a shelf keeps its books', () async {
    final b = (await repo.importPdf(pdf('a.pdf'))).book!;
    final s = await repo.createShelf('Work');
    await repo.moveToShelf(b.id, s.id);
    await repo.deleteShelf(s.id);
    expect((await repo.book(b.id))!.shelfId, isNull);
    expect(await repo.watchShelves().first, isEmpty);
  });

  test('remove hides the book but is undoable; purge deletes the file for good', () async {
    final b = (await repo.importPdf(pdf('a.pdf'))).book!;
    await repo.remove(b.id);
    expect(await repo.watchBooks().first, isEmpty);
    expect(repo.fileOf(b).existsSync(), isTrue);
    await repo.restore(b.id);
    expect((await repo.watchBooks().first).length, 1);
    await repo.remove(b.id);
    expect(await repo.purge(), 1);
    expect(repo.fileOf(b).existsSync(), isFalse);
    expect(await repo.book(b.id), isNull);
    // After a purge the same PDF can be added again.
    expect((await repo.importPdf(pdf('a.pdf'))).status, ImportStatus.added);
  });

  test('bookmarks: toggling adds then removes a page; they list by page; removing the book purges them', () async {
    final b = (await repo.importPdf(pdf('a.pdf'))).book!;
    expect(await repo.toggleBookmark(b.id, 9), isTrue);
    expect(await repo.toggleBookmark(b.id, 3), isTrue);
    expect((await repo.watchBookmarks(b.id).first).map((m) => m.page), [3, 9]);
    expect(await repo.toggleBookmark(b.id, 9), isFalse, reason: 'second tap on the same page removes it');
    final m = (await repo.watchBookmarks(b.id).first).single;
    await repo.renameBookmark(m.id, '  Chapter 1 ');
    expect((await repo.watchBookmarks(b.id).first).single.label, 'Chapter 1');
    await repo.remove(b.id);
    await repo.purge();
    expect(await db.select(db.bookmarks).get(), isEmpty);
  });

  test('highlights: add, order by page, note, colour, remove; purged with the book', () async {
    final b = (await repo.importPdf(pdf('a.pdf'))).book!;
    await repo.addHighlight(b.id, const HighlightDraft(page: 9, rects: [[1, 5, 2, 1]], text: 'later'));
    final first = await repo.addHighlight(b.id, const HighlightDraft(page: 2, rects: [[1, 5, 2, 1], [3, 9, 4, 6]], text: 'earlier'), color: 'blue');
    final list = await repo.watchHighlights(b.id).first;
    expect(list.map((h) => h.snippet), ['earlier', 'later']);
    expect(list.first.color, 'blue');
    expect(decodeRects(list.first.rects).length, 2);
    await repo.setHighlightNote(first, '  why  ');
    await repo.setHighlightColor(first, 'pink');
    final h = (await repo.watchHighlights(b.id).first).first;
    expect((h.note, h.color), ('why', 'pink'));
    await repo.removeHighlight(first);
    expect((await repo.watchHighlights(b.id).first).length, 1);
    await repo.remove(b.id);
    await repo.purge();
    expect(await db.select(db.highlights).get(), isEmpty);
  });

  test('tags: stored cleaned-up, replaced as a whole, empty clears', () async {
    final b = (await repo.importPdf(pdf('a.pdf'))).book!;
    expect(await repo.setTags(b.id, ' Work, #to read ,work'), ['Work', 'to read']);
    expect(decodeTags((await repo.book(b.id))!.tags), ['Work', 'to read']);
    await repo.setTags(b.id, '');
    expect((await repo.book(b.id))!.tags, '[]');
  });

  group('tag management and bulk actions', () {
    Future<List<String>> tagsOf(String id) async => decodeTags((await repo.book(id))!.tags);

    test('rename: every book changes, case-only renames work, renaming onto an existing tag merges', () async {
      final a = (await repo.importPdf(pdf('a.pdf', pages: 1))).book!;
      final b = (await repo.importPdf(pdf('b.pdf', pages: 2))).book!;
      final c = (await repo.importPdf(pdf('c.pdf', pages: 3))).book!;
      await repo.setTags(a.id, 'work, safety');
      await repo.setTags(b.id, 'Work');
      await repo.setTags(c.id, 'fiction');
      expect(await repo.renameTag('WORK', 'Job'), 2);
      expect(await tagsOf(a.id), ['Job', 'safety']);
      expect(await tagsOf(b.id), ['Job']);
      expect(await tagsOf(c.id), ['fiction'], reason: 'untouched');
      expect(await repo.renameTag('job', 'Job'), 0, reason: 'nothing to change');
      expect(await repo.renameTag('safety', 'job'), 1, reason: 'merge into the existing tag');
      expect(await tagsOf(a.id), ['Job'], reason: 'no duplicate left after the merge');
      await repo.renameTag('fiction', 'Fiction');
      expect(await tagsOf(c.id), ['Fiction'], reason: 'only the spelling changed');
      await expectLater(repo.renameTag('Job', '  # , '), throwsArgumentError);
    });

    test('delete removes the tag from every book and keeps the books', () async {
      final a = (await repo.importPdf(pdf('a.pdf', pages: 1))).book!;
      final b = (await repo.importPdf(pdf('b.pdf', pages: 2))).book!;
      await repo.setTags(a.id, 'x, y');
      await repo.setTags(b.id, 'X');
      expect(await repo.deleteTag('x'), 2);
      expect(await tagsOf(a.id), ['y']);
      expect(await tagsOf(b.id), isEmpty);
      expect((await repo.watchBooks().first).length, 2);
    });

    test('add tags to several books: merged with what they have, only the chosen ones, capped at 20', () async {
      final a = (await repo.importPdf(pdf('a.pdf', pages: 1))).book!;
      final b = (await repo.importPdf(pdf('b.pdf', pages: 2))).book!;
      final c = (await repo.importPdf(pdf('c.pdf', pages: 3))).book!;
      await repo.setTags(a.id, 'keep');
      expect(await repo.addTagsToBooks([a.id, b.id], 'New, keep'), 2);
      expect(await tagsOf(a.id), ['keep', 'New']);
      expect(await tagsOf(b.id), ['New', 'keep']);
      expect(await tagsOf(c.id), isEmpty);
      expect(await repo.addTagsToBooks([a.id], '  '), 0);
      await repo.addTagsToBooks([c.id], [for (var i = 0; i < 25; i++) 't$i'].join(','));
      expect((await tagsOf(c.id)).length, 20);
    });

    test('move several books to a shelf and favourite them in one go', () async {
      final a = (await repo.importPdf(pdf('a.pdf', pages: 1))).book!;
      final b = (await repo.importPdf(pdf('b.pdf', pages: 2))).book!;
      final c = (await repo.importPdf(pdf('c.pdf', pages: 3))).book!;
      final shelf = await repo.createShelf('Work');
      await repo.moveBooksToShelf([a.id, b.id], shelf.id);
      await repo.setFavorites([a.id, b.id], true);
      expect(((await repo.book(a.id))!.shelfId, (await repo.book(b.id))!.shelfId, (await repo.book(c.id))!.shelfId), (shelf.id, shelf.id, null));
      expect(((await repo.book(a.id))!.favorite, (await repo.book(c.id))!.favorite), (1, 0));
      await repo.moveBooksToShelf([a.id], null);
      await repo.setFavorites([a.id], false);
      expect(((await repo.book(a.id))!.shelfId, (await repo.book(a.id))!.favorite), (null, 0));
    });
  });
}
