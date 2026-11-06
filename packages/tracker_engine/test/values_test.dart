import 'dart:math';

import 'package:test/test.dart';
import 'package:tracker_engine/tracker_engine.dart';

PropertyDef p(PropertyType t, [Map<String, Object?> c = const {}]) => PropertyDef(id: 'p1', name: 'P', type: t, config: c);
final status = p(PropertyType.status, Cfg.options(const [
  SelectOption(id: 'a', label: 'Not started', group: StatusGroup.todo),
  SelectOption(id: 'b', label: 'In progress', color: 'blue', group: StatusGroup.inProgress),
  SelectOption(id: 'c', label: 'Done', color: 'green', group: StatusGroup.complete),
]));

void main() {
  group('validate', () {
    test('null (empty) is valid for every writable type', () {
      for (final t in PropertyType.values.where((t) => t.isStored)) {
        expect(Values.validate(p(t), null), isNull, reason: t.name);
      }
    });
    test('numbers reject NaN/infinity/strings', () {
      final n = p(PropertyType.number);
      expect(Values.validate(n, double.nan), isNotNull);
      expect(Values.validate(n, double.infinity), isNotNull);
      expect(Values.validate(n, '5'), isNotNull);
      expect(Values.validate(n, 5.5), isNull);
    });
    test('progress is 0..100', () {
      final g = p(PropertyType.progress);
      expect(Values.validate(g, 101), isNotNull);
      expect(Values.validate(g, -1), isNotNull);
      expect(Values.validate(g, 100), isNull);
    });
    test('dates: valid, impossible day rejected, range end >= start', () {
      final d = p(PropertyType.date);
      expect(Values.validate(d, '2026-02-28'), isNull);
      expect(Values.validate(d, '2026-02-31'), isNotNull);
      expect(Values.validate(d, 'tomorrow'), isNotNull);
      final r = p(PropertyType.dateRange);
      expect(Values.validate(r, {'start': '2026-01-02', 'end': '2026-01-01'}), isNotNull);
      expect(Values.validate(r, {'start': '2026-01-02'}), isNull);
    });
    test('select must reference an existing option; multi-select no duplicates', () {
      expect(Values.validate(status, 'b'), isNull);
      expect(Values.validate(status, 'zzz'), isNotNull);
      final m = p(PropertyType.multiSelect, status.config);
      expect(Values.validate(m, ['a', 'b']), isNull);
      expect(Values.validate(m, ['a', 'a']), isNotNull);
    });
    test('computed properties cannot be written', () {
      expect(Values.validate(p(PropertyType.formula), 1), isNotNull);
      expect(Values.validate(p(PropertyType.rollup), 1), isNotNull);
    });
    test('malformed url/email are kept but flagged', () {
      final u = p(PropertyType.url);
      expect(Values.validate(u, 'not a url'), isNull);
      expect(Values.isWellFormed(u, 'not a url'), isFalse);
      expect(Values.isWellFormed(u, 'https://example.com/x'), isTrue);
      expect(Values.isWellFormed(p(PropertyType.email), 'a@b.co'), isTrue);
    });
  });

  group('normalize', () {
    test('trims, empties to null, de-dupes, integral doubles become ints', () {
      expect(Values.normalize(p(PropertyType.text), '  hi '), 'hi');
      expect(Values.normalize(p(PropertyType.text), '   '), isNull);
      expect(Values.normalize(p(PropertyType.multiSelect), ['a', 'b', 'a']), ['a', 'b']);
      expect(Values.normalize(p(PropertyType.multiSelect), <String>[]), isNull);
      expect(Values.normalize(p(PropertyType.number), 5.0), 5);
      expect(Values.normalize(p(PropertyType.date), '2026-11-06T10:00:00+02:00'), '2026-11-06T08:00:00.000Z');
    });
  });

  group('parseText', () {
    final n = p(PropertyType.number);
    test('number formats', () {
      expect(Values.parseText(n, '1,234.56').value, 1234.56);
      expect(Values.parseText(n, '1.234,56').value, 1234.56);
      expect(Values.parseText(n, '12,5').value, 12.5);
      expect(Values.parseText(n, '1,234').value, 1234);
      expect(Values.parseText(n, '-7').value, -7);
      expect(Values.parseText(n, 'abc').error, isNotNull);
      expect(Values.parseText(n, '').value, isNull);
    });
    test('currency to minor units honouring decimals', () {
      expect(Values.parseText(p(PropertyType.currency), r'$1,234.50').value, 123450);
      expect(Values.parseText(p(PropertyType.currency, {'decimals': 0}), '1500').value, 1500);
    });
    test('checkbox words', () {
      final c = p(PropertyType.checkbox);
      expect(Values.parseText(c, 'Yes').value, true);
      expect(Values.parseText(c, 'no').value, false);
      expect(Values.parseText(c, 'maybe').error, isNotNull);
    });
    test('dates: ISO and day-first, reject nonsense', () {
      final d = p(PropertyType.date);
      expect(Values.parseText(d, '2026-11-06').value, '2026-11-06');
      expect(Values.parseText(d, '6/11/2026').value, '2026-11-06');
      expect(Values.parseText(d, '31/02/2026').error, isNotNull);
      expect(Values.parseText(p(PropertyType.dateRange), '2026-01-01 to 2026-01-31').value, {'start': '2026-01-01', 'end': '2026-01-31'});
    });
    test('select matches label case/diacritic-insensitively, unknown offers new option', () {
      expect(Values.parseText(status, 'in PROGRESS').value, 'b');
      final r = Values.parseText(status, 'Blocked');
      expect(r.newOptionLabel, 'Blocked');
      expect(r.isOk, isFalse);
      final m = p(PropertyType.multiSelect, status.config);
      expect(Values.parseText(m, 'Done; Not started').value, ['c', 'a']);
    });
  });

  group('format', () {
    test('numbers with grouping, prefix/suffix, currency, percent, status label', () {
      expect(Values.format(p(PropertyType.number, {'decimals': 2, 'suffix': ' kg'}), 1234.5), '1,234.50 kg');
      expect(Values.format(p(PropertyType.currency), 123450), r'$1,234.50');
      expect(Values.format(p(PropertyType.currency), -5), r'-$0.05');
      expect(Values.format(p(PropertyType.percent, {'fraction': true, 'decimals': 1}), 0.256), '25.6%');
      expect(Values.format(status, 'c'), 'Done');
      expect(Values.format(status, 'gone'), '(removed)');
      expect(Values.format(p(PropertyType.date, {'includeTime': true}), '2026-11-06T08:05:00.000Z'), '2026-11-06 08:05');
    });
  });

  group('storage', () {
    test('columns per type', () {
      expect(Values.toStorage(p(PropertyType.text), 'Éclair')!.sort, 'eclair');
      expect(Values.toStorage(p(PropertyType.checkbox), true)!.intVal, 1);
      expect(Values.toStorage(p(PropertyType.currency), 250)!.num, 250.0);
      expect(Values.toStorage(p(PropertyType.date), '1970-01-02')!.num, 86400000.0);
      expect(Values.toStorage(status, 'c')!.num, isNull, reason: 'rank is derived from current options at query time, never stored');
      expect(Values.toStorage(p(PropertyType.date), '1969-12-31')!.day, -1);
      expect(Values.toStorage(p(PropertyType.date), '1970-01-01T23:59:59Z')!.day, 0);
      expect(Values.toStorage(p(PropertyType.multiSelect), ['x', 'y'])!.json, '["x","y"]');
      expect(Values.toStorage(p(PropertyType.formula), 1), isNull);
      expect(Values.toStorage(p(PropertyType.text), null), isNull);
    });
    test('json encoder escapes control characters and quotes', () {
      expect(Values.toStorage(p(PropertyType.person), ['a"b\n'])!.json, r'["a\"b\n"]');
    });
    test('foldText is case and diacritic insensitive', () {
      expect(foldText('ÀÉÎõü Straße'), 'aeiou strasse');
    });
  });

  group('fractional index', () {
    test('between respects bounds for simple cases', () {
      expect(between(null, null).compareTo('') > 0, isTrue);
      final a = between(null, null), b = between(a, null);
      expect(a.compareTo(b) < 0, isTrue);
      final m = between(a, b);
      expect(a.compareTo(m) < 0 && m.compareTo(b) < 0, isTrue);
      expect(() => between('b', 'a'), throwsArgumentError);
      expect(() => between('a', 'a'), throwsArgumentError);
    });
    test('1000 random insertions keep a strictly sorted list, never end in 0, keys stay short', () {
      final r = Random(7);
      final keys = <String>[];
      for (var i = 0; i < 1000; i++) {
        final pos = r.nextInt(keys.length + 1);
        final k = between(pos == 0 ? null : keys[pos - 1], pos == keys.length ? null : keys[pos]);
        keys.insert(pos, k);
        expect(k.endsWith('0'), isFalse);
      }
      for (var i = 1; i < keys.length; i++) {
        expect(keys[i - 1].compareTo(keys[i]) < 0, isTrue, reason: 'at $i');
      }
      expect(keys.map((k) => k.length).reduce(max), lessThan(40));
    });
    test('worst case: always inserting at the front/back or the same gap stays valid', () {
      var lo = between(null, null);
      var hi = between(lo, null);
      for (var i = 0; i < 200; i++) {
        final m = between(lo, hi);
        expect(lo.compareTo(m) < 0 && m.compareTo(hi) < 0, isTrue);
        hi = m; // squeeze repeatedly
      }
      final ks = keysAfter(null, 100);
      for (var i = 1; i < ks.length; i++) {
        expect(ks[i - 1].compareTo(ks[i]) < 0, isTrue);
      }
    });
  });
}
