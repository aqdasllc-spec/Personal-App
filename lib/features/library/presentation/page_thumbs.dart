import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// What the "Pages" sheet needs to draw its grid.
typedef PageThumbsBuilder = Widget Function(
  BuildContext context, {
  required File file,
  required int pageCount,
  required int current,
  required Set<int> bookmarked,
  required Set<int> drawn,
  required void Function(int page) onPick,
});

/// A grid of small page pictures (drawn by the PDF engine as you scroll). The current page is outlined; a
/// bookmark ribbon and a pen mark show which pages you marked or drew on.
Widget buildPageThumbs(
  BuildContext context, {
  required File file,
  required int pageCount,
  required int current,
  required Set<int> bookmarked,
  required Set<int> drawn,
  required void Function(int page) onPick,
}) => PdfDocumentViewBuilder.file(
  file.path,
  builder: (context, doc) => PageThumbGrid(
    pageCount: pageCount,
    current: current,
    bookmarked: bookmarked,
    drawn: drawn,
    onPick: onPick,
    pictureOf: (page) => PdfPageView(document: doc, pageNumber: page, maximumDpi: 80),
  ),
  loadingBuilder: (_) => const Center(child: CircularProgressIndicator()),
  errorBuilder: (_, _, _) => const Center(child: Text('Could not draw the pages.')),
);

/// The grid itself; [pictureOf] supplies the picture of a page (a fake in tests).
class PageThumbGrid extends StatefulWidget {
  const PageThumbGrid({
    super.key,
    required this.pageCount,
    required this.current,
    required this.bookmarked,
    required this.drawn,
    required this.onPick,
    required this.pictureOf,
  });
  final int pageCount, current;
  final Set<int> bookmarked, drawn;
  final void Function(int page) onPick;
  final Widget Function(int page) pictureOf;
  @override
  State<PageThumbGrid> createState() => _PageThumbGridState();
}

class _PageThumbGridState extends State<PageThumbGrid> {
  late final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, box) {
        final cols = (box.maxWidth / 110).floor().clamp(2, 8);
        const gap = 8.0;
        final cell = (box.maxWidth - 16 - gap * (cols - 1)) / cols;
        final height = cell * 1.41 + 22; // an A4-ish picture and the page number under it
        // open at the current page
        if (_scroll.positions.isEmpty) {
          final row = (widget.current - 1) ~/ cols;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scroll.hasClients) {
              _scroll.jumpTo((row * (height + gap) - box.maxHeight / 3).clamp(0.0, _scroll.position.maxScrollExtent));
            }
          });
        }
        return GridView.builder(
          key: const Key('page-grid'),
          controller: _scroll,
          padding: const EdgeInsets.all(8),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: gap,
            crossAxisSpacing: gap,
            mainAxisExtent: height,
          ),
          itemCount: widget.pageCount,
          itemBuilder: (context, i) {
            final page = i + 1;
            final here = page == widget.current;
            return Semantics(
              button: true,
              selected: here,
              label: 'Page $page${widget.bookmarked.contains(page) ? ', bookmarked' : ''}${widget.drawn.contains(page) ? ', has drawings' : ''}',
              child: InkWell(
                key: Key('thumb-$page'),
                borderRadius: BorderRadius.circular(8),
                onTap: () => widget.onPick(page),
                child: Column(
                  children: [
                    Expanded(
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: here ? scheme.primary : scheme.outlineVariant, width: here ? 3 : 1),
                            ),
                            child: ClipRRect(borderRadius: BorderRadius.circular(4), child: widget.pictureOf(page)),
                          ),
                          if (widget.bookmarked.contains(page))
                            Positioned(
                              top: 0,
                              right: 4,
                              child: Icon(Icons.bookmark, color: scheme.primary, size: 22, key: Key('thumb-mark-$page')),
                            ),
                          if (widget.drawn.contains(page))
                            Positioned(
                              bottom: 2,
                              right: 4,
                              child: Icon(Icons.edit, color: scheme.tertiary, size: 16, key: Key('thumb-ink-$page')),
                            ),
                        ],
                      ),
                    ),
                    Text('$page', style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: here ? FontWeight.w700 : null)),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
