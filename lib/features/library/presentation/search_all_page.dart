import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../data/local/app_database.dart';
import '../application/library_controller.dart';
import '../application/search_all.dart';
import '../domain_highlights.dart';
import '../domain_search_all.dart';

/// Two tabs: search the text inside every book, and every highlight you made with colour filters.
class SearchAllPage extends ConsumerStatefulWidget {
  const SearchAllPage({super.key});
  @override
  ConsumerState<SearchAllPage> createState() => _SearchAllPageState();
}

class _SearchAllPageState extends ConsumerState<SearchAllPage> {
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  void _open(String bookId, int page, {String? query}) => context.push(
    '${Routes.library}/read/$bookId?page=$page${query == null ? '' : '&q=${Uri.encodeQueryComponent(query)}'}',
  );

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Search and notes'),
        bottom: const TabBar(
          tabs: [
            Tab(key: Key('tab-search-books'), text: 'In books'),
            Tab(key: Key('tab-all-highlights'), text: 'Highlights'),
          ],
        ),
      ),
      body: TabBarView(
        children: [
          _InBooks(controller: _q, onOpen: _open),
          _Highlights(onOpen: (b, p) => _open(b, p)),
        ],
      ),
    ),
  );
}

class _InBooks extends ConsumerWidget {
  const _InBooks({required this.controller, required this.onOpen});
  final TextEditingController controller;
  final void Function(String bookId, int page, {String? query}) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(searchAllProvider);
    final ctl = ref.read(searchAllProvider.notifier);
    final t = Theme.of(context).textTheme;
    final byBook = <String, List<BookHit>>{};
    for (final h in s.hits) {
      byBook.putIfAbsent(h.bookId, () => []).add(h);
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            key: const Key('search-all-field'),
            controller: controller,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search the text in all your books',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: s.running
                  ? IconButton(key: const Key('search-all-stop'), tooltip: 'Stop searching', icon: const Icon(Icons.stop_circle_outlined), onPressed: ctl.stop)
                  : null,
              border: const OutlineInputBorder(),
            ),
            onChanged: ctl.typed,
            onSubmitted: ctl.start,
          ),
        ),
        if (s.running) LinearProgressIndicator(value: s.booksTotal == 0 ? null : s.booksDone / s.booksTotal),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              s.query.isEmpty
                  ? 'Type at least two letters: results come as you type. The first search reads each book once; after that it is instant. Scanned books are searched after you chose "Make searchable" in them.'
                  : s.query.length < 2
                  ? 'Type at least two letters to search.'
                  : s.running
                  ? 'Searching… ${s.booksDone} of ${s.booksTotal} books, ${s.hits.length} found'
                  : s.hits.isEmpty
                  ? 'Nothing found for "${s.query}".'
                  : '${s.hits.length}${s.truncated ? '+' : ''} ${s.hits.length == 1 ? 'place' : 'places'} in ${byBook.length} ${byBook.length == 1 ? 'book' : 'books'}',
              key: const Key('search-all-status'),
              style: t.bodySmall,
            ),
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              for (final e in byBook.entries) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(e.value.first.title, style: t.titleSmall),
                ),
                for (final h in e.value)
                  ListTile(
                    key: Key('hit-${h.bookId}-${h.page}'),
                    dense: true,
                    title: Text(h.snippet, maxLines: 3, overflow: TextOverflow.ellipsis),
                    subtitle: Text('Page ${h.page}'),
                    onTap: () => onOpen(h.bookId, h.page, query: s.query),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Highlights extends ConsumerStatefulWidget {
  const _Highlights({required this.onOpen});
  final void Function(String bookId, int page) onOpen;
  @override
  ConsumerState<_Highlights> createState() => _HighlightsState();
}

class _HighlightsState extends ConsumerState<_Highlights> {
  String? _color; // null = all

  Future<void> _rename(String color) async {
    final cur = ref.read(highlightMeaningsProvider)[color] ?? '';
    final v = await showDialog<String>(
      context: context,
      builder: (_) => _MeaningDialog(colorName: highlightColorNames[color] ?? color, initial: cur),
    );
    if (v != null) ref.read(highlightMeaningsProvider.notifier).set(color, v);
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(allHighlightsProvider).value ?? const <HighlightRow>[];
    final meanings = ref.watch(highlightMeaningsProvider);
    final books = {for (final b in ref.watch(booksProvider).value ?? const <BookRow>[]) b.id: b};
    // highlights of removed books are hidden with the book
    final visible = [for (final h in all) if (books.containsKey(h.bookId)) h];
    final shown = [for (final h in visible) if (_color == null || h.color == _color) h];
    final t = Theme.of(context).textTheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                key: const Key('hl-filter-all'),
                label: Text('All (${visible.length})'),
                selected: _color == null,
                onSelected: (_) => setState(() => _color = null),
              ),
              for (final e in highlightColorNames.entries)
                GestureDetector(
                  onLongPress: () => _rename(e.key),
                  child: ChoiceChip(
                    key: Key('hl-filter-${e.key}'),
                    avatar: CircleAvatar(radius: 8, backgroundColor: highlightColor(e.key)),
                    label: Text('${meanings[e.key] ?? e.value} (${visible.where((h) => h.color == e.key).length})'),
                    selected: _color == e.key,
                    onSelected: (_) => setState(() => _color = _color == e.key ? null : e.key),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Expanded(child: Text('Press and hold a colour to say what it means to you.', style: t.bodySmall)),
              TextButton.icon(
                key: const Key('hl-copy'),
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('Copy'),
                onPressed: shown.isEmpty
                    ? null
                    : () async {
                        final text = shown
                            .map((h) => '"${h.snippet}" — ${books[h.bookId]!.title}, p. ${h.page}${h.note.isEmpty ? '' : '\n  Note: ${h.note}'}')
                            .join('\n\n');
                        await Clipboard.setData(ClipboardData(text: text));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Copied ${shown.length} ${shown.length == 1 ? 'highlight' : 'highlights'}.')));
                        }
                      },
              ),
            ],
          ),
        ),
        Expanded(
          child: shown.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    visible.isEmpty ? 'No highlights yet. Select text in a book and choose Highlight.' : 'No highlights in this colour.',
                    key: const Key('hl-empty'),
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView(
                  children: [
                    for (final h in shown)
                      ListTile(
                        key: Key('hl-${h.id}'),
                        leading: CircleAvatar(radius: 8, backgroundColor: highlightColor(h.color)),
                        title: Text(h.snippet.isEmpty ? '(no text)' : h.snippet, maxLines: 3, overflow: TextOverflow.ellipsis),
                        subtitle: Text('${books[h.bookId]!.title} · page ${h.page}${h.note.isEmpty ? '' : '\n${h.note}'}'),
                        isThreeLine: h.note.isNotEmpty,
                        onTap: () => widget.onOpen(h.bookId, h.page),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// Asks what a highlight colour means. Owns its text controller, so it is only disposed after the dialog has closed.
class _MeaningDialog extends StatefulWidget {
  const _MeaningDialog({required this.colorName, required this.initial});
  final String colorName, initial;
  @override
  State<_MeaningDialog> createState() => _MeaningDialogState();
}

class _MeaningDialogState extends State<_MeaningDialog> {
  late final _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('What does ${widget.colorName} mean?'),
    content: TextField(
      key: const Key('meaning-field'),
      controller: _c,
      autofocus: true,
      maxLength: 30,
      decoration: const InputDecoration(hintText: 'For example: Important, Quote, To check'),
      onSubmitted: (v) => Navigator.pop(context, v),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(key: const Key('meaning-save'), onPressed: () => Navigator.pop(context, _c.text), child: const Text('Save')),
    ],
  );
}
