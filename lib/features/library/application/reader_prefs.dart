import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../app/providers.dart';

/// "Only a stylus draws" (finger touches scroll and zoom even while the pen is on). Remembered on this device.
class StylusOnly extends Notifier<bool> {
  static const key = 'pen_stylus_only';
  @override
  bool build() {
    Future.microtask(() async {
      try {
        final v = await ref.read(syncedStoreProvider).state(key);
        if (v == '1') state = true;
      } catch (_) {}
    });
    return false;
  }

  void set(bool v) {
    state = v;
    try {
      ref.read(syncedStoreProvider).setState(key, v ? '1' : '0');
    } catch (_) {}
  }
}

final stylusOnlyProvider = NotifierProvider<StylusOnly, bool>(StylusOnly.new);

/// Colour scheme of the page while reading.
enum ReaderTheme {
  normal('Original'),
  paper('Paper'),
  sepia('Sepia'),
  night('Night'),
  black('Black');

  const ReaderTheme(this.label);
  final String label;

  /// Colour filter applied over the rendered page (null = untouched).
  ColorFilter? get filter => switch (this) {
    ReaderTheme.normal => null,
    ReaderTheme.paper => const ColorFilter.mode(
      Color(0xFFF3EBD6),
      BlendMode.multiply,
    ),
    ReaderTheme.sepia => const ColorFilter.matrix(<double>[
      0.35, 0.69, 0.17, 0, 0, //
      0.31, 0.62, 0.15, 0, 0,
      0.24, 0.48, 0.12, 0, 0,
      0, 0, 0, 1, 0,
    ]),
    // inverted, but not pure black: easier on the eyes at night
    ReaderTheme.night => const ColorFilter.matrix(<double>[
      -0.85, 0, 0, 0, 235, //
      0, -0.85, 0, 0, 235,
      0, 0, -0.85, 0, 235,
      0, 0, 0, 1, 0,
    ]),
    // pure black for OLED screens
    ReaderTheme.black => const ColorFilter.matrix(<double>[
      -1, 0, 0, 0, 255, //
      0, -1, 0, 0, 255,
      0, 0, -1, 0, 255,
      0, 0, 0, 1, 0,
    ]),
  };

  /// The viewer background BEFORE the filter (so after it the page surround matches the mood of the theme).
  Color get background => switch (this) {
    ReaderTheme.normal => const Color(0xFFCFCFCF),
    ReaderTheme.paper => const Color(0xFFE6DFCB),
    ReaderTheme.sepia => const Color(0xFFD8D0C0),
    ReaderTheme.night => const Color(0xFFD0D0D0),
    ReaderTheme.black => const Color(0xFFFFFFFF),
  };

  /// A swatch for the picker: roughly how a white page with black text looks.
  (Color page, Color ink) get swatch => switch (this) {
    ReaderTheme.normal => (const Color(0xFFFFFFFF), const Color(0xFF000000)),
    ReaderTheme.paper => (const Color(0xFFF3EBD6), const Color(0xFF2B2418)),
    ReaderTheme.sepia => (const Color(0xFFF1E4C8), const Color(0xFF4A3520)),
    ReaderTheme.night => (const Color(0xFF121212), const Color(0xFFEBEBEB)),
    ReaderTheme.black => (const Color(0xFF000000), const Color(0xFFFFFFFF)),
  };
}

enum ReaderScroll {
  vertical('Scroll down'),
  horizontal('Swipe sideways');

  const ReaderScroll(this.label);
  final String label;
}

enum ReaderOrientation {
  auto('Auto'),
  portrait('Portrait'),
  landscape('Landscape');

  const ReaderOrientation(this.label);
  final String label;
}

/// Reading preferences (shared by all books).
@immutable
class ReaderPrefs {
  const ReaderPrefs({
    this.theme = ReaderTheme.normal,
    this.dim = 0,
    this.warmth = 0,
    this.scroll = ReaderScroll.vertical,
    this.tapTurn = true,
    this.keepAwake = true,
    this.orientation = ReaderOrientation.auto,
  });

  final ReaderTheme theme;

  /// 0..0.7: darkens the screen (a software "brightness" for reading in bed).
  final double dim;

  /// 0..1: warm amber tint that cuts blue light.
  final double warmth;
  final ReaderScroll scroll;

  /// Tap the left / right edge of the page to turn it (centre tap shows or hides the toolbar).
  final bool tapTurn;
  final bool keepAwake;
  final ReaderOrientation orientation;

  ReaderPrefs copyWith({
    ReaderTheme? theme,
    double? dim,
    double? warmth,
    ReaderScroll? scroll,
    bool? tapTurn,
    bool? keepAwake,
    ReaderOrientation? orientation,
  }) => ReaderPrefs(
    theme: theme ?? this.theme,
    dim: (dim ?? this.dim).clamp(0.0, 0.7),
    warmth: (warmth ?? this.warmth).clamp(0.0, 1.0),
    scroll: scroll ?? this.scroll,
    tapTurn: tapTurn ?? this.tapTurn,
    keepAwake: keepAwake ?? this.keepAwake,
    orientation: orientation ?? this.orientation,
  );

  String toJson() => jsonEncode({
    'theme': theme.name,
    'dim': dim,
    'warmth': warmth,
    'scroll': scroll.name,
    'tapTurn': tapTurn,
    'keepAwake': keepAwake,
    'orientation': orientation.name,
  });

  /// Forgiving: unknown / missing values fall back to the defaults.
  static ReaderPrefs fromJson(String? json) {
    if (json == null || json.isEmpty) return const ReaderPrefs();
    try {
      final m = jsonDecode(json) as Map;
      T pick<T extends Enum>(List<T> values, Object? v, T d) =>
          values.where((e) => e.name == v).firstOrNull ?? d;
      double num0(Object? v, double d) => v is num ? v.toDouble() : d;
      return ReaderPrefs(
        theme: pick(ReaderTheme.values, m['theme'], ReaderTheme.normal),
        dim: num0(m['dim'], 0).clamp(0.0, 0.7),
        warmth: num0(m['warmth'], 0).clamp(0.0, 1.0),
        scroll: pick(ReaderScroll.values, m['scroll'], ReaderScroll.vertical),
        tapTurn: m['tapTurn'] is bool ? m['tapTurn'] as bool : true,
        keepAwake: m['keepAwake'] is bool ? m['keepAwake'] as bool : true,
        orientation: pick(
          ReaderOrientation.values,
          m['orientation'],
          ReaderOrientation.auto,
        ),
      );
    } catch (_) {
      return const ReaderPrefs();
    }
  }

  @override
  bool operator ==(Object other) =>
      other is ReaderPrefs && other.toJson() == toJson();
  @override
  int get hashCode => toJson().hashCode;
}

const _prefsKey = 'reader_prefs';

class ReaderPrefsController extends Notifier<ReaderPrefs> {
  @override
  ReaderPrefs build() {
    Future.microtask(() async {
      try {
        final saved = await ref.read(syncedStoreProvider).state(_prefsKey);
        if (saved != null) state = ReaderPrefs.fromJson(saved);
      } catch (_) {}
    });
    return const ReaderPrefs();
  }

  void update(ReaderPrefs Function(ReaderPrefs) change) {
    state = change(state);
    try {
      ref.read(syncedStoreProvider).setState(_prefsKey, state.toJson());
    } catch (_) {}
  }
}

final readerPrefsProvider =
    NotifierProvider<ReaderPrefsController, ReaderPrefs>(
      ReaderPrefsController.new,
    );

/// Keeps the screen on while reading. Overridden in tests.
final screenAwakeProvider = Provider<void Function(bool on)>(
  (ref) => (on) {
    try {
      on ? WakelockPlus.enable() : WakelockPlus.disable();
    } catch (_) {}
  },
);

/// Locks the screen orientation / hides the system bars while reading. Overridden in tests.
abstract class ReaderSystem {
  void setOrientation(ReaderOrientation o);
  void setImmersive(bool on);
  void restore();
}

class PlatformReaderSystem implements ReaderSystem {
  @override
  void setOrientation(ReaderOrientation o) {
    SystemChrome.setPreferredOrientations(switch (o) {
      ReaderOrientation.auto => DeviceOrientation.values,
      ReaderOrientation.portrait => [DeviceOrientation.portraitUp],
      ReaderOrientation.landscape => [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ],
    });
  }

  @override
  void setImmersive(bool on) => SystemChrome.setEnabledSystemUIMode(
    on ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
  );

  @override
  void restore() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  }
}

final readerSystemProvider = Provider<ReaderSystem>(
  (ref) => PlatformReaderSystem(),
);
