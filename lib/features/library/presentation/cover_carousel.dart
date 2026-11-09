import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/app_database.dart';
import '../../../design_system/tokens.dart';
import '../application/library_controller.dart';
import 'book_peek.dart';
import 'shelf_styles.dart' show BookCover;

/// Shelf style "Cover carousel": the books' covers stand in a 3D row, like records in a crate. Swipe (or use the
/// arrows) and they rotate past; the one in the middle faces you, with its details and Read below.
class CoverCarouselView extends ConsumerStatefulWidget {
  const CoverCarouselView({
    super.key,
    required this.books,
    required this.onOpen,
    required this.onMenu,
    required this.dotOf,
    required this.selection,
  });
  final List<BookRow> books;
  final void Function(BookRow) onOpen, onMenu;
  final Widget? Function(BookRow) dotOf;
  final Set<String>? selection;

  @override
  ConsumerState<CoverCarouselView> createState() => _CoverCarouselViewState();
}

class _CoverCarouselViewState extends ConsumerState<CoverCarouselView> with SingleTickerProviderStateMixin {
  /// Where the row stands: 0 = the first book in the middle, 1.5 = between the second and third.
  late final AnimationController _pos = AnimationController.unbounded(vsync: this);
  final _focus = FocusNode(debugLabel: 'carousel');
  double _step = 120;

  int get _center => _pos.value.round().clamp(0, math.max(0, widget.books.length - 1));

  @override
  void didUpdateWidget(CoverCarouselView old) {
    super.didUpdateWidget(old);
    if (old.books.isEmpty || widget.books.isEmpty) return;
    // keep the same book in the middle when the list changes (sorting, a new book, a sync)
    final id = old.books[_center.clamp(0, old.books.length - 1)].id;
    final i = widget.books.indexWhere((b) => b.id == id);
    _pos.value = (i >= 0 ? i : _pos.value.clamp(0, widget.books.length - 1)).toDouble();
  }

  @override
  void dispose() {
    _pos.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _goTo(int i) {
    if (widget.books.isEmpty) return;
    final to = i.clamp(0, widget.books.length - 1).toDouble();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) {
      _pos.value = to;
    } else {
      _pos.animateTo(to, duration: const Duration(milliseconds: 380), curve: const Cubic(.2, .8, .2, 1));
    }
  }

  void _tap(int i) {
    if (i != _center) {
      _goTo(i);
      return;
    }
    widget.onOpen(widget.books[i]); // reads, or (in selection mode) ticks the book
  }

  KeyEventResult _key(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _goTo(_center - 1);
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.arrowRight) {
      _goTo(_center + 1);
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.enter || e.logicalKey == LogicalKeyboardKey.space) {
      _tap(_center);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final books = widget.books;
    return LayoutBuilder(
      builder: (context, box) {
        final h = ((box.maxHeight - 190) / 1.32).clamp(130.0, 330.0);
        final w = (h * .68).roundToDouble();
        _step = w * .62;
        final stage = h * 1.3 + 28;
        return ListView(
          key: const Key('carousel'),
          padding: const EdgeInsets.only(bottom: Space.s24),
          children: [
            Focus(
              focusNode: _focus,
              onKeyEvent: _key,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _focus.requestFocus(),
                onHorizontalDragStart: (_) => _pos.stop(),
                onHorizontalDragUpdate: (d) {
                  _pos.value = (_pos.value - d.delta.dx / _step).clamp(-.4, books.length - .6);
                },
                onHorizontalDragEnd: (d) {
                  final v = d.primaryVelocity ?? 0;
                  _goTo((_pos.value - v / _step * .12).round());
                },
                child: SizedBox(
                  height: stage,
                  child: AnimatedBuilder(
                    animation: _pos,
                    builder: (context, _) => _stage(box.maxWidth, w, h),
                  ),
                ),
              ),
            ),
            AnimatedBuilder(animation: _pos, builder: (context, _) => _info(books[_center])),
          ],
        );
      },
    );
  }

  Widget _stage(double width, double w, double h) {
    final books = widget.books;
    final p = _pos.value;
    final c = context.colors;
    final from = math.max(0, p.floor() - 5), to = math.min(books.length - 1, p.ceil() + 5);
    final order = [for (var i = from; i <= to; i++) i]..sort((a, b) => (b - p).abs().compareTo((a - p).abs()));
    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        for (final i in order) _cover(i, i - p, width, w, h, c),
      ],
    );
  }

  Widget _cover(int i, double d, double width, double w, double h, FolioColors c) {
    final b = widget.books[i];
    final a = d.abs();
    final x = a <= 1 ? d * _step : d.sign * (_step + (a - 1) * w * .27);
    final angle = -d.clamp(-1.0, 1.0) * .95;
    final scale = 1 - math.min(a, 3) * .07;
    final shade = math.min(a, 4) * .1;
    final isCenter = i == _center;
    final dot = isCenter ? widget.dotOf(b) : null;
    final refl = h * .26;
    final cover = SizedBox(
      width: w,
      height: h,
      child: Stack(
        children: [
          Positioned.fill(
            child: BookCover(book: b, width: w, height: h, onTap: () => _tap(i), faceKey: Key('carousel-cover-${b.id}')),
          ),
          if (shade > 0)
            Positioned.fill(child: IgnorePointer(child: ColoredBox(color: Colors.black.withValues(alpha: shade)))),
          if (dot != null) Positioned(top: 0, left: 0, right: 0, child: dot),
        ],
      ),
    );
    return Positioned(
      left: width / 2 - w / 2,
      top: 14,
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, .0012)
          ..translateByDouble(x, 0, 0, 1)
          ..rotateY(angle)
          ..scaleByDouble(scale, scale, 1, 1),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: isCenter ? .35 : .22), blurRadius: 20, offset: const Offset(0, 10))],
              ),
              child: BookPeekTarget(
                book: b,
                onOpen: () => widget.onOpen(b),
                onMore: () => widget.onMenu(b),
                selected: widget.selection?.contains(b.id),
                child: cover,
              ),
            ),
            const SizedBox(height: 4),
            // a soft reflection on a glossy floor
            IgnorePointer(
              child: ExcludeSemantics(
                child: SizedBox(
                  width: w,
                  height: refl,
                  child: ClipRect(
                    child: Stack(
                      children: [
                        OverflowBox(
                          alignment: Alignment.topCenter,
                          minHeight: h,
                          maxHeight: h,
                          child: Transform.flip(flipY: true, child: BookCover(book: b, width: w, height: h)),
                        ),
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [c.bg.withValues(alpha: .62), c.bg],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _info(BookRow b) {
    final t = Theme.of(context).textTheme;
    final c = context.colors;
    final p = readingProgress(b);
    final started = b.lastPage > 0;
    final n = widget.books.length;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.s24),
      child: Column(
        children: [
          Text(
            b.title,
            key: const Key('carousel-title'),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: t.titleLarge?.copyWith(fontFamily: 'serif'),
          ),
          if (b.author.isNotEmpty) Text(b.author, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodyMedium),
          const SizedBox(height: Space.s4),
          Text(
            [
              '${_center + 1} of $n',
              if (started) 'page ${b.lastPage} of ${b.pageCount}' else if (b.pageCount > 0) '${b.pageCount} pages',
            ].join(' · '),
            style: t.bodySmall,
          ),
          if (started) ...[
            const SizedBox(height: Space.s8),
            SizedBox(
              width: 180,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(value: p, minHeight: 4, color: c.accent, backgroundColor: c.surface2),
              ),
            ),
          ],
          const SizedBox(height: Space.s12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                key: const Key('carousel-prev'),
                tooltip: 'Previous book',
                onPressed: _center > 0 ? () => _goTo(_center - 1) : null,
                icon: const Icon(Icons.chevron_left),
              ),
              const SizedBox(width: Space.s4),
              OutlinedButton(key: const Key('carousel-more'), onPressed: () => widget.onMenu(b), child: const Text('More')),
              const SizedBox(width: Space.s8),
              FilledButton(
                key: const Key('carousel-read'),
                onPressed: () => widget.onOpen(b),
                child: Text(widget.selection != null ? 'Select' : (started ? 'Continue' : 'Read')),
              ),
              const SizedBox(width: Space.s4),
              IconButton(
                key: const Key('carousel-next'),
                tooltip: 'Next book',
                onPressed: _center < n - 1 ? () => _goTo(_center + 1) : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
