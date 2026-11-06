// Differential test: replays random scenarios through (a) the Dart reference server and
// (b) the real Postgres `apply_changes` function, then compares final field state and
// conflict counts. Requires a Postgres with supabase/migrations applied via
// supabase/tests/run.sh-style setup. Usage:
//   PGHOST=/tmp PGPORT=54329 PGUSER=postgres dart run tool/differential.dart [scenarios]
import 'dart:convert';
import 'dart:io';

import 'package:sync_engine/testing.dart';

String uuidFor(int s) => '00000000-0000-4000-8000-${s.toRadixString(16).padLeft(12, '0')}';
String sqlStr(String s) => "'${s.replaceAll("'", "''")}'";

Future<void> main(List<String> args) async {
  final n = args.isEmpty ? 200 : int.parse(args[0]);
  final dbName = 'folio_diff_$pid';
  Future<ProcessResult> psql(List<String> a, {String? db}) =>
      Process.run('psql', ['-X', '-q', '-v', 'ON_ERROR_STOP=1', '-d', db ?? dbName, ...a]);
  var r = await Process.run('psql', ['-X', '-q', '-d', 'postgres', '-c', 'create database $dbName']);
  if (r.exitCode != 0) { stderr.writeln(r.stderr); exit(2); }
  try {
    for (final f in ['../../supabase/tests/00_stub_auth.sql', '../../supabase/migrations/20261106000000_sync_core.sql']) {
      r = await psql(['-f', f]);
      if (r.exitCode != 0) { stderr.writeln(r.stderr); exit(2); }
    }
    final expected = <String, String>{};
    final expectedConflicts = <String, int>{};
    final sql = StringBuffer();
    for (var seed = 0; seed < n; seed++) {
      final sim = simulate(seed);
      final uid = uuidFor(seed);
      sql.writeln("reset role; insert into auth.users values ('$uid'); set role authenticated;");
      sql.writeln("select set_config('request.jwt.claim.sub', '$uid', false) \\g /dev/null");
      for (final c in sim.server.trace) {
        final j = jsonEncode({'tbl': c.key.table, 'row_id': c.key.rowId, 'field': c.key.field, 'value': c.value,
          'hlc': c.hlc.toString(), 'base_hlc': c.baseHlc?.toString(), 'device_id': c.deviceId, 'change_id': c.changeId});
        sql.writeln('select apply_changes(${sqlStr('[$j]')}::jsonb) \\g /dev/null');
      }
      for (final e in sim.server.state.entries) {
        expected['$uid|${e.key.table}|${e.key.rowId}|${e.key.field}'] = '${e.value.value}|${e.value.hlc}';
      }
      expectedConflicts[uid] = sim.server.conflicts.length;
    }
    sql.writeln('reset role;');
    sql.writeln(r"\echo FIELDS");
    sql.writeln("select owner_id||'|'||tbl||'|'||row_id||'|'||field||'|'||(value #>> '{}')||'|'||hlc from sync_fields order by 1;");
    sql.writeln(r"\echo CONFLICTS");
    sql.writeln("select owner_id||'|'||count(*) from sync_conflicts group by owner_id;");
    final file = File('${Directory.systemTemp.path}/diff_$pid.sql')..writeAsStringSync(sql.toString());
    r = await psql(['-t', '-A', '-f', file.path]);
    file.deleteSync();
    if (r.exitCode != 0) { stderr.writeln(r.stderr); exit(2); }
    final lines = const LineSplitter().convert(r.stdout as String);
    final fi = lines.indexOf('FIELDS'), ci = lines.indexOf('CONFLICTS');
    final actual = <String, String>{};
    for (final l in lines.sublist(fi + 1, ci).where((l) => l.isNotEmpty)) {
      final p = l.split('|');
      actual['${p[0]}|${p[1]}|${p[2]}|${p[3]}'] = '${p[4]}|${p.sublist(5).join('|')}';
    }
    final actualConflicts = <String, int>{
      for (final l in lines.sublist(ci + 1).where((l) => l.isNotEmpty)) l.split('|')[0]: int.parse(l.split('|')[1])
    };
    var bad = 0;
    for (final k in {...expected.keys, ...actual.keys}) {
      if (expected[k] != actual[k]) { bad++; if (bad < 6) stderr.writeln('FIELD MISMATCH $k dart=${expected[k]} sql=${actual[k]}'); }
    }
    for (final k in expectedConflicts.keys) {
      final e = expectedConflicts[k]!, a = actualConflicts[k] ?? 0;
      if (e != a) { bad++; if (bad < 6) stderr.writeln('CONFLICT COUNT MISMATCH $k dart=$e sql=$a'); }
    }
    final totalConf = expectedConflicts.values.fold(0, (a, b) => a + b);
    if (bad > 0) { stderr.writeln('FAILED: $bad mismatches'); exit(1); }
    print('PASS: $n scenarios, ${expected.length} fields, $totalConf conflicts identical in Dart reference and Postgres');
  } finally {
    await Process.run('psql', ['-X', '-q', '-d', 'postgres', '-c', 'drop database $dbName']);
  }
}
