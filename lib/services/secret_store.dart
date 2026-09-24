import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../utils/platform_info.dart';

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

/// 鸿蒙（HarmonyOS / OpenHarmony）上的 [SecretStore]，底层是系统关键资产库。
///
/// `flutter_secure_storage` 的平台分发只覆盖 Web/Android/iOS/Linux/macOS/
/// Windows，鸿蒙上 `_selectOptions` 会直接抛 `UnsupportedError`，因此鸿蒙改用
/// `lynai/secure_storage` 通道；原生实现（ohos/entry/src/main/ets/lynai/
/// LynaiSecureStorage.ets）基于 Asset Store Kit，关键资产由 HUKS 加密后落库，
/// 与 Android Keystore / iOS Keychain 处于同一保护等级。
class OhosAssetSecretStore implements SecretStore {
  OhosAssetSecretStore({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('lynai/secure_storage');

  final MethodChannel _channel;

  @override
  Future<String?> read(String key) async {
    final value = await _channel.invokeMethod<String>('read', {'key': key});
    return value;
  }

  @override
  Future<void> write(String key, String value) =>
      _channel.invokeMethod<void>('write', {'key': key, 'value': value});

  @override
  Future<void> delete(String key) =>
      _channel.invokeMethod<void>('delete', {'key': key});
}

/// 按平台选择生产环境的 [SecretStore]。
///
/// 鸿蒙之外的平台仍然使用 [FlutterSecureSecretStore]，行为不变。
SecretStore createDefaultSecretStore() =>
    isOhosPlatform ? OhosAssetSecretStore() : FlutterSecureSecretStore();

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
