import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../application/quran_providers.dart';
import '../data/quran_data.dart';
import '../domain/daily.dart';
import 'cabinet_painters.dart';
import 'daily_sheet.dart';
import 'quran_style.dart';

/// Home's Quran corner: a gold-framed cabinet, full width and low, with the Quran in a lit glass niche on the left
/// (tap it: the lamp comes on and the Quran opens) and the ayah or hadith of the day on the right, in Urdu or English.
class QuranCabinet extends ConsumerStatefulWidget {
  const QuranCabinet({super.key, this.now});

  /// Today (tests pass a fixed date).
  final DateTime? now;

  @override
  ConsumerState<QuranCabinet> createState() => _QuranCabinetState();
}

class _QuranCabinetState extends ConsumerState<QuranCabinet> with SingleTickerProviderStateMixin {
  late final AnimationController _light = AnimationController(vsync: this, duration: const Duration(milliseconds: 750));
  bool _hadith = false;
  bool _opening = false;

  @override
  void dispose() {
    _light.dispose();
    super.dispose();
  }

  Future<void> _openQuran() async {
    if (_opening) return;
    _opening = true;
    HapticFeedback.lightImpact();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) {
      _light.value = 1;
    } else {
      await _light.animateTo(1, curve: Curves.easeOutCubic);
    }
    if (!mounted) return;
    await context.push(Routes.quran);
    if (!mounted) return;
    _opening = false;
    if (reduce) {
      _light.value = 0;
    } else {
      await _light.animateTo(0, duration: const Duration(milliseconds: 900), curve: Curves.easeIn);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(dailyLangProvider);
    final urdu = lang == DailyLang.urdu;
    final quran = ref.watch(quranDataProvider).value;
    final hadiths = ref.watch(hadithDataProvider).value;
    final last = ref.watch(quranLastReadProvider);
    final now = widget.now ?? DateTime.now();

    return Semantics(
      container: true,
      label: urdu ? 'قرآن مجید' : 'The Holy Quran',
      child: Container(
        key: const Key('quran-cabinet'),
        decoration: BoxDecoration(
          gradient: QuranColors.goldGradient,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(color: Color(0x26000000), blurRadius: 12, offset: Offset(0, 3)),
          ],
        ),
        padding: const EdgeInsets.all(3),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(13),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [QuranColors.velvet, QuranColors.velvetDeep],
              ),
            ),
            child: CustomPaint(
              painter: const StarLatticePainter(),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 2, 10, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(urdu),
                    const SizedBox(height: 2),
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _niche(urdu, quran, last),
                          const SizedBox(width: 12),
                          Expanded(child: _daily(urdu, quran, hadiths, now)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(bool urdu) => Wrap(
    alignment: WrapAlignment.spaceBetween,
    crossAxisAlignment: WrapCrossAlignment.center,
    runSpacing: 0,
    spacing: 8,
    children: [
      _Pills(
        urdu: urdu,
        items: [
          _Pill(
            key: const Key('daily-tab-ayah'),
            label: urdu ? 'آج کی آیت' : 'Daily Ayah',
            semantics: urdu ? 'آج کی آیت' : 'Ayah of the day',
            selected: !_hadith,
            onTap: () => setState(() => _hadith = false),
          ),
          _Pill(
            key: const Key('daily-tab-hadith'),
            label: urdu ? 'آج کی حدیث' : 'Daily Hadith',
            semantics: urdu ? 'آج کی حدیث' : 'Hadith of the day',
            selected: _hadith,
            onTap: () => setState(() => _hadith = true),
          ),
        ],
      ),
      _Pills(
        urdu: urdu,
        items: [
          _Pill(
            key: const Key('daily-lang-urdu'),
            label: 'اردو',
            labelIsUrdu: true,
            semantics: 'Urdu translation',
            selected: urdu,
            onTap: () => ref.read(dailyLangProvider.notifier).set(DailyLang.urdu),
          ),
          _Pill(
            key: const Key('daily-lang-english'),
            label: 'English',
            labelIsUrdu: false,
            semantics: 'English translation',
            selected: !urdu,
            onTap: () => ref.read(dailyLangProvider.notifier).set(DailyLang.english),
          ),
        ],
      ),
    ],
  );

  Widget _niche(bool urdu, QuranData? q, (int, int)? last) {
    final lastName = q != null && last != null && q.valid(last.$1, last.$2) ? q.surah(last.$1) : null;
    return Semantics(
      button: true,
      label: urdu ? 'قرآن کھولیں' : 'Open the Quran',
      child: GestureDetector(
        key: const Key('quran-open'),
        onTap: _openQuran,
        child: SizedBox(
          width: 108,
          child: Column(
            children: [
              SizedBox(
                height: 128,
                child: AnimatedBuilder(
                  animation: _light,
                  builder: (_, _) => CustomPaint(
                    size: const Size(108, 128),
                    painter: NichePainter(light: _light.value, lift: _light.value),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                urdu ? 'قرآن پڑھیں' : 'Read Quran',
                textAlign: TextAlign.center,
                style: urdu
                    ? urduText(12, color: QuranColors.goldLight, weight: FontWeight.w600).copyWith(height: 1.3)
                    : const TextStyle(color: QuranColors.goldLight, fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
              if (lastName != null)
                Text(
                  urdu ? 'جاری: ${lastName.arabic.replaceAll('سُوْرَةُ ', '')} ${urduDigits(last!.$2)}' : 'Continue ${last!.$1}:${last.$2}',
                  key: const Key('quran-continue-label'),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: urdu
                      ? urduText(10, color: QuranColors.creamMuted).copyWith(height: 1.3)
                      : const TextStyle(color: QuranColors.creamMuted, fontSize: 10.5),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _daily(bool urdu, QuranData? q, HadithData? h, DateTime now) {
    Widget body;
    if (!_hadith) {
      if (q == null) {
        body = _loading(urdu);
      } else {
        final d = dailyAyah(q, now);
        final translation = (urdu ? d.urdu : d.english).join(' ');
        body = _DailyText(
          key: ValueKey('ayah-${d.ref}-$urdu'),
          arabic: d.arabic.join(' '),
          arabicIsQuran: true,
          translation: translation,
          urdu: urdu,
          reference: urdu ? '${d.surah.arabic} · ${_urduRef(d)}' : '${d.surah.name} ${d.ref}',
        );
      }
    } else {
      if (h == null) {
        body = _loading(urdu);
      } else {
        final d = dailyHadith(h, now);
        body = _DailyText(
          key: ValueKey('hadith-${d.number}-$urdu'),
          translation: urdu ? d.urduSaying : d.english,
          urdu: urdu,
          reference: urdu ? d.referenceUrdu : d.reference,
        );
      }
    }
    return Semantics(
      button: true,
      label: urdu ? 'مکمل پڑھیں' : 'Read in full',
      child: GestureDetector(
        key: const Key('daily-open'),
        behavior: HitTestBehavior.opaque,
        onTap: q == null || h == null ? null : () => showDailySheet(context, hadith: _hadith, now: widget.now ?? DateTime.now()),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: .18),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: QuranColors.gold.withValues(alpha: .35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _FadeIn(key: body.key, child: body)),
            ],
          ),
        ),
      ),
    );
  }

  static String _urduRef(DailyAyah d) =>
      d.from == d.to ? 'آیت ${urduDigits(d.from)}' : 'آیات ${urduDigits(d.from)}–${urduDigits(d.to)}';

  Widget _loading(bool urdu) => Center(
    child: Text(
      urdu ? 'لوڈ ہو رہا ہے…' : 'Loading…',
      style: urdu ? urduText(12, color: QuranColors.creamMuted) : const TextStyle(color: QuranColors.creamMuted, fontSize: 12),
    ),
  );
}

/// A pair of choices drawn as slim gold pills, each with a full 48-pixel-high tap area.
class _Pills extends StatelessWidget {
  const _Pills({required this.urdu, required this.items});
  final bool urdu;
  final List<_Pill> items;

  @override
  Widget build(BuildContext context) => Wrap(children: items); // big text: the pills go onto a second line
}

class _Pill extends StatelessWidget {
  const _Pill({
    super.key,
    required this.label,
    required this.semantics,
    required this.selected,
    required this.onTap,
    this.labelIsUrdu,
  });
  final String label, semantics;
  final bool selected;
  final VoidCallback onTap;

  /// Whether [label] itself is Urdu (null: decide from the script of the label).
  final bool? labelIsUrdu;

  @override
  Widget build(BuildContext context) {
    final isUrdu = labelIsUrdu ?? RegExp(r'[\u0600-\u06FF]').hasMatch(label);
    final fg = selected ? QuranColors.velvetDeep : QuranColors.creamMuted;
    return Semantics(
      button: true,
      selected: selected,
      label: semantics,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Center(
              widthFactor: 1,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: EdgeInsets.symmetric(horizontal: 11, vertical: isUrdu ? 0 : 6),
                decoration: BoxDecoration(
                  gradient: selected ? QuranColors.goldGradient : null,
                  color: selected ? null : Colors.black.withValues(alpha: .2),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: QuranColors.gold.withValues(alpha: selected ? .9 : .45)),
                ),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: isUrdu
                      ? urduText(12, color: fg, weight: FontWeight.w700).copyWith(height: 1.6)
                      : TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg, height: 1.2),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The day's text in the card: Arabic (ayah only), then the translation, then the reference. Long texts are cut
/// with "…"; tapping opens everything.
class _DailyText extends StatelessWidget {
  const _DailyText({
    super.key,
    this.arabic,
    this.arabicIsQuran = false,
    required this.translation,
    required this.urdu,
    required this.reference,
  });
  final String? arabic;
  final bool arabicIsQuran, urdu;
  final String translation, reference;

  @override
  Widget build(BuildContext context) {
    final dir = urdu ? TextDirection.rtl : TextDirection.ltr;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (arabic != null)
          Text(
            arabic!,
            key: const Key('daily-arabic'),
            textDirection: TextDirection.rtl,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: quranArabic(17, color: QuranColors.goldLight).copyWith(height: 1.6),
          ),
        Expanded(
          child: Align(
            alignment: Alignment.topCenter,
            child: Text(
              translation,
              key: const Key('daily-translation'),
              textDirection: dir,
              textAlign: TextAlign.center,
              maxLines: urdu ? (arabic == null ? 4 : 3) : (arabic == null ? 5 : 3),
              overflow: TextOverflow.ellipsis,
              style: urdu
                  ? urduText(12.5, color: QuranColors.cream).copyWith(height: 1.75)
                  : const TextStyle(color: QuranColors.cream, fontSize: 12.5, height: 1.4),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Directionality(
          textDirection: dir,
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: Text(
                  reference,
                  key: const Key('daily-reference'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: urdu
                      ? urduText(10.5, color: QuranColors.gold).copyWith(height: 1.3)
                      : const TextStyle(color: QuranColors.gold, fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  urdu ? 'مکمل پڑھیں' : 'Read more ›',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: urdu
                      ? urduText(10.5, color: QuranColors.goldLight).copyWith(height: 1.3)
                      : const TextStyle(color: QuranColors.goldLight, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Fades its child in when it first appears (a new key = a new fade); nothing of the previous content stays behind.
class _FadeIn extends StatelessWidget {
  const _FadeIn({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      builder: (_, v, c) => Opacity(opacity: v, child: c),
      child: child,
    );
  }
}
