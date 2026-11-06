import 'package:flutter/material.dart';

import '../../../data/local/app_database.dart';
import '../../../design_system/tokens.dart';
import '../application/library_controller.dart';

const _spinePalette = <Color>[
  Color(0xFF2F5D50),
  Color(0xFF7A3B2E),
  Color(0xFF2E4A6B),
  Color(0xFF8A6A2A),
  Color(0xFF55406B),
  Color(0xFF3F4A3A),
  Color(0xFF8C4F5E),
  Color(0xFF30606B),
  Color(0xFF5E4B3A),
  Color(0xFF6B3B3B),
];

int _h(String s) {
  var h = 17;
  for (final c in s.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return h;
}

Color bookColor(BookRow b) => _spinePalette[_h(b.id) % _spinePalette.length];
Color onBookColor(Color c) =>
    ThemeData.estimateBrightnessForColor(c) == Brightness.dark
    ? const Color(0xFFF6F2EA)
    : const Color(0xFF1F1B16);

/// Spine size: thicker for longer books, slightly varied heights so a shelf looks real.
double spineWidth(BookRow b) =>
    (26 + b.pageCount / 10).clamp(28, 62).toDouble();
double spineHeight(BookRow b) => 150 + (_h(b.id) % 5) * 9.0;

/// The small status dot in a book's top-right corner:
/// red = only on this device, rotating arrows = syncing, green = a copy is in the cloud. Tap to change.
class CloudDot extends StatefulWidget {
  const CloudDot({
    super.key,
    required this.book,
    required this.busy,
    required this.onTap,
    this.size = 14,
  });
  final BookRow book;
  final bool busy;
  final VoidCallback onTap;
  final double size;
  @override
  State<CloudDot> createState() => _CloudDotState();
}

class _CloudDotState extends State<CloudDot>
    with SingleTickerProviderStateMixin {
  late final _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.busy) _spin.repeat();
  }

  @override
  void didUpdateWidget(CloudDot old) {
    super.didUpdateWidget(old);
    if (widget.busy && !_spin.isAnimating) _spin.repeat();
    if (!widget.busy && _spin.isAnimating) _spin.stop();
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final synced = widget.book.cloudState == 'synced';
    final color = widget.busy ? c.brass : (synced ? c.ok : c.danger);
    final label = widget.busy
        ? 'Syncing'
        : (synced
              ? 'Synced to cloud. Tap to remove the cloud copy'
              : 'Only on this device. Tap to sync to cloud');
    final s = widget.size;
    return Semantics(
      key: Key('cloud-dot-${widget.book.id}'),
      container: true,
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.busy ? null : widget.onTap,
        // a larger invisible hit area around the small dot (min ~32dp touch target)
        child: Padding(
          padding: const EdgeInsets.all(9),
          child: Container(
            width: s,
            height: s,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1.5),
              boxShadow: const [
                BoxShadow(color: Color(0x55000000), blurRadius: 2),
              ],
            ),
            child: widget.busy
                ? RotationTransition(
                    turns: _spin,
                    child: Icon(Icons.sync, size: s - 4, color: Colors.white),
                  )
                : null,
          ),
        ),
      ),
    );
  }
}

/// A book spine for the realistic shelf.
class Spine extends StatelessWidget {
  const Spine({
    super.key,
    required this.book,
    required this.onTap,
    this.onLongPress,
    this.dot,
  });
  final BookRow book;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// Optional cloud status dot, drawn in the top-right corner.
  final Widget? dot;

  @override
  Widget build(BuildContext context) {
    final c = bookColor(book);
    final fg = onBookColor(c);
    final progress = readingProgress(book);
    return Semantics(
      button: true,
      label: '${book.title}${book.author.isEmpty ? '' : ' by ${book.author}'}',
      child: InkWell(
        key: Key('book-${book.id}'),
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
        child: Container(
          width: spineWidth(book),
          height: spineHeight(book),
          decoration: BoxDecoration(
            color: c,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 3,
                offset: Offset(1, 0),
              ),
            ],
            gradient: LinearGradient(
              colors: [c, Color.lerp(c, Colors.black, .18)!],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 4,
                  ),
                  child: RotatedBox(
                    quarterTurns: 1,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        book.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: fg,
                          fontFamily: 'serif',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (dot != null) Positioned(top: -5, right: -5, child: dot!),
              if (book.favorite == 1)
                Positioned(
                  bottom: 8,
                  left: 0,
                  right: 0,
                  child: Icon(
                    Icons.star,
                    size: 12,
                    color: context.colors.brass,
                  ),
                ),
              if (progress > 0)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 3,
                    color: fg.withValues(alpha: .8),
                    backgroundColor: Colors.transparent,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small cover-like tile (grid and list use it).
class CoverTile extends StatelessWidget {
  const CoverTile({super.key, required this.book, this.size = 56, this.dot});
  final BookRow book;
  final double size;

  /// Optional cloud status dot (top-right corner).
  final Widget? dot;
  @override
  Widget build(BuildContext context) {
    final c = bookColor(book);
    final tile = Container(
      width: size * .75,
      height: size,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c,
        borderRadius: BorderRadius.circular(Radii.input),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 4,
            offset: Offset(1, 2),
          ),
        ],
      ),
      child: Text(
        book.title.isEmpty ? '?' : book.title.characters.first.toUpperCase(),
        style: TextStyle(
          color: onBookColor(c),
          fontFamily: 'serif',
          fontSize: size * .38,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    if (dot == null) return tile;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        tile,
        Positioned(top: -5, right: -5, child: dot!),
      ],
    );
  }
}
