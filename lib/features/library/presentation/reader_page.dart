import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/components.dart';
import '../../../data/local/app_database.dart';
import '../application/library_controller.dart';

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

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _repo.markOpened(widget.bookId));
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
    final p = _page;
    if (p != null) _repo.saveProgress(widget.bookId, p);
    super.dispose();
  }

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
    return Scaffold(
      appBar: AppBar(
        title: Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
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
              isLabelVisible: marks.isNotEmpty,
              label: Text('${marks.length}'),
              child: const Icon(Icons.list_alt),
            ),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              showDragHandle: true,
              isScrollControlled: true,
              builder: (_) => _BookmarksSheet(
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

class _BookmarksSheet extends ConsumerWidget {
  const _BookmarksSheet({
    required this.bookId,
    required this.current,
    required this.onJump,
  });
  final String bookId;
  final int current;
  final void Function(int page) onJump;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(libraryRepositoryProvider);
    final marks =
        ref.watch(bookmarksProvider(bookId)).value ?? const <BookmarkRow>[];
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.6,
        ),
        child: marks.isEmpty
            ? const Padding(
                padding: EdgeInsets.fromLTRB(24, 8, 24, 32),
                child: Text(
                  'No bookmarks yet. Tap the bookmark icon at the top to mark the page you are on.',
                  textAlign: TextAlign.center,
                ),
              )
            : ListView(
                shrinkWrap: true,
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
                      subtitle: m.label.isEmpty ? null : Text(m.label),
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
      ),
    );
  }
}
