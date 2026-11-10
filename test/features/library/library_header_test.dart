import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/features/library/data/library_repository.dart';
import 'package:folio/features/library/presentation/book_edit.dart' show EditScope;

import '../../helpers.dart';

Future<void> io(WidgetTester t, {int rounds = 6}) async {
  for (var i = 0; i < rounds; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    for (var k = 0; k < 3; k++) {
      await t.pump(const Duration(milliseconds: 60));
    }
  }
  await t.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('the Library header slides away while scrolling down the books and comes back on scrolling up', (t) async {
    t.view.physicalSize = const Size(411, 890);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final env = await TestEnv.create();
    addTearDown(env.db.close);
    await t.runAsync(() async {
      final repo = LibraryRepository(env.db, directory: env.libraryDir, inspector: FakePdfInspector());
      for (var i = 0; i < 24; i++) {
        await repo.importPdf(await env.writePdf('Book $i.pdf', 10 + i));
      }
    });
    await t.pumpWidget(env.app);
    await io(t);
    await t.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Library')));
    await io(t);
    await t.tap(find.byTooltip('List'));
    await io(t);
    double factor() => t.widget<AnimatedAlign>(find.byKey(const Key('library-header'))).heightFactor!;
    expect(factor(), 1);
    final list = find.descendant(of: find.byType(EditScope), matching: find.byType(Scrollable)).first;
    await t.drag(list, const Offset(0, -400));
    await io(t, rounds: 2);
    expect(factor(), 0, reason: 'scrolled down: more room for the books');
    expect(find.byKey(const Key('chip-all')).hitTestable(), findsOneWidget, reason: 'the shelf chips stay');
    await t.drag(list, const Offset(0, 120));
    await io(t, rounds: 2);
    expect(factor(), 1, reason: 'scrolled up: back');
    // searching keeps it
    await t.drag(list, const Offset(0, -400));
    await io(t, rounds: 2);
    expect(factor(), 0);
    await t.drag(list, const Offset(0, 2000));
    await io(t, rounds: 2);
    await t.enterText(find.byKey(const Key('library-search')), 'Book 1');
    await io(t, rounds: 2);
    await t.drag(list, const Offset(0, -300));
    await io(t, rounds: 2);
    expect(factor(), 1, reason: 'never hidden while searching');
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  });
}
