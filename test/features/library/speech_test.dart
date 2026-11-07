import 'package:flutter_test/flutter_test.dart';
import 'package:folio/features/library/application/read_aloud.dart';
import '../../helpers.dart';
import 'package:folio/features/library/domain_speech.dart';

void main() {
  group('chunkText', () {
    test('blank text gives nothing; short text is one piece with tidy spacing', () {
      expect(chunkText('   \n '), isEmpty);
      expect(chunkText('Hello   world.\n\n  Next line'), ['Hello world.\nNext line']);
    });

    test('long text is cut after a sentence end, every piece within the limit, nothing lost', () {
      final text = List.generate(40, (i) => 'Sentence number $i is here.').join(' ');
      final parts = chunkText(text, max: 200);
      expect(parts.length, greaterThan(3));
      expect(parts.every((p) => p.length <= 200), isTrue);
      expect(parts.every((p) => p.endsWith('.')), isTrue, reason: 'cut at sentence ends');
      expect(parts.join(' '), text);
    });

    test('a very long word with no spaces is still cut', () {
      final parts = chunkText('x' * 450, max: 200);
      expect(parts.map((p) => p.length), [200, 200, 50]);
    });
  });

  group('ReadAloud', () {
    late FakeSpeechEngine engine;
    late List<int> turned;
    ReadAloud make(Map<int, String?> pages, {int count = 4}) {
      engine = FakeSpeechEngine();
      turned = [];
      return ReadAloud(engine: engine, textOf: (p) async => pages[p], goTo: turned.add, pageCount: () => count);
    }

    test('reads page after page, turning the page, and says when the book is finished', () async {
      final r = make({1: 'One.', 2: 'Two.', 3: 'Three.', 4: 'Four.'});
      await r.start(2);
      expect(engine.spoken, ['Two.', 'Three.', 'Four.']);
      expect(turned, [2, 3, 4]);
      expect(r.state.value.playing, isFalse);
      expect(r.state.value.message, 'Finished the book.');
    });

    test('pages without text are skipped; three blank pages in a row stop it with a hint', () async {
      final r = make({1: 'One.', 2: null, 3: '  ', 4: 'Four.'});
      await r.start(1);
      expect(engine.spoken, ['One.', 'Four.']);
      final r2 = make({1: null, 2: null, 3: null, 4: 'Four.'});
      await r2.start(1);
      expect(engine.spoken, isEmpty);
      expect(r2.state.value.message, contains('Make searchable'));
      expect(r2.state.value.playing, isFalse);
    });

    test('pause stops talking; resume carries on from that page; stop closes the bar', () async {
      final r = make({1: 'One.', 2: 'Two.', 3: 'Three.', 4: 'Four.'});
      final run = r.start(1);
      await Future<void>.delayed(Duration.zero);
      await r.pause();
      await run;
      expect(r.state.value.playing, isFalse);
      expect(r.state.value.active, isTrue);
      final before = engine.spoken.length;
      await r.resume();
      expect(engine.spoken.length, greaterThan(before));
      await r.stop();
      expect(r.state.value.active, isFalse);
    });

    test('changing the speed restarts the current page at the new speed and is remembered after stopping', () async {
      final r = make({1: 'One.'}, count: 1);
      await r.start(1);
      await r.setRate(1.5);
      expect(engine.rates, [1.5]);
      await r.stop();
      expect(r.state.value.rate, 1.5);
    });

    test('the user jumping to another page while reading makes it follow; our own page turns do not', () async {
      final r = make({1: 'One.', 2: 'Two.', 3: 'Three.', 4: 'Four.'});
      final run = r.start(1);
      await Future<void>.delayed(Duration.zero);
      r.pageChanged(1); // same page: ignored
      expect(engine.spoken.where((s) => s == 'One.').length, 1);
      r.pageChanged(4); // jump
      await run;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(engine.spoken.last, 'Four.');
    });
  });
}
