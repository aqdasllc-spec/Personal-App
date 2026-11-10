import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/tokens.dart';
import '../presentation/quran_style.dart';
import 'prayer.dart';
import 'prayer_providers.dart';

String _hm(BuildContext context, DateTime t) => MaterialLocalizations.of(context).formatTimeOfDay(
  TimeOfDay.fromDateTime(t),
  alwaysUse24HourFormat: MediaQuery.maybeAlwaysUse24HourFormatOf(context) ?? false,
);

/// Sehri and Iftar (in Ramadan), Tahajjud, Ishraq / Chasht, and when prayer is disliked.
class ExtraTimesCard extends StatelessWidget {
  const ExtraTimesCard({super.key, required this.settings, required this.now});
  final PrayerSettings settings;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final x = extraTimes(settings, now);
    final t = Theme.of(context).textTheme;
    final c = context.colors;
    String span(DateTime a, DateTime b) => '${_hm(context, a)} – ${_hm(context, b)}';
    Widget row(String key, String english, String urdu, String value, {String? note}) => Padding(
      key: Key('extra-$key'),
      padding: const EdgeInsets.symmetric(vertical: Space.s4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: Space.s8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(english, style: t.bodyLarge),
                    Text(urdu, textDirection: TextDirection.rtl, style: urduText(13, color: c.textMuted)),
                  ],
                ),
                if (note != null) Text(note, style: t.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: Space.s8),
          Text(value, style: t.bodyLarge?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
        ],
      ),
    );
    return Card(
      key: const Key('extra-times'),
      child: Padding(
        padding: const EdgeInsets.all(Space.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('More times today', style: t.titleMedium),
            const SizedBox(height: Space.s8),
            if (x.ramadan) ...[
              row('sehri', 'Sehri ends', 'سحری کا اختتام', _hm(context, x.sehriEnds), note: 'Stop eating at Fajr time'),
              row('iftar', 'Iftar', 'افطار', _hm(context, x.iftar), note: 'At Maghrib time'),
              const Divider(),
            ],
            row('ishraq', 'Ishraq / Chasht', 'اشراق / چاشت', 'from ${_hm(context, x.ishraq)}', note: 'About 20 minutes after sunrise, until zawal'),
            row('tahajjud', 'Tahajjud', 'تہجد', span(x.lastThird, x.nextFajr), note: 'The last third of the night (midnight ${_hm(context, x.midnight)})'),
            const Divider(),
            Text('Prayer is disliked (makrooh)', style: t.titleSmall),
            row('sunrise', 'While the sun rises', 'طلوع', span(x.sunriseFrom, x.sunriseTo)),
            row('zawal', 'Zawal (sun at its height)', 'زوال', span(x.zawalFrom, x.zawalTo)),
            row('sunset', 'While the sun sets', 'غروب', span(x.sunsetFrom, x.sunsetTo), note: "Except that day's Asr, if it was not yet prayed"),
            const SizedBox(height: Space.s4),
            Text('Approximate: the minutes are the common rule of thumb. Ask your local scholars where it matters.', style: t.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// Today's five prayers: tap to mark prayed or missed; days in a row; the qaza still to make up.
class PrayerLogCard extends ConsumerWidget {
  const PrayerLogCard({super.key, required this.settings, required this.now});
  final PrayerSettings settings;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final log = ref.watch(prayerLogProvider);
    final t = Theme.of(context).textTheme;
    final c = context.colors;
    final day = prayerDay(settings, now);
    final streak = log.streak(now);
    final owed = log.owedTotal;
    void set(PrayerLog v) => ref.read(prayerLogProvider.notifier).set(v);
    return Card(
      key: const Key('prayer-log'),
      child: Padding(
        padding: const EdgeInsets.all(Space.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text('Today’s prayers', style: t.titleMedium)),
                if (streak > 0)
                  Text(
                    '$streak ${streak == 1 ? 'day' : 'days'} in a row',
                    key: const Key('prayer-streak'),
                    style: t.bodySmall?.copyWith(color: QuranColors.goldDeep, fontWeight: FontWeight.w600),
                  ),
              ],
            ),
            Text('Tap once for prayed, twice for missed (it goes to qaza).', style: t.bodySmall),
            const SizedBox(height: Space.s12),
            Wrap(
              spacing: Space.s8,
              runSpacing: Space.s8,
              children: [
                for (final p in Prayer.values.where((p) => p.isPrayer))
                  Builder(
                    builder: (context) {
                      final v = log.on(now, p);
                      final begun = !day.times[p]!.isAfter(now);
                      return FilterChip(
                        key: Key('log-${p.name}'),
                        showCheckmark: false,
                        avatar: Icon(
                          v == true ? Icons.check_circle : (v == false ? Icons.cancel : Icons.radio_button_unchecked),
                          size: 18,
                          color: v == true ? QuranColors.goldDeep : (v == false ? c.danger : c.textMuted),
                        ),
                        label: Text(p.english),
                        selected: v != null,
                        selectedColor: v == false ? c.danger.withValues(alpha: .12) : QuranColors.gold.withValues(alpha: .22),
                        tooltip: begun ? null : 'Its time has not come yet',
                        onSelected: begun ? (_) => set(log.mark(now, p, v == null ? true : (v ? false : null))) : null,
                      );
                    },
                  ),
              ],
            ),
            const Divider(height: Space.s24),
            ListTile(
              key: const Key('qaza-open'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.history_edu_outlined),
              title: const Text('Qaza to make up'),
              subtitle: Text(owed == 0 ? 'None' : '$owed prayers', key: const Key('qaza-total')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showModalBottomSheet<void>(context: context, isScrollControlled: true, showDragHandle: true, builder: (_) => const QazaSheet()),
            ),
          ],
        ),
      ),
    );
  }
}

/// The qaza of each prayer: make one up, or add missed prayers from before the log.
class QazaSheet extends ConsumerWidget {
  const QazaSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final log = ref.watch(prayerLogProvider);
    final t = Theme.of(context).textTheme;
    void set(PrayerLog v) => ref.read(prayerLogProvider.notifier).set(v);
    Future<void> addPast() async {
      final n = await showDialog<int>(context: context, builder: (_) => const _AddPastDialog());
      if (n == null || n <= 0) return;
      var l = ref.read(prayerLogProvider);
      for (final p in Prayer.values.where((p) => p.isPrayer)) {
        l = l.addPast(p, n);
      }
      set(l);
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.s16, 0, Space.s16, Space.s16),
        child: Column(
          key: const Key('qaza-sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Qaza · قضا', style: t.titleLarge),
            Text('Missed prayers still to make up. Each time you pray one, tap “Made up”.', style: t.bodySmall),
            const SizedBox(height: Space.s12),
            for (final p in Prayer.values.where((p) => p.isPrayer))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.s4),
                child: Row(
                  children: [
                    SizedBox(width: 90, child: Text(p.english, style: t.titleSmall)),
                    Expanded(child: Text('${log.owed(p)} to make up', key: Key('qaza-${p.name}'))),
                    IconButton(
                      key: Key('qaza-add-${p.name}'),
                      tooltip: 'Add one',
                      onPressed: () => set(log.addPast(p, 1)),
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                    FilledButton.tonal(
                      key: Key('qaza-made-${p.name}'),
                      onPressed: log.owed(p) == 0 ? null : () => set(log.makeUp(p)),
                      child: const Text('Made up'),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: Space.s8),
            OutlinedButton.icon(
              key: const Key('qaza-past'),
              onPressed: addPast,
              icon: const Icon(Icons.playlist_add),
              label: const Text('Add missed days from the past'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddPastDialog extends StatefulWidget {
  const _AddPastDialog();
  @override
  State<_AddPastDialog> createState() => _AddPastDialogState();
}

class _AddPastDialogState extends State<_AddPastDialog> {
  final _n = TextEditingController();
  bool _years = false;

  @override
  void dispose() {
    _n.dispose();
    super.dispose();
  }

  int? get _days {
    final n = int.tryParse(_n.text.trim());
    if (n == null || n <= 0) return null;
    return _years ? n * 354 : n; // a Hijri year has about 354 days
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Missed days from the past'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Each day adds one of each of the five prayers. An estimate is fine; you can correct it later.'),
        const SizedBox(height: Space.s12),
        TextField(
          key: const Key('qaza-past-n'),
          controller: _n,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'How many'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: Space.s8),
        SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: const [ButtonSegment(value: false, label: Text('Days')), ButtonSegment(value: true, label: Text('Years'))],
          selected: {_years},
          onSelectionChanged: (v) => setState(() => _years = v.first),
        ),
        if (_days != null) Padding(padding: const EdgeInsets.only(top: Space.s8), child: Text('Adds ${_days!} of each prayer.')),
      ],
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(key: const Key('qaza-past-add'), onPressed: _days == null ? null : () => Navigator.pop(context, _days), child: const Text('Add')),
    ],
  );
}

/// Minutes to add or take away per prayer, to match the local mosque.
class MosqueTimesDialog extends StatefulWidget {
  const MosqueTimesDialog({super.key, required this.offsets});
  final Map<Prayer, int> offsets;
  @override
  State<MosqueTimesDialog> createState() => _MosqueTimesDialogState();
}

class _MosqueTimesDialogState extends State<MosqueTimesDialog> {
  late final Map<Prayer, int> _o = {...widget.offsets};

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return AlertDialog(
      title: const Text('Mosque times'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Add or take away minutes so the times (and reminders) match your mosque.', style: t.bodySmall),
            const SizedBox(height: Space.s8),
            for (final p in Prayer.values)
              Row(
                children: [
                  Expanded(child: Text(p.english)),
                  IconButton(
                    key: Key('offset-minus-${p.name}'),
                    tooltip: 'A minute earlier',
                    onPressed: (_o[p] ?? 0) > -60 ? () => setState(() => _o[p] = (_o[p] ?? 0) - 1) : null,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  SizedBox(
                    width: 44,
                    child: Text(
                      () {
                        final v = _o[p] ?? 0;
                        return v == 0 ? '0' : (v > 0 ? '+$v' : '$v');
                      }(),
                      key: Key('offset-${p.name}'),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  IconButton(
                    key: Key('offset-plus-${p.name}'),
                    tooltip: 'A minute later',
                    onPressed: (_o[p] ?? 0) < 60 ? () => setState(() => _o[p] = (_o[p] ?? 0) + 1) : null,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => setState(_o.clear), child: const Text('Reset')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          key: const Key('offset-save'),
          onPressed: () => Navigator.pop(context, {for (final e in _o.entries) if (e.value != 0) e.key: e.value}),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
