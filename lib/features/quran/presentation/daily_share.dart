import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/tokens.dart';
import '../../backup/backup_controller.dart' show backupTempDirProvider;
import '../../library/application/export_notes.dart' show shareFileProvider;
import '../application/quran_providers.dart';
import '../domain/daily.dart';
import '../prayer/prayer.dart' show hijriEnglish;
import '../prayer/prayer_providers.dart';
import 'quran_style.dart';

/// Which translation goes on the daily picture.
enum ShareLang { urdu, english, both }

/// The ayah or hadith of the day as a picture to send: a parchment card under a green arch (unlike the dark card used
/// for single ayahs), with the date in both calendars.
Future<void> showDailyShare(BuildContext context, {required bool hadith, required DateTime now}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _DailyShareSheet(hadith: hadith, now: now),
);

const _parchment = Color(0xFFFBF5E4);
const _ink = Color(0xFF0B3B2D);
const _inkSoft = Color(0xFF36584C);

class _DailyShareSheet extends ConsumerStatefulWidget {
  const _DailyShareSheet({required this.hadith, required this.now});
  final bool hadith;
  final DateTime now;
  @override
  ConsumerState<_DailyShareSheet> createState() => _DailyShareSheetState();
}

class _DailyShareSheetState extends ConsumerState<_DailyShareSheet> {
  final _card = GlobalKey();
  late ShareLang _lang = ref.read(dailyLangProvider) == DailyLang.urdu ? ShareLang.urdu : ShareLang.english;
  bool _busy = false;

  Future<void> _share(String name, String subject) async {
    setState(() => _busy = true);
    try {
      final boundary = _card.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final dir = await ref.read(backupTempDirProvider)();
      final f = File('${dir.path}/$name.png');
      await f.writeAsBytes(png!.buffer.asUint8List(), flush: true);
      await ref.read(shareFileProvider)(f, subject);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not make the picture: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = ref.watch(quranDataProvider).value;
    final h = ref.watch(hadithDataProvider).value;
    if (q == null || h == null) return const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()));
    final offset = ref.watch(prayerSettingsProvider).hijriOffset;
    final now = widget.now;
    final urdu = _lang != ShareLang.english, english = _lang != ShareLang.urdu;

    late final String arabic, titleEn, titleUr, refEn, refUr, file, subject;
    String? tUr, tEn;
    if (!widget.hadith) {
      final d = dailyAyah(q, now);
      arabic = [for (var i = 0; i < d.arabic.length; i++) ayahWithEnd(d.arabic[i], d.from + i)].join(' ');
      tUr = d.urdu.join(' ');
      tEn = d.english.join(' ');
      titleEn = 'Ayah of the Day';
      titleUr = 'آج کی آیت';
      refEn = 'Surah ${d.surah.name} ${d.ref}';
      refUr = '${d.surah.arabic}، آیت ${urduDigits(d.from)}${d.to > d.from ? '–${urduDigits(d.to)}' : ''}';
      file = 'ayah-of-the-day-${d.surah.number}-${d.from}';
      subject = 'Ayah of the day · Quran ${d.ref}';
    } else {
      final d = dailyHadith(h, now);
      arabic = d.arabic;
      tUr = d.urdu;
      tEn = d.english;
      titleEn = 'Hadith of the Day';
      titleUr = 'آج کی حدیث';
      refEn = d.reference;
      refUr = d.referenceUrdu;
      file = 'hadith-of-the-day';
      subject = 'Hadith of the day · ${d.reference}';
    }
    final long = arabic.length + (urdu ? tUr.length : 0) + (english ? tEn.length : 0);
    final scale = long > 900 ? .78 : (long > 600 ? .88 : 1.0); // long passages get smaller type so the card stays a card
    final date = '${MaterialLocalizations.of(context).formatMediumDate(now)} · ${hijriEnglish(now, offset)}';

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Space.s16, 0, Space.s16, Space.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RepaintBoundary(
              key: _card,
              child: Container(
                key: const Key('daily-share-card'),
                decoration: BoxDecoration(color: _parchment, borderRadius: BorderRadius.circular(6)),
                padding: const EdgeInsets.all(8),
                child: Container(
                  decoration: BoxDecoration(border: Border.all(color: QuranColors.gold, width: 2.5), borderRadius: BorderRadius.circular(4)),
                  padding: const EdgeInsets.all(3),
                  child: Container(
                    decoration: BoxDecoration(border: Border.all(color: QuranColors.goldDeep.withValues(alpha: .6)), borderRadius: BorderRadius.circular(2)),
                    child: Column(
                      children: [
                        // the green arch with the title
                        CustomPaint(
                          painter: _ArchPainter(),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 26, 16, 14),
                            child: Column(
                              children: [
                                Text(titleUr, textDirection: TextDirection.rtl, style: urduText(20, color: QuranColors.goldLight, weight: FontWeight.w700)),
                                Text(titleEn.toUpperCase(), style: const TextStyle(color: QuranColors.gold, fontSize: 11.5, letterSpacing: 2.2, fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
                          child: Column(
                            children: [
                              Text(
                                arabic,
                                key: const Key('daily-share-arabic'),
                                textDirection: TextDirection.rtl,
                                textAlign: TextAlign.center,
                                style: widget.hadith ? arabicText(19 * scale, color: _ink) : quranArabic(24 * scale, color: _ink),
                              ),
                              const SizedBox(height: 12),
                              _Flourish(),
                              if (urdu) ...[
                                const SizedBox(height: 10),
                                Text.rich(
                                  widget.hadith || q.urduRtl
                                      ? urduSpan(tUr, urduText(15 * scale, color: _inkSoft).copyWith(height: 2.0))
                                      : TextSpan(text: tUr, style: TextStyle(color: _inkSoft, fontSize: 14.5 * scale, height: 1.5)),
                                  key: const Key('daily-share-urdu'),
                                  textDirection: widget.hadith || q.urduRtl ? TextDirection.rtl : TextDirection.ltr,
                                  textAlign: TextAlign.center,
                                ),
                              ],
                              if (english) ...[
                                const SizedBox(height: 10),
                                Text(
                                  tEn,
                                  key: const Key('daily-share-english'),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: _inkSoft, fontSize: 14.5 * scale, height: 1.5, fontStyle: FontStyle.italic),
                                ),
                              ],
                              const SizedBox(height: 14),
                              if (urdu) Text(refUr, textDirection: TextDirection.rtl, textAlign: TextAlign.center, style: urduText(12.5, color: QuranColors.goldDeep)),
                              if (english) Text(refEn, textAlign: TextAlign.center, style: const TextStyle(color: QuranColors.goldDeep, fontSize: 12.5, fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                        Container(
                          width: double.infinity,
                          color: _ink.withValues(alpha: .06),
                          padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 10),
                          child: Text(date, key: const Key('daily-share-date'), textAlign: TextAlign.center, style: const TextStyle(color: _inkSoft, fontSize: 11, letterSpacing: .3)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: Space.s12),
            SegmentedButton<ShareLang>(
              key: const Key('daily-share-lang'),
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: ShareLang.urdu, label: Text('اردو', style: urduText(13).copyWith(height: 1.2))),
                const ButtonSegment(value: ShareLang.english, label: Text('English')),
                const ButtonSegment(value: ShareLang.both, label: Text('Both')),
              ],
              selected: {_lang},
              onSelectionChanged: (v) => setState(() => _lang = v.first),
            ),
            const SizedBox(height: Space.s12),
            FilledButton.icon(
              key: const Key('daily-share-go'),
              onPressed: _busy ? null : () => _share(file, subject),
              icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.share),
              label: const Text('Share picture'),
            ),
            const SizedBox(height: Space.s4),
            Text(
              widget.hadith ? 'Sahih al-Bukhari; translations as shown in Folio.' : 'Translations: ${q.urduName} (Urdu), Saheeh International (English).',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// The top of the card: a pointed (mihrab) arch in deep green with a gold edge.
class _ArchPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final arch = Path()
      ..moveTo(0, h)
      ..lineTo(0, h * .45)
      ..quadraticBezierTo(w * .02, h * .12, w * .5, 0)
      ..quadraticBezierTo(w * .98, h * .12, w, h * .45)
      ..lineTo(w, h)
      ..close();
    canvas.drawPath(arch, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [QuranColors.velvet, QuranColors.velvetDeep]).createShader(Offset.zero & size));
    canvas.drawPath(arch, Paint()
      ..color = QuranColors.gold
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2);
    // a small star at the apex
    final c = Offset(w / 2, 11), r = 5.0;
    final star = Path();
    for (var i = 0; i < 16; i++) {
      final a = i * math.pi / 8;
      final rr = i.isEven ? r : r * .45;
      final p = c + Offset(rr * math.cos(a), rr * math.sin(a));
      i == 0 ? star.moveTo(p.dx, p.dy) : star.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(star..close(), Paint()..color = QuranColors.gold);
  }

  @override
  bool shouldRepaint(_ArchPainter oldDelegate) => false;
}

/// A thin gold line with a diamond in the middle.
class _Flourish extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Container(width: 60, height: 1, color: QuranColors.gold),
      const SizedBox(width: 6),
      Transform.rotate(angle: .785, child: Container(width: 7, height: 7, color: QuranColors.gold)),
      const SizedBox(width: 6),
      Container(width: 60, height: 1, color: QuranColors.gold),
    ],
  );
}
