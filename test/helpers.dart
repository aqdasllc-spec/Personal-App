import 'dart:async';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:folio/app/app.dart';
import 'package:folio/app/providers.dart';
import 'package:folio/app/sync_controller.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/data/local/database_opener.dart';
import 'package:folio/data/sync/in_memory_transport.dart';
import 'package:folio/data/sync/synced_store.dart';
import 'package:folio/data/sync/sync_service.dart';
import 'package:folio/features/auth/auth_repository.dart';
import 'package:folio/features/security/app_lock.dart';
import 'package:sync_engine/sync_engine.dart';

class FakeAuthenticator implements Authenticator {
  bool available = true;
  bool succeed = true;
  int calls = 0;
  @override
  Future<bool> isAvailable() async => available;
  @override
  Future<bool> authenticate(String reason) async {
    calls++;
    return succeed;
  }
}

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository([AppSession initial = const SignedOutSession()]) : _current = initial;
  AppSession _current;
  Object? failWith;
  bool confirmationRequired = false;
  final calls = <String>[];
  final _c = StreamController<AppSession>.broadcast();
  @override
  AppSession get current => _current;
  @override
  Stream<AppSession> get changes => _c.stream;
  void _set(AppSession s) {
    _current = s;
    _c.add(s);
  }

  @override
  Future<void> signIn(String email, String password) async {
    calls.add('signIn:$email');
    if (failWith != null) throw failWith!;
    _set(SignedInSession(userId: 'u1', email: email));
  }

  @override
  Future<bool> signUp(String email, String password) async {
    calls.add('signUp:$email');
    if (failWith != null) throw failWith!;
    if (confirmationRequired) return false;
    _set(SignedInSession(userId: 'u1', email: email));
    return true;
  }

  @override
  Future<void> signOut() async => _set(const SignedOutSession());
  @override
  Future<void> continueLocalOnly() async => _set(const LocalOnlySession());
}

/// Tests intentionally create several in-memory databases.
void quietDrift() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

class TestEnv {
  TestEnv._(this.db, this.store, this.authenticator, this.auth, this.sync, this.transport, this.server);
  final AppDatabase db;
  final SyncedStore store;
  final FakeAuthenticator authenticator;
  final FakeAuthRepository auth;
  final SyncService? sync;
  final InMemoryTransport? transport;
  final FakeServer? server;

  static Future<TestEnv> create({AppSession session = const LocalOnlySession(), bool lockEnabled = false, bool withSync = false}) async {
    quietDrift();
    final db = openInMemory();
    final store = await SyncedStore.open(db, deviceId: 'test-device');
    final server = withSync ? FakeServer() : null;
    final transport = withSync ? InMemoryTransport(server!) : null;
    return TestEnv._(db, store, FakeAuthenticator(), FakeAuthRepository(session), withSync ? SyncService(store, transport!) : null, transport, server)
      .._lockEnabled = lockEnabled;
  }

  bool _lockEnabled = false;

  List<Override> get overrides => [
        databaseProvider.overrideWithValue(db),
        syncedStoreProvider.overrideWithValue(store),
        authRepositoryProvider.overrideWithValue(auth),
        syncServiceProvider.overrideWithValue(sync),
        authenticatorProvider.overrideWithValue(authenticator),
        appLockProvider.overrideWith(() => AppLockController(authenticator: authenticator, startEnabled: _lockEnabled)),
        syncControllerProvider.overrideWith(() => SyncController(sync, interval: const Duration(days: 1))),
      ];

  Widget get app => ProviderScope(overrides: overrides, child: const FolioApp());
}

/// Pump a few short frames so debounced work and database futures complete, then settle.
Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 80));
  }
  await t.pumpAndSettle();
}
