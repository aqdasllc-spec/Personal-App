/// Simulation helpers shared by tests and tools. Not for production use.
library;

import 'dart:math';

import 'sync_engine.dart';

/// Minimal client model: local values, outbox, pull cursor.
class SimDevice {
  SimDevice(this.id, this.server, int Function() now) : clock = HlcClock(id, now: now, maxDrift: const Duration(days: 3650));
  final String id;
  final HlcClock clock;
  final FakeServer server;
  final local = <FieldKey, Versioned>{};
  final outbox = <Change>[];
  int cursor = 0;
  int _n = 0;

  void edit(FieldKey k, Object? v, List<Change> history) {
    final c = Change(key: k, value: v, hlc: clock.tick(), baseHlc: local[k]?.hlc, deviceId: id, changeId: '${_n++}');
    local[k] = Versioned(v, c.hlc);
    outbox.add(c);
    history.add(c);
  }

  void push(Random r, {bool allowDuplicates = true}) {
    for (final c in List.of(outbox)) {
      server.apply(c);
      if (allowDuplicates && r.nextInt(5) == 0) server.apply(c); // retried delivery
    }
    outbox.clear();
  }

  void pull() {
    for (final c in server.since(cursor)) {
      clock.observe(c.hlc);
      final cur = local[c.key];
      if (cur == null || c.hlc > cur.hlc) local[c.key] = Versioned(c.value, c.hlc);
    }
    cursor = server.seq;
  }
}

/// Runs one random multi-device scenario and returns the server plus every edit made.
({FakeServer server, List<Change> history, List<SimDevice> devices}) simulate(int seed) {
  final r = Random(seed);
  final server = FakeServer();
  var phys = 1000000;
  final devices = List<SimDevice>.generate(1 + r.nextInt(4), (i) {
    final skew = (r.nextInt(7) - 3) * 50;
    return SimDevice('d$i', server, () => phys + skew);
  });
  final keys = List.generate(1 + r.nextInt(6), (i) => FieldKey('cells', 'r${i ~/ 3}:p${i % 3}', 'value'));
  final history = <Change>[];

  for (var i = 0, n = 20 + r.nextInt(200); i < n; i++) {
    phys += r.nextInt(3);
    final d = devices[r.nextInt(devices.length)];
    switch (r.nextInt(5)) {
      case 0:
      case 1:
        d.edit(keys[r.nextInt(keys.length)], 'v$i', history);
      case 2:
        d.push(r);
      case 3:
        d.pull();
      default:
        d.push(r);
        d.pull();
    }
  }
  for (var round = 0; round < 3; round++) {
    for (final d in devices) { d.push(r, allowDuplicates: false); }
    for (final d in devices) { d.pull(); }
  }

  return (server: server, history: history, devices: devices);
}
