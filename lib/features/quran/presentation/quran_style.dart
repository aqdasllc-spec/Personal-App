import 'package:flutter/material.dart';

import '../data/quran_data.dart' show QuranScript;

/// The Quran corner's own look: deep green and gold, the same in light and dark mode (it is an object, a cabinet,
/// not part of the page's paper).
abstract final class QuranColors {
  static const velvet = Color(0xFF0B3B2D);
  static const velvetDeep = Color(0xFF062519);
  static const gold = Color(0xFFD4AF37);
  static const goldLight = Color(0xFFF6E7A6);
  static const goldDeep = Color(0xFF9C7A1E);
  static const cream = Color(0xFFF8F1DC);
  static const creamMuted = Color(0xFFD9CFB2);
  static const lamp = Color(0xFFFFD27A);

  static const goldGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [goldDeep, gold, goldLight, gold, goldDeep],
    stops: [0, .28, .5, .72, 1],
  );
}

/// The script the Quran is being shown in. Set by `quranDataProvider` whenever the choice changes; every screen that
/// shows the Arabic watches that provider, so it is rebuilt with the new script.
QuranScript activeQuranScript = QuranScript.indopak;

/// Arabic of the Quran: the Indo-Pak script in Scheherazade New (a bold, open Naskh like the mushafs printed in
/// Pakistan and India), or the Madinah (Uthmani) script in Amiri Quran.
TextStyle quranArabic(double size, {Color? color}) => activeQuranScript == QuranScript.indopak
    ? TextStyle(fontFamily: 'ScheherazadeNew', fontSize: size, color: color, height: 1.9)
    : TextStyle(fontFamily: 'AmiriQuran', fontSize: size, color: color, height: 1.9);

/// Urdu (Nastaliq). The Naskh fallback covers the few marks Nastaliq lacks.
TextStyle urduText(double size, {Color? color, FontWeight? weight}) => TextStyle(
  fontFamily: 'NotoNastaliqUrdu',
  fontFamilyFallback: const ['ScheherazadeNew'],
  fontSize: size,
  color: color,
  fontWeight: weight,
  height: 1.7,
);

/// Arabic that is not Quran text (hadith): Scheherazade New, an easy-to-read Naskh.
TextStyle arabicText(double size, {Color? color}) =>
    TextStyle(fontFamily: 'ScheherazadeNew', fontSize: size, color: color, height: 1.7);

/// Western digits to Arabic-Indic (١٢٣), for ayah numbers inside Arabic text.
String arabicDigits(int n) => n.toString().split('').map((d) => String.fromCharCode(0x0660 + int.parse(d))).join();

/// Western digits to Urdu (Extended Arabic-Indic, ۱۲۳).
String urduDigits(int n) => n.toString().split('').map((d) => String.fromCharCode(0x06F0 + int.parse(d))).join();

/// The end-of-ayah mark with its number: ﴿۲۵۵﴾ in Indo-Pak (Urdu digits, as Pakistani mushafs write them), ﴿٢٥٥﴾ in
/// the Madinah script.
String ayahEnd(int n) => activeQuranScript == QuranScript.indopak ? '﴿${urduDigits(n)}﴾' : '﴿${arabicDigits(n)}﴾';

/// An ayah followed by its end mark, joined by a no-break space so the number never sits alone on the next line.
String ayahWithEnd(String text, int n) => '$text\u00A0${ayahEnd(n)}';

/// Urdu text whose ﷺ is set in the Naskh font: the Nastaliq one draws it tall enough to run into the line above.
TextSpan urduSpan(String text, TextStyle style) {
  if (!text.contains('\uFDFA')) return TextSpan(text: text, style: style);
  final parts = text.split('\uFDFA');
  return TextSpan(
    style: style,
    children: [
      for (var i = 0; i < parts.length; i++) ...[
        TextSpan(text: parts[i]),
        if (i < parts.length - 1) TextSpan(text: '\uFDFA', style: style.copyWith(fontFamily: 'ScheherazadeNew', fontSize: (style.fontSize ?? 15) * 1.05)),
      ],
    ],
  );
}

/// A translation of the Quran (Urdu, Roman Urdu or English), justified and in its own direction.
class QuranTranslation extends StatelessWidget {
  const QuranTranslation(this.text, {super.key, required this.urdu, required this.rtl, this.size = 15, this.color, this.center = false});
  final String text;

  /// [urdu]: the Urdu translation (Nastaliq when [rtl], plain letters for Roman Urdu); otherwise English.
  final bool urdu, rtl, center;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final align = center ? TextAlign.center : TextAlign.justify;
    if (urdu && rtl) {
      return Text.rich(urduSpan(text, urduText(size, color: color).copyWith(height: 2.05)), textDirection: TextDirection.rtl, textAlign: align);
    }
    final base = Theme.of(context).textTheme.bodyLarge ?? const TextStyle();
    return Text(text, textAlign: align, style: base.copyWith(fontSize: size, color: color, height: 1.55));
  }
}
