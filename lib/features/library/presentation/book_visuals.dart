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

/// A book spine for the realistic shelf. With "Ribbons and dust" on (Settings), a ribbon runs down the spine as far as
/// you have read, books not opened for months gather dust, and finished books get gold bands.
class Spine extends ConsumerWidget {
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

  /// Optional cloud status dot, drawn in the top-right corner.
  final Widget? dot;

  /// Size factor (the glass cabinets show books a little smaller).
  final double scale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = bookColor(book);
    final fg = onBookColor(c);
    final progress = readingProgress(book);
    final looks = ref.watch(ribbonsProvider);
    final finished = progress >= .95;
    final dust = looks ? dustOf(book, DateTime.now()) : 0.0;
    final w = spineWidth(book) * scale, h = spineHeight(book) * scale;
    final brass = context.colors.brass;
    return Semantics(
      button: true,
      label: '${book.title}${book.author.isEmpty ? '' : ' by ${book.author}'}'
          '${finished ? ', finished' : (progress > 0 ? ', ${(progress * 100).round()}% read' : '')}',
      child: InkWell(
        key: Key('book-${book.id}'),
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
        child: Container(
          width: w,
          height: h,
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
              if (looks && finished) ...[
                Positioned(key: Key('gold-${book.id}'), top: 6 * scale, left: 3, right: 3, child: _Band(brass)),
                Positioned(top: 11 * scale, left: 3, right: 3, child: _Band(brass)),
                Positioned(bottom: 6 * scale, left: 3, right: 3, child: _Band(brass)),
              ],
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    4,
                    dot != null ? cloudBadgeHeight + 8 : (looks && finished ? 18 * scale : 10),
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
              // the ribbon: from the top of the spine down to how far you have read
              if (looks && progress > 0 && !finished)
                Positioned(
                  key: Key('ribbon-${book.id}'),
                  top: 0,
                  right: 3,
                  width: 6,
                  height: (h * progress).clamp(14.0, h - 4),
                  child: const CustomPaint(painter: _RibbonPainter()),
                ),
              if (dust > 0)
                Positioned.fill(
                  key: Key('dust-${book.id}'),
                  child: IgnorePointer(
                    child: CustomPaint(painter: _DustPainter(dust, book.id.hashCode)),
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
              if (progress > 0 && !looks)
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

class _Band extends StatelessWidget {
  const _Band(this.color);
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    height: 2,
    decoration: BoxDecoration(
      color: color,
      boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 1, offset: Offset(0, 1))],
    ),
  );
}

/// A silk ribbon with a notched end.
class _RibbonPainter extends CustomPainter {
  const _RibbonPainter();
  @override
  void paint(Canvas canvas, Size s) {
    final notch = s.width * .8;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(s.width, 0)
      ..lineTo(s.width, s.height)
      ..lineTo(s.width / 2, s.height - notch)
      ..lineTo(0, s.height)
      ..close();
    canvas.drawShadow(path, Colors.black, 1.5, false);
    canvas.drawPath(
      path,
      Paint()
        ..shader = const LinearGradient(colors: [Color(0xFFB02A2F), Color(0xFF7E1A20)])
            .createShader(Offset.zero & s),
    );
    canvas.drawLine(
      Offset(s.width * .3, 0),
      Offset(s.width * .3, s.height - notch),
      Paint()
        ..color = const Color(0x44FFFFFF)
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_RibbonPainter old) => false;
}

/// A grey veil, heavier at the top where dust settles, with a few specks (the same specks for a book every time).
class _DustPainter extends CustomPainter {
  _DustPainter(this.amount, this.seed);
  final double amount;
  final int seed;

  @override
  void paint(Canvas canvas, Size s) {
    final r = Offset.zero & s;
    canvas.drawRect(
      r,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFFD9D4C7).withValues(alpha: amount * 1.4),
            const Color(0xFFBDB7A8).withValues(alpha: amount * .7),
          ],
        ).createShader(r),
    );
    var x = seed & 0x7fffffff;
    int next() => x = (x * 1103515245 + 12345) & 0x7fffffff;
    final speck = Paint()..color = const Color(0xFFEDE8DC).withValues(alpha: (amount * 1.6).clamp(0, 1));
    final n = (amount * 70).round();
    for (var i = 0; i < n; i++) {
      final px = (next() % 1000) / 1000 * s.width;
      final py = (next() % 1000) / 1000 * s.height;
      canvas.drawCircle(Offset(px, py), .5 + (next() % 10) / 12, speck);
    }
  }

  @override
  bool shouldRepaint(_DustPainter old) => old.amount != amount || old.seed != seed;
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
