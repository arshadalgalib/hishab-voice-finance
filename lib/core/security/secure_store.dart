import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Narrow abstraction over platform secure storage.
///
/// Only three things ever live here — the PIN verifier, the biometric opt-in
/// flag and the *user supplied* cloud-speech token. Nothing else is stored in
/// secure storage, and no value from here is ever written to the SQLite
/// database, a backup file, a log line or a test fixture.
abstract class SecureStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);

  Future<Map<String, String>> readAll();

  Future<void> deleteAll();
}

/// Production implementation backed by `flutter_secure_storage`
/// (Android Keystore-backed EncryptedSharedPreferences).
class FlutterSecureStore implements SecureStore {
  FlutterSecureStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<Map<String, String>> readAll() => _storage.readAll();

  @override
  Future<void> deleteAll() => _storage.deleteAll();
}

/// In-memory implementation used by tests and by the "no secure storage on this
/// platform" fallback. It never touches the real keystore.
class InMemorySecureStore implements SecureStore {
  InMemorySecureStore([Map<String, String>? initial]) : _values = {...?initial};

  final Map<String, String> _values;

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);

  @override
  Future<Map<String, String>> readAll() async =>
      Map<String, String>.unmodifiable(_values);

  @override
  Future<void> deleteAll() async => _values.clear();
}
