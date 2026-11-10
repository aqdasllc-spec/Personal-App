import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../library/application/reader_prefs.dart' show ReaderOrientation, ReaderSystem, readerSystemProvider, screenAwakeProvider;
import '../../settings/rotation.dart' show OrientationLock, RotationMode, orientationLockProvider, rotationProvider;
import '../application/quran_providers.dart';
import '../data/quran_data.dart';
import 'quran_style.dart';

/// Tilawat mode settings: scroll speed (1-20), page colour, translation under the Arabic, rotation. Remembered.
class TilawatSettings {
  const TilawatSettings({this.speed = 5, this.night = true, this.translation = false, this.orientation = ReaderOrientation.auto});
  final int speed;
  final bool night, translation;
  final ReaderOrientation orientation;

  /// Pixels a second at text size 1 (bigger text scrolls a little faster, so the reading pace stays similar).
  double get pixelsPerSecond => 4.0 + speed * 3.0;

  TilawatSettings copyWith({int? speed, bool? night, bool? translation, ReaderOrientation? orientation}) => TilawatSettings(
    speed: speed ?? this.speed,
    night: night ?? this.night,
    translation: translation ?? this.translation,
    orientation: orientation ?? this.orientation,
  );

  String encode() => '$speed,${night ? 1 : 0},${translation ? 1 : 0},${orientation.name}';

  static TilawatSettings decode(String? raw) {
    final p = (raw ?? '').split(',');
    if (p.length != 4) return const TilawatSettings();
    return TilawatSettings(
      speed: (int.tryParse(p[0]) ?? 5).clamp(1, 20),
      night: p[1] == '1',
      translation: p[2] == '1',
      orientation: ReaderOrientation.values.where((o) => o.name == p[3]).firstOrNull ?? ReaderOrientation.auto,
    );
  }
}

class TilawatController extends Notifier<TilawatSettings> {
  static const key = 'quran_tilawat';
  @override
  TilawatSettings build() {
    Future.microtask(() async {
      try {
        final raw = await ref.read(syncedStoreProvider).state(key);
        if (raw != null) state = TilawatSettings.decode(raw);
      } catch (_) {}
    });
    return const TilawatSettings();
  }

  void set(TilawatSettings v) {
    state = v;
    try {
      ref.read(syncedStoreProvider).setState(key, v.encode());
    } catch (_) {}
  }
}

final tilawatProvider = NotifierProvider<TilawatController, TilawatSettings>(TilawatController.new);

/// Reading the Quran on its own, full screen: page after page of the Madinah Mushaf as flowing text, scrolling by
/// itself at the pace you set. Tap to show or hide the controls; drag to move (it pauses while you hold).
class TilawatPage extends ConsumerStatefulWidget {
  const TilawatPage({super.key, required this.surah, this.ayah = 1});
  final int surah, ayah;
  @override
  ConsumerState<TilawatPage> createState() => _TilawatPageState();
}

class _TilawatPageState extends ConsumerState<TilawatPage> with SingleTickerProviderStateMixin {
  final _scroll = ScrollController();
  final _center = GlobalKey();
  final _pageKeys = <int, GlobalKey>{};
  late final Ticker _ticker = createTicker(_tick);
  Duration _last = Duration.zero;
  double _carry = 0; // sub-pixel progress, so slow speeds still move smoothly
  bool _playing = false, _controls = true, _holding = false;
  Timer? _hide, _where;
  int? _startPage;
  int _visiblePage = 1;
  (Offset, DateTime)? _down;

  // read while the page is alive: providers may not be read in dispose()
  late final ReaderSystem _sys;
  late final void Function(bool) _awake;
  late final OrientationLock _lock;
  late final RotationMode _appRotation;
  late final void Function((int, int)?) _setLastRead;
  QuranData? _quran;

  @override
  void initState() {
    super.initState();
    _sys = ref.read(readerSystemProvider);
    _awake = ref.read(screenAwakeProvider);
    _lock = ref.read(orientationLockProvider);
    _appRotation = ref.read(rotationProvider);
    _setLastRead = ref.read(quranLastReadProvider.notifier).set;
    _sys.setImmersive(true);
    _sys.setOrientation(ref.read(tilawatProvider).orientation);
    _awake(true);
    _where = Timer.periodic(const Duration(milliseconds: 700), (_) => _findVisiblePage());
  }

  @override
  void dispose() {
    _ticker.dispose();
    _hide?.cancel();
    _where?.cancel();
    _saveLastRead();
    _sys.setImmersive(false);
    _awake(false);
    unawaited(_lock.apply(_appRotation)); // back to the app's own rotation choice
    _scroll.dispose();
    super.dispose();
  }

  void _tick(Duration now) {
    final dt = (now - _last).inMicroseconds / 1e6;
    _last = now;
    if (!_playing || _holding || !_scroll.hasClients || dt <= 0 || dt > .25) return;
    final p = _scroll.position;
    _carry += ref.read(tilawatProvider).pixelsPerSecond * ref.read(quranTextScaleProvider) * dt;
    if (_carry < .5) return;
    final step = _carry.floorToDouble();
    _carry -= step;
    if (p.pixels >= p.maxScrollExtent) {
      _setPlaying(false); // the end of the Quran
      return;
    }
    _scroll.jumpTo((p.pixels + step).clamp(p.minScrollExtent, p.maxScrollExtent));
  }

  void _setPlaying(bool on) {
    setState(() => _playing = on);
    if (on) {
      _last = Duration.zero;
      if (!_ticker.isActive) _ticker.start();
      _hideSoon();
    } else {
      _ticker.stop();
      _hide?.cancel();
      setState(() => _controls = true);
    }
  }

  void _hideSoon() {
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 3), () {
      if (mounted && _playing) setState(() => _controls = false);
    });
  }

  void _toggleControls() {
    setState(() => _controls = !_controls);
    if (_controls && _playing) _hideSoon();
  }

  /// The Mushaf page at the top of the screen.
  void _findVisiblePage() {
    if (!mounted) return;
    int? best;
    for (final e in _pageKeys.entries) {
      final box = e.value.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      final top = box.localToGlobal(Offset.zero).dy, bottom = top + box.size.height;
      if (top <= 80 && bottom > 80) best = e.key;
    }
    if (best != null && best != _visiblePage) setState(() => _visiblePage = best!);
  }

  void _saveLastRead() {
    final q = _quran;
    if (q == null || _startPage == null) return;
    final (s, a) = q.refOf(q.firstOnPage(_visiblePage));
    // only when the reading moved on from where it began (or the start is not the first ayah on its page)
    if (_visiblePage != _startPage || widget.ayah > 1) {
      try {
        _setLastRead(_visiblePage == _startPage ? (widget.surah, widget.ayah) : (s, a));
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(quranDataProvider);
    final set = ref.watch(tilawatProvider);
    final scale = ref.watch(quranTextScaleProvider);
    final night = set.night;
    final bg = night ? const Color(0xFF0A1F18) : const Color(0xFFFBF5E4);
    final ink = night ? QuranColors.cream : const Color(0xFF14261F);
    final soft = night ? QuranColors.creamMuted : const Color(0xFF4A5E55);
    return Scaffold(
      key: const Key('tilawat-page'),
      backgroundColor: bg,
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not open the Quran: $e')),
        data: (q) {
          _quran = q;
          final start = _startPage ??= q.pageOf(q.indexOf(widget.surah, widget.ayah.clamp(1, q.surah(widget.surah).ayahCount)));
          if (_visiblePage == 1 && start != 1 && _pageKeys.isEmpty) _visiblePage = start;
          Widget page(int n) => _MushafPage(
            key: _pageKeys.putIfAbsent(n, GlobalKey.new),
            quran: q,
            page: n,
            scale: scale,
            ink: ink,
            soft: soft,
            translation: set.translation,
            urdu: ref.watch(translationModeProvider) != TranslationMode.english,
          );
          return Stack(
            children: [
              Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (e) {
                  _holding = true;
                  _down = (e.position, DateTime.now());
                },
                onPointerUp: (e) {
                  _holding = false;
                  final d = _down;
                  // a quick touch that did not move is a tap: show or hide the controls at once
                  if (d != null && (e.position - d.$1).distance < 14 && DateTime.now().difference(d.$2) < const Duration(milliseconds: 350)) {
                    _toggleControls();
                  }
                  _down = null;
                },
                onPointerCancel: (_) {
                  _holding = false;
                  _down = null;
                },
                child: SafeArea(
                  child: CustomScrollView(
                    key: const Key('tilawat-scroll'),
                    controller: _scroll,
                    center: _center,
                    slivers: [
                      // pages before the start, growing upwards
                      SliverList(delegate: SliverChildBuilderDelegate((_, i) => page(start - 1 - i), childCount: start - 1)),
                      SliverList(
                        key: _center,
                        delegate: SliverChildBuilderDelegate((_, i) => page(start + i), childCount: QuranData.pageCount - start + 1),
                      ),
                    ],
                  ),
                ),
              ),
              // top bar
              AnimatedPositioned(
                duration: const Duration(milliseconds: 220),
                top: _controls ? 0 : -120,
                left: 0,
                right: 0,
                child: _bar(
                  context,
                  top: true,
                  child: Row(
                    children: [
                      IconButton(
                        key: const Key('tilawat-close'),
                        color: QuranColors.goldLight,
                        tooltip: 'Close',
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Tilawat · تلاوت',
                              style: TextStyle(color: QuranColors.goldLight, fontWeight: FontWeight.w700),
                            ),
                            Text(
                              'Page $_visiblePage of ${QuranData.pageCount} · Juz ${q.juzOf(q.refOf(q.firstOnPage(_visiblePage)).$1, q.refOf(q.firstOnPage(_visiblePage)).$2)}',
                              key: const Key('tilawat-where'),
                              style: const TextStyle(color: QuranColors.creamMuted, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuButton<ReaderOrientation>(
                        key: const Key('tilawat-rotate'),
                        tooltip: 'Rotation',
                        iconColor: QuranColors.goldLight,
                        icon: Icon(switch (set.orientation) {
                          ReaderOrientation.auto => Icons.screen_rotation,
                          ReaderOrientation.portrait => Icons.stay_current_portrait,
                          ReaderOrientation.landscape => Icons.stay_current_landscape,
                        }),
                        initialValue: set.orientation,
                        onSelected: (o) {
                          ref.read(tilawatProvider.notifier).set(set.copyWith(orientation: o));
                          ref.read(readerSystemProvider).setOrientation(o);
                        },
                        itemBuilder: (_) => [
                          for (final (o, label) in [
                            (ReaderOrientation.auto, 'Turn with the phone'),
                            (ReaderOrientation.portrait, 'Stay upright'),
                            (ReaderOrientation.landscape, 'Stay sideways (landscape)'),
                          ])
                            CheckedPopupMenuItem(key: Key('tilawat-rotate-${o.name}'), value: o, checked: o == set.orientation, child: Text(label)),
                        ],
                      ),
                      IconButton(
                        key: const Key('tilawat-night'),
                        color: QuranColors.goldLight,
                        tooltip: night ? 'Light page' : 'Night page',
                        icon: Icon(night ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
                        onPressed: () => ref.read(tilawatProvider.notifier).set(set.copyWith(night: !night)),
                      ),
                      IconButton(
                        key: const Key('tilawat-translation'),
                        color: set.translation ? QuranColors.gold : QuranColors.goldLight,
                        tooltip: set.translation ? 'Arabic only' : 'Show the translation',
                        icon: const Icon(Icons.translate),
                        onPressed: () => ref.read(tilawatProvider.notifier).set(set.copyWith(translation: !set.translation)),
                      ),
                    ],
                  ),
                ),
              ),
              // bottom bar: play / pause and speed
              AnimatedPositioned(
                duration: const Duration(milliseconds: 220),
                bottom: _controls ? 0 : -160,
                left: 0,
                right: 0,
                child: _bar(
                  context,
                  top: false,
                  child: Row(
                    children: [
                      IconButton.filled(
                        key: const Key('tilawat-play'),
                        style: IconButton.styleFrom(backgroundColor: QuranColors.gold, foregroundColor: QuranColors.velvetDeep),
                        tooltip: _playing ? 'Pause' : 'Scroll by itself',
                        iconSize: 30,
                        icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                        onPressed: () => _setPlaying(!_playing),
                      ),
                      IconButton(
                        key: const Key('tilawat-slower'),
                        color: QuranColors.goldLight,
                        tooltip: 'Slower',
                        icon: const Icon(Icons.remove),
                        onPressed: set.speed > 1 ? () => ref.read(tilawatProvider.notifier).set(set.copyWith(speed: set.speed - 1)) : null,
                      ),
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: QuranColors.gold,
                            thumbColor: QuranColors.gold,
                            inactiveTrackColor: QuranColors.gold.withValues(alpha: .25),
                          ),
                          child: Slider(
                            key: const Key('tilawat-speed'),
                            min: 1,
                            max: 20,
                            divisions: 19,
                            value: set.speed.toDouble(),
                            label: 'Speed ${set.speed}',
                            onChanged: (v) => ref.read(tilawatProvider.notifier).set(set.copyWith(speed: v.round())),
                          ),
                        ),
                      ),
                      IconButton(
                        key: const Key('tilawat-faster'),
                        color: QuranColors.goldLight,
                        tooltip: 'Faster',
                        icon: const Icon(Icons.add),
                        onPressed: set.speed < 20 ? () => ref.read(tilawatProvider.notifier).set(set.copyWith(speed: set.speed + 1)) : null,
                      ),
                      SizedBox(
                        width: 64,
                        child: Text(
                          'Speed ${set.speed}',
                          key: const Key('tilawat-speed-label'),
                          style: const TextStyle(color: QuranColors.goldLight, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _bar(BuildContext context, {required bool top, required Widget child}) => Container(
    decoration: BoxDecoration(
      color: QuranColors.velvetDeep.withValues(alpha: .94),
      border: Border(
        top: top ? BorderSide.none : const BorderSide(color: QuranColors.gold, width: 1),
        bottom: top ? const BorderSide(color: QuranColors.gold, width: 1) : BorderSide.none,
      ),
    ),
    child: SafeArea(
      top: top,
      bottom: !top,
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4), child: child),
    ),
  );
}

/// One page of the Madinah Mushaf as flowing text (ayah markers inline), with surah headings where a surah starts.
class _MushafPage extends StatelessWidget {
  const _MushafPage({
    super.key,
    required this.quran,
    required this.page,
    required this.scale,
    required this.ink,
    required this.soft,
    required this.translation,
    required this.urdu,
  });
  final QuranData quran;
  final int page;
  final double scale;
  final Color ink, soft;
  final bool translation, urdu;

  @override
  Widget build(BuildContext context) {
    final q = quran;
    final from = q.firstOnPage(page);
    final to = page == QuranData.pageCount ? q.ayahCount - 1 : q.firstOnPage(page + 1) - 1;
    final blocks = <Widget>[];
    var run = <InlineSpan>[];
    void flush() {
      if (run.isEmpty) return;
      blocks.add(
        Text.rich(
          TextSpan(children: run),
          textDirection: TextDirection.rtl,
          textAlign: TextAlign.justify,
          style: quranArabic(25 * scale, color: ink).copyWith(height: 2.1),
        ),
      );
      run = <InlineSpan>[];
    }

    for (var i = from; i <= to; i++) {
      final (s, a) = q.refOf(i);
      if (a == 1) {
        flush();
        final su = q.surah(s);
        blocks.add(_SurahBanner(arabic: su.arabic, name: '${su.number}. ${su.name}', ink: ink, soft: soft));
        if (s != 1 && s != 9) {
          blocks.add(
            Text(
              q.bismillah,
              textAlign: TextAlign.center,
              textDirection: TextDirection.rtl,
              style: quranArabic(22 * scale, color: ink).copyWith(height: 2),
            ),
          );
        }
      }
      if (translation) {
        blocks.add(
          Text(
            '${q.arabic[i]} ${ayahEnd(a)}',
            textDirection: TextDirection.rtl,
            textAlign: TextAlign.right,
            style: quranArabic(25 * scale, color: ink).copyWith(height: 2.1),
          ),
        );
        blocks.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: urdu
                ? Text(
                    q.urdu[i],
                    textDirection: TextDirection.rtl,
                    style: urduText(15 * scale, color: soft).copyWith(height: 2.0),
                  )
                : Text(
                    q.english[i],
                    style: TextStyle(color: soft, fontSize: 15 * scale, height: 1.5),
                  ),
          ),
        );
      } else {
        run.add(TextSpan(text: '${q.arabic[i]} '));
        run.add(
          TextSpan(
            text: '${ayahEnd(a)} ',
            style: TextStyle(color: QuranColors.goldDeep.withValues(alpha: .95)),
          ),
        );
      }
    }
    flush();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...blocks,
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: Container(height: 1, color: QuranColors.gold.withValues(alpha: .35))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  arabicDigits(page),
                  key: Key('tilawat-page-$page'),
                  style: arabicText(14, color: QuranColors.goldDeep),
                ),
              ),
              Expanded(child: Container(height: 1, color: QuranColors.gold.withValues(alpha: .35))),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _SurahBanner extends StatelessWidget {
  const _SurahBanner({required this.arabic, required this.name, required this.ink, required this.soft});
  final String arabic, name;
  final Color ink, soft;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(vertical: 12),
    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
    decoration: BoxDecoration(
      border: Border.all(color: QuranColors.gold, width: 1.5),
      borderRadius: BorderRadius.circular(10),
      color: QuranColors.gold.withValues(alpha: .08),
    ),
    child: Column(
      children: [
        Text(
          arabic,
          textDirection: TextDirection.rtl,
          style: quranArabic(22, color: ink).copyWith(height: 1.5),
        ),
        Text(name, style: TextStyle(color: soft, fontSize: 12)),
      ],
    ),
  );
}
