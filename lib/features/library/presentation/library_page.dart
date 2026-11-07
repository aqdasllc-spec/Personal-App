import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../data/local/app_database.dart';
import '../../../design_system/components.dart';
import '../../../design_system/tokens.dart';
import '../application/book_sync.dart';
import '../application/export_notes.dart';
import '../application/library_controller.dart';
import '../data/library_repository.dart';
import '../domain_tags.dart';
import 'book_peek.dart';
import 'book_visuals.dart';

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});
  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  final _search = TextEditingController();
  bool _importing = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _say(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  Future<void> _import() async {
    if (_importing) return;
    final repo = ref.read(libraryRepositoryProvider);
    final filter = ref.read(libraryUiProvider).filter;
    final paths = await ref.read(pdfPickerProvider)();
    if (paths.isEmpty || !mounted) return;
    setState(() => _importing = true);
    var added = 0, dup = 0;
    final bad = <String>[];
    try {
      for (final path in paths) {
        final r = await repo.importPdf(
          path,
          shelfId: filter is ShelfFilter ? filter.shelfId : null,
        );
        switch (r.status) {
          case ImportStatus.added:
            added++;
          case ImportStatus.duplicate:
            dup++;
          case ImportStatus.unreadable:
          case ImportStatus.missing:
            bad.add(r.fileName);
        }
      }
    } catch (e) {
      if (mounted) _say('Import stopped: $e');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
    if (!mounted) return;
    final parts = <String>[
      if (added > 0) 'Added $added ${added == 1 ? 'book' : 'books'}',
      if (dup > 0) '$dup already in your library',
      if (bad.isNotEmpty) 'couldn\'t read ${bad.join(', ')}',
    ];
    if (parts.isNotEmpty) _say(parts.join(' · '));
  }

  Future<void> _newShelf() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _NameDialog(
        title: 'New shelf',
        label: 'Shelf name',
        action: 'Create',
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    final s = await ref.read(libraryRepositoryProvider).createShelf(name);
    ref.read(libraryUiProvider.notifier).setFilter(ShelfFilter(s.id));
  }

  Future<void> _cloudTap(BookRow b) async {
    final ctl = ref.read(bookSyncProvider.notifier);
    if (!ref.read(canCloudSyncProvider)) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Sign in to sync'),
          content: const Text(
            'Cloud sync needs an account. Go to Settings → Account → Sign in to sync.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    final synced = b.cloudState == 'synced';
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: Key(synced ? 'unsync-dialog' : 'sync-dialog'),
        title: Text(synced ? 'Remove from cloud?' : 'Sync to cloud?'),
        content: Text(
          synced
              ? '"${b.title}" is saved in your cloud. Unsync deletes the cloud copy to free space. The book stays on this phone.'
              : 'Upload "${b.title}" (${_size(b.sizeBytes)}) to your private cloud so it is backed up and available on your other devices.',
        ),
        actions: [
          TextButton(
            key: const Key('cloud-cancel'),
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('cloud-confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(synced ? 'Unsync' : 'Sync'),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;
    final ok = synced ? await ctl.unsync(b) : await ctl.sync(b);
    if (!mounted) return;
    final err = ref.read(bookSyncProvider).message;
    if (!ok && err != null) {
      _say(err);
      ctl.clearMessage();
    }
  }

  void _open(BookRow b) => context.push('${Routes.library}/read/${b.id}');

  Future<void> _details(BookRow b) async {
    ScaffoldMessenger.of(context).hideCurrentSnackBar(); // a snackbar would sit on top of the sheet's buttons
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) =>
          _BookSheet(bookId: b.id, onOpen: () => _open(b), onSay: _say),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ui = ref.watch(libraryUiProvider);
    final books = ref.watch(booksProvider);
    final visible = ref.watch(visibleBooksProvider);
    final shelves = ref.watch(shelvesProvider).value ?? const <ShelfRow>[];
    final c = context.colors;
    final cloudOn = ref.watch(cloudBooksProvider) != null;
    final busyIds = ref.watch(bookSyncProvider).busy;
    // The cloud dot is shown only in builds that have cloud sync at all.
    Widget? dotOf(BookRow b) => cloudOn
        ? CloudDot(
            book: b,
            busy: busyIds.contains(b.id),
            onTap: () => _cloudTap(b),
          )
        : null;
    final compact = MediaQuery.sizeOf(context).width < 600;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.s16,
                Space.s16,
                Space.s16,
                Space.s8,
              ),
              child: Wrap(
                spacing: Space.s12,
                runSpacing: Space.s8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Library',
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontFamily: 'serif'),
                  ),
                  SizedBox(
                    width: compact ? double.infinity : 280,
                    child: TextField(
                      key: const Key('library-search'),
                      controller: _search,
                      onChanged: ref.read(libraryUiProvider.notifier).setQuery,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Search title or author',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: ui.query.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear search',
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: () {
                                  _search.clear();
                                  ref
                                      .read(libraryUiProvider.notifier)
                                      .setQuery('');
                                },
                              ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(Radii.input),
                        ),
                      ),
                    ),
                  ),
                  SegmentedButton<LibraryView>(
                    key: const Key('library-views'),
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: LibraryView.shelf,
                        icon: Icon(Icons.shelves),
                        tooltip: 'Shelf',
                      ),
                      ButtonSegment(
                        value: LibraryView.grid,
                        icon: Icon(Icons.grid_view),
                        tooltip: 'Grid',
                      ),
                      ButtonSegment(
                        value: LibraryView.list,
                        icon: Icon(Icons.view_list),
                        tooltip: 'List',
                      ),
                    ],
                    selected: {ui.view},
                    onSelectionChanged: (s) =>
                        ref.read(libraryUiProvider.notifier).setView(s.first),
                  ),
                  IconButton.outlined(
                    key: const Key('library-filter'),
                    tooltip: 'Sort and filter',
                    icon: Badge(
                      isLabelVisible: ui.activeFilters > 0,
                      label: Text('${ui.activeFilters}'),
                      child: const Icon(Icons.tune),
                    ),
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      showDragHandle: true,
                      isScrollControlled: true,
                      builder: (_) => const _FilterSheet(),
                    ),
                  ),
                  FilledButton.icon(
                    key: const Key('library-add'),
                    onPressed: _importing ? null : _import,
                    icon: _importing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add),
                    label: Text(_importing ? 'Adding…' : 'Add PDFs'),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 48,
              child: Row(
                children: [
                  Expanded(
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                        horizontal: Space.s16,
                      ),
                      children: [
                        _chip(
                          'All books',
                          ui.filter is AllBooks,
                          () => ref
                              .read(libraryUiProvider.notifier)
                              .setFilter(const AllBooks()),
                        ),
                        _chip(
                          'Favourites',
                          ui.filter is Favorites,
                          () => ref
                              .read(libraryUiProvider.notifier)
                              .setFilter(const Favorites()),
                          icon: Icons.star_outline,
                        ),
                        for (final s in shelves)
                          _chip(
                            s.name,
                            ui.filter == ShelfFilter(s.id),
                            () => ref
                                .read(libraryUiProvider.notifier)
                                .setFilter(ShelfFilter(s.id)),
                            onLong: () => _shelfMenu(s),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: const Key('library-new-shelf'),
                    tooltip: 'New shelf',
                    icon: const Icon(Icons.create_new_folder_outlined),
                    onPressed: _newShelf,
                  ),
                  const SizedBox(width: Space.s8),
                ],
              ),
            ),
            if (ui.activeFilters > 0)
              SizedBox(
                height: 44,
                child: Row(
                  children: [
                    Expanded(
                      child: ListView(
                        key: const Key('active-filters'),
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: Space.s16),
                        children: [
                          if (ui.status != ReadStatus.all)
                            _activeChip(ui.status.label, () => ref.read(libraryUiProvider.notifier).setStatus(ReadStatus.all), key: const Key('active-status')),
                          for (final t in ui.tags)
                            _activeChip('#$t', () => ref.read(libraryUiProvider.notifier).toggleTag(t), key: Key('active-tag-$t')),
                        ],
                      ),
                    ),
                    // always visible, however many chips there are
                    TextButton(key: const Key('clear-filters'), onPressed: ref.read(libraryUiProvider.notifier).clearFilters, child: const Text('Clear filters')),
                    const SizedBox(width: Space.s8),
                  ],
                ),
              ),
            const _CloudBanner(),
            Expanded(
              child: books.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => EmptyState(
                  icon: Icons.error_outline,
                  title: 'Couldn\'t load your library',
                  message: '$e',
                ),
                data: (all) {
                  if (all.isEmpty) {
                    return EmptyState(
                      icon: Icons.auto_stories_outlined,
                      title: 'Your library is empty',
                      message: 'Add PDFs from your device. Folio keeps its own copy; your original files are never changed.',
                      actionLabel: 'Add PDFs',
                      onAction: _import,
                    );
                  }
                  final list = visible.value ?? const <BookRow>[];
                  if (list.isEmpty) {
                    return EmptyState(
                      icon: Icons.search_off,
                      title: 'Nothing here',
                      message: ui.query.isNotEmpty
                          ? 'No book matches "${ui.query}".'
                          : (ui.activeFilters > 0
                              ? 'No book matches these filters. Remove one above to see more.'
                          : (ui.filter is Favorites
                                ? 'Star a book to find it here.'
                                : 'This shelf is empty. Open a book\'s menu to move it here.')),
                    );
                  }
                  return switch (ui.view) {
                    LibraryView.shelf => _ShelfView(
                      books: list,
                      onOpen: _open,
                      onMenu: _details,
                      dotOf: dotOf,
                    ),
                    LibraryView.grid => _GridView(
                      books: list,
                      onOpen: _open,
                      onMenu: _details,
                      dotOf: dotOf,
                    ),
                    LibraryView.list => _ListView(
                      books: list,
                      onOpen: _open,
                      onMenu: _details,
                      dotOf: dotOf,
                    ),
                  };
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _activeChip(String label, VoidCallback onRemove, {Key? key}) => Padding(
        padding: const EdgeInsets.only(right: Space.s8),
        child: InputChip(key: key, label: Text(label), onDeleted: onRemove, deleteButtonTooltipMessage: 'Remove filter'),
      );

  Widget _chip(
    String label,
    bool selected,
    VoidCallback onTap, {
    IconData? icon,
    VoidCallback? onLong,
  }) => Padding(
    padding: const EdgeInsets.only(right: Space.s8),
    child: GestureDetector(
      onLongPress: onLong,
      child: ChoiceChip(
        avatar: icon == null ? null : Icon(icon, size: 16),
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
      ),
    ),
  );

  Future<void> _shelfMenu(ShelfRow s) async {
    final repo = ref.read(libraryRepositoryProvider);
    final act = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Rename shelf'),
              onTap: () => Navigator.pop(ctx, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete shelf (keeps the books)'),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || act == null) return;
    if (act == 'rename') {
      final n = await showDialog<String>(
        context: context,
        builder: (_) => _NameDialog(
          title: 'Rename shelf',
          label: 'Shelf name',
          action: 'Save',
          initial: s.name,
        ),
      );
      if (n != null && n.trim().isNotEmpty) await repo.renameShelf(s.id, n);
    } else {
      if (ref.read(libraryUiProvider).filter == ShelfFilter(s.id)) {
        ref.read(libraryUiProvider.notifier).setFilter(const AllBooks());
      }
      await repo.deleteShelf(s.id);
    }
  }
}

class _ShelfView extends StatelessWidget {
  final Widget? Function(BookRow) dotOf;
  const _ShelfView({
    required this.dotOf,
    required this.books,
    required this.onOpen,
    required this.onMenu,
  });
  final List<BookRow> books;
  final void Function(BookRow) onOpen, onMenu;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LayoutBuilder(
      builder: (context, box) {
        final avail = box.maxWidth - Space.s32;
        final rows = <List<BookRow>>[[]];
        var used = 0.0;
        for (final b in books) {
          final w = spineWidth(b) + 3;
          if (used + w > avail && rows.last.isNotEmpty) {
            rows.add([]);
            used = 0;
          }
          rows.last.add(b);
          used += w;
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.s16,
            vertical: Space.s16,
          ),
          itemCount: rows.length,
          itemBuilder: (_, i) => Padding(
            padding: const EdgeInsets.only(bottom: Space.s24),
            child: Column(
              children: [
                SizedBox(
                  height: 200,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final b in rows[i])
                        Padding(
                          padding: const EdgeInsets.only(right: 3),
                          child: BookPeekTarget(
                            book: b,
                            onOpen: () => onOpen(b),
                            onMore: () => onMenu(b),
                            child: Spine(
                              book: b,
                              onTap: () => onOpen(b),
                              dot: dotOf(b),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Container(
                  height: 10,
                  decoration: BoxDecoration(
                    color: c.surface2,
                    border: Border(
                      top: BorderSide(color: c.border),
                      bottom: BorderSide(color: c.border),
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x22000000),
                        blurRadius: 6,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _GridView extends StatelessWidget {
  final Widget? Function(BookRow) dotOf;
  const _GridView({
    required this.dotOf,
    required this.books,
    required this.onOpen,
    required this.onMenu,
  });
  final List<BookRow> books;
  final void Function(BookRow) onOpen, onMenu;
  @override
  Widget build(BuildContext context) => GridView.builder(
    padding: const EdgeInsets.all(Space.s16),
    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 180,
      mainAxisExtent: 220,
      crossAxisSpacing: Space.s12,
      mainAxisSpacing: Space.s12,
    ),
    itemCount: books.length,
    itemBuilder: (_, i) {
      final b = books[i];
      return BookPeekTarget(
        book: b,
        onOpen: () => onOpen(b),
        onMore: () => onMenu(b),
        child: InkWell(
          key: Key('book-${b.id}'),
          borderRadius: BorderRadius.circular(Radii.card),
          onTap: () => onOpen(b),
          child: Padding(
            padding: const EdgeInsets.all(Space.s8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Center(
                    child: CoverTile(book: b, size: 120, dot: dotOf(b)),
                  ),
                ),
                const SizedBox(height: Space.s8),
                Text(
                  b.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                if (b.author.isNotEmpty)
                  Text(
                    b.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                if (readingProgress(b) > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: LinearProgressIndicator(
                      value: readingProgress(b),
                      minHeight: 3,
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _ListView extends StatelessWidget {
  final Widget? Function(BookRow) dotOf;
  const _ListView({
    required this.dotOf,
    required this.books,
    required this.onOpen,
    required this.onMenu,
  });
  final List<BookRow> books;
  final void Function(BookRow) onOpen, onMenu;
  @override
  Widget build(BuildContext context) => ListView.separated(
    itemCount: books.length,
    separatorBuilder: (_, _) => const Divider(height: 1),
    itemBuilder: (_, i) {
      final b = books[i];
      final pct = (readingProgress(b) * 100).round();
      return BookPeekTarget(
        book: b,
        onOpen: () => onOpen(b),
        onMore: () => onMenu(b),
        child: ListTile(
          key: Key('book-${b.id}'),
          leading: CoverTile(book: b, size: 48, dot: dotOf(b)),
          title: Text(b.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            [
              if (b.author.isNotEmpty) b.author,
              '${b.pageCount} pages',
              if (b.lastPage > 0) '$pct% read',
            ].join(' · '),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (b.favorite == 1)
                Icon(Icons.star, size: 18, color: context.colors.brass),
              IconButton(
                tooltip: 'Book menu',
                icon: const Icon(Icons.more_vert),
                onPressed: () => onMenu(b),
              ),
            ],
          ),
          onTap: () => onOpen(b),
        ),
      );
    },
  );
}

/// Bottom sheet with details and actions for one book. Reads the live row so edits show at once.
class _BookSheet extends ConsumerWidget {
  const _BookSheet({
    required this.bookId,
    required this.onOpen,
    required this.onSay,
  });
  final String bookId;
  final VoidCallback onOpen;
  final void Function(String) onSay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(libraryRepositoryProvider);
    final b = ref
        .watch(booksProvider)
        .value
        ?.where((x) => x.id == bookId)
        .firstOrNull;
    final shelves = ref.watch(shelvesProvider).value ?? const <ShelfRow>[];
    if (b == null) return const SizedBox(height: 120);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Space.s16, 0, Space.s16, Space.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CoverTile(book: b, size: 72),
                const SizedBox(width: Space.s16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        b.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (b.author.isNotEmpty) Text(b.author),
                      Text(
                        '${b.pageCount} pages · ${_size(b.sizeBytes)}${b.lastPage > 0 ? ' · page ${b.lastPage}' : ''}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.s16),
            Wrap(
              spacing: Space.s8,
              runSpacing: Space.s8,
              children: [
                FilledButton.icon(
                  key: const Key('book-open'),
                  icon: const Icon(Icons.menu_book_outlined),
                  label: Text(b.lastPage > 0 ? 'Continue reading' : 'Read'),
                  onPressed: () {
                    Navigator.pop(context);
                    onOpen();
                  },
                ),
                OutlinedButton.icon(
                  key: const Key('book-favorite'),
                  icon: Icon(b.favorite == 1 ? Icons.star : Icons.star_outline),
                  label: Text(b.favorite == 1 ? 'Unfavourite' : 'Favourite'),
                  onPressed: () => repo.setFavorite(b.id, b.favorite != 1),
                ),
                OutlinedButton.icon(
                  key: const Key('book-edit'),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit details'),
                  onPressed: () async {
                    final r = await showDialog<(String, String, String)>(
                      context: context,
                      builder: (_) => _DetailsDialog(
                        title: b.title,
                        author: b.author,
                        tags: tagsToText(decodeTags(b.tags)),
                      ),
                    );
                    if (r != null) {
                      await repo.updateDetails(b.id, title: r.$1, author: r.$2);
                      await repo.setTags(b.id, r.$3);
                    }
                  },
                ),
                OutlinedButton.icon(
                  key: const Key('book-export'),
                  icon: const Icon(Icons.ios_share),
                  label: const Text('Share notes'),
                  onPressed: () async => onSay(await exportBookNotes(ref, b, copy: false)),
                ),
              ],
            ),
            const SizedBox(height: Space.s16),
            DropdownButtonFormField<String?>(
              key: const Key('book-shelf'),
              initialValue: b.shelfId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Shelf',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('No shelf')),
                for (final s in shelves)
                  DropdownMenuItem(value: s.id, child: Text(s.name)),
              ],
              onChanged: (v) => repo.moveToShelf(b.id, v),
            ),
            const SizedBox(height: Space.s8),
            TextButton.icon(
              key: const Key('book-remove'),
              style: TextButton.styleFrom(
                foregroundColor: context.colors.danger,
              ),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Remove from library'),
              onPressed: () async {
                final m = ScaffoldMessenger.maybeOf(context);
                final removed = await ref
                    .read(bookSyncProvider.notifier)
                    .removeBook(b);
                if (!removed) {
                  // the cloud copy could not be deleted, so the book stays (nothing is left behind in the cloud).
                  // A dialog, not a snackbar: a snackbar would cover this sheet's buttons.
                  final err = ref.read(bookSyncProvider).message;
                  ref.read(bookSyncProvider.notifier).clearMessage();
                  if (err != null && context.mounted) {
                    await showDialog<void>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Can\'t remove it yet'),
                        content: Text(err),
                        actions: [
                          FilledButton(
                            key: const Key('remove-error-ok'),
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('OK'),
                          ),
                        ],
                      ),
                    );
                  }
                  return;
                }
                if (context.mounted) Navigator.pop(context);
                m?.hideCurrentSnackBar();
                m?.showSnackBar(
                  SnackBar(
                    content: Text('Removed "${b.title}"'),
                    action: SnackBarAction(
                      label: 'Undo',
                      onPressed: () => repo.restore(b.id),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

String _size(int bytes) => bytes >= 1048576
    ? '${(bytes / 1048576).toStringAsFixed(1)} MB'
    : '${(bytes / 1024).round()} KB';

class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.label,
    required this.action,
    this.initial = '',
  });
  final String title, label, action, initial;
  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _c = TextEditingController(text: widget.initial);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      key: const Key('name-field'),
      controller: _c,
      autofocus: true,
      decoration: InputDecoration(labelText: widget.label),
      onSubmitted: (v) => Navigator.pop(context, v),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const Key('name-ok'),
        onPressed: () => Navigator.pop(context, _c.text),
        child: Text(widget.action),
      ),
    ],
  );
}

class _DetailsDialog extends StatefulWidget {
  const _DetailsDialog({required this.title, required this.author, required this.tags});
  final String title, author, tags;
  @override
  State<_DetailsDialog> createState() => _DetailsDialogState();
}

class _DetailsDialogState extends State<_DetailsDialog> {
  late final _t = TextEditingController(text: widget.title);
  late final _a = TextEditingController(text: widget.author);
  late final _g = TextEditingController(text: widget.tags);
  @override
  void dispose() {
    _t.dispose();
    _a.dispose();
    _g.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Edit details'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          key: const Key('details-title'),
          controller: _t,
          decoration: const InputDecoration(labelText: 'Title'),
        ),
        TextField(
          key: const Key('details-author'),
          controller: _a,
          decoration: const InputDecoration(labelText: 'Author'),
        ),
        TextField(
          key: const Key('details-tags'),
          controller: _g,
          decoration: const InputDecoration(labelText: 'Tags', hintText: 'work, to read, safety'),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const Key('details-save'),
        onPressed: _t.text.trim().isEmpty
            ? null
            : () => Navigator.pop(context, (_t.text, _a.text, _g.text)),
        child: const Text('Save'),
      ),
    ],
  );
}

/// "N books are in your cloud but not on this phone" with a Download button.
class _CloudBanner extends ConsumerWidget {
  const _CloudBanner();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.watch(cloudOnlyCountProvider).value ?? 0;
    final busy = ref.watch(bookSyncProvider).busy.contains('*download');
    if (n == 0) return const SizedBox.shrink();
    return Container(
      key: const Key('cloud-banner'),
      margin: const EdgeInsets.fromLTRB(
        Space.s16,
        Space.s4,
        Space.s16,
        Space.s8,
      ),
      padding: const EdgeInsets.all(Space.s12),
      decoration: BoxDecoration(
        color: context.colors.accentSoft,
        borderRadius: BorderRadius.circular(Radii.card),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_download_outlined),
          const SizedBox(width: Space.s12),
          Expanded(
            child: Text(
              '$n ${n == 1 ? 'book is' : 'books are'} in your cloud but not on this phone.',
            ),
          ),
          TextButton(
            key: const Key('cloud-download'),
            onPressed: busy
                ? null
                : () async {
                    final ctl = ref.read(bookSyncProvider.notifier);
                    await ctl.downloadAll();
                    final m = ref.read(bookSyncProvider).message;
                    if (m != null && context.mounted) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text(m)));
                      ctl.clearMessage();
                    }
                  },
            child: Text(busy ? 'Downloading…' : 'Download'),
          ),
        ],
      ),
    );
  }
}


/// Sort order, reading status and tags.
class _FilterSheet extends ConsumerWidget {
  const _FilterSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(libraryUiProvider);
    final ctl = ref.read(libraryUiProvider.notifier);
    final tags = tagCounts(ref.watch(booksProvider).value ?? const <BookRow>[]);
    final t = Theme.of(context).textTheme;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Space.s16, 0, Space.s16, Space.s16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Sort by', style: t.titleSmall),
              const SizedBox(height: Space.s8),
              Wrap(
                spacing: Space.s8,
                runSpacing: Space.s4,
                children: [
                  for (final s in LibrarySort.values)
                    ChoiceChip(
                      key: Key('sort-${s.name}'),
                      label: Text(s.label),
                      selected: ui.sort == s,
                      onSelected: (_) => ctl.setSort(s),
                    ),
                ],
              ),
              const SizedBox(height: Space.s16),
              Text('Reading status', style: t.titleSmall),
              const SizedBox(height: Space.s8),
              Wrap(
                spacing: Space.s8,
                runSpacing: Space.s4,
                children: [
                  for (final s in ReadStatus.values)
                    ChoiceChip(
                      key: Key('status-${s.name}'),
                      label: Text(s.label),
                      selected: ui.status == s,
                      onSelected: (_) => ctl.setStatus(s),
                    ),
                ],
              ),
              const SizedBox(height: Space.s16),
              Text('Tags', style: t.titleSmall),
              const SizedBox(height: Space.s8),
              if (tags.isEmpty)
                Text('No tags yet. Open a book\'s menu → Edit details to add some (for example: work, to read, safety).', style: t.bodySmall)
              else
                Wrap(
                  spacing: Space.s8,
                  runSpacing: Space.s4,
                  children: [
                    for (final (tag, count) in tags)
                      FilterChip(
                        key: Key('tag-filter-$tag'),
                        label: Text('$tag · $count'),
                        selected: ui.tags.any((x) => x.toLowerCase() == tag.toLowerCase()),
                        onSelected: (_) => ctl.toggleTag(tag),
                      ),
                  ],
                ),
              if (ui.activeFilters > 0)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(key: const Key('sheet-clear'), onPressed: ctl.clearFilters, child: const Text('Clear filters')),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
