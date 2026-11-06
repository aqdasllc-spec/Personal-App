import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:folio/features/tracker/data/tracker_repository.dart';
import 'package:tracker_engine/tracker_engine.dart' as te;

import '../features/tracker/tracker_ui_helpers.dart' show settle;
import '../helpers.dart';

void _size(WidgetTester t, double w, double h) {
  t.view.physicalSize = Size(w, h);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

void main() {
  dialogFlows();
  for (final (label, w) in [('phone', 400.0), ('tablet', 800.0), ('desktop', 1400.0)]) {
    for (final tpl in ['template-blank', 'template-goals_projects_tasks', 'template-reading_log', 'template-habits', 'template-finance']) {
      testWidgets('Goals → New tracker → $tpl on $label shows the tracker, not a blank screen', (t) async {
        _size(t, w, 900);
        final env = await TestEnv.create();
        addTearDown(env.db.close);
        await t.pumpWidget(env.app);
        await t.pumpAndSettle();
        // open Goals from the navigation
        await t.tap(find.text(w < 600 ? 'Goals' : 'Goals & Projects').last);
        await settle(t);
        expect(find.text('Build your own trackers'), findsOneWidget);
        await t.tap(find.text('New tracker'));
        await settle(t);
        await t.tap(find.byKey(Key(tpl)));
        await settle(t);
        if (tpl == 'template-blank') {
          await t.enterText(find.byKey(const Key('prompt-field')), 'My tracker');
          await t.tap(find.text('Create'));
          await settle(t);
        }
        expect(t.takeException(), isNull);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.byKey(const Key('view-options')), findsOneWidget, reason: 'the tracker toolbar must be on screen');
        expect(find.byKey(const Key('add-record')), findsOneWidget);
        // dispose the app before the test ends so no timers outlive it
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 1));
      });
    }
  }
}

// ---- every dialog/sheet inside the tracker flow, driven through the REAL app shell and router ----
void dialogFlows() {
  for (final (label, w) in [('phone', 400.0), ('desktop', 1400.0)]) {
    testWidgets('dialogs and sheets never close the tracker page ($label)', (t) async {
      _size(t, w, 900);
      final env = await TestEnv.create();
      addTearDown(env.db.close);
      await t.runAsync(() async {
        final repo = TrackerRepository(env.store);
        final tr = await repo.createTracker(name: 'Budget');
        final props = await repo.properties(tr);
        final status = await repo.addProperty(tr, 'Status', te.PropertyType.status, config: te.Cfg.options(const [te.SelectOption(id: 'a', label: 'Open'), te.SelectOption(id: 'b', label: 'Closed')]));
        await repo.createRecord(tr, values: {props.single.id: 'Rent', status: 'a'});
        await repo.createRecord(tr, values: {props.single.id: 'Food', status: 'b'});
      });
      await t.pumpWidget(env.app);
      await t.pumpAndSettle();
      await t.tap(find.text(w < 600 ? 'Goals' : 'Goals & Projects').last);
      await settle(t);
      if (w < 600) {
        await t.tap(find.text('Budget'));
        await settle(t);
      }
      void alive(String step) {
        expect(t.takeException(), isNull, reason: step);
        expect(find.byKey(const Key('view-options')), findsOneWidget, reason: 'tracker page still on screen after: $step');
      }

      alive('open tracker');

      // add property dialog
      await t.tap(find.byTooltip('Add property').first);
      await settle(t);
      await t.enterText(find.widgetWithText(TextField, 'Name').last, 'Amount');
      await t.tap(find.text('Add property'));
      await settle(t);
      alive('add property');

      // cancel path of a dialog
      await t.tap(find.byTooltip('Add property').first);
      await settle(t);
      await t.tap(find.text('Cancel'));
      await settle(t);
      alive('cancel property dialog');

      // view options sheet: apply and cancel
      await t.tap(find.byKey(const Key('view-options')));
      await settle(t);
      await t.tap(find.byKey(const Key('apply-view')));
      await settle(t);
      alive('apply view options');
      await t.tap(find.byKey(const Key('view-options')));
      await settle(t);
      await t.tap(find.text('Cancel'));
      await settle(t);
      alive('cancel view options');

      // view menu: rename + failed delete of the last view
      await t.longPress(find.byKey(const Key('view-Table')));
      await settle(t);
      await t.tap(find.text('Rename view'));
      await settle(t);
      await t.enterText(find.byKey(const Key('prompt-field')), 'Everything');
      await t.tap(find.text('Rename'));
      await settle(t);
      alive('rename view');
      expect(find.byKey(const Key('view-Everything')), findsOneWidget);
      await t.longPress(find.byKey(const Key('view-Everything')));
      await settle(t);
      await t.tap(find.text('Delete view'));
      await settle(t);
      alive('delete last view (refused)');

      // new view menu → Board
      await t.tap(find.byKey(const Key('new-view')));
      await settle(t);
      await t.tap(find.text('Board').last);
      await settle(t);
      alive('add board view');

      // record detail: open from a card, close
      await t.tap(find.byKey(Key('view-Everything')));
      await settle(t);
      alive('switch view');

      if (w >= 600) {
        // option picker dialog on a status cell
        await t.tap(find.text('Open'));
        await t.pump();
        await t.tap(find.text('Open'));
        await settle(t);
        await t.tap(find.descendant(of: find.byType(SimpleDialog), matching: find.text('Closed')));
        await settle(t);
        alive('option picker');

        // tracker list menu: rename, then delete
        await t.tap(find.byTooltip('Tracker options'));
        await settle(t);
        await t.tap(find.text('Rename'));
        await settle(t);
        await t.enterText(find.byKey(const Key('prompt-field')), 'Household');
        await t.tap(find.text('Rename').last);
        await settle(t);
        expect(find.text('Household'), findsWidgets);
        await t.tap(find.byTooltip('Tracker options'));
        await settle(t);
        await t.tap(find.text('Delete'));
        await settle(t);
        await t.tap(find.text('Delete').last);
        await settle(t);
        expect(t.takeException(), isNull);
        expect(find.text('Build your own trackers'), findsOneWidget, reason: 'deleting the only tracker returns to the empty state');
      }
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
    });
  }
}
