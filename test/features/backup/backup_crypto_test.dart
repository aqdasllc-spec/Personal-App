import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/features/backup/backup_crypto.dart';
import 'package:folio/features/backup/backup_service.dart';
import 'package:folio/features/planner/data/planner_repository.dart';

import 'backup_service_test.dart' show Device;

const fast = 1000; // PBKDF2 iterations for tests (real default: 150 000)

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('enc'));
  tearDown(() => dir.deleteSync(recursive: true));

  Uint8List data(int n) => Uint8List.fromList([for (var i = 0; i < n; i++) (i * 31 + 7) & 0xff]);
  File write(String name, List<int> bytes) => File('${dir.path}/$name')..writeAsBytesSync(bytes);

  Future<File> encrypt(List<int> plain, {String pw = 'correct horse', int chunk = 100}) async {
    final src = write('plain.bin', plain);
    final out = File('${dir.path}/enc.bin');
    await BackupCrypto.encryptFile(src, out, pw, iterations: fast, chunkSize: chunk);
    return out;
  }

  Future<List<int>> decrypt(File enc, String pw) async {
    final out = File('${dir.path}/out.bin');
    await BackupCrypto.decryptFile(enc, out, pw);
    return out.readAsBytesSync();
  }

  test('round trip across chunk boundaries (empty, short, exact multiple, long)', () async {
    for (final n in [0, 1, 99, 100, 101, 200, 1234]) {
      final plain = data(n);
      final enc = await encrypt(plain);
      expect(await decrypt(enc, 'correct horse'), plain, reason: '$n bytes');
      expect(await BackupCrypto.isEncrypted(enc), isTrue);
    }
  });

  test('the file reveals nothing readable and differs every time (random salt/nonce)', () async {
    final plain = Uint8List.fromList(List.filled(500, 65)); // "AAAA..."
    final a = await encrypt(plain);
    final bytesA = a.readAsBytesSync();
    expect(String.fromCharCodes(bytesA).contains('AAAAAAAA'), isFalse);
    File('${dir.path}/enc.bin').deleteSync();
    final b = await encrypt(plain);
    expect(b.readAsBytesSync(), isNot(bytesA));
  });

  test('wrong or empty password is rejected cleanly and leaves no output file', () async {
    final enc = await encrypt(data(350));
    final out = File('${dir.path}/out.bin');
    await expectLater(BackupCrypto.decryptFile(enc, out, 'nope'), throwsA(isA<WrongPasswordException>()));
    expect(out.existsSync(), isFalse);
    await expectLater(BackupCrypto.encryptFile(write('p', [1]), File('${dir.path}/x'), ''), throwsArgumentError);
  });

  test('any changed byte, a truncated file, dropped/reordered chunks or garbage are detected', () async {
    final plain = data(450); // 5 chunks of 100
    final enc = await encrypt(plain);
    final original = enc.readAsBytesSync();
    final out = File('${dir.path}/out.bin');

    // flip a bit in the middle of the ciphertext, in the header, and in the last byte (a tag)
    for (final at in [original.length ~/ 2, 12, original.length - 1]) {
      final bad = Uint8List.fromList(original)..[at] ^= 1;
      await expectLater(BackupCrypto.decryptFile(write('bad.bin', bad), out, 'correct horse'), throwsA(anyOf(isA<WrongPasswordException>(), isA<DamagedBackupException>())), reason: 'byte $at');
      expect(out.existsSync(), isFalse);
    }
    // truncated exactly after a whole chunk: must not silently return a shorter backup
    final chunkLen = 4 + 100 + 16;
    final truncated = original.sublist(0, 41 + 4 + chunkLen * 3);
    await expectLater(BackupCrypto.decryptFile(write('trunc.bin', truncated), out, 'correct horse'), throwsA(isA<DamagedBackupException>()));
    // swap two chunks
    final c1 = original.sublist(45, 45 + chunkLen), c2 = original.sublist(45 + chunkLen, 45 + 2 * chunkLen);
    final swapped = Uint8List.fromList([...original.sublist(0, 45), ...c2, ...c1, ...original.sublist(45 + 2 * chunkLen)]);
    // (45 = 41-byte header incl. chunk size + first length field is inside chunkLen; layout is header | chunks)
    await expectLater(BackupCrypto.decryptFile(write('swap.bin', swapped), out, 'correct horse'), throwsA(anyOf(isA<WrongPasswordException>(), isA<DamagedBackupException>())));
    await expectLater(BackupCrypto.decryptFile(write('junk.bin', data(300)), out, 'x'), throwsA(isA<DamagedBackupException>()));
    expect(await BackupCrypto.isEncrypted(write('junk2.bin', data(300))), isFalse);
  });

  group('password protected backups end to end', () {
    late Device a;
    late Directory work;
    setUp(() async {
      a = await Device.create();
      work = Directory.systemTemp.createTempSync('encbk');
    });
    tearDown(() async {
      await a.close();
      work.deleteSync(recursive: true);
    });

    BackupService svcFor(Device d) => BackupService(d.env.db, d.env.store, libraryDir: d.libDir, kdfIterations: fast, chunkSize: 4096, scratch: work);

    test('create with a password, inspect/restore need it, wrong password refused, no readable copy left behind', () async {
      await a.planner.saveTask(const TaskInput(title: 'Secret plan'));
      final book = (await a.lib.importPdf((File('${work.path}/s.pdf')..writeAsStringSync('pages=9')).path)).book!;
      final svc = svcFor(a);
      final file = await svc.create(work, password: 'hunter22!');
      expect(await svc.isEncrypted(file.path), isTrue);
      expect(String.fromCharCodes(file.readAsBytesSync()).contains('Secret plan'), isFalse);
      expect(work.listSync().where((e) => e.path.endsWith('.part') || e.path.contains('folio-restore')), isEmpty, reason: 'no plaintext zip left in the folder');

      await expectLater(svc.inspect(file.path), throwsA(isA<BackupPasswordRequired>()));
      await expectLater(svc.inspect(file.path, password: 'wrong'), throwsA(isA<BackupWrongPassword>()));
      final info = await svc.inspect(file.path, password: 'hunter22!');
      expect((info.tasks, info.books, info.encrypted), (1, 1, true));

      final b = await Device.create();
      addTearDown(b.close);
      final r = await svcFor(b).restore(file.path, password: 'hunter22!');
      expect((r.tasks, r.books), (1, 1));
      expect((await b.planner.tasks()).single.title, 'Secret plan');
      expect(b.lib.fileOf(book).readAsStringSync(), 'pages=9', reason: 'the PDF came back too');
      expect(work.listSync().where((e) => e.path.contains('folio-restore')), isEmpty, reason: 'the decrypted temp copy is removed');
    });

    test('without a password the backup is a plain zip as before; an empty password means no encryption', () async {
      final svc = svcFor(a);
      final f1 = await svc.create(work);
      expect(await svc.isEncrypted(f1.path), isFalse);
      final f2 = await BackupService(a.env.db, a.env.store, libraryDir: a.libDir, now: () => DateTime(2030, 1, 1)).create(work, password: '');
      expect(await svc.isEncrypted(f2.path), isFalse);
      expect((await svc.inspect(f1.path)).encrypted, isFalse);
    });
  });
}
