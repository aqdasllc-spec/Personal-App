import 'package:flutter/material.dart';

/// Design tokens (docs/02_UI_UX_DESIGN.md §2). Values here are the single source of truth
/// in code; /design/index.html mirrors them for the concept prototype.
@immutable
class FolioColors extends ThemeExtension<FolioColors> {
  const FolioColors({
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.border,
    required this.text,
    required this.textMuted,
    required this.accent,
    required this.accentSoft,
    required this.onAccent,
    required this.brass,
    required this.danger,
    required this.warn,
    required this.ok,
    required this.info,
  });

  final Color bg, surface, surface2, border, text, textMuted, accent, accentSoft, onAccent, brass, danger, warn, ok, info;

  static const light = FolioColors(
    bg: Color(0xFFF6F2EA),
    surface: Color(0xFFFFFDF8),
    surface2: Color(0xFFEFE9DC),
    border: Color(0xFFE2D9C8),
    text: Color(0xFF1F1B16),
    textMuted: Color(0xFF6F675B),
    accent: Color(0xFF2F5D50),
    accentSoft: Color(0xFFDCE9E3),
    onAccent: Color(0xFFFFFFFF),
    brass: Color(0xFFB5832A),
    danger: Color(0xFFB3402F),
    warn: Color(0xFFB7791F),
    ok: Color(0xFF3C7A4F),
    info: Color(0xFF346C9C),
  );

  static const dark = FolioColors(
    bg: Color(0xFF14120F),
    surface: Color(0xFF1C1A16),
    surface2: Color(0xFF25221C),
    border: Color(0xFF2F2B24),
    text: Color(0xFFF1EBDD),
    textMuted: Color(0xFFA59C8A),
    accent: Color(0xFF7CC1AC),
    accentSoft: Color(0xFF23382F),
    onAccent: Color(0xFF0F1F1A),
    brass: Color(0xFFD9AC4F),
    danger: Color(0xFFE58A78),
    warn: Color(0xFFE0B060),
    ok: Color(0xFF7CC593),
    info: Color(0xFF7FB3E0),
  );

  @override
  FolioColors copyWith() => this;

  @override
  FolioColors lerp(ThemeExtension<FolioColors>? other, double t) => t < .5 ? this : (other as FolioColors? ?? this);
}

/// Spacing scale (dp).
abstract final class Space {
  static const double s2 = 2, s4 = 4, s8 = 8, s12 = 12, s16 = 16, s24 = 24, s32 = 32, s48 = 48, s64 = 64;
}

abstract final class Radii {
  static const double input = 6, card = 10, sheet = 16, pill = 999;
}

abstract final class Motion {
  static const fast = Duration(milliseconds: 120);
  static const medium = Duration(milliseconds: 200);
  static const slow = Duration(milliseconds: 320);
  static const curve = Cubic(.2, .8, .2, 1);
}

extension FolioTheme on BuildContext {
  FolioColors get colors => Theme.of(this).extension<FolioColors>()!;
}

/// Window-size classes (docs/02 §4).
enum WindowClass {
  compact,
  medium,
  expanded;

  static WindowClass of(double width) => width < 600 ? compact : (width <= 1024 ? medium : expanded);
}
