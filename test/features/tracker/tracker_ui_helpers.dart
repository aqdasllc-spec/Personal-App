import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/app/providers.dart';
import 'package:folio/design_system/theme.dart';
import 'package:folio/features/tracker/application/tracker_controller.dart';
import 'package:folio/features/tracker/presentation/tracker_screen.dart';

import 'tracker_helpers.dart';

void size(WidgetTester t, double w, double h) {
  t.view.physicalSize = Size(w, h);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

/// Pumps a TrackerScreen for [trackerId] backed by [env]'s database.
Future<ProviderContainer> pumpTracker(WidgetTester t, Env env, String trackerId, {String name = 'Tasks', Brightness brightness = Brightness.light}) async {
  final container = ProviderContainer(overrides: [
    databaseProvider.overrideWithValue(env.db),
    syncedStoreProvider.overrideWithValue(env.store),
  ]);
  addTearDown(container.dispose);
  await t.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: buildTheme(brightness),
      home: Scaffold(body: TrackerScreen(trackerId: trackerId, name: name)),
    ),
  ));
  await settle(t);
  return container;
}

Future<ProviderContainer> pumpTrackerNoSettle(WidgetTester t, Env env, String trackerId) async {
  final container = ProviderContainer(overrides: [databaseProvider.overrideWithValue(env.db), syncedStoreProvider.overrideWithValue(env.store)]);
  addTearDown(container.dispose);
  await t.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp(theme: buildTheme(Brightness.light), home: Scaffold(body: TrackerScreen(trackerId: trackerId, name: 'Tasks')))));
  return container;
}

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 80));
  }
  await t.pumpAndSettle();
}

TrackerScreenState stateOf(ProviderContainer c, String trackerId) => c.read(trackerControllerProvider(trackerId)).requireValue;
