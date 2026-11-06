import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/app/providers.dart';
import 'package:folio/app/sync_controller.dart';
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
    await env.store.setFields('tasks', 't1', {'title': 'A', 'notes': 'x'});

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

  group('gating', () {
    Future<(TestEnv, ProviderContainer, bool Function(bool))> setup({String? Function()? conflict}) async {
      final env = await TestEnv.create(withSync: true);
      var signedIn = false;
      env.syncControllerFactory = () => SyncController(env.sync, isSignedIn: () => signedIn, accountConflict: () async => conflict?.call());
      final c = ProviderContainer(overrides: env.overrides);
      addTearDown(c.dispose);
      return (env, c, (bool v) => signedIn = v);
    }

    test('signed out: nothing is sent, status stays local-only (no scary error)', () async {
      final (env, c, _) = await setup();
      await env.store.setFields('tasks', 't1', {'title': 'A'});
      await c.read(syncControllerProvider.notifier).syncNow();
      final s = c.read(syncControllerProvider);
      expect((s.phase, s.error, env.server!.state.length), (SyncPhase.localOnly, null, 0));
      expect(s.pending, greaterThan(0), reason: 'edits wait for sign-in');
    });

    test('after signing in, the waiting edits are sent', () async {
      final (env, c, signIn) = await setup();
      await env.store.setFields('tasks', 't1', {'title': 'A'});
      final ctrl = c.read(syncControllerProvider.notifier);
      await ctrl.syncNow();
      signIn(true);
      await ctrl.syncNow();
      expect((c.read(syncControllerProvider).phase, c.read(syncControllerProvider).pending), (SyncPhase.synced, 0));
      expect(env.server!.state.length, 1);
    });

    test('a different account on the same device is refused: nothing is mixed', () async {
      final (env, c, signIn) = await setup(conflict: () => 'This device already holds data from another account.');
      signIn(true);
      await env.store.setFields('tasks', 't1', {'title': 'A'});
      await c.read(syncControllerProvider.notifier).syncNow();
      final s = c.read(syncControllerProvider);
      expect((s.phase, env.server!.state.length), (SyncPhase.attention, 0));
      expect(s.error, contains('another account'));
    });
  });
}
