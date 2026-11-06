// Spike S-3: encryption + FTS5 + isolate use with package:sqlite3 3.x
import 'dart:io';
import 'dart:isolate';
import 'package:sqlite3/sqlite3.dart';

Future<void> main() async {
  print('sqlite ${sqlite3.version}');
  final dir = Directory.systemTemp.createTempSync('s3');
  final path = '${dir.path}/enc.db';
  final db = sqlite3.open(path);
  final cipherInfo = <String>[];
  for (final q in ['PRAGMA cipher_version', 'PRAGMA cipher']) {
    try { cipherInfo.add('$q -> ${db.select(q)}'); } catch (e) { cipherInfo.add('$q failed: $e'); }
  }
  print(cipherInfo.join('\n'));
  final hasCipher = db.select('PRAGMA cipher_version').isNotEmpty || db.select('PRAGMA cipher').isNotEmpty;
  print('encryption available: $hasCipher');
  if (hasCipher) {
    db.execute("PRAGMA key = 'correct horse battery staple'");
    db.execute('CREATE TABLE t(x TEXT)');
    db.execute("INSERT INTO t VALUES('secret-notes-content')");
    db.execute("CREATE VIRTUAL TABLE f USING fts5(a)");
    db.execute("INSERT INTO f VALUES('encrypted full text search works')");
    print('fts under encryption: ${db.select("SELECT * FROM f WHERE f MATCH 'search'").length} hit');
    db.dispose();
    final raw = File(path).readAsBytesSync();
    final leaks = String.fromCharCodes(raw).contains('secret-notes-content');
    print('plaintext visible on disk: $leaks');
    final wrong = sqlite3.open(path);
    try { wrong.execute("PRAGMA key = 'wrong'"); wrong.select('SELECT * FROM t'); print('wrong key: READ OK (BAD)'); } catch (e) { print('wrong key rejected: ${e.toString().split("\n").first}'); }
    wrong.dispose();
    final ok = sqlite3.open(path);
    ok.execute("PRAGMA key = 'correct horse battery staple'");
    print('right key rows: ${ok.select("SELECT * FROM t").length}');
    // second connection from another isolate
    final n = await Isolate.run(() {
      final c = sqlite3.open(path); c.execute("PRAGMA key = 'correct horse battery staple'");
      return c.select('SELECT * FROM t').length;
    });
    print('isolate connection rows: $n');
  }
  dir.deleteSync(recursive: true);
}
