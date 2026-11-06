import 'package:flutter_test/flutter_test.dart';
import 'package:folio/features/library/domain_highlights.dart';

void main() {
  test('character boxes merge into one bar per line; characters without a box are skipped', () {
    // line 1 (y 100..90): three chars, a zero-size "space", one more; line 2 (y 80..70): two chars
    final chars = [
      [10.0, 100.0, 15.0, 90.0],
      [15.0, 100.0, 20.0, 90.0],
      [20.0, 100.0, 20.0, 90.0], // space with no width
      [22.0, 101.0, 30.0, 91.0],
      [10.0, 80.0, 16.0, 70.0],
      [16.0, 80.0, 24.0, 70.0],
    ];
    expect(lineRectsOf(chars), [
      [10.0, 101.0, 30.0, 90.0],
      [10.0, 80.0, 24.0, 70.0],
    ]);
    expect(lineRectsOf(const []), isEmpty);
    expect(lineRectsOf([[1.0, 5.0, 2.0, 1.0]]), [[1.0, 5.0, 2.0, 1.0]]);
  });

  test('rects survive encoding; garbage decodes to nothing; colours cycle', () {
    final r = [[1.5, 9.0, 4.0, 2.0], [0.0, 20.0, 3.0, 10.0]];
    expect(decodeRects(encodeRects(r)), r);
    expect(decodeRects('not json'), isEmpty);
    expect(decodeRects('[[1,2,3]]'), isEmpty);
    var c = 'yellow';
    final seen = <String>[];
    for (var i = 0; i < 4; i++) {
      c = nextHighlightColor(c);
      seen.add(c);
    }
    expect(seen, ['green', 'blue', 'pink', 'yellow']);
    expect(nextHighlightColor('unknown'), 'yellow', reason: 'an unknown colour starts over');
    expect(highlightColor('pink'), isNot(highlightColor('yellow')));
  });
}
