import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../application/quran_audio.dart';
import '../application/quran_providers.dart';
import '../data/quran_data.dart' show urduTranslations;
import '../domain/daily.dart';
import 'daily_share.dart';
import 'quran_style.dart';

/// The day's ayah or hadith in full, with both translations a tap apart, Listen (ayah), Open in Quran, Share picture and Copy.
Future<void> showDailySheet(BuildContext context, {required bool hadith, required DateTime now}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  builder: (_) => _DailySheet(hadith: hadith, now: now),
);

class _DailySheet extends ConsumerWidget {
  const _DailySheet({required this.hadith, required this.now});
  final bool hadith;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final urdu = ref.watch(dailyLangProvider) == DailyLang.urdu;
    final q = ref.watch(quranDataProvider).value;
    final h = ref.watch(hadithDataProvider).value;
    if (q == null || h == null) return const SizedBox.shrink();
    final audio = ref.watch(quranAudioProvider);

    late final String title, arabic, translation, reference, copyText;
    DailyAyah? ayah;
    if (!hadith) {
      final d = ayah = dailyAyah(q, now);
      title = urdu ? 'آج کی آیت' : 'Ayah of the day';
      arabic = [for (var i = 0; i < d.arabic.length; i++) ayahWithEnd(d.arabic[i], d.from + i)].join(' ');
      translation = (urdu ? d.urdu : d.english).join(' ');
      reference = urdu ? '${d.surah.arabic} (${urduDigits(d.surah.number)})، آیت ${urduDigits(d.from)}${d.to > d.from ? '–${urduDigits(d.to)}' : ''}' : 'Surah ${d.surah.name} (${d.surah.english}) ${d.ref}';
      copyText = '${d.arabic.join(' ')}\n\n$translation\n\n— ${urdu ? reference : 'Quran ${d.ref}'}';
    } else {
      final d = dailyHadith(h, now);
      title = urdu ? 'آج کی حدیث' : 'Hadith of the day';
      arabic = d.arabic;
      translation = urdu ? d.urdu : d.english;
      reference = urdu ? d.referenceUrdu : d.reference;
      copyText = '$translation\n\n— $reference';
    }
    final playingThis = ayah != null && audio.active && audio.surah == ayah.surah.number && (audio.ayah ?? 0) >= ayah.from && (audio.ayah ?? 0) <= ayah.to;
    final dir = urdu ? TextDirection.rtl : TextDirection.ltr;

    return DraggableScrollableSheet(
      initialChildSize: .72,
      minChildSize: .4,
      maxChildSize: .95,
      expand: false,
      builder: (context, scroll) => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [QuranColors.velvet, QuranColors.velvetDeep]),
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          border: Border(top: BorderSide(color: QuranColors.gold, width: 2)),
        ),
        child: ListView(
          key: const Key('daily-sheet'),
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
          children: [
            Center(
              child: Container(width: 40, height: 4, decoration: BoxDecoration(color: QuranColors.gold.withValues(alpha: .6), borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    textDirection: dir,
                    style: urdu ? urduText(18, color: QuranColors.goldLight, weight: FontWeight.w700) : const TextStyle(color: QuranColors.goldLight, fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                SegmentedButton<bool>(
                  key: const Key('sheet-lang'),
                  showSelectedIcon: false,
                  style: SegmentedButton.styleFrom(
                    foregroundColor: QuranColors.creamMuted,
                    selectedForegroundColor: QuranColors.velvetDeep,
                    selectedBackgroundColor: QuranColors.gold,
                    side: BorderSide(color: QuranColors.gold.withValues(alpha: .6)),
                    visualDensity: VisualDensity.compact,
                  ),
                  segments: [
                    ButtonSegment(value: true, label: Text('اردو', style: urduText(12).copyWith(height: 1.2))),
                    const ButtonSegment(value: false, label: Text('English')),
                  ],
                  selected: {urdu},
                  onSelectionChanged: (s) => ref.read(dailyLangProvider.notifier).set(s.first ? DailyLang.urdu : DailyLang.english),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              arabic,
              key: const Key('sheet-arabic'),
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.justify,
              style: hadith ? arabicText(19, color: QuranColors.goldLight) : quranArabic(24, color: QuranColors.goldLight),
            ),
            const SizedBox(height: 14),
            Container(height: 1, color: QuranColors.gold.withValues(alpha: .35)),
            const SizedBox(height: 14),
            Text.rich(
              urdu && (hadith || q.urduRtl)
                  ? urduSpan(translation, urduText(16, color: QuranColors.cream).copyWith(height: 2.05))
                  : TextSpan(text: translation, style: const TextStyle(color: QuranColors.cream, fontSize: 16, height: 1.55)),
              key: const Key('sheet-translation'),
              textDirection: urdu && (hadith || q.urduRtl) ? TextDirection.rtl : TextDirection.ltr,
              textAlign: TextAlign.justify,
            ),
            const SizedBox(height: 12),
            Text(
              reference,
              textDirection: dir,
              textAlign: urdu ? TextAlign.right : TextAlign.left,
              style: urdu ? urduText(13, color: QuranColors.gold) : const TextStyle(color: QuranColors.gold, fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                if (ayah != null)
                  FilledButton.icon(
                    key: const Key('sheet-listen'),
                    style: FilledButton.styleFrom(backgroundColor: QuranColors.gold, foregroundColor: QuranColors.velvetDeep),
                    onPressed: () {
                      final a = ref.read(quranAudioProvider.notifier);
                      if (playingThis) {
                        a.toggle();
                      } else {
                        a.playFrom(q, ayah!.surah.number, ayah.from, to: ayah.to);
                      }
                    },
                    icon: Icon(playingThis && audio.playing ? Icons.pause : Icons.play_arrow),
                    label: Text(playingThis && audio.playing ? (urdu ? 'روکیں' : 'Pause') : (urdu ? 'سنیں' : 'Listen'), style: urdu ? urduText(13).copyWith(height: 1.2) : null),
                  ),
                if (ayah != null)
                  OutlinedButton.icon(
                    key: const Key('sheet-open-quran'),
                    style: OutlinedButton.styleFrom(foregroundColor: QuranColors.goldLight, side: const BorderSide(color: QuranColors.gold)),
                    onPressed: () {
                      Navigator.of(context).pop();
                      context.push('${Routes.quran}/${ayah!.surah.number}?ayah=${ayah.from}');
                    },
                    icon: const Icon(Icons.menu_book_outlined),
                    label: Text(urdu ? 'قرآن میں کھولیں' : 'Open in Quran', style: urdu ? urduText(13).copyWith(height: 1.2) : null),
                  ),
                OutlinedButton.icon(
                  key: const Key('sheet-share'),
                  style: OutlinedButton.styleFrom(foregroundColor: QuranColors.goldLight, side: const BorderSide(color: QuranColors.gold)),
                  onPressed: () => showDailyShare(context, hadith: hadith, now: now),
                  icon: const Icon(Icons.image_outlined, size: 18),
                  label: Text(urdu ? 'تصویر بھیجیں' : 'Share picture', style: urdu ? urduText(13).copyWith(height: 1.2) : null),
                ),
                OutlinedButton.icon(
                  key: const Key('sheet-copy'),
                  style: OutlinedButton.styleFrom(foregroundColor: QuranColors.goldLight, side: const BorderSide(color: QuranColors.gold)),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: copyText));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(urdu ? 'کاپی ہو گیا' : 'Copied')));
                    }
                  },
                  icon: const Icon(Icons.copy, size: 18),
                  label: Text(urdu ? 'کاپی' : 'Copy', style: urdu ? urduText(13).copyWith(height: 1.2) : null),
                ),
              ],
            ),
            if (playingThis && audio.error != null) ...[
              const SizedBox(height: 10),
              Text(audio.error!, textAlign: TextAlign.center, style: const TextStyle(color: QuranColors.creamMuted, fontSize: 12)),
            ],
            const SizedBox(height: 20),
            Text(
              hadith
                  ? (urdu ? 'ماخذ: صحیح بخاری (عربی، اردو ترجمہ)۔' : 'Source: Sahih al-Bukhari, English translation by Muhammad Muhsin Khan.')
                  : (urdu
                        ? 'ترجمہ: ${urduTranslations.firstWhere((t) => t.name == q.urduName, orElse: () => urduTranslations.first).urdu}۔ عربی متن: شاہ فہد قرآن کمپلیکس۔'
                        : 'Translation: Saheeh International. Arabic text: King Fahd Quran Complex.'),
              textDirection: dir,
              textAlign: TextAlign.center,
              style: urdu ? urduText(11, color: QuranColors.creamMuted) : const TextStyle(color: QuranColors.creamMuted, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
