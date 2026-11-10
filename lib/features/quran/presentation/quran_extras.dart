import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../design_system/tokens.dart';
import '../../backup/backup_controller.dart' show backupTempDirProvider;
import '../../library/application/export_notes.dart' show shareFileProvider;
import '../application/quran_downloads.dart';
import '../application/quran_providers.dart';
import '../data/quran_data.dart';
import '../domain/quran_search.dart';
import 'cabinet_painters.dart';
import 'quran_style.dart';

/// Search the whole Quran: Arabic (any spelling, with or without vowel marks) and Urdu by typing in Arabic script,
/// English by typing in English.
class QuranSearchPage extends ConsumerStatefulWidget {
  const QuranSearchPage({super.key});
  @override
  ConsumerState<QuranSearchPage> createState() => _QuranSearchPageState();
}

class _QuranSearchPageState extends ConsumerState<QuranSearchPage> {
  final _q = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final index = ref.watch(quranSearchIndexProvider);
    final q = ref.watch(quranDataProvider).value;
    final t = Theme.of(context).textTheme;
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(backgroundColor: QuranColors.velvet, foregroundColor: QuranColors.goldLight, title: const Text('Search the Quran')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(Space.s16),
            child: TextField(
              key: const Key('quran-find-field'),
              controller: _q,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'A word in Arabic, Urdu or English: صبر · patience',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.input)),
              ),
            ),
          ),
          Expanded(
            child: index.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Search is not available: $e')),
              data: (ix) {
                if (q == null) return const SizedBox.shrink();
                final query = _query.trim();
                if (query.length < 2) {
                  return Padding(
                    padding: const EdgeInsets.all(Space.s24),
                    child: Text(
                      'Type at least two letters. Arabic finds the word in any spelling, with or without vowel marks; '
                      'Arabic script also searches the Urdu translation; English searches the English translation.',
                      textAlign: TextAlign.center,
                      style: t.bodyMedium?.copyWith(color: c.textMuted),
                    ),
                  );
                }
                final hits = ix.find(query);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Space.s16),
                      child: Text(
                        hits.isEmpty ? 'No ayah contains "$query".' : '${hits.length}${hits.length == 300 ? '+' : ''} ${hits.length == 1 ? 'ayah' : 'ayahs'}',
                        key: const Key('quran-find-count'),
                        style: t.bodySmall,
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        key: const Key('quran-find-results'),
                        padding: const EdgeInsets.all(Space.s12),
                        itemCount: hits.length,
                        separatorBuilder: (_, _) => const SizedBox(height: Space.s8),
                        itemBuilder: (_, i) {
                          final h = hits[i];
                          final (s, a) = q.refOf(h.index);
                          final english = h.field == SearchField.english;
                          return Material(
                            color: c.surface,
                            borderRadius: BorderRadius.circular(Radii.card),
                            child: InkWell(
                              key: Key('find-$s-$a'),
                              borderRadius: BorderRadius.circular(Radii.card),
                              onTap: () => context.push('${Routes.quran}/$s?ayah=$a'),
                              child: Padding(
                                padding: const EdgeInsets.all(Space.s12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Text('${q.surah(s).name} $s:$a', style: t.labelMedium?.copyWith(color: QuranColors.goldDeep, fontWeight: FontWeight.w700)),
                                    Text(q.arabic[h.index], textDirection: TextDirection.rtl, maxLines: 2, overflow: TextOverflow.ellipsis, style: quranArabic(19, color: c.text)),
                                    if (english)
                                      Text.rich(_highlight(q.english[h.index], foldEnglish(query), c.text), maxLines: 3, overflow: TextOverflow.ellipsis)
                                    else
                                      Text(q.urdu[h.index], textDirection: TextDirection.rtl, maxLines: 2, overflow: TextOverflow.ellipsis, style: urduText(14, color: c.textMuted)),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// The English with the first match of [q] (folded) in bold.
  static TextSpan _highlight(String text, String q, Color color) {
    final lower = text.toLowerCase();
    final at = lower.indexOf(q);
    final base = TextStyle(color: color, height: 1.4);
    if (at < 0) return TextSpan(text: text, style: base);
    return TextSpan(
      style: base,
      children: [
        TextSpan(text: text.substring(0, at)),
        TextSpan(text: text.substring(at, at + q.length), style: const TextStyle(fontWeight: FontWeight.w800, backgroundColor: Color(0x55D4AF37))),
        TextSpan(text: text.substring(at + q.length)),
      ],
    );
  }
}

/// Add, change or remove a bookmark (with a note) on an ayah.
Future<void> showBookmarkSheet(BuildContext context, WidgetRef ref, Surah s, int ayah) async {
  final existing = ref.read(quranBookmarksProvider.notifier).of(s.number, ayah);
  final r = await showModalBottomSheet<(bool save, String note)>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _BookmarkSheet(title: '${s.name} ${s.number}:$ayah', note: existing?.note ?? '', exists: existing != null),
  );
  if (r == null) return;
  final ctl = ref.read(quranBookmarksProvider.notifier);
  r.$1 ? ctl.save(s.number, ayah, r.$2) : ctl.remove(s.number, ayah);
}

class _BookmarkSheet extends StatefulWidget {
  const _BookmarkSheet({required this.title, required this.note, required this.exists});
  final String title, note;
  final bool exists;
  @override
  State<_BookmarkSheet> createState() => _BookmarkSheetState();
}

class _BookmarkSheetState extends State<_BookmarkSheet> {
  late final _c = TextEditingController(text: widget.note);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(Space.s16, 0, Space.s16, MediaQuery.viewInsetsOf(context).bottom + Space.s16),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Bookmark ${widget.title}', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: Space.s12),
        TextField(
          key: const Key('bookmark-note'),
          controller: _c,
          minLines: 2,
          maxLines: 6,
          decoration: const InputDecoration(labelText: 'Note (optional)', hintText: 'Why this ayah matters to you', border: OutlineInputBorder()),
        ),
        const SizedBox(height: Space.s12),
        Row(
          children: [
            if (widget.exists)
              TextButton.icon(
                key: const Key('bookmark-remove'),
                onPressed: () => Navigator.pop(context, (false, '')),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Remove bookmark'),
              ),
            const Spacer(),
            FilledButton(key: const Key('bookmark-save'), onPressed: () => Navigator.pop(context, (true, _c.text)), child: const Text('Save')),
          ],
        ),
      ],
    ),
  );
}

/// The Bookmarks tab: every bookmarked ayah with its note, newest first.
class QuranBookmarksList extends ConsumerWidget {
  const QuranBookmarksList({super.key, required this.quran});
  final QuranData quran;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(quranBookmarksProvider);
    final t = Theme.of(context).textTheme;
    if (list.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(Space.s24),
        child: Text('No bookmarks yet. In a surah, tap the bookmark button on an ayah to save it, with a note if you like.', textAlign: TextAlign.center, style: t.bodyMedium),
      );
    }
    return ListView.separated(
      key: const Key('bookmark-list'),
      padding: const EdgeInsets.all(Space.s12),
      itemCount: list.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final b = list[i];
        if (!quran.valid(b.surah, b.ayah)) return const SizedBox.shrink();
        final idx = quran.indexOf(b.surah, b.ayah);
        return ListTile(
          key: Key('bookmark-${b.surah}-${b.ayah}'),
          leading: const Icon(Icons.bookmark, color: QuranColors.goldDeep),
          title: Text('${quran.surah(b.surah).name} ${b.surah}:${b.ayah}'),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(quran.arabic[idx], textDirection: TextDirection.rtl, maxLines: 1, overflow: TextOverflow.ellipsis, style: quranArabic(16).copyWith(height: 1.6)),
              if (b.note.isNotEmpty) Text(b.note, maxLines: 3, overflow: TextOverflow.ellipsis),
            ],
          ),
          onTap: () => context.push('${Routes.quran}/${b.surah}?ayah=${b.ayah}'),
        );
      },
    );
  }
}

/// Preview an ayah as a picture (gold and green card) and share it, or copy the text.
Future<void> showShareAyahSheet(BuildContext context, WidgetRef ref, QuranData q, int surah, int ayah) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _ShareSheet(quran: q, surah: surah, ayah: ayah),
);

class _ShareSheet extends ConsumerStatefulWidget {
  const _ShareSheet({required this.quran, required this.surah, required this.ayah});
  final QuranData quran;
  final int surah, ayah;
  @override
  ConsumerState<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends ConsumerState<_ShareSheet> {
  final _card = GlobalKey();
  late TranslationMode _mode = ref.read(translationModeProvider) == TranslationMode.none ? TranslationMode.urdu : ref.read(translationModeProvider);
  bool _busy = false;

  String get _text {
    final q = widget.quran, i = q.indexOf(widget.surah, widget.ayah);
    return [
      q.arabic[i],
      if (_mode.showUrdu) q.urdu[i],
      if (_mode.showEnglish) q.english[i],
      'Quran ${widget.surah}:${widget.ayah} (${q.surah(widget.surah).name})',
    ].join('\n\n');
  }

  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      final boundary = _card.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final dir = await ref.read(backupTempDirProvider)();
      final f = File('${dir.path}/quran-${widget.surah}-${widget.ayah}.png');
      await f.writeAsBytes(png!.buffer.asUint8List(), flush: true);
      await ref.read(shareFileProvider)(f, 'Quran ${widget.surah}:${widget.ayah}');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not make the picture: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.quran, i = q.indexOf(widget.surah, widget.ayah);
    final s = q.surah(widget.surah);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Space.s16, 0, Space.s16, Space.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RepaintBoundary(
              key: _card,
              child: Container(
                key: const Key('share-card'),
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(gradient: QuranColors.goldGradient, borderRadius: BorderRadius.circular(18)),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [QuranColors.velvet, QuranColors.velvetDeep]),
                  ),
                  child: CustomPaint(
                    painter: const StarLatticePainter(opacity: .08, cell: 30),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                      child: Column(
                        children: [
                          Text(s.arabic, textDirection: TextDirection.rtl, style: quranArabic(16, color: QuranColors.gold).copyWith(height: 1.4)),
                          const SizedBox(height: 8),
                          Text('${q.arabic[i]} ${ayahEnd(widget.ayah)}', textDirection: TextDirection.rtl, textAlign: TextAlign.center, style: quranArabic(24, color: QuranColors.goldLight)),
                          if (_mode.showUrdu) ...[
                            const SizedBox(height: 10),
                            Text(q.urdu[i], textDirection: TextDirection.rtl, textAlign: TextAlign.center, style: urduText(15, color: QuranColors.cream)),
                          ],
                          if (_mode.showEnglish) ...[
                            const SizedBox(height: 10),
                            Text(q.english[i], textAlign: TextAlign.center, style: const TextStyle(color: QuranColors.cream, fontSize: 14.5, height: 1.45)),
                          ],
                          const SizedBox(height: 12),
                          Container(height: 1, width: 80, color: QuranColors.gold.withValues(alpha: .6)),
                          const SizedBox(height: 8),
                          Text('${s.name} · ${widget.surah}:${widget.ayah}', style: const TextStyle(color: QuranColors.gold, fontSize: 12.5, fontWeight: FontWeight.w600, letterSpacing: .3)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: Space.s12),
            Wrap(
              spacing: Space.s8,
              runSpacing: Space.s8,
              children: [
                for (final m in TranslationMode.values)
                  ChoiceChip(key: Key('share-mode-${m.name}'), label: Text(m.description), selected: m == _mode, onSelected: (_) => setState(() => _mode = m)),
              ],
            ),
            const SizedBox(height: Space.s12),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: Space.s8,
              runSpacing: Space.s8,
              children: [
                OutlinedButton.icon(
                  key: const Key('share-copy'),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: _text));
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
                  },
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Copy text'),
                ),
                FilledButton.icon(
                  key: const Key('share-picture'),
                  onPressed: _busy ? null : _share,
                  icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.share),
                  label: const Text('Share picture'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Listening without internet: download this surah or the whole Quran for the chosen reciter; stop; delete.
Future<void> showDownloadSheet(BuildContext context, QuranData q, Surah s) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _DownloadSheet(quran: q, surah: s),
);

class _DownloadSheet extends ConsumerStatefulWidget {
  const _DownloadSheet({required this.quran, required this.surah});
  final QuranData quran;
  final Surah surah;
  @override
  ConsumerState<_DownloadSheet> createState() => _DownloadSheetState();
}

class _DownloadSheetState extends ConsumerState<_DownloadSheet> {
  int? _surahHere, _allHere, _bytes;

  @override
  void initState() {
    super.initState();
    _count();
  }

  Future<void> _count() async {
    final d = ref.read(quranDownloadsProvider.notifier);
    final r = ref.read(reciterProvider);
    final s = widget.surah;
    try {
      final a = await d.countHere(r, s.firstIndex, s.firstIndex + s.ayahCount - 1);
      final b = await d.countHere(r, 0, widget.quran.ayahCount - 1);
      final c = await d.bytesHere(r);
      if (mounted) {
        setState(() {
          _surahHere = a;
          _allHere = b;
          _bytes = c;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _surahHere = 0;
          _allHere = 0;
          _bytes = 0;
        });
      }
    }
  }

  /// Starts a download of [ayahs] ayahs; on mobile data with Wi-Fi only on, asks first (showing the size).
  Future<void> _start(int ayahs, void Function(bool mobileOk) go) async {
    if (!ref.read(wifiOnlyProvider) || !await ref.read(onMobileDataProvider)()) {
      go(false);
      return;
    }
    if (!mounted) return;
    final r = ref.read(reciterProvider);
    final mb = (wholeQuranBytes(r) * ayahs / widget.quran.ayahCount / 1e6).round();
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('You are on mobile data'),
        content: Text('This download is about ${mb >= 1000 ? '${(mb / 1000).toStringAsFixed(1)} GB' : '$mb MB'}. Use mobile data for it, or wait until you are on Wi-Fi?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Wait for Wi-Fi')),
          FilledButton(key: const Key('download-mobile-ok'), onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Use mobile data')),
        ],
      ),
    );
    if (yes == true) go(true);
  }

  @override
  Widget build(BuildContext context) {
    final r = ref.watch(reciterProvider);
    final job = ref.watch(quranDownloadsProvider);
    ref.listen(quranDownloadsProvider, (prev, next) {
      if (next != null && !next.running) _count();
    });
    final t = Theme.of(context).textTheme;
    final s = widget.surah;
    final ctl = ref.read(quranDownloadsProvider.notifier);
    final running = job != null && job.running && job.reciterId == r.id;
    String mb(int b) => b >= 1e9 ? '${(b / 1e9).toStringAsFixed(2)} GB' : '${(b / 1e6).toStringAsFixed(1)} MB';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.s16, 0, Space.s16, Space.s16),
        child: Column(
          key: const Key('download-sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Listen without internet', style: t.titleLarge),
            Text('Recitation by ${r.name}.', style: t.bodySmall),
            SwitchListTile(
              key: const Key('download-wifi-only'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Download on Wi-Fi only'),
              subtitle: const Text('On mobile data Folio asks first, and pauses if Wi-Fi is lost'),
              value: ref.watch(wifiOnlyProvider),
              onChanged: ref.read(wifiOnlyProvider.notifier).set,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(_surahHere == s.ayahCount ? Icons.download_done : Icons.download, color: QuranColors.goldDeep),
              title: Text('${s.name} (${s.ayahCount} ayahs)'),
              subtitle: Text(_surahHere == null ? 'Checking…' : (_surahHere == s.ayahCount ? 'On this phone' : '$_surahHere of ${s.ayahCount} on this phone'), key: const Key('download-surah-state')),
              trailing: FilledButton(
                key: const Key('download-surah'),
                onPressed: running || _surahHere == s.ayahCount
                    ? null
                    : () => _start(s.ayahCount, (ok) => ctl.downloadSurah(widget.quran, r, s.number, mobileOk: ok)),
                child: const Text('Download'),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(_allHere == widget.quran.ayahCount ? Icons.download_done : Icons.cloud_download_outlined, color: QuranColors.goldDeep),
              title: Text('The whole Quran (${wholeQuranSize(r)})'),
              subtitle: Text(_allHere == null ? 'Checking…' : '$_allHere of ${widget.quran.ayahCount} ayahs on this phone'),
              trailing: OutlinedButton(
                key: const Key('download-all'),
                onPressed: running || _allHere == widget.quran.ayahCount
                    ? null
                    : () => _start(widget.quran.ayahCount, (ok) => ctl.downloadAll(widget.quran, r, mobileOk: ok)),
                child: const Text('Download'),
              ),
            ),
            if (job != null && job.reciterId == r.id) ...[
              const SizedBox(height: Space.s8),
              Text(
                job.running ? 'Downloading ${job.label}: ${job.done} of ${job.total}' : (job.error ?? 'Downloaded ${job.label}: ${job.done} of ${job.total}'),
                key: const Key('download-progress'),
                style: t.bodyMedium?.copyWith(color: job.error != null ? context.colors.danger : null),
              ),
              const SizedBox(height: Space.s4),
              LinearProgressIndicator(value: job.fraction, color: QuranColors.gold),
              if (running)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(key: const Key('download-stop'), onPressed: ctl.cancel, child: const Text('Stop (what is downloaded stays)')),
                ),
            ],
            const SizedBox(height: Space.s8),
            if ((_bytes ?? 0) > 0)
              TextButton.icon(
                key: const Key('download-delete'),
                onPressed: () async {
                  await ctl.deleteAll(r);
                  await _count();
                },
                icon: const Icon(Icons.delete_outline),
                label: Text('Delete ${r.name}\'s downloads (${mb(_bytes!)})'),
              ),
            Text('Listening uses the downloaded files by itself; anything not downloaded is streamed.', style: t.bodySmall),
          ],
        ),
      ),
    );
  }
}
