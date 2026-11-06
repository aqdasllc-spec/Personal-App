import 'package:test/test.dart';
import 'package:tracker_engine/tracker_engine.dart';

import 'fixtures.dart';

void main() {
  group('parse / write', () {
    test('quotes, escaped quotes, newlines in cells, CRLF, BOM, trailing newline', () {
      const src = '﻿a,b,c\r\n1,"x, y","he said ""hi"""\r\n"multi\nline",,3\r\n';
      expect(parseCsv(src), [['a', 'b', 'c'], ['1', 'x, y', 'he said "hi"'], ['multi\nline', '', '3']]);
    });
    test('detects semicolon and tab delimiters', () {
      expect(parseCsv('a;b\n1;2'), [['a', 'b'], ['1', '2']]);
      expect(parseCsv('a\tb\n1\t2'), [['a', 'b'], ['1', '2']]);
    });
    test('blank lines skipped, empty quoted cell kept, unterminated quote rejected', () {
      expect(parseCsv('a,b\n\n1,2\n'), [['a', 'b'], ['1', '2']]);
      expect(parseCsv('"",x'), [['', 'x']]);
      expect(() => parseCsv('a,"b'), throwsFormatException);
    });
    test('write then parse is lossless for awkward text', () {
      final rows = [['h1', 'h2'], ['a,b', 'q"uote'], ['line\nbreak', '  spaces  '], ['ünï', '']];
      expect(parseCsv(writeCsv(rows)), rows);
    });
  });

  group('export', () {
    test('machine-friendly cells; formula-injection guarded for text, numbers stay numbers', () {
      final s = tasksSnapshot([
        task('a', '=HYPERLINK("http://evil")', status: 'doing', hours: -5, due: '2026-11-08', tags: ['t1', 't2'], done: true),
        task('b', '+cmd', hours: 2.5),
      ]);
      final csv = exportCsv(s, s.properties, s.records, now: now);
      final rows = parseCsv(csv);
      expect(rows.first, ['Name', 'Status', 'Hours', 'Due', 'Tags', 'Done?', 'Days left']);
      expect(rows[1], ["'=HYPERLINK(\"http://evil\")", 'In progress', '-5', '2026-11-08', 'Urgent; Home', 'true', '2']);
      expect(rows[2][0], "'+cmd");
      expect(rows[2][2], '2.5');
    });
  });

  group('import plan (dry run)', () {
    final headers = ['Name', 'Status', 'Hours', 'Due', 'Tags', 'Done?'];
    final mapping = {0: 'name', 1: 'status', 2: 'hours', 3: 'due', 4: 'tags', 5: 'done'};

    test('typed parsing of every mapped column', () {
      final plan = planImport(
        headers: headers,
        rows: [['Write', 'in progress', '1,5', '6/11/2026', 'Urgent; Work', 'yes']],
        properties: taskProps,
        mapping: mapping,
      );
      expect(plan.hasErrors, isFalse);
      expect(plan.records.single, {'name': 'Write', 'status': 'doing', 'hours': 1.5, 'due': '2026-11-06', 'tags': ['t1', 't3'], 'done': true});
    });
    test('bad cells are reported with row/column, the rest of the row is kept, nothing throws', () {
      final plan = planImport(
        headers: headers,
        rows: [['A', 'In progress', 'lots', '2026-13-45', '', 'maybe'], ['B', 'Done', '2', '', '', '']],
        properties: taskProps,
        mapping: mapping,
      );
      expect(plan.issues.map((i) => '${i.row}:${i.column}'), ['1:Hours', '1:Due', '1:Done?']);
      expect(plan.records[0], {'name': 'A', 'status': 'doing'});
      expect(plan.records[1]['hours'], 2);
    });
    test('unknown option labels are collected so the user can create them', () {
      final plan = planImport(headers: headers, rows: [['A', 'Waiting', '', '', 'Errands', '']], properties: taskProps, mapping: mapping);
      expect(plan.newOptions, {'status': {'Waiting'}, 'tags': {'Errands'}});
      expect(plan.hasErrors, isFalse);
    });
    test('unmapped columns are listed; blank rows skipped; export guard apostrophe is undone', () {
      final plan = planImport(
        headers: ['Name', 'Extra'],
        rows: [["'=x", 'zzz'], ['', ''], ['B', 'q']],
        properties: taskProps,
        mapping: {0: 'name'},
      );
      expect(plan.skippedColumns, ['Extra']);
      expect(plan.records.map((r) => r['name']), ['=x', 'B']);
    });
    test('computed/relation properties are never imported', () {
      final plan = planImport(headers: ['Days left'], rows: [['5']], properties: taskProps, mapping: {0: 'daysLeft'});
      expect(plan.records.single, isEmpty);
    });
    test('export then import round-trips stored values', () {
      final s = tasksSnapshot();
      final stored = s.properties.where((p) => p.type.isStored).toList();
      final rows = parseCsv(exportCsv(s, stored, s.records.where((r) => !r.archived).toList(), now: now));
      final plan = planImport(headers: rows.first, rows: rows.sublist(1), properties: stored, mapping: {for (var i = 0; i < stored.length; i++) i: stored[i].id});
      expect(plan.hasErrors, isFalse, reason: plan.issues.join('; '));
      for (var i = 0; i < plan.records.length; i++) {
        final orig = s.records[i].cells;
        for (final e in orig.entries) {
          final got = plan.records[i][e.key];
          expect(got is num ? got.toDouble() : got, e.value is num ? (e.value! as num).toDouble() : e.value, reason: '${s.records[i].id}.${e.key}');
        }
      }
    });
  });

  group('inferType', () {
    test('guesses sensible types', () {
      expect(inferType(['true', 'no', 'Yes']), PropertyType.checkbox);
      expect(inferType(['2026-01-02', '2026-03-04']), PropertyType.date);
      expect(inferType(['1', '2.5', '-3']), PropertyType.number);
      expect(inferType(['https://a.b', 'http://c.d']), PropertyType.url);
      expect(inferType(['a@b.co', 'x@y.zz']), PropertyType.email);
      expect(inferType(['a', 'b', 'a', 'b', 'a', 'b', 'a', 'b']), PropertyType.select);
      expect(inferType(['one', 'two', 'three']), PropertyType.text);
      expect(inferType(['', ' ']), PropertyType.text);
    });
  });
}
