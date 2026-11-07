import 'package:flutter/material.dart';
import 'features/library/application/library_controller.dart';
import 'features/library/application/book_sync.dart';
import 'features/library/data/cloud_books.dart';
import 'features/library/data/library_repository.dart';
import 'features/library/data/pdf_inspector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'app/sync_controller.dart';
import 'data/local/database_opener.dart';
import 'data/sync/supabase_sync_transport.dart';
import 'data/sync/synced_store.dart';
import 'data/sync/sync_service.dart';
import 'features/auth/auth_repository.dart';
import 'features/planner/application/planner_controller.dart';
import 'features/planner/data/local_notifications_scheduler.dart';
import 'features/security/app_lock.dart';
import 'features/security/key_service.dart';
import 'features/settings/rotation.dart';

/// Supply at build time: --dart-define=SUPABASE_URL=https://xyz.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=...
/// (The publishable/anon key is public by design; Row Level Security enforces access. Never put a
/// service-role key in the app.) Without them the app runs local-only.
const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final key = await DatabaseKeyService(SecureStorageKeyStore()).getOrCreate();
  final db = openEncrypted(await defaultDatabaseFile(), key);
  final store = await SyncedStore.open(db);

  final authenticator = LocalAuthAuthenticator();
  // If the user enabled app lock but this device can no longer authenticate (biometrics removed,
  // no passcode), starting locked would lock them out of their own data: start unlocked and off.
  var lockEnabled = (await store.state('app_lock_enabled')) == '1';
  if (lockEnabled && !await authenticator.isAvailable()) {
    lockEnabled = false;
    await store.setState('app_lock_enabled', '0');
  }

  final rotation = await loadRotationMode(store.state);
  await SystemOrientationLock().apply(rotation);

  AuthRepository auth = LocalOnlyAuthRepository();
  SyncService? sync;
  if (_supabaseUrl.isNotEmpty && _supabaseKey.isNotEmpty) {
    await Supabase.initialize(url: _supabaseUrl, publishableKey: _supabaseKey);
    auth = SupabaseAuthRepository(Supabase.instance.client,
        startLocalOnly: (await store.state('mode')) == 'local',
        onLocalOnly: (local) => store.setState('mode', local ? 'local' : 'cloud'));
    sync = SyncService(store, SupabaseSyncTransport(Supabase.instance.client));
  }

  final libraryDir = await resolveLibraryDirectory();
  // Books stay in the bin (Settings -> Storage) for 30 days, then are deleted for good.
  await LibraryRepository(db, directory: libraryDir, inspector: PdfrxInspector()).purge(keep: binRetention);

  runApp(ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      syncedStoreProvider.overrideWithValue(store),
      authRepositoryProvider.overrideWithValue(auth),
      syncServiceProvider.overrideWithValue(sync),
      authenticatorProvider.overrideWithValue(authenticator),
      appLockProvider.overrideWith(() => AppLockController(
          authenticator: authenticator,
          startEnabled: lockEnabled,
          persistEnabled: (v) => store.setState('app_lock_enabled', v ? '1' : '0'),
        )),
      syncControllerProvider.overrideWith(() => SyncController(
        sync,
        isSignedIn: () => auth.current is SignedInSession,
        accountConflict: () async {
          // Never mix two accounts' data on one device: the first account to sync owns this database.
          final user = (auth.current as SignedInSession).userId;
          final owner = await store.state('sync_owner');
          if (owner == null) {
            await store.setState('sync_owner', user);
            return null;
          }
          return owner == user ? null : 'This device already holds data from another account, so it will not sync with this one.';
        },
      )),
      rotationProvider.overrideWith(() => RotationController(rotation)),
      reminderSchedulerProvider.overrideWithValue(createReminderScheduler()),
      libraryDirectoryProvider.overrideWithValue(libraryDir),
      cloudBooksProvider.overrideWithValue(_supabaseUrl.isNotEmpty && _supabaseKey.isNotEmpty ? SupabaseCloudBooks(Supabase.instance.client) : null),
    ],
    child: const FolioApp(),
  ));
}
