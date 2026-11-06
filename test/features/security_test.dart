import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/app/providers.dart';
import 'package:folio/features/security/app_lock.dart';
import 'package:folio/features/security/key_service.dart';

import '../helpers.dart';

void main() {
  group('DatabaseKeyService', () {
    test('creates a 256-bit hex key once and returns the same key afterwards', () async {
      final store = InMemoryKeyStore();
      final svc = DatabaseKeyService(store);
      final k1 = await svc.getOrCreate();
      expect(k1, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(await DatabaseKeyService(store).getOrCreate(), k1);
    });

    test('different installs get different keys', () async {
      final a = await DatabaseKeyService(InMemoryKeyStore(), random: Random(1)).getOrCreate();
      final b = await DatabaseKeyService(InMemoryKeyStore(), random: Random(2)).getOrCreate();
      expect(a, isNot(b));
    });

    test('a malformed stored key is never silently replaced (would orphan the encrypted DB)', () async {
      final store = InMemoryKeyStore()..map[DatabaseKeyService.storageKey] = 'garbage';
      await expectLater(DatabaseKeyService(store).getOrCreate(), throwsStateError);
      expect(store.map[DatabaseKeyService.storageKey], 'garbage');
    });
  });

  group('AppLockController', () {
    late FakeAuthenticator auth;
    late DateTime now;
    late ProviderContainer c;
    final persisted = <bool>[];

    ProviderContainer make({bool enabled = false}) {
      final container = ProviderContainer(overrides: [
        appLockProvider.overrideWith(() => AppLockController(authenticator: auth, now: () => now, startEnabled: enabled, persistEnabled: (v) async => persisted.add(v))),
      ]);
      addTearDown(container.dispose);
      return container;
    }

    setUp(() {
      auth = FakeAuthenticator();
      now = DateTime(2026, 11, 6, 9);
      persisted.clear();
      c = make();
    });

    test('enabling requires a successful device check, then persists', () async {
      auth.succeed = false;
      expect(await c.read(appLockProvider.notifier).setEnabled(true), isFalse);
      expect(c.read(appLockProvider).enabled, isFalse);
      auth.succeed = true;
      expect(await c.read(appLockProvider.notifier).setEnabled(true), isTrue);
      expect(c.read(appLockProvider).enabled, isTrue);
      expect(persisted, [true]);
    });

    test('cannot enable when the device has no biometrics/passcode (avoids self lock-out)', () async {
      auth.available = false;
      expect(await c.read(appLockProvider.notifier).setEnabled(true), isFalse);
      expect(c.read(appLockProvider).enabled, isFalse);
    });

    test('disabling also requires authentication', () async {
      c = make(enabled: true);
      c.read(appLockProvider.notifier).state = c.read(appLockProvider).copyWith(locked: false);
      auth.succeed = false;
      expect(await c.read(appLockProvider.notifier).setEnabled(false), isFalse);
      expect(c.read(appLockProvider).enabled, isTrue);
    });

    test('locks only after the timeout has elapsed in background', () async {
      await c.read(appLockProvider.notifier).setEnabled(true);
      final n = c.read(appLockProvider.notifier);
      n.onBackgrounded();
      now = now.add(const Duration(seconds: 30));
      n.onResumed();
      expect(c.read(appLockProvider).locked, isFalse, reason: 'short absence does not lock');
      n.onBackgrounded();
      now = now.add(const Duration(minutes: 2));
      n.onResumed();
      expect(c.read(appLockProvider).locked, isTrue);
    });

    test('disabled lock never locks', () {
      final n = c.read(appLockProvider.notifier);
      n.onBackgrounded();
      now = now.add(const Duration(hours: 5));
      n.onResumed();
      expect(c.read(appLockProvider).locked, isFalse);
    });

    test('failed unlock stays locked and flags failure; success unlocks', () async {
      c = make(enabled: true);
      expect(c.read(appLockProvider).locked, isTrue);
      auth.succeed = false;
      await c.read(appLockProvider.notifier).unlock();
      expect(c.read(appLockProvider).locked, isTrue);
      expect(c.read(appLockProvider).failed, isTrue);
      auth.succeed = true;
      await c.read(appLockProvider.notifier).unlock();
      expect(c.read(appLockProvider).locked, isFalse);
    });
  });
}
