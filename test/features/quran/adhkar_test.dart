import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/features/quran/data/adhkar.dart';
import 'package:folio/features/quran/data/quran_data.dart';
import 'package:folio/features/quran/prayer/prayer.dart';
import 'package:folio/features/quran/presentation/adhkar_page.dart';

import '../../helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the bundled adhkar: 34, morning / evening / both, the Quranic ones point at the right ayahs', () async {
    final list = await loadAdhkarAsset();
    final q = await loadQuranAsset();
    expect(list.length, 34);
    expect(list.where((d) => d.forMorning()).length + list.where((d) => d.forEvening()).length, greaterThan(34));
    expect(list.every((d) => d.count >= 1 && (d.quran != null || (d.arabic.isNotEmpty && d.english.isNotEmpty))), isTrue);
    final quranic = {for (final d in list.where((d) => d.quran != null)) d.n: d.quran};
    expect(quranic, {2: (2, 255, 255), 3: (2, 285, 286), 4: (112, 1, 4), 5: (113, 1, 5), 6: (114, 1, 6)});
    for (final (s, from, to) in quranic.values.nonNulls) {
      expect(q.valid(s, from) && q.valid(s, to), isTrue);
    }
    expect(q.english[q.indexOf(2, 255)], startsWith('Allah - there is no deity except Him'));
    final evOnly = list.firstWhere((d) => d.n == 3);
    expect((evOnly.forMorning(), evOnly.forEvening()), (false, true), reason: 'the end of Al-Baqarah is for the night');
  });

  test('morning from Fajr until Asr, evening from Asr until the next Fajr', () {
    const lahore = PrayerSettings(lat: 31.5204, lng: 74.3587);
    final d = prayerDay(lahore, DateTime(2026, 11, 10));
    expect(isMorningNow(lahore, d.times[Prayer.fajr]!.add(const Duration(minutes: 5))), isTrue);
    expect(isMorningNow(lahore, d.times[Prayer.asr]!.subtract(const Duration(minutes: 1))), isTrue);
    expect(isMorningNow(lahore, d.times[Prayer.asr]!.add(const Duration(minutes: 1))), isFalse);
    expect(isMorningNow(lahore, d.times[Prayer.fajr]!.subtract(const Duration(minutes: 1))), isFalse);
    expect(isMorningNow(const PrayerSettings(), DateTime(2026, 11, 10, 8)), isTrue);
  });

  Future<void> wait(WidgetTester t, [int rounds = 8]) async {
    for (var i = 0; i < rounds; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('from the Quran: morning or evening, tick what you said (remembered), Ayat al-Kursi in the Quran\'s own text', (t) async {
    t.view.physicalSize = const Size(411, 1400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final env = await TestEnv.create();
    addTearDown(env.db.close);
    await t.pumpWidget(env.app);
    await wait(t, 14);
    await t.tap(find.byKey(const Key('quran-open')));
    await wait(t, 10);
    await t.tap(find.byKey(const Key('quran-adhkar')));
    await wait(t, 10);
    await t.tap(find.byKey(const Key('adhkar-morning')));
    await wait(t, 3);
    final q = await t.runAsync(loadQuranAsset);
    expect(t.widget<Text>(find.byKey(const Key('dhikr-arabic-2'))).data, startsWith(q!.arabic[q.indexOf(2, 255)]));
    expect(find.byKey(const Key('dhikr-3')), findsNothing, reason: 'evening only');
    final list = find.descendant(of: find.byKey(const Key('adhkar-list')), matching: find.byType(Scrollable)).first;
    await t.scrollUntilVisible(find.byKey(const Key('dhikr-count-4')), 300, scrollable: list);
    expect(t.widget<Text>(find.byKey(const Key('dhikr-count-4'))).data, '3 times');
    await t.scrollUntilVisible(find.byKey(const Key('adhkar-progress')), -300, scrollable: list);
    await t.scrollUntilVisible(find.byKey(const Key('dhikr-done-2')), 100, scrollable: list);
    final total = int.parse(RegExp(r'of (\d+)').firstMatch(t.widget<Text>(find.byKey(const Key('adhkar-progress'))).data!)!.group(1)!);
    await t.tap(find.byKey(const Key('dhikr-done-2')));
    await wait(t, 3);
    await t.scrollUntilVisible(find.byKey(const Key('adhkar-progress')), -300, scrollable: list);
    expect(t.widget<Text>(find.byKey(const Key('adhkar-progress'))).data, '1 of $total said today');
    expect(await t.runAsync(() => env.store.state('adhkar_done')), contains('m":[2]'));

    await t.tap(find.byKey(const Key('adhkar-evening')));
    await wait(t, 3);
    await t.scrollUntilVisible(find.byKey(const Key('dhikr-3')), 300, scrollable: list);
    expect(find.byKey(const Key('dhikr-3')), findsOneWidget);
    await t.scrollUntilVisible(find.byKey(const Key('adhkar-progress')), -300, scrollable: list);
    expect(t.widget<Text>(find.byKey(const Key('adhkar-progress'))).data, startsWith('0 of'));
    // a dhikr that is not from the Quran shows the Hisn al-Muslim English
    await t.scrollUntilVisible(find.byKey(const Key('dhikr-english-8')), 300, scrollable: list);
    expect(t.widget<Text>(find.byKey(const Key('dhikr-english-8'))).data, startsWith('We have reached the evening'));
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  });
}
