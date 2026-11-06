import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/app/app.dart';
import 'package:folio/features/settings/rotation.dart';
import 'package:folio/features/tracker/data/tracker_repository.dart';
import 'package:tracker_engine/tracker_engine.dart' as te;

import '../features/tracker/tracker_ui_helpers.dart' show settle;
import '../helpers.dart';

void _size(WidgetTester t, double w, double h) {
  t.view.physicalSize = Size(w, h);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

class _FakeLock implements OrientationLock {
  final applied = <RotationMode>[];
  @override
  Future<void> apply(RotationMode mode) async => applied.add(mode);
}

/// A tracker like the one in the user's screenshot: a long name and several columns.
Future<String> _seed(WidgetTester t, TestEnv env) async => (await t.runAsync(() async {
      final repo = TrackerRepository(env.store);
      final tr = await repo.createTracker(name: 'Admissions 2026');
      final name = (await repo.properties(tr)).single.id;
      await repo.addProperty(tr, 'Status', te.PropertyType.status, config: te.Cfg.options(const [te.SelectOption(id: 'a', label: 'Applied'), te.SelectOption(id: 'b', label: 'Offer')]));
      await repo.addProperty(tr, 'Deadline', te.PropertyType.date);
      await repo.createRecord(tr, values: {name: 'University of Frankfurt'});
      await repo.createRecord(tr, values: {name: 'TU Munich'});
      return tr;
    }))!;

Future<void> _dispose(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 1));
}

void main() {
  group('portrait phone', () {
    testWidgets('the first columns after the name are visible without scrolling and labels stay on one line', (t) async {
      _size(t, 411, 890); // the user's phone
      final env = await TestEnv.create();
      addTearDown(env.db.close);
      await _seed(t, env);
      await t.pumpWidget(env.app);
      await t.pumpAndSettle();
      await t.tap(find.text('Goals').last);
      await settle(t);
      await t.tap(find.text('Admissions 2026'));
      await settle(t);
      expect(t.takeException(), isNull);
      expect(find.text('Admissions 2026'), findsWidgets);
      expect(t.getSize(find.text('Options')).height, lessThan(24), reason: '"Options" must not wrap onto two lines');
      expect(find.text('Name'), findsOneWidget);
      expect(find.text('Status'), findsOneWidget, reason: 'the second column header is on screen');
      expect(t.getTopLeft(find.text('Status')).dx, lessThan(411), reason: 'and inside the visible width, not hidden off to the right');
      // title not truncated by the record counter
      final title = t.getSize(find.text('Admissions 2026').first);
      expect(title.width, greaterThan(150));
      await _dispose(t);
    });
  });

  group('Back button', () {
    testWidgets('inside a tracker: back shows the tracker list; then Home; it never skips straight out of the app', (t) async {
      _size(t, 411, 890);
      final env = await TestEnv.create();
      addTearDown(env.db.close);
      await _seed(t, env);
      await t.pumpWidget(env.app);
      await t.pumpAndSettle();
      await t.tap(find.text('Goals').last);
      await settle(t);
      await t.tap(find.text('Admissions 2026'));
      await settle(t);
      expect(find.byKey(const Key('view-options')), findsOneWidget);

      await t.binding.handlePopRoute(); // Back #1: tracker -> tracker list
      await settle(t);
      expect(find.text('Trackers'), findsOneWidget);
      expect(find.byKey(const Key('view-options')), findsNothing);

      await t.binding.handlePopRoute(); // Back #2: Goals tab -> Home tab
      await settle(t);
      expect(find.text('Command Center'), findsOneWidget);
      await _dispose(t);
    });

    testWidgets('from another tab, back goes Home first', (t) async {
      _size(t, 411, 890);
      final env = await TestEnv.create();
      addTearDown(env.db.close);
      await t.pumpWidget(env.app);
      await t.pumpAndSettle();
      await t.tap(find.text('Library').last);
      await settle(t);
      expect(find.text('Library'), findsWidgets);
      await t.binding.handlePopRoute();
      await settle(t);
      expect(find.text('Command Center'), findsOneWidget);
      await _dispose(t);
    });
  });

  group('landscape phone (850 × 390)', () {
    testWidgets('every section fits: no overflow, navigation still reachable', (t) async {
      _size(t, 850, 390);
      final env = await TestEnv.create();
      addTearDown(env.db.close);
      await _seed(t, env);
      await t.pumpWidget(env.app);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      for (final dest in ['Library', 'Goals & Projects', 'Knowledge', 'Planner', 'Settings', 'Home']) {
        await t.tap(find.byTooltip(dest));
        await settle(t);
        expect(t.takeException(), isNull, reason: 'overflow on $dest');
      }
      await _dispose(t);
    });

    testWidgets('tracker uses a single slim toolbar and still leaves room for rows', (t) async {
      _size(t, 850, 390);
      final env = await TestEnv.create();
      addTearDown(env.db.close);
      await _seed(t, env);
      await t.pumpWidget(env.app);
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Goals & Projects'));
      await settle(t);
      await t.tap(find.text('Admissions 2026'));
      await settle(t);
      expect(t.takeException(), isNull);
      expect(find.text('University of Frankfurt'), findsOneWidget);
      expect(find.text('TU Munich'), findsOneWidget, reason: 'several rows visible at once in landscape');
      expect(find.byKey(const Key('view-switch')), findsOneWidget);
      // search toggles open
      await t.tap(find.byKey(const Key('toggle-search')));
      await settle(t);
      expect(find.byKey(const Key('tracker-search')), findsOneWidget);
      // the dialogs still fit in 390 px of height
      await t.tap(find.byTooltip('Add property').first);
      await settle(t);
      expect(find.text('New property'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.tap(find.text('Cancel'));
      await settle(t);
      await t.tap(find.byKey(const Key('view-options')));
      await settle(t);
      expect(find.text('View options'), findsOneWidget);
      expect(t.takeException(), isNull);
      await _dispose(t);
    });
  });

  group('rotation setting', () {
    testWidgets('Settings → Display lets the user lock the app to portrait; it is applied and remembered', (t) async {
      _size(t, 411, 890);
      final env = await TestEnv.create();
      addTearDown(env.db.close);
      final lock = _FakeLock();
      await t.pumpWidget(ProviderScope(overrides: [...env.overrides, orientationLockProvider.overrideWithValue(lock)], child: const FolioApp()));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Settings'));
      await settle(t);
      expect(find.text('Screen rotation'), findsOneWidget);
      await t.tap(find.text('Portrait'));
      await settle(t);
      expect(lock.applied, [RotationMode.portrait]);
      expect(await t.runAsync(() => env.store.state('rotation_mode')), 'portrait');
      await t.tap(find.text('Auto'));
      await settle(t);
      expect(lock.applied.last, RotationMode.auto);
      expect(await t.runAsync(() => loadRotationMode(env.store.state)), RotationMode.auto);
      await _dispose(t);
    });
  });
}
