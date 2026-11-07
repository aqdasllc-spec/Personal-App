import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sync_engine/sync_engine.dart';

import 'sync_transport.dart';

/// Production transport over Supabase (PostgREST + the `apply_changes` RPC).
///
/// NOTE: compiled and analysed, but NOT yet exercised against a live Supabase project;
/// the SQL it calls is tested against Postgres 16 (supabase/tests, tool/differential.dart).
class SupabaseSyncTransport implements SyncTransport {
  SupabaseSyncTransport(this._client);
  final SupabaseClient _client;

  @override
  Future<void> push(List<Change> changes) async {
    try {
      await _client.rpc(
        'apply_changes',
        params: {
          'changes': [
            for (final c in changes)
              {
                'tbl': c.key.table,
                'row_id': c.key.rowId,
                'field': c.key.field,
                'value': c.value,
                'hlc': c.hlc.toString(),
                'base_hlc': c.baseHlc?.toString(),
                'device_id': c.deviceId,
                'change_id': c.changeId,
              },
          ],
        },
      );
    } on PostgrestException catch (e) {
      // 22023/54000: our payload is invalid -> retrying cannot help.
      final fatal = e.code == '22023' || e.code == '54000';
      throw SyncTransportException(e.message, retryable: !fatal);
    } catch (e) {
      throw SyncTransportException('$e');
    }
  }

  @override
  Future<PullPage> pull({required int cursor, int limit = 500}) async {
    try {
      final rows = await _client
          .from('change_log')
          .select()
          .gt('seq', cursor)
          .order('seq')
          .limit(limit + 1);
      final more = rows.length > limit;
      final page = rows.take(limit);
      return PullPage([
        for (final r in page)
          SeqChange(
            (r['seq'] as num).toInt(),
            Change(
              key: FieldKey(
                r['tbl'] as String,
                r['row_id'] as String,
                r['field'] as String,
              ),
              value: r['value'],
              hlc: Hlc.parse(r['hlc'] as String),
              baseHlc: r['base_hlc'] == null
                  ? null
                  : Hlc.parse(r['base_hlc'] as String),
              deviceId: r['device_id'] as String,
              changeId: r['change_id'] as String,
            ),
          ),
      ], hasMore: more);
    } catch (e) {
      throw SyncTransportException('$e');
    }
  }

  @override
  Future<List<ServerConflict>> conflicts({required int afterId}) async {
    try {
      final rows = await _client
          .from('sync_conflicts')
          .select()
          .gt('id', afterId)
          .order('id')
          .limit(500);
      return [
        for (final r in rows)
          ServerConflict(
            (r['id'] as num).toInt(),
            Conflict(
              key: FieldKey(
                r['tbl'] as String,
                r['row_id'] as String,
                r['field'] as String,
              ),
              lostValue: r['lost_value'],
              lostHlc: Hlc.parse(r['lost_hlc'] as String),
              winnerHlc: Hlc.parse(r['winner_hlc'] as String),
            ),
          ),
      ];
    } catch (e) {
      throw SyncTransportException('$e');
    }
  }
}
