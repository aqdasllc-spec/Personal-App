import 'package:flutter_test/flutter_test.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/features/library/application/library_controller.dart';
import 'package:folio/features/library/domain_tags.dart';

BookRow book(String id, String title, {String author = '', int pages = 100, int last = 0, int? opened, int added = 0, String tags = '[]', int fav = 0, String? shelf}) => BookRow(
      id: id,
      title: title,
      author: author,
      fileName: '$title.pdf',
      pageCount: pages,
      sizeBytes: 1,
      sha256: id,
      shelfId: shelf,
      favorite: fav,
      cloudState: 'local',
      tags: tags,
      sortPos: 0,
      textState: 'unknown',
      lastPage: last,
      lastOpenedAt: opened,
      addedAt: added,
    );

List<String> ids(List<BookRow> l) => [for (final b in l) b.id];

void main() {
  final a = book('a', 'banana', author: 'Zed', pages: 50, opened: 300, added: 1);
  final b = book('b', 'Apple', author: 'amy', pages: 400, opened: 100, added: 3);
  final c = book('c', 'cherry', pages: 400, added: 2); // never opened, no author
  final d = book('d', 'Apple', author: 'Amy', pages: 10, added: 4); // same title as b

  group('sorting', () {
    test('recently added is newest first', () => expect(ids(sortBooks([a, b, c, d], LibrarySort.added)), ['d', 'b', 'c', 'a']));
    test('recently read: most recent first, never-opened last (newest added first among them)', () => expect(ids(sortBooks([a, b, c, d], LibrarySort.read)), ['a', 'b', 'd', 'c']));
    test('title ignores case; equal titles fall back to newest added', () => expect(ids(sortBooks([a, b, c, d], LibrarySort.title)), ['d', 'b', 'a', 'c']));
    test('author ignores case; books without an author come last', () => expect(ids(sortBooks([a, b, c, d], LibrarySort.author)), ['d', 'b', 'a', 'c']));
    test('longest first; ties by newest added', () => expect(ids(sortBooks([a, b, c, d], LibrarySort.pages)), ['b', 'c', 'a', 'd']));
    test('sorting does not change the input list', () {
      final input = [a, b, c, d];
      sortBooks(input, LibrarySort.title);
      expect(ids(input), ['a', 'b', 'c', 'd']);
    });
  });

  group('reading status', () {
    test('thresholds: 0 = not started, below 95% = reading, 95% and up = finished', () {
      expect(statusOf(book('x', 'x', pages: 100, last: 0)), ReadStatus.unread);
      expect(statusOf(book('x', 'x', pages: 100, last: 1)), ReadStatus.reading);
      expect(statusOf(book('x', 'x', pages: 100, last: 94)), ReadStatus.reading);
      expect(statusOf(book('x', 'x', pages: 100, last: 95)), ReadStatus.finished);
      expect(statusOf(book('x', 'x', pages: 100, last: 100)), ReadStatus.finished);
      expect(statusOf(book('x', 'x', pages: 0, last: 3)), ReadStatus.reading, reason: 'unknown length is never "finished"');
    });
  });

  group('tags', () {
    test('typed text becomes clean tags: separators, #, spaces, duplicates ignoring case, limits', () {
      expect(normalizeTags('Work, to  read ,#Safety\nwork,  '), ['Work', 'to read', 'Safety']);
      expect(normalizeTags('   '), isEmpty);
      expect(normalizeTags('x' * 50).single.length, maxTagLength);
      expect(normalizeTags([for (var i = 0; i < 40; i++) 't$i'].join(',')).length, maxTags);
      expect(tagsToText(['a', 'b']), 'a, b');
    });

    test('stored tags decode forgivingly', () {
      expect(decodeTags(encodeTags(['a', 'b c'])), ['a', 'b c']);
      expect(decodeTags('nope'), isEmpty);
      expect(decodeTags('[1,"",  "ok", null]'), ['ok']);
    });

    test('tag list: alphabetical, counted, first spelling wins', () {
      final books = [book('1', 'a', tags: encodeTags(['Work', 'safety'])), book('2', 'b', tags: encodeTags(['work'])), book('3', 'c')];
      expect(tagCounts(books), [('safety', 1), ('Work', 2)]);
    });
  });

  group('filtering', () {
    final books = [
      book('1', 'Permit to work', author: 'HSE', last: 40, added: 1, tags: encodeTags(['work', 'safety'])),
      book('2', 'Novel', author: 'Ana', last: 100, added: 2, tags: encodeTags(['fiction'])),
      book('3', 'Manual', author: 'HSE', added: 3, tags: encodeTags(['Work']), fav: 1),
    ];
    LibraryUi ui({ReadStatus s = ReadStatus.all, Set<String> tags = const {}, String q = '', LibrarySort sort = LibrarySort.added, LibraryFilter f = const AllBooks()}) => LibraryUi(status: s, tags: tags, query: q, sort: sort, filter: f);

    test('by status', () {
      expect(ids(filterBooks(books, ui(s: ReadStatus.unread))), ['3']);
      expect(ids(filterBooks(books, ui(s: ReadStatus.reading))), ['1']);
      expect(ids(filterBooks(books, ui(s: ReadStatus.finished))), ['2']);
    });

    test('by tags: a book needs ALL chosen tags, compared ignoring case', () {
      expect(ids(filterBooks(books, ui(tags: {'WORK'}))), ['3', '1']);
      expect(ids(filterBooks(books, ui(tags: {'work', 'safety'}))), ['1']);
      expect(ids(filterBooks(books, ui(tags: {'work', 'fiction'}))), isEmpty);
    });

    test('search also finds tags; everything combines with the shelf choice and the sort', () {
      expect(ids(filterBooks(books, ui(q: 'fict'))), ['2']);
      expect(ids(filterBooks(books, ui(f: const Favorites(), tags: {'work'}))), ['3']);
      expect(ids(filterBooks(books, ui(q: 'hse', sort: LibrarySort.title))), ['3', '1']);
    });

    test('active filter count: status plus one per tag (shelf and sort do not count)', () {
      expect(const LibraryUi().activeFilters, 0);
      expect(ui(s: ReadStatus.reading, tags: {'a', 'b'}, sort: LibrarySort.title, f: const Favorites()).activeFilters, 3);
    });
  });
}
