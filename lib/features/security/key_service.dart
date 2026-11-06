import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class KeyStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Keychain (iOS/macOS), Keystore-backed storage (Android), Credential Locker/DPAPI (Windows).
class SecureStorageKeyStore implements KeyStore {
  SecureStorageKeyStore([FlutterSecureStorage? s])
      : _s = s ?? const FlutterSecureStorage(iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device));
  final FlutterSecureStorage _s;
  @override
  Future<String?> read(String key) => _s.read(key: key);
  @override
  Future<void> write(String key, String value) => _s.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _s.delete(key: key);
}

class InMemoryKeyStore implements KeyStore {
  final map = <String, String>{};
  @override
  Future<String?> read(String key) async => map[key];
  @override
  Future<void> write(String key, String value) async => map[key] = value;
  @override
  Future<void> delete(String key) async => map.remove(key);
}

/// Owns the 256-bit database key. Generated once from a CSPRNG and never leaves secure storage
/// except to open the database.
class DatabaseKeyService {
  DatabaseKeyService(this._store, {Random? random}) : _random = random ?? Random.secure();
  static const storageKey = 'folio.db.key.v1';
  final KeyStore _store;
  final Random _random;

  Future<String> getOrCreate() async {
    final existing = await _store.read(storageKey);
    if (existing != null) {
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(existing)) {
        // Never silently replace a damaged key: that would make the encrypted database unreadable.
        throw StateError('Stored database key is malformed; refusing to overwrite it.');
      }
      return existing;
    }
    final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    await _store.write(storageKey, hex);
    return hex;
  }
}
