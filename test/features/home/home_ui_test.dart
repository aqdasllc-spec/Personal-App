import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/app/app.dart';
import 'package:folio/features/home/home_page.dart';
import 'package:folio/features/library/data/library_repository.dart';
import 'package:folio/features/planner/application/planner_controller.dart';
import 'package:folio/features/planner/data/planner_repository.dart';

import '../../helpers.dart';

final now = DateTime(2026, 11, 6, 12);

Future<void> settleH(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pump(const Duration(milliseconds: 60));
  }
  await t.pumpAndSettle();
}

Future<TestEnv> openHome(WidgetTester t, Future<void> Function(TestEnv env)? seed, {double w = 411, double h = 890}) async {
  t.view.physicalSize = Size(w, h);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final env = await TestEnv.create();
  addTearDown(env.db.close);
  if (seed != null) await t.runAsync(() => seed(env));
  await t.pumpWidget(ProviderScope(
    overrides: [...env.overrides, plannerControllerProvider.overrideWith(() => PlannerController(now: () => now))],
    child: const FolioApp(),
  ));
  await settleH(t);
  return env;
}

Future<void> end(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 1));
}

void main() {
  test('greeting follows the time of day', () {
    expect(greeting(DateTime(2026, 1, 1, 8)), 'Good morning');
    expect(greeting(DateTime(2026, 1, 1, 13)), 'Good afternoon');
    expect(greeting(DateTime(2026, 1, 1, 20)), 'Good evening');
  });

  testWidgets('a fresh Home says there is nothing planned and the library is empty', (t) async {
    await openHome(t, null);
    expect(find.text('Today'), findsOneWidget);
    expect(find.textContaining('Nothing planned for today'), findsOneWidget);
    expect(find.textContaining('Your library is empty'), findsOneWidget);
    expect(find.text('Coming up'), findsNothing);
    await end(t);
  });

  testWidgets('shows today\'s tasks, overdue, upcoming and recently read books; quick add and tick work', (t) async {
    final env = await openHome(t, (env) async {
      final repo = PlannerRepository(env.store);
      await repo.saveTask(TaskInput(title: 'Pay rent', due: DateTime(2026, 11, 6)));
      await repo.saveTask(TaskInput(title: 'Old thing', due: DateTime(2026, 11, 3)));
      await repo.saveTask(TaskInput(title: 'Dentist forms', due: DateTime(2026, 11, 8)));
      final lib = LibraryRepository(env.db, directory: env.libraryDir, inspector: FakePdfInspector());
      final f = await env.writePdf('Deep_Work.pdf', 200);
      final b = (await lib.importPdf(f)).book!;
      await lib.saveProgress(b.id, 50);
    }, h: 1500); // a tall screen: every Home card is laid out (the Quran cabinet sits above them)
    expect(find.text('Pay rent'), findsOneWidget);
    expect(find.text('1 overdue'), findsOneWidget);
    expect(find.text('Old thing'), findsOneWidget);
    expect(find.text('Coming up'), findsOneWidget);
    expect(find.text('Dentist forms'), findsOneWidget);
    expect(find.text('Deep Work'), findsOneWidget);
    expect(find.text('0 of 1 done'), findsOneWidget);

    await t.enterText(find.byKey(const Key('home-quick-add')), 'Call mum');
    await t.tap(find.byKey(const Key('home-quick-add-go')));
    await settleH(t);
    expect(find.text('Call mum'), findsOneWidget);
    expect((await t.runAsync(() => env.db.select(env.db.tasks).get()))!.map((x) => x.title), contains('Call mum'));

    final rows = (await t.runAsync(() => env.db.select(env.db.tasks).get()))!;
    final rent = rows.firstWhere((x) => x.title == 'Pay rent');
    await t.tap(find.byKey(Key('done-${rent.id}')));
    await settleH(t);
    expect(find.text('1 of 2 done'), findsOneWidget);
    await end(t);
  });

  testWidgets('tapping a recent book opens the reader; Open planner goes to the Planner', (t) async {
    final env = await openHome(t, (env) async {
      final lib = LibraryRepository(env.db, directory: env.libraryDir, inspector: FakePdfInspector());
      final b = (await lib.importPdf(await env.writePdf('Alpha.pdf', 30))).book!;
      await lib.saveProgress(b.id, 3);
    }, h: 1500); // a tall screen: every Home card is laid out (the Quran cabinet sits above them)
    final b = (await t.runAsync(() => env.db.select(env.db.books).get()))!.single;
    await t.tap(find.byKey(Key('home-book-${b.id}')));
    await settleH(t);
    expect(find.text('PDF view page 3'), findsOneWidget);
    await t.pageBack();
    await settleH(t);
    await t.tap(find.byKey(const Key('home-open-planner')));
    await settleH(t);
    expect(find.byKey(const Key('planner-quick-add')), findsOneWidget);
    await end(t);
  });

  testWidgets('wide and landscape layouts have no overflow', (t) async {
    for (final s in [const Size(1200, 800), const Size(850, 390)]) {
      await openHome(t, (env) async {
        final repo = PlannerRepository(env.store);
        for (var i = 0; i < 9; i++) {
          await repo.saveTask(TaskInput(title: 'Task $i', due: DateTime(2026, 11, 6 + (i % 3))));
        }
      }, w: s.width, h: s.height);
      expect(t.takeException(), isNull);
      await end(t);
    }
  });

  testWidgets('Continue reading: recently read first by default; the menu switches to My order and it is remembered', (t) async {
    late List<String> ids;
    final env = await openHome(t, (env) async {
      final lib = LibraryRepository(env.db, directory: env.libraryDir, inspector: FakePdfInspector());
      ids = [];
      for (final (name, pages) in [('Alpha', 11), ('Bravo', 12), ('Charlie', 13), ('Unread', 14)]) {
        final b = (await lib.importPdf(await env.writePdf('$name.pdf', pages))).book!;
        await lib.updateDetails(b.id, title: name);
        ids.add(b.id);
      }
      // read in the order Bravo, Alpha, Charlie (Charlie most recent); Unread is never opened
      for (final i in [1, 0, 2]) {
        await lib.saveProgress(ids[i], 3);
        await Future<void>.delayed(const Duration(milliseconds: 4));
      }
      await lib.setOrder([ids[0], ids[1], ids[2], ids[3]]); // my order: Alpha, Bravo, Charlie, Unread
    }, h: 1500); // a tall screen: every Home card is laid out (the Quran cabinet sits above them)
    List<String> shownOrder() {
      final found = <(int, double)>[];
      for (var i = 0; i < ids.length; i++) {
        final f = find.byKey(Key('home-book-${ids[i]}'));
        if (f.evaluate().isNotEmpty) found.add((i, t.getTopLeft(f).dx));
      }
      found.sort((a, b) => a.$2.compareTo(b.$2));
      return [for (final f in found) ['Alpha', 'Bravo', 'Charlie', 'Unread'][f.$1]];
    }

    expect(shownOrder(), ['Charlie', 'Alpha', 'Bravo'], reason: 'most recently read first; unread books are not listed');
    await t.tap(find.byKey(const Key('home-reading-order')));
    await settleH(t);
    await t.tap(find.text('My order'));
    await settleH(t);
    expect(shownOrder(), ['Alpha', 'Bravo', 'Charlie']);
    expect(await t.runAsync(() => env.store.state('home_reading_order')), 'mine');
    await end(t);
  });
}
