// Spike S-4: scalar-field sync model. Verifies (1) convergence, (2) no silent loss.
import 'dart:math';

class Hlc implements Comparable<Hlc> {
  final int wall, counter; final String node;
  const Hlc(this.wall, this.counter, this.node);
  @override int compareTo(Hlc o) {
    final a = wall.compareTo(o.wall); if (a != 0) return a;
    final b = counter.compareTo(o.counter); if (b != 0) return b;
    return node.compareTo(o.node);
  }
  bool operator >(Hlc o) => compareTo(o) > 0;
  @override bool operator ==(Object o) => o is Hlc && compareTo(o) == 0;
  @override int get hashCode => Object.hash(wall, counter, node);
  @override String toString() => '$wall.$counter@$node';
}

class Clock {
  final String node; int wall = 0, counter = 0;
  Clock(this.node);
  Hlc tick(int phys) {
    if (phys > wall) { wall = phys; counter = 0; } else { counter++; }
    return Hlc(wall, counter, node);
  }
  void merge(Hlc r, int phys) {
    final w = max(max(wall, r.wall), phys);
    if (w == wall && w == r.wall) { counter = max(counter, r.counter) + 1; }
    else if (w == wall) { counter++; }
    else if (w == r.wall) { counter = r.counter + 1; }
    else { counter = 0; }
    wall = w;
  }
}

class Cell { final String? value; final Hlc hlc; Cell(this.value, this.hlc); }
class Change { final String key; final String? value; final Hlc hlc; final Hlc? base; Change(this.key, this.value, this.hlc, this.base); }
class Conflict { final String key; final String? lost; final Hlc lostHlc; Conflict(this.key, this.lost, this.lostHlc); }

class Server {
  final state = <String, Cell>{};
  final log = <Change>[];          // change_log with seq = index
  final conflicts = <Conflict>[];
  final seen = <String>{};         // idempotency: hlc string
  void apply(Change c) {
    if (!seen.add('${c.key}|${c.hlc}')) return; // retry-safe
    final cur = state[c.key];
    if (cur == null) { state[c.key] = Cell(c.value, c.hlc); log.add(c); return; }
    final causal = c.base != null && c.base == cur.hlc;
    if (causal) {
      state[c.key] = Cell(c.value, c.hlc); log.add(c); return;
    }
    // concurrent edit: winner by HLC, loser preserved
    if (c.hlc > cur.hlc) {
      conflicts.add(Conflict(c.key, cur.value, cur.hlc));
      state[c.key] = Cell(c.value, c.hlc); log.add(c);
    } else {
      conflicts.add(Conflict(c.key, c.value, c.hlc));
    }
  }
}

class Device {
  final String id; final Clock clock; final Server s;
  final local = <String, Cell>{}; final outbox = <Change>[]; int cursor = 0;
  Device(this.id, this.s) : clock = Clock(id);
  void edit(String key, String? v, int phys, List<Change> history) {
    final base = local[key]?.hlc; final h = clock.tick(phys);
    local[key] = Cell(v, h);
    final c = Change(key, v, h, base);
    outbox.add(c); history.add(c);
  }
  void push({Random? dropRnd}) {
    // simulate flaky network: may deliver duplicate batch (retry)
    for (final c in List.of(outbox)) { s.apply(c); if (dropRnd != null && dropRnd.nextInt(5) == 0) s.apply(c); }
    outbox.clear();
  }
  void pull(int phys) {
    for (var i = cursor; i < s.log.length; i++) {
      final c = s.log[i]; clock.merge(c.hlc, phys);
      final cur = local[c.key];
      final pending = outbox.any((o) => o.key == c.key);
      if (cur == null || c.hlc > cur.hlc || !pending) {
        if (cur == null || c.hlc > cur.hlc) local[c.key] = Cell(c.value, c.hlc);
      }
    }
    cursor = s.log.length;
  }
}

int run(int seed) {
  final r = Random(seed);
  final s = Server();
  final devs = List.generate(1 + r.nextInt(4), (i) => Device('d$i', s)); // 1..4 devices
  final keys = List.generate(1 + r.nextInt(6), (i) => 'r${i ~/ 3}:p${i % 3}');
  final history = <Change>[];
  var phys = 1000;
  final ops = 20 + r.nextInt(200);
  for (var i = 0; i < ops; i++) {
    phys += r.nextInt(3); // wall clock barely moves; some devices skewed
    final d = devs[r.nextInt(devs.length)];
    final skew = d.id.hashCode % 7 - 3;               // clock skew per device
    switch (r.nextInt(5)) {
      case 0: case 1: d.edit(keys[r.nextInt(keys.length)], 'v$i', phys + skew * 50, history); break;
      case 2: d.push(dropRnd: r); break;
      case 3: d.pull(phys + skew * 50); break;
      case 4: if (r.nextBool()) { d.push(dropRnd: r); d.pull(phys); } break;
    }
  }
  // network heals: everyone pushes then pulls until quiescent
  for (var round = 0; round < 3; round++) {
    for (final d in devs) { d.push(); }
    for (final d in devs) { d.pull(phys + 10000); }
  }
  // (1) convergence
  for (final d in devs) {
    for (final k in s.state.keys) {
      final a = d.local[k], b = s.state[k]!;
      if (a == null || a.hlc != b.hlc || a.value != b.value) throw 'seed $seed: ${d.id} diverged on $k';
    }
  }
  // (2) no silent loss: every edit is final, superseded causally, or logged as conflict
  final lostSet = s.conflicts.map((c) => '${c.key}|${c.lostHlc}').toSet();
  final superseded = history.where((e) => e.base != null).map((e) => '${e.key}|${e.base}').toSet();
  var losses = 0;
  for (final e in history) {
    final fin = s.state[e.key]!;
    final isFinal = fin.hlc == e.hlc;
    final k = '${e.key}|${e.hlc}';
    if (!isFinal && !superseded.contains(k) && !lostSet.contains(k)) throw 'seed $seed: SILENT LOSS $k';
    if (lostSet.contains(k)) losses++;
  }
  return s.conflicts.length;
}
void main() {
  var totalConflicts = 0, n = 5000;
  for (var seed = 0; seed < n; seed++) { totalConflicts += run(seed); }
  print('PASS: $n random scenarios converged with no silent loss; conflicts preserved & logged: $totalConflicts');
}
