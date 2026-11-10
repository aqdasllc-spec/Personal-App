import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/features/library/application/read_aloud.dart' show mediaControlsProvider;
import 'package:folio/features/quran/application/quran_audio.dart';
import 'package:folio/features/quran/data/quran_data.dart';

import '../../helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late QuranData q;
  setUpAll(() async => q = await loadQuranAsset());

  String name(Uri u) => u.scheme == 'silence' ? 'pause${u.path}' : u.pathSegments.last.replaceAll('.mp3', '');

  test('each ayah 3x with a 2 s pause, the selection twice; Next and Previous stay in the round', () async {
    final player = FakeAyahPlayer();
    final c = ProviderContainer(overrides: [
      ayahPlayerFactoryProvider.overrideWithValue(() => player),
      mediaControlsProvider.overrideWithValue(FakeMediaControls()),
    ]);
    addTearDown(c.dispose);
    final audio = c.read(quranAudioProvider.notifier);
    await audio.playFrom(q, 112, 1, to: 2, repeat: const RepeatPlan(eachAyah: 3, rounds: 2, pause: Duration(seconds: 2)));
    await pumpEventQueue();
    final first = q.indexOf(112, 1) + 1;
    final a1 = '$first', a2 = '${first + 1}';
    expect(player.queue.map(name).toList(), [
      a1, 'pause2000', a1, 'pause2000', a1, 'pause2000', a2, 'pause2000', a2, 'pause2000', a2, 'pause2000', // round 1
      a1, 'pause2000', a1, 'pause2000', a1, 'pause2000', a2, 'pause2000', a2, 'pause2000', a2, // round 2: no pause at the very end
    ]);
    var s = c.read(quranAudioProvider);
    expect((s.ayah, s.repeat, s.repeats, s.round, s.rounds), (1, 1, 3, 1, 2));
    player.finishCurrent(); // pause
    player.finishCurrent(); // second recitation
    await pumpEventQueue();
    s = c.read(quranAudioProvider);
    expect((s.ayah, s.repeat), (1, 2));
    await audio.next();
    await pumpEventQueue();
    s = c.read(quranAudioProvider);
    expect((s.ayah, s.repeat, s.round), (2, 1, 1), reason: 'Next: the first recitation of the next ayah');
    await audio.next();
    await pumpEventQueue();
    expect(c.read(quranAudioProvider).ayah, 2, reason: 'no ayah after the selection in this round');
    await audio.previous();
    await pumpEventQueue();
    s = c.read(quranAudioProvider);
    expect((s.ayah, s.repeat, s.round), (1, 1, 1));
    await player.seekToIndex(12); // round 2 starts
    await pumpEventQueue();
    s = c.read(quranAudioProvider);
    expect((s.ayah, s.round), (1, 2));
  });

  test('plain listening is unchanged: each ayah once, no pauses', () async {
    final player = FakeAyahPlayer();
    final c = ProviderContainer(overrides: [
      ayahPlayerFactoryProvider.overrideWithValue(() => player),
      mediaControlsProvider.overrideWithValue(FakeMediaControls()),
    ]);
    addTearDown(c.dispose);
    await c.read(quranAudioProvider.notifier).playFrom(q, 1, 5);
    await pumpEventQueue();
    expect(player.queue.map(name).toList(), ['5', '6', '7']);
    expect(c.read(quranAudioProvider).repeats, 1);
  });

  testWidgets('Hifz sheet: choose ayahs and repeats, hide the Arabic, tap to show; the bar says which repeat', (t) async {
    t.view.physicalSize = const Size(411, 1400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final env = await TestEnv.create();
    addTearDown(env.db.close);
    await t.pumpWidget(env.app);
    Future<void> wait([int rounds = 8]) async {
      for (var i = 0; i < rounds; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 120)));
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    await wait(14);
    await t.tap(find.byKey(const Key('quran-open')));
    await wait(10);
    await t.tap(find.byKey(const Key('surah-1')));
    await wait(8);
    await t.tap(find.byKey(const Key('hifz-open')));
    await wait(6);
    await t.tap(find.byKey(const Key('hifz-each-5')));
    await t.tap(find.byKey(const Key('hifz-rounds-2')));
    await wait(2);
    await t.ensureVisible(find.byKey(const Key('hifz-hide')));
    await t.tap(find.byKey(const Key('hifz-hide')));
    await wait(2);
    expect(t.widget<Text>(find.byKey(const Key('hifz-summary'))).data, contains('each 5×, the whole selection 2×'));
    expect(await t.runAsync(() => env.store.state('quran_hifz')), '5,2,0,1');
    await t.ensureVisible(find.byKey(const Key('hifz-start')));
    await t.tap(find.byKey(const Key('hifz-start')));
    await wait(6);
    expect(env.ayahPlayer.queue.length, 5 * 5 * 2, reason: 'ayahs 1-5, each 5×, twice');
    expect(t.widget<Text>(find.byKey(const Key('audio-subtitle'))).data, startsWith('repeat 1/5 · round 1/2'));
    expect(find.byKey(const Key('arabic-1-1')), findsNothing, reason: 'hidden');
    await t.tap(find.byKey(const Key('reveal-1-1')));
    await wait(2);
    expect(find.byKey(const Key('arabic-1-1')), findsOneWidget);
    expect(find.byKey(const Key('reveal-1-2')), findsOneWidget, reason: 'the others stay hidden');
    await t.tap(find.byKey(const Key('audio-stop')));
    await wait(2);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  });
}
