import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/features/library/domain_smart_views.dart';

import 'library_filter_ui_test.dart' show open, openSheet, io, end;

void main() {
  group('domain', () {
    test('round trip; bad data and bad entries are skipped', () {
      final v = [const SmartView(name: 'Work', status: 'unread', tags: ['work', 'safety'], sort: 'title')];
      final back = decodeViews(encodeViews(v)).single;
      expect((back.name, back.status, back.sort), ('Work', 'unread', 'title'));
      expect(back.tags, ['work', 'safety']);
      expect(decodeViews('nonsense'), isEmpty);
      expect(decodeViews(null), isEmpty);
      expect(decodeViews('[{"n":""},{"x":1},{"n":"Ok","t":[1,"a"]}]').map((x) => '${x.name}:${x.tags.join(',')}'), ['Ok:a']);
    });

    test('saving under an existing name (any case) replaces; long names are cut; the oldest drops past the limit', () {
      var v = withView(const [], const SmartView(name: 'Work', tags: ['a']));
      v = withView(v, const SmartView(name: '  work ', tags: ['b']));
      expect(v.map((x) => '${x.name}:${x.tags.join(',')}'), ['work:b']);
      v = withView(v, SmartView(name: 'x' * 50));
      expect(v.last.name.length, maxViewNameLength);
      for (var i = 0; i < 25; i++) {
        v = withView(v, SmartView(name: 'v$i'));
      }
      expect(v.length, maxSmartViews);
      expect(v.last.name, 'v24');
      expect(v.any((x) => x.name == 'work'), isFalse, reason: 'oldest dropped');
    });

    test('renaming or deleting a tag updates the views that use it', () {
      const views = [SmartView(name: 'A', tags: ['Work', 'safety'])];
      expect(renameTagInViews(views, 'work', 'Job').single.tags, ['Job', 'safety']);
      expect(dropTagFromViews(views, 'WORK').single.tags, ['safety']);
    });
  });

  group('library', () {
    testWidgets('save the current filters as a view, clear them, apply the view, delete it; it is remembered', (t) async {
      final (env, _) = await open(t);
      await openSheet(t);
      expect(t.widget<TextButton>(find.byKey(const Key('save-view'))).onPressed, isNull, reason: 'nothing to save yet');
      await t.tap(find.byKey(const Key('tag-filter-work')));
      await io(t);
      await t.tap(find.byKey(const Key('save-view')));
      await io(t, rounds: 3);
      await t.enterText(find.byKey(const Key('name-field')), 'Work stuff');
      await t.tap(find.byKey(const Key('name-ok')));
      await io(t, rounds: 3);
      expect(find.byKey(const Key('view-Work stuff')), findsOneWidget);
      expect(await t.runAsync(() => env.store.state('smart_views')), contains('Work stuff'));

      await t.tap(find.byKey(const Key('sheet-clear')));
      await io(t);
      expect(find.byKey(const Key('active-tag-work')), findsNothing);
      await t.tap(find.byKey(const Key('view-Work stuff')));
      await io(t);
      expect(find.byKey(const Key('active-tag-work')), findsOneWidget, reason: 'the view brought the tag filter back');

      await t.tap(find.byTooltip('Delete view Work stuff'));
      await io(t);
      expect(find.byKey(const Key('view-Work stuff')), findsNothing);
      await end(t);
    });
  });
}
