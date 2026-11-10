import 'dart:async';

import 'package:flutter/material.dart';
import 'package:folio/app/router.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/features/quran/data/quran_data.dart';
import 'package:folio/features/quran/domain/khatm.dart';

import '../../helpers.dart';

void main() {
  final day1 = DateTime(2026, 11, 1);

  group('plan arithmetic', () {
    test('30 days from Al-Fatiha: about 21 pages a day, spread so the last day ends on page 604', () {
      final p = KhatmPlan(start: day1, days: 30, donePage: 0);
      expect(p.expectedBy(0), 0);
      expect(p.expectedBy(1), 21);
      expect(p.expectedBy(15), 302);
      expect(p.expectedBy(30), 604);
      final t = khatmToday(p, day1.add(const Duration(hours: 10)));
      expect((t.day, t.from, t.to, t.status), (1, 1, 21, KhatmStatus.onTrack));
    });

    test('reading today\'s pages marks the day done; missing a day shows how far behind, folded into today', () {
      var p = KhatmPlan(start: day1, days: 30, donePage: 0).withDone(21);
      expect(khatmToday(p, day1).status, KhatmStatus.doneToday);
      expect(khatmToday(p, day1).from, 1, reason: 'the finished portion is still shown');
      final day3 = day1.add(const Duration(days: 2));
      final t = khatmToday(p, day3);
      expect(t.status, KhatmStatus.behind);
      expect(t.behindBy, 41 - 21);
      expect((t.from, t.to), (22, 61), reason: 'yesterday\'s pages and today\'s');
      p = p.withDone(10);
      expect(p.donePage, 21, reason: 'reading an earlier page again never moves you back');
    });

    test('starting where you are; finishing; past the end; saving', () {
      final p = KhatmPlan(start: day1, days: 10, startPage: 302, donePage: 301);
      expect(p.totalPages, 303);
      expect(p.expectedBy(1), 301 + 31);
      final done = p.withDone(604);
      expect(done.finished, isTrue);
      expect(done.progress, 1.0);
      expect(khatmToday(done, day1).status, KhatmStatus.finished);
      expect(p.dayOf(day1.add(const Duration(days: 40))), 10, reason: 'after the last day it stays on the last day');
      final back = KhatmPlan.decode(p.encode())!;
      expect((back.days, back.startPage, back.donePage, back.start), (p.days, p.startPage, p.donePage, p.start));
      expect(KhatmPlan.decode('{"days":0,"from":1,"start":0,"done":0}'), isNull);
    });

    test('Madinah mushaf pages: 604, in order, Al-Baqara starts on page 2', () async {
      final q = await loadQuranAsset();
      expect(q.pages.length, 6236);
      expect(q.pageOf(0), 1);
      expect(q.pageOf(q.indexOf(2, 1)), 2);
      expect(q.pageOf(6235), 604);
      expect(q.firstOnPage(2), q.indexOf(2, 1));
      expect(q.firstOnPage(604), lessThan(6236));
      for (var p = 1; p <= 604; p += 37) {
        final i = q.firstOnPage(p);
        expect(q.pageOf(i), p);
        expect(i == 0 || q.pageOf(i - 1) == p - 1, isTrue);
      }
    });
  });

  group('in the Quran (through the real app)', () {
    Future<void> wait(WidgetTester t, [int rounds = 10]) async {
      for (var i = 0; i < rounds; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 120)));
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('set a 30-day goal; today\'s portion opens at the right place; reading moves the plan forward', (t) async {
      t.view.physicalSize = const Size(411, 1400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final env = await TestEnv.create();
      addTearDown(env.db.close);
      await t.pumpWidget(env.app);
      await wait(t, 14);
      await t.tap(find.byKey(const Key('quran-open')));
      await wait(t, 10);
      await t.tap(find.byKey(const Key('khatm-set')));
      await wait(t, 4);
      await t.tap(find.byKey(const Key('khatm-days-30')));
      await wait(t, 2);
      expect(find.textContaining('About 21 pages a day'), findsOneWidget);
      await t.tap(find.byKey(const Key('khatm-start')));
      await wait(t, 4);
      expect(find.text('Khatm · day 1 of 30'), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const Key('khatm-today'))).data, startsWith('Today: pages 1-21'));
      expect(await t.runAsync(() => env.store.state('quran_khatm')), contains('"days":30'));

      // read on to page 21's end: the first ayah of page 22 is where you are now
      final q = await t.runAsync(loadQuranAsset);
      final (s, a) = q!.refOf(q.firstOnPage(22));
      await t.tap(find.byKey(const Key('khatm-read')));
      await wait(t, 8);
      expect(find.byKey(const Key('ayah-list')), findsOneWidget);
      await t.pageBack();
      await wait(t, 4);
      // open that ayah (as a link from today's portion would)
      unawaited(GoRouter.of(t.element(find.byKey(const Key('surah-list')))).push('${Routes.quran}/$s?ayah=$a'));
      await wait(t, 8);
      await t.tap(find.byKey(Key('mark-$s-$a')));
      await wait(t, 4);
      await t.pageBack();
      await wait(t, 6);
      expect(t.widget<Text>(find.byKey(const Key('khatm-status'))).data, "Today's portion is done");
      expect(find.textContaining('21 of 604 pages'), findsOneWidget);

      // Home shows it under the Quran
      await t.pageBack();
      await wait(t, 6);
      expect(find.byKey(const Key('khatm-label')), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
    });
  });
}
