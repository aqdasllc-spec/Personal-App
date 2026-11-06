import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/app/providers.dart';
import 'package:folio/design_system/option_colors.dart';
import 'package:folio/design_system/theme.dart';
import 'package:folio/features/tracker/application/tracker_controller.dart';
import 'package:folio/features/tracker/presentation/trackers_page.dart';
import 'package:tracker_engine/tracker_engine.dart' as te;
import 'package:two_dimensional_scrollables/two_dimensional_scrollables.dart' show TableView;

import 'tracker_helpers.dart';
import 'tracker_ui_helpers.dart';

void main() {
  late Env env;
  setUp(() async => env = await Env.create());
  tearDown(() => env.close());

  /// Tracker with three rows. Row order: Write intro, Read paper, File taxes.
  Future<({String tracker, Map<String, String> p, List<String> ids})> seed(WidgetTester t) async => (await t.runAsync(() async {
        final x = await env.taskTracker();
        final ids = [
          await env.repo.createRecord(x.tracker, values: {x.p['name']!: 'Write intro', x.p['hours']!: 3.5, x.p['status']!: 'doing', x.p['done']!: false}),
          await env.repo.createRecord(x.tracker, values: {x.p['name']!: 'Read paper', x.p['hours']!: 1, x.p['status']!: 'todo'}),
          await env.repo.createRecord(x.tracker, values: {x.p['name']!: 'File taxes', x.p['hours']!: 2, x.p['status']!: 'done', x.p['done']!: true}),
        ];
        return (tracker: x.tracker, p: x.p, ids: ids);
      }))!;

  Future<te.CellValue> cell(WidgetTester t, String rec, String prop) async => (await t.runAsync<te.CellValue>(() => env.repo.cellValue(rec, prop)));

  /// Chooses [label] in the property type dropdown, scrolling the (long) menu if needed.
  Future<void> pickType(WidgetTester t, String label) async {
    await t.tap(find.byKey(const Key('property-type')));
    await settle(t);
    final item = find.text(label);
    if (item.evaluate().isEmpty) {
      await t.scrollUntilVisible(item, 120, scrollable: find.byType(Scrollable).last);
    }
    await t.tap(item.last);
    await settle(t);
  }

  Future<void> editText(WidgetTester t, String shownText, String newText) async {
    await t.tap(find.text(shownText)); // select
    await t.pump();
    await t.tap(find.text(shownText)); // edit
    await settle(t);
    await t.enterText(find.byKey(const Key('cell-editor')), newText);
    await t.testTextInput.receiveAction(TextInputAction.done);
    await settle(t);
  }

  group('grid editing', () {
    testWidgets('renders headers, typed values, option pills and the record count', (t) async {
      size(t, 1400, 900);
      final x = await seed(t);
      await pumpTracker(t, env, x.tracker);
      for (final h in ['Name', 'Status', 'Hours', 'Due', 'Tags', 'Done?']) {
        expect(find.text(h), findsOneWidget, reason: h);
      }
      expect(find.text('Write intro'), findsOneWidget);
      expect(find.text('3.5'), findsOneWidget);
      expect(find.text('In progress'), findsOneWidget);
      expect(find.text('3 records'), findsOneWidget);
    });

    testWidgets('click a cell to select it, click again to edit in place; Enter saves', (t) async {
      size(t, 1400, 900);
      final x = await seed(t);
      final c = await pumpTracker(t, env, x.tracker);
      await t.tap(find.text('Read paper'));
      await t.pump();
      expect(stateOf(c, x.tracker).active?.recordId, x.ids[1]);
      expect(stateOf(c, x.tracker).editing, isFalse, reason: 'first click only selects');
      await editText(t, 'Read paper', 'Read the paper twice');
      expect(find.text('Read the paper twice'), findsOneWidget);
      expect(await cell(t, x.ids[1], x.p['name']!), 'Read the paper twice');
      expect(stateOf(c, x.tracker).editing, isFalse);
    });

    testWidgets('invalid input is rejected in plain language, the stored value is untouched and the editor stays open', (t) async {
      size(t, 1400, 900);
      final x = await seed(t);
      await pumpTracker(t, env, x.tracker);
      await editText(t, '3.5', 'abc');
      expect(find.text('"abc" is not a number.'), findsOneWidget);
      expect(await cell(t, x.ids[0], x.p['hours']!), 3.5);
      expect(find.byKey(const Key('cell-editor')), findsOneWidget, reason: 'the user\'s text is not thrown away');
    });

    testWidgets('Escape cancels an edit without saving', (t) async {
      size(t, 1400, 900);
      final x = await seed(t);
      await pumpTracker(t, env, x.tracker);
      await t.tap(find.text('Write intro'));
      await t.pump();
      await t.tap(find.text('Write intro'));
      await settle(t);
      await t.enterText(find.byKey(const Key('cell-editor')), 'discarded');
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(t);
      expect(find.byKey(const Key('cell-editor')), findsNothing);
      expect(await cell(t, x.ids[0], x.p['name']!), 'Write intro');
    });

    testWidgets('checkbox toggles with a single click', (t) async {
      size(t, 1400, 900);
      final x = await seed(t);
      await pumpTracker(t, env, x.tracker);
      await t.tap(find.byIcon(Icons.check_box_outline_blank).first);
      await settle(t);
      expect(await cell(t, x.ids[0], x.p['done']!), true);
    });

    testWidgets('status cell opens an option picker; picking changes the value', (t) async {
      size(t, 1400, 900);
      final x = await seed(t);
      await pumpTracker(t, env, x.tracker);
      await t.tap(find.text('Not started'));
      await t.pump();
      await t.tap(find.text('Not started'));
      await settle(t);
      expect(find.text('Status'), findsWidgets);
      await t.tap(find.descendant(of: find.byType(SimpleDialog), matching: find.text('Done')));
      await settle(t);
      expect(await cell(t, x.ids[1], x.p['status']!), 'done');
    });

    testWidgets('the picker can create a new option on the fly', (t) async {
      size(t, 1400, 900);
      final x = await seed(t);
      await pumpTracker(t, env, x.tracker);
      await t.tap(find.text('Not started'));
      await t.pump();
      await t.tap(find.text('Not started'));
      await settle(t);
      await t.enterText(find.widgetWithText(TextField, 'New option…'), 'Waiting');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await settle(t);
      expect(find.text('Waiting'), findsOneWidget);
      final defs = (await t.runAsync(() => env.repo.properties(x.tracker)))!;
      expect(defs.firstWhere((d) => d.id == x.p['status']).options.map((o) => o.label), contains('Waiting'));
    });

    testWidgets('keyboard: arrows move, Enter edits, Delete clears, Ctrl+Z undoes', (t) async {
      size(t, 1400, 900);
      final x = await seed(t);
      final c = await pumpTracker(t, env, x.tracker);
      await t.tap(find.text('Write intro'));
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.pump();
      expect(stateOf(c, x.tracker).active?.propertyId, x.p['status']);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.pump();
      expect(stateOf(c, x.tracker).active, ActiveCell(x.ids[1], x.p['status']!));
      await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight); // Hours
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.delete);
      await settle(t);
      expect(await cell(t, x.ids[1], x.p['hours']!), isNull);
      await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await settle(t);
      expect(await cell(t, x.ids[1], x.p['hours']!), 1, reason: 'Ctrl+Z restored the cleared value');
    });

    testWidgets('undo and redo buttons walk back and forward through edits', (t) async {
      size(t, 1400, 900);
      final x = await seed(t);
      await pumpTracker(t, env, x.tracker);
      await editText(t, 'Write intro', 'Changed');
      expect(find.text('Changed'), findsOneWidget);
      await t.tap(find.byTooltip('Undo: Edit cell'));
      await settle(t);
      expect(find.text('Write intro'), findsOneWidget);
      await t.tap(find.byTooltip('Redo'));
      await settle(t);
      expect(find.text('Changed'), findsOneWidget);
    });
  });

  group('rows', () {
    testWidgets('New row appends an empty record and focuses its title; undo removes it', (t) async {
      size(t, 1400, 900);
      final x = await seed(t);
      final c = await pumpTracker(t, env, x.tracker);
      await t.tap(find.byKey(const Key('add-record')));
      await settle(t);
      expect(stateOf(c, x.tracker).records.length, 4);
      expect(stateOf(c, x.tracker).active?.propertyId, x.p['name']);
      await t.tap(find.byTooltip('Undo: Add row'));
      await settle(t);
      expect(stateOf(c, x.tracker).records.length, 3);
    });

    testWidgets('row menu: duplicate, then delete; both are undoable', (t) async {
      size(t, 1400, 900);
      final x = await seed(t);
      final c = await pumpTracker(t, env, x.tracker);
      await t.longPress(find.text('1').first);
      await settle(t);
      await t.tap(find.text('Duplicate'));
      await settle(t);
      expect(find.text('Write intro'), findsNWidgets(2));
      await t.longPress(find.text('1').first);
      await settle(t);
      await t.tap(find.text('Delete'));
      await settle(t);
      expect(find.text('Write intro'), findsOneWidget);
      await t.tap(find.byTooltip('Undo: Delete 1 row'));
      await settle(t);
      expect(find.text('Write intro'), findsNWidgets(2));
      expect(stateOf(c, x.tracker).records.length, 4);
    });

    testWidgets('select several rows, bulk set a value, then bulk delete', (t) async {
      size(t, 1400, 900);
      final x = await seed(t);
      final c = await pumpTracker(t, env, x.tracker);
      await t.tap(find.byKey(Key('select-${x.ids[0]}')));
      await t.tap(find.byKey(Key('select-${x.ids[1]}')));
      await settle(t);
      expect(find.text('2 selected'), findsOneWidget);
      await t.tap(find.text('Set value…'));
      await settle(t);
      await t.tap(find.byKey(const Key('bulk-property')));
      await settle(t);
      await t.tap(find.text('Hours').last);
      await settle(t);
      await t.enterText(find.byKey(const Key('bulk-text')), '9');
      await t.tap(find.byKey(const Key('bulk-apply')));
      await settle(t);
      expect(await cell(t, x.ids[0], x.p['hours']!), 9);
      expect(await cell(t, x.ids[1], x.p['hours']!), 9);
      expect(await cell(t, x.ids[2], x.p['hours']!), 2, reason: 'unselected row untouched');
      await t.tap(find.byKey(const Key('bulk-delete')));
      await settle(t);
      expect(stateOf(c, x.tracker).records.map((r) => r.id), [x.ids[2]]);
    });

    testWidgets('search narrows the rows and can be cleared', (t) async {
      size(t, 1400, 900);
      final x = await seed(t);
      await pumpTracker(t, env, x.tracker);
      await t.enterText(find.byKey(const Key('tracker-search')), 'taxes');
      await settle(t);
      expect(find.text('File taxes'), findsOneWidget);
      expect(find.text('Write intro'), findsNothing);
      await t.tap(find.byTooltip('Clear search'));
      await settle(t);
      expect(find.text('Write intro'), findsOneWidget);
    });
  });

  group('properties', () {
    testWidgets('add a Number property from the header +', (t) async {
      size(t, 1400, 900);
      final x = await seed(t);
      await pumpTracker(t, env, x.tracker);
      await t.tap(find.byTooltip('Add property'));
      await settle(t);
      await t.enterText(find.widgetWithText(TextField, 'Name').last, 'Budget');
      await pickType(t, 'Number');
      await t.tap(find.text('Add property'));
      await settle(t);
      expect(find.text('Budget'), findsOneWidget);
    });

    testWidgets('a formula property shows live validation, then calculated values in every row', (t) async {
      size(t, 1400, 900);
      final x = await seed(t);
      await pumpTracker(t, env, x.tracker);
      await t.tap(find.byTooltip('Add property'));
      await settle(t);
      await t.enterText(find.widgetWithText(TextField, 'Name').last, 'Double');
      await pickType(t, 'Formula');
      await t.enterText(find.byKey(const Key('formula-field')), 'prop("Hours") *');
      await settle(t);
      expect(find.textContaining('✗'), findsOneWidget, reason: 'syntax error shown while typing');
      await t.enterText(find.byKey(const Key('formula-field')), 'prop("Hours") * 2');
      await settle(t);
      expect(find.textContaining('Preview for this first row: 7'), findsOneWidget);
      await t.tap(find.text('Add property'));
      await settle(t);
      expect(find.text('Double'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
      expect(find.text('2'), findsWidgets);
      expect(find.text('4'), findsOneWidget);
    });

    testWidgets('a circular formula is rejected with a readable message', (t) async {
      size(t, 1400, 900);
      final x = await seed(t);
      final c = await pumpTracker(t, env, x.tracker);
      final ctrl = c.read(trackerControllerProvider(x.tracker).notifier);
      await t.runAsync(() => ctrl.addProperty('A', te.PropertyType.formula, {'formula': '1'}));
      await settle(t);
      final a = stateOf(c, x.tracker).properties.firstWhere((p) => p.name == 'A');
      await t.runAsync(() => ctrl.addProperty('B', te.PropertyType.formula, {'formula': 'prop("${a.id}")+1'}));
      await settle(t);
      final b = stateOf(c, x.tracker).properties.firstWhere((p) => p.name == 'B');
      final ok = await t.runAsync(() => ctrl.updateProperty(a.id, config: {'formula': 'prop("${b.id}")'}));
      await settle(t);
      expect(ok, isFalse);
      expect(find.textContaining('loop'), findsOneWidget);
    });

    testWidgets('header menu: sort descending reorders the rows; hide removes the column from the view only', (t) async {
      size(t, 1400, 900);
      final x = await seed(t);
      final c = await pumpTracker(t, env, x.tracker);
      await t.tap(find.text('Hours'));
      await settle(t);
      await t.tap(find.text('Sort descending'));
      await settle(t);
      expect(stateOf(c, x.tracker).records.map((r) => r.cells[x.p['name']]), ['Write intro', 'File taxes', 'Read paper']);
      await t.tap(find.text('Due'));
      await settle(t);
      await t.tap(find.text('Hide in this view'));
      await settle(t);
      expect(find.text('Due'), findsNothing);
      final defs = (await t.runAsync(() => env.repo.properties(x.tracker)))!;
      expect(defs.any((d) => d.name == 'Due'), isTrue, reason: 'hiding never deletes the property');
    });
  });

  group('views', () {
    testWidgets('view options: add a filter and apply; the table shows only matching rows', (t) async {
      size(t, 1400, 900);
      final x = await seed(t);
      final c = await pumpTracker(t, env, x.tracker);
      await t.tap(find.byKey(const Key('view-options')));
      await settle(t);
      await t.tap(find.byKey(const Key('add-filter')));
      await settle(t);
      await t.tap(find.byKey(const Key('cond-prop')));
      await settle(t);
      await t.tap(find.text('Hours').last);
      await settle(t);
      await t.tap(find.byKey(const Key('cond-op')));
      await settle(t);
      await t.tap(find.text('>').last);
      await settle(t);
      await t.enterText(find.byKey(const Key('operand-gt')), '1.5');
      await t.tap(find.byKey(const Key('apply-view')));
      await settle(t);
      expect(stateOf(c, x.tracker).records.map((r) => r.cells[x.p['name']]), ['Write intro', 'File taxes']);
      expect(find.descendant(of: find.byKey(const Key('view-options')), matching: find.text('1')), findsOneWidget, reason: 'the active-filter count is a badge on the button');
      expect(find.text('2 records'), findsOneWidget);
    });

    testWidgets('a filter that matches nothing explains itself instead of showing a blank screen', (t) async {
      size(t, 1400, 900);
      final x = await seed(t);
      final c = await pumpTracker(t, env, x.tracker);
      // driven like any UI action: the controller call completes under normal pumping
      c.read(trackerControllerProvider(x.tracker).notifier).updateView(te.ViewConfig(filter: te.FilterGroup(children: [te.FilterCondition(propertyId: x.p['hours']!, op: te.FilterOp.gt, value: 999)])));
      await settle(t);
      expect(find.text('0 records'), findsOneWidget);
      expect(find.byKey(const Key('new-row')), findsOneWidget, reason: 'still possible to add rows');
    });

    testWidgets('add a Board view: cards are grouped by status and a card can be dragged to another column', (t) async {
      size(t, 1400, 900);
      final x = await seed(t);
      final c = await pumpTracker(t, env, x.tracker);
      await t.tap(find.byKey(const Key('new-view')));
      await settle(t);
      await t.tap(find.text('Board').last);
      await settle(t);
      expect(find.byKey(Key('card-${x.ids[1]}')), findsOneWidget);
      final from = t.getCenter(find.byKey(Key('card-${x.ids[1]}')));
      final to = t.getCenter(find.byKey(const Key('column-done')));
      final g = await t.startGesture(from);
      await t.pump(const Duration(milliseconds: 600)); // long-press to lift
      await g.moveTo(to, timeStamp: const Duration(milliseconds: 100));
      await t.pump();
      await g.up();
      await settle(t);
      expect(await cell(t, x.ids[1], x.p['status']!), 'done', reason: '"Read paper" moved from Not started to Done');
      expect(stateOf(c, x.tracker).groups!.firstWhere((g) => g.key == 'done').records.map((r) => r.id), contains(x.ids[1]));
    });

    testWidgets('List view shows rows with summary pills; opening a row shows the detail', (t) async {
      size(t, 1400, 900);
      final x = await seed(t);
      await pumpTracker(t, env, x.tracker);
      await t.tap(find.byKey(const Key('new-view')));
      await settle(t);
      await t.tap(find.text('List').last);
      await settle(t);
      expect(find.byKey(Key('list-${x.ids[2]}')), findsOneWidget);
      await t.tap(find.byKey(Key('list-${x.ids[2]}')));
      await settle(t);
      expect(find.text('Subtasks'), findsOneWidget);
    });

    testWidgets('not-yet-built layouts are labelled, not offered as working', (t) async {
      size(t, 1400, 900);
      final x = await seed(t);
      await pumpTracker(t, env, x.tracker);
      await t.tap(find.byKey(const Key('new-view')));
      await settle(t);
      expect(find.text('Calendar (Phase 3)'), findsOneWidget);
      expect(find.text('Gantt (Phase 3)'), findsOneWidget);
    });

    testWidgets('the last view can not be deleted and says why', (t) async {
      size(t, 1400, 900);
      final x = await seed(t);
      await pumpTracker(t, env, x.tracker);
      await t.longPress(find.byKey(const Key('view-Table')));
      await settle(t);
      await t.tap(find.text('Delete view'));
      await settle(t);
      expect(find.text('A tracker needs at least one view.'), findsOneWidget);
    });
  });

  group('record detail', () {
    testWidgets('open a record, edit its title and a number, add a subtask', (t) async {
      size(t, 1400, 900);
      final x = await seed(t);
      final c = await pumpTracker(t, env, x.tracker);
      await t.tap(find.byTooltip('Open record').first);
      await settle(t);
      expect(find.text('Subtasks'), findsOneWidget);
      final title = find.byKey(ValueKey('tf-${x.ids[0]}-${x.p['name']}-Write intro'));
      await t.enterText(title, 'Write the intro');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await settle(t);
      expect(await cell(t, x.ids[0], x.p['name']!), 'Write the intro');
      await t.tap(find.byKey(const Key('add-subtask')));
      await settle(t);
      expect(stateOf(c, x.tracker).records.where((r) => r.parentId == x.ids[0]).length, 1);
    });

    testWidgets('narrow screens open the record full-screen', (t) async {
      size(t, 420, 900);
      final x = await seed(t);
      await pumpTracker(t, env, x.tracker);
      await t.tap(find.byTooltip('Open record').first);
      await settle(t);
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text('Subtasks'), findsOneWidget);
    });
  });

  group('scale and themes', () {
    testWidgets('1,200 rows: only the visible rows are built; the page says it is showing the first 1,000', (t) async {
      size(t, 1400, 900);
      final x = (await t.runAsync(() async {
        final tr = await env.repo.createTracker(name: 'Big');
        final name = (await env.repo.properties(tr)).single.id;
        for (var i = 0; i < 1200; i++) {
          await env.repo.createRecord(tr, values: {name: 'Row $i'});
        }
        return (tracker: tr, name: name);
      }))!;
      await pumpTracker(t, env, x.tracker);
      expect(find.text('1200 records'), findsOneWidget);
      expect(find.textContaining('Showing the first 1000 of 1200'), findsOneWidget);
      expect(find.byType(Text).evaluate().length, lessThan(200), reason: 'virtualised: nowhere near 1,000 rows are in the tree');
      expect(find.text('Row 0'), findsOneWidget);
      expect(find.text('Row 999'), findsNothing);
      await t.drag(find.byType(TableView), const Offset(0, -60000));
      await settle(t);
      expect(find.text('Row 999'), findsOneWidget, reason: 'scrolling reaches the end of the loaded page');
    });

    testWidgets('dark theme renders the grid, pills and dialogs without errors', (t) async {
      size(t, 1400, 900);
      final x = await seed(t);
      await pumpTracker(t, env, x.tracker, brightness: Brightness.dark);
      await t.tap(find.byKey(const Key('view-options')));
      await settle(t);
      expect(find.text('View options'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    test('every option colour pair meets 4.5:1 contrast in both themes', () {
      double lum(Color c) {
        double ch(double v) => v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4).toDouble();
        return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
      }

      for (final b in Brightness.values) {
        for (final n in OptionColors.names) {
          final (bg, fg) = OptionColors.of(n, b);
          final l1 = lum(bg), l2 = lum(fg);
          final ratio = (l1 > l2 ? l1 + .05 : l2 + .05) / (l1 > l2 ? l2 + .05 : l1 + .05);
          expect(ratio, greaterThanOrEqualTo(4.5), reason: '$n/${b.name}: ${ratio.toStringAsFixed(2)}');
        }
      }
    });
  });

  group('trackers page', () {
    Future<void> pumpPage(WidgetTester t) async {
      final container = ProviderContainer(overrides: [databaseProvider.overrideWithValue(env.db), syncedStoreProvider.overrideWithValue(env.store)]);
      addTearDown(container.dispose);
      await t.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp(theme: buildTheme(Brightness.light), home: const Scaffold(body: TrackersPage()))));
      await settle(t);
    }

    testWidgets('empty state offers templates; a template creates linked trackers and opens the first', (t) async {
      size(t, 1400, 900);
      await pumpPage(t);
      expect(find.text('Build your own trackers'), findsOneWidget);
      await t.tap(find.text('New tracker'));
      await settle(t);
      await t.tap(find.byKey(const Key('template-goals_projects_tasks')));
      await settle(t);
      expect(find.text('Goals'), findsWidgets);
      expect(find.byKey(const Key('view-All goals')), findsOneWidget);
      final list = (await t.runAsync(() => env.repo.trackers()))!;
      expect(list.map((x) => x.name), ['Goals', 'Projects', 'Tasks']);
    });

    testWidgets('a blank tracker asks for a name and opens with a Name column', (t) async {
      size(t, 1400, 900);
      await pumpPage(t);
      await t.tap(find.text('New tracker'));
      await settle(t);
      await t.tap(find.byKey(const Key('template-blank')));
      await settle(t);
      await t.enterText(find.byKey(const Key('prompt-field')), 'Reading list');
      await t.tap(find.text('Create'));
      await settle(t);
      expect(find.text('Reading list'), findsWidgets);
      expect(find.text('Name'), findsOneWidget);
      expect(find.text('No rows yet'), findsOneWidget);
    });

    testWidgets('on a phone the list comes first, then the tracker with a back button', (t) async {
      size(t, 420, 900);
      await t.runAsync(() => env.repo.createTracker(name: 'Budget'));
      await pumpPage(t);
      expect(find.text('Trackers'), findsOneWidget);
      await t.tap(find.text('Budget'));
      await settle(t);
      expect(find.byTooltip('Back to trackers'), findsOneWidget);
      await t.tap(find.byTooltip('Back to trackers'));
      await settle(t);
      expect(find.text('Trackers'), findsOneWidget);
    });
  });
}
