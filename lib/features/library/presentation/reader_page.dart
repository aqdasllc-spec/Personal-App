import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/components.dart';
import '../../../data/local/app_database.dart';
import '../application/export_notes.dart';
import '../application/library_controller.dart';
import '../application/export_ink.dart';
import '../application/ocr_controller.dart';
import '../application/read_aloud.dart';
import '../data/media_controls.dart';
import '../data/speech.dart' show SpeechEngine, VoiceInfo;
import '../domain_lookup.dart';
import '../domain_speech.dart';
import '../domain_ink.dart';
import '../domain_ocr.dart';
import '../application/reader_prefs.dart';
import '../../settings/rotation.dart';
import 'reader_settings_sheet.dart';
import '../domain_highlights.dart';

/// Full-screen PDF reader. Remembers the page you were on.
class ReaderPage extends ConsumerStatefulWidget {
  const ReaderPage({super.key, required this.bookId, this.startPage, this.searchQuery});
  final String bookId;

  /// Open at this page instead of where you stopped (a search hit, for example).
  final int? startPage;

  /// Start with this text searched (from the "search in all books" screen).
  final String? searchQuery;
  @override
  ConsumerState<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends ConsumerState<ReaderPage> {
  Timer? _debounce;
  int? _page;
  late final _repo = ref.read(libraryRepositoryProvider);
  final _control = ReaderControl();
  final _searchCtl = TextEditingController();
  Timer? _searchDebounce;
  bool _searching = false;
  bool _immersive = false;
  late final ProviderContainer _container;
  late final _system = ref.read(readerSystemProvider);
  late final _awake = ref.read(screenAwakeProvider);
  late final _ocr = OcrRunner(
    _repo,
    ref.read(pageRecognizerProvider),
    ref.read(textProbeProvider),
  );
  late final MediaControls _media; // read in initState: dispose cannot read providers
  late final ReadAloud _aloud = ReadAloud(
    engine: ref.read(speechEngineProvider),
    textOf: _textOfPage,
    goTo: (p) => _control.goTo?.call(p),
    pageCount: () => _pageCount,
    voice: () => _container.read(voiceChoiceProvider.future),
    autoVoice: () => _container.read(voiceAutoProvider.future),
  );
  int _pageCount = 0;
  BookRow? _book;
  Timer? _dwell; // a page counts as read after a few seconds on it
  Timer? _clock; // reading time, counted while the app is in front
  bool _dwellStarted = false;
  static const _dwellTime = Duration(seconds: 4);
  static const _tick = Duration(seconds: 15);
  String _textState = 'unknown';
  bool _probed = false;
  List<OcrMatch> _hits = const [];
  int _hitIndex = -1;
  String _hitQuery = '';

  @override
  void initState() {
    super.initState();
    _container = ProviderScope.containerOf(context, listen: false);
    _control.prefs.value = ref.read(readerPrefsProvider);
    _control.onZoneTap = _onZone;
    _media = ref.read(mediaControlsProvider);
    _clock = Timer.periodic(_tick, (_) {
      final s = WidgetsBinding.instance.lifecycleState;
      if (s == null || s == AppLifecycleState.resumed) _repo.addReadingSeconds(_tick.inSeconds);
    });
    _page = widget.startPage;
    final q = widget.searchQuery?.trim();
    if (q != null && q.isNotEmpty) {
      _searching = true;
      _searchCtl.text = q;
      // the viewer is not up yet: start the search a moment after the first frames
      _searchDebounce = Timer(const Duration(milliseconds: 600), () => _startSearch(q));
    }
    _control.onLookUp = _lookUp;
    _control.onStroke = _onStroke;
    _control.onErase = _onErase;
    _ocr.progress.addListener(() {
      if (mounted) setState(() {});
    });
    _aloud.state.addListener(() {
      if (mounted) setState(() {});
      _syncLockScreen();
    });
    _applySystem(_control.prefs.value);
    Future.microtask(() => _repo.markOpened(widget.bookId));
    _control.onHighlight = (d) async {
      await _repo.addHighlight(widget.bookId, d);
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text(
                'Highlighted. Open the list at the top to add a note.',
              ),
              duration: Duration(seconds: 2),
            ),
          );
      }
    };
  }

  /// Orientation lock and screen-on follow the reading settings.
  void _applySystem(ReaderPrefs p) {
    _system.setOrientation(p.orientation);
    _awake(p.keepAwake);
  }

  void _setImmersive(bool on) {
    setState(() => _immersive = on);
    _system.setImmersive(on);
  }

  void _onZone(TapZone zone) {
    final prefs = _control.prefs.value;
    if (zone == TapZone.center || !prefs.tapTurn) {
      if (zone == TapZone.center) _setImmersive(!_immersive);
      return;
    }
    final total =
        ref
            .read(booksProvider)
            .value
            ?.where((b) => b.id == widget.bookId)
            .firstOrNull
            ?.pageCount ??
        0;
    final cur = _page ?? 1;
    final target = zone == TapZone.right ? cur + 1 : cur - 1;
    if (target < 1 || (total > 0 && target > total)) return;
    _control.goTo?.call(target);
  }

  /// Every change to a page's drawings, newest last: the page and its strokes before the change (for Undo).
  final _inkHistory = <(int, List<Stroke>)>[];

  Future<void> _setInk(int page, List<Stroke> list) async {
    final before = _control.ink.value[page] ?? const <Stroke>[];
    _inkHistory.add((page, before));
    if (_inkHistory.length > 100) _inkHistory.removeAt(0);
    _control.ink.value = {..._control.ink.value, page: list};
    await _repo.saveInk(widget.bookId, page, list);
  }

  Future<void> _onStroke(int page, Stroke s) =>
      _setInk(page, [...(_control.ink.value[page] ?? const <Stroke>[]), s]);

  Future<void> _onErase(int page, double x, double y) async {
    final cur = _control.ink.value[page] ?? const <Stroke>[];
    final left = eraseAt(cur, x, y);
    if (left.length != cur.length) await _setInk(page, left);
  }

  Future<void> _undoStroke() async {
    if (_inkHistory.isEmpty) return;
    final (page, before) = _inkHistory.removeLast();
    _control.ink.value = {..._control.ink.value, page: before};
    await _repo.saveInk(widget.bookId, page, before);
  }

  Future<void> _clearInkPage(int page) async {
    if ((_control.ink.value[page] ?? const <Stroke>[]).isEmpty) return;
    await _setInk(page, const []);
  }

  void _setPen(PenState p) {
    final starting = p.on && !_control.pen.value.on;
    _control.pen.value = p;
    setState(() {});
    if (starting) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Draw with one finger. Pinch with two fingers to zoom.'),
            duration: Duration(seconds: 3),
          ),
        );
    }
  }

  /// Colours, thickness, Undo and Clear page, shown while the pen is on.
  Widget _penBar(int page) {
    final pen = _control.pen.value;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      key: const Key('pen-bar'),
      color: scheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: SizedBox(
          // one slim row: the page needs the room
          height: 52,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                // colour + thickness live in a small pop-up so they take no room while you draw
                PopupMenuButton<void>(
                  key: const Key('pen-style'),
                  tooltip: 'Pen colour and thickness',
                  position: PopupMenuPosition.over,
                  itemBuilder: (menuContext) => [
                    PopupMenuItem<void>(
                      enabled: false,
                      padding: const EdgeInsets.all(8),
                      child: _penStyleMenu(menuContext),
                    ),
                  ],
                  child: SizedBox(
                    width: 52,
                    height: 52,
                    child: Center(
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: Color(penColors[pen.color].$2),
                          shape: BoxShape.circle,
                          border: Border.all(color: scheme.onSurface, width: 2),
                        ),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  key: const Key('pen-eraser'),
                  tooltip: pen.erase ? 'Back to the pen' : 'Eraser: touch a stroke to remove it',
                  isSelected: pen.erase,
                  icon: const Icon(Icons.cleaning_services_outlined),
                  selectedIcon: const Icon(Icons.cleaning_services),
                  onPressed: () => _setPen(pen.copyWith(erase: !pen.erase)),
                ),
                IconButton(
                  key: const Key('pen-undo'),
                  tooltip: 'Undo last stroke',
                  icon: const Icon(Icons.undo),
                  onPressed: _undoStroke,
                ),
                IconButton(
                  key: const Key('pen-clear'),
                  tooltip: 'Clear drawings on this page',
                  icon: const Icon(Icons.delete_sweep_outlined),
                  onPressed: () => _clearInkPage(page),
                ),
                const Spacer(),
                FilledButton.tonal(
                  key: const Key('pen-done'),
                  onPressed: () => _setPen(pen.copyWith(on: false)),
                  child: const Text('Done'),
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The pop-up with the six colours and three thicknesses.
  Widget _penStyleMenu(BuildContext menuContext) {
    final pen = _control.pen.value;
    final scheme = Theme.of(context).colorScheme;
    void pick(PenState next) {
      _setPen(next.copyWith(erase: false));
      Navigator.pop(menuContext);
    }

    void stylusOnly(bool v) {
      ref.read(stylusOnlyProvider.notifier).set(v);
      _setPen(_control.pen.value.copyWith(stylusOnly: v));
      Navigator.pop(menuContext);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              key: const Key('pen-tool-pen'),
              label: const Text('Pen'),
              selected: !pen.highlighter,
              onSelected: (_) => pick(pen.copyWith(highlighter: false)),
            ),
            ChoiceChip(
              key: const Key('pen-tool-highlighter'),
              label: const Text('Highlighter'),
              selected: pen.highlighter,
              onSelected: (_) => pick(pen.copyWith(highlighter: true)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        FilterChip(
          key: const Key('pen-stylus-only'),
          label: const Text('Stylus only'),
          tooltip: 'Only a stylus draws; fingers scroll and zoom',
          selected: pen.stylusOnly,
          onSelected: stylusOnly,
        ),
        const SizedBox(height: 4),
        Wrap(
          children: [
            for (var i = 0; i < penColors.length; i++)
              Semantics(
                button: true,
                selected: pen.color == i,
                label: '${penColors[i].$1} pen',
                child: InkResponse(
                  key: Key('pen-color-$i'),
                  onTap: () => pick(pen.copyWith(color: i)),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Color(penColors[i].$2),
                        shape: BoxShape.circle,
                        border: pen.color == i ? Border.all(color: scheme.primary, width: 3) : null,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < penWidths.length; i++)
              Semantics(
                button: true,
                selected: pen.width == i,
                label: '${penWidths[i].$1} line',
                child: InkResponse(
                  key: Key('pen-width-$i'),
                  onTap: () => pick(pen.copyWith(width: i)),
                  child: Container(
                    width: 64,
                    height: 44,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: pen.width == i ? scheme.primaryContainer : null,
                    ),
                    child: Container(
                      width: 36,
                      height: 2.0 + i * 3,
                      decoration: BoxDecoration(
                        color: scheme.onSurface,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// What the voice reads on [page]: the text we recognised on a scan, otherwise the PDF's own text.
  Future<String?> _textOfPage(int page) async {
    final book = _book;
    if (book == null) return null;
    if (_useOcr) {
      final row = await _repo.pageText(book.id, page);
      if (row != null && row.body.trim().isNotEmpty) return row.body;
    }
    return ref.read(pageTextReaderProvider).textOf(_repo.fileOf(book), page);
  }

  /// Keeps the lock-screen / notification controls in step with what is being read.
  void _syncLockScreen() {
    final s = _aloud.state.value;
    final book = _book;
    if (!s.active || book == null) {
      _media.hide();
      return;
    }
    _media.show(
      title: book.title,
      subtitle: s.message ?? 'Page ${s.page} of ${book.pageCount}',
      playing: s.playing,
      onPlay: _aloud.resume,
      onPause: _aloud.pause,
      onStop: _aloud.stop,
      onNext: () => _aloud.start((s.page + 1).clamp(1, book.pageCount)),
      onPrevious: () => _aloud.start((s.page - 1).clamp(1, book.pageCount)),
    );
  }

  /// "Export as PDF with my drawings": choose what to include, build it, share it.
  Future<void> _exportInk(BookRow book, int current, Map<int, List<Stroke>> ink) async {
    final drawn = drawnPages(ink);
    final here = (ink[current] ?? const <Stroke>[]).isNotEmpty;
    final whole = book.pageCount <= maxWholeBookExportPages;
    final scope = await showDialog<InkExportScope>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Export as PDF with my drawings'),
        children: [
          if (here)
            SimpleDialogOption(
              key: const Key('export-ink-this'),
              onPressed: () => Navigator.pop(ctx, InkExportScope.thisPage),
              child: Text('This page ($current)'),
            ),
          SimpleDialogOption(
            key: const Key('export-ink-drawn'),
            onPressed: drawn.isEmpty ? null : () => Navigator.pop(ctx, InkExportScope.drawnPages),
            child: Text('Pages with drawings (${drawn.length})'),
          ),
          SimpleDialogOption(
            key: const Key('export-ink-all'),
            onPressed: whole ? () => Navigator.pop(ctx, InkExportScope.wholeBook) : null,
            child: Text(
              whole
                  ? 'The whole book (${book.pageCount} pages)'
                  : 'The whole book (only for books up to $maxWholeBookExportPages pages)',
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 8, 24, 8),
            child: Text(
              'Pages become pictures in the new PDF, so their text can no longer be selected there. Your original PDF is not changed.',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
    if (scope == null || !mounted) return;
    final progress = ValueNotifier<(int, int)>((0, 1));
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: ValueListenableBuilder<(int, int)>(
            valueListenable: progress,
            builder: (_, v, _) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Drawing page ${v.$1} of ${v.$2}…', key: const Key('export-ink-progress')),
                const SizedBox(height: 12),
                LinearProgressIndicator(value: v.$2 == 0 ? null : v.$1 / v.$2),
              ],
            ),
          ),
        ),
      ),
    );
    String message;
    try {
      message = await exportBookWithInk(
        ref,
        book,
        scope: scope,
        currentPage: current,
        onProgress: (d, t) => progress.value = (d, t),
      );
    } catch (_) {
      message = 'Could not make the PDF. Please try again.';
    }
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // the progress dialog
    progress.dispose();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _toggleListen(int current) {
    final s = _aloud.state.value;
    if (!s.active) {
      _aloud.start(current);
    } else {
      _aloud.stop();
    }
  }

  /// Selected text -> a small sheet to look it up (dictionary / translate, both open the browser) or copy it.
  Future<void> _lookUp(String raw) async {
    final text = cleanLookUp(raw);
    if (text.isEmpty || !mounted) return;
    final open = ref.read(urlOpenerProvider);
    final lang = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Look up', style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(ctx).colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SelectableText(text, key: const Key('lookup-text'), maxLines: 6),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    key: const Key('lookup-define'),
                    icon: const Icon(Icons.menu_book_outlined),
                    label: const Text('Meaning'),
                    onPressed: () {
                      Navigator.pop(ctx);
                      open(dictionaryUri(text));
                    },
                  ),
                  FilledButton.tonalIcon(
                    key: const Key('lookup-translate'),
                    icon: const Icon(Icons.translate),
                    label: const Text('Translate'),
                    onPressed: () {
                      Navigator.pop(ctx);
                      open(translateUri(text, lang));
                    },
                  ),
                  TextButton.icon(
                    key: const Key('lookup-copy'),
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Copy'),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: text));
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Meaning and Translate open your browser; the selected text is sent to that website.',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Pick a language and a voice from what the phone has installed.
  Future<void> _chooseVoice() async {
    final engine = ref.read(speechEngineProvider);
    final voices = await engine.voices();
    if (!mounted) return;
    final current = await _container.read(voiceChoiceProvider.future);
    final auto = await _container.read(voiceAutoProvider.future);
    if (!mounted) return;
    final picked = await showModalBottomSheet<({VoiceInfo? voice, bool auto})>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _VoiceSheet(voices: voices, current: current, engine: engine, auto: auto),
    );
    if (picked == null) return;
    await _container.read(voiceAutoProvider.notifier).set(picked.auto);
    if (picked.auto) {
      // back to automatic: pick again from the book's language the next time reading starts
      await _aloud.stop();
      return;
    }
    await _container.read(voiceChoiceProvider.notifier).set(picked.voice);
    await _aloud.changeVoice(picked.voice);
  }

  /// Play / pause, speed and close, shown while the voice bar is open.
  Widget _listenBar() {
    final s = _aloud.state.value;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      key: const Key('listen-bar'),
      color: scheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            IconButton(
              key: const Key('listen-play'),
              tooltip: s.playing ? 'Pause reading' : 'Read aloud',
              icon: Icon(s.playing ? Icons.pause_circle : Icons.play_circle, size: 36),
              onPressed: s.playing ? _aloud.pause : _aloud.resume,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                s.message ?? (s.playing ? 'Reading page ${s.page}' : 'Paused on page ${s.page}'),
                key: const Key('listen-status'),
              ),
            ),
            PopupMenuButton<double>(
              key: const Key('listen-speed'),
              tooltip: 'Reading speed',
              initialValue: s.rate,
              onSelected: _aloud.setRate,
              itemBuilder: (_) => [
                for (final r in speechRates)
                  PopupMenuItem(value: r, child: Text(rateLabel(r))),
              ],
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(rateLabel(s.rate), style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
            IconButton(
              key: const Key('listen-voice'),
              tooltip: 'Choose a voice',
              icon: const Icon(Icons.record_voice_over_outlined),
              onPressed: _chooseVoice,
            ),
            IconButton(
              key: const Key('listen-close'),
              tooltip: 'Stop reading aloud',
              icon: const Icon(Icons.close),
              onPressed: _aloud.stop,
            ),
          ],
        ),
      ),
    );
  }

  /// "Pages": a grid of page pictures to jump to a page.
  Future<void> _showPages(BookRow book, int current, Set<int> marked, Set<int> drawn) async {
    final file = _repo.fileOf(book);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SizedBox(
        height: MediaQuery.sizeOf(ctx).height * 0.75,
        child: Column(
          children: [
            Text('Pages (${book.pageCount})', style: Theme.of(ctx).textTheme.titleMedium),
            Expanded(
              child: ref.read(pageThumbsBuilderProvider)(
                ctx,
                file: file,
                pageCount: book.pageCount,
                current: current,
                bookmarked: marked,
                drawn: drawn,
                onPick: (p) {
                  Navigator.pop(ctx);
                  _control.goTo?.call(p);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The row of tools under the page: contents, bookmark, pen, voice.
  Widget _toolRow(BookRow book, int current, List<BookmarkRow> marks, List<HighlightRow> highlights, bool marked) {
    final pen = _control.pen.value.on;
    final aloud = _aloud.state.value.active;
    return Material(
      key: const Key('reader-tools'),
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            _tool(
              const Key('reader-bookmarks'),
              'Contents',
              'Bookmarks and highlights',
              Badge(
                isLabelVisible: marks.isNotEmpty || highlights.isNotEmpty,
                label: Text('${marks.length + highlights.length}'),
                child: const Icon(Icons.list_alt),
              ),
              false,
              () => showModalBottomSheet<void>(
                context: context,
                showDragHandle: true,
                isScrollControlled: true,
                builder: (_) => _MarksSheet(
                  book: book,
                  bookId: book.id,
                  current: current,
                  onJump: (p) => _control.goTo?.call(p),
                ),
              ),
            ),
            _tool(
              const Key('reader-pages'),
              'Pages',
              'Page pictures: jump to a page',
              const Icon(Icons.grid_view_outlined),
              false,
              () => _showPages(book, current, {for (final m in marks) m.page}, {
                for (final e in _control.ink.value.entries)
                  if (e.value.isNotEmpty) e.key,
              }),
            ),
            _tool(
              const Key('reader-bookmark'),
              marked ? 'Marked' : 'Bookmark',
              marked ? 'Remove bookmark from this page' : 'Bookmark this page',
              Icon(marked ? Icons.bookmark : Icons.bookmark_border),
              marked,
              () => _repo.toggleBookmark(book.id, current),
            ),
            _tool(
              const Key('reader-pen'),
              'Draw',
              pen ? 'Stop drawing' : 'Draw with a pen',
              const Icon(Icons.edit_outlined),
              pen,
              () => _setPen(_control.pen.value.copyWith(on: !pen)),
            ),
            _tool(
              const Key('reader-listen'),
              'Listen',
              aloud ? 'Stop reading aloud' : 'Read aloud',
              const Icon(Icons.headphones_outlined),
              aloud,
              () => _toggleListen(current),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tool(Key key, String label, String tip, Widget icon, bool on, VoidCallback onTap) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Tooltip(
        message: tip,
        child: InkWell(
          key: key,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: MediaQuery.sizeOf(context).height < 480 ? 48 : 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconTheme(
                    data: IconThemeData(color: on ? scheme.primary : scheme.onSurfaceVariant),
                    child: icon,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: on ? scheme.primary : scheme.onSurfaceVariant,
                      fontWeight: on ? FontWeight.w700 : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _scheduleDwell(int page) {
    _dwell?.cancel();
    _dwell = Timer(_dwellTime, () {
      final s = WidgetsBinding.instance.lifecycleState;
      if (s == null || s == AppLifecycleState.resumed) _repo.markPageRead(widget.bookId, page);
    });
  }

  void _onPage(int page) {
    setState(() => _page = page);
    _scheduleDwell(page);
    _aloud.pageChanged(page);
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 600),
      () => _repo.saveProgress(widget.bookId, page),
    );
  }

  @override
  void dispose() {
    // Save the final position immediately (the debounce may not have fired).
    _debounce?.cancel();
    _searchDebounce?.cancel();
    _searchCtl.dispose();
    _dwell?.cancel();
    _clock?.cancel();
    _ocr.dispose();
    _aloud.dispose();
    _media.hide();
    final p = _page;
    if (p != null) _repo.saveProgress(widget.bookId, p);
    // give the phone back to the app's own settings
    _awake(false);
    _system.setImmersive(false);
    _container
        .read(orientationLockProvider)
        .apply(_container.read(rotationProvider));
    super.dispose();
  }

  static bool _sameInk(Map<int, List<Stroke>> a, Map<int, List<Stroke>> b) {
    final ka = a.keys.where((k) => a[k]!.isNotEmpty).toSet();
    final kb = b.keys.where((k) => b[k]!.isNotEmpty).toSet();
    if (ka.length != kb.length || !ka.containsAll(kb)) return false;
    return ka.every((k) => a[k]!.length == b[k]!.length);
  }

  void _openSearch() => setState(() => _searching = true);

  /// Scanned books are searched in the text we read off the pages; others in the PDF's own text.
  bool get _useOcr => _textState == 'scanned' || _textState == 'ocr';

  Future<void> _startSearch(String q) async {
    if (!_useOcr) {
      _control.startSearch?.call(q);
      return;
    }
    final query = q.trim();
    _hitQuery = query;
    if (query.isEmpty) {
      _clearOcrSearch();
      return;
    }
    final pages = await _repo.pageTexts(widget.bookId);
    if (!mounted || _hitQuery != query) return;
    _hits = searchPages(pages, query);
    _hitIndex = _hits.isEmpty ? -1 : 0;
    _publishOcr();
    if (_hits.isNotEmpty) _control.goTo?.call(_hits[0].page);
  }

  void _publishOcr() {
    _control.search.value = ReaderSearch(
      query: _hitQuery,
      count: _hits.length,
      index: _hitIndex < 0 ? null : _hitIndex,
    );
    final h = _hitIndex < 0 ? null : _hits[_hitIndex];
    _control.ocrBoxes.value = [
      if (h != null)
        OcrHit(h.page, h.line.left, h.line.top, h.line.right, h.line.bottom),
    ];
  }

  void _clearOcrSearch() {
    _hits = const [];
    _hitIndex = -1;
    _hitQuery = '';
    _control.ocrBoxes.value = const [];
    _control.search.value = const ReaderSearch();
  }

  void _step(int d) {
    if (!_useOcr) {
      d > 0 ? _control.nextMatch?.call() : _control.prevMatch?.call();
      return;
    }
    if (_hits.isEmpty) return;
    _hitIndex = (_hitIndex + d) % _hits.length;
    if (_hitIndex < 0) _hitIndex += _hits.length;
    _publishOcr();
    _control.goTo?.call(_hits[_hitIndex].page);
  }

  void _closeSearch() {
    _searchDebounce?.cancel();
    _searchCtl.clear();
    _control.stopSearch?.call();
    _clearOcrSearch();
    setState(() => _searching = false);
  }

  void _onQuery(String q) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(
      const Duration(milliseconds: 400),
      () => _startSearch(q),
    );
  }

  Widget _searchTitle() => TextField(
    key: const Key('reader-search-field'),
    controller: _searchCtl,
    autofocus: true,
    textInputAction: TextInputAction.search,
    decoration: const InputDecoration(
      hintText: 'Search in this PDF',
      border: InputBorder.none,
    ),
    onChanged: _onQuery,
    onSubmitted: (q) {
      // Enter: search now, or go to the next match when the search is already up to date
      _searchDebounce?.cancel();
      if (_control.search.value.query == q.trim() &&
          _control.search.value.count > 0) {
        _step(1);
      } else {
        _startSearch(q);
      }
    },
  );

  List<Widget> _searchActions() => [
    ValueListenableBuilder<ReaderSearch>(
      valueListenable: _control.search,
      builder: (context, s, _) {
        final String label;
        if (s.query.isEmpty) {
          label = '';
        } else if (s.count == 0) {
          label = s.searching ? 'Searching…' : 'No matches';
        } else {
          label =
              '${(s.index ?? -1) + 1} / ${s.count}${s.searching ? '+' : ''}';
        }
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (label.isNotEmpty)
              Text(label, key: const Key('reader-search-count')),
            IconButton(
              key: const Key('reader-search-prev'),
              tooltip: 'Previous match',
              icon: const Icon(Icons.keyboard_arrow_up),
              onPressed: s.count == 0 ? null : () => _step(-1),
            ),
            IconButton(
              key: const Key('reader-search-next'),
              tooltip: 'Next match',
              icon: const Icon(Icons.keyboard_arrow_down),
              onPressed: s.count == 0 ? null : () => _step(1),
            ),
          ],
        );
      },
    ),
    IconButton(
      key: const Key('reader-search-close'),
      tooltip: 'Close search',
      icon: const Icon(Icons.close),
      onPressed: _closeSearch,
    ),
  ];

  double? _scrub;

  /// Drag to jump through the book (like an e-reader's progress bar).
  Widget _pageBar(int current, int total) {
    final shown = (_scrub ?? current.toDouble()).clamp(1.0, total.toDouble());
    return Material(
      key: const Key('reader-pagebar'),
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 52,
          child: Row(
            children: [
              const SizedBox(width: 16),
              Text('${shown.round()}', key: const Key('reader-scrub-label')),
              Expanded(
                child: Slider(
                  key: const Key('reader-slider'),
                  min: 1,
                  max: total.toDouble(),
                  divisions: total - 1,
                  value: shown,
                  label: '${shown.round()}',
                  semanticFormatterCallback: (v) =>
                      'Page ${v.round()} of $total',
                  onChanged: (v) => setState(() => _scrub = v),
                  onChangeEnd: (v) {
                    setState(() => _scrub = null);
                    _control.goTo?.call(v.round());
                  },
                ),
              ),
              Text('$total'),
              const SizedBox(width: 16),
            ],
          ),
        ),
      ),
    );
  }

  void _startOcr(BookRow book) {
    _ocr.run(book.id, _repo.fileOf(book), book.pageCount);
  }

  /// Offer to make a scan searchable, or show how far the reading has got.
  Widget? _ocrBanner(BookRow book) {
    if (_textState != 'scanned' && !_ocr.progress.value.running) return null;
    final pr = _ocr.progress.value;
    final scheme = Theme.of(context).colorScheme;
    final Widget content;
    if (pr.running) {
      content = Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Reading page ${pr.done} of ${pr.total}…',
                  key: const Key('ocr-progress'),
                ),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: pr.total == 0 ? null : pr.done / pr.total,
                ),
              ],
            ),
          ),
          TextButton(
            key: const Key('ocr-stop'),
            onPressed: _ocr.stop,
            child: const Text('Stop'),
          ),
        ],
      );
    } else if (!_ocr.supported) {
      content = const Text(
        'This looks like a scan. Making it searchable works on phones and tablets.',
      );
    } else {
      content = Row(
        children: [
          const Expanded(
            child: Text(
              'This looks like a scan, so search can\'t see its text yet.',
            ),
          ),
          FilledButton(
            key: const Key('ocr-start'),
            onPressed: () => _startOcr(book),
            child: const Text('Make searchable'),
          ),
        ],
      );
    }
    return Material(
      key: const Key('ocr-banner'),
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: content,
      ),
    );
  }

  Future<void> _showPageText(BookRow book, int page) async {
    final row = await _repo.pageText(book.id, page);
    if (!mounted) return;
    final text = row?.body.trim() ?? '';
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Text of page $page',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(
                  child: SelectableText(
                    text.isEmpty
                        ? 'No text was found on this page. Handwriting and very faint scans are often not recognised.'
                        : text,
                    key: const Key('page-text'),
                  ),
                ),
              ),
              if (text.isNotEmpty)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    key: const Key('page-text-copy'),
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Copy'),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: text));
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// The page with the chosen colour scheme, dimming and warm tint on top.
  Widget _pageArea(BuildContext context, Widget view) {
    final p = ref.watch(readerPrefsProvider);
    return Stack(
      fit: StackFit.expand,
      children: [
        ColorFiltered(
          key: const Key('reader-filter'),
          colorFilter:
              p.theme.filter ??
              const ColorFilter.mode(Colors.transparent, BlendMode.dst),
          child: view,
        ),
        if (p.warmth > 0)
          IgnorePointer(
            child: ColoredBox(
              key: const Key('reader-warm-overlay'),
              color: const Color(0xFFFFA33A).withValues(alpha: p.warmth * 0.30),
            ),
          ),
        if (p.dim > 0)
          IgnorePointer(
            child: ColoredBox(
              key: const Key('reader-dim-overlay'),
              color: Colors.black.withValues(alpha: p.dim),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // reading settings changed: tell the PDF view and the phone
    ref.listen<bool>(stylusOnlyProvider, (prev, next) {
      if (_control.pen.value.stylusOnly != next) _control.pen.value = _control.pen.value.copyWith(stylusOnly: next);
    });
    ref.listen<ReaderPrefs>(readerPrefsProvider, (prev, next) {
      _control.prefs.value = next;
      _applySystem(next);
    });
    final repo = ref.watch(libraryRepositoryProvider);
    final book = ref
        .watch(booksProvider)
        .value
        ?.where((b) => b.id == widget.bookId)
        .firstOrNull;
    if (book == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(
          icon: Icons.menu_book_outlined,
          title: 'Book not found',
          message: 'It may have been removed from your library.',
        ),
      );
    }
    final file = repo.fileOf(book);
    _book = book;
    _pageCount = book.pageCount;
    if (!_dwellStarted) {
      _dwellStarted = true;
      _scheduleDwell(_page ?? (book.lastPage < 1 ? 1 : book.lastPage));
    }
    _textState = book.textState;
    if (!_probed && _textState == 'unknown' && file.existsSync()) {
      _probed = true;
      _ocr.probeBook(book.id, book.textState, file);
    }
    final current = _page ?? (book.lastPage < 1 ? 1 : book.lastPage);
    final marks =
        ref.watch(bookmarksProvider(book.id)).value ?? const <BookmarkRow>[];
    final marked = marks.any((m) => m.page == current);
    final highlights =
        ref.watch(highlightsProvider(book.id)).value ?? const <HighlightRow>[];
    // hand the saved highlights to the PDF view (it repaints itself when they change)
    if (!listEquals(_control.highlights.value, highlights)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _control.highlights.value = highlights;
      });
    }
    final inkRows = ref.watch(inkProvider(book.id)).value ?? const <PageInkRow>[];
    final inkMap = {for (final r in inkRows) r.page: decodeStrokes(r.strokes)};
    if (!_sameInk(_control.ink.value, inkMap)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _control.ink.value = inkMap;
      });
    }
    return Scaffold(
      appBar: _immersive
          ? null
          : AppBar(
              title: _searching
                  ? _searchTitle()
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          book.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (book.pageCount > 0)
                          Text(
                            '$current / ${book.pageCount}',
                            key: const Key('reader-page'),
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                      ],
                    ),
              actions: _searching
                  ? _searchActions()
                  : [
                      IconButton(
                        key: const Key('reader-search'),
                        tooltip: 'Search in this PDF',
                        icon: const Icon(Icons.search),
                        onPressed: _openSearch,
                      ),
                      IconButton(
                        key: const Key('reader-settings'),
                        tooltip: 'Reading settings',
                        icon: const Icon(Icons.text_fields),
                        onPressed: () => showModalBottomSheet<void>(
                          context: context,
                          showDragHandle: true,
                          isScrollControlled: true,
                          builder: (_) => const ReaderSettingsSheet(),
                        ),
                      ),
                      PopupMenuButton<String>(
                        key: const Key('reader-more'),
                        tooltip: 'More',
                        onSelected: (v) {
                          if (v == 'ocr') _startOcr(book);
                          if (v == 'redo') {
                            _repo.clearPageTexts(book.id).then((_) {
                              if (mounted) _startOcr(book);
                            });
                          }
                          if (v == 'text') _showPageText(book, current);
                          if (v == 'exportink') _exportInk(book, current, inkMap);
                        },
                        itemBuilder: (_) => [
                          if (_ocr.supported && _textState != 'ocr')
                            const PopupMenuItem(
                              value: 'ocr',
                              child: Text(
                                'Make searchable (scans, handwriting)',
                              ),
                            ),
                          if (_ocr.supported && _textState == 'ocr')
                            const PopupMenuItem(
                              value: 'redo',
                              child: Text('Read the pages again'),
                            ),
                          if (inkMap.values.any((l) => l.isNotEmpty))
                            const PopupMenuItem(
                              key: Key('reader-export-ink'),
                              value: 'exportink',
                              child: Text('Export as PDF with my drawings'),
                            ),
                          if (_useOcr)
                            const PopupMenuItem(
                              value: 'text',
                              child: Text('Text of this page'),
                            ),
                        ],
                      ),
                    ],
            ),
      bottomNavigationBar: _immersive
          ? null
          // the bars keep a readable size even when the phone's text is huge: the page needs the room
          : MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.3,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_aloud.state.value.active) _listenBar(),
                  if (_control.pen.value.on)
                    // while drawing, the slider and tool row give way to one slim pen bar
                    _penBar(current)
                  else ...[
                    // a short (landscape) screen drops the slider: the page matters more; edges and swipes still turn pages
                    if (book.pageCount >= 2 &&
                        MediaQuery.sizeOf(context).height >= 480)
                      _pageBar(current, book.pageCount),
                    _toolRow(book, current, marks, highlights, marked),
                  ],
                ],
              ),
            ),
      body: file.existsSync()
          ? Column(
              children: [
                ?_ocrBanner(book),
                Expanded(
                  child: _pageArea(
                    context,
                    ref.read(pdfViewBuilderProvider)(
                      context,
                      file,
                      widget.startPage ?? book.lastPage,
                      _onPage,
                      _control,
                    ),
                  ),
                ),
              ],
            )
          : const EmptyState(
              icon: Icons.broken_image_outlined,
              title: 'The file is missing',
              message: 'Folio can\'t find this book\'s PDF on this device. Remove it and add the PDF again.',
            ),
    );
  }
}

/// Bookmarks and highlights of the open book, in two tabs.
class _MarksSheet extends ConsumerWidget {
  const _MarksSheet({
    required this.book,
    required this.bookId,
    required this.current,
    required this.onJump,
  });
  final BookRow book;
  final String bookId;
  final int current;
  final void Function(int page) onJump;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(libraryRepositoryProvider);
    final marks =
        ref.watch(bookmarksProvider(bookId)).value ?? const <BookmarkRow>[];
    final highlights =
        ref.watch(highlightsProvider(bookId)).value ?? const <HighlightRow>[];
    final height = MediaQuery.sizeOf(context).height * 0.6;
    return SafeArea(
      child: SizedBox(
        height: height,
        child: DefaultTabController(
          length: 2,
          child: Column(
            children: [
              TabBar(
                tabs: [
                  Tab(
                    key: const Key('tab-bookmarks'),
                    text: 'Bookmarks (${marks.length})',
                  ),
                  Tab(
                    key: const Key('tab-highlights'),
                    text: 'Highlights (${highlights.length})',
                  ),
                ],
              ),
              if (marks.isNotEmpty || highlights.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Export your notes',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      TextButton.icon(
                        key: const Key('export-copy'),
                        icon: const Icon(Icons.copy, size: 18),
                        label: const Text('Copy'),
                        onPressed: () async {
                          final m = await exportBookNotes(
                            ref,
                            book,
                            copy: true,
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context)
                                .showSnackBar(SnackBar(content: Text(m)));
                          }
                        },
                      ),
                      TextButton.icon(
                        key: const Key('export-share'),
                        icon: const Icon(Icons.ios_share, size: 18),
                        label: const Text('Share'),
                        onPressed: () async {
                          final m = await exportBookNotes(
                            ref,
                            book,
                            copy: false,
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context)
                                .showSnackBar(SnackBar(content: Text(m)));
                          }
                        },
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: TabBarView(
                  children: [
                    marks.isEmpty
                        ? const _Empty(
                            'No bookmarks yet. Tap the bookmark icon at the top to mark the page you are on.',
                          )
                        : ListView(
                            children: [
                              for (final m in marks)
                                ListTile(
                                  key: Key('bookmark-${m.page}'),
                                  leading: Icon(
                                    Icons.bookmark,
                                    color: m.page == current
                                        ? Theme.of(context).colorScheme.primary
                                        : null,
                                  ),
                                  title: Text('Page ${m.page}'),
                                  subtitle: m.label.isEmpty
                                      ? null
                                      : Text(m.label),
                                  onTap: () {
                                    Navigator.pop(context);
                                    onJump(m.page);
                                  },
                                  trailing: IconButton(
                                    key: Key('bookmark-delete-${m.page}'),
                                    tooltip: 'Remove bookmark',
                                    icon: const Icon(Icons.delete_outline),
                                    onPressed: () => repo.removeBookmark(m.id),
                                  ),
                                ),
                            ],
                          ),
                    highlights.isEmpty
                        ? const _Empty(
                            'No highlights yet. Select some text in the PDF and choose Highlight.',
                          )
                        : ListView(
                            children: [
                              for (final h in highlights)
                                ListTile(
                                  key: Key('highlight-${h.id}'),
                                  leading: InkWell(
                                    key: Key('hl-color-${h.id}'),
                                    customBorder: const CircleBorder(),
                                    onTap: () => repo.setHighlightColor(
                                      h.id,
                                      nextHighlightColor(h.color),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: CircleAvatar(
                                        radius: 10,
                                        backgroundColor: highlightColor(
                                          h.color,
                                        ),
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    h.snippet.isEmpty ? '(no text)' : h.snippet,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    'Page ${h.page}${h.note.isEmpty ? '' : '\n${h.note}'}',
                                  ),
                                  isThreeLine: h.note.isNotEmpty,
                                  onTap: () {
                                    Navigator.pop(context);
                                    onJump(h.page);
                                  },
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        key: Key('hl-note-${h.id}'),
                                        tooltip: h.note.isEmpty
                                            ? 'Add a note'
                                            : 'Edit note',
                                        icon: Icon(
                                          h.note.isEmpty
                                              ? Icons.note_add_outlined
                                              : Icons.edit_note,
                                        ),
                                        onPressed: () async {
                                          final n = await showDialog<String>(
                                            context: context,
                                            builder: (_) =>
                                                _NoteDialog(initial: h.note),
                                          );
                                          if (n != null) {
                                            await repo.setHighlightNote(
                                              h.id,
                                              n,
                                            );
                                          }
                                        },
                                      ),
                                      IconButton(
                                        key: Key('hl-delete-${h.id}'),
                                        tooltip: 'Remove highlight',
                                        icon: const Icon(Icons.delete_outline),
                                        onPressed: () =>
                                            repo.removeHighlight(h.id),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
    child: Text(text, textAlign: TextAlign.center),
  );
}

class _NoteDialog extends StatefulWidget {
  const _NoteDialog({required this.initial});
  final String initial;
  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  late final _c = TextEditingController(text: widget.initial);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Note'),
    content: TextField(
      key: const Key('note-field'),
      controller: _c,
      autofocus: true,
      maxLines: 5,
      minLines: 2,
      decoration: const InputDecoration(
        hintText: 'Your thoughts on this passage',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const Key('note-save'),
        onPressed: () => Navigator.pop(context, _c.text),
        child: const Text('Save'),
      ),
    ],
  );
}

/// Language drop-down and the voices of that language; "Phone default" clears the choice.
class _VoiceSheet extends StatefulWidget {
  const _VoiceSheet({required this.voices, required this.current, required this.engine, required this.auto});
  final bool auto;
  final List<VoiceInfo> voices;
  final VoiceInfo? current;
  final SpeechEngine engine;
  @override
  State<_VoiceSheet> createState() => _VoiceSheetState();
}

class _VoiceSheetState extends State<_VoiceSheet> {
  late String? _locale = widget.current?.locale ?? widget.voices.firstOrNull?.locale;

  @override
  Widget build(BuildContext context) {
    final locales = {for (final v in widget.voices) v.locale}.toList()..sort();
    final shown = [for (final v in widget.voices) if (v.locale == _locale) v];
    final t = Theme.of(context).textTheme;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text('Voice for reading aloud', style: t.titleMedium),
            SwitchListTile(
              key: const Key('voice-auto'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Match the language of the book'),
              subtitle: const Text('Picks an installed voice that speaks the language of the page being read.'),
              value: widget.auto,
              onChanged: (v) => Navigator.pop(context, (voice: widget.current, auto: v)),
            ),
            const SizedBox(height: 8),
            if (widget.voices.isEmpty)
              const Text(
                'This phone did not list any voices. You can add some in the phone\'s Settings, under Language and input, Text-to-speech.',
                key: Key('voice-none'),
              )
            else ...[
              Text('Pick the language of your book:', style: t.bodySmall),
              DropdownButton<String>(
                key: const Key('voice-language'),
                isExpanded: true,
                value: _locale,
                items: [
                  for (final l in locales) DropdownMenuItem(value: l, child: Text(localeLabel(l))),
                ],
                onChanged: (v) => setState(() => _locale = v),
              ),
            ],
            RadioGroup<VoiceInfo?>(
              groupValue: widget.current,
              onChanged: (v) => Navigator.pop(context, (voice: v, auto: false)),
              child: Column(
                children: [
                  const RadioListTile<VoiceInfo?>(
                    key: Key('voice-default'),
                    value: null,
                    title: Text('Phone default'),
                  ),
                  for (final v in shown)
                    RadioListTile<VoiceInfo?>(
                      key: Key('voice-${v.name}'),
                      value: v,
                      title: Text(v.name),
                      subtitle: Text(localeLabel(v.locale)),
                    ),
                ],
              ),
            ),
            TextButton.icon(
              key: const Key('voice-sample'),
              icon: const Icon(Icons.volume_up_outlined),
              label: const Text('Hear a sample of the current voice'),
              onPressed: () => widget.engine.speak('This is how I sound when I read your book.'),
            ),
          ],
        ),
      ),
    );
  }
}
