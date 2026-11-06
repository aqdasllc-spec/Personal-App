import 'package:sync_engine/sync_engine.dart';
import 'package:test/test.dart';

void main() {
  test('string form sorts like logical order', () {
    final a = const Hlc(1000, 0, 'a'), b = const Hlc(1000, 1, 'a'), c = const Hlc(1001, 0, 'a');
    expect([c, a, b]..sort(), [a, b, c]);
    expect(a.toString().compareTo(b.toString()) < 0, isTrue);
  });

  test('parse round-trips, including node ids containing dashes', () {
    const h = Hlc(0x18c3a1b2c3d, 42, 'dev-ice-1');
    expect(Hlc.parse(h.toString()), h);
  });

  test('tick is strictly monotonic even if wall clock stalls or goes backwards', () {
    var t = 5000;
    final c = HlcClock('n', now: () => t);
    final seen = <Hlc>[c.tick(), c.tick()];
    t = 4000; // clock set backwards
    seen.add(c.tick());
    t = 6000;
    seen.add(c.tick());
    for (var i = 1; i < seen.length; i++) {
      expect(seen[i] > seen[i - 1], isTrue, reason: '$i');
    }
  });

  test('observe makes later local ticks exceed the remote timestamp', () {
    final c = HlcClock('a', now: () => 1000);
    c.observe(const Hlc(1500, 7, 'b'));
    expect(c.tick() > const Hlc(1500, 7, 'b'), isTrue);
  });

  test('observe rejects timestamps absurdly far in the future', () {
    final c = HlcClock('a', now: () => 1000, maxDrift: const Duration(hours: 1));
    expect(() => c.observe(Hlc(1000 + 2 * 3600 * 1000, 0, 'b')), throwsA(isA<ClockDriftException>()));
  });
}
