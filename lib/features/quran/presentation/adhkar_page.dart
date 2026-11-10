import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/tokens.dart';
import '../application/quran_providers.dart';
import '../data/adhkar.dart';
import '../data/quran_data.dart';
import '../prayer/prayer.dart';
import '../prayer/prayer_providers.dart';
import 'cabinet_painters.dart';
import 'quran_style.dart';

/// Morning is from Fajr until Asr; evening from Asr on (and through the night until Fajr).
bool isMorningNow(PrayerSettings s, DateTime now) {
  if (!s.hasLocation) return now.hour >= 4 && now.hour < 15;
  final d = prayerDay(s, now);
  return !now.isBefore(d.times[Prayer.fajr]!) && now.isBefore(d.times[Prayer.asr]!);
}

/// The morning and evening adhkar (Hisn al-Muslim): each with how many times to say it, its translation, and its
/// virtue and source; tick the ones said today.
class AdhkarPage extends ConsumerStatefulWidget {
  const AdhkarPage({super.key, this.now});
  final DateTime Function()? now;
  @override
  ConsumerState<AdhkarPage> createState() => _AdhkarPageState();
}

class _AdhkarPageState extends ConsumerState<AdhkarPage> {
  bool? _morning;
  bool _translit = false;

  @override
  Widget build(BuildContext context) {
    final now = (widget.now ?? DateTime.now)();
    final morning = _morning ?? isMorningNow(ref.watch(prayerSettingsProvider), now);
    final all = ref.watch(adhkarProvider);
    final q = ref.watch(quranDataProvider).value;
    final urdu = ref.watch(dailyLangProvider) == DailyLang.urdu;
    final done = ref.watch(adhkarDoneProvider.notifier).on(now, morning);
    ref.watch(adhkarDoneProvider);
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: QuranColors.velvet,
        foregroundColor: QuranColors.goldLight,
        title: const Text('Adhkar · اذکار'),
        actions: [
          IconButton(
            key: const Key('adhkar-translit'),
            tooltip: _translit ? 'Hide the pronunciation' : 'Show the pronunciation (English letters)',
            icon: Icon(_translit ? Icons.abc : Icons.abc_outlined, color: _translit ? QuranColors.gold : null),
            onPressed: () => setState(() => _translit = !_translit),
          ),
        ],
      ),
      body: all.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not open the adhkar: $e')),
        data: (list) {
          final items = list.where((d) => morning ? d.forMorning() : d.forEvening()).toList();
          final n = items.where((d) => done.contains(d.n)).length;
          return ListView(
            key: const Key('adhkar-list'),
            padding: const EdgeInsets.fromLTRB(Space.s12, Space.s12, Space.s12, Space.s24),
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(gradient: QuranColors.goldGradient, borderRadius: BorderRadius.circular(14)),
                child: Container(
                  decoration: BoxDecoration(color: QuranColors.velvet, borderRadius: BorderRadius.circular(11)),
                  child: CustomPaint(
                    painter: const StarLatticePainter(opacity: .09, cell: 28),
                    child: Padding(
                      padding: const EdgeInsets.all(Space.s12),
                      child: Column(
                        children: [
                          SegmentedButton<bool>(
                            key: const Key('adhkar-time'),
                            showSelectedIcon: false,
                            style: SegmentedButton.styleFrom(
                              foregroundColor: QuranColors.creamMuted,
                              selectedForegroundColor: QuranColors.velvetDeep,
                              selectedBackgroundColor: QuranColors.gold,
                              side: BorderSide(color: QuranColors.gold.withValues(alpha: .6)),
                            ),
                            segments: [
                              ButtonSegment(
                                value: true,
                                icon: const Icon(Icons.wb_sunny_outlined),
                                label: Text('Morning', key: const Key('adhkar-morning')),
                              ),
                              ButtonSegment(
                                value: false,
                                icon: const Icon(Icons.nights_stay_outlined),
                                label: Text('Evening', key: const Key('adhkar-evening')),
                              ),
                            ],
                            selected: {morning},
                            onSelectionChanged: (v) => setState(() => _morning = v.first),
                          ),
                          const SizedBox(height: Space.s8),
                          Text(
                            morning ? 'أذكار الصباح · صبح کے اذکار' : 'أذكار المساء · شام کے اذکار',
                            textDirection: TextDirection.rtl,
                            style: urduText(16, color: QuranColors.goldLight),
                          ),
                          const SizedBox(height: Space.s8),
                          LinearProgressIndicator(
                            value: items.isEmpty ? 0 : n / items.length,
                            color: QuranColors.gold,
                            backgroundColor: QuranColors.gold.withValues(alpha: .2),
                          ),
                          const SizedBox(height: Space.s4),
                          Text(
                            n == items.length ? 'All said today. May Allah accept.' : '$n of ${items.length} said today',
                            key: const Key('adhkar-progress'),
                            style: const TextStyle(color: QuranColors.creamMuted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: Space.s12),
              for (final d in items)
                _DhikrCard(
                  key: Key('dhikr-${d.n}'),
                  d: d,
                  quran: q,
                  urdu: urdu,
                  translit: _translit,
                  done: done.contains(d.n),
                  onDone: () => ref.read(adhkarDoneProvider.notifier).toggle(now, morning, d.n),
                ),
              const SizedBox(height: Space.s8),
              Text(
                'From Hisn al-Muslim (Sa\'id al-Qahtani). Translations: Hisn al-Muslim (English); the ayahs of the Quran with the '
                'app\'s Quran translations. Urdu is shown for the ayahs; for the other adhkar the English is shown.',
                style: t.bodySmall,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DhikrCard extends StatelessWidget {
  const _DhikrCard({super.key, required this.d, required this.quran, required this.urdu, required this.translit, required this.done, required this.onDone});
  final Dhikr d;
  final QuranData? quran;
  final bool urdu, translit, done;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final q = quran;
    String arabic = d.arabic;
    String? urduText_, english = d.english;
    String? title;
    if (d.quran != null && q != null) {
      final (s, from, to) = d.quran!;
      final idx = [for (var a = from; a <= to; a++) q.indexOf(s, a)];
      arabic = [for (var k = 0; k < idx.length; k++) '${q.arabic[idx[k]]} ${ayahEnd(from + k)}'].join(' ');
      urduText_ = [for (final i in idx) q.urdu[i]].join(' ');
      english = [for (final i in idx) q.english[i]].join(' ');
      final su = q.surah(s);
      title = from == to ? '${su.name} $s:$from' : (from == 1 && to == su.ayahCount ? 'Surah ${su.name}' : '${su.name} $s:$from-$to');
    }
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: Space.s12),
      padding: const EdgeInsets.fromLTRB(Space.s12, Space.s8, Space.s12, Space.s12),
      decoration: BoxDecoration(
        color: done ? QuranColors.gold.withValues(alpha: .10) : c.surface,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: done ? QuranColors.gold : c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(color: QuranColors.velvet, borderRadius: BorderRadius.circular(999)),
                child: Text(
                  d.count == 1 ? 'Once' : '${d.count} times',
                  key: Key('dhikr-count-${d.n}'),
                  style: const TextStyle(color: QuranColors.goldLight, fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
              if (title != null) ...[
                const SizedBox(width: Space.s8),
                Flexible(
                  child: Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: t.labelMedium?.copyWith(color: QuranColors.goldDeep),
                  ),
                ),
              ],
              const Spacer(),
              IconButton(
                key: Key('dhikr-done-${d.n}'),
                tooltip: done ? 'Said (tap to undo)' : 'Mark as said',
                icon: Icon(done ? Icons.check_circle : Icons.radio_button_unchecked, color: done ? QuranColors.goldDeep : c.textMuted),
                onPressed: onDone,
              ),
            ],
          ),
          if (d.before.isNotEmpty)
            Text(
              d.before,
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.center,
              style: arabicText(17, color: c.textMuted),
            ),
          Text(
            arabic,
            key: Key('dhikr-arabic-${d.n}'),
            textDirection: TextDirection.rtl,
            textAlign: TextAlign.center,
            style: d.quran != null ? quranArabic(22, color: c.text) : arabicText(21, color: c.text),
          ),
          if (translit && d.translit.isNotEmpty) ...[
            const SizedBox(height: Space.s8),
            Text(
              d.translit,
              style: t.bodyMedium?.copyWith(fontStyle: FontStyle.italic, color: QuranColors.goldDeep),
            ),
          ],
          const SizedBox(height: Space.s8),
          if (urdu && urduText_ != null)
            Text(
              urduText_,
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.right,
              style: urduText(15, color: c.text).copyWith(height: 2),
            )
          else
            Text(english, key: Key('dhikr-english-${d.n}'), style: t.bodyMedium?.copyWith(height: 1.5)),
          if (d.virtue.isNotEmpty || d.source.isNotEmpty)
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              // its own (clear) Material, so the tap ripple shows on the coloured card
              child: Material(
                type: MaterialType.transparency,
                child: ExpansionTile(
                  key: Key('dhikr-more-${d.n}'),
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: Space.s4),
                  title: Text(d.virtue.isNotEmpty ? 'Its virtue and source' : 'Source', style: t.labelLarge?.copyWith(color: QuranColors.goldDeep)),
                  children: [
                    if (d.virtue.isNotEmpty)
                      Text(
                        d.virtue,
                        textDirection: TextDirection.rtl,
                        textAlign: TextAlign.right,
                        style: arabicText(16, color: c.text),
                      ),
                    if (d.source.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: Space.s4),
                        child: Text(
                          d.source,
                          textDirection: TextDirection.rtl,
                          textAlign: TextAlign.right,
                          style: arabicText(14, color: c.textMuted),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
