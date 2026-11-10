import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:alarm/alarm.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';

import '../../planner/domain/reminders.dart';
import 'wav.dart';

/// Words in Urdu (Arabic) script need an Urdu voice.
bool isUrduScript(String s) => RegExp(r'[؀-ۿ]').hasMatch(s);

/// Turns words into speech in a sound file, on the phone (no internet).
abstract class SpeechMaker {
  /// Writes [text] spoken into [out] (a WAV file). False when the phone could not.
  Future<bool> make(String text, File out);

  /// Whether the phone has a voice that reads Urdu script.
  Future<bool> hasUrduVoice();
}

class TtsSpeechMaker implements SpeechMaker {
  FlutterTts? _tts;

  Future<FlutterTts> _engine() async {
    final t = _tts ??= FlutterTts();
    await t.awaitSynthCompletion(true);
    return t;
  }

  @override
  Future<bool> hasUrduVoice() async {
    try {
      final t = await _engine();
      return await t.isLanguageAvailable('ur-PK') == true || await t.isLanguageAvailable('ur') == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> make(String text, File out) async {
    try {
      final t = await _engine();
      await t.setLanguage(isUrduScript(text) ? 'ur-PK' : 'en-US');
      await t.setSpeechRate(.42); // slow and clear
      await t.setPitch(1.0);
      await t.setVolume(1.0);
      await out.parent.create(recursive: true);
      if (await out.exists()) await out.delete();
      await t.synthesizeToFile(text, out.path, true);
      // the engine may finish writing a moment after it reports done
      for (var i = 0; i < 40 && (!await out.exists() || await out.length() < 1000); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      return await out.exists() && await out.length() >= 1000;
    } catch (e) {
      debugPrint('Speech could not be made: $e');
      return false;
    }
  }
}

/// A prayer alarm sounding now.
class RingingAlarm {
  const RingingAlarm(this.id, this.title, this.body, this.payload);
  final int id;
  final String title, body;
  final String? payload;
}

/// What happened when the spoken / own-sound reminders were set.
class RingResult {
  const RingResult({this.ok = true, this.problem});

  /// False: the alarms could not be set at all (the caller falls back to ordinary notifications).
  final bool ok;

  /// Something the user should know (e.g. no Urdu voice on the phone).
  final String? problem;
}

/// Prayer reminders that speak or play a sound: rung by an alarm (sounds in silent mode, can keep going until
/// "I'm up"), not shown as a plain notification.
abstract class PrayerRinger {
  /// Call once at start-up: picks up an alarm that is ringing now (e.g. the one that opened the app).
  Future<void> start();

  /// Makes exactly [alarms] pending (each [Reminder] has [Reminder.speech] or [Reminder.sound]).
  Future<RingResult> replace(List<Reminder> alarms);

  /// Rings [r] at [Reminder.at] (a few seconds from now), to hear it.
  Future<RingResult> test(Reminder r);

  /// The prayer alarms sounding now.
  Stream<List<RingingAlarm>> get ringing;

  Future<void> stop(int id);
}

class NoopRinger implements PrayerRinger {
  @override
  Future<void> start() async {}
  @override
  Future<RingResult> replace(List<Reminder> alarms) async => const RingResult(ok: false);
  @override
  Future<RingResult> test(Reminder r) async => const RingResult(ok: false);
  @override
  Stream<List<RingingAlarm>> get ringing => const Stream.empty();
  @override
  Future<void> stop(int id) async {}
}

/// The id the "Try it" alarm uses.
const prayerTestAlarmId = prayerNotificationIds + 0xfff1;

/// Folder (in the app's documents) for the speech files.
const _voiceDir = 'prayer_voice';

/// Rings through the `alarm` plugin (Android alarm clock + a foreground service that plays the sound).
class AlarmRinger implements PrayerRinger {
  AlarmRinger({SpeechMaker? speech, Future<Directory> Function()? documents})
    : _speech = speech ?? TtsSpeechMaker(),
      _documents = documents ?? getApplicationDocumentsDirectory;
  final SpeechMaker _speech;
  final Future<Directory> Function() _documents;
  Future<bool>? _ready;
  Future<RingResult> _queue = Future.value(const RingResult());
  int _generation = 0;

  Future<bool> _init() => _ready ??= () async {
    try {
      await Alarm.init();
      return true;
    } catch (e) {
      debugPrint('Alarms unavailable: $e');
      return false;
    }
  }();

  @override
  Future<void> start() async {
    await _init();
  }

  @override
  Stream<List<RingingAlarm>> get ringing async* {
    if (!await _init()) return;
    yield* Alarm.ringing.map(
      (set) => [
        for (final a in set.alarms)
          RingingAlarm(a.id, a.notificationSettings.title, a.notificationSettings.body, a.payload),
      ],
    );
  }

  @override
  Future<void> stop(int id) async {
    if (await _init()) await Alarm.stop(id);
  }

  /// The sound file for [r], relative to the documents folder (null = the phone's alarm sound), and a problem to
  /// mention, if any.
  Future<(String?, String?)> _audioFor(Reminder r, Directory docs) async {
    final sound = r.sound;
    if (sound != null) {
      if (await File('${docs.path}/$sound').exists()) return (sound, null);
      return (null, 'Your sound file is missing; the phone\'s alarm sound is used instead. Choose it again.');
    }
    final words = r.speech;
    if (words == null || words.trim().isEmpty) return (null, null);
    final first = !r.payload.startsWith('prayer-again');
    final times = first ? 3 : 2;
    final name = sha1.convert(utf8.encode('v1|$times|$words')).toString().substring(0, 20);
    final rel = '$_voiceDir/$name.wav';
    final file = File('${docs.path}/$rel');
    if (await file.exists()) return (rel, null);
    if (isUrduScript(words) && !await _speech.hasUrduVoice()) {
      return (null, 'This phone has no Urdu voice, so the alarm sound plays instead. Write the words in English letters (Roman Urdu), or add an Urdu voice in the phone\'s text-to-speech settings.');
    }
    final raw = File('${docs.path}/$_voiceDir/$name.raw.wav');
    if (!await _speech.make(words, raw)) {
      return (null, 'The phone could not turn the words into speech, so the alarm sound plays instead. Check Settings → Text-to-speech on the phone.');
    }
    final pcm = readWav(await raw.readAsBytes());
    if (pcm == null) {
      await raw.rename(file.path); // not plain PCM: use it as it is
    } else {
      await file.writeAsBytes(repeatWithGaps(pcm, times: times), flush: true);
      await raw.delete();
    }
    return (rel, null);
  }

  AlarmSettings _settings(Reminder r, String? audio) {
    final again = r.payload.startsWith('prayer-again');
    return AlarmSettings(
      id: r.id,
      dateTime: r.at,
      assetAudioPath: audio,
      loopAudio: r.insistent,
      vibrate: true,
      // the "get up" reminder that keeps going is at full volume, and stays there
      volumeSettings: again && r.insistent ? const VolumeSettings.fixed(volume: 1, volumeEnforced: true) : const VolumeSettings.fixed(),
      notificationSettings: NotificationSettings(title: r.title, body: r.body, stopButton: "I'm up · اٹھ گیا"),
      warningNotificationOnKill: false,
      androidStopAlarmOnTermination: false,
      allowAlarmOverlap: true,
      allowSameSecondScheduling: true,
      androidStaleAfter: const Duration(minutes: 30),
      payload: r.payload,
    );
  }

  static bool _same(AlarmSettings a, AlarmSettings b) =>
      a.dateTime.millisecondsSinceEpoch == b.dateTime.millisecondsSinceEpoch &&
      a.assetAudioPath == b.assetAudioPath &&
      a.loopAudio == b.loopAudio &&
      a.notificationSettings.title == b.notificationSettings.title &&
      a.notificationSettings.body == b.notificationSettings.body &&
      a.volumeSettings.volume == b.volumeSettings.volume;

  @override
  Future<RingResult> replace(List<Reminder> alarms) {
    final gen = ++_generation;
    return _queue = _queue.then<RingResult>((_) async => gen == _generation ? await _replace(alarms) : const RingResult()).catchError((Object e) {
      debugPrint('Could not set prayer alarms: $e');
      return const RingResult(ok: false);
    });
  }

  Future<RingResult> _replace(List<Reminder> alarms) async {
    if (!await _init()) return const RingResult(ok: false);
    final docs = await _documents();
    String? problem;
    final want = <int, AlarmSettings>{};
    for (final r in alarms) {
      final (audio, p) = await _audioFor(r, docs);
      problem ??= p;
      want[r.id] = _settings(r, audio);
    }
    final have = {for (final a in await Alarm.getAlarms()) a.id: a};
    for (final id in have.keys) {
      if (!want.containsKey(id) && id != prayerTestAlarmId) await Alarm.stop(id);
    }
    for (final e in want.entries) {
      final old = have[e.key];
      if (old == null || !_same(old, e.value)) await Alarm.set(alarmSettings: e.value);
    }
    await _tidy(docs, {for (final a in want.values) ?a.assetAudioPath});
    return RingResult(problem: problem);
  }

  /// Removes speech files no alarm uses any more.
  Future<void> _tidy(Directory docs, Set<String> used) async {
    final d = Directory('${docs.path}/$_voiceDir');
    if (!await d.exists()) return;
    await for (final f in d.list()) {
      final rel = '$_voiceDir/${f.uri.pathSegments.last}';
      if (f is File && !used.contains(rel)) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }
  }

  @override
  Future<RingResult> test(Reminder r) async {
    if (!await _init()) return const RingResult(ok: false);
    try {
      final docs = await _documents();
      final (audio, problem) = await _audioFor(r, docs);
      await Alarm.set(alarmSettings: _settings(Reminder(id: prayerTestAlarmId, at: r.at, title: r.title, body: r.body, payload: r.payload, tone: r.tone, insistent: r.insistent, speech: r.speech, sound: r.sound), audio));
      return RingResult(problem: problem);
    } catch (e) {
      debugPrint('Could not ring the test alarm: $e');
      return const RingResult(ok: false);
    }
  }
}

final prayerRingerProvider = Provider<PrayerRinger>((_) {
  final mobile = !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);
  return mobile ? AlarmRinger() : NoopRinger();
});

/// The prayer alarms sounding now (shown full screen with an "I'm up" button).
final prayerRingingProvider = StreamProvider<List<RingingAlarm>>((ref) => ref.watch(prayerRingerProvider).ringing);

/// The last thing worth telling about the spoken reminders (null = all fine).
class RingProblem extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? v) => state = v;
}

final prayerRingProblemProvider = NotifierProvider<RingProblem, String?>(RingProblem.new);
