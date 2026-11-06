import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/data/sync/synced_tables.dart';

void main() {
  test('every table the client syncs is on the server allow-list in apply_changes', () {
    final sql = Directory('supabase/migrations').listSync().whereType<File>().map((f) => f.readAsStringSync()).join('\n');
    final m = RegExp(r"allowed_tbl constant text\[\] := array\[(.*?)\];", dotAll: true).allMatches(sql).last;
    final server = RegExp(r"'([a-z_]+)'").allMatches(m.group(1)!).map((x) => x.group(1)!).toSet();
    final client = syncedTables.keys.toSet();
    expect(server.containsAll(client), isTrue, reason: 'client syncs tables the server would reject: ${client.difference(server)}');
    for (final t in syncedTables.values) {
      expect(t.fieldToColumn.keys.every((f) => RegExp(r'^[A-Za-z0-9_:\-]{1,100}$').hasMatch(f)), isTrue, reason: '${t.name} has a field name the server rejects');
    }
  });
}
