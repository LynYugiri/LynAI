import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';

import '../models/device_identity.dart';
import 'backend_uri.dart';
import 'secret_store.dart';

/// Creates and uses the stable Ed25519 identity for this installation.
class DeviceIdentityService {
  DeviceIdentityService({required SecretStore secretStore})
    : _secretStore = secretStore;

  static const privateKeySecretKey = 'device_identity.ed25519.private_key';
  static const publicKeySecretKey = 'device_identity.ed25519.public_key';
  static const deviceIdSecretKey = 'device_identity.id';
  static const identityRecordSecretKey = 'device_identity.record.v1';
  static const identityStagingSecretKey = 'device_identity.record.v1.staging';
  static const lanScope = 'lan:v1';

  final SecretStore _secretStore;
  final Ed25519 _algorithm = Ed25519();

  final Map<String, DeviceIdentity> _identities = {};
  final Map<String, SimpleKeyPair> _keyPairs = {};
  final Map<String, Future<DeviceIdentity>> _initializations = {};

  /// Returns the initialized identity, creating it exactly once when absent.
  Future<DeviceIdentity> initialize({String scope = lanScope}) {
    final normalizedScope = _normalizeScope(scope);
    final identity = _identities[normalizedScope];
    if (identity != null) return Future.value(identity);
    return _initializations[normalizedScope] ??= _initialize(normalizedScope)
        .whenComplete(() {
          _initializations.remove(normalizedScope);
        });
  }

  /// Signs [message] with this installation's Ed25519 private key.
  Future<List<int>> sign(List<int> message, {String scope = lanScope}) async {
    final normalizedScope = _normalizeScope(scope);
    await initialize(scope: normalizedScope);
    final signature = await _algorithm.sign(
      message,
      keyPair: _keyPairs[normalizedScope]!,
    );
    return List.unmodifiable(signature.bytes);
  }

  Future<DeviceIdentity> _initialize(String scope) async {
    final recordKey = _recordKey(scope);
    final stagingKey = _stagingKey(scope);
    final migrateLegacy = scope == lanScope;
    final stored = await Future.wait([
      _secretStore.read(recordKey),
      _secretStore.read(stagingKey),
      if (migrateLegacy) _secretStore.read(privateKeySecretKey),
      if (migrateLegacy) _secretStore.read(publicKeySecretKey),
      if (migrateLegacy) _secretStore.read(deviceIdSecretKey),
    ]);
    final recordValue = stored[0];
    final stagingValue = stored[1];
    if (recordValue != null) {
      final loaded = await _loadRecord(recordValue, scope: scope);
      if (stagingValue != null) {
        try {
          final staged = await _loadRecord(
            stagingValue,
            scope: scope,
            cache: false,
          );
          if (staged.deviceId != loaded.deviceId) {
            // The committed identity is authoritative after any interrupted write.
          }
        } catch (_) {
          // A valid committed record is authoritative over abandoned staging.
        }
        await _deleteBestEffort(stagingKey);
      }
      if (migrateLegacy) await _deleteLegacyBestEffort();
      return loaded;
    }
    final privateKeyValue = migrateLegacy ? stored[2] : null;
    final publicKeyValue = migrateLegacy ? stored[3] : null;
    final deviceIdValue = migrateLegacy ? stored[4] : null;

    if (privateKeyValue == null &&
        publicKeyValue == null &&
        deviceIdValue == null) {
      if (stagingValue != null) {
        await _loadRecord(stagingValue, scope: scope, cache: false);
        await _secretStore.write(recordKey, stagingValue);
        await _deleteBestEffort(stagingKey);
        return _loadRecord(stagingValue, scope: scope);
      }
      return _createIdentity(scope);
    }
    if (privateKeyValue == null ||
        publicKeyValue == null ||
        deviceIdValue == null) {
      throw const DeviceIdentityCorruptedException(
        'stored identity is incomplete',
      );
    }

    late String record;
    try {
      record = _encodeRecord(
        base64Decode(privateKeyValue),
        base64Decode(publicKeyValue),
        deviceIdValue,
      );
    } catch (error) {
      throw DeviceIdentityCorruptedException(error.toString());
    }
    final identity = await _loadRecord(record, scope: scope, cache: false);
    if (stagingValue != null) {
      try {
        final staged = await _loadRecord(
          stagingValue,
          scope: scope,
          cache: false,
        );
        if (staged.deviceId != identity.deviceId) {
          await _deleteBestEffort(stagingKey);
        }
      } catch (_) {
        await _deleteBestEffort(stagingKey);
      }
    }
    await _secretStore.write(stagingKey, record);
    await _secretStore.write(recordKey, record);
    await _deleteBestEffort(stagingKey);
    await _deleteLegacyBestEffort();
    return _loadRecord(record, scope: scope);
  }

  Future<DeviceIdentity> _createIdentity(String scope) async {
    final keyPair = await _algorithm.newKeyPair();
    final extracted = await keyPair.extract();
    final privateKey = await extracted.extractPrivateKeyBytes();
    final publicKey = (await extracted.extractPublicKey()).bytes;
    final deviceId = deviceIdForPublicKey(publicKey);

    final record = _encodeRecord(privateKey, publicKey, deviceId);
    await _secretStore.write(_stagingKey(scope), record);
    await _secretStore.write(_recordKey(scope), record);
    await _deleteBestEffort(_stagingKey(scope));
    _keyPairs[scope] = extracted;
    final identity = DeviceIdentity(deviceId: deviceId, publicKey: publicKey);
    _identities[scope] = identity;
    return identity;
  }

  String _encodeRecord(
    List<int> privateKey,
    List<int> publicKey,
    String deviceId,
  ) => jsonEncode({
    'version': 1,
    'deviceId': deviceId,
    'privateKey': base64Encode(privateKey),
    'publicKey': base64Encode(publicKey),
  });

  Future<DeviceIdentity> _loadRecord(
    String value, {
    required String scope,
    bool cache = true,
  }) async {
    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map || decoded['version'] != 1) {
        throw const FormatException('unsupported identity record');
      }
      final privateKey = base64Decode(decoded['privateKey'] as String);
      final publicKey = base64Decode(decoded['publicKey'] as String);
      final deviceId = decoded['deviceId'] as String;
      if (privateKey.length != 32 || publicKey.length != 32) {
        throw const FormatException('invalid Ed25519 key length');
      }
      final expectedDeviceId = deviceIdForPublicKey(publicKey);
      if (deviceId != expectedDeviceId) {
        throw const FormatException('device ID does not match public key');
      }
      final keyPair = SimpleKeyPairData(
        privateKey,
        publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
        type: KeyPairType.ed25519,
      );
      final probe = utf8.encode('lynai-device-identity-check');
      final signature = await _algorithm.sign(probe, keyPair: keyPair);
      if (!await _algorithm.verify(probe, signature: signature)) {
        throw const FormatException('private and public keys do not match');
      }
      final identity = DeviceIdentity(
        deviceId: expectedDeviceId,
        publicKey: publicKey,
      );
      if (cache) {
        _keyPairs[scope] = keyPair;
        _identities[scope] = identity;
      }
      return identity;
    } catch (error) {
      throw DeviceIdentityCorruptedException(error.toString());
    }
  }

  Future<void> _deleteLegacyBestEffort() async {
    for (final key in const [
      privateKeySecretKey,
      publicKeySecretKey,
      deviceIdSecretKey,
    ]) {
      await _deleteBestEffort(key);
    }
  }

  Future<void> _deleteBestEffort(String key) async {
    try {
      await _secretStore.delete(key);
    } catch (_) {}
  }

  static String deviceIdForPublicKey(List<int> publicKey) {
    return _base32LowerNoPadding(sha256.convert(publicKey).bytes);
  }

  static String accountScope(String backendUrl, String userId) {
    final origin = backendOrigin(backendUrl);
    final normalizedUserId = userId.trim();
    if (origin.isEmpty || normalizedUserId.isEmpty) {
      throw ArgumentError('backend origin and userId are required');
    }
    return 'account:$origin|$normalizedUserId';
  }

  static String backendOrigin(String value) {
    return normalizedBackendOrigin(value);
  }

  static bool isInsecureHttp(String value) => isInsecureHttpBackend(value);

  static String? insecureHttpWarning(String value) =>
      insecureHttpBackendWarning(value);

  static String _normalizeScope(String scope) {
    final normalized = scope.trim();
    if (normalized.isEmpty) throw ArgumentError.value(scope, 'scope');
    return normalized;
  }

  static String _scopeSuffix(String scope) => base64UrlEncode(
    sha256.convert(utf8.encode(scope)).bytes,
  ).replaceAll('=', '');

  static String _recordKey(String scope) => scope == lanScope
      ? identityRecordSecretKey
      : '$identityRecordSecretKey.${_scopeSuffix(scope)}';

  static String _stagingKey(String scope) => scope == lanScope
      ? identityStagingSecretKey
      : '$identityStagingSecretKey.${_scopeSuffix(scope)}';

  static String _base32LowerNoPadding(List<int> bytes) {
    const alphabet = 'abcdefghijklmnopqrstuvwxyz234567';
    final output = StringBuffer();
    var buffer = 0;
    var bits = 0;
    for (final byte in bytes) {
      buffer = (buffer << 8) | byte;
      bits += 8;
      while (bits >= 5) {
        bits -= 5;
        output.write(alphabet[(buffer >> bits) & 31]);
      }
    }
    if (bits > 0) {
      output.write(alphabet[(buffer << (5 - bits)) & 31]);
    }
    return output.toString();
  }
}
