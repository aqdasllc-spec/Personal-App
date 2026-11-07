import 'package:sync_engine/sync_engine.dart';

import 'sync_transport.dart';

/// Transport backed by the reference [FakeServer]. Supports simulated outages.
class InMemoryTransport implements SyncTransport {
  InMemoryTransport(this.server);
  final FakeServer server;
  bool offline = false;
  int pushCalls = 0;

  void _check() {
    if (offline) throw SyncTransportException('offline');
  }

  @override
  Future<void> push(List<Change> changes) async {
    _check();
    pushCalls++;
    changes.forEach(server.apply);
  }

  @override
  Future<PullPage> pull({required int cursor, int limit = 500}) async {
    _check();
    final all = server.since(cursor);
    final page = all.take(limit).toList();
    return PullPage([
      for (var i = 0; i < page.length; i++) SeqChange(cursor + i + 1, page[i]),
    ], hasMore: all.length > limit);
  }

  @override
  Future<List<ServerConflict>> conflicts({required int afterId}) async {
    _check();
    return [
      for (var i = afterId; i < server.conflicts.length; i++)
        ServerConflict(i + 1, server.conflicts[i]),
    ];
  }
}
