import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../design_system/tokens.dart';
import '../../planner/application/planner_controller.dart' show reminderSchedulerProvider;
import '../application/quran_providers.dart';
import '../presentation/cabinet_painters.dart';
import '../presentation/quran_style.dart';
import 'prayer.dart';
import 'prayer_providers.dart';

String _clock(BuildContext context, DateTime t) {
  final s = MaterialLocalizations.of(context).formatTimeOfDay(
    TimeOfDay.fromDateTime(t),
    alwaysUse24HourFormat: MediaQuery.maybeAlwaysUse24HourFormatOf(context) ?? false,
  );
  return s;
}

/// "۶:۴۷ صبح": 12-hour time with the part of the day in Urdu (Latin AM/PM would break a right-to-left line).
String urduClock(DateTime t) {
  final h12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final part = t.hour < 12 ? 'صبح' : (t.hour < 15 ? 'دوپہر' : (t.hour < 19 ? 'شام' : 'رات'));
  return '${urduDigits(h12)}:${urduDigits(t.minute).padLeft(2, '۰')} $part';
}

/// "1 h 12 min" / "۱ گھنٹہ ۱۲ منٹ"
String _left(Duration d, bool urdu) {
  final h = d.inHours, m = d.inMinutes % 60;
  if (urdu) {
    final parts = [if (h > 0) '${urduDigits(h)} گھنٹے', '${urduDigits(m)} منٹ'];
    return parts.join(' ');
  }
  return [if (h > 0) '$h h', '$m min'].join(' ');
}

/// The thin line at the bottom of the Quran cabinet: the next prayer with a countdown, and today's Hijri date.
class PrayerStrip extends ConsumerStatefulWidget {
  const PrayerStrip({super.key, required this.urdu, this.now});
  final bool urdu;
  final DateTime Function()? now;
  @override
  ConsumerState<PrayerStrip> createState() => _PrayerStripState();
}

class _PrayerStripState extends ConsumerState<PrayerStrip> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    // keep the reminders rolling forward (a week at a time) whenever Home is shown
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(prayerSettingsProvider.notifier).resync();
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(prayerSettingsProvider);
    final urdu = widget.urdu;
    final now = (widget.now ?? DateTime.now)();
    final hijri = urdu ? hijriUrdu(now, s.hijriOffset, urduDigits) : hijriEnglish(now, s.hijriOffset);
    final small = urdu
        ? urduText(11, color: QuranColors.cream).copyWith(height: 1.5)
        : const TextStyle(color: QuranColors.cream, fontSize: 11.5, fontWeight: FontWeight.w600);
    final muted = urdu ? urduText(10.5, color: QuranColors.creamMuted).copyWith(height: 1.5) : const TextStyle(color: QuranColors.creamMuted, fontSize: 11);

    Widget next;
    if (!s.hasLocation) {
      next = Text(urdu ? 'نماز کے اوقات: مقام منتخب کریں' : 'Prayer times: tap to set your place', key: const Key('prayer-strip-setup'), style: small, maxLines: 1, overflow: TextOverflow.ellipsis);
    } else {
      final n = prayerNow(s, now);
      final left = _left(n.nextAt.difference(now) + const Duration(seconds: 59), urdu);
      next = Text(
        urdu ? '${n.next.urdu} ${urduClock(n.nextAt)}، $left میں' : '${n.next.english} ${_clock(context, n.nextAt)} · in $left',
        key: const Key('prayer-strip-next'),
        style: small,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    return Semantics(
      button: true,
      label: urdu ? 'نماز کے اوقات' : 'Prayer times',
      child: InkWell(
        key: const Key('prayer-strip'),
        onTap: () => context.push(Routes.prayer),
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Directionality(
              textDirection: urdu ? TextDirection.rtl : TextDirection.ltr,
              child: Row(
                children: [
                  const Icon(Icons.schedule, size: 16, color: QuranColors.gold),
                  const SizedBox(width: 6),
                  Expanded(flex: 3, child: next),
                  const SizedBox(width: 8),
                  Flexible(flex: 2, child: Text(hijri, key: const Key('prayer-strip-hijri'), style: muted, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: urdu ? TextAlign.left : TextAlign.right)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Today's prayer times, the Hijri date, reminders and the settings they depend on.
class PrayerPage extends ConsumerStatefulWidget {
  const PrayerPage({super.key, this.now});
  final DateTime Function()? now;
  @override
  ConsumerState<PrayerPage> createState() => _PrayerPageState();
}

class _PrayerPageState extends ConsumerState<PrayerPage> {
  Timer? _tick;
  bool _locating = false;
  String? _problem;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _locate() async {
    setState(() {
      _locating = true;
      _problem = null;
    });
    final pos = await ref.read(locationPortProvider).current((why) => _problem = why);
    if (!mounted) return;
    setState(() => _locating = false);
    if (pos != null) {
      final s = ref.read(prayerSettingsProvider);
      ref.read(prayerSettingsProvider.notifier).set(s.copyWith(lat: pos.lat, lng: pos.lng, place: s.place.isEmpty ? 'My location' : s.place));
    }
  }

  Future<void> _manual() async {
    final s = ref.read(prayerSettingsProvider);
    final r = await showDialog<({double lat, double lng, String place})>(
      context: context,
      builder: (_) => _PlaceDialog(lat: s.lat, lng: s.lng, place: s.place),
    );
    if (r != null) ref.read(prayerSettingsProvider.notifier).set(s.copyWith(lat: r.lat, lng: r.lng, place: r.place));
  }

  Future<void> _toggleAlert(Prayer p, bool on) async {
    final s = ref.read(prayerSettingsProvider);
    if (on) {
      final sched = ref.read(reminderSchedulerProvider);
      if (!await sched.hasPermission()) await sched.requestPermission();
    }
    final a = {...s.alerts};
    on ? a.add(p) : a.remove(p);
    ref.read(prayerSettingsProvider.notifier).set(s.copyWith(alerts: a));
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(prayerSettingsProvider);
    final urdu = ref.watch(dailyLangProvider) == DailyLang.urdu;
    final now = (widget.now ?? DateTime.now)();
    final t = Theme.of(context).textTheme;
    final c = context.colors;
    final set = ref.read(prayerSettingsProvider.notifier).set;

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: QuranColors.velvet,
        foregroundColor: QuranColors.goldLight,
        title: const Text('Prayer times'),
      ),
      body: ListView(
        key: const Key('prayer-page'),
        padding: const EdgeInsets.all(Space.s16),
        children: [
          // date banner
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(gradient: QuranColors.goldGradient, borderRadius: BorderRadius.circular(14)),
            child: Container(
              decoration: BoxDecoration(color: QuranColors.velvet, borderRadius: BorderRadius.circular(11)),
              child: CustomPaint(
                painter: const StarLatticePainter(opacity: .08, cell: 28),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Space.s16, horizontal: Space.s16),
                  child: Column(
                    children: [
                      Text(hijriUrdu(now, s.hijriOffset, urduDigits), key: const Key('prayer-hijri-urdu'), textDirection: TextDirection.rtl, style: urduText(20, color: QuranColors.goldLight)),
                      Text(hijriEnglish(now, s.hijriOffset), key: const Key('prayer-hijri'), style: const TextStyle(color: QuranColors.cream, fontSize: 15, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(MaterialLocalizations.of(context).formatFullDate(now), style: const TextStyle(color: QuranColors.creamMuted, fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: Space.s16),
          if (!s.hasLocation)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(Space.s16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Where are you?', style: t.titleMedium),
                    const SizedBox(height: Space.s4),
                    Text('Prayer times depend on your place. They are calculated on your phone; your location is not sent anywhere.', style: t.bodySmall),
                    const SizedBox(height: Space.s12),
                    Wrap(
                      spacing: Space.s8,
                      runSpacing: Space.s8,
                      children: [
                        FilledButton.icon(
                          key: const Key('prayer-locate'),
                          onPressed: _locating ? null : _locate,
                          icon: _locating ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.my_location),
                          label: const Text('Use my location'),
                        ),
                        OutlinedButton(key: const Key('prayer-manual'), onPressed: _manual, child: const Text('Enter the place')),
                      ],
                    ),
                    if (_problem != null) ...[
                      const SizedBox(height: Space.s8),
                      Text(_problem!, key: const Key('prayer-problem'), style: t.bodySmall?.copyWith(color: c.danger)),
                    ],
                  ],
                ),
              ),
            )
          else
            _times(context, s, now, urdu),
          const SizedBox(height: Space.s24),
          Text('Settings', style: t.titleMedium),
          const SizedBox(height: Space.s8),
          if (s.hasLocation)
            ListTile(
              key: const Key('prayer-place'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.place_outlined),
              title: Text(s.place.isEmpty ? 'Your place' : s.place),
              subtitle: Text('${s.lat!.toStringAsFixed(4)}, ${s.lng!.toStringAsFixed(4)}'),
              trailing: Wrap(
                children: [
                  IconButton(tooltip: 'Use my location again', onPressed: _locating ? null : _locate, icon: const Icon(Icons.my_location)),
                  IconButton(tooltip: 'Enter the place', onPressed: _manual, icon: const Icon(Icons.edit_location_alt_outlined)),
                ],
              ),
            ),
          if (_problem != null && s.hasLocation) Text(_problem!, style: t.bodySmall?.copyWith(color: c.danger)),
          const SizedBox(height: Space.s8),
          DropdownButtonFormField<PrayerMethod>(
            key: const Key('prayer-method'),
            initialValue: s.method,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Calculation method', border: OutlineInputBorder()),
            items: [for (final m in PrayerMethod.values) DropdownMenuItem(value: m, child: Text(m.label, overflow: TextOverflow.ellipsis))],
            onChanged: (m) => m == null ? null : set(s.copyWith(method: m)),
          ),
          const SizedBox(height: Space.s12),
          Text('Asr time', style: t.bodyLarge),
          const SizedBox(height: Space.s4),
          SegmentedButton<bool>(
            key: const Key('prayer-asr'),
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: true, label: Text('Hanafi (later)')),
              ButtonSegment(value: false, label: Text("Shafi'i, Maliki, Hanbali")),
            ],
            selected: {s.hanafi},
            onSelectionChanged: (v) => set(s.copyWith(hanafi: v.first)),
          ),
          const SizedBox(height: Space.s16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Hijri date adjustment', style: t.bodyLarge),
                    Text('Moon sighting where you live may differ from the Umm al-Qura calendar (in Pakistan and India often one day behind).', style: t.bodySmall),
                  ],
                ),
              ),
              IconButton(key: const Key('hijri-minus'), tooltip: 'One day earlier', onPressed: s.hijriOffset > -2 ? () => set(s.copyWith(hijriOffset: s.hijriOffset - 1)) : null, icon: const Icon(Icons.remove_circle_outline)),
              Text(s.hijriOffset == 0 ? '0' : (s.hijriOffset > 0 ? '+${s.hijriOffset}' : '${s.hijriOffset}'), key: const Key('hijri-offset'), style: t.titleMedium),
              IconButton(key: const Key('hijri-plus'), tooltip: 'One day later', onPressed: s.hijriOffset < 2 ? () => set(s.copyWith(hijriOffset: s.hijriOffset + 1)) : null, icon: const Icon(Icons.add_circle_outline)),
            ],
          ),
          const SizedBox(height: Space.s16),
          Text(
            'Times are calculated on your phone with the standard astronomical method for the authority you choose; mosques may '
            'add a few minutes. Reminders are scheduled a week ahead and renewed each time you open Folio.',
            style: t.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _times(BuildContext context, PrayerSettings s, DateTime now, bool urdu) {
    final day = prayerDay(s, now);
    final n = prayerNow(s, now);
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final p in Prayer.values)
            Container(
              key: Key('prayer-row-${p.name}'),
              color: p == n.next ? QuranColors.gold.withValues(alpha: .16) : null,
              padding: const EdgeInsets.symmetric(horizontal: Space.s16, vertical: Space.s4),
              child: Row(
                children: [
                  Expanded(
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: Space.s12,
                      children: [
                        Text(p.english, style: t.titleMedium?.copyWith(color: p.isPrayer ? c.text : c.textMuted, fontWeight: p == n.next ? FontWeight.w700 : null)),
                        Text(p.urdu, textDirection: TextDirection.rtl, style: urduText(15, color: p.isPrayer ? c.text : c.textMuted)),
                      ],
                    ),
                  ),
                  const SizedBox(width: Space.s8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(_clock(context, day.times[p]!), key: Key('prayer-time-${p.name}'), style: t.titleMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()], fontWeight: p == n.next ? FontWeight.w700 : null)),
                      if (p == n.next) Text('in ${_left(n.nextAt.difference(now) + const Duration(seconds: 59), false)}', style: t.bodySmall?.copyWith(color: QuranColors.goldDeep)),
                    ],
                  ),
                  const SizedBox(width: Space.s4),
                  if (p.isPrayer)
                    IconButton(
                      key: Key('prayer-alert-${p.name}'),
                      tooltip: s.alerts.contains(p) ? 'Reminder on' : 'Remind me',
                      onPressed: () => _toggleAlert(p, !s.alerts.contains(p)),
                      icon: Icon(s.alerts.contains(p) ? Icons.notifications_active : Icons.notifications_none, color: s.alerts.contains(p) ? QuranColors.goldDeep : null),
                    )
                  else
                    const SizedBox(width: 48),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PlaceDialog extends StatefulWidget {
  const _PlaceDialog({this.lat, this.lng, this.place = ''});
  final double? lat, lng;
  final String place;
  @override
  State<_PlaceDialog> createState() => _PlaceDialogState();
}

class _PlaceDialogState extends State<_PlaceDialog> {
  late final _place = TextEditingController(text: widget.place);
  late final _lat = TextEditingController(text: widget.lat?.toString() ?? '');
  late final _lng = TextEditingController(text: widget.lng?.toString() ?? '');
  String? _error;

  @override
  void dispose() {
    _place.dispose();
    _lat.dispose();
    _lng.dispose();
    super.dispose();
  }

  void _save() {
    final lat = double.tryParse(_lat.text.trim().replaceAll(',', '.'));
    final lng = double.tryParse(_lng.text.trim().replaceAll(',', '.'));
    if (lat == null || lng == null || lat.abs() > 90 || lng.abs() > 180) {
      setState(() => _error = 'Latitude is -90 to 90 and longitude -180 to 180, e.g. 31.5204 and 74.3587 for Lahore.');
      return;
    }
    Navigator.pop(context, (lat: lat, lng: lng, place: _place.text.trim()));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Enter the place'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(key: const Key('place-name'), controller: _place, decoration: const InputDecoration(labelText: 'Name (for you), e.g. Lahore')),
          TextField(key: const Key('place-lat'), controller: _lat, keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true), decoration: const InputDecoration(labelText: 'Latitude')),
          TextField(key: const Key('place-lng'), controller: _lng, keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true), decoration: const InputDecoration(labelText: 'Longitude')),
          const SizedBox(height: 8),
          Text(_error ?? 'You can copy them from a map app: press and hold on the place.', style: TextStyle(fontSize: 12, color: _error == null ? null : Theme.of(context).colorScheme.error)),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(key: const Key('place-save'), onPressed: _save, child: const Text('Save')),
    ],
  );
}
