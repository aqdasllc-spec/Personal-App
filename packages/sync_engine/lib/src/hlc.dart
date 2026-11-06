import 'dart:math';

/// Hybrid logical clock timestamp.
///
/// The canonical string form is fixed-width so that **lexicographic order equals
/// logical order**. This matters: Postgres compares the same text column with plain
/// `<`/`>`, so server and client agree on the winner without custom operators.
///
///     <wall ms, 12 hex>-<counter, 4 hex>-<node id>
final class Hlc implements Comparable<Hlc> {
  const Hlc(this.wall, this.counter, this.node);

  final int wall;
  final int counter;
  final String node;

  static const maxCounter = 0xFFFF;

  factory Hlc.parse(String s) {
    final parts = s.split('-');
    if (parts.length < 3 || parts[0].length != 12 || parts[1].length != 4) {
      throw FormatException('Invalid HLC', s);
    }
    // node ids may contain '-', so re-join the tail.
    return Hlc(int.parse(parts[0], radix: 16), int.parse(parts[1], radix: 16),
        parts.sublist(2).join('-'));
  }

  @override
  String toString() =>
      '${wall.toRadixString(16).padLeft(12, '0')}-${counter.toRadixString(16).padLeft(4, '0')}-$node';

  @override
  int compareTo(Hlc other) => toString().compareTo(other.toString());

  bool operator >(Hlc o) => compareTo(o) > 0;
  bool operator <(Hlc o) => compareTo(o) < 0;

  @override
  bool operator ==(Object other) => other is Hlc && other.wall == wall && other.counter == counter && other.node == node;

  @override
  int get hashCode => Object.hash(wall, counter, node);
}

class ClockDriftException implements Exception {
  ClockDriftException(this.drift);
  final Duration drift;
  @override
  String toString() => 'Remote clock is ${drift.inMinutes} min ahead of this device';
}

/// Per-device hybrid logical clock. Inject [now] in tests.
class HlcClock {
  HlcClock(this.node, {int Function()? now, this.maxDrift = const Duration(hours: 24)})
      : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  final String node;
  final Duration maxDrift;
  final int Function() _now;
  int _wall = 0;
  int _counter = 0;

  /// Restore the last persisted timestamp after an app restart so the clock never
  /// moves backwards even if the system time did.
  void seed(Hlc last) {
    if (last.wall > _wall || (last.wall == _wall && last.counter > _counter)) {
      _wall = last.wall;
      _counter = last.counter;
    }
  }

  /// Most recent timestamp issued or observed (for persistence).
  Hlc get latest => Hlc(_wall, _counter, node);

  /// Timestamp for a local event (an edit).
  Hlc tick() {
    final phys = _now();
    if (phys > _wall) {
      _wall = phys;
      _counter = 0;
    } else {
      _counter++;
      if (_counter > Hlc.maxCounter) {
        // Extremely unlikely (65k events within one ms); advance wall time instead.
        _wall++;
        _counter = 0;
      }
    }
    return Hlc(_wall, _counter, node);
  }

  /// Merge a timestamp seen from another device (on pull).
  /// Throws [ClockDriftException] when [remote] is implausibly far in the future,
  /// which would otherwise drag every future local timestamp forward.
  void observe(Hlc remote) {
    final phys = _now();
    final ahead = remote.wall - phys;
    if (ahead > maxDrift.inMilliseconds) {
      throw ClockDriftException(Duration(milliseconds: ahead));
    }
    final w = max(max(_wall, remote.wall), phys);
    if (w == _wall && w == remote.wall) {
      _counter = max(_counter, remote.counter) + 1;
    } else if (w == _wall) {
      _counter++;
    } else if (w == remote.wall) {
      _counter = remote.counter + 1;
    } else {
      _counter = 0;
    }
    _wall = w;
  }
}
