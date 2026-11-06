import 'dart:io';

import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'app_database.dart';

/// Opens the encrypted database. [hexKey] is a 256-bit key from secure storage.
/// Throws [WrongDatabaseKeyException] if the file exists but the key is wrong.
class WrongDatabaseKeyException implements Exception {
  @override
  String toString() => 'The database could not be decrypted with the supplied key.';
}

AppDatabase openEncrypted(File file, String hexKey, {bool logStatements = false}) {
  return AppDatabase(NativeDatabase.createInBackground(
    file,
    logStatements: logStatements,
    setup: (raw) => applyKey(raw, hexKey),
  ));
}

/// In-memory, unencrypted - tests only.
AppDatabase openInMemory() => AppDatabase(NativeDatabase.memory());

/// Applies the key and verifies it by reading the schema.
void applyKey(Database raw, String hexKey) {
  assert(RegExp(r'^[0-9a-f]{64}$').hasMatch(hexKey), 'key must be 32 bytes of lowercase hex');
  // Raw-key syntax avoids passphrase KDF cost; the key is already 256 random bits.
  raw.execute("PRAGMA key = \"x'$hexKey'\"");
  try {
    raw.select('SELECT count(*) FROM sqlite_master');
  } on SqliteException {
    throw WrongDatabaseKeyException();
  }
}

Future<File> defaultDatabaseFile() async {
  final dir = await getApplicationSupportDirectory();
  return File(p.join(dir.path, 'folio.db'));
}
