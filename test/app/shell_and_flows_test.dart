import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/design_system/tokens.dart';
import 'package:folio/features/auth/auth_repository.dart';

import '../helpers.dart';

void _size(WidgetTester t, double w, double h) {
  t.view.physicalSize = Size(w, h);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

const _signedIn = SignedInSession(userId: 'u', email: 'sam@example.com');

void main() {
  group('adaptive navigation', () {
    testWidgets('expanded: sidebar with the four sections, no rail or bottom bar', (t) async {
      final sem = t.ensureSemantics();
      _size(t, 1400, 900);
      final env = await TestEnv.create();
      await t.pumpWidget(env.app);
      await t.pumpAndSettle();
      expect(find.byType(NavigationRail), findsNothing);
      expect(find.byType(NavigationBar), findsNothing);
      for (final label in ['Home', 'Library', 'Planner', 'Settings']) {
        expect(find.bySemanticsLabel(label), findsWidgets, reason: label);
      }
      await t.tap(find.bySemanticsLabel('Library').first);
      await t.pumpAndSettle();
      expect(find.text('Your library is empty'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
      sem.dispose();
    });

    testWidgets('medium: navigation rail', (t) async {
      _size(t, 800, 900);
      final env = await TestEnv.create();
      await t.pumpWidget(env.app);
      await t.pumpAndSettle();
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('compact: bottom bar with the four sections including Settings', (t) async {
      _size(t, 400, 800);
      final env = await TestEnv.create();
      await t.pumpWidget(env.app);
      await t.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationDestination), findsNWidgets(4));
      expect(find.text('Goals'), findsNothing, reason: 'Goals & Projects was removed');
      expect(find.text('Knowledge'), findsNothing);
      await t.tap(find.text('Settings').last);
      await t.pumpAndSettle();
      await t.scrollUntilVisible(find.text('App lock'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('App lock'), findsOneWidget);
      expect(find.text('Local only'), findsWidgets);
    });

    testWidgets('dark theme renders the shell without errors', (t) async {
      _size(t, 1400, 900);
      t.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(t.platformDispatcher.clearPlatformBrightnessTestValue);
      final env = await TestEnv.create();
      await t.pumpWidget(env.app);
      await t.pumpAndSettle();
      final ctx = t.element(find.byType(Scaffold).first);
      expect(Theme.of(ctx).brightness, Brightness.dark);
      expect(ctx.colors.bg, FolioColors.dark.bg);
      expect(t.takeException(), isNull);
    });
  });

  group('sign-in flow', () {
    testWidgets('signed-out users see sign-in and cannot skip validation', (t) async {
      _size(t, 1000, 900);
      final env = await TestEnv.create(session: const SignedOutSession());
      await t.pumpWidget(env.app);
      await t.pumpAndSettle();
      expect(find.text('Welcome back'), findsOneWidget);
      await t.tap(find.text('Sign in'));
      await t.pumpAndSettle();
      expect(find.text('Enter your email address.'), findsOneWidget);
      expect(env.auth.calls, isEmpty);
    });

    testWidgets('successful sign-in lands on Home', (t) async {
      _size(t, 1400, 900);
      final env = await TestEnv.create(session: const SignedOutSession());
      await t.pumpWidget(env.app);
      await t.pumpAndSettle();
      await t.enterText(find.widgetWithText(TextFormField, 'Email'), 'sam@example.com');
      await t.enterText(find.widgetWithText(TextFormField, 'Password'), 'hunter2');
      await t.tap(find.text('Sign in'));
      await t.pumpAndSettle();
      expect(env.auth.calls, ['signIn:sam@example.com']);
      expect(find.text('Command Center'), findsOneWidget);
    });

    testWidgets('server failure is shown in plain language and stays on the page', (t) async {
      _size(t, 1000, 900);
      final env = await TestEnv.create(session: const SignedOutSession());
      env.auth.failWith = AuthFailure(AuthFailureKind.invalidCredentials, 'Email or password is incorrect.');
      await t.pumpWidget(env.app);
      await t.pumpAndSettle();
      await t.enterText(find.widgetWithText(TextFormField, 'Email'), 'sam@example.com');
      await t.enterText(find.widgetWithText(TextFormField, 'Password'), 'wrong');
      await t.tap(find.text('Sign in'));
      await t.pumpAndSettle();
      expect(find.text('Email or password is incorrect.'), findsOneWidget);
      expect(find.text('Welcome back'), findsOneWidget);
    });

    testWidgets('sign-up enforces the password policy and explains email confirmation', (t) async {
      _size(t, 1000, 900);
      final env = await TestEnv.create(session: const SignedOutSession());
      env.auth.confirmationRequired = true;
      await t.pumpWidget(env.app);
      await t.pumpAndSettle();
      await t.tap(find.text('Create an account'));
      await t.pumpAndSettle();
      await t.enterText(find.widgetWithText(TextFormField, 'Email'), 'sam@example.com');
      await t.enterText(find.widgetWithText(TextFormField, 'Password'), 'weak');
      await t.tap(find.text('Create account'));
      await t.pumpAndSettle();
      expect(find.text('Use at least 10 characters.'), findsOneWidget);
      expect(env.auth.calls, isEmpty);
      await t.enterText(find.widgetWithText(TextFormField, 'Password'), 'Correct7Horse');
      await t.tap(find.text('Create account'));
      await t.pumpAndSettle();
      expect(find.textContaining('Check your inbox'), findsOneWidget);
    });

    testWidgets('"Use without an account" enters the app in local-only mode', (t) async {
      _size(t, 1400, 900);
      final env = await TestEnv.create(session: const SignedOutSession());
      await t.pumpWidget(env.app);
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Use without an account'));
      await t.tap(find.text('Use without an account'));
      await t.pumpAndSettle();
      expect(find.text('Command Center'), findsOneWidget);
    });

    testWidgets('signing out from Settings returns to sign-in', (t) async {
      final sem = t.ensureSemantics();
      _size(t, 1400, 900);
      final env = await TestEnv.create(session: _signedIn);
      await t.pumpWidget(env.app);
      await t.pumpAndSettle();
      await t.tap(find.bySemanticsLabel('Settings').first);
      await t.pumpAndSettle();
      await t.tap(find.text('Sign out'));
      await t.pumpAndSettle();
      expect(find.text('Welcome back'), findsOneWidget);
      sem.dispose();
    });
  });

  group('app lock screen', () {
    testWidgets('locked app shows only the lock screen and unlocks on success', (t) async {
      _size(t, 1000, 900);
      final env = await TestEnv.create(lockEnabled: true);
      await t.pumpWidget(env.app);
      await t.pumpAndSettle();
      expect(find.text('Folio is locked'), findsOneWidget);
      expect(find.text('Command Center'), findsNothing, reason: 'content must not be visible while locked');
      env.authenticator.succeed = false;
      await t.tap(find.text('Unlock'));
      await t.pumpAndSettle();
      expect(find.textContaining('Couldn\'t verify'), findsOneWidget);
      env.authenticator.succeed = true;
      await t.tap(find.text('Unlock'));
      await t.pumpAndSettle();
      expect(find.text('Command Center'), findsOneWidget);
    });
  });

  group('design tokens', () {
    double lum(Color c) {
      double ch(double v) => v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4).toDouble();
      return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
    }

    double ratio(Color a, Color b) {
      final l1 = lum(a), l2 = lum(b);
      return (l1 > l2 ? l1 + .05 : l2 + .05) / (l1 > l2 ? l2 + .05 : l1 + .05);
    }

    for (final (name, c) in [('light', FolioColors.light), ('dark', FolioColors.dark)]) {
      test('$name: body text >= 7:1; muted/accent/status text >= 4.5:1 on their surfaces', () {
        expect(ratio(c.text, c.bg), greaterThanOrEqualTo(7), reason: 'text on bg');
        expect(ratio(c.text, c.surface), greaterThanOrEqualTo(7), reason: 'text on surface');
        expect(ratio(c.textMuted, c.bg), greaterThanOrEqualTo(4.5), reason: 'muted on bg');
        expect(ratio(c.textMuted, c.surface), greaterThanOrEqualTo(4.5), reason: 'muted on surface');
        expect(ratio(c.accent, c.surface), greaterThanOrEqualTo(4.5), reason: 'accent on surface');
        expect(ratio(c.onAccent, c.accent), greaterThanOrEqualTo(4.5), reason: 'button label');
        expect(ratio(c.accent, c.accentSoft), greaterThanOrEqualTo(4.5), reason: 'selected nav item');
        for (final s in [c.danger, c.warn, c.ok, c.info]) {
          expect(ratio(s, c.surface), greaterThanOrEqualTo(3), reason: 'status colour as graphic');
        }
      });
    }
  });
}
