import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

class WrongPasswordException implements Exception {
  @override
  String toString() => 'Wrong password, or the backup file is damaged.';
}

class DamagedBackupException implements Exception {
  DamagedBackupException([
    this.detail = 'The encrypted backup is damaged or incomplete.',
  ]);
  final String detail;
  @override
  String toString() => detail;
}

/// Password protection for backup files (optional).
///
/// File layout:  "FOLIOENC" 0x01 | salt(16) | iterations(u32) | nonce base(12) | chunk size(u32) |
///               repeated: length(u32) | AES-256-GCM(ciphertext + 16-byte tag)
/// The key comes from PBKDF2-HMAC-SHA256 (salted, many iterations). The plaintext (the backup zip) is cut into
/// chunks so big libraries never have to fit in memory. Each chunk is authenticated together with the header, its
/// position and a "final chunk" flag, so a wrong password, a changed byte, reordered chunks or a truncated file are
/// all detected instead of producing garbage.
class BackupCrypto {
  static const magic = [
    0x46,
    0x4f,
    0x4c,
    0x49,
    0x4f,
    0x45,
    0x4e,
    0x43,
  ]; // FOLIOENC
  static const version = 1;
  static const defaultIterations = 150000;
  static const defaultChunk = 1 << 20;
  static const _headerLen = 8 + 1 + 16 + 4 + 12 + 4;
  static const _maxIterations = 5000000;
  static const _maxChunk = 64 << 20;

  static final _gcm = AesGcm.with256bits();

  static Future<bool> isEncrypted(File f) async {
    final raf = await f.open();
    try {
      final head = await raf.read(magic.length);
      if (head.length != magic.length) return false;
      for (var i = 0; i < magic.length; i++) {
        if (head[i] != magic[i]) return false;
      }
      return true;
    } finally {
      await raf.close();
    }
  }

  static Future<SecretKey> _key(
    String password,
    List<int> salt,
    int iterations,
  ) => Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: iterations,
    bits: 256,
  ).deriveKeyFromPassword(password: password, nonce: salt);

  static Uint8List _u32(int v) =>
      Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.big);

  static List<int> _nonce(List<int> base, int index) {
    final n = Uint8List.fromList(base);
    final d = n.buffer.asByteData();
    d.setUint32(8, d.getUint32(8, Endian.big) ^ index, Endian.big);
    return n;
  }

  static List<int> _aad(List<int> header, int index, bool last) => [
    ...header,
    ..._u32(index),
    last ? 1 : 0,
  ];

  static Uint8List _random(int n) {
    final r = Random.secure();
    return Uint8List.fromList([for (var i = 0; i < n; i++) r.nextInt(256)]);
  }

  /// Encrypts [source] into [dest].
  static Future<void> encryptFile(
    File source,
    File dest,
    String password, {
    int iterations = defaultIterations,
    int chunkSize = defaultChunk,
  }) async {
    if (password.isEmpty) throw ArgumentError('A password is required.');
    final salt = _random(16), nonceBase = _random(12);
    final header = Uint8List.fromList([
      ...magic,
      version,
      ...salt,
      ..._u32(iterations),
      ...nonceBase,
      ..._u32(chunkSize),
    ]);
    final key = await _key(password, salt, iterations);
    final input = await source.open();
    final out = await dest.open(mode: FileMode.write);
    try {
      await out.writeFrom(header);
      var index = 0;
      var current = await input.read(chunkSize);
      while (true) {
        final next = current.length < chunkSize
            ? Uint8List(0)
            : await input.read(chunkSize);
        final last = next.isEmpty;
        final box = await _gcm.encrypt(
          current,
          secretKey: key,
          nonce: _nonce(nonceBase, index),
          aad: _aad(header, index, last),
        );
        await out.writeFrom(_u32(current.length));
        await out.writeFrom(box.cipherText);
        await out.writeFrom(box.mac.bytes);
        if (last) break;
        current = next;
        index++;
      }
    } catch (_) {
      await out.close();
      if (await dest.exists()) await dest.delete();
      rethrow;
    } finally {
      await input.close();
    }
    await out.close();
  }

  /// Decrypts [source] into [dest]. Throws [WrongPasswordException] or [DamagedBackupException]; [dest] is removed on failure.
  static Future<void> decryptFile(
    File source,
    File dest,
    String password,
  ) async {
    final total = await source.length();
    final input = await source.open();
    RandomAccessFile? out;
    try {
      final header = await input.read(_headerLen);
      if (header.length != _headerLen ||
          !_hasMagic(header) ||
          header[8] != version) {
        throw DamagedBackupException(
          'This is not a valid encrypted Folio backup.',
        );
      }
      final d = header.buffer.asByteData(header.offsetInBytes);
      final iterations = d.getUint32(8 + 1 + 16, Endian.big);
      final chunkSize = d.getUint32(8 + 1 + 16 + 4 + 12, Endian.big);
      if (iterations < 1 ||
          iterations > _maxIterations ||
          chunkSize < 1 ||
          chunkSize > _maxChunk) {
        throw DamagedBackupException();
      }
      final salt = header.sublist(9, 25), nonceBase = header.sublist(29, 41);
      final key = await _key(password, salt, iterations);
      out = await dest.open(mode: FileMode.write);
      var index = 0;
      while (true) {
        final lenBytes = await input.read(4);
        if (lenBytes.length != 4) throw DamagedBackupException();
        final len = lenBytes.buffer
            .asByteData(lenBytes.offsetInBytes)
            .getUint32(0, Endian.big);
        if (len > chunkSize) throw DamagedBackupException();
        final body = await input.read(len + 16);
        if (body.length != len + 16) throw DamagedBackupException();
        final last = await input.position() >= total;
        try {
          final plain = await _gcm.decrypt(
            SecretBox(
              body.sublist(0, len),
              nonce: _nonce(nonceBase, index),
              mac: Mac(body.sublist(len)),
            ),
            secretKey: key,
            aad: _aad(header, index, last),
          );
          await out.writeFrom(plain);
        } on SecretBoxAuthenticationError {
          // the very first chunk failing almost always means a wrong password
          throw index == 0
              ? WrongPasswordException()
              : DamagedBackupException();
        }
        if (last) break;
        index++;
      }
    } catch (_) {
      await out?.close();
      out = null;
      if (await dest.exists()) await dest.delete();
      rethrow;
    } finally {
      await input.close();
    }
    await out.close();
  }

  static bool _hasMagic(List<int> h) {
    for (var i = 0; i < magic.length; i++) {
      if (h[i] != magic[i]) return false;
    }
    return true;
  }
}
