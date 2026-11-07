import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/app_database.dart';
import '../../../design_system/tokens.dart';
import '../application/covers.dart';
import '../application/library_controller.dart';
import '../domain_tags.dart';
import 'book_edit.dart';
import 'book_visuals.dart';

/// Lets a finger drag across books to select (or deselect) them while in selection mode.
/// Each selectable book registers itself; the owner turns pointer positions into book ids.
class SelectDragScope extends InheritedWidget {
  const SelectDragScope({super.key, required this.onStart, required this.onMove, required super.child});
  final void Function(String bookId, Offset global) onStart;
  final void Function(Offset global) onMove;
  static SelectDragScope? maybeOf(BuildContext c) => c.dependOnInheritedWidgetOfExactType<SelectDragScope>();
  @override
  bool updateShouldNotify(SelectDragScope old) => false;
}

/// Marks a selectable book on screen so a drag can find which book is under the finger.
class BookTag {
  const BookTag(this.id);
  final String id;
}

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
    this.selected,
  });
  final BookRow book;
  final Widget child;
  final VoidCallback onOpen;

  /// null = normal mode (hover / long-press preview). true / false = selection mode: the book shows a tick or an
  /// empty ring and the preview is off.
  final bool? selected;

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

  void _show({required bool interactive}) {
    if (!mounted || (_interactive && !interactive)) return;
    _hide();
    _interactive = interactive;
    // Centred on the screen so the page and the whole name are easy to read.
    final screen = MediaQuery.sizeOf(context);
    final w = (screen.width - 32).clamp(200.0, 360.0);
    final imageHeight = (screen.height * 0.44).clamp(120.0, 460.0);
    final entry = OverlayEntry(
      builder: (_) => Stack(
        children: [
          if (interactive)
            Positioned.fill(
              child: GestureDetector(
                key: const Key('peek-barrier'),
                behavior: HitTestBehavior.opaque,
                onTap: _hide,
                child: const ColoredBox(color: Color(0x88000000)),
              ),
            ),
          Center(
            child: IgnorePointer(
              ignoring: !interactive,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: w,
                  maxHeight: screen.height - 32,
                ),
                child: _PeekCard(
                  book: widget.book,
                  imageHeight: imageHeight,
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
          ),
        ],
      ),
    );
    _entry = entry;
    Overlay.of(context, rootOverlay: true).insert(entry);
  }

  @override
  Widget build(BuildContext context) {
    // rearranging: no preview card (the book is for dragging)
    if (EditScope.maybeOf(context)?.editing ?? false) {
      _hide();
      return EditableBook(book: widget.book, child: widget.child);
    }
    final sel = widget.selected;
    if (sel != null) {
      _hide();
      final c = context.colors;
      final drag = SelectDragScope.maybeOf(context);
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        // press and hold on a book, then slide over others: they get the same state as the first one
        onLongPressStart: (d) => drag?.onStart(widget.book.id, d.globalPosition),
        onLongPressMoveUpdate: (d) => drag?.onMove(d.globalPosition),
        child: MetaData(
          metaData: BookTag(widget.book.id),
          behavior: HitTestBehavior.translucent,
          child: Stack(
        children: [
          widget.child,
          if (sel)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.accent.withValues(alpha: .18),
                    border: Border.all(color: c.accent, width: 2),
                    borderRadius: BorderRadius.circular(Radii.input),
                  ),
                ),
              ),
            ),
          Positioned(
            left: 4,
            bottom: 4,
            child: IgnorePointer(
              child: Container(
                key: Key(sel ? 'sel-${widget.book.id}' : 'unsel-${widget.book.id}'),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: sel ? c.accent : c.surface.withValues(alpha: .85),
                  border: Border.all(color: sel ? c.onAccent : c.textMuted, width: 1.5),
                ),
                child: sel ? Icon(Icons.check, size: 15, color: c.onAccent) : null,
              ),
            ),
          ),
        ],
      ),
        ),
      );
    }
    return _hoverAndPress();
  }

  Widget _hoverAndPress() => MouseRegion(
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
  const _PeekCard({
    required this.book,
    required this.imageHeight,
    this.onRead,
    this.onMore,
  });
  final BookRow book;
  final double imageHeight;
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
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // first page
            Container(
              height: imageHeight,
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
                error: (_, _) => CoverTile(book: book, size: 150),
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
                  if (decodeTags(book.tags).isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: Space.s4),
                      child: Wrap(
                        key: const Key('peek-tags'),
                        spacing: Space.s4,
                        runSpacing: 0,
                        children: [
                          for (final tag in decodeTags(book.tags))
                            Chip(
                              label: Text('#$tag'),
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              padding: EdgeInsets.zero,
                              labelStyle: t.bodySmall,
                            ),
                        ],
                      ),
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
                            child: Text(
                              book.lastPage > 0 ? 'Continue' : 'Read',
                            ),
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
      ),
    );
  }
}
