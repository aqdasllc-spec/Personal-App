// Spike S-7: cells-as-rows benchmark. 10k records x 20 properties.
import 'dart:io';
import 'dart:math';
import 'package:sqlite3/sqlite3.dart';

int ms(Stopwatch s) => s.elapsedMilliseconds;

void main(List<String> args) {
  final nRec = args.isNotEmpty ? int.parse(args[0]) : 10000;
  const nProp = 20;
  final db = sqlite3.openInMemory();
  print('sqlite ${sqlite3.version}');
  db.execute('''
    PRAGMA journal_mode=WAL;
    CREATE TABLE records(id INTEGER PRIMARY KEY, tracker_id INT, parent_id INT, sort_key TEXT, deleted_at INT);
    CREATE TABLE cells(record_id INT, property_id INT, v_text TEXT, v_num REAL, v_int INT, v_json TEXT, hlc TEXT,
      PRIMARY KEY(record_id, property_id)) WITHOUT ROWID;
    CREATE INDEX cells_prop_num ON cells(property_id, v_num) WHERE v_num IS NOT NULL;
    CREATE INDEX cells_prop_text ON cells(property_id, v_text) WHERE v_text IS NOT NULL;
    CREATE INDEX records_tracker ON records(tracker_id, sort_key) WHERE deleted_at IS NULL;
  ''');
  final rnd = Random(42);
  final statuses = ['Not started', 'In progress', 'Blocked', 'Review', 'Done'];
  // props 0 title(text) 1 status(text) 2 progress(num) 3 priority(text) 4 due(num epoch) 5..19 mixed
  var sw = Stopwatch()..start();
  db.execute('BEGIN');
  final insR = db.prepare('INSERT INTO records VALUES(?,?,?,?,NULL)');
  final insC = db.prepare('INSERT INTO cells VALUES(?,?,?,?,?,NULL,?)');
  for (var r = 0; r < nRec; r++) {
    insR.execute([r, 1, null, r.toRadixString(36).padLeft(6, '0')]);
    for (var p = 0; p < nProp; p++) {
      if (p == 0 || p == 1 || p == 3 || p >= 10) {
        final t = p == 1 ? statuses[rnd.nextInt(5)] : p == 3 ? ['High','Medium','Low'][rnd.nextInt(3)] : 'text r$r p$p ${rnd.nextInt(1000)}';
        insC.execute([r, p, p == 0 ? 'Task number $r alpha beta' : t, null, null, 'h$r']);
      } else {
        insC.execute([r, p, null, rnd.nextDouble() * 100, null, 'h$r']);
      }
    }
  }
  db.execute('COMMIT');
  print('insert ${nRec * nProp} cells: ${ms(sw)} ms');

  List<int> times(String name, String sql, [List<Object?> params = const [], int runs = 20]) {
    final t = <int>[];
    ResultSet? rs;
    for (var i = 0; i < runs; i++) {
      final s = Stopwatch()..start();
      rs = db.select(sql, params);
      s.stop();
      t.add(s.elapsedMicroseconds);
    }
    t.sort();
    print('${name.padRight(46)} p50 ${(t[runs ~/ 2] / 1000).toStringAsFixed(2)} ms  p95 ${(t[(runs * .95).floor().clamp(0, runs - 1)] / 1000).toStringAsFixed(2)} ms  rows=${rs!.length}');
    return t;
  }

  // 1. filter: status = 'In progress' AND progress > 50, return ids
  times('filter status=X AND progress>50 (ids)', '''
    SELECT s.record_id FROM cells s JOIN cells n ON n.record_id=s.record_id AND n.property_id=2
    WHERE s.property_id=1 AND s.v_text='In progress' AND n.v_num>50''');
  // 2. sort by progress desc, page of 50 (keyset-ish via LIMIT) w/ non-deleted
  times('sort progress DESC limit 50', '''
    SELECT c.record_id FROM cells c JOIN records r ON r.id=c.record_id
    WHERE c.property_id=2 AND r.deleted_at IS NULL ORDER BY c.v_num DESC LIMIT 50''');
  // 3. filter+sort+page together
  times('filter status + sort progress, page 50', '''
    SELECT n.record_id FROM cells s JOIN cells n ON n.record_id=s.record_id AND n.property_id=2
    WHERE s.property_id=1 AND s.v_text='Done' ORDER BY n.v_num DESC LIMIT 50''');
  // 4. group counts by status
  times('group count by status', "SELECT v_text, count(*) FROM cells WHERE property_id=1 GROUP BY v_text");
  // 5. aggregate sum/avg progress
  times('aggregate avg/sum progress', 'SELECT avg(v_num), sum(v_num) FROM cells WHERE property_id=2');
  // 6. visible-page load: 50 records x 8 visible columns
  final ids = List.generate(50, (i) => i * 37 % nRec).join(',');
  times('load page: 50 rows x 8 visible props', 'SELECT record_id, property_id, v_text, v_num FROM cells WHERE record_id IN ($ids) AND property_id IN (0,1,2,3,4,5,6,7)');
  // 7. load page all 20 props
  times('load page: 50 rows x 20 props', 'SELECT * FROM cells WHERE record_id IN ($ids)');
  // 8. contains search on title (LIKE, no index) -> shows why FTS needed
  times('LIKE %alpha 99% on title (no FTS)', "SELECT record_id FROM cells WHERE property_id=0 AND v_text LIKE '%number 99%'", const [], 10);
  // 9. single cell update
  final upd = db.prepare('UPDATE cells SET v_num=?, hlc=? WHERE record_id=? AND property_id=2');
  sw = Stopwatch()..start();
  for (var i = 0; i < 1000; i++) { upd.execute([i.toDouble(), 'h2', i]); }
  print('1000 single-cell updates (autocommit mem): ${ms(sw)} ms');
  // 10. FTS5 external content
  db.execute('CREATE VIRTUAL TABLE fts USING fts5(title, body, tokenize="unicode61 remove_diacritics 2")');
  sw = Stopwatch()..start();
  db.execute('BEGIN');
  db.execute("INSERT INTO fts(rowid,title,body) SELECT record_id, v_text, '' FROM cells WHERE property_id=0");
  db.execute('COMMIT');
  print('FTS5 index $nRec titles: ${ms(sw)} ms');
  times('FTS5 MATCH "alpha number*" bm25 limit 20', "SELECT rowid FROM fts WHERE fts MATCH 'alpha AND number*' ORDER BY bm25(fts) LIMIT 20");
  db.dispose();
  exit(0);
}
