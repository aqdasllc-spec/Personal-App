import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../../design_system/tokens.dart';
import '../presentation/cabinet_painters.dart';
import '../presentation/quran_style.dart';
import 'prayer.dart';
import 'prayer_providers.dart';

/// The way the top of the phone points: degrees clockwise from magnetic north, and how strong the magnetic field is
/// (in microtesla; far from 25-65 means the compass needs calibrating or something metal is near).
typedef Heading = ({double degrees, double field});

/// Works out the heading from the accelerometer (which way is down) and the magnetometer, tilt-compensated
/// (the same arithmetic as Android's SensorManager.getRotationMatrix / getOrientation).
double? headingFrom(List<double> g, List<double> m) {
  final ax = g[0], ay = g[1], az = g[2], ex = m[0], ey = m[1], ez = m[2];
  var hx = ey * az - ez * ay, hy = ez * ax - ex * az, hz = ex * ay - ey * ax;
  final normH = math.sqrt(hx * hx + hy * hy + hz * hz);
  final normA = math.sqrt(ax * ax + ay * ay + az * az);
  if (normH < .1 || normA < .1) return null; // in free fall, or next to a magnet
  hx /= normH;
  hy /= normH;
  hz /= normH;
  final nx = ax / normA, nz = az / normA;
  final my = nz * hx - nx * hz;
  final deg = math.atan2(hy, my) * 180 / math.pi;
  return (deg + 360) % 360;
}

/// The compass: a stream of headings (tests give their own).
final headingStreamProvider = Provider<Stream<Heading>?>((_) {
  if (kIsWeb || (defaultTargetPlatform != TargetPlatform.android && defaultTargetPlatform != TargetPlatform.iOS)) return null;
  final out = StreamController<Heading>();
  List<double>? g;
  StreamSubscription<AccelerometerEvent>? a;
  StreamSubscription<MagnetometerEvent>? m;
  out.onListen = () {
    a = accelerometerEventStream(samplingPeriod: SensorInterval.uiInterval).listen((e) => g = [e.x, e.y, e.z], onError: out.addError);
    m = magnetometerEventStream(samplingPeriod: SensorInterval.uiInterval).listen((e) {
      final gg = g;
      if (gg == null) return;
      final h = headingFrom(gg, [e.x, e.y, e.z]);
      if (h != null) out.add((degrees: h, field: math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z)));
    }, onError: out.addError);
  };
  out.onCancel = () {
    a?.cancel();
    m?.cancel();
  };
  return out.stream;
});

/// How far true north is from magnetic north here (degrees, east positive), from the phone's model of the Earth's field.
final declinationProvider = FutureProvider.family<double, (double, double)>((ref, at) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return 0;
  try {
    return await const MethodChannel('folio/battery').invokeMethod<double>('declination', {'lat': at.$1, 'lng': at.$2}) ?? 0;
  } catch (_) {
    return 0;
  }
});

String compassPoint(double deg) {
  const names = ['N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE', 'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW'];
  return names[((deg % 360) / 22.5).round() % 16];
}

class QiblaPage extends ConsumerStatefulWidget {
  const QiblaPage({super.key});
  @override
  ConsumerState<QiblaPage> createState() => _QiblaPageState();
}

class _QiblaPageState extends ConsumerState<QiblaPage> {
  StreamSubscription<Heading>? _sub;
  double? _heading; // smoothed, true north
  double _field = 45;
  bool _noSensor = false;
  bool _wasFacing = false;

  @override
  void initState() {
    super.initState();
    final stream = ref.read(headingStreamProvider);
    if (stream == null) {
      _noSensor = true;
      return;
    }
    _sub = stream.listen((h) {
      final s = ref.read(prayerSettingsProvider);
      final decl = s.hasLocation ? (ref.read(declinationProvider((s.lat!, s.lng!))).value ?? 0) : 0;
      final trueDeg = (h.degrees + decl + 360) % 360;
      final prev = _heading;
      // smooth the needle, going the short way round
      final next = prev == null ? trueDeg : (prev + _shortest(prev, trueDeg) * .2 + 360) % 360;
      if (mounted) {
        setState(() {
          _heading = next;
          _field = h.field;
        });
      }
    }, onError: (Object _) {
      if (mounted) setState(() => _noSensor = true);
    });
  }

  static double _shortest(double from, double to) => ((to - from + 540) % 360) - 180;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(prayerSettingsProvider);
    final t = Theme.of(context).textTheme;
    if (s.hasLocation) ref.watch(declinationProvider((s.lat!, s.lng!)));
    final qibla = s.hasLocation ? qiblaBearing(s.lat!, s.lng!) : null;
    final h = _heading;
    final off = qibla == null || h == null ? null : _shortest(h, qibla);
    final facing = off != null && off.abs() <= 4;
    if (facing && !_wasFacing) HapticFeedback.mediumImpact();
    _wasFacing = facing;
    final badField = _field < 20 || _field > 70;
    return Scaffold(
      backgroundColor: QuranColors.velvetDeep,
      appBar: AppBar(backgroundColor: QuranColors.velvet, foregroundColor: QuranColors.goldLight, title: const Text('Qibla · قبلہ')),
      body: Stack(
        children: [
          const Positioned.fill(child: CustomPaint(painter: StarLatticePainter(opacity: .08))),
          ListView(
            key: const Key('qibla-page'),
            padding: const EdgeInsets.all(Space.s24),
            children: [
              if (qibla == null)
                Text('Set your place on the prayer times page first.', style: t.bodyLarge?.copyWith(color: Colors.white))
              else ...[
                Text(
                  'The Kaaba is ${qibla.round()}° from north (${compassPoint(qibla)})',
                  key: const Key('qibla-bearing'),
                  textAlign: TextAlign.center,
                  style: t.titleMedium?.copyWith(color: QuranColors.goldLight),
                ),
                const SizedBox(height: Space.s24),
                AspectRatio(
                  aspectRatio: 1,
                  child: CustomPaint(
                    key: const Key('qibla-dial'),
                    painter: _DialPainter(heading: h ?? 0, qibla: qibla, facing: facing, live: h != null, letters: t.titleMedium ?? const TextStyle()),
                  ),
                ),
                const SizedBox(height: Space.s24),
                Text(
                  _noSensor
                      ? 'This phone has no compass. Face ${qibla.round()}° from north: use the sun, a map, or another compass.'
                      : h == null
                      ? 'Hold the phone flat…'
                      : facing
                      ? 'You are facing the Qibla'
                      : 'Turn ${off! > 0 ? 'right' : 'left'} ${off.abs().round()}°',
                  key: const Key('qibla-hint'),
                  textAlign: TextAlign.center,
                  style: t.headlineSmall?.copyWith(color: facing ? QuranColors.gold : Colors.white, fontWeight: FontWeight.w600),
                ),
                if (facing)
                  Text('آپ کا رخ قبلہ کی طرف ہے', textAlign: TextAlign.center, textDirection: TextDirection.rtl, style: urduText(18, color: QuranColors.goldLight)),
                const SizedBox(height: Space.s16),
                Text(
                  badField && h != null
                      ? 'The compass looks disturbed: move away from metal and magnets, then wave the phone in a figure 8.'
                      : 'Hold the phone flat, away from metal and magnets. If the needle seems wrong, wave the phone in a figure 8 to calibrate it.',
                  key: const Key('qibla-tip'),
                  textAlign: TextAlign.center,
                  style: t.bodySmall?.copyWith(color: badField && h != null ? Colors.orangeAccent : Colors.white70),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  _DialPainter({required this.heading, required this.qibla, required this.facing, required this.live, required this.letters});
  final double heading, qibla;
  final bool facing, live;
  final TextStyle letters;

  @override
  void paint(Canvas canvas, Size size) {
    final ctr = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 8;
    final gold = Paint()
      ..color = QuranColors.gold
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(ctr, r, gold);
    canvas.drawCircle(ctr, r - 10, gold..strokeWidth = 1);
    if (facing) {
      canvas.drawCircle(ctr, r - 12, Paint()..color = QuranColors.gold.withValues(alpha: .14));
    }
    canvas.save();
    canvas.translate(ctr.dx, ctr.dy);
    canvas.rotate(-heading * math.pi / 180); // the dial turns so north stays north
    final tick = Paint()..color = QuranColors.goldLight.withValues(alpha: .7);
    for (var d = 0; d < 360; d += 15) {
      final a = d * math.pi / 180;
      final long = d % 90 == 0;
      tick.strokeWidth = long ? 3 : 1.4;
      canvas.drawLine(Offset(math.sin(a) * (r - 14), -math.cos(a) * (r - 14)), Offset(math.sin(a) * (r - (long ? 30 : 22)), -math.cos(a) * (r - (long ? 30 : 22))), tick);
    }
    for (final (d, l) in [(0, 'N'), (90, 'E'), (180, 'S'), (270, 'W')]) {
      final a = d * math.pi / 180;
      final tp = TextPainter(
        text: TextSpan(text: l, style: letters.copyWith(color: d == 0 ? QuranColors.gold : QuranColors.goldLight, fontSize: 18, fontWeight: FontWeight.w700)),
        textDirection: TextDirection.ltr,
      )..layout();
      final p = Offset(math.sin(a) * (r - 48), -math.cos(a) * (r - 48));
      canvas.save();
      canvas.translate(p.dx, p.dy);
      canvas.rotate(heading * math.pi / 180); // letters stay upright
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }
    // the Kaaba on the rim at the Qibla bearing, with a line from the centre
    final q = qibla * math.pi / 180;
    final kaaba = Offset(math.sin(q) * (r - 4), -math.cos(q) * (r - 4));
    canvas.drawLine(Offset.zero, kaaba * .82, Paint()
      ..color = QuranColors.gold
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round);
    canvas.save();
    canvas.translate(kaaba.dx, kaaba.dy);
    canvas.rotate(heading * math.pi / 180);
    final box = Rect.fromCenter(center: Offset.zero, width: 26, height: 26);
    canvas.drawRRect(RRect.fromRectAndRadius(box, const Radius.circular(3)), Paint()..color = const Color(0xFF111111));
    canvas.drawRect(Rect.fromLTWH(box.left, box.top + 6, box.width, 4), Paint()..color = QuranColors.gold);
    canvas.restore();
    canvas.restore();
    // the phone's direction: a fixed arrow at the top
    final arrow = Path()
      ..moveTo(ctr.dx, ctr.dy - r + 2)
      ..lineTo(ctr.dx - 12, ctr.dy - r + 26)
      ..lineTo(ctr.dx + 12, ctr.dy - r + 26)
      ..close();
    canvas.drawPath(arrow, Paint()..color = live ? (facing ? QuranColors.gold : Colors.white) : Colors.white38);
    canvas.drawCircle(ctr, 6, Paint()..color = QuranColors.gold);
  }

  @override
  bool shouldRepaint(_DialPainter o) => o.heading != heading || o.qibla != qibla || o.facing != facing || o.live != live;
}
