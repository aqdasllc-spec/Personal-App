import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/library/reader_settings_test.dart' show io;
import '../helpers.dart';

/// Automated checks only: no overflow at 2x text, in light and dark, and every tap target is
/// big enough and labelled. This does not replace trying the app with TalkBack.
void main() {
  for (final dark in [false, true]) {
    // Settings still overflows at 2x text (known; see the roadmap), so it is not audited yet.
    for (final tab in ['Home', 'Library', 'Planner']) {
      testWidgets(
        '$tab: ${dark ? 'dark' : 'light'}, text 2x, targets labelled and big enough',
        (t) async {
          t.view.physicalSize = const Size(411, 890);
          t.view.devicePixelRatio = 1;
          t.platformDispatcher.textScaleFactorTestValue = 2.0;
          t.platformDispatcher.platformBrightnessTestValue = dark
              ? Brightness.dark
              : Brightness.light;
          addTearDown(() {
            t.view.reset();
            t.platformDispatcher.clearAllTestValues();
          });
          final env = await TestEnv.create();
          addTearDown(env.db.close);
          final handle = t.ensureSemantics();
          await t.pumpWidget(env.app);
          await io(t);
          if (tab != 'Home') {
            await t.tap(
              find.descendant(
                of: find.byType(NavigationBar),
                matching: find.text(tab),
              ),
            );
            await io(t);
          }
          expect(
            t.takeException(),
            isNull,
            reason: 'no overflow or error at 2x text',
          );
          await expectLater(t, meetsGuideline(androidTapTargetGuideline));
          await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
          handle.dispose();
          await t.pumpWidget(const SizedBox());
          await t.pump(const Duration(seconds: 1));
        },
      );
    }
  }
}
