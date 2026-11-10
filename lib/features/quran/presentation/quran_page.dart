import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../../app/router.dart';
import '../../../design_system/tokens.dart';
import '../application/quran_audio.dart';
import '../application/quran_providers.dart';
import '../data/quran_data.dart';
import '../domain/khatm.dart';
import 'cabinet_painters.dart';
import 'quran_style.dart';

/// Spellings of surah names vary ("Yaseen", "Yasin", "Ya-Sin"; "Al-Faatiha", "Fatiha"): letters only, doubled vowels
/// made single, ee/oo read as i/u, so any of them finds the surah.
String normalizeSurahName(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r"[^a-z]"), '')
    .replaceAll('ee', 'i')
    .replaceAll('oo', 'u')
    .replaceAll('aa', 'a')
    .replaceAll('ii', 'i')
    .replaceAll('uu', 'u');

/// The Quran's contents: Continue reading, then every surah (or the 30 juz), with a search box.
class QuranHomePage extends ConsumerStatefulWidget {
  const QuranHomePage({super.key});
  @override
  ConsumerState<QuranHomePage> createState() => _QuranHomePageState();
}

class _QuranHomePageState extends ConsumerState<QuranHomePage> {
  final _q = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  void _open(int surah, [int ayah = 1]) => context.push('${Routes.quran}/$surah?ayah=$ayah');

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(quranDataProvider);
    final c = context.colors;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: c.bg,
        appBar: AppBar(
          backgroundColor: QuranColors.velvet,
          foregroundColor: QuranColors.goldLight,
          toolbarHeight: 64,
          title: Row(
            children: [
              Flexible(
                flex: 2,
                child: Text(
                  'القرآن الكريم',
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.fade,
                  style: quranArabic(22, color: QuranColors.goldLight).copyWith(height: 1.4),
                ),
              ),
              const SizedBox(width: 10),
              const Flexible(
                child: Text('The Holy Quran', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: QuranColors.creamMuted)),
              ),
            ],
          ),
          actions: [
            IconButton(
              key: const Key('quran-settings'),
              tooltip: 'Translation, text size and reciter',
              icon: const Icon(Icons.tune),
              onPressed: () => showQuranSettings(context),
            ),
          ],
          bottom: const TabBar(
            indicatorColor: QuranColors.gold,
            labelColor: QuranColors.goldLight,
            unselectedLabelColor: QuranColors.creamMuted,
            tabs: [Tab(key: Key('quran-tab-surahs'), text: 'Surahs'), Tab(key: Key('quran-tab-juz'), text: 'Juz (Para)')],
          ),
        ),
        body: data.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Could not open the Quran: $e')),
          data: (q) {
            final last = ref.watch(quranLastReadProvider);
            final query = _query.trim().toLowerCase();
            final nq = normalizeSurahName(query);
            final surahs = q.surahs.where((s) {
              if (query.isEmpty) return true;
              return '${s.number}' == query ||
                  (nq.isNotEmpty && normalizeSurahName(s.name).contains(nq)) ||
                  s.english.toLowerCase().contains(query) ||
                  s.arabic.contains(_query.trim());
            }).toList();
            return TabBarView(
              children: [
                ListView(
                  key: const Key('surah-list'),
                  padding: const EdgeInsets.only(bottom: Space.s24),
                  children: [
                    _KhatmCard(quran: q, onOpen: _open),
                    if (last != null && q.valid(last.$1, last.$2)) _continueCard(q, last),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(Space.s16, Space.s12, Space.s16, Space.s4),
                      child: TextField(
                        key: const Key('surah-search'),
                        controller: _q,
                        onChanged: (v) => setState(() => _query = v),
                        decoration: InputDecoration(
                          isDense: true,
                          prefixIcon: const Icon(Icons.search),
                          hintText: 'Find a surah: name or number',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.input)),
                        ),
                      ),
                    ),
                    for (final s in surahs) _SurahTile(surah: s, onTap: () => _open(s.number)),
                    if (surahs.isEmpty)
                      const Padding(padding: EdgeInsets.all(Space.s24), child: Text('No surah matches.', textAlign: TextAlign.center)),
                  ],
                ),
                ListView.builder(
                  key: const Key('juz-list'),
                  itemCount: q.juzStarts.length,
                  itemBuilder: (_, i) {
                    final (s, a) = q.juzStarts[i];
                    return ListTile(
                      key: Key('juz-${i + 1}'),
                      leading: _NumberBadge(i + 1),
                      title: Text('Juz ${i + 1} (Para ${i + 1})'),
                      subtitle: Text('Starts at ${q.surah(s).name} $s:$a'),
                      trailing: Text(q.surah(s).arabic, style: quranArabic(16).copyWith(height: 1.3)),
                      onTap: () => _open(s, a),
                    );
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _continueCard(QuranData q, (int, int) last) {
    final s = q.surah(last.$1);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.s16, Space.s16, Space.s16, 0),
      child: Material(
        color: QuranColors.velvet,
        borderRadius: BorderRadius.circular(Radii.card),
        child: InkWell(
          key: const Key('quran-continue'),
          borderRadius: BorderRadius.circular(Radii.card),
          onTap: () => _open(last.$1, last.$2),
          child: Container(
            padding: const EdgeInsets.all(Space.s16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.card),
              border: Border.all(color: QuranColors.gold.withValues(alpha: .6)),
            ),
            child: Row(
              children: [
                const Icon(Icons.bookmark, color: QuranColors.gold),
                const SizedBox(width: Space.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Continue reading', style: TextStyle(color: QuranColors.creamMuted, fontSize: 12)),
                      Text('${s.name} ${last.$1}:${last.$2}', style: const TextStyle(color: QuranColors.goldLight, fontSize: 17, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                Text(s.arabic, style: quranArabic(18, color: QuranColors.goldLight).copyWith(height: 1.3)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NumberBadge extends StatelessWidget {
  const _NumberBadge(this.n);
  final int n;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 40,
    height: 40,
    child: CustomPaint(
      painter: const _StarBadgePainter(),
      child: Center(
        child: Text('$n', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: QuranColors.goldDeep)),
      ),
    ),
  );
}

class _StarBadgePainter extends CustomPainter {
  const _StarBadgePainter();
  @override
  void paint(Canvas canvas, Size s) {
    // one eight-pointed star (two squares), gold
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..shader = QuranColors.goldGradient.createShader(Offset.zero & s);
    final c = s.center(Offset.zero);
    final r = s.width * .44;
    for (final turn in [0.0, math.pi / 4]) {
      final path = Path();
      for (var i = 0; i < 4; i++) {
        final a = turn + i * math.pi / 2;
        final pt = c + Offset(math.cos(a), math.sin(a)) * r;
        i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
      }
      canvas.drawPath(path..close(), p);
    }
  }

  @override
  bool shouldRepaint(_StarBadgePainter old) => false;
}

class _SurahTile extends StatelessWidget {
  const _SurahTile({required this.surah, required this.onTap});
  final Surah surah;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListTile(
      key: Key('surah-${surah.number}'),
      onTap: onTap,
      leading: _NumberBadge(surah.number),
      title: Text('${surah.name} · ${surah.english}', maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('${surah.revelation} · ${surah.ayahCount} ayahs', style: t.bodySmall),
      trailing: Text(surah.arabic, style: quranArabic(18).copyWith(height: 1.3, color: context.colors.text)),
    );
  }
}

/// One surah: the Arabic with the chosen translation under each ayah, Listen, and where you stopped is remembered.
class SurahPage extends ConsumerStatefulWidget {
  const SurahPage({super.key, required this.surah, this.startAyah = 1});
  final int surah, startAyah;
  @override
  ConsumerState<SurahPage> createState() => _SurahPageState();
}

class _SurahPageState extends ConsumerState<SurahPage> {
  final _items = ItemScrollController();
  final _positions = ItemPositionsListener.create();
  Timer? _saveTimer;
  int? _followed;

  /// Hifz: ayahs shown again by tapping them while the Arabic is hidden.
  final _revealed = <int>{};

  Future<void> _hifzSheet(QuranData q, Surah s) async {
    final first = (_firstVisibleAyah() ?? 1).clamp(1, s.ayahCount);
    final r = await showModalBottomSheet<({int from, int to})>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _HifzSheet(surah: s, from: first, to: (first + 4).clamp(first, s.ayahCount)),
    );
    if (r == null || !mounted) return;
    final h = ref.read(hifzProvider);
    setState(_revealed.clear);
    await ref.read(quranAudioProvider.notifier).playFrom(
      q,
      s.number,
      r.from,
      to: r.to,
      repeat: RepeatPlan(eachAyah: h.eachAyah, rounds: h.rounds, pause: Duration(seconds: h.pauseSeconds)),
    );
  }

  @override
  void initState() {
    super.initState();
    _positions.itemPositions.addListener(_onScroll);
  }

  @override
  void dispose() {
    _positions.itemPositions.removeListener(_onScroll);
    _saveTimer?.cancel();
    super.dispose();
  }

  /// Remembers the first ayah on screen (a moment after scrolling stops).
  void _onScroll() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      final ayah = _firstVisibleAyah();
      if (ayah != null) ref.read(quranLastReadProvider.notifier).set((widget.surah, ayah));
    });
  }

  int? _firstVisibleAyah() {
    final visible = _positions.itemPositions.value.where((p) => p.itemTrailingEdge > 0.05 && p.index > 0).toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    return visible.isEmpty ? null : visible.first.index;
  }

  /// While reciting, keep the ayah being read on screen.
  void _follow(QuranAudioState a) {
    if (a.surah != widget.surah || a.ayah == null || a.ayah == _followed) return;
    _followed = a.ayah;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_items.isAttached) return;
      final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      reduce
          ? _items.jumpTo(index: a.ayah!, alignment: .15)
          : _items.scrollTo(index: a.ayah!, alignment: .15, duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);
    });
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(quranDataProvider);
    final mode = ref.watch(translationModeProvider);
    final scale = ref.watch(quranTextScaleProvider);
    final audio = ref.watch(quranAudioProvider);
    final hifz = ref.watch(hifzProvider);
    ref.listen(quranAudioProvider, (_, a) => _follow(a));
    final c = context.colors;
    return data.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Could not open the Quran: $e'))),
      data: (q) {
        final s = q.surah(widget.surah);
        final mine = audio.active && audio.surah == s.number;
        return Scaffold(
          backgroundColor: c.bg,
          appBar: AppBar(
            backgroundColor: QuranColors.velvet,
            foregroundColor: QuranColors.goldLight,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${s.number}. ${s.name}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                Text('${s.english} · ${s.revelation} · ${s.ayahCount} ayahs', style: const TextStyle(fontSize: 11.5, color: QuranColors.creamMuted)),
              ],
            ),
            actions: [
              IconButton(
                key: const Key('surah-listen'),
                tooltip: mine && audio.playing ? 'Pause' : 'Listen from here',
                icon: Icon(mine && audio.playing ? Icons.pause_circle : Icons.play_circle),
                onPressed: () {
                  final a = ref.read(quranAudioProvider.notifier);
                  if (mine) {
                    a.toggle();
                  } else {
                    a.playFrom(q, s.number, _firstVisibleAyah() ?? 1);
                  }
                },
              ),
              IconButton(
                key: const Key('hifz-open'),
                tooltip: 'Memorise (Hifz): repeat and hide',
                icon: Icon(hifz.hideArabic ? Icons.visibility_off : Icons.school_outlined),
                onPressed: () => _hifzSheet(q, s),
              ),
              PopupMenuButton<TranslationMode>(
                key: const Key('translation-menu'),
                tooltip: 'Translation',
                icon: const Icon(Icons.translate),
                initialValue: mode,
                onSelected: ref.read(translationModeProvider.notifier).set,
                itemBuilder: (_) => [
                  for (final m in TranslationMode.values)
                    CheckedPopupMenuItem(key: Key('translation-${m.name}'), value: m, checked: m == mode, child: Text(m.description)),
                ],
              ),
              IconButton(tooltip: 'Text size and reciter', icon: const Icon(Icons.tune), onPressed: () => showQuranSettings(context)),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: ScrollablePositionedList.builder(
                  key: const Key('ayah-list'),
                  itemScrollController: _items,
                  itemPositionsListener: _positions,
                  initialScrollIndex: widget.startAyah <= 1 ? 0 : widget.startAyah.clamp(1, s.ayahCount),
                  itemCount: s.ayahCount + 2,
                  padding: const EdgeInsets.only(bottom: Space.s24),
                  itemBuilder: (context, i) {
                    if (i == 0) return _SurahHeader(surah: s, bismillah: s.number == 1 || s.number == 9 ? null : q.bismillah);
                    if (i == s.ayahCount + 1) return _endOfSurah(q, s);
                    final idx = q.indexOf(s.number, i);
                    return _AyahTile(
                      key: Key('ayah-${s.number}-$i'),
                      surah: s,
                      ayah: i,
                      arabic: q.arabic[idx],
                      urdu: mode.showUrdu ? q.urdu[idx] : null,
                      english: mode.showEnglish ? q.english[idx] : null,
                      scale: scale,
                      sajda: q.sajdas.contains((s.number, i)),
                      reciting: mine && audio.ayah == i,
                      hidden: hifz.hideArabic && !_revealed.contains(i),
                      onReveal: () => setState(() => _revealed.add(i)),
                      onPlay: () => ref.read(quranAudioProvider.notifier).playFrom(q, s.number, i),
                      onMark: () {
                        ref.read(quranLastReadProvider.notifier).set((s.number, i));
                        final m = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
                        m.showSnackBar(
                          SnackBar(
                            content: Text('Saved ${s.number}:$i as your place. Home shows it under the Quran.'),
                            duration: const Duration(seconds: 2),
                            behavior: SnackBarBehavior.floating,
                            // above the audio bar when it is showing
                            margin: EdgeInsets.fromLTRB(Space.s16, 0, Space.s16, audio.active ? 84 : Space.s16),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              if (audio.active || audio.error != null) _AudioBar(quran: q),
            ],
          ),
        );
      },
    );
  }

  Widget _endOfSurah(QuranData q, Surah s) => Padding(
    padding: const EdgeInsets.all(Space.s24),
    child: Column(
      children: [
        Text('۞', style: quranArabic(28, color: QuranColors.goldDeep).copyWith(height: 1.2)),
        const SizedBox(height: Space.s12),
        if (s.number < 114)
          FilledButton.icon(
            key: const Key('next-surah'),
            onPressed: () => context.pushReplacement('${Routes.quran}/${s.number + 1}'),
            icon: const Icon(Icons.arrow_forward),
            label: Text('Next: ${q.surah(s.number + 1).name}'),
          ),
      ],
    ),
  );
}

class _SurahHeader extends StatelessWidget {
  const _SurahHeader({required this.surah, required this.bismillah});
  final Surah surah;
  final String? bismillah;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.s16, Space.s16, Space.s16, Space.s8),
    child: Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(gradient: QuranColors.goldGradient, borderRadius: BorderRadius.circular(14)),
      child: Container(
        decoration: BoxDecoration(color: QuranColors.velvet, borderRadius: BorderRadius.circular(11)),
        child: CustomPaint(
          painter: const StarLatticePainter(opacity: .09, cell: 28),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.s16, horizontal: Space.s12),
            child: Column(
              children: [
                Text(surah.arabic, textDirection: TextDirection.rtl, style: quranArabic(26, color: QuranColors.goldLight).copyWith(height: 1.5)),
                Text(
                  '${surah.name} · ${surah.english} · ${surah.revelation} · ${surah.ayahCount} ayahs',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: QuranColors.creamMuted, fontSize: 12),
                ),
                if (bismillah != null) ...[
                  const SizedBox(height: Space.s8),
                  Text(bismillah!, key: const Key('bismillah'), textDirection: TextDirection.rtl, style: quranArabic(22, color: QuranColors.cream)),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _AyahTile extends StatelessWidget {
  const _AyahTile({
    super.key,
    required this.surah,
    required this.ayah,
    required this.arabic,
    required this.urdu,
    required this.english,
    required this.scale,
    required this.sajda,
    required this.reciting,
    required this.onPlay,
    required this.onMark,
    this.hidden = false,
    this.onReveal,
  });
  final Surah surah;
  final int ayah;
  final String arabic;
  final String? urdu, english;
  final double scale;
  final bool sajda, reciting;
  final VoidCallback onPlay, onMark;

  /// Hifz: the Arabic is hidden (only its first word shows as a cue) until tapped.
  final bool hidden;
  final VoidCallback? onReveal;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      margin: const EdgeInsets.symmetric(horizontal: Space.s12, vertical: Space.s4),
      padding: const EdgeInsets.fromLTRB(Space.s12, Space.s8, Space.s12, Space.s12),
      decoration: BoxDecoration(
        color: reciting ? QuranColors.gold.withValues(alpha: .14) : c.surface,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: reciting ? QuranColors.gold : c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  border: Border.all(color: QuranColors.gold),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text('${surah.number}:$ayah', style: t.labelSmall?.copyWith(color: QuranColors.goldDeep, fontWeight: FontWeight.w700)),
              ),
              if (sajda) ...[
                const SizedBox(width: 6),
                Tooltip(
                  message: 'Sajdah (prostration of recitation)',
                  child: Text('۩ Sajdah', style: t.labelSmall?.copyWith(color: QuranColors.goldDeep)),
                ),
              ],
              if (reciting) ...[
                const SizedBox(width: 6),
                Icon(Icons.graphic_eq, size: 16, color: QuranColors.goldDeep),
              ],
              const Spacer(),
              IconButton(
                key: Key('play-${surah.number}-$ayah'),
                tooltip: 'Listen from this ayah',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.play_arrow_outlined),
                onPressed: onPlay,
              ),
              IconButton(
                key: Key('mark-${surah.number}-$ayah'),
                tooltip: 'Remember this place',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.bookmark_add_outlined),
                onPressed: onMark,
              ),
              IconButton(
                tooltip: 'Copy',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.copy, size: 18),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: [arabic, ?urdu, ?english, 'Quran ${surah.number}:$ayah'].join('\n\n')));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
                },
              ),
            ],
          ),
          if (hidden)
            Semantics(
              button: true,
              label: 'Show ayah $ayah',
              child: InkWell(
                key: Key('reveal-${surah.number}-$ayah'),
                onTap: onReveal,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(minHeight: 56),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: QuranColors.gold.withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: QuranColors.gold.withValues(alpha: .4)),
                  ),
                  child: Row(
                    textDirection: TextDirection.rtl,
                    children: [
                      Text('${arabic.split(' ').first} …', textDirection: TextDirection.rtl, style: quranArabic(24 * scale, color: c.text)),
                      const Spacer(),
                      Text('Tap to show', style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ),
            )
          else
            Text(
              '$arabic ${ayahEnd(ayah)}',
              key: Key('arabic-${surah.number}-$ayah'),
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.right,
              style: quranArabic(26 * scale, color: c.text),
            ),
          if (urdu != null) ...[
            const SizedBox(height: Space.s8),
            Text(
              urdu!,
              key: Key('urdu-${surah.number}-$ayah'),
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.right,
              style: urduText(15 * scale.clamp(.9, 1.4), color: c.text),
            ),
          ],
          if (english != null) ...[
            const SizedBox(height: Space.s8),
            Text(
              english!,
              key: Key('english-${surah.number}-$ayah'),
              style: t.bodyMedium?.copyWith(fontSize: 15 * scale.clamp(.9, 1.4), height: 1.5, color: c.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

/// While reciting: who is reciting, which ayah, Previous / Play-Pause / Next / Stop.
class _AudioBar extends ConsumerWidget {
  const _AudioBar({required this.quran});
  final QuranData quran;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = ref.watch(quranAudioProvider);
    final r = ref.watch(reciterProvider);
    final ctl = ref.read(quranAudioProvider.notifier);
    return Material(
      key: const Key('quran-audio-bar'),
      color: QuranColors.velvet,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.s16, Space.s8, Space.s8, Space.s8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      a.error ?? (a.translationTurn ? 'Translation of ${a.surah}:${a.ayah}' : '${quran.surah(a.surah ?? 1).name} ${a.surah}:${a.ayah}'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: QuranColors.goldLight, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      [
                        if (a.phase == PlayerPhase.loading) 'Loading…',
                        if (a.repeats > 1) 'repeat ${a.repeat}/${a.repeats}',
                        if (a.rounds > 1) 'round ${a.round}/${a.rounds}',
                        r.name,
                      ].join(' · '),
                      key: const Key('audio-subtitle'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: QuranColors.creamMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(color: QuranColors.goldLight, tooltip: 'Previous ayah', icon: const Icon(Icons.skip_previous), onPressed: ctl.previous),
              IconButton(
                key: const Key('audio-toggle'),
                color: QuranColors.goldLight,
                tooltip: a.playing ? 'Pause' : 'Play',
                icon: Icon(a.playing ? Icons.pause_circle_filled : Icons.play_circle_filled, size: 34),
                onPressed: ctl.toggle,
              ),
              IconButton(color: QuranColors.goldLight, tooltip: 'Next ayah', icon: const Icon(Icons.skip_next), onPressed: ctl.next),
              IconButton(key: const Key('audio-stop'), color: QuranColors.goldLight, tooltip: 'Stop', icon: const Icon(Icons.stop), onPressed: ctl.stop),
            ],
          ),
        ),
      ),
    );
  }
}

/// Translation, text size, reciter and spoken translation.
Future<void> showQuranSettings(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => const _QuranSettings(),
);

class _QuranSettings extends ConsumerWidget {
  const _QuranSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(translationModeProvider);
    final scale = ref.watch(quranTextScaleProvider);
    final reciter = ref.watch(reciterProvider);
    final spoken = ref.watch(spokenTranslationProvider);
    final t = Theme.of(context).textTheme;
    final q = ref.watch(quranDataProvider).value;
    void restart() {
      if (q != null) ref.read(quranAudioProvider.notifier).restart(q);
    }

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .8,
      maxChildSize: .95,
      builder: (context, scroll) => ListView(
        key: const Key('quran-settings-sheet'),
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(Space.s16, 0, Space.s16, Space.s32),
        children: [
          Text('Translation under each ayah', style: t.titleMedium),
          const SizedBox(height: Space.s8),
          Wrap(
            spacing: Space.s8,
            runSpacing: Space.s8,
            children: [
              for (final m in TranslationMode.values)
                ChoiceChip(
                  key: Key('mode-${m.name}'),
                  label: Text(m.description),
                  selected: m == mode,
                  onSelected: (_) => ref.read(translationModeProvider.notifier).set(m),
                ),
            ],
          ),
          const SizedBox(height: Space.s24),
          Text('Arabic text size', style: t.titleMedium),
          Slider(
            key: const Key('quran-text-size'),
            value: scale,
            min: .8,
            max: 1.8,
            divisions: 10,
            label: '${(scale * 100).round()}%',
            onChanged: ref.read(quranTextScaleProvider.notifier).set,
          ),
          Text(
            q?.bismillah ?? '',
            textDirection: TextDirection.rtl,
            textAlign: TextAlign.center,
            style: quranArabic(26 * scale, color: context.colors.text),
          ),
          const SizedBox(height: Space.s24),
          Text('Reciter', style: t.titleMedium),
          Text('Recitations are streamed, so listening needs the internet.', style: t.bodySmall),
          const SizedBox(height: Space.s8),
          for (final r in reciters)
            ListTile(
              key: Key('reciter-${r.id}'),
              contentPadding: EdgeInsets.zero,
              leading: Icon(r.id == reciter.id ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: r.id == reciter.id ? QuranColors.goldDeep : null),
              title: Text(r.name),
              trailing: Text(r.arabic, style: arabicText(15).copyWith(height: 1.2)),
              onTap: () {
                ref.read(reciterProvider.notifier).set(r);
                restart();
              },
            ),
          const SizedBox(height: Space.s16),
          Text('After each ayah', style: t.titleMedium),
          const SizedBox(height: Space.s8),
          Wrap(
            spacing: Space.s8,
            runSpacing: Space.s8,
            children: [
              for (final m in SpokenTranslation.values)
                ChoiceChip(
                  key: Key('spoken-${m.name}'),
                  label: Text(m.label),
                  selected: m == spoken,
                  onSelected: (_) {
                    ref.read(spokenTranslationProvider.notifier).set(m);
                    restart();
                  },
                ),
            ],
          ),
          const SizedBox(height: Space.s24),
          Text(
            'Texts: Arabic (Uthmani, Hafs) from the King Fahd Glorious Quran Printing Complex; English: Saheeh International; '
            'Urdu: Fateh Muhammad Jalandhry (via tanzil.net). Hadith: Sahih al-Bukhari. Audio: cdn.islamic.network. '
            'Everything except the audio is stored on your phone and works offline.',
            style: t.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// The khatm goal: today's portion, progress, and whether you are on track. Without a goal: a button to set one.
class _KhatmCard extends ConsumerWidget {
  const _KhatmCard({required this.quran, required this.onOpen});
  final QuranData quran;
  final void Function(int surah, [int ayah]) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(khatmProvider);
    final t = Theme.of(context).textTheme;
    final c = context.colors;
    if (plan == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(Space.s16, Space.s16, Space.s16, 0),
        child: OutlinedButton.icon(
          key: const Key('khatm-set'),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), foregroundColor: QuranColors.goldDeep, side: const BorderSide(color: QuranColors.gold)),
          onPressed: () => showKhatmSetup(context, ref, quran),
          icon: const Icon(Icons.flag_outlined),
          label: const Text('Set a khatm goal (finish the Quran in … days)'),
        ),
      );
    }
    final today = khatmToday(plan, DateTime.now());
    final from = quran.refOf(quran.firstOnPage(today.from));
    final (statusText, statusColor) = switch (today.status) {
      KhatmStatus.finished => ('Khatm complete. May Allah accept it.', QuranColors.goldDeep),
      KhatmStatus.doneToday => ("Today's portion is done", c.ok),
      KhatmStatus.onTrack => ('On track', c.ok),
      KhatmStatus.behind => ('${today.behindBy} ${today.behindBy == 1 ? 'page' : 'pages'} behind (included in today\'s portion)', c.warn),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.s16, Space.s16, Space.s16, 0),
      child: Card(
        key: const Key('khatm-card'),
        child: Padding(
          padding: const EdgeInsets.all(Space.s16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.flag, color: QuranColors.goldDeep),
                  const SizedBox(width: Space.s8),
                  Expanded(child: Text('Khatm · day ${today.day} of ${plan.days}', style: t.titleMedium)),
                  PopupMenuButton<String>(
                    key: const Key('khatm-menu'),
                    tooltip: 'Change or stop the goal',
                    onSelected: (v) => v == 'stop' ? ref.read(khatmProvider.notifier).stop() : showKhatmSetup(context, ref, quran),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'new', child: Text('Start a new goal')),
                      PopupMenuItem(key: Key('khatm-stop'), value: 'stop', child: Text('Stop the goal')),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: Space.s8),
              if (today.status != KhatmStatus.finished)
                Text(
                  today.status == KhatmStatus.doneToday
                      ? 'Tomorrow continues from page ${plan.donePage + 1}.'
                      : "Today: pages ${today.from}-${today.to} (from ${quran.surah(from.$1).name} ${from.$1}:${from.$2})",
                  key: const Key('khatm-today'),
                  style: t.bodyLarge,
                ),
              const SizedBox(height: Space.s4),
              Text(statusText, key: const Key('khatm-status'), style: t.bodyMedium?.copyWith(color: statusColor, fontWeight: FontWeight.w600)),
              const SizedBox(height: Space.s12),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(value: plan.progress, minHeight: 6, color: QuranColors.gold, backgroundColor: c.surface2),
              ),
              const SizedBox(height: Space.s4),
              Text('${(plan.donePage - plan.startPage + 1).clamp(0, plan.totalPages)} of ${plan.totalPages} pages · ${(plan.progress * 100).round()}%', style: t.bodySmall),
              if (today.status == KhatmStatus.onTrack || today.status == KhatmStatus.behind) ...[
                const SizedBox(height: Space.s12),
                FilledButton.icon(
                  key: const Key('khatm-read'),
                  style: FilledButton.styleFrom(backgroundColor: QuranColors.velvet, foregroundColor: QuranColors.goldLight),
                  onPressed: () => onOpen(from.$1, from.$2),
                  icon: const Icon(Icons.menu_book),
                  label: const Text("Read today's portion"),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Choose how many days, and whether to begin at Al-Fatiha or where you are now.
Future<void> showKhatmSetup(BuildContext context, WidgetRef ref, QuranData q) async {
  final last = ref.read(quranLastReadProvider);
  final here = last != null && q.valid(last.$1, last.$2) ? q.pageOf(q.indexOf(last.$1, last.$2)) : 1;
  var days = 30;
  var fromHere = false;
  final ok = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final t = Theme.of(ctx).textTheme;
        final from = fromHere ? here : 1;
        final perDay = ((QuranData.pageCount - from + 1) / days).ceil();
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.s16, 0, Space.s16, Space.s16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Finish the Quran in', style: t.titleMedium),
                const SizedBox(height: Space.s8),
                Wrap(
                  spacing: Space.s8,
                  runSpacing: Space.s8,
                  children: [
                    for (final d in const [7, 10, 15, 20, 30, 40, 60])
                      ChoiceChip(key: Key('khatm-days-$d'), label: Text('$d days'), selected: d == days, onSelected: (_) => setState(() => days = d)),
                  ],
                ),
                const SizedBox(height: Space.s16),
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: [
                    const ButtonSegment(value: false, label: Text('From Al-Fatiha')),
                    ButtonSegment(value: true, label: Text('From page $here (where you are)'), enabled: here > 1),
                  ],
                  selected: {fromHere},
                  onSelectionChanged: (v) => setState(() => fromHere = v.first),
                ),
                const SizedBox(height: Space.s16),
                Text('About $perDay ${perDay == 1 ? 'page' : 'pages'} a day (one juz is about 20 pages).', key: const Key('khatm-per-day'), style: t.bodyMedium),
                const SizedBox(height: Space.s16),
                FilledButton(key: const Key('khatm-start'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Start')),
              ],
            ),
          ),
        );
      },
    ),
  );
  if (ok == true) ref.read(khatmProvider.notifier).start(days: days, fromPage: fromHere ? here : 1);
}

/// Memorising: which ayahs, how many times, pauses, and hiding the Arabic.
class _HifzSheet extends ConsumerStatefulWidget {
  const _HifzSheet({required this.surah, required this.from, required this.to});
  final Surah surah;
  final int from, to;
  @override
  ConsumerState<_HifzSheet> createState() => _HifzSheetState();
}

class _HifzSheetState extends ConsumerState<_HifzSheet> {
  late int _from = widget.from, _to = widget.to;

  @override
  Widget build(BuildContext context) {
    final h = ref.watch(hifzProvider);
    final set = ref.read(hifzProvider.notifier).set;
    final t = Theme.of(context).textTheme;
    final n = widget.surah.ayahCount;
    Widget chips<T>(String keyPrefix, List<T> values, T current, String Function(T) label, void Function(T) pick) => Wrap(
      spacing: Space.s8,
      runSpacing: Space.s8,
      children: [for (final v in values) ChoiceChip(key: Key('$keyPrefix-$v'), label: Text(label(v)), selected: v == current, onSelected: (_) => pick(v))],
    );
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .85,
      maxChildSize: .95,
      builder: (context, scroll) => ListView(
        key: const Key('hifz-sheet'),
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(Space.s16, 0, Space.s16, Space.s24),
        children: [
          Text('Memorise (Hifz)', style: t.titleLarge),
          Text('${widget.surah.name}: choose the ayahs, how often to hear them, and hide the text to test yourself.', style: t.bodySmall),
          const SizedBox(height: Space.s16),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: const Key('hifz-from'),
                  initialValue: _from,
                  decoration: const InputDecoration(labelText: 'From ayah', border: OutlineInputBorder()),
                  items: [for (var i = 1; i <= n; i++) DropdownMenuItem(value: i, child: Text('$i'))],
                  onChanged: (v) => setState(() {
                    _from = v ?? _from;
                    if (_to < _from) _to = _from;
                  }),
                ),
              ),
              const SizedBox(width: Space.s12),
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: ValueKey('hifz-to-$_from'),
                  initialValue: _to,
                  decoration: const InputDecoration(labelText: 'To ayah', border: OutlineInputBorder()),
                  items: [for (var i = _from; i <= n; i++) DropdownMenuItem(value: i, child: Text('$i'))],
                  onChanged: (v) => setState(() => _to = v ?? _to),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.s16),
          Text('Repeat each ayah', style: t.titleSmall),
          const SizedBox(height: Space.s4),
          chips('hifz-each', const [1, 2, 3, 5, 7, 10], h.eachAyah, (v) => '$v×', (v) => set(ref.read(hifzProvider).copyWith(eachAyah: v))),
          const SizedBox(height: Space.s16),
          Text('Then repeat the whole selection', style: t.titleSmall),
          const SizedBox(height: Space.s4),
          chips('hifz-rounds', const [1, 2, 3, 5, 10], h.rounds, (v) => v == 1 ? 'Once' : '$v×', (v) => set(ref.read(hifzProvider).copyWith(rounds: v))),
          const SizedBox(height: Space.s16),
          Text('Pause after each repeat (time to say it back)', style: t.titleSmall),
          const SizedBox(height: Space.s4),
          chips('hifz-pause', const [0, 2, 5], h.pauseSeconds, (v) => v == 0 ? 'No pause' : '$v s', (v) => set(ref.read(hifzProvider).copyWith(pauseSeconds: v))),
          const SizedBox(height: Space.s8),
          SwitchListTile(
            key: const Key('hifz-hide'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Hide the Arabic'),
            subtitle: const Text('Only the first word of each ayah shows as a cue; tap an ayah to see it.'),
            value: h.hideArabic,
            onChanged: (v) => set(ref.read(hifzProvider).copyWith(hideArabic: v)),
          ),
          const SizedBox(height: Space.s8),
          Text(
            'You will hear ayahs $_from-$_to, each ${h.eachAyah}×${h.rounds > 1 ? ', the whole selection ${h.rounds}×' : ''}.',
            key: const Key('hifz-summary'),
            style: t.bodyMedium,
          ),
          const SizedBox(height: Space.s12),
          FilledButton.icon(
            key: const Key('hifz-start'),
            style: FilledButton.styleFrom(backgroundColor: QuranColors.velvet, foregroundColor: QuranColors.goldLight, minimumSize: const Size.fromHeight(48)),
            onPressed: () => Navigator.pop(context, (from: _from, to: _to)),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Start'),
          ),
        ],
      ),
    );
  }
}
