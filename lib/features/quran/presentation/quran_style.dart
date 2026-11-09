import 'package:flutter/material.dart';

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

/// Arabic of the Quran (Uthmani script): Amiri Quran.
TextStyle quranArabic(double size, {Color? color}) =>
    TextStyle(fontFamily: 'AmiriQuran', fontSize: size, color: color, height: 1.9);

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

/// The end-of-ayah mark with its number: ﴿٢٥٥﴾.
String ayahEnd(int n) => '﴿${arabicDigits(n)}﴾';
