import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/components.dart';
import '../../../data/local/app_database.dart';
import '../application/export_notes.dart';
import '../application/library_controller.dart';
import '../application/ocr_controller.dart';
import '../domain_ink.dart';
import '../domain_ocr.dart';
import '../application/reader_prefs.dart';
import '../../settings/rotation.dart';
import 'reader_settings_sheet.dart';
import '../domain_highlights.dart';

/// Full-screen PDF reader. Remembers the page you were on.
class ReaderPage extends ConsumerStatefulWidget {
  const ReaderPage({super.key, required this.bookId});
  final String bookId;
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
  final _inkOrder = <int>[]; // pages in the order strokes were drawn (for Undo)
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
    _control.onStroke = _onStroke;
    _ocr.progress.addListener(() {
      if (mounted) setState(() {});
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

  Future<void> _onStroke(int page, Stroke s) async {
    final list = [...(_control.ink.value[page] ?? const <Stroke>[]), s];
    _control.ink.value = {..._control.ink.value, page: list};
    _inkOrder.add(page);
    await _repo.saveInk(widget.bookId, page, list);
  }

  Future<void> _undoStroke() async {
    while (_inkOrder.isNotEmpty) {
      final page = _inkOrder.removeLast();
      final list = [...(_control.ink.value[page] ?? const <Stroke>[])];
      if (list.isEmpty) continue;
      list.removeLast();
      _control.ink.value = {..._control.ink.value, page: list};
      await _repo.saveInk(widget.bookId, page, list);
      return;
    }
  }

  Future<void> _clearInkPage(int page) async {
    _inkOrder.removeWhere((p) => p == page);
    _control.ink.value = {..._control.ink.value, page: const []};
    await _repo.saveInk(widget.bookId, page, const []);
  }

  void _setPen(PenState p) {
    _control.pen.value = p;
    setState(() {});
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
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          // wraps onto a second line on narrow screens so every button stays reachable
          child: Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (var i = 0; i < penColors.length; i++)
                Semantics(
                  button: true,
                  selected: pen.color == i,
                  label: '${penColors[i].$1} pen',
                  child: InkResponse(
                    key: Key('pen-color-$i'),
                    onTap: () => _setPen(pen.copyWith(color: i)),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Color(penColors[i].$2),
                          shape: BoxShape.circle,
                          border: pen.color == i
                              ? Border.all(color: scheme.primary, width: 3)
                              : null,
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              SegmentedButton<int>(
                key: const Key('pen-width'),
                showSelectedIcon: false,
                segments: [
                  for (var i = 0; i < penWidths.length; i++)
                    ButtonSegment(value: i, label: Text(penWidths[i].$1)),
                ],
                selected: {pen.width},
                onSelectionChanged: (v) => _setPen(pen.copyWith(width: v.first)),
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
              TextButton(
                key: const Key('pen-done'),
                onPressed: () => _setPen(pen.copyWith(on: false)),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onPage(int page) {
    setState(() => _page = page);
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
    _ocr.dispose();
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
                  : Text(
                      book.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
                          if (v == 'pen') {
                            _setPen(
                              _control.pen.value.copyWith(
                                on: !_control.pen.value.on,
                              ),
                            );
                          }
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            key: const Key('reader-pen'),
                            value: 'pen',
                            child: Text(
                              _control.pen.value.on
                                  ? 'Stop drawing'
                                  : 'Draw with a pen',
                            ),
                          ),
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
                          if (_useOcr)
                            const PopupMenuItem(
                              value: 'text',
                              child: Text('Text of this page'),
                            ),
                        ],
                      ),
                      IconButton(
                        key: const Key('reader-bookmark'),
                        tooltip: marked
                            ? 'Remove bookmark from this page'
                            : 'Bookmark this page',
                        icon: Icon(
                          marked ? Icons.bookmark : Icons.bookmark_border,
                        ),
                        onPressed: () => _repo.toggleBookmark(book.id, current),
                      ),
                      IconButton(
                        key: const Key('reader-bookmarks'),
                        tooltip: 'Bookmarks',
                        icon: Badge(
                          isLabelVisible:
                              marks.isNotEmpty || highlights.isNotEmpty,
                          label: Text('${marks.length + highlights.length}'),
                          child: const Icon(Icons.list_alt),
                        ),
                        onPressed: () => showModalBottomSheet<void>(
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
                      if (book.pageCount > 0)
                        Padding(
                          padding: const EdgeInsets.only(right: 16),
                          child: Center(
                            child: Text(
                              '${_page ?? (book.lastPage < 1 ? 1 : book.lastPage)} / ${book.pageCount}',
                              key: const Key('reader-page'),
                            ),
                          ),
                        ),
                    ],
            ),
      bottomNavigationBar: _immersive
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_control.pen.value.on) _penBar(current),
                if (book.pageCount >= 2) _pageBar(current, book.pageCount),
              ],
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
                      book.lastPage,
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
