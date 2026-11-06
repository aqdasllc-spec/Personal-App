import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/components.dart';
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
    return Scaffold(
      appBar: AppBar(
        title: Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
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
            )
          : const EmptyState(
              icon: Icons.broken_image_outlined,
              title: 'The file is missing',
              message: 'Folio can\'t find this book\'s PDF on this device. Remove it and add the PDF again.',
            ),
    );
  }
}
