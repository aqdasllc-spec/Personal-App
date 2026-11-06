import 'package:flutter/material.dart';

import 'tokens.dart';

/// Display serif for titles; UI sans for everything else. Fonts (Fraunces, Inter - both OFL)
/// are NOT bundled yet: until they are added under assets/fonts the platform serif/sans
/// fallbacks are used. Tracked in docs/06 Phase 1 checklist.
const _serif = 'Fraunces';
const _sans = 'Inter';
const _serifFallback = ['Georgia', 'Times New Roman', 'serif'];
const _sansFallback = ['Segoe UI', 'Roboto', 'Helvetica Neue', 'sans-serif'];

ThemeData buildTheme(Brightness b) {
  final c = b == Brightness.light ? FolioColors.light : FolioColors.dark;
  final scheme = ColorScheme(
    brightness: b,
    primary: c.accent,
    onPrimary: c.onAccent,
    secondary: c.brass,
    onSecondary: c.onAccent,
    error: c.danger,
    onError: c.onAccent,
    surface: c.surface,
    onSurface: c.text,
    surfaceContainerHighest: c.surface2,
    outline: c.border,
    onSurfaceVariant: c.textMuted,
  );
  TextStyle ui(double size, double h, {FontWeight w = FontWeight.w400, Color? color}) => TextStyle(
      fontFamily: _sans, fontFamilyFallback: _sansFallback, fontSize: size, height: h / size, fontWeight: w, color: color ?? c.text);
  TextStyle display(double size, double h) => TextStyle(
      fontFamily: _serif, fontFamilyFallback: _serifFallback, fontSize: size, height: h / size, fontWeight: FontWeight.w600, letterSpacing: -.2, color: c.text);

  return ThemeData(
    useMaterial3: true,
    brightness: b,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.bg,
    dividerColor: c.border,
    extensions: [c],
    textTheme: TextTheme(
      displaySmall: display(32, 40),
      headlineSmall: display(24, 32),
      titleLarge: display(20, 28),
      titleMedium: ui(16, 24, w: FontWeight.w600),
      bodyLarge: ui(16, 24),
      bodyMedium: ui(14, 20),
      labelLarge: ui(14, 20, w: FontWeight.w600),
      bodySmall: ui(12, 16, color: c.textMuted),
    ),
    cardTheme: CardThemeData(
      color: c.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.card), side: BorderSide(color: c.border)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.bg,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.input), borderSide: BorderSide(color: c.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.input), borderSide: BorderSide(color: c.border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.input), borderSide: BorderSide(color: c.accent, width: 2)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.accent,
        foregroundColor: c.onAccent,
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(backgroundColor: c.surface, indicatorColor: c.accentSoft),
    navigationRailTheme: NavigationRailThemeData(backgroundColor: c.surface, indicatorColor: c.accentSoft),
    dividerTheme: DividerThemeData(color: c.border, space: 1, thickness: 1),
  );
}
