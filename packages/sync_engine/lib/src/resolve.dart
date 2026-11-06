import 'change.dart';

/// Result of applying one incoming [Change] to the current server/local value.
final class Resolution {
  const Resolution._(this.accept, this.duplicate, this.conflict);

  /// The incoming change becomes the current value.
  final bool accept;

  /// The exact same edit was already applied (retry); nothing to do.
  final bool duplicate;

  /// Set when two edits were concurrent. The loser is preserved here, never dropped.
  final Conflict? conflict;

  static const Resolution acceptClean = Resolution._(true, false, null);
  static const Resolution noop = Resolution._(false, true, null);
  const Resolution.acceptWithConflict(Conflict c) : this._(true, false, c);
  const Resolution.rejectWithConflict(Conflict c) : this._(false, false, c);
}

/// Field-level rule shared (and mirrored in SQL by `apply_changes`):
///
/// 1. no current value        -> accept
/// 2. same clock              -> duplicate, ignore
/// 3. `baseHlc == current`    -> causal successor, accept
/// 4. otherwise concurrent    -> higher HLC wins, loser is recorded as a [Conflict]
///
/// An edit with an unknown base (device never saw the field) is concurrent with any
/// existing value - this closes the silent-overwrite hole found by spike S-4.
Resolution resolve(Versioned? current, Change incoming) {
  if (current == null) return Resolution.acceptClean;
  if (incoming.hlc == current.hlc) return Resolution.noop;
  if (incoming.baseHlc != null && incoming.baseHlc == current.hlc) return Resolution.acceptClean;
  if (incoming.hlc > current.hlc) {
    return Resolution.acceptWithConflict(Conflict(
        key: incoming.key, lostValue: current.value, lostHlc: current.hlc, winnerHlc: incoming.hlc));
  }
  return Resolution.rejectWithConflict(Conflict(
      key: incoming.key, lostValue: incoming.value, lostHlc: incoming.hlc, winnerHlc: current.hlc));
}
