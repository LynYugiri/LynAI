import 'package:flutter/foundation.dart';

/// Stable public identity of this application installation.
@immutable
class DeviceIdentity {
  DeviceIdentity({required this.deviceId, required List<int> publicKey})
    : publicKey = List.unmodifiable(publicKey);

  /// Lowercase, unpadded Base32 SHA-256 fingerprint of [publicKey].
  final String deviceId;

  /// Ed25519 public key bytes.
  final List<int> publicKey;
}

/// Stored device identity material is incomplete, malformed, or inconsistent.
class DeviceIdentityCorruptedException implements Exception {
  const DeviceIdentityCorruptedException(this.message);

  final String message;

  @override
  String toString() => 'DeviceIdentityCorruptedException: $message';
}
