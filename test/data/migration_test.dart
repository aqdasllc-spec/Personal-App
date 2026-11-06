import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/data/local/database_opener.dart';

import '../generated_migrations/schema.dart';

/// Every released schema version is snapshotted in drift_schemas/. When you bump
/// `schemaVersion`: run `dart run drift_dev schema dump ...`, regenerate helpers, add an
/// upgrade step in AppDatabase.migration and add a `from N to M` test below (with seeded data).
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;
  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  test('a fresh install matches the committed v1 schema exactly', () async {
    final connection = await verifier.startAt(1);
    final db = AppDatabase(connection);
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 1);
  });

  test('current schemaVersion has a committed snapshot (forgot to dump?)', () {
    final db = openInMemory();
    addTearDown(db.close);
    expect(GeneratedHelper.versions, contains(db.schemaVersion), reason: 'run drift_dev schema dump for v${db.schemaVersion}');
  });
}

