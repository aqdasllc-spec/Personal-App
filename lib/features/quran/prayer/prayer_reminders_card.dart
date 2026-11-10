import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../design_system/tokens.dart';
import '../../planner/application/planner_controller.dart' show reminderSchedulerProvider;
import '../../planner/domain/reminders.dart';
import '../presentation/quran_style.dart';
import 'battery.dart';
import 'prayer.dart';
import 'prayer_providers.dart';
import 'prayer_ringer.dart';

/// Lets the user choose a sound file (e.g. an Azan) and keeps a copy for the alarm. Returns the copy's path relative to
/// the app's documents folder, or null if nothing was chosen. A function so tests need no file picker.
final prayerSoundPickerProvider = Provider<Future<String?> Function()>((_) => () async {
  final picked = await FilePicker.pickFiles(type: FileType.audio);
  final path = picked.singleOrNull?.path;
  if (path == null) return null;
  final docs = await getApplicationDocumentsDirectory();
  final name = path.split(Platform.pathSeparator).last.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  final rel = 'prayer_sounds/${DateTime.now().millisecondsSinceEpoch}_$name';
  final dest = File('${docs.path}/$rel');
  await dest.parent.create(recursive: true);
  await File(path).copy(dest.path);
  return rel;
});

/// The name to show for a chosen sound file.
String soundName(String? rel) {
  if (rel == null) return '';
  final last = rel.split('/').last;
  final cut = last.indexOf('_');
  return cut > 0 && int.tryParse(last.substring(0, cut)) != null ? last.substring(cut + 1) : last;
}

/// How each prayer's reminder sounds, the second "get up" reminder (its words and when), and what keeps them reliable.
class PrayerRemindersCard extends ConsumerStatefulWidget {
  const PrayerRemindersCard({super.key, required this.now});
  final DateTime now;
  @override
  ConsumerState<PrayerRemindersCard> createState() => _PrayerRemindersCardState();
}

class _PrayerRemindersCardState extends ConsumerState<PrayerRemindersCard> with WidgetsBindingObserver {
  late final TextEditingController _words;
  Timer? _save;

  PrayerSettings get _cur => ref.read(prayerSettingsProvider);
  void _set(PrayerSettings v) => ref.read(prayerSettingsProvider.notifier).set(v);

  @override
  void initState() {
    super.initState();
    _words = TextEditingController(text: _cur.secondWords);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // back from the phone's battery settings: look again
    if (state == AppLifecycleState.resumed) ref.invalidate(batteryUnrestrictedProvider);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_save?.isActive ?? false) {
      _save!.cancel();
      _commitWords();
    }
    _words.dispose();
    super.dispose();
  }

  void _commitWords() {
    final w = _words.text.trim();
    if (w != _cur.secondWords) _set(_cur.copyWith(secondWords: w.isEmpty ? defaultGetUpWords : w));
  }

  /// Picks a sound file; null when none was chosen (or it failed, which is said).
  Future<String?> _pickSound() async {
    try {
      return await ref.read(prayerSoundPickerProvider)();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not use that file: $e')));
      }
      return null;
    }
  }

  Future<void> _chooseTone(Prayer p, PrayerTone t) async {
    if (t == PrayerTone.own) {
      final file = await _pickSound();
      if (file == null) return;
      _set(_cur.withTone(p, t, sound: file));
    } else {
      _set(_cur.withTone(p, t));
    }
  }

  Future<void> _chooseSecondTone(PrayerTone t) async {
    if (t == PrayerTone.own) {
      final file = await _pickSound();
      if (file == null) return;
      _set(_cur.copyWith(secondTone: t, secondSound: file));
    } else {
      _set(_cur.copyWith(secondTone: t));
    }
  }

  Future<void> _tryIt(bool again) async {
    if (_save?.isActive ?? false) {
      _save!.cancel();
      _commitWords();
    }
    final sched = ref.read(reminderSchedulerProvider);
    if (!await sched.hasPermission()) await sched.requestPermission();
    final c = _cur;
    final n = prayerNow(c, widget.now);
    final p = n.next == Prayer.sunrise ? Prayer.dhuhr : n.next;
    final at = DateTime.now().add(const Duration(seconds: 5));
    final tone = again ? c.secondTone : c.toneOf(p);
    final r = Reminder(
      id: 0,
      at: at,
      title: again ? 'Get up for ${p.salahOn(at)} · اٹھیں، ${p.salahUrduOn(at)} ادا کریں' : '${p.salahOn(at)} · ${p.salahUrduOn(at)}',
      body: again ? 'This is how the second reminder will sound.' : 'This is how the reminder will sound.',
      payload: again ? 'prayer-again:test' : 'prayer:test',
      tone: tone.name,
      insistent: again ? c.secondKeepRinging : (tone.rings && c.firstKeepRinging),
      speech: switch (tone) {
        PrayerTone.spoken => spokenName(p, at),
        PrayerTone.voice => getUpSpeech(c.secondWords, p, at),
        _ => null,
      },
      sound: tone == PrayerTone.own ? (again ? c.secondSound : c.sounds[p]) : null,
    );
    String message;
    if (tone.rings) {
      final res = await ref.read(prayerRingerProvider).test(r);
      message = res.ok
          ? (res.problem ?? 'It will sound in 5 seconds. Tap "I\'m up" to stop it.')
          : 'Spoken reminders are not available on this phone; it will come as a loud notification.';
      if (!res.ok) await sched.testPrayerAlarm(Reminder(id: 0, at: at, title: r.title, body: r.body, payload: r.payload, tone: PrayerTone.alarm.name, insistent: r.insistent));
    } else {
      final ok = await sched.testPrayerAlarm(r);
      message = ok ? 'It will come in 5 seconds. You can lock the screen to see how it looks.' : 'Notifications are not allowed for Folio. Allow them in the phone\'s settings.';
    }
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _toneMenu(Key key, String label, PrayerTone value, List<PrayerTone> options, void Function(PrayerTone) pick) =>
      DropdownButtonFormField<PrayerTone>(
        key: key,
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
        items: [for (final v in options) DropdownMenuItem(value: v, child: Text(v.label, overflow: TextOverflow.ellipsis))],
        onChanged: (v) => v == null ? null : pick(v),
      );

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(prayerSettingsProvider);
    final t = Theme.of(context).textTheme;
    final c = context.colors;
    final now = widget.now;
    final alerted = [for (final p in Prayer.values) if (s.alerts.contains(p)) p];
    final anyRings = alerted.any((p) => s.toneOf(p).rings);
    final second = s.secondAfterSeconds > 0;
    final mins = s.secondAfterSeconds ~/ 60, secs = s.secondAfterSeconds % 60;
    final firstTones = [for (final v in PrayerTone.values) if (v != PrayerTone.voice) v];
    final problem = ref.watch(prayerRingProblemProvider);
    final until = ref.watch(prayerScheduledUntilProvider);
    final battery = ref.watch(batteryUnrestrictedProvider).value;
    final sample = getUpSpeech(_words.text, Prayer.fajr, now);
    final urduNoVoice = s.secondTone == PrayerTone.voice && isUrduScript(_words.text);

    return Card(
      key: const Key('prayer-reminders'),
      child: Padding(
        padding: const EdgeInsets.all(Space.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Reminders', style: t.titleMedium),
            if (alerted.isEmpty)
              Text('Tap the bell next to a prayer above to be reminded of it.', style: t.bodySmall)
            else ...[
              Text('At the prayer time', style: t.bodySmall),
              const SizedBox(height: Space.s12),
              for (final p in alerted) ...[
                Row(
                  children: [
                    SizedBox(
                      width: 92,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.english, style: t.titleSmall),
                          Text(p.urdu, textDirection: TextDirection.rtl, style: urduText(13, color: c.textMuted)),
                        ],
                      ),
                    ),
                    Expanded(child: _toneMenu(Key('prayer-tone-${p.name}'), 'Sound', s.toneOf(p), firstTones, (v) => _chooseTone(p, v))),
                  ],
                ),
                if (s.toneOf(p) == PrayerTone.own)
                  Padding(
                    padding: const EdgeInsets.only(left: 92),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            s.sounds[p] == null ? 'No file chosen yet' : soundName(s.sounds[p]),
                            overflow: TextOverflow.ellipsis,
                            style: t.bodySmall,
                          ),
                        ),
                        TextButton(
                          key: Key('prayer-sound-${p.name}'),
                          onPressed: () => _chooseTone(p, PrayerTone.own),
                          child: const Text('Change'),
                        ),
                      ],
                    ),
                  ),
                if (s.toneOf(p) == PrayerTone.spoken)
                  Padding(
                    padding: const EdgeInsets.only(left: 92, top: Space.s4),
                    child: Text('Says “${spokenName(p, now)}”', style: t.bodySmall?.copyWith(color: QuranColors.goldDeep)),
                  ),
                const SizedBox(height: Space.s12),
              ],
              if (anyRings)
                SwitchListTile(
                  key: const Key('first-insistent'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Keep sounding until I tap “I’m up”'),
                  subtitle: const Text('Otherwise it says it three times and stops'),
                  value: s.firstKeepRinging,
                  onChanged: (v) => _set(_cur.copyWith(firstKeepRinging: v)),
                ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(key: const Key('prayer-test'), onPressed: () => _tryIt(false), icon: const Icon(Icons.play_circle_outline), label: const Text('Try it')),
              ),
            ],
            const Divider(),
            SwitchListTile(
              key: const Key('prayer-second'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Second reminder: get up and pray'),
              subtitle: const Text('A little after the prayer time (for example before the jama‘ah), in case you did not get up'),
              value: second,
              onChanged: (on) => _set(_cur.copyWith(secondAfterSeconds: on ? 10 * 60 : 0)),
            ),
            if (second) ...[
              const SizedBox(height: Space.s8),
              Row(
                children: [
                  const Text('After'),
                  const SizedBox(width: Space.s8),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      key: const Key('second-min'),
                      initialValue: mins,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'minutes', border: OutlineInputBorder()),
                      items: [for (var m = 0; m <= 59; m++) DropdownMenuItem(value: m, child: Text('$m'))],
                      onChanged: (m) {
                        if (m == null) return;
                        final sec = _cur.secondAfterSeconds % 60;
                        _set(_cur.copyWith(secondAfterSeconds: (m * 60 + sec).clamp(5, 3599)));
                      },
                    ),
                  ),
                  const SizedBox(width: Space.s8),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      key: const Key('second-sec'),
                      initialValue: secs,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'seconds', border: OutlineInputBorder()),
                      items: [for (var x = 0; x <= 59; x++) DropdownMenuItem(value: x, child: Text('$x'))],
                      onChanged: (x) {
                        if (x == null) return;
                        final m = _cur.secondAfterSeconds ~/ 60;
                        _set(_cur.copyWith(secondAfterSeconds: (m * 60 + x).clamp(5, 3599)));
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Space.s4),
              Text('${minSec(s.secondAfterSeconds)} after the prayer time.', key: const Key('second-summary'), style: t.bodySmall),
              const SizedBox(height: Space.s12),
              SegmentedButton<bool>(
                key: const Key('second-scope'),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: true, label: Text('Fajr only')),
                  ButtonSegment(value: false, label: Text('Every prayer with a bell')),
                ],
                selected: {s.secondFajrOnly},
                onSelectionChanged: (v) => _set(_cur.copyWith(secondFajrOnly: v.first)),
              ),
              const SizedBox(height: Space.s12),
              _toneMenu(const Key('second-tone'), 'Sound of the second reminder', s.secondTone, PrayerTone.values, _chooseSecondTone),
              if (s.secondTone == PrayerTone.voice) ...[
                const SizedBox(height: Space.s12),
                TextField(
                  key: const Key('second-words'),
                  controller: _words,
                  minLines: 1,
                  maxLines: 3,
                  maxLength: 200,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Words it says',
                    hintText: 'e.g. Get up, otherwise the prayer will be missed',
                    helperText: '{prayer} becomes the prayer’s name. English letters work best.',
                    helperMaxLines: 2,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) {
                    setState(() {});
                    _save?.cancel();
                    _save = Timer(const Duration(milliseconds: 900), _commitWords);
                  },
                  onEditingComplete: () {
                    _save?.cancel();
                    _commitWords();
                    FocusScope.of(context).unfocus();
                  },
                ),
                Text('For Fajr it says: “$sample”', key: const Key('second-sample'), style: t.bodySmall?.copyWith(color: QuranColors.goldDeep)),
                if (urduNoVoice)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.s4),
                    child: Text(
                      'Urdu script needs an Urdu voice on the phone (Settings → Text-to-speech). If there is none, the alarm sound plays instead.',
                      style: t.bodySmall,
                    ),
                  ),
              ],
              if (s.secondTone == PrayerTone.own)
                Row(
                  children: [
                    Expanded(child: Text(s.secondSound == null ? 'No file chosen yet' : soundName(s.secondSound), overflow: TextOverflow.ellipsis, style: t.bodySmall)),
                    TextButton(key: const Key('second-sound'), onPressed: () => _chooseSecondTone(PrayerTone.own), child: const Text('Change')),
                  ],
                ),
              SwitchListTile(
                key: const Key('second-insistent'),
                contentPadding: EdgeInsets.zero,
                title: Text(s.secondTone.rings ? 'Keep going, loud, until I tap “I’m up”' : 'Keep ringing until I open it'),
                value: s.secondKeepRinging,
                onChanged: (v) => _set(_cur.copyWith(secondKeepRinging: v)),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(key: const Key('prayer-test-second'), onPressed: () => _tryIt(true), icon: const Icon(Icons.play_circle_outline), label: const Text('Try the second reminder')),
              ),
            ],
            if (problem != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.s8),
                child: Text(problem, key: const Key('ring-problem'), style: t.bodySmall?.copyWith(color: c.danger)),
              ),
            const Divider(),
            Text('Make sure they come', style: t.titleSmall),
            const SizedBox(height: Space.s4),
            if (until != null)
              Text(
                'Set up to ${MaterialLocalizations.of(context).formatMediumDate(until)}. Opening Folio moves this forward; '
                'two days before the end a notification asks you to open it once.',
                key: const Key('prayer-until'),
                style: t.bodySmall,
              ),
            if (battery == false) ...[
              const SizedBox(height: Space.s8),
              Text(
                'Battery saving may delay or block Folio’s alarms on this phone.',
                key: const Key('battery-warning'),
                style: t.bodySmall?.copyWith(color: c.danger),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  key: const Key('battery-allow'),
                  onPressed: () => ref.read(batteryPortProvider).askUnrestricted(),
                  icon: const Icon(Icons.battery_alert_outlined),
                  label: const Text('Make reminders reliable'),
                ),
              ),
            ] else if (battery == true)
              Padding(
                padding: const EdgeInsets.only(top: Space.s4),
                child: Row(
                  children: [
                    Icon(Icons.verified_outlined, size: 18, color: QuranColors.goldDeep),
                    const SizedBox(width: Space.s8),
                    Expanded(child: Text('Battery: Folio is allowed to run alarms on time.', key: const Key('battery-ok'), style: t.bodySmall)),
                  ],
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const Key('app-settings'),
                onPressed: () => ref.read(batteryPortProvider).openAppSettings(),
                child: const Text('Phone settings for Folio (Autostart on Xiaomi, Oppo, Vivo)'),
              ),
            ),
            Text(
              'Spoken reminders sound like an alarm, even in silent mode. For the others to come through Do Not Disturb, '
              'add Folio to its exceptions.',
              style: t.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
