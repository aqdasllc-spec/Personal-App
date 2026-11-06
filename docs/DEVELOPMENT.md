# Development guide

## Toolchain
- Flutter **3.47.9** / Dart **3.13.7** (pinned; required by pdfrx later). Install from https://docs.flutter.dev/get-started/install.
- **Windows:** enable *Developer Mode* (symlinks) — needed once the PDF engine is added (Phase 4).
- PostgreSQL client + server 16 for the database tests (`psql` on PATH).
- Platform SDKs as usual: Xcode (iOS/macOS), Android SDK, Visual Studio (Windows desktop).

## Layout
```
lib/            app (features, data, design_system, app shell)
packages/sync_engine/   pure-Dart sync primitives + tests + tool/differential.dart (the tracker_engine package was removed)
supabase/       migrations/ and tests/ (SQL)
drift_schemas/  committed snapshot of every released local DB schema
test/           app tests (data, features, app)
spikes/         Phase 0 throwaway experiments (see spikes/RESULTS.md)
docs/ design/ architecture/
```

## Everyday commands
```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # after editing Drift tables
flutter analyze && flutter test                            # app
(cd packages/sync_engine && dart analyze && dart test)     # sync engine
```

## Database / server tests
Needs a throwaway Postgres 16 (not a Supabase project):
```bash
export PGHOST=localhost PGPORT=5432 PGUSER=postgres PGPASSWORD=...
supabase/tests/run.sh                                         # RLS + apply_changes assertions
(cd packages/sync_engine && dart run tool/differential.dart 300)   # Dart reference == Postgres
```
`supabase/tests/00_stub_auth.sql` emulates `auth.uid()`/roles **for tests only**.

## Running the app
```bash
flutter run -d <device>                       # local-only mode (no cloud)
flutter run -d <device> \
  --dart-define=SUPABASE_URL=https://<ref>.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=<publishable/anon key>
```
Apply `supabase/migrations/*.sql` to the project first. Never ship a service-role key.

## Changing the local schema
1. Edit tables in `lib/data/local/app_database.dart`, bump `schemaVersion`.
2. `dart run drift_dev schema dump lib/data/local/app_database.dart drift_schemas/`
3. `dart run drift_dev schema generate drift_schemas/ test/generated_migrations/`
4. Add the upgrade step in `migration.onUpgrade` and a `from N to M` test with seeded data.

## Changing the sync rules
The rule exists in **three** places that must agree: `packages/sync_engine/lib/src/resolve.dart`, the SQL in `supabase/migrations/*_sync_core.sql`, and (client apply) `lib/data/sync/synced_store.dart`. Change them together; `tool/differential.dart` and `supabase/tests` fail if the first two diverge.

## Adding a synced table
Add it to `lib/data/sync/synced_tables.dart` (field → column allow-list; `tasks` is the example) and to the `allowed_tbl` array in `apply_changes` (new migration), then write through `SyncedStore.setFields`. Never write synced columns directly.

## Secrets
Only the Supabase URL and publishable key are compiled into the app. Database encryption key lives in the OS secure store (`DatabaseKeyService`). Do not commit `.env` files or service-role keys.

## Testing rule: go through the real shell
Widget tests that pump a screen inside a bare `MaterialApp` can hide navigation bugs (e.g. `Navigator.pop(outerContext)` in a dialog works there but pops the *page* inside the app's nested shell navigator → blank screen). Every dialog/sheet must pop with **its own** `dialogContext`, and each user flow needs at least one test that starts from `TestEnv.app` (the real router + shell) — see `test/app/phone_layout_test.dart`.


## Cloud sync (Supabase)
1. In the Supabase dashboard → SQL Editor, run `supabase/migrations/20261106000000_sync_core.sql` once (creates the sync tables, row-level security and `apply_changes`).
2. Auth → Providers → Email: enabled. For a personal app, turn **Confirm email** off (otherwise sign-up needs a link that opens in a browser).
3. Build with the project URL and the *publishable* key (never the secret/service-role key):
   `flutter build apk --release --dart-define=SUPABASE_URL=https://<ref>.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=<key>`
   Without these the app runs local-only. The key is deliberately not committed.
4. Rules in the app: sync runs only when signed in; the first account to sync owns the device database, and a different account is refused rather than mixed in; "Local only" is remembered across restarts and can be left from Settings → Account → Sign in to sync.
