import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local/app_database.dart';
import '../data/sync/synced_store.dart';
import '../data/sync/sync_service.dart';
import '../features/auth/auth_repository.dart';
import '../features/security/app_lock.dart';
import 'sync_controller.dart';

/// Overridden in `main()` / tests. Reading them un-overridden is a programming error.
final databaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('databaseProvider must be overridden'),
);
final syncedStoreProvider = Provider<SyncedStore>(
  (ref) => throw UnimplementedError('syncedStoreProvider must be overridden'),
);

/// null => local-only (no cloud configured or user chose no account).
final syncServiceProvider = Provider<SyncService?>((ref) => null);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => LocalOnlyAuthRepository(),
);

final sessionProvider = StreamProvider<AppSession>((ref) async* {
  final repo = ref.watch(authRepositoryProvider);
  yield repo.current;
  yield* repo.changes;
});

final authenticatorProvider = Provider<Authenticator>(
  (ref) => LocalAuthAuthenticator(),
);

final appLockProvider = NotifierProvider<AppLockController, LockState>(
  () => throw UnimplementedError('appLockProvider must be overridden'),
);

final syncControllerProvider = NotifierProvider<SyncController, SyncStatus>(
  () => throw UnimplementedError('syncControllerProvider must be overridden'),
);
