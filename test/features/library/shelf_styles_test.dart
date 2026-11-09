import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/features/library/data/library_repository.dart';
import 'package:folio/features/library/presentation/shelf_styles.dart';

import '../../helpers.dart';
import 'reader_settings_test.dart' show io;

void main() {
  late List<BookRow> books;
  late ShelfRow classics;

  /// Five books: Alpha, Beta, Gamma on "Classics" (Beta half read), Delta and Epsilon on no shelf.
  Future<TestEnv> open(
    WidgetTester t, {
    String? style,
    Size size = const Size(411, 890),
    Future<void> Function(TestEnv, LibraryRepository)? extra,
  }) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final env = await TestEnv.create();
    addTearDown(env.db.close);
    await t.runAsync(() async {
      final repo = LibraryRepository(env.db, directory: env.libraryDir, inspector: FakePdfInspector());
      books = [];
      var pages = 40;
      for (final title in ['Alpha', 'Beta', 'Gamma', 'Delta', 'Epsilon']) {
        // different page counts so the files differ (identical files are one book)
        final b = (await repo.importPdf(await env.writePdf('$title.pdf', pages += 30))).book!;
        await repo.updateDetails(b.id, title: title);
        books.add(b);
      }
      classics = await repo.createShelf('Classics');
      for (final b in books.take(3)) {
        await repo.moveToShelf(b.id, classics.id);
      }
      await repo.saveProgress(books[1].id, 50);
      await repo.markOpened(books[1].id);
      if (style != null) await env.store.setState('shelf_style', style);
      if (extra != null) await extra(env, repo);
    });
    await t.pumpWidget(env.app);
    await io(t);
    // phones use the bottom bar, wider screens the side rail
    await t.tap(find.descendant(of: find.byWidgetPredicate((w) => w is NavigationBar || w is NavigationRail), matching: find.text('Library')), warnIfMissed: false); // the rail's label is inside its tap area
    await io(t);
    return env;
  }

  Future<void> endIt(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  }

  testWidgets('Settings: the shelf style is chosen there and remembered', (t) async {
    final env = await open(t);
    expect(find.byKey(const Key('turning-shelf')), findsNothing, reason: 'Classic by default');
    await t.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Settings')));
    await io(t);
    await t.scrollUntilVisible(find.byKey(const Key('shelf-style-cabinets')), 200, scrollable: find.byType(Scrollable).first);
    await t.ensureVisible(find.byKey(const Key('shelf-style-cabinets'))); // to the top, clear of the bottom bar
    await io(t, rounds: 1);
    await t.tap(find.byKey(const Key('shelf-style-cabinets')));
    await io(t, rounds: 2);
    expect(await t.runAsync(() => env.store.state('shelf_style')), 'cabinets');
    await t.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Library')));
    await io(t);
    expect(find.byKey(Key('cabinet-${classics.id}')), findsOneWidget);
    await endIt(t);
  });

  testWidgets('Turning books: first tap turns the book and shows its card, Put back returns it, second tap reads', (t) async {
    await open(t, style: 'turning');
    expect(find.byKey(const Key('turning-shelf')), findsOneWidget);
    final beta = books[1];
    await t.tap(find.byKey(Key('book-${beta.id}')));
    await io(t, rounds: 2);
    expect(find.byKey(Key('turned-card-${beta.id}')), findsOneWidget);
    expect(find.text('Page 50 of 100 · 50%'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);

    await t.tap(find.byKey(const Key('turned-back')));
    await io(t, rounds: 2);
    expect(find.byKey(Key('turned-card-${beta.id}')), findsNothing);

    // turn it again, then tap the cover: the reader opens
    await t.tap(find.byKey(Key('book-${beta.id}')));
    await io(t, rounds: 2);
    await t.tap(find.byKey(Key('cover-face-${beta.id}')));
    await io(t, rounds: 4);
    expect(find.textContaining('PDF view page'), findsOneWidget);
    await t.pump(const Duration(seconds: 1));
    await endIt(t);
  });

  testWidgets('Glass cabinets: a wall with one cabinet per shelf plus Unsorted; tap opens it, Back closes it', (t) async {
    await open(t, style: 'cabinets');
    expect(find.text('Continue reading'), findsOneWidget, reason: 'Beta was opened');
    expect(find.byKey(Key('cabinet-${classics.id}')), findsOneWidget);
    expect(find.byKey(const Key('cabinet-unsorted')), findsOneWidget);
    expect(find.text('3 books'), findsOneWidget);
    expect(find.text('2 books'), findsOneWidget);

    await t.tap(find.byKey(Key('cabinet-${classics.id}')));
    await io(t, rounds: 4);
    expect(find.byKey(const Key('cabinet-back')), findsOneWidget);
    expect(find.text('Classics'), findsWidgets);
    for (final b in books.take(3)) {
      expect(find.byKey(Key('book-${b.id}')), findsOneWidget);
    }
    expect(find.byKey(Key('book-${books[3].id}')), findsNothing, reason: 'Delta is not on this shelf');

    // inside, books turn like the "Turning books" style
    await t.tap(find.byKey(Key('book-${books[0].id}')));
    await io(t, rounds: 2);
    expect(find.byKey(Key('turned-card-${books[0].id}')), findsOneWidget);
    expect(find.text('Read'), findsOneWidget);

    // the phone's Back closes the cabinet, it does not leave the Library
    await t.binding.handlePopRoute();
    await io(t, rounds: 3);
    expect(find.byKey(const Key('cabinet-back')), findsNothing);
    expect(find.byKey(Key('cabinet-${classics.id}')), findsOneWidget);

    // Unsorted holds the books on no shelf
    await t.tap(find.byKey(const Key('cabinet-unsorted')));
    await io(t, rounds: 4);
    expect(find.byKey(Key('book-${books[3].id}')), findsOneWidget);
    expect(find.byKey(Key('book-${books[4].id}')), findsOneWidget);
    expect(find.byKey(Key('book-${books[0].id}')), findsNothing);
    await t.tap(find.byKey(const Key('cabinet-back')));
    await io(t, rounds: 3);
    expect(find.byKey(const Key('cabinet-unsorted')), findsOneWidget);
    await endIt(t);
  });

  testWidgets('Glass cabinets: searching shows the matching books on open shelves', (t) async {
    await open(t, style: 'cabinets');
    await t.enterText(find.byKey(const Key('library-search')), 'eps');
    await io(t, rounds: 2);
    expect(find.byKey(const Key('turning-shelf')), findsOneWidget);
    expect(find.byKey(Key('book-${books[4].id}')), findsOneWidget);
    expect(find.byKey(Key('cabinet-${classics.id}')), findsNothing);
    await endIt(t);
  });

  testWidgets('Glass cabinets fit a small landscape phone without overflow', (t) async {
    await open(t, style: 'cabinets', size: const Size(740, 360));
    expect(t.takeException(), isNull);
    await t.scrollUntilVisible(find.byKey(Key('cabinet-${classics.id}')), 120, scrollable: find.descendant(of: find.byKey(const ValueKey('cabinet-wall')), matching: find.byType(Scrollable)).first);
    await t.tap(find.byKey(Key('cabinet-${classics.id}')));
    await io(t, rounds: 4);
    expect(t.takeException(), isNull);
    await t.ensureVisible(find.byKey(Key('book-${books[1].id}'))); // a short screen scrolls to the books
    await io(t, rounds: 1);
    await t.tap(find.byKey(Key('book-${books[1].id}')));
    await io(t, rounds: 2);
    expect(find.byKey(Key('turned-card-${books[1].id}')), findsOneWidget);
    expect(t.takeException(), isNull);
    await endIt(t);
  });

  bool? litOf(WidgetTester t, BookRow b) =>
      t.widget<SpotlightBook>(find.ancestor(of: find.byKey(Key('book-${b.id}')), matching: find.byType(SpotlightBook))).lit;

  testWidgets('Spotlight search: every book stays on the shelf, matches light up, the rest dim; it can be turned off', (t) async {
    final env = await open(t);
    await t.enterText(find.byKey(const Key('library-search')), 'eps');
    await io(t, rounds: 2);
    for (final b in books) {
      expect(find.byKey(Key('book-${b.id}')), findsOneWidget, reason: '${b.title} stays in place');
    }
    expect(litOf(t, books[4]), isTrue);
    expect(litOf(t, books[0]), isFalse);
    await t.enterText(find.byKey(const Key('library-search')), '');
    await io(t, rounds: 2);
    expect(litOf(t, books[0]), isNull, reason: 'no search, no spotlight');

    // Settings -> Spotlight search off: searching narrows the shelf again
    await t.runAsync(() => env.store.setState('shelf_spotlight', '0'));
    await endIt(t);
  });

  testWidgets('Spotlight search off: a search hides the books that do not match', (t) async {
    await open(t, extra: (env, _) => env.store.setState('shelf_spotlight', '0'));
    await t.enterText(find.byKey(const Key('library-search')), 'eps');
    await io(t, rounds: 2);
    expect(find.byKey(Key('book-${books[4].id}')), findsOneWidget);
    expect(find.byKey(Key('book-${books[0].id}')), findsNothing);
    await endIt(t);
  });

  testWidgets('Ribbons and dust: a ribbon on a book being read, gold on a finished one, dust on one left alone; off removes them', (t) async {
    final old = DateTime.now().subtract(const Duration(days: 300)).millisecondsSinceEpoch;
    Future<void> seed(TestEnv env, LibraryRepository repo) async {
      await repo.saveProgress(books[2].id, books[2].pageCount); // Gamma finished
      await (env.db.update(env.db.books)..where((b) => b.id.equals(books[3].id))).write(BooksCompanion(lastOpenedAt: Value(old)));
    }

    await open(t, extra: seed);
    expect(find.byKey(Key('ribbon-${books[1].id}')), findsOneWidget, reason: 'Beta is half read');
    expect(find.byKey(Key('gold-${books[2].id}')), findsOneWidget, reason: 'Gamma is finished');
    expect(find.byKey(Key('ribbon-${books[2].id}')), findsNothing);
    expect(find.byKey(Key('dust-${books[3].id}')), findsOneWidget, reason: 'Delta was last opened 300 days ago');
    expect(find.byKey(Key('dust-${books[1].id}')), findsNothing, reason: 'Beta was opened today');
    await endIt(t);

    await open(t, extra: (env, repo) async {
      await seed(env, repo);
      await env.store.setState('shelf_ribbons', '0');
    });
    expect(find.byKey(Key('ribbon-${books[1].id}')), findsNothing);
    expect(find.byKey(Key('gold-${books[2].id}')), findsNothing);
    expect(find.byKey(Key('dust-${books[3].id}')), findsNothing);
    await endIt(t);
  });

  testWidgets('Cover carousel: the middle cover shows its details; arrows, swipes and side covers move it; Read opens it', (t) async {
    await open(t, style: 'carousel');
    expect(find.byKey(const Key('carousel')), findsOneWidget);
    String title() => t.widget<Text>(find.byKey(const Key('carousel-title'))).data!;
    final first = title();
    expect(books.map((b) => b.title), contains(first));
    expect(find.textContaining('1 of 5'), findsOneWidget);

    await t.tap(find.byKey(const Key('carousel-next')));
    await io(t, rounds: 2);
    expect(title(), isNot(first));
    expect(find.textContaining('2 of 5'), findsOneWidget);

    await t.tap(find.byKey(const Key('carousel-prev')));
    await io(t, rounds: 2);
    expect(title(), first);

    // swipe left on the middle cover: the next book comes to the middle
    final middle = books.firstWhere((b) => b.title == first);
    await t.drag(find.byKey(Key('carousel-cover-${middle.id}')), const Offset(-160, 0));
    await io(t, rounds: 2);
    expect(find.textContaining('of 5'), findsOneWidget);
    expect(title(), isNot(first));

    // tapping the middle cover reads; Read does the same
    await t.tap(find.byKey(const Key('carousel-read')));
    await io(t, rounds: 4);
    expect(find.textContaining('PDF view page'), findsOneWidget);
    await t.pump(const Duration(seconds: 1));
    await endIt(t);
  });

  testWidgets('Cover carousel fits a small landscape phone', (t) async {
    await open(t, style: 'carousel', size: const Size(740, 360));
    expect(find.byKey(const Key('carousel')), findsOneWidget);
    expect(t.takeException(), isNull);
    await endIt(t);
  });
}
