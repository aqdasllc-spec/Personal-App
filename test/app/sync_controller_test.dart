import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/app/providers.dart';
import 'package:folio/design_system/components.dart';

import '../helpers.dart';

void main() {
  test('local-only mode reports localOnly and syncNow is a no-op', () async {
    final env = await TestEnv.create();
    final c = ProviderContainer(overrides: env.overrides);
    addTearDown(c.dispose);
    expect(c.read(syncControllerProvider).phase, SyncPhase.localOnly);
    await c.read(syncControllerProvider.notifier).syncNow();
    expect(c.read(syncControllerProvider).phase, SyncPhase.localOnly);
  });

  test('success -> synced with last sync time; outage -> offline with pending count; recovery -> synced', () async {
    final env = await TestEnv.create(withSync: true);
    final c = ProviderContainer(overrides: env.overrides);
    addTearDown(c.dispose);
    final ctrl = c.read(syncControllerProvider.notifier);
    await env.store.setFields('trackers', 't1', {'name': 'A', 'color': 'x'});

    env.transport!.offline = true;
    await ctrl.syncNow();
    var s = c.read(syncControllerProvider);
    expect(s.phase, SyncPhase.offline);
    expect(s.pending, 2);
    expect(s.failures, 1);
    expect(s.error, 'offline');

    env.transport!.offline = false;
    await ctrl.syncNow();
    s = c.read(syncControllerProvider);
    expect(s.phase, SyncPhase.synced);
    expect(s.pending, 0);
    expect(s.failures, 0);
    expect(s.lastSync, isNotNull);
    expect(env.server!.state.length, 2);
  });
}
