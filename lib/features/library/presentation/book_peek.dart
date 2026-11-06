import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/app_database.dart';
import '../../../design_system/tokens.dart';
import '../application/covers.dart';
import '../application/library_controller.dart';
import 'book_visuals.dart';

/// Wraps a book so that:
///  * hovering it with a mouse (desktop) floats a preview card above it, and
///  * long-pressing it (phone/tablet) opens the same card with Read / More buttons.
/// The card shows the first page, the full title, the author and reading progress.
class BookPeekTarget extends StatefulWidget {
  const BookPeekTarget({
    super.key,
    required this.book,
    required this.child,
    required this.onOpen,
    this.onMore,
  });
  final BookRow book;
  final Widget child;
  final VoidCallback onOpen;

  /// Opens the full book menu. Null hides the "More" button.
  final VoidCallback? onMore;

  @override
  State<BookPeekTarget> createState() => _BookPeekTargetState();
}

class _BookPeekTargetState extends State<BookPeekTarget> {
  Timer? _hoverTimer;
  OverlayEntry? _entry;
  bool _interactive = false;

  @override
  void dispose() {
    _hoverTimer?.cancel();
    _entry?.remove();
    _entry = null;
    super.dispose();
  }

  void _hide() {
    _hoverTimer?.cancel();
    _entry?.remove();
    _entry = null;
    _interactive = false;
  }

  Rect? _anchor() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  void _show({required bool interactive}) {
    if (!mounted || (_interactive && !interactive)) return;
    final anchor = _anchor();
    if (anchor == null) return;
    _hide();
    _interactive = interactive;
    final screen = MediaQuery.sizeOf(context);
    const w = 232.0;
    final left = (anchor.center.dx - w / 2).clamp(
      8.0,
      (screen.width - w - 8).clamp(8.0, double.infinity),
    );
    // Above the book when there is room, else below, else centred over it.
    final above = anchor.top > 330;
    final below = !above && screen.height - anchor.bottom > 330;
    final entry = OverlayEntry(
      builder: (_) => Stack(
        children: [
          if (interactive)
            Positioned.fill(
              child: GestureDetector(
                key: const Key('peek-barrier'),
                behavior: HitTestBehavior.opaque,
                onTap: _hide,
                child: const ColoredBox(color: Color(0x33000000)),
              ),
            ),
          Positioned(
            left: left,
            width: w,
            bottom: above ? screen.height - anchor.top + 8 : null,
            top: above
                ? null
                : (below
                      ? anchor.bottom + 8
                      : (screen.height / 2 - 170).clamp(8.0, double.infinity)),
            child: IgnorePointer(
              ignoring: !interactive,
              child: _PeekCard(
                book: widget.book,
                onRead: !interactive
                    ? null
                    : () {
                        _hide();
                        widget.onOpen();
                      },
                onMore: !interactive || widget.onMore == null
                    ? null
                    : () {
                        _hide();
                        widget.onMore!();
                      },
              ),
            ),
          ),
        ],
      ),
    );
    _entry = entry;
    Overlay.of(context, rootOverlay: true).insert(entry);
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) {
      _hoverTimer?.cancel();
      _hoverTimer = Timer(
        const Duration(milliseconds: 350),
        () => _show(interactive: false),
      );
    },
    onExit: (_) {
      _hoverTimer?.cancel();
      if (!_interactive) _hide();
    },
    child: Listener(
      // pressing the book (to open it) dismisses the hover card
      onPointerDown: (_) {
        if (!_interactive) _hide();
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onLongPress: () => _show(interactive: true),
        child: widget.child,
      ),
    ),
  );
}

class _PeekCard extends ConsumerWidget {
  const _PeekCard({required this.book, this.onRead, this.onMore});
  final BookRow book;
  final VoidCallback? onRead, onMore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final cover = ref.watch(coverBytesProvider(book.id));
    final pct = (readingProgress(book) * 100).round();
    return Material(
      key: Key('peek-${book.id}'),
      elevation: 12,
      color: c.surface,
      borderRadius: BorderRadius.circular(Radii.card),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // first page
          Container(
            height: 250,
            color: c.surface2,
            alignment: Alignment.center,
            child: cover.when(
              data: (bytes) => bytes == null
                  ? CoverTile(book: book, size: 150)
                  : Image.memory(
                      bytes,
                      key: const Key('peek-image'),
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                    ),
              loading: () => const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              error: (_, __) => CoverTile(book: book, size: 150),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(Space.s12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  book.title,
                  key: const Key('peek-title'),
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                  style: t.titleSmall?.copyWith(
                    fontFamily: 'serif',
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (book.author.isNotEmpty)
                  Text(
                    book.author,
                    key: const Key('peek-author'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodySmall,
                  ),
                const SizedBox(height: Space.s4),
                Text(
                  '${book.pageCount} pages${book.lastPage > 0 ? ' · $pct% read' : ' · not started'}',
                  style: t.bodySmall?.copyWith(color: c.textMuted),
                ),
                if (book.lastPage > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.s4),
                    child: LinearProgressIndicator(
                      value: readingProgress(book),
                      minHeight: 3,
                    ),
                  ),
                if (onRead != null) ...[
                  const SizedBox(height: Space.s12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          key: const Key('peek-read'),
                          onPressed: onRead,
                          child: Text(book.lastPage > 0 ? 'Continue' : 'Read'),
                        ),
                      ),
                      if (onMore != null) ...[
                        const SizedBox(width: Space.s8),
                        OutlinedButton(
                          key: const Key('peek-more'),
                          onPressed: onMore,
                          child: const Text('More'),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
