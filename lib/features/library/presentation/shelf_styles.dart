import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/app_database.dart';
import '../../../design_system/tokens.dart';
import '../application/covers.dart';
import '../application/library_controller.dart';
import 'book_peek.dart';
import 'book_visuals.dart';

// The two extra looks for the Library's Shelf view (Settings -> Library -> Shelf style):
//  * Turning books: tap a spine and the book turns to show its cover, with its details below; tap again to read.
//  * Glass cabinets: every shelf is a small glass cabinet; tap one and its doors swing open onto two rows of books.

const _turn = Duration(milliseconds: 320);
const _curve = Cubic(.2, .8, .2, 1);

/// Width of a book seen from the front (its cover), for a spine of height [h].
double coverWidthFor(double h) => (h * .68).roundToDouble();

/// A spine that can turn to show its cover. Tap handling is the caller's ([onTap]).
class TurnableBook extends ConsumerWidget {
  const TurnableBook({
    super.key,
    required this.book,
    required this.turned,
    required this.onTap,
    this.scale = 1,
    this.dot,
  });
  final BookRow book;
  final bool turned;
  final VoidCallback onTap;
  final double scale;
  final Widget? dot;

  static double widthOf(BookRow b, {required bool turned, double scale = 1}) =>
      turned ? coverWidthFor(spineHeight(b) * scale) : spineWidth(b) * scale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = spineHeight(book) * scale;
    final sw = spineWidth(book) * scale, cw = coverWidthFor(h);
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final d = reduce ? Duration.zero : _turn;
    return AnimatedContainer(
      duration: d,
      curve: _curve,
      width: turned ? cw : sw,
      height: h,
      transform: Matrix4.translationValues(0, turned ? -6 : 0, 0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(3),
        boxShadow: turned
            ? const [BoxShadow(color: Color(0x55000000), blurRadius: 14, offset: Offset(0, 8))]
            : const [],
      ),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: sw,
            child: AnimatedOpacity(
              duration: d,
              opacity: turned ? 0 : 1,
              child: Spine(book: book, onTap: onTap, dot: dot, scale: scale),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: cw,
            child: IgnorePointer(
              ignoring: !turned,
              child: AnimatedOpacity(
                duration: d,
                opacity: turned ? 1 : 0,
                child: _CoverFace(book: book, onTap: onTap, width: cw, height: h),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CoverFace extends ConsumerWidget {
  const _CoverFace({required this.book, required this.onTap, required this.width, required this.height});
  final BookRow book;
  final VoidCallback onTap;
  final double width, height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = bookColor(book);
    final fg = onBookColor(c);
    final cover = ref.watch(coverBytesProvider(book.id)).value;
    return Semantics(
      button: true,
      label: 'Read ${book.title}',
      child: GestureDetector(
        key: Key('cover-face-${book.id}'),
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color.lerp(c, Colors.white, .12)!, Color.lerp(c, Colors.black, .2)!],
                  ),
                ),
                child: cover != null
                    ? Image.memory(
                        cover,
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                        cacheWidth: (width * 2.5).round(),
                        gaplessPlayback: true,
                      )
                    : Padding(
                        padding: const EdgeInsets.fromLTRB(8, 12, 8, 26),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              book.title,
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: fg,
                                fontFamily: 'serif',
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                height: 1.2,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(width: 24, height: 2, color: context.colors.brass),
                            const Spacer(),
                            if (book.author.isNotEmpty)
                              Text(
                                book.author,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: fg.withValues(alpha: .85), fontSize: 10),
                              ),
                          ],
                        ),
                      ),
              ),
              // the spine edge, so it still reads as a book
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 5,
                child: ColoredBox(color: Colors.black.withValues(alpha: .18)),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  color: Colors.black.withValues(alpha: .45),
                  child: const Text(
                    'Tap to read',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Details of the turned book: progress and Read / More / Put back.
class TurnedBookCard extends StatelessWidget {
  const TurnedBookCard({
    super.key,
    required this.book,
    required this.onRead,
    required this.onMore,
    required this.onPutBack,
  });
  final BookRow book;
  final VoidCallback onRead, onMore, onPutBack;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final p = readingProgress(book);
    final started = book.lastPage > 0;
    return Container(
      key: Key('turned-card-${book.id}'),
      padding: const EdgeInsets.all(Space.s12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: c.border),
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 18, offset: Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CoverTile(book: book, size: 64),
              const SizedBox(width: Space.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      book.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: t.titleMedium?.copyWith(fontFamily: 'serif'),
                    ),
                    if (book.author.isNotEmpty)
                      Text(book.author, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodySmall),
                    const SizedBox(height: Space.s4),
                    Text(
                      started
                          ? 'Page ${book.lastPage} of ${book.pageCount} · ${(p * 100).round()}%'
                          : (book.pageCount > 0 ? '${book.pageCount} pages · not started' : 'Not started'),
                      style: t.bodySmall,
                    ),
                    if (started) ...[
                      const SizedBox(height: Space.s4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: p,
                          minHeight: 4,
                          color: c.accent,
                          backgroundColor: c.surface2,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.s12),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: Space.s8,
            runSpacing: Space.s8,
            children: [
              TextButton(key: const Key('turned-back'), onPressed: onPutBack, child: const Text('Put back')),
              OutlinedButton(key: const Key('turned-more'), onPressed: onMore, child: const Text('More')),
              FilledButton(
                key: const Key('turned-read'),
                onPressed: onRead,
                child: Text(started ? 'Continue' : 'Read'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// [child] with the turned book's card floating at the bottom (always on screen, slides in and out).
class _WithFloatingCard extends StatelessWidget {
  const _WithFloatingCard({required this.child, required this.card});
  final Widget child;
  final Widget? card;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Stack(
      children: [
        Positioned.fill(child: child),
        Positioned(
          left: Space.s12,
          right: Space.s12,
          bottom: Space.s12,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: AnimatedSwitcher(
                duration: reduce ? Duration.zero : _turn,
                switchInCurve: _curve,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (c, a) => SlideTransition(
                  position: Tween(begin: const Offset(0, .4), end: Offset.zero).animate(a),
                  child: FadeTransition(opacity: a, child: c),
                ),
                child: card ?? const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Room under the last books so the floating card does not hide them.
const _cardRoom = 190.0;

/// Shared tap rule: in selection mode a tap selects; otherwise the first tap turns the book, the second opens it.
mixin _Turning<T extends StatefulWidget> on State<T> {
  String? turned;

  void tapBook(BookRow b, {required Set<String>? selection, required void Function(BookRow) onOpen}) {
    if (selection != null) {
      onOpen(b); // selection mode: the page's own callback toggles the tick
      return;
    }
    if (turned == b.id) {
      setState(() => turned = null);
      onOpen(b);
    } else {
      setState(() => turned = b.id);
    }
  }

  /// The turned book, if it is still in [books].
  BookRow? turnedIn(List<BookRow> books) => turned == null ? null : books.where((b) => b.id == turned).firstOrNull;
}

/// Style "Turning books": open shelves like the classic view, but a tapped book turns to show its cover.
class TurningShelfView extends StatefulWidget {
  const TurningShelfView({
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
  State<TurningShelfView> createState() => _TurningShelfViewState();
}

class _TurningShelfViewState extends State<TurningShelfView> with _Turning<TurningShelfView> {
  @override
  Widget build(BuildContext context) {
    final t = turnedIn(widget.books);
    return LayoutBuilder(
      builder: (context, box) {
        final avail = box.maxWidth - Space.s32;
        final rows = <List<BookRow>>[[]];
        var used = 0.0;
        for (final b in widget.books) {
          final w = TurnableBook.widthOf(b, turned: b.id == t?.id) + 3;
          if (used + w > avail && rows.last.isNotEmpty) {
            rows.add([]);
            used = 0;
          }
          rows.last.add(b);
          used += w;
        }
        return _WithFloatingCard(
          card: _cardFor(t),
          child: ListView.builder(
            key: const Key('turning-shelf'),
            padding: EdgeInsets.fromLTRB(Space.s16, Space.s16, Space.s16, t == null ? Space.s16 : _cardRoom),
            itemCount: rows.length,
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.only(bottom: Space.s24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 206,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [for (final b in rows[i]) _book(b, t)],
                    ),
                  ),
                  const ShelfLedge(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget? _cardFor(BookRow? t) => t == null
      ? null
      : TurnedBookCard(
          key: ValueKey('card-${t.id}'),
          book: t,
          onRead: () => tapBook(t, selection: null, onOpen: widget.onOpen),
          onMore: () => widget.onMenu(t),
          onPutBack: () => setState(() => turned = null),
        );

  Widget _book(BookRow b, BookRow? t) => Padding(
    padding: const EdgeInsets.only(right: 3),
    child: BookPeekTarget(
      book: b,
      onOpen: () => widget.onOpen(b),
      onMore: () => widget.onMenu(b),
      selected: widget.selection?.contains(b.id),
      child: TurnableBook(
        book: b,
        turned: widget.selection == null && b.id == t?.id,
        dot: widget.dotOf(b),
        onTap: () => tapBook(b, selection: widget.selection, onOpen: widget.onOpen),
      ),
    ),
  );
}

/// The board a row of books stands on.
class ShelfLedge extends StatelessWidget {
  const ShelfLedge({super.key, this.height = 10});
  final double height;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: c.surface2,
        border: Border(
          top: BorderSide(color: c.border),
          bottom: BorderSide(color: c.border),
        ),
        boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 6, offset: Offset(0, 3))],
      ),
    );
  }
}

// ---------------------------------------------------------------- glass cabinets

/// Colours of a cabinet, from the app's theme so it fits light and dark.
class _CabinetLook {
  _CabinetLook(BuildContext context) {
    final c = context.colors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    frame = Color.lerp(c.surface2, c.brass, dark ? .14 : .2)!;
    edge = Color.lerp(frame, c.text, .16)!;
    back = Color.lerp(c.bg, c.surface2, dark ? .3 : .7)!;
    ledge = Color.lerp(frame, c.text, .06)!;
    glass = dark ? const Color(0x2978A596) : const Color(0x55CDE4DC);
    glint = dark ? const Color(0x33FFFFFF) : const Color(0x9EFFFFFF);
    glintSoft = dark ? const Color(0x12FFFFFF) : const Color(0x38FFFFFF);
    knob = c.brass;
  }
  late final Color frame, edge, back, ledge, glass, glint, glintSoft, knob;
}

/// A glass cabinet: frame, a back wall with two shelves, and two glass doors that swing open.
/// [open] animates the doors; [rows] are the two shelves' contents (already built).
class GlassCabinet extends StatefulWidget {
  const GlassCabinet({
    super.key,
    required this.open,
    required this.rows,
    required this.rowHeight,
    this.onOpenDoors,
    this.small = false,
  });
  final bool open;
  final List<Widget> rows;
  final double rowHeight;
  final VoidCallback? onOpenDoors;

  /// The mini version on the wall (thinner frame, no door hint).
  final bool small;

  @override
  State<GlassCabinet> createState() => _GlassCabinetState();
}

class _GlassCabinetState extends State<GlassCabinet> with SingleTickerProviderStateMixin {
  late final AnimationController _doors = AnimationController(vsync: this, duration: const Duration(milliseconds: 620));

  @override
  void initState() {
    super.initState();
    if (widget.open) {
      // swing open just after the cabinet appears
      Future.delayed(const Duration(milliseconds: 140), () {
        if (mounted) _go(true);
      });
    }
  }

  @override
  void didUpdateWidget(GlassCabinet old) {
    super.didUpdateWidget(old);
    if (old.open != widget.open) _go(widget.open);
  }

  void _go(bool open) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) {
      _doors.value = open ? 1 : 0;
    } else {
      open ? _doors.forward() : _doors.reverse();
    }
  }

  @override
  void dispose() {
    _doors.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final look = _CabinetLook(context);
    final frameW = widget.small ? 5.0 : 9.0;
    final door = widget.small ? 3.0 : 5.0;
    final inside = Container(
      decoration: BoxDecoration(
        color: look.back,
        borderRadius: BorderRadius.circular(3),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .18), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      padding: EdgeInsets.only(top: widget.small ? 3 : 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final r in widget.rows) ...[
            SizedBox(height: widget.rowHeight, child: r),
            Container(height: widget.small ? 3 : 9, color: look.ledge),
            if (!widget.small) const SizedBox(height: 6),
          ],
        ],
      ),
    );
    return Container(
      decoration: BoxDecoration(
        color: look.frame,
        borderRadius: BorderRadius.circular(widget.small ? 7 : 10),
        border: Border.all(color: look.edge),
        boxShadow: const [BoxShadow(color: Color(0x29000000), blurRadius: 14, offset: Offset(0, 6))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: widget.small ? 4 : 7,
            decoration: BoxDecoration(
              color: look.edge,
              borderRadius: BorderRadius.vertical(top: Radius.circular(widget.small ? 6 : 9)),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(frameW, frameW - 2, frameW, frameW),
            child: Stack(
              children: [
                inside,
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _doors,
                    builder: (context, _) {
                      final v = Curves.easeInOutCubic.transform(_doors.value);
                      if (v >= 1) return const SizedBox.shrink();
                      final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
                      Widget leaf(bool left) {
                        final pane = _GlassPane(look: look, border: door, knobOnRight: left, small: widget.small);
                        if (reduce) return Opacity(opacity: 1 - v, child: pane);
                        final angle = v * 1.82 * (left ? -1 : 1); // about 104 degrees
                        return Transform(
                          alignment: left ? Alignment.centerLeft : Alignment.centerRight,
                          transform: Matrix4.identity()
                            ..setEntry(3, 2, .0014)
                            ..rotateY(angle),
                          child: pane,
                        );
                      }

                      return IgnorePointer(
                        ignoring: v > 0 || widget.onOpenDoors == null,
                        child: GestureDetector(
                          key: const Key('cabinet-doors'),
                          behavior: HitTestBehavior.opaque,
                          onTap: widget.onOpenDoors,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: leaf(true)),
                              Expanded(child: leaf(false)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassPane extends StatelessWidget {
  const _GlassPane({required this.look, required this.border, required this.knobOnRight, required this.small});
  final _CabinetLook look;
  final double border;
  final bool knobOnRight, small;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      border: Border.all(color: look.frame, width: border),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        // a tinted pane with two light streaks (a drawn reflection: a real blur would stutter on cheaper phones)
        colors: [
          look.glass,
          look.glass,
          look.glint,
          look.glint,
          look.glass,
          look.glass,
          look.glintSoft,
          look.glintSoft,
          look.glass,
        ],
        stops: const [0, .14, .14, .19, .19, .27, .27, .30, .30],
      ),
    ),
    child: Align(
      alignment: knobOnRight ? const Alignment(.86, 0) : const Alignment(-.86, 0),
      child: Container(
        width: small ? 3 : 5,
        height: small ? 12 : 24,
        decoration: BoxDecoration(
          color: look.knob,
          borderRadius: BorderRadius.circular(3),
          boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 2, offset: Offset(0, 1))],
        ),
      ),
    ),
  );
}

/// One cabinet on the wall: closed, with small book shapes behind the glass, its name and count below.
class _MiniCabinet extends StatelessWidget {
  const _MiniCabinet({required this.name, required this.books, required this.onTap, required this.tileKey});
  final String name;
  final List<BookRow> books;
  final VoidCallback onTap;
  final Key tileKey;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: 'Open $name, ${books.length} ${books.length == 1 ? 'book' : 'books'}',
      excludeSemantics: true,
      child: InkWell(
        key: tileKey,
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.card),
        child: Padding(
          padding: const EdgeInsets.all(Space.s4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              LayoutBuilder(
                builder: (context, box) {
                  final avail = box.maxWidth - 16;
                  const k = .3;
                  final rows = <List<BookRow>>[[], []];
                  var r = 0;
                  var used = 0.0;
                  for (final b in books) {
                    final w = spineWidth(b) * k + 2;
                    if (used + w > avail) {
                      if (r == 1) break;
                      r = 1;
                      used = 0;
                    }
                    rows[r].add(b);
                    used += w;
                  }
                  Widget row(List<BookRow> bs) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final b in bs)
                          Container(
                            margin: const EdgeInsets.only(right: 2),
                            width: spineWidth(b) * k,
                            height: spineHeight(b) * k,
                            decoration: BoxDecoration(color: bookColor(b), borderRadius: BorderRadius.circular(1)),
                          ),
                      ],
                    ),
                  );
                  return GlassCabinet(open: false, small: true, rowHeight: 58, rows: [row(rows[0]), row(rows[1])]);
                },
              ),
              const SizedBox(height: Space.s8),
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleSmall),
              Text('${books.length} ${books.length == 1 ? 'book' : 'books'}', style: t.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

/// Style "Glass cabinets". With no shelf chosen: "Continue reading" and a wall of closed cabinets (one per shelf,
/// plus "Unsorted"). With a shelf chosen (tap a cabinet, or its chip): that cabinet, doors swinging open.
class CabinetWallView extends StatefulWidget {
  const CabinetWallView({
    super.key,
    required this.allBooks,
    required this.books,
    required this.shelves,
    required this.filter,
    required this.onPick,
    required this.onOpen,
    required this.onMenu,
    required this.dotOf,
    required this.selection,
  });

  /// Everything in the library (for the counts on the wall) and what the current filter shows (inside a cabinet).
  final List<BookRow> allBooks, books;
  final List<ShelfRow> shelves;
  final LibraryFilter filter;

  /// Choose a cabinet (ShelfFilter / NoShelf) or go back to the wall (AllBooks).
  final void Function(LibraryFilter) onPick;
  final void Function(BookRow) onOpen, onMenu;
  final Widget? Function(BookRow) dotOf;
  final Set<String>? selection;

  @override
  State<CabinetWallView> createState() => _CabinetWallViewState();
}

class _CabinetWallViewState extends State<CabinetWallView> with _Turning<CabinetWallView> {
  @override
  void didUpdateWidget(CabinetWallView old) {
    super.didUpdateWidget(old);
    if (old.filter != widget.filter) turned = null;
  }

  bool get _inside => widget.filter is ShelfFilter || widget.filter is NoShelf;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // the phone's Back closes the cabinet instead of leaving the Library
      canPop: !_inside,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _inside) widget.onPick(const AllBooks());
      },
      child: _WithFloatingCard(
        card: _cardFor(),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 320),
          switchInCurve: _curve,
          transitionBuilder: (child, a) => FadeTransition(
            opacity: a,
            child: ScaleTransition(scale: Tween(begin: .94, end: 1.0).animate(a), child: child),
          ),
          child: _inside ? _cabinet(context) : _wall(context),
        ),
      ),
    );
  }

  Widget? _cardFor() {
    final tb = turnedIn(_inside ? widget.books : readingBooks(widget.allBooks, mine: false, limit: 10));
    return tb == null
        ? null
        : TurnedBookCard(
            key: ValueKey('card-${tb.id}'),
            book: tb,
            onRead: () => tapBook(tb, selection: null, onOpen: widget.onOpen),
            onMore: () => widget.onMenu(tb),
            onPutBack: () => setState(() => turned = null),
          );
  }

  Widget _wall(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final unsorted = widget.allBooks.where((b) => b.shelfId == null).toList();
    final reading = readingBooks(widget.allBooks, mine: false, limit: 10);
    final cabinets = <(Key, String, List<BookRow>, LibraryFilter)>[
      for (final s in widget.shelves)
        (Key('cabinet-${s.id}'), s.name, widget.allBooks.where((b) => b.shelfId == s.id).toList(), ShelfFilter(s.id)),
      if (unsorted.isNotEmpty || widget.shelves.isEmpty)
        (const Key('cabinet-unsorted'), 'Unsorted', unsorted, const NoShelf()),
    ];
    final tb = turnedIn(reading);
    return ListView(
      key: const ValueKey('cabinet-wall'),
      padding: EdgeInsets.fromLTRB(Space.s16, Space.s16, Space.s16, tb == null ? Space.s16 : _cardRoom),
      children: [
        if (reading.isNotEmpty) ...[
          Text('Continue reading', style: t.titleSmall),
          const SizedBox(height: Space.s8),
          SizedBox(
            height: 176,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final b in reading)
                  Padding(
                    padding: const EdgeInsets.only(right: 3, top: 8),
                    child: Align(alignment: Alignment.bottomCenter, child: _book(b, tb, .85)),
                  ),
              ],
            ),
          ),
          const ShelfLedge(height: 8),
          const SizedBox(height: Space.s24),
        ],
        Text('Cabinets', style: t.titleSmall),
        const SizedBox(height: Space.s8),
        LayoutBuilder(
          builder: (context, box) {
            final cols = math.max(2, (box.maxWidth / 220).floor());
            final w = (box.maxWidth - (cols - 1) * Space.s12) / cols;
            return Wrap(
              spacing: Space.s12,
              runSpacing: Space.s16,
              children: [
                for (final (key, name, books, f) in cabinets)
                  SizedBox(
                    width: w,
                    child: _MiniCabinet(tileKey: key, name: name, books: books, onTap: () => widget.onPick(f)),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: Space.s16),
        Text(
          'Tap a cabinet to open it. Shelves are made with the + next to the shelf names above.',
          style: t.bodySmall,
        ),
      ],
    );
  }

  Widget _cabinet(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final f = widget.filter;
    final name = f is ShelfFilter
        ? (widget.shelves.where((s) => s.id == f.shelfId).firstOrNull?.name ?? 'Shelf')
        : 'Unsorted';
    final books = widget.books;
    final tb = turnedIn(books);
    const scale = .8;
    return ListView(
      key: ValueKey('cabinet-open-$name'),
      padding: EdgeInsets.fromLTRB(Space.s16, Space.s16, Space.s16, tb == null ? Space.s16 : _cardRoom),
      children: [
        Row(
          children: [
            TextButton.icon(
              key: const Key('cabinet-back'),
              onPressed: () => widget.onPick(const AllBooks()),
              icon: const Icon(Icons.chevron_left),
              label: const Text('All cabinets'),
            ),
            const Spacer(),
            Text('${books.length} ${books.length == 1 ? 'book' : 'books'}', style: t.bodySmall),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.s4, 0, Space.s4, Space.s12),
          child: Text(name, style: t.headlineSmall?.copyWith(fontFamily: 'serif')),
        ),
        LayoutBuilder(
          builder: (context, box) {
            final avail = box.maxWidth - 2 * 9 - 16; // frame + inner padding
            final rows = _twoRows(books, avail, tb?.id, scale);
            Widget row(List<BookRow> bs) => ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: bs.length,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.only(right: 3, top: 10),
                child: Align(alignment: Alignment.bottomCenter, child: _book(bs[i], tb, scale)),
              ),
            );
            return GlassCabinet(
              key: ValueKey('glass-$name'),
              open: true,
              rowHeight: 166,
              rows: [row(rows.$1), row(rows.$2)],
            );
          },
        ),
        if (books.isEmpty) ...[
          const SizedBox(height: Space.s12),
          Text('This cabinet is empty. Open a book\'s menu and choose this shelf to put it here.', style: t.bodySmall),
        ],
        if (books.length > 6) ...[
          const SizedBox(height: Space.s8),
          Text('Swipe a row sideways for more.', style: t.bodySmall),
        ],
      ],
    );
  }

  /// Top row first; if the books need more than two widths, they are split evenly and both rows scroll sideways.
  (List<BookRow>, List<BookRow>) _twoRows(List<BookRow> books, double avail, String? turnedId, double scale) {
    double w(BookRow b) => TurnableBook.widthOf(b, turned: b.id == turnedId, scale: scale) + 3;
    final total = books.fold<double>(0, (s, b) => s + w(b));
    if (total > 2 * avail) {
      final half = (books.length / 2).ceil();
      return (books.sublist(0, half), books.sublist(half));
    }
    var used = 0.0;
    var n = 0;
    while (n < books.length && used + w(books[n]) <= avail) {
      used += w(books[n]);
      n++;
    }
    return (books.sublist(0, n), books.sublist(n));
  }

  Widget _book(BookRow b, BookRow? tb, double scale) => BookPeekTarget(
    book: b,
    onOpen: () => widget.onOpen(b),
    onMore: () => widget.onMenu(b),
    selected: widget.selection?.contains(b.id),
    child: TurnableBook(
      book: b,
      scale: scale,
      turned: widget.selection == null && b.id == tb?.id,
      dot: widget.dotOf(b),
      onTap: () => tapBook(b, selection: widget.selection, onOpen: widget.onOpen),
    ),
  );
}
