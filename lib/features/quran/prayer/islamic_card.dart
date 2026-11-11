import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/tokens.dart';
import '../presentation/quran_style.dart';
import 'islamic.dart';
import 'prayer.dart';
import 'prayer_providers.dart';

/// "Did you pray?", Jumu'ah, Surah Al-Kahf / Al-Mulk, and reminders before Islamic dates and voluntary fasts.
class IslamicRemindersCard extends ConsumerWidget {
  const IslamicRemindersCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(islamicRemindersProvider);
    final t = Theme.of(context).textTheme;
    void set(IslamicSettings v) => ref.read(islamicRemindersProvider.notifier).set(v);
    IslamicSettings cur() => ref.read(islamicRemindersProvider);
    String hm(Clock c) => MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay(hour: c.hour, minute: c.minute));
    Future<Clock?> pick(Clock c) async {
      final v = await showTimePicker(context: context, initialTime: TimeOfDay(hour: c.hour, minute: c.minute));
      return v == null ? null : (hour: v.hour, minute: v.minute);
    }

    Widget timeChip(Key key, Clock c, void Function(Clock) done) => ActionChip(
      key: key,
      avatar: const Icon(Icons.schedule, size: 18),
      label: Text(hm(c)),
      onPressed: () async {
        final v = await pick(c);
        if (v != null) done(v);
      },
    );

    Widget row(Key key, String title, String urdu, bool value, void Function(bool) changed, {String? subtitle, Widget? extra}) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          key: key,
          contentPadding: EdgeInsets.zero,
          title: Wrap(
            spacing: Space.s8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(title),
              Text(urdu, textDirection: TextDirection.rtl, style: urduText(13, color: QuranColors.goldDeep).copyWith(height: 1.4)),
            ],
          ),
          subtitle: subtitle == null ? null : Text(subtitle),
          value: value,
          onChanged: changed,
        ),
        if (value && extra != null) Padding(padding: const EdgeInsets.only(bottom: Space.s8), child: extra),
      ],
    );

    return Card(
      key: const Key('islamic-reminders'),
      child: Padding(
        padding: const EdgeInsets.all(Space.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text("Sunnah, Jumu'ah and Islamic dates", style: t.titleMedium),
            const SizedBox(height: Space.s4),
            row(
              const Key('ask-prayed'),
              'Did you pray?',
              'کیا نماز ادا کی؟',
              s.askPrayed,
              (v) => set(cur().copyWith(askPrayed: v)),
              subtitle: 'After each prayer time, a quiet notification with Prayed and Missed buttons; your answer goes into the prayer log (and the qaza count).',
              extra: Row(
                children: [
                  const Text('Ask'),
                  const SizedBox(width: Space.s8),
                  DropdownButton<int>(
                    key: const Key('ask-after'),
                    value: s.askAfterMinutes,
                    items: [for (final m in const [20, 30, 45, 60, 90, 120]) DropdownMenuItem(value: m, child: Text('$m min'))],
                    onChanged: (m) => m == null ? null : set(cur().copyWith(askAfterMinutes: m)),
                  ),
                  const SizedBox(width: Space.s8),
                  const Flexible(child: Text('after the prayer time (always before the next one)')),
                ],
              ),
            ),
            row(
              const Key('jumuah'),
              "Jumu'ah",
              'جمعہ',
              s.jumuah,
              (v) => set(cur().copyWith(jumuah: v)),
              subtitle: "On Fridays, before the khutbah at your mosque (with the phone's alarm sound).",
              extra: Wrap(
                spacing: Space.s8,
                runSpacing: Space.s8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('Khutbah at'),
                  timeChip(const Key('khutbah-at'), s.khutbahAt, (v) => set(cur().copyWith(khutbahAt: v))),
                  const Text('remind'),
                  DropdownButton<int>(
                    key: const Key('jumuah-before'),
                    value: s.jumuahBefore,
                    items: [for (final m in const [15, 20, 30, 45, 60, 90]) DropdownMenuItem(value: m, child: Text('$m min before'))],
                    onChanged: (m) => m == null ? null : set(cur().copyWith(jumuahBefore: m)),
                  ),
                ],
              ),
            ),
            row(
              const Key('kahf'),
              'Surah Al-Kahf on Fridays',
              'جمعہ کو سورۃ الکہف',
              s.kahf,
              (v) => set(cur().copyWith(kahf: v)),
              extra: Row(children: [const Text('At'), const SizedBox(width: Space.s8), timeChip(const Key('kahf-at'), s.kahfAt, (v) => set(cur().copyWith(kahfAt: v)))]),
            ),
            row(
              const Key('mulk'),
              'Surah Al-Mulk at night',
              'رات کو سورۃ الملک',
              s.mulk,
              (v) => set(cur().copyWith(mulk: v)),
              extra: Row(children: [const Text('At'), const SizedBox(width: Space.s8), timeChip(const Key('mulk-at'), s.mulkAt, (v) => set(cur().copyWith(mulkAt: v)))]),
            ),
            const Divider(),
            row(
              const Key('islamic-dates'),
              'Islamic dates',
              'اسلامی تاریخیں',
              s.dates,
              (v) => set(cur().copyWith(dates: v)),
              subtitle: "The evening before Ramadan, the Eids, Arafah, Ashura, Shab-e-Barat, Laylat al-Qadr and the Islamic New Year.",
            ),
            row(
              const Key('fast-monthu'),
              'Monday and Thursday fasts',
              'پیر اور جمعرات کے روزے',
              s.monThu,
              (v) => set(cur().copyWith(monThu: v)),
            ),
            row(
              const Key('fast-white'),
              'The white days (13th–15th)',
              'ایام بیض',
              s.whiteDays,
              (v) => set(cur().copyWith(whiteDays: v)),
            ),
            if (s.dates || s.monThu || s.whiteDays)
              Row(
                children: [
                  const Expanded(child: Text('Remind the evening before at')),
                  timeChip(const Key('evening-at'), s.eveningAt, (v) => set(cur().copyWith(eveningAt: v))),
                ],
              ),
            const SizedBox(height: Space.s4),
            Text(
              'Not reminded on the days fasting is not allowed (the Eids and the days after Eid al-Adha), nor in Ramadan. '
              'Dates follow the Hijri adjustment set below; they can move a day with the moon sighting.',
              style: t.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// The coming Islamic dates, with their Gregorian dates and how far away they are.
class IslamicDatesCard extends ConsumerWidget {
  const IslamicDatesCard({super.key, required this.now});
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offset = ref.watch(prayerSettingsProvider).hijriOffset;
    final t = Theme.of(context).textTheme;
    final c = context.colors;
    final today = DateTime(now.year, now.month, now.day);
    final list = upcomingIslamicDates(today, offset, days: 400).take(8).toList();
    final ml = MaterialLocalizations.of(context);
    return Card(
      key: const Key('islamic-dates-card'),
      child: Padding(
        padding: const EdgeInsets.all(Space.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Coming Islamic dates', style: t.titleMedium),
            const SizedBox(height: Space.s8),
            for (final e in list)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.s4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.day.english, style: t.bodyLarge),
                          Text(e.day.urdu, textDirection: TextDirection.rtl, style: urduText(13, color: QuranColors.goldDeep).copyWith(height: 1.5)),
                        ],
                      ),
                    ),
                    const SizedBox(width: Space.s8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(ml.formatMediumDate(e.date), style: t.bodyMedium),
                        Text(
                          () {
                            final d = e.date.difference(today).inDays;
                            return d == 0 ? 'today' : (d == 1 ? 'tomorrow' : 'in $d days');
                          }(),
                          style: t.bodySmall?.copyWith(color: c.textMuted),
                        ),
                        Text('${e.day.day} ${hijriMonthsEnglish[e.day.month - 1]} ${e.hijriYear}', style: t.bodySmall?.copyWith(color: c.textMuted)),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
