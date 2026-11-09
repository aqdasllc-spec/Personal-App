import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/app_database.dart';
import '../../../design_system/tokens.dart';
import '../application/library_controller.dart';
import 'book_peek.dart';
import 'book_visuals.dart' show bookColor;
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
    this.fullscreen = false,
    this.initialIndex = 0,
    this.onCenter,
  });
  final List<BookRow> books;
  final void Function(BookRow) onOpen, onMenu;
  final Widget? Function(BookRow) dotOf;
  final Set<String>? selection;

  /// The full-screen version (bigger covers, no Library header); Close returns the book in the middle.
  final bool fullscreen;
  final int initialIndex;

  /// Told whenever a different book comes to the middle.
  final ValueChanged<int>? onCenter;

  @override
  ConsumerState<CoverCarouselView> createState() => _CoverCarouselViewState();
}

class _CoverCarouselViewState extends ConsumerState<CoverCarouselView> with SingleTickerProviderStateMixin {
  /// Where the row stands: 0 = the first book in the middle, 1.5 = between the second and third.
  late final AnimationController _pos = AnimationController.unbounded(
    vsync: this,
    value: widget.initialIndex.clamp(0, math.max(0, widget.books.length - 1)).toDouble(),
  );
  final _focus = FocusNode(debugLabel: 'carousel');
  double _step = 120;

  int get _center => _pos.value.round().clamp(0, math.max(0, widget.books.length - 1));

  int _lastCenter = -1;

  @override
  void initState() {
    super.initState();
    _pos.addListener(() {
      final c = _center;
      if (c != _lastCenter) {
        _lastCenter = c;
        widget.onCenter?.call(c);
      }
    });
  }

  @override
  void didUpdateWidget(CoverCarouselView old) {
    super.didUpdateWidget(old);
    if (identical(old.books, widget.books) || old.books.isEmpty || widget.books.isEmpty) return;
    // keep the same book in the middle when the list changes (sorting, a new book, a sync)
    final id = old.books[_center.clamp(0, old.books.length - 1)].id;
    final i = widget.books.indexWhere((b) => b.id == id);
    final to = (i >= 0 ? i : _pos.value.clamp(0, widget.books.length - 1)).toDouble();
    if (to != _pos.value) {
      // not during this build: listeners outside this widget may rebuild
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _pos.value = to;
      });
    }
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

  /// Opens the full-screen carousel at the current book; when it closes, this one moves to where it ended.
  Future<void> _openFull() async {
    final i = await Navigator.of(context, rootNavigator: true).push<int>(
      PageRouteBuilder(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 240),
        pageBuilder: (_, _, _) => _FullCarousel(
          books: widget.books,
          start: _center,
          onOpen: widget.onOpen,
          onMenu: widget.onMenu,
          dotOf: widget.dotOf,
        ),
        transitionsBuilder: (_, a, _, child) => FadeTransition(
          opacity: a,
          child: ScaleTransition(scale: Tween(begin: .96, end: 1.0).animate(a), child: child),
        ),
      ),
    );
    if (i != null && mounted) _pos.value = i.toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final books = widget.books;
    return LayoutBuilder(
      builder: (context, box) {
        // As big as fits: the details below need about 170 px; covers keep a book's proportions (0.68) and leave
        // room at the sides for their neighbours.
        final reserve = widget.fullscreen ? 250.0 : 150.0;
        var h = ((box.maxHeight - reserve) / 1.16).clamp(180.0, 620.0);
        final maxW = box.maxWidth * (widget.fullscreen ? .7 : .62);
        if (h * .68 > maxW) h = maxW / .68;
        final w = (h * .68).roundToDouble();
        _step = w * .7;
        final stage = h * 1.14 + 22;
        return ListView(
          key: Key(widget.fullscreen ? 'carousel-full' : 'carousel'),
          padding: const EdgeInsets.only(bottom: Space.s24),
          children: [
            Focus(
              focusNode: _focus,
              autofocus: widget.fullscreen,
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
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: AnimatedBuilder(animation: _pos, builder: (context, _) => _stage(box.maxWidth, w, h)),
                      ),
                      if (!widget.fullscreen)
                        Positioned(
                          top: 8,
                          left: 12,
                          child: AnimatedBuilder(
                            animation: _pos,
                            builder: (context, _) => _pill('${_center + 1} of ${books.length}'),
                          ),
                        ),
                      if (!widget.fullscreen)
                        Positioned(
                          top: 4,
                          right: 8,
                          child: IconButton.filledTonal(
                            key: const Key('carousel-open-full'),
                            tooltip: 'Full screen',
                            icon: const Icon(Icons.open_in_full, size: 20),
                            onPressed: _openFull,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            AnimatedBuilder(
              animation: _pos,
              builder: (context, _) => widget.fullscreen ? _info(books[_center]) : _compactInfo(books[_center]),
            ),
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
    return Stack(clipBehavior: Clip.hardEdge, children: [for (final i in order) _cover(i, i - p, width, w, h, c)]);
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
    final refl = h * .14;
    final cover = SizedBox(
      width: w,
      height: h,
      child: Stack(
        children: [
          Positioned.fill(
            child: BookCover(
              book: b,
              width: w,
              height: h,
              onTap: () => _tap(i),
              faceKey: Key('carousel-cover-${b.id}'),
            ),
          ),
          if (shade > 0)
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(color: Colors.black.withValues(alpha: shade)),
              ),
            ),
          if (dot != null) Positioned(top: 0, left: 0, right: 0, child: dot),
        ],
      ),
    );
    return Positioned(
      left: width / 2 - w / 2,
      top: 10,
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
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isCenter ? .35 : .22),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
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
                          child: Transform.flip(
                            flipY: true,
                            child: BookCover(book: b, width: w, height: h),
                          ),
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

  Widget _pill(String text) {
    final c = context.colors;
    return Container(
      key: const Key('carousel-position'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.surface.withValues(alpha: .9),
        borderRadius: BorderRadius.circular(Radii.pill),
        border: Border.all(color: c.border),
      ),
      child: Text(text, style: Theme.of(context).textTheme.labelMedium),
    );
  }

  /// Under the cover on the shelf: title, one line of details, a thin progress bar and the buttons; the cover gets the room.
  Widget _compactInfo(BookRow b) {
    final t = Theme.of(context).textTheme;
    final c = context.colors;
    final p = readingProgress(b);
    final started = b.lastPage > 0;
    final finished = p >= .95;
    final n = widget.books.length;
    final details = [
      if (b.author.isNotEmpty) b.author,
      if (finished)
        'Finished'
      else if (started)
        'page ${b.lastPage} of ${b.pageCount} · ${(p * 100).round()}%'
      else if (b.pageCount > 0)
        '${b.pageCount} pages',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.s16),
      child: Column(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Column(
              key: ValueKey(b.id),
              children: [
                Text(
                  b.title,
                  key: const Key('carousel-title'),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.titleLarge?.copyWith(fontFamily: 'serif', fontWeight: FontWeight.w600),
                ),
                if (details.isNotEmpty)
                  Text(
                    details,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodySmall?.copyWith(color: c.textMuted),
                  ),
                if (started && !finished) ...[
                  const SizedBox(height: Space.s8),
                  SizedBox(
                    width: 200,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: p,
                        minHeight: 4,
                        color: c.accent,
                        backgroundColor: c.surface2,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: Space.s8),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: Space.s4,
            runSpacing: Space.s4,
            children: [
              IconButton(
                key: const Key('carousel-prev'),
                tooltip: 'Previous book',
                onPressed: _center > 0 ? () => _goTo(_center - 1) : null,
                icon: const Icon(Icons.chevron_left),
              ),
              OutlinedButton(
                key: const Key('carousel-more'),
                onPressed: () => widget.onMenu(b),
                child: const Text('More'),
              ),
              FilledButton.icon(
                key: const Key('carousel-read'),
                onPressed: () => widget.onOpen(b),
                icon: Icon(widget.selection != null ? Icons.check : Icons.auto_stories_outlined, size: 18),
                label: Text(widget.selection != null ? 'Select' : (started && !finished ? 'Continue' : 'Read')),
              ),
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

  Widget _info(BookRow b) {
    final t = Theme.of(context).textTheme;
    final c = context.colors;
    final p = readingProgress(b);
    final started = b.lastPage > 0;
    final finished = p >= .95;
    final n = widget.books.length;
    final muted = t.bodyMedium?.copyWith(color: c.textMuted);
    Widget chip(IconData icon, String text, {Key? key}) => Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(Radii.pill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: c.textMuted),
          const SizedBox(width: 5),
          Text(text, style: t.labelMedium?.copyWith(color: c.text)),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.s24, 0, Space.s24, 0),
      child: Column(
        children: [
          Text(
            '${_center + 1} of $n',
            key: const Key('carousel-position'),
            style: t.labelSmall?.copyWith(color: c.textMuted, letterSpacing: .6),
          ),
          const SizedBox(height: Space.s4),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Column(
              key: ValueKey(b.id),
              children: [
                Text(
                  b.title,
                  key: const Key('carousel-title'),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.headlineSmall?.copyWith(fontFamily: 'serif', height: 1.2),
                ),
                if (b.author.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    b.author,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: muted,
                  ),
                ],
                const SizedBox(height: Space.s12),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: Space.s8,
                  runSpacing: Space.s8,
                  children: [
                    if (finished)
                      chip(Icons.check_circle_outline, 'Finished', key: const Key('carousel-finished'))
                    else if (started)
                      chip(Icons.bookmark_outline, 'Page ${b.lastPage} of ${b.pageCount} · ${(p * 100).round()}%')
                    else if (b.pageCount > 0)
                      chip(Icons.menu_book_outlined, '${b.pageCount} pages · not started'),
                    if (b.lastOpenedAt != null) chip(Icons.schedule, _ago(b.lastOpenedAt!)),
                    if (b.favorite == 1) chip(Icons.star_rounded, 'Favourite'),
                  ],
                ),
                if (started && !finished) ...[
                  const SizedBox(height: Space.s12),
                  SizedBox(
                    width: 240,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: p,
                        minHeight: 5,
                        color: c.accent,
                        backgroundColor: c.surface2,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: Space.s16),
          // wraps onto two lines on a narrow screen or with large text
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: Space.s4,
            runSpacing: Space.s4,
            children: [
              IconButton(
                key: const Key('carousel-prev'),
                tooltip: 'Previous book',
                onPressed: _center > 0 ? () => _goTo(_center - 1) : null,
                icon: const Icon(Icons.chevron_left),
              ),
              OutlinedButton(
                key: const Key('carousel-more'),
                onPressed: () => widget.onMenu(b),
                child: const Text('More'),
              ),
              FilledButton.icon(
                key: const Key('carousel-read'),
                onPressed: () => widget.onOpen(b),
                icon: Icon(widget.selection != null ? Icons.check : Icons.auto_stories_outlined, size: 18),
                label: Text(widget.selection != null ? 'Select' : (started && !finished ? 'Continue' : 'Read')),
              ),
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

  static String _ago(int ms) {
    final d = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms));
    if (d.inMinutes < 2) return 'Read just now';
    if (d.inHours < 1) return 'Read ${d.inMinutes} min ago';
    if (d.inHours < 24) return 'Read ${d.inHours} h ago';
    if (d.inDays == 1) return 'Read yesterday';
    if (d.inDays < 30) return 'Read ${d.inDays} days ago';
    final m = (d.inDays / 30).floor();
    return m < 12 ? 'Read $m ${m == 1 ? 'month' : 'months'} ago' : 'Read over a year ago';
  }
}

/// The carousel on its own screen: a soft backdrop in the middle book's colour, bigger covers, Close at the top.
class _FullCarousel extends StatefulWidget {
  const _FullCarousel({
    required this.books,
    required this.start,
    required this.onOpen,
    required this.onMenu,
    required this.dotOf,
  });
  final List<BookRow> books;
  final int start;
  final void Function(BookRow) onOpen, onMenu;
  final Widget? Function(BookRow) dotOf;
  @override
  State<_FullCarousel> createState() => _FullCarouselState();
}

class _FullCarouselState extends State<_FullCarousel> {
  late int _index = widget.start;

  void _close() => Navigator.of(context).pop(_index);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        backgroundColor: c.bg,
        body: Stack(
          children: [
            // a wash of the middle book's colour behind everything
            Positioned.fill(
              child: _Backdrop(color: bookColor(widget.books[_index.clamp(0, widget.books.length - 1)]), base: c.bg),
            ),
            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Space.s8, Space.s4, Space.s8, 0),
                    child: Row(
                      children: [
                        IconButton(
                          key: const Key('carousel-close-full'),
                          tooltip: 'Close full screen',
                          icon: const Icon(Icons.close_fullscreen),
                          onPressed: _close,
                        ),
                        const Spacer(),
                      ],
                    ),
                  ),
                  Expanded(
                    child: CoverCarouselView(
                      books: widget.books,
                      onOpen: (b) {
                        Navigator.of(context).pop(_index);
                        widget.onOpen(b);
                      },
                      onMenu: (b) {
                        Navigator.of(context).pop(_index);
                        widget.onMenu(b);
                      },
                      dotOf: widget.dotOf,
                      selection: null,
                      fullscreen: true,
                      initialIndex: widget.start,
                      onCenter: (i) => setState(() => _index = i),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.color, required this.base});
  final Color color, base;
  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 450),
    decoration: BoxDecoration(
      gradient: RadialGradient(
        center: const Alignment(0, -.35),
        radius: 1.1,
        colors: [Color.lerp(base, color, .32)!, base],
      ),
    ),
  );
}
