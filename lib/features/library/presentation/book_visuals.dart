import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/app_database.dart';
import '../../../design_system/tokens.dart';
import '../application/covers.dart';
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

/// Height of the cloud status badge (1.5x the old dot).
const double cloudBadgeHeight = 21;

/// The cloud status badge: a rectangle across the top of the book, as wide as the book.
/// red "Sync" = only on this device, rotating arrows = syncing, green "Synced" = a copy is in the cloud.
/// Tap to change. On very narrow books it shows an icon instead of text.
class CloudDot extends StatefulWidget {
  const CloudDot({
    super.key,
    required this.book,
    required this.busy,
    required this.onTap,
  });
  final BookRow book;
  final bool busy;
  final VoidCallback onTap;
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
    return Semantics(
      key: Key('cloud-dot-${widget.book.id}'),
      container: true,
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // while syncing, swallow the tap (otherwise it would fall through and open the book)
        onTap: widget.busy ? () {} : widget.onTap,
        child: LayoutBuilder(
          builder: (context, box) {
            final wide = box.maxWidth >= 44;
            final Widget content;
            if (widget.busy) {
              content = Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  RotationTransition(
                    turns: _spin,
                    child: const Icon(
                      Icons.sync,
                      size: 13,
                      color: Colors.white,
                    ),
                  ),
                  if (wide) const SizedBox(width: 3),
                  if (wide) const _BadgeText('Syncing'),
                ],
              );
            } else if (wide) {
              content = _BadgeText(synced ? 'Synced' : 'Sync');
            } else {
              content = Icon(
                synced ? Icons.cloud_done : Icons.cloud_upload,
                size: 13,
                color: Colors.white,
              );
            }
            return Container(
              height: cloudBadgeHeight,
              width: double.infinity,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: color,
                border: const Border(
                  bottom: BorderSide(color: Color(0x55FFFFFF)),
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x44000000),
                    blurRadius: 2,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
              child: FittedBox(fit: BoxFit.scaleDown, child: content),
            );
          },
        ),
      ),
    );
  }
}

class _BadgeText extends StatelessWidget {
  const _BadgeText(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text,
    maxLines: 1,
    style: const TextStyle(
      color: Colors.white,
      fontSize: 10,
      fontWeight: FontWeight.w700,
      letterSpacing: .3,
    ),
  );
}

/// A book spine for the realistic shelf.
class Spine extends StatelessWidget {
  const Spine({
    super.key,
    required this.book,
    required this.onTap,
    this.onLongPress,
    this.dot,
    this.scale = 1,
  });
  final BookRow book;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// Size factor (the glass cabinets show books a little smaller).
  final double scale;

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
          width: spineWidth(book) * scale,
          height: spineHeight(book) * scale,
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
                  padding: EdgeInsets.fromLTRB(
                    4,
                    dot != null ? cloudBadgeHeight + 8 : 10,
                    4,
                    10,
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
                          fontSize: 13 * scale.clamp(.85, 1.0),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (dot != null)
                Positioned(top: 0, left: 0, right: 0, child: dot!),
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
class CoverTile extends ConsumerWidget {
  const CoverTile({super.key, required this.book, this.size = 56, this.dot});
  final BookRow book;
  final double size;

  /// Optional cloud status badge (across the top of the cover).
  final Widget? dot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = bookColor(book);
    final radius = BorderRadius.circular(Radii.input);
    final cover = ref.watch(coverBytesProvider(book.id)).value;
    final w = size * .75;
    final letter = Text(
      book.title.isEmpty ? '?' : book.title.characters.first.toUpperCase(),
      style: TextStyle(
        color: onBookColor(c),
        fontFamily: 'serif',
        fontSize: size * .38,
        fontWeight: FontWeight.w700,
      ),
    );
    final tile = Container(
      width: w,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c,
        borderRadius: radius,
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 4,
            offset: Offset(1, 2),
          ),
        ],
      ),
      // the real first page once it has been rendered, a coloured letter until then (or if it cannot be)
      child: cover == null
          ? letter
          : ClipRRect(
              borderRadius: radius,
              child: Image.memory(
                cover,
                key: Key('cover-${book.id}'),
                width: w,
                height: size,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                cacheWidth: (w * 2).round(),
                gaplessPlayback: true,
              ),
            ),
    );
    if (dot == null) return tile;
    return Stack(
      children: [
        tile,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: ClipRRect(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(Radii.input),
            ),
            child: dot!,
          ),
        ),
      ],
    );
  }
}
