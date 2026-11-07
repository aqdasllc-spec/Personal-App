import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/components.dart';
import '../../../data/local/app_database.dart';
import '../application/export_notes.dart';
import '../application/library_controller.dart';
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

  @override
  void initState() {
    super.initState();
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
    final p = _page;
    if (p != null) _repo.saveProgress(widget.bookId, p);
    super.dispose();
  }

  void _openSearch() => setState(() => _searching = true);

  void _closeSearch() {
    _searchDebounce?.cancel();
    _searchCtl.clear();
    _control.stopSearch?.call();
    setState(() => _searching = false);
  }

  void _onQuery(String q) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(
      const Duration(milliseconds: 400),
      () => _control.startSearch?.call(q),
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
        _control.nextMatch?.call();
      } else {
        _control.startSearch?.call(q);
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
              onPressed: s.count == 0 ? null : () => _control.prevMatch?.call(),
            ),
            IconButton(
              key: const Key('reader-search-next'),
              tooltip: 'Next match',
              icon: const Icon(Icons.keyboard_arrow_down),
              onPressed: s.count == 0 ? null : () => _control.nextMatch?.call(),
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

  @override
  Widget build(BuildContext context) {
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
    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? _searchTitle()
            : Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
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
                  key: const Key('reader-bookmark'),
                  tooltip: marked
                      ? 'Remove bookmark from this page'
                      : 'Bookmark this page',
                  icon: Icon(marked ? Icons.bookmark : Icons.bookmark_border),
                  onPressed: () => _repo.toggleBookmark(book.id, current),
                ),
                IconButton(
                  key: const Key('reader-bookmarks'),
                  tooltip: 'Bookmarks',
                  icon: Badge(
                    isLabelVisible: marks.isNotEmpty || highlights.isNotEmpty,
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
      body: file.existsSync()
          ? ref.read(pdfViewBuilderProvider)(
              context,
              file,
              book.lastPage,
              _onPage,
              _control,
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
                      const Expanded(child: Text('Export your notes', style: TextStyle(fontWeight: FontWeight.w600))),
                      TextButton.icon(
                        key: const Key('export-copy'),
                        icon: const Icon(Icons.copy, size: 18),
                        label: const Text('Copy'),
                        onPressed: () async {
                          final m = await exportBookNotes(ref, book, copy: true);
                          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
                        },
                      ),
                      TextButton.icon(
                        key: const Key('export-share'),
                        icon: const Icon(Icons.ios_share, size: 18),
                        label: const Text('Share'),
                        onPressed: () async {
                          final m = await exportBookNotes(ref, book, copy: false);
                          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
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
