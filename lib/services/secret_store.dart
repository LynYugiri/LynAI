import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persistent storage for sensitive string values.
abstract interface class SecretStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

/// Production [SecretStore] backed by platform-protected storage.
class FlutterSecureSecretStore implements SecretStore {
  FlutterSecureSecretStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Deterministic [SecretStore] for unit and widget tests.
class InMemorySecretStore implements SecretStore {
  InMemorySecretStore([Map<String, String> initialValues = const {}])
    : _values = Map.of(initialValues);

  final Map<String, String> _values;

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}
