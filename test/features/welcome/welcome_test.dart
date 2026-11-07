import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/features/welcome/welcome_page.dart';

import '../../helpers.dart';

Future<void> io(WidgetTester t, {int rounds = 8}) async {
  for (var i = 0; i < rounds; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    for (var k = 0; k < 3; k++) {
      await t.pump(const Duration(milliseconds: 60));
    }
  }
  await t.pump(const Duration(milliseconds: 300));
}

Future<void> end(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets('first launch: the tour opens over Home, Next walks through, Get started closes it and it never returns', (t) async {
    t.view.physicalSize = const Size(411, 890);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final env = await TestEnv.create(showWelcome: true);
    addTearDown(env.db.close);
    await t.pumpWidget(env.app);
    await io(t);
    expect(find.text('Welcome to Folio'), findsOneWidget);
    expect(find.byKey(const Key('welcome-back')), findsNothing, reason: 'nothing before the first screen');
    for (final title in ['Your library', 'Plan your days', 'Yours to keep']) {
      await t.tap(find.byKey(const Key('welcome-next')));
      await io(t, rounds: 4);
      expect(find.text(title), findsOneWidget);
    }
    expect(find.text('Get started'), findsOneWidget);
    await t.tap(find.byKey(const Key('welcome-back')));
    await io(t, rounds: 4);
    expect(find.text('Plan your days'), findsOneWidget);
    await t.tap(find.byKey(const Key('welcome-next')));
    await io(t, rounds: 4);
    await t.tap(find.byKey(const Key('welcome-next')));
    await io(t, rounds: 4);
    expect(find.text('Welcome to Folio'), findsNothing);
    expect(find.byKey(const Key('home-quick-add')), findsOneWidget, reason: 'back on Home');
    expect(await t.runAsync(() => env.store.state('welcome_done')), '1');
    await end(t);
  });

  testWidgets('Skip also counts as seen', (t) async {
    t.view.physicalSize = const Size(411, 890);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final env = await TestEnv.create(showWelcome: true);
    addTearDown(env.db.close);
    await t.pumpWidget(env.app);
    await io(t);
    await t.tap(find.byKey(const Key('welcome-skip')));
    await io(t, rounds: 4);
    expect(find.text('Welcome to Folio'), findsNothing);
    expect(await t.runAsync(() => env.store.state('welcome_done')), '1');
    await end(t);
  });

  testWidgets('a returning user (already seen) goes straight to Home', (t) async {
    t.view.physicalSize = const Size(411, 890);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final env = await TestEnv.create();
    addTearDown(env.db.close);
    await t.pumpWidget(env.app);
    await io(t);
    expect(find.text('Welcome to Folio'), findsNothing);
    expect(find.byKey(const Key('home-quick-add')), findsOneWidget);
    await end(t);
  });

  testWidgets('every screen fits a small landscape phone without overflow', (t) async {
    t.view.physicalSize = const Size(850, 390);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final env = await TestEnv.create(showWelcome: true);
    addTearDown(env.db.close);
    await t.pumpWidget(env.app);
    await io(t);
    for (var i = 0; i < welcomeSteps.length - 1; i++) {
      await t.tap(find.byKey(const Key('welcome-next')));
      await io(t, rounds: 3);
    }
    expect(t.takeException(), isNull);
    await end(t);
  });

  testWidgets('Settings -> Help reopens the tour and lists the tips', (t) async {
    t.view.physicalSize = const Size(411, 890);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final env = await TestEnv.create();
    addTearDown(env.db.close);
    await t.pumpWidget(env.app);
    await io(t);
    await t.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Settings')));
    await io(t);
    await t.scrollUntilVisible(find.byKey(const Key('settings-tips')), 300, scrollable: find.byType(Scrollable).first);
    await t.ensureVisible(find.byKey(const Key('settings-tips')));
    await t.pump();
    await t.tap(find.byKey(const Key('settings-tips')));
    await io(t, rounds: 3);
    expect(find.textContaining('Press and hold a book'), findsOneWidget);
    await t.ensureVisible(find.byKey(const Key('settings-welcome')));
    await t.pump();
    await t.tap(find.byKey(const Key('settings-welcome')));
    await io(t, rounds: 4);
    expect(find.text('Welcome to Folio'), findsOneWidget);
    await t.tap(find.byKey(const Key('welcome-skip')));
    await io(t, rounds: 4);
    expect(find.text('Welcome to Folio'), findsNothing);
    await end(t);
  });
}
