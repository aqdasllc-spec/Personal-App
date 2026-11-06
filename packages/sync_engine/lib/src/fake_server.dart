import 'change.dart';
import 'resolve.dart';

/// In-memory reference implementation of the server contract (`apply_changes` +
/// `change_log`). Used by tests and by the client-side sync integration tests.
/// The SQL in `supabase/migrations` must stay behaviourally identical.
class FakeServer {
  final Map<FieldKey, Versioned> state = {};
  final List<Change> log = []; // index == seq - 1
  final List<Conflict> conflicts = [];
  final Set<String> _seen = {};

  /// Every call to [apply] in order, including retried duplicates (for differential tests).
  final List<Change> trace = [];

  int get seq => log.length;

  /// Idempotent per (deviceId, changeId).
  void apply(Change c) {
    trace.add(c);
    if (!_seen.add('${c.deviceId}/${c.changeId}')) return;
    final r = resolve(state[c.key], c);
    if (r.conflict != null) conflicts.add(r.conflict!);
    if (r.accept) {
      state[c.key] = Versioned(c.value, c.hlc);
      log.add(c);
    }
  }

  List<Change> since(int cursor) => log.sublist(cursor);
}
