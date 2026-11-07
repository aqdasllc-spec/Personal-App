import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../data/local/app_database.dart';
import '../../../design_system/tokens.dart';
import 'book_visuals.dart';

/// Rearrange mode (the pen button): what the books need to know. Provided by the Library page.
class EditScope extends InheritedWidget {
  const EditScope({
    super.key,
    required this.editing,
    required this.canReorder,
    required this.onDrop,
    required this.onNudge,
    required this.selectedId,
    required this.onSelect,
    required this.onDragMove,
    required this.onDragEnd,
    required super.child,
  });

  final bool editing;

  /// False while a search or filter hides some books (reordering a partial list would be confusing).
  final bool canReorder;

  /// [dragged] was dropped on the book [target].
  final void Function(String dragged, String target) onDrop;

  /// Screen-reader / keyboard alternative: move a book one place earlier (-1) or later (+1).
  final void Function(String id, int delta) onNudge;

  /// The book picked (by tapping it) to be moved with the arrow buttons; null = none.
  final String? selectedId;
  final void Function(String id) onSelect;
  final void Function(Offset global) onDragMove;
  final VoidCallback onDragEnd;

  static EditScope? maybeOf(BuildContext c) =>
      c.dependOnInheritedWidgetOfExactType<EditScope>();

  @override
  bool updateShouldNotify(EditScope old) =>
      old.editing != editing ||
      old.canReorder != canReorder ||
      old.selectedId != selectedId;
}

/// A book in rearrange mode: it wiggles, can be dragged, and other books can be dropped on it.
class EditableBook extends StatelessWidget {
  const EditableBook({super.key, required this.book, required this.child});
  final BookRow book;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scope = EditScope.maybeOf(context);
    if (scope == null || !scope.editing) return child;
    final c = context.colors;
    final color = bookColor(book);
    final feedback = Material(
      elevation: 10,
      borderRadius: BorderRadius.circular(Radii.input),
      color: color,
      child: Container(
        width: 150,
        padding: const EdgeInsets.symmetric(
          horizontal: Space.s12,
          vertical: Space.s8,
        ),
        child: Text(
          book.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: onBookColor(color),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
    return Semantics(
      container: true,
      label: '${book.title}. Rearranging.',
      customSemanticsActions: {
        const CustomSemanticsAction(label: 'Move earlier'): () =>
            scope.onNudge(book.id, -1),
        const CustomSemanticsAction(label: 'Move later'): () =>
            scope.onNudge(book.id, 1),
      },
      child: DragTarget<String>(
        onWillAcceptWithDetails: (d) => scope.canReorder && d.data != book.id,
        onAcceptWithDetails: (d) => scope.onDrop(d.data, book.id),
        builder: (context, candidates, _) => Draggable<String>(
          key: Key('drag-book-${book.id}'),
          data: book.id,
          dragAnchorStrategy: pointerDragAnchorStrategy,
          feedback: feedback,
          childWhenDragging: Opacity(opacity: .3, child: child),
          onDragUpdate: (d) => scope.onDragMove(d.globalPosition),
          onDragEnd: (_) => scope.onDragEnd(),
          // a tap picks the book for the arrow buttons (it must not open); the drag still starts from here
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => scope.onSelect(book.id),
            child: AbsorbPointer(
              child: Wiggle(
                seed: book.id.hashCode,
                child: Container(
                  // an accent bar on the left shows where the dragged book will go
                  foregroundDecoration: candidates.isNotEmpty
                      ? BoxDecoration(
                          border: Border(
                            left: BorderSide(color: c.accent, width: 4),
                          ),
                        )
                      : (scope.selectedId == book.id
                            ? BoxDecoration(
                                border: Border.all(color: c.accent, width: 3),
                                borderRadius: BorderRadius.circular(
                                  Radii.input,
                                ),
                              )
                            : null),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The little "jiggle" of rearrange mode. Each book starts at a different moment so they do not move in lockstep.
/// With the system's reduce-motion setting on, nothing moves (the dragging still works).
class Wiggle extends StatefulWidget {
  const Wiggle({super.key, required this.child, required this.seed});
  final Widget child;
  final int seed;
  @override
  State<Wiggle> createState() => _WiggleState();
}

class _WiggleState extends State<Wiggle> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: 130 + (widget.seed.abs() % 40)),
  );

  @override
  void initState() {
    super.initState();
    _c.value = (widget.seed.abs() % 100) / 100; // different phase per book
    _c.repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      return widget.child;
    }
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) =>
          Transform.rotate(angle: (_c.value * 2 - 1) * 0.03, child: child),
      child: widget.child,
    );
  }
}
