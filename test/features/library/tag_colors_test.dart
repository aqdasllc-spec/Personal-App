import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/features/library/domain_tag_colors.dart';

import 'library_filter_ui_test.dart' show open, openSheet, io, end;

void main() {
  group('domain', () {
    test('palette has 8 distinct colours with names', () {
      expect(tagPalette.length, 8);
      expect({for (final p in tagPalette) p.$2}.length, 8);
      expect({for (final p in tagPalette) p.$1}.length, 8);
    });

    test('round trip ignores case; bad data and out-of-range colours are dropped', () {
      final m = decodeTagColors(encodeTagColors({'work': 3, 'safety': 5}));
      expect(m, {'work': 3, 'safety': 5});
      expect(colorOfTag(m, ' WORK '), tagPalette[3].$2);
      expect(colorNameOfTag(m, 'safety'), 'Blue');
      expect(colorOfTag(m, 'none'), isNull);
      expect(decodeTagColors('nonsense'), isEmpty);
      expect(decodeTagColors(null), isEmpty);
      expect(decodeTagColors('{"a":99,"b":-1,"c":"x","d":2}'), {'d': 2});
    });
  });

  group('library', () {
    testWidgets('pick a colour in Manage tags: it shows on the filter chip, is remembered, follows a rename, can be cleared', (t) async {
      final (env, _) = await open(t);
      await openSheet(t);
      expect(find.byKey(const Key('tag-dot-work')), findsNothing);
      await t.tap(find.byKey(const Key('manage-tags')));
      await io(t);
      await t.tap(find.byKey(const Key('tag-color-work')));
      await io(t, rounds: 3);
      await t.tap(find.byKey(const Key('tag-color-5')));
      await io(t, rounds: 3);
      expect(find.byKey(const Key('tag-dot-work')), findsWidgets); // filter chip and manager row
      final saved = await t.runAsync(() => env.store.state('tag_colors'));
      expect(saved, '{"work":5}');

      // rename keeps the colour
      await t.tap(find.byKey(const Key('tag-rename-work')));
      await io(t, rounds: 3);
      await t.enterText(find.byKey(const Key('name-field')), 'Job');
      await t.tap(find.byKey(const Key('name-ok')));
      await io(t);
      expect(find.byKey(const Key('tag-dot-job')), findsWidgets);
      expect(find.byKey(const Key('tag-dot-work')), findsNothing);

      // clear
      await t.tap(find.byKey(const Key('tag-color-Job')));
      await io(t, rounds: 3);
      await t.tap(find.byKey(const Key('tag-color-none')));
      await io(t, rounds: 3);
      expect(find.byKey(const Key('tag-dot-job')), findsNothing);
      await end(t);
    });
  });
}
