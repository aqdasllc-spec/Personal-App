import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/features/library/data/library_repository.dart';
import 'package:folio/features/library/domain_reading_stats.dart';

import '../../helpers.dart';
import '../library/reader_settings_test.dart' show io;

Set<String> days(List<String> d) => d.toSet();

void main() {
  group('domain', () {
    final today = DateTime(2026, 11, 8);
    test('dayKey pads', () {
      expect(dayKey(DateTime(2026, 3, 4)), '2026-03-04');
    });

    test('streak: counts back from today, or from yesterday while today is still empty; a gap ends it', () {
      expect(currentStreak(days(['2026-11-08', '2026-11-07', '2026-11-06']), today), 3);
      expect(currentStreak(days(['2026-11-07', '2026-11-06']), today), 2, reason: 'today not read yet: still alive');
      expect(currentStreak(days(['2026-11-06', '2026-11-05']), today), 0, reason: 'yesterday missed: over');
      expect(currentStreak(days(['2026-11-08', '2026-11-06']), today), 1);
      expect(currentStreak({}, today), 0);
    });

    test('streak crosses month and year ends', () {
      expect(currentStreak(days(['2027-01-01', '2026-12-31', '2026-12-30']), DateTime(2027, 1, 1)), 3);
      expect(currentStreak(days(['2026-03-01', '2026-02-28']), DateTime(2026, 3, 1)), 2);
    });

    test('best streak is the longest run ever', () {
      expect(bestStreak(days(['2026-10-01', '2026-10-02', '2026-10-03', '2026-10-10', '2026-10-11'])), 3);
      expect(bestStreak({}), 0);
      expect(bestStreak(days(['2026-10-31', '2026-11-01'])), 2);
    });

    test('last days, week time, and labels', () {
      final stats = [const DayStat('2026-11-08', 5, 600), const DayStat('2026-11-06', 2, 900), const DayStat('2026-10-01', 9, 99999)];
      expect(lastDays(stats, today), [0, 0, 0, 0, 2, 0, 5]);
      expect(secondsInLast(stats, today), 1500);
      expect(readingDays(stats), {'2026-11-08', '2026-11-06', '2026-10-01'});
      expect(readingTimeLabel(20), 'under a minute');
      expect(readingTimeLabel(42 * 60), '42 min');
      expect(readingTimeLabel(65 * 60), '1 h 05 min');
    });
  });

  group('repository', () {
    test('a page counts once per day; time adds up; stats list days with reading', () async {
      var now = DateTime(2026, 11, 8, 9);
      final env = await TestEnv.create();
      addTearDown(env.db.close);
      final repo = LibraryRepository(env.db, directory: env.libraryDir, inspector: FakePdfInspector(), now: () => now);
      await repo.markPageRead('b1', 3);
      await repo.markPageRead('b1', 3);
      await repo.markPageRead('b1', 4);
      await repo.markPageRead('b2', 3);
      await repo.addReadingSeconds(15);
      await repo.addReadingSeconds(30);
      now = DateTime(2026, 11, 9, 23, 59);
      await repo.markPageRead('b1', 3); // same page, next day: counts again
      await repo.addReadingSeconds(0); // nothing
      final s = await repo.watchReadingStats().first;
      expect(s.map((d) => '${d.day}:${d.pages}:${d.seconds}').toList(), ['2026-11-08:3:45', '2026-11-09:1:0']);
    });
  });

  group('Home', () {
    Future<(TestEnv, BookRow)> open(WidgetTester t, {Future<void> Function(LibraryRepository, BookRow)? seed}) async {
      t.view.physicalSize = const Size(411, 1200);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final env = await TestEnv.create();
      addTearDown(env.db.close);
      late BookRow b;
      await t.runAsync(() async {
        final repo = LibraryRepository(env.db, directory: env.libraryDir, inspector: FakePdfInspector());
        b = (await repo.importPdf(await env.writePdf('x.pdf', 20))).book!;
        if (seed != null) await seed(repo, b);
      });
      await t.pumpWidget(env.app);
      await io(t);
      return (env, b);
    }

    Future<void> endIt(WidgetTester t) async {
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
    }

    testWidgets('no reading yet: an invitation, and the goal can still be set', (t) async {
      final (env, _) = await open(t);
      expect(find.byKey(const Key('stats-empty')), findsOneWidget);
      expect(find.text('Goal: 10 pages a day'), findsOneWidget);
      await t.ensureVisible(find.byKey(const Key('reading-goal-edit')));
      await t.tap(find.byKey(const Key('reading-goal-edit')));
      await io(t, rounds: 3);
      for (var i = 0; i < 2; i++) {
        await t.tap(find.byKey(const Key('goal-plus')));
        await io(t, rounds: 1);
      }
      expect(find.text('12 pages'), findsOneWidget);
      await t.tap(find.byKey(const Key('goal-save')));
      await io(t, rounds: 3);
      expect(find.text('Goal: 12 pages a day'), findsOneWidget);
      expect(await t.runAsync(() => env.store.state('read_goal')), '12');
      await endIt(t);
    });

    testWidgets('with reading: pages today against the goal, streak, week summary, goal reached', (t) async {
      final now = DateTime.now();
      final (_, _) = await open(t, seed: (repo, b) async {
        for (var p = 1; p <= 10; p++) {
          await repo.markPageRead(b.id, p);
        }
        await repo.addReadingSeconds(1800);
      });
      await t.ensureVisible(find.byKey(const Key('stats-today')));
      expect(find.text('10 of 10 pages today'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget, reason: 'goal reached');
      expect(find.text('1-day streak'), findsOneWidget);
      expect(find.text('Best: 1'), findsOneWidget);
      expect(find.text('Last 7 days: 10 pages · 30 min with a book open'), findsOneWidget);
      expect(find.byKey(const Key('stats-bar-6')), findsOneWidget);
      expect(now.year, greaterThan(2000));
      await endIt(t);
    });
  });

  group('reader', () {
    testWidgets('a page counts as read after a few seconds on it, not when flipped past; time ticks while open', (t) async {
      t.view.physicalSize = const Size(411, 890);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final env = await TestEnv.create();
      addTearDown(env.db.close);
      late BookRow b;
      await t.runAsync(() async {
        final repo = LibraryRepository(env.db, directory: env.libraryDir, inspector: FakePdfInspector());
        b = (await repo.importPdf(await env.writePdf('x.pdf', 20))).book!;
      });
      await t.pumpWidget(env.app);
      await io(t);
      await t.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Library')));
      await io(t);
      await t.tap(find.byKey(Key('book-${b.id}')));
      await io(t);
      // quickly through pages 5 and 6, then rest on 7
      await t.tap(find.text('go to page 7'));
      await t.pump(const Duration(seconds: 1));
      await t.tap(find.text('tap right'));
      await t.pump(const Duration(seconds: 1));
      await t.tap(find.text('go to page 7'));
      await t.pump(const Duration(seconds: 5));
      await io(t, rounds: 4);
      final pages = (await t.runAsync(() => env.db.select(env.db.readPages).get()))!.map((r) => r.page).toSet();
      expect(pages, contains(7));
      expect(pages, isNot(contains(8)), reason: 'flipped past too fast');
      await t.pump(const Duration(seconds: 31));
      await io(t, rounds: 4);
      final secs = (await t.runAsync(() => env.db.select(env.db.readTime).get()))!.fold<int>(0, (a, r) => a + r.seconds);
      expect(secs, greaterThanOrEqualTo(30));
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
    });
  });
}
