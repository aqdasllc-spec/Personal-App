import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/features/planner/application/planner_controller.dart' show reminderSchedulerProvider;
import 'package:folio/features/planner/data/reminder_scheduler.dart';
import 'package:folio/features/planner/domain/reminders.dart';
import 'package:folio/features/quran/application/quran_audio.dart';
import 'package:folio/features/quran/application/quran_downloads.dart';
import 'package:folio/features/quran/application/quran_providers.dart';
import 'package:folio/features/quran/data/quran_data.dart';
import 'package:folio/features/quran/domain/daily.dart';

import '../../helpers.dart';

class _Sched extends NoopReminderScheduler {
  List<Reminder> daily = [];
  @override
  Future<void> replaceDailyAyahAlarms(List<Reminder> alarms) async => daily = alarms;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late QuranData q;
  setUpAll(() async => q = await loadQuranAsset());

  Future<(ProviderContainer, Directory, List<Uri>)> setup({bool Function(Uri)? failing}) async {
    final env = await TestEnv.create();
    addTearDown(env.db.close);
    final dir = await Directory.systemTemp.createTemp('qaudio');
    addTearDown(() => dir.delete(recursive: true));
    final fetched = <Uri>[];
    final c = ProviderContainer(overrides: [
      ...env.overrides,
      quranAudioDirProvider.overrideWith((_) async => dir),
      quranLoaderProvider.overrideWithValue(() async => q),
      fileFetcherProvider.overrideWithValue((url, into) async {
        if (failing?.call(url) ?? false) throw const SocketException('no network');
        fetched.add(url);
        await into.writeAsBytes([0x49, 0x44, 0x33, 1, 2, 3]);
      }),
    ]);
    addTearDown(c.dispose);
    await c.read(quranAudioDirProvider.future);
    return (c, dir, fetched);
  }

  test('download a surah: its files are saved, then played from the phone instead of the internet', () async {
    final (c, dir, fetched) = await setup();
    final r = c.read(reciterProvider);
    final d = c.read(quranDownloadsProvider.notifier);
    await d.downloadSurah(q, r, 1);
    final job = c.read(quranDownloadsProvider)!;
    expect((job.done, job.total, job.running, job.error), (7, 7, false, null));
    expect(fetched.map((u) => u.pathSegments.last), unorderedEquals(['1.mp3', '2.mp3', '3.mp3', '4.mp3', '5.mp3', '6.mp3', '7.mp3']));
    expect(await d.countHere(r, 0, 6), 7);
    expect(await d.bytesHere(r), 7 * 6);
    final resolve = c.read(ayahUriResolverProvider);
    expect(resolve(r, 1).scheme, 'file');
    expect(resolve(r, 8).scheme, 'https', reason: 'not downloaded: streamed');

    fetched.clear();
    await d.downloadSurah(q, r, 1);
    expect(fetched, isEmpty, reason: 'files already there are skipped');

    await d.deleteAll(r);
    expect(await d.countHere(r, 0, 6), 0);
    expect(c.read(ayahUriResolverProvider)(r, 1).scheme, 'https');
  });

  test('a failing download stops with a clear message and continues later where it stopped', () async {
    var broken = true;
    final (c, _, fetched) = await setup(failing: (u) => broken && u.pathSegments.last == '5.mp3');
    final r = c.read(reciterProvider);
    final d = c.read(quranDownloadsProvider.notifier);
    await d.downloadSurah(q, r, 1);
    final job = c.read(quranDownloadsProvider)!;
    expect(job.running, isFalse);
    expect(job.error, contains('could not download ayah 5'));
    expect(job.error, contains('continues where it stopped'));
    broken = false;
    fetched.clear();
    await d.downloadSurah(q, r, 1);
    expect(c.read(quranDownloadsProvider)!.error, isNull);
    expect(await d.countHere(r, 0, 6), 7);
    expect(fetched.length, lessThan(7), reason: 'only what was missing');
  });

  test('size estimate before downloading the whole Quran', () {
    expect(wholeQuranSize(reciters.first), 'about 1.6 GB');
    expect(wholeQuranSize(reciters.firstWhere((r) => r.bitrate == 64)), 'about 813 MB');
  });

  test('morning ayah notification: a week ahead with each day\'s ayah, in the Home card\'s language; off clears', () async {
    final env = await TestEnv.create();
    addTearDown(env.db.close);
    final sched = _Sched();
    final c = ProviderContainer(overrides: [
      ...env.overrides,
      reminderSchedulerProvider.overrideWithValue(sched),
      quranLoaderProvider.overrideWithValue(() async => q),
    ]);
    addTearDown(c.dispose);
    final n = c.read(dailyAyahNotifyProvider.notifier);
    await pumpEventQueue();
    await n.set((hour: 7, minute: 0));
    final now = DateTime(2026, 11, 10, 9);
    await n.resync(now: now);
    expect(sched.daily.length, 6, reason: "today's 7:00 has passed: the next six mornings");
    expect(sched.daily.every((r) => r.at.hour == 7 && r.at.isAfter(now)), isTrue);
    expect(sched.daily.every((r) => r.id >= dailyAyahNotificationIds && r.id < dailyAyahNotificationIds + 0x10000), isTrue);
    expect(sched.daily.map((r) => r.id).toSet().length, 6);
    final first = sched.daily.first;
    final a = dailyAyah(q, first.at);
    expect(first.title, startsWith('آج کی آیت'), reason: 'Urdu by default');
    expect(first.body, startsWith(a.urdu.first.substring(0, 20)));
    c.read(dailyLangProvider.notifier).set(DailyLang.english);
    await n.resync(now: now);
    expect(sched.daily.first.title, 'Ayah of the day · ${a.surah.name} ${a.ref}');
    await n.set(null);
    expect(sched.daily, isEmpty);
    expect(await env.store.state('quran_daily_notify'), '');
  });
}
