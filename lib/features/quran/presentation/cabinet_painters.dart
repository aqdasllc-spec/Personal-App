import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'quran_style.dart';

/// A faint lattice of eight-pointed stars, the classic Islamic geometric pattern, in gold on the velvet.
class StarLatticePainter extends CustomPainter {
  const StarLatticePainter({this.opacity = .07, this.cell = 34});
  final double opacity, cell;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = QuranColors.gold.withValues(alpha: opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = .8;
    for (var y = 0.0; y < size.height + cell; y += cell) {
      for (var x = 0.0; x < size.width + cell; x += cell) {
        _star(canvas, Offset(x, y), cell * .32, p);
      }
    }
  }

  static void _star(Canvas c, Offset o, double r, Paint p) {
    // two overlapping squares = an eight-pointed star (Rub el Hizb shape)
    for (final turn in [0.0, math.pi / 4]) {
      final path = Path();
      for (var i = 0; i < 4; i++) {
        final a = turn + i * math.pi / 2;
        final pt = o + Offset(math.cos(a), math.sin(a)) * r;
        i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
      }
      c.drawPath(path..close(), p);
    }
  }

  @override
  bool shouldRepaint(StarLatticePainter old) => old.opacity != opacity || old.cell != cell;
}

/// The arched glass niche (a mihrab shape) with a hanging lamp and the Quran resting on its stand (rehal).
/// [light] 0..1 turns the lamp on: a warm glow fills the niche and the Quran shines.
class NichePainter extends CustomPainter {
  NichePainter({required this.light, required this.lift, this.title = 'القرآن'});
  final double light, lift;
  final String title;

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final arch = _archPath(Rect.fromLTWH(2, 2, w - 4, h - 4));

    // the inside: dark velvet, lit from the lamp when on
    canvas.save();
    canvas.clipPath(arch);
    canvas.drawRect(
      Offset.zero & s,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0E4636), QuranColors.velvetDeep],
        ).createShader(Offset.zero & s),
    );
    if (light > 0) {
      final lampAt = Offset(w / 2, h * .2);
      canvas.drawCircle(
        lampAt,
        h * 1.1,
        Paint()
          ..shader = RadialGradient(
            colors: [
              QuranColors.lamp.withValues(alpha: .62 * light),
              QuranColors.lamp.withValues(alpha: .18 * light),
              Colors.transparent,
            ],
            stops: const [0, .45, 1],
          ).createShader(Rect.fromCircle(center: lampAt, radius: h * 1.1)),
      );
      // soft rays
      final ray = Paint()..color = QuranColors.lamp.withValues(alpha: .10 * light);
      for (var i = -2; i <= 2; i++) {
        final a = math.pi / 2 + i * .22;
        final path = Path()
          ..moveTo(lampAt.dx, lampAt.dy + 6)
          ..lineTo(lampAt.dx + math.cos(a - .05) * h, lampAt.dy + math.sin(a - .05) * h)
          ..lineTo(lampAt.dx + math.cos(a + .05) * h, lampAt.dy + math.sin(a + .05) * h)
          ..close();
        canvas.drawPath(path, ray);
      }
    }
    _lamp(canvas, Offset(w / 2, 0), h);
    _rehalAndBook(canvas, s);
    // glass: two diagonal reflections
    final glass = Paint()..color = Colors.white.withValues(alpha: .07);
    canvas.drawPath(
      Path()
        ..moveTo(w * .18, 0)
        ..lineTo(w * .34, 0)
        ..lineTo(w * .02, h * .55)
        ..lineTo(0, h * .45)
        ..close(),
      glass,
    );
    canvas.drawPath(
      Path()
        ..moveTo(w * .42, 0)
        ..lineTo(w * .47, 0)
        ..lineTo(w * .12, h * .62)
        ..lineTo(w * .08, h * .62)
        ..close(),
      glass,
    );
    canvas.restore();

    // gold frame around the arch
    canvas.drawPath(
      arch,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..shader = QuranColors.goldGradient.createShader(Offset.zero & s),
    );
    canvas.drawPath(
      _archPath(Rect.fromLTWH(6, 6, w - 12, h - 12)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .8
        ..color = QuranColors.gold.withValues(alpha: .55),
    );
  }

  /// A pointed arch over a rectangle.
  static Path _archPath(Rect r) {
    final shoulder = r.top + r.width * .55;
    return Path()
      ..moveTo(r.left, r.bottom)
      ..lineTo(r.left, shoulder)
      ..quadraticBezierTo(r.left, r.top + r.width * .12, r.center.dx, r.top)
      ..quadraticBezierTo(r.right, r.top + r.width * .12, r.right, shoulder)
      ..lineTo(r.right, r.bottom)
      ..close();
  }

  void _lamp(Canvas c, Offset top, double h) {
    final gold = Paint()..color = QuranColors.gold;
    final y0 = h * .05, y1 = h * .13;
    c.drawLine(top + Offset(0, y0), top + Offset(0, y1), Paint()
      ..color = QuranColors.gold.withValues(alpha: .8)
      ..strokeWidth = 1);
    final body = Path()
      ..moveTo(top.dx - 7, top.dy + y1 + 4)
      ..lineTo(top.dx + 7, top.dy + y1 + 4)
      ..lineTo(top.dx + 5, top.dy + y1 + 15)
      ..lineTo(top.dx - 5, top.dy + y1 + 15)
      ..close();
    c.drawPath(
      Path()
        ..moveTo(top.dx, top.dy + y1)
        ..lineTo(top.dx + 8, top.dy + y1 + 4)
        ..lineTo(top.dx - 8, top.dy + y1 + 4)
        ..close(),
      gold,
    );
    c.drawPath(body, Paint()..color = Color.lerp(const Color(0xFF6E5A23), QuranColors.lamp, light)!);
    c.drawPath(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = QuranColors.gold,
    );
    if (light > 0) {
      c.drawCircle(top + Offset(0, y1 + 10), 9 + 6 * light, Paint()
        ..color = QuranColors.lamp.withValues(alpha: .35 * light)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    }
  }

  void _rehalAndBook(Canvas c, Size s) {
    final w = s.width, h = s.height;
    final base = h * .9;
    // the stand: two crossed wooden boards with gold edges
    final wood = Paint()..color = const Color(0xFF6B3E1F);
    final edge = Paint()
      ..color = QuranColors.gold.withValues(alpha: .8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final cx = w / 2;
    final left = Path()
      ..moveTo(cx - w * .30, base)
      ..lineTo(cx - w * .24, base)
      ..lineTo(cx + w * .16, h * .64)
      ..lineTo(cx + w * .10, h * .64)
      ..close();
    final right = Path()
      ..moveTo(cx + w * .30, base)
      ..lineTo(cx + w * .24, base)
      ..lineTo(cx - w * .16, h * .64)
      ..lineTo(cx - w * .10, h * .64)
      ..close();
    for (final p in [left, right]) {
      c.drawPath(p, wood);
      c.drawPath(p, edge);
    }
    // the Quran, open-faced cover tilted on the stand, lifting a little when lit
    final bw = w * .52, bh = h * .34;
    final top = h * .36 - lift * 6;
    final book = RRect.fromRectAndRadius(Rect.fromLTWH(cx - bw / 2, top, bw, bh), const Radius.circular(3));
    if (light > 0) {
      c.drawRRect(
        book.inflate(4 + 4 * light),
        Paint()
          ..color = QuranColors.lamp.withValues(alpha: .45 * light)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
    }
    c.drawRRect(
      book,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF14704F), Color(0xFF0A4A33)],
        ).createShader(book.outerRect),
    );
    // spine shadow and gold border
    c.drawRect(Rect.fromLTWH(book.left, book.top, 4, bh), Paint()..color = Colors.black.withValues(alpha: .25));
    c.drawRRect(
      book.deflate(3),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..shader = QuranColors.goldGradient.createShader(book.outerRect),
    );
    // centre medallion with the title
    final mid = book.center;
    final r = bh * .36;
    final medallion = Path();
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4;
      final rr = i.isEven ? r : r * .82;
      final pt = mid + Offset(math.cos(a), math.sin(a)) * rr;
      i == 0 ? medallion.moveTo(pt.dx, pt.dy) : medallion.lineTo(pt.dx, pt.dy);
    }
    c.drawPath(
      medallion..close(),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = QuranColors.goldLight,
    );
    final tp = TextPainter(
      text: TextSpan(text: title, style: quranArabic(r * .9, color: QuranColors.goldLight).copyWith(height: 1)),
      textDirection: TextDirection.rtl,
    )..layout();
    tp.paint(c, mid - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(NichePainter old) => old.light != light || old.lift != lift || old.title != title;
}
