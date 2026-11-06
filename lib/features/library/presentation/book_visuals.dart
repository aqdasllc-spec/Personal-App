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

/// A book spine for the realistic shelf.
class Spine extends StatelessWidget {
  const Spine({
    super.key,
    required this.book,
    required this.onTap,
    required this.onLongPress,
  });
  final BookRow book;
  final VoidCallback onTap, onLongPress;

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
              if (book.favorite == 1)
                Positioned(
                  top: 4,
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
  const CoverTile({super.key, required this.book, this.size = 56});
  final BookRow book;
  final double size;
  @override
  Widget build(BuildContext context) {
    final c = bookColor(book);
    return Container(
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
  }
}
