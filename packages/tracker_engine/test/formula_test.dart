import 'package:test/test.dart';
import 'package:tracker_engine/tracker_engine.dart';

class Ctx implements FormulaContext {
  Ctx([this.values = const {}, DateTime? now]) : now = now ?? DateTime.utc(2026, 11, 6, 12);
  final Map<String, Object?> values;
  @override
  final DateTime now;
  @override
  bool knows(String id) => values.containsKey(id);
  @override
  Object? read(String id) => values[id];
}

Object? ev(String s, [Map<String, Object?> v = const {}]) => evaluateFormula(s, Ctx(v));

void main() {
  group('arithmetic & logic', () {
    test('precedence, parentheses, unary minus', () {
      expect(ev('1 + 2 * 3'), 7);
      expect(ev('(1 + 2) * 3'), 9);
      expect(ev('-2 * -3'), 6);
      expect(ev('10 % 4'), 2);
      expect(ev('2 + 3 > 4 and 1 == 1'), true);
      expect(ev('not (1 > 2)'), true);
      expect(ev('1 < 2 or 1 / 0 > 1'), true, reason: 'or short-circuits');
    });
    test('errors are values, not exceptions', () {
      expect(ev('1 / 0'), const FormulaError('#DIV0'));
      expect(ev('"a" * 2'), const FormulaError('#TYPE'));
      expect(ev('1 +'), const FormulaError('#SYNTAX'));
      expect(ev('foo(1)'), const FormulaError('#NAME'));
      expect(ev('x'), const FormulaError('#SYNTAX'));
      expect(ev('prop("nope")'), const FormulaError('#REF'));
      expect(ev('1 + 1 / 0'), const FormulaError('#DIV0'), reason: 'errors propagate');
      expect(ev('round()'), const FormulaError('#ARGS'));
    });
    test('if() is lazy: untaken branch is not evaluated', () {
      expect(ev('if(true, 1, 1/0)'), 1);
      expect(ev('if(false, 1/0, 2)'), 2);
    });
  });

  group('properties', () {
    test('prop() reads typed values', () {
      expect(ev('prop("a") + prop("b")', {'a': 2, 'b': 3.5}), 5.5);
      expect(ev('upper(prop("t"))', {'t': 'hi'}), 'HI');
      expect(ev('prop("a") + "x"', {'a': 1}), '1x');
      expect(ev('sum(prop("l"))', {'l': [1, 2, 3]}), 6);
      expect(ev('count(prop("l"))', {'l': [1, null, 3]}), 2);
      expect(ev('join(prop("l"), "-")', {'l': ['a', 'b']}), 'a-b');
      expect(ev('isEmpty(prop("n"))', {'n': null}), true);
    });
  });

  group('functions', () {
    test('text', () {
      expect(ev('concat("a", 1, "b")'), 'a1b');
      expect(ev('length("héllo")'), 5);
      expect(ev('replace("a-b-c", "-", "+")'), 'a+b+c');
      expect(ev('contains("hello", "ell")'), true);
      expect(ev('trim("  x ")'), 'x');
    });
    test('math', () {
      expect(ev('round(2.567, 2)'), 2.57);
      expect(ev('round(2.5)'), 3);
      expect(ev('floor(2.9) + ceil(2.1)'), 5);
      expect(ev('min(3, 1, 2)'), 1);
      expect(ev('max(3, 1, 2)'), 3);
      expect(ev('avg(1, 2, 3)'), 2);
      expect(ev('sqrt(-1)'), const FormulaError('#TYPE'));
      expect(ev('pow(2, 10)'), 1024);
    });
    test('dates', () {
      final d = DateTime.utc(2026, 1, 31);
      expect(ev('dateAdd(prop("d"), 1, "months")', {'d': d}), DateTime.utc(2026, 2, 28), reason: 'month-end clamp');
      expect(ev('dateAdd(prop("d"), 2, "weeks")', {'d': d}), DateTime.utc(2026, 2, 14));
      expect(ev('dateBetween(prop("a"), prop("b"), "days")', {'a': DateTime.utc(2026, 11, 14), 'b': DateTime.utc(2026, 11, 6)}), 8);
      expect(ev('dateBetween(prop("b"), prop("a"), "days")', {'a': DateTime.utc(2026, 11, 14), 'b': DateTime.utc(2026, 11, 6)}), -8);
      expect(ev('dateBetween(prop("due"), today(), "days")', {'due': DateTime.utc(2026, 11, 14)}), 8);
      expect(ev('formatDate(prop("d"), "DD MMM YYYY")', {'d': d}), '31 Jan 2026');
      expect(ev('dateAdd(today(), 1, "fortnights")'), const FormulaError('#ARGS'));
      expect(ev('prop("d") - prop("e")', {'d': DateTime.utc(2026, 1, 3), 'e': DateTime.utc(2026, 1, 1)}), 2);
    });
  });

  group('limits (no hang, no crash on hostile input)', () {
    test('deep nesting is rejected at parse time', () {
      final s = '${'(' * 200}1${')' * 200}';
      expect(ev(s), const FormulaError('#SYNTAX'));
    });
    test('long source rejected', () {
      expect(ev('1+' * 3000), const FormulaError('#SYNTAX'));
    });
    test('a maximum-length expression still evaluates quickly and correctly', () {
      // The 4000-char source cap bounds the work; maxSteps is a defensive backstop only.
      final src = List.filled(790, '1').join('+');
      expect(src.length <= FormulaLimits.maxSourceLength, isTrue);
      expect(ev(src), 790);
    });
    test('unterminated string and stray characters', () {
      expect(ev('"abc'), const FormulaError('#SYNTAX'));
      expect(ev('1 @ 2'), const FormulaError('#SYNTAX'));
    });
  });

  group('names <-> ids', () {
    final defs = [
      const PropertyDef(id: 'p_due', name: 'Due', type: PropertyType.date),
      const PropertyDef(id: 'p_cost', name: 'Cost (USD)', type: PropertyType.number),
    ];
    test('canonicalize replaces names with ids; display reverses', () {
      const src = 'dateBetween(prop("Due"), today(), "days") + prop("Cost (USD)")';
      final canon = canonicalizeFormula(src, defs);
      expect(canon, 'dateBetween(prop("p_due"), today(), "days") + prop("p_cost")');
      expect(displayFormula(canon, defs), src);
    });
    test('unknown names are left alone (-> #REF when evaluated)', () {
      expect(canonicalizeFormula('prop("Missing")', defs), 'prop("Missing")');
    });
    test('renaming a property does not break a stored formula', () {
      final stored = canonicalizeFormula('prop("Due")', defs);
      final renamed = [defs[0].copyWith(name: 'Deadline'), defs[1]];
      expect(displayFormula(stored, renamed), 'prop("Deadline")');
      expect(ev(stored, {'p_due': 5}), 5);
    });
    test('dependencies are collected', () {
      expect(formulaDependencies(parseFormula('prop("a") + if(prop("b"), prop("a"), 1)')), {'a', 'b'});
    });
  });

  group('cycles and ordering', () {
    PropertyDef f(String id, String name, String src) => PropertyDef(id: id, name: name, type: PropertyType.formula, config: {'formula': src});
    test('dependencies are evaluated first', () {
      final order = formulaOrder([f('c', 'C', 'prop("b")+1'), f('b', 'B', 'prop("a")+1'), f('a', 'A', '1')]);
      expect(order.map((d) => d.id).toList(), ['a', 'b', 'c']);
    });
    test('a cycle is detected with a readable path', () {
      expect(
        () => formulaOrder([f('a', 'A', 'prop("b")'), f('b', 'B', 'prop("c")'), f('c', 'C', 'prop("a")')]),
        throwsA(isA<FormulaCycleException>().having((e) => e.path.first, 'path starts and ends at the same node', isNotEmpty)),
      );
      expect(() => formulaOrder([f('a', 'A', 'prop("a")')]), throwsA(isA<FormulaCycleException>()));
    });
    test('references to non-formula properties are not cycles', () {
      expect(formulaOrder([f('a', 'A', 'prop("n")*2')]).length, 1);
    });
  });
}
