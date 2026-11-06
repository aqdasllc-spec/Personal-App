import 'package:sync_engine/sync_engine.dart';
import 'package:test/test.dart';

void main() {
  group('resolve', () {
    const k = FieldKey('cells', 'r1:p1', 'value');
    Change ch(String v, Hlc h, Hlc? base) => Change(key: k, value: v, hlc: h, baseHlc: base, deviceId: 'd', changeId: v);
    const h1 = Hlc(1, 0, 'a'), h2 = Hlc(2, 0, 'b'), h3 = Hlc(3, 0, 'a');

    test('first write accepted', () => expect(resolve(null, ch('x', h1, null)).accept, isTrue));
    test('causal successor accepted without conflict', () {
      final r = resolve(const Versioned('x', h1), ch('y', h2, h1));
      expect(r.accept, isTrue);
      expect(r.conflict, isNull);
    });
    test('unknown base against an existing value is concurrent, loser preserved', () {
      final r = resolve(const Versioned('x', h1), ch('y', h2, null));
      expect(r.accept, isTrue);
      expect(r.conflict!.lostValue, 'x');
    });
    test('older concurrent edit is rejected but preserved', () {
      final r = resolve(const Versioned('new', h3), ch('old', h2, h1));
      expect(r.accept, isFalse);
      expect(r.conflict!.lostValue, 'old');
      expect(r.conflict!.winnerHlc, h3);
    });
    test('same hlc is a duplicate', () => expect(resolve(const Versioned('x', h1), ch('x', h1, null)).duplicate, isTrue));
  });

  group('mergeSets', () {
    test('independent adds and removes combine', () {
      final r = mergeSets({'a', 'b'}, {'a', 'b', 'c'}, {'a'});
      expect(r.merged, {'a', 'c'});
    });
    test('add wins over untouched', () => expect(mergeSets({}, {'x'}, {'y'}).merged, {'x', 'y'}));
    test('both removed', () => expect(mergeSets({'a'}, <String>{}, <String>{}).merged, isEmpty));
  });

  group('mergeText', () {
    const base = 'one\ntwo\nthree\nfour\nfive';
    test('identical / one-sided changes', () {
      expect(mergeText(base, base, 'x').merged, 'x');
      expect(mergeText(base, 'x', base).merged, 'x');
      expect(mergeText(base, 'x', 'x').merged, 'x');
    });
    test('edits in different places merge cleanly', () {
      final r = mergeText(base, 'ONE\ntwo\nthree\nfour\nfive', 'one\ntwo\nthree\nfour\nFIVE');
      expect(r.conflict, isFalse);
      expect(r.merged, 'ONE\ntwo\nthree\nfour\nFIVE');
    });
    test('insertions far apart merge', () {
      final r = mergeText(base, 'zero\none\ntwo\nthree\nfour\nfive', 'one\ntwo\nthree\nfour\nfive\nsix');
      expect(r.merged, 'zero\none\ntwo\nthree\nfour\nfive\nsix');
    });
    test('both sides edit the same line differently -> conflict keeps both', () {
      final r = mergeText(base, 'one\nTWO-L\nthree\nfour\nfive', 'one\nTWO-R\nthree\nfour\nfive');
      expect(r.conflict, isTrue);
      expect(r.local, contains('TWO-L'));
      expect(r.remote, contains('TWO-R'));
    });
    test('both sides make the same edit -> clean, not duplicated', () {
      final e = 'one\nTWO\nthree\nfour\nfive';
      expect(mergeText(base, e, '$e\n'.trimRight()).merged, e);
    });
    test('delete vs edit of same line conflicts', () {
      expect(mergeText(base, 'one\nthree\nfour\nfive', 'one\nTWO\nthree\nfour\nfive').conflict, isTrue);
    });
    test('no text is ever lost: merged result contains every non-conflicting edit', () {
      final r = mergeText('a\nb\nc\nd\ne\nf', 'a\nB\nc\nd\ne\nf', 'a\nb\nc\nd\nE\nf');
      expect(r.merged, 'a\nB\nc\nd\nE\nf');
    });
  });
}
