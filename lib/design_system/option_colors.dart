import 'package:flutter/material.dart';

/// Colour pairs for select/status options (docs/02 §2). Option colours are stored by NAME so
/// both themes stay legible; every pair is checked for >= 4.5:1 contrast in tests.
abstract final class OptionColors {
  static const names = [
    'gray',
    'brown',
    'orange',
    'yellow',
    'green',
    'teal',
    'blue',
    'purple',
    'pink',
    'red',
  ];

  static const _light = {
    'gray': (Color(0xFFE8E3D9), Color(0xFF5B554A)),
    'brown': (Color(0xFFEADFD2), Color(0xFF6B4A2B)),
    'orange': (Color(0xFFF6E0C8), Color(0xFF8A5214)),
    'yellow': (Color(0xFFF5EBBF), Color(0xFF6F5A0E)),
    'green': (Color(0xFFD5E8D9), Color(0xFF2C5E3A)),
    'teal': (Color(0xFFCFE7E5), Color(0xFF1F5E5A)),
    'blue': (Color(0xFFD6E4F2), Color(0xFF2A5A86)),
    'purple': (Color(0xFFE3DAF0), Color(0xFF5B3F86)),
    'pink': (Color(0xFFF3D9E4), Color(0xFF85335A)),
    'red': (Color(0xFFF3D6CF), Color(0xFF8E2F20)),
  };

  static const _dark = {
    'gray': (Color(0xFF34302A), Color(0xFFC9C1B1)),
    'brown': (Color(0xFF42342A), Color(0xFFDDBF9F)),
    'orange': (Color(0xFF4A3320), Color(0xFFF0BE88)),
    'yellow': (Color(0xFF463E1A), Color(0xFFEBD88A)),
    'green': (Color(0xFF233A29), Color(0xFF9AD6AB)),
    'teal': (Color(0xFF1D3A38), Color(0xFF8FD3CD)),
    'blue': (Color(0xFF1F3346), Color(0xFF9CC6EE)),
    'purple': (Color(0xFF33294A), Color(0xFFC8B0F0)),
    'pink': (Color(0xFF48283A), Color(0xFFEFA9C8)),
    'red': (Color(0xFF4A2822), Color(0xFFF0A596)),
  };

  /// (background, foreground) for [name]; unknown names fall back to gray.
  static (Color, Color) of(String name, Brightness b) {
    final m = b == Brightness.dark ? _dark : _light;
    return m[name] ?? m['gray']!;
  }
}
