import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/tokens.dart';
import '../data/quran_data.dart';
import '../data/tafsir.dart';
import 'quran_style.dart';

/// The tafsir of one ayah, in the chosen edition (switch editions at the top).
Future<void> showTafsirSheet(BuildContext context, QuranData q, int surah, int ayah) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => _TafsirSheet(quran: q, surah: surah, ayah: ayah),
);

final _arabicLine = RegExp(r'^[\s؀-ۿݐ-ݿࢠ-ࣿﭐ-﷿ﹰ-﻿\(\)\[\]﴾﴿0-9.,:;«»"!؟،]+$');

class _TafsirSheet extends ConsumerWidget {
  const _TafsirSheet({required this.quran, required this.surah, required this.ayah});
  final QuranData quran;
  final int surah, ayah;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ed = ref.watch(tafsirChoiceProvider);
    final data = ref.watch(surahTafsirProvider((ed.slug, surah)));
    final t = Theme.of(context).textTheme;
    final c = context.colors;
    final s = quran.surah(surah);
    final i = quran.indexOf(surah, ayah);
    return DraggableScrollableSheet(
      initialChildSize: .8,
      minChildSize: .4,
      maxChildSize: .95,
      expand: false,
      builder: (context, scroll) => ListView(
        key: const Key('tafsir-sheet'),
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(Space.s16, 0, Space.s16, Space.s24),
        children: [
          Row(
            children: [Expanded(child: Text('Tafsir · ${s.name} $surah:$ayah', style: t.titleMedium))],
          ),
          const SizedBox(height: Space.s8),
          DropdownButtonFormField<String>(
            key: const Key('tafsir-edition'),
            initialValue: ed.slug,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Tafsir', border: OutlineInputBorder(), isDense: true),
            items: [
              for (final e in tafsirEditions)
                DropdownMenuItem(
                  value: e.slug,
                  child: Text('${e.name} — ${e.author}', overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) {
              final e = tafsirEditions.where((e) => e.slug == v).firstOrNull;
              if (e != null) ref.read(tafsirChoiceProvider.notifier).set(e);
            },
          ),
          const SizedBox(height: Space.s12),
          Text(
            ayahWithEnd(quran.arabic[i], ayah),
            textDirection: TextDirection.rtl,
            textAlign: TextAlign.justify,
            style: quranArabic(22, color: c.text),
          ),
          const SizedBox(height: Space.s12),
          ...data.when(
            skipLoadingOnRefresh: false, // Try again shows it is trying
            loading: () => [
              const SizedBox(height: Space.s24),
              const Center(child: CircularProgressIndicator()),
              const SizedBox(height: Space.s8),
              Text('Getting the tafsir of ${s.name}… (once; then it is kept on the phone)', textAlign: TextAlign.center, style: t.bodySmall),
            ],
            error: (e, _) => [
              Text(
                '$e',
                key: const Key('tafsir-error'),
                style: t.bodyMedium?.copyWith(color: c.danger),
              ),
              const SizedBox(height: Space.s8),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonal(
                  key: const Key('tafsir-retry'),
                  onPressed: () => ref.invalidate(surahTafsirProvider((ed.slug, surah))),
                  child: const Text('Try again'),
                ),
              ),
            ],
            data: (st) {
              final x = st.of(ayah);
              if (x == null) return [Text('This tafsir has nothing for this ayah.', style: t.bodyMedium)];
              return [
                if (x.from != x.to)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.s8),
                    child: Text(
                      ed.urdu ? 'آیات ${urduDigits(x.from)}–${urduDigits(x.to)} کی تفسیر ایک ساتھ' : 'Ayahs ${x.from}–${x.to} are explained together',
                      key: const Key('tafsir-together'),
                      textDirection: ed.urdu ? TextDirection.rtl : TextDirection.ltr,
                      style: ed.urdu ? urduText(13, color: QuranColors.goldDeep) : t.labelMedium?.copyWith(color: QuranColors.goldDeep),
                    ),
                  ),
                for (final p in x.text.split(RegExp(r'\n+')).map((p) => p.trim()).where((p) => p.isNotEmpty))
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.s8),
                    child: _arabicLine.hasMatch(p) && !ed.urdu
                        ? Text(
                            p,
                            textDirection: TextDirection.rtl,
                            textAlign: TextAlign.center,
                            style: arabicText(18, color: QuranColors.goldDeep),
                          )
                        : (ed.urdu
                              ? Text.rich(urduSpan(p, urduText(15, color: c.text).copyWith(height: 2.05)), textDirection: TextDirection.rtl, textAlign: TextAlign.justify)
                              : Text(p, textAlign: TextAlign.justify, style: t.bodyLarge?.copyWith(height: 1.55))),
                  ),
                const SizedBox(height: Space.s8),
                Text('${ed.name}, ${ed.author}. Text from quran.com via the open Tafsir API.', style: t.bodySmall),
              ];
            },
          ),
        ],
      ),
    );
  }
}
