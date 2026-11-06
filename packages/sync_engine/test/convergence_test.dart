import 'package:sync_engine/testing.dart';
import 'package:test/test.dart';

void _check(int seed) {
  final (:server, :history, :devices) = simulate(seed);
  // 1. convergence
  for (final d in devices) {
    for (final e in server.state.entries) {
      final l = d.local[e.key];
      expect(l?.hlc, e.value.hlc, reason: 'seed $seed ${d.id} ${e.key}');
      expect(l?.value, e.value.value, reason: 'seed $seed ${d.id} ${e.key}');
    }
  }
  // 2. no silent loss: every edit is final, causally superseded, or in the conflict log
  final lost = server.conflicts.map((c) => '${c.key}|${c.lostHlc}').toSet();
  final superseded = history.where((e) => e.baseHlc != null).map((e) => '${e.key}|${e.baseHlc}').toSet();
  for (final e in history) {
    final id = '${e.key}|${e.hlc}';
    final isFinal = server.state[e.key]!.hlc == e.hlc;
    expect(isFinal || superseded.contains(id) || lost.contains(id), isTrue, reason: 'seed $seed silent loss of $id');
  }
}


void main() {
  test('3000 random multi-device scenarios converge with no silent loss', () {
    for (var seed = 0; seed < 3000; seed++) {
      _check(seed);
    }
  });
}
