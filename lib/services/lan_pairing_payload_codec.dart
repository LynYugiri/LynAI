import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';

import '../models/lan_pairing_payload.dart';
import 'device_identity_service.dart';

class LanPairingPayloadCodec {
  static const protocolVersion = 1;
  static const uriPrefix = 'lynai://pair/';
  static const maxEncodedBytes = 16 * 1024;
  static const _pairingDomain = 'LynAI/LAN/pairing/v1\x00';
  static const _bindingDomain = 'LynAI/LAN/tls-binding/v1\x00';

  final Ed25519 _ed25519 = Ed25519();

  Future<String> create({
    required DeviceIdentityService identityService,
    required String spkiSha256,
    required DateTime certificateExpiresAt,
    required String nonce,
    required List<String> addresses,
    required int port,
    required DateTime expiresAt,
  }) async {
    if (addresses.isEmpty ||
        addresses.length > 8 ||
        addresses.any((address) => !isAllowedLanAddress(address))) {
      throw const FormatException('invalid LAN pairing addresses');
    }
    final identity = await identityService.initialize();
    final unsigned = LanPairingPayload(
      version: protocolVersion,
      deviceId: identity.deviceId,
      publicKey: identity.publicKey,
      spkiSha256: spkiSha256,
      certificateExpiresAt: certificateExpiresAt,
      nonce: nonce,
      addresses: addresses,
      port: port,
      expiresAt: expiresAt,
      signature: const [],
    );
    final signature = await identityService.sign(
      _message(_pairingDomain, unsigned.unsignedJson()),
    );
    final payload = LanPairingPayload(
      version: unsigned.version,
      deviceId: unsigned.deviceId,
      publicKey: unsigned.publicKey,
      spkiSha256: unsigned.spkiSha256,
      certificateExpiresAt: unsigned.certificateExpiresAt,
      nonce: unsigned.nonce,
      addresses: unsigned.addresses,
      port: unsigned.port,
      expiresAt: unsigned.expiresAt,
      signature: signature,
    );
    final encoded =
        '$uriPrefix${_b64(utf8.encode(_canonical(payload.toJson())))}';
    if (encoded.length > maxEncodedBytes) {
      throw const FormatException('LAN pairing payload is too large');
    }
    return encoded;
  }

  Future<LanPairingPayload> decodeAndVerify(
    String encoded, {
    DateTime? now,
  }) async {
    if (!encoded.startsWith(uriPrefix)) {
      throw const FormatException('unsupported LAN pairing payload');
    }
    if (encoded.length > maxEncodedBytes) {
      throw const FormatException('LAN pairing payload is too large');
    }
    final json = jsonDecode(
      utf8.decode(_decode(encoded.substring(uriPrefix.length))),
    );
    if (json is! Map) throw const FormatException('invalid pairing payload');
    final payload = LanPairingPayload.fromJson(Map<String, dynamic>.from(json));
    if (payload.version != protocolVersion ||
        payload.publicKey.length != 32 ||
        payload.deviceId.isEmpty ||
        payload.deviceId.length > 128 ||
        payload.nonce.length < 20 ||
        payload.nonce.length > 128 ||
        payload.addresses.isEmpty ||
        payload.addresses.length > 8 ||
        payload.addresses.toSet().length != payload.addresses.length ||
        payload.addresses.any((address) => !isAllowedLanAddress(address)) ||
        payload.port < 1 ||
        payload.port > 65535 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(payload.spkiSha256)) {
      throw const FormatException('invalid pairing payload fields');
    }
    final expectedId = DeviceIdentityService.deviceIdForPublicKey(
      payload.publicKey,
    );
    if (expectedId != payload.deviceId) {
      throw const FormatException(
        'pairing device ID does not match public key',
      );
    }
    final valid = await _ed25519.verify(
      _message(_pairingDomain, payload.unsignedJson()),
      signature: Signature(
        payload.signature,
        publicKey: SimplePublicKey(
          payload.publicKey,
          type: KeyPairType.ed25519,
        ),
      ),
    );
    if (!valid) throw const FormatException('invalid pairing signature');
    final clock = (now ?? DateTime.now()).toUtc();
    if (!payload.expiresAt.toUtc().isAfter(clock) ||
        !payload.certificateExpiresAt.toUtc().isAfter(clock)) {
      throw const FormatException('pairing payload expired');
    }
    return payload;
  }

  Future<LanTlsBinding> createBinding({
    required DeviceIdentityService identityService,
    required String spkiSha256,
    required DateTime certificateExpiresAt,
    required String pairingNonce,
  }) async {
    final identity = await identityService.initialize();
    final unsigned = LanTlsBinding(
      version: protocolVersion,
      deviceId: identity.deviceId,
      publicKey: identity.publicKey,
      spkiSha256: spkiSha256,
      certificateExpiresAt: certificateExpiresAt,
      pairingNonce: pairingNonce,
      signature: const [],
    );
    return LanTlsBinding(
      version: unsigned.version,
      deviceId: unsigned.deviceId,
      publicKey: unsigned.publicKey,
      spkiSha256: unsigned.spkiSha256,
      certificateExpiresAt: unsigned.certificateExpiresAt,
      pairingNonce: unsigned.pairingNonce,
      signature: await identityService.sign(
        _message(_bindingDomain, unsigned.unsignedJson()),
      ),
    );
  }

  Future<bool> verifyBinding(LanTlsBinding binding) async {
    if (binding.version != protocolVersion ||
        DeviceIdentityService.deviceIdForPublicKey(binding.publicKey) !=
            binding.deviceId) {
      return false;
    }
    return _ed25519.verify(
      _message(_bindingDomain, binding.unsignedJson()),
      signature: Signature(
        binding.signature,
        publicKey: SimplePublicKey(
          binding.publicKey,
          type: KeyPairType.ed25519,
        ),
      ),
    );
  }

  static List<int> _message(String domain, Map<String, dynamic> json) => [
    ...utf8.encode(domain),
    ...utf8.encode(_canonical(json)),
  ];

  static String _canonical(Map<String, dynamic> value) => jsonEncode(
    Map<String, dynamic>.fromEntries(
      value.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    ),
  );

  static String _b64(List<int> bytes) =>
      base64UrlEncode(bytes).replaceAll('=', '');

  static List<int> _decode(String value) =>
      base64Url.decode(base64Url.normalize(value));

  static String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

  static bool isAllowedLanAddress(String value) {
    final address = InternetAddress.tryParse(value);
    if (address == null || address.isLoopback) return false;
    if (address.isLinkLocal) return true;
    final bytes = address.rawAddress;
    if (address.type == InternetAddressType.IPv4) {
      return bytes[0] == 10 ||
          (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
          (bytes[0] == 192 && bytes[1] == 168);
    }
    return bytes.length == 16 && (bytes[0] & 0xfe) == 0xfc;
  }
}
