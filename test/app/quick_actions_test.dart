import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/app/quick_actions.dart';
import 'package:folio/features/library/data/library_repository.dart';

import '../features/library/reader_settings_test.dart' show io;
import '../helpers.dart';

void quickTest(String name, Future<void> Function(WidgetTester) body) =>
    testWidgets(name, (t) async {
      await body(t);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
    });

void main() {
  test('the four shortcuts have unique types and readable names', () {
    expect(QuickAction.values.map((a) => a.type).toSet().length, 4);
    expect(QuickAction.of('add_task'), QuickAction.addTask);
    expect(QuickAction.of('nope'), isNull);
    expect(QuickAction.values.map((a) => a.label), ['Continue reading', 'Add a task', 'Planner: today', 'Library']);
  });

  Future<TestEnv> boot(WidgetTester t, {bool withBook = false}) async {
    t.view.physicalSize = const Size(411, 890);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final env = await TestEnv.create();
    addTearDown(env.db.close);
    if (withBook) {
      await t.runAsync(() async {
        final repo = LibraryRepository(env.db, directory: env.libraryDir, inspector: FakePdfInspector());
        final b = (await repo.importPdf(await env.writePdf('x.pdf', 5))).book!;
        await repo.markOpened(b.id);
      });
    }
    await t.pumpWidget(env.app);
    await io(t);
    return env;
  }

  quickTest('shortcuts are registered when the app starts', (t) async {
    final env = await boot(t);
    expect(env.quick.items, QuickAction.values);
    expect(env.quick.tap, isNotNull);
  });

  quickTest('Planner: today and Library open those tabs', (t) async {
    final env = await boot(t);
    env.quick.tap!('today');
    await io(t, rounds: 3);
    expect(find.byKey(const Key('planner-quick-add')), findsWidgets);
    env.quick.tap!('library');
    await io(t, rounds: 3);
    expect(find.byKey(const Key('planner-quick-add')), findsNothing);
  });

  quickTest('Add a task goes Home and puts the cursor in the quick-add box', (t) async {
    final env = await boot(t);
    env.quick.tap!('library');
    await io(t, rounds: 3);
    env.quick.tap!('add_task');
    await io(t, rounds: 3);
    final field = t.widget<TextField>(find.byKey(const Key('home-quick-add')));
    expect(field.focusNode!.hasFocus, isTrue);
  });

  quickTest('Continue reading opens the book you read last', (t) async {
    final env = await boot(t, withBook: true);
    env.quick.tap!('continue');
    await io(t, rounds: 4);
    expect(find.textContaining('PDF view page'), findsOneWidget);
  });

  quickTest('Continue reading with nothing opened yet just shows the Library', (t) async {
    final env = await boot(t);
    env.quick.tap!('continue');
    await io(t, rounds: 3);
    expect(find.textContaining('PDF view page'), findsNothing);
  });
}
