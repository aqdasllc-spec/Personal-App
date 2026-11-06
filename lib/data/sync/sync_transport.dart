import 'package:sync_engine/sync_engine.dart';

class SeqChange {
  const SeqChange(this.seq, this.change);
  final int seq;
  final Change change;
}

class PullPage {
  const PullPage(this.changes, {required this.hasMore});
  final List<SeqChange> changes;
  final bool hasMore;
}

class ServerConflict {
  const ServerConflict(this.id, this.conflict);
  final int id;
  final Conflict conflict;
}

class SyncTransportException implements Exception {
  SyncTransportException(this.message, {this.retryable = true});
  final String message;
  final bool retryable;
  @override
  String toString() => 'SyncTransportException($message)';
}

/// The wire contract. Implementations: Supabase (production) and in-memory (tests).
abstract interface class SyncTransport {
  /// Idempotent: re-sending the same (deviceId, changeId) is harmless.
  Future<void> push(List<Change> changes);
  Future<PullPage> pull({required int cursor, int limit = 500});
  Future<List<ServerConflict>> conflicts({required int afterId});
}
