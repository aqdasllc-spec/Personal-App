import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/app/app.dart';
import 'package:folio/features/settings/rotation.dart';

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

Future<void> _dispose(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 1));
}

void main() {
  group('portrait phone', () {
    testWidgets('bottom bar shows exactly Home, Library, Planner, Settings', (t) async {
      _size(t, 411, 890);
      final env = await TestEnv.create();
      addTearDown(env.db.close);
      await t.pumpWidget(env.app);
      await t.pumpAndSettle();
      expect(find.byType(NavigationDestination), findsNWidgets(4));
      for (final label in ['Home', 'Library', 'Planner', 'Settings']) {
        expect(find.descendant(of: find.byType(NavigationBar), matching: find.text(label)), findsOneWidget, reason: label);
      }
      expect(find.text('Goals'), findsNothing);
      expect(find.text('Knowledge'), findsNothing);
      expect(t.takeException(), isNull);
      await _dispose(t);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
    });
  });

  group('Back button', () {
    for (final tab in ['Library', 'Planner', 'Settings']) {
      testWidgets('from $tab, back goes to Home first', (t) async {
        _size(t, 411, 890);
        final env = await TestEnv.create();
        addTearDown(env.db.close);
        await t.pumpWidget(env.app);
        await t.pumpAndSettle();
        await t.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(tab)));
        await settle(t);
        expect(find.byKey(const Key('home-quick-add')), findsNothing);
        await t.binding.handlePopRoute();
        await settle(t);
        expect(find.byKey(const Key('home-quick-add')), findsOneWidget);
        await _dispose(t);
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 1));
      });
    }
  });

  group('landscape phone (850 × 390)', () {
    testWidgets('every section fits: no overflow, navigation still reachable', (t) async {
      _size(t, 850, 390);
      final env = await TestEnv.create();
      addTearDown(env.db.close);
      await t.pumpWidget(env.app);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      for (final dest in ['Library', 'Planner', 'Settings', 'Home']) {
        await t.tap(find.byTooltip(dest));
        await settle(t);
        expect(t.takeException(), isNull, reason: 'overflow on $dest');
      }
      await _dispose(t);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
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
      await t.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Settings')));
      await settle(t);
      await t.scrollUntilVisible(find.text('Screen rotation'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('Screen rotation'), findsOneWidget);
      await t.ensureVisible(find.text('Portrait'));
      await t.pump();
      await t.tap(find.text('Portrait'));
      await settle(t);
      expect(lock.applied, [RotationMode.portrait]);
      expect(await t.runAsync(() => env.store.state('rotation_mode')), 'portrait');
      await t.tap(find.text('Auto'));
      await settle(t);
      expect(lock.applied.last, RotationMode.auto);
      expect(await t.runAsync(() => loadRotationMode(env.store.state)), RotationMode.auto);
      await _dispose(t);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
    });
  });
}
