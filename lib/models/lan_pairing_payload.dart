import 'dart:convert';

class LanPairingPayload {
  LanPairingPayload({
    required this.version,
    required this.deviceId,
    required List<int> publicKey,
    required this.spkiSha256,
    required this.certificateExpiresAt,
    required this.nonce,
    required this.addresses,
    required this.port,
    required this.expiresAt,
    required List<int> signature,
  }) : publicKey = List.unmodifiable(publicKey),
       signature = List.unmodifiable(signature);

  final int version;
  final String deviceId;
  final List<int> publicKey;
  final String spkiSha256;
  final DateTime certificateExpiresAt;
  final String nonce;
  final List<String> addresses;
  final int port;
  final DateTime expiresAt;
  final List<int> signature;

  Map<String, dynamic> unsignedJson() => {
    'v': version,
    'deviceId': deviceId,
    'publicKey': _b64(publicKey),
    'spki': spkiSha256,
    'certExp': certificateExpiresAt.toUtc().millisecondsSinceEpoch,
    'nonce': nonce,
    'addresses': [...addresses]..sort(),
    'port': port,
    'expires': expiresAt.toUtc().millisecondsSinceEpoch,
  };

  Map<String, dynamic> toJson() => {
    ...unsignedJson(),
    'signature': _b64(signature),
  };

  factory LanPairingPayload.fromJson(Map<String, dynamic> json) =>
      LanPairingPayload(
        version: (json['v'] as num).toInt(),
        deviceId: json['deviceId'] as String,
        publicKey: _decode(json['publicKey'] as String),
        spkiSha256: json['spki'] as String,
        certificateExpiresAt: DateTime.fromMillisecondsSinceEpoch(
          (json['certExp'] as num).toInt(),
          isUtc: true,
        ),
        nonce: json['nonce'] as String,
        addresses: (json['addresses'] as List).cast<String>(),
        port: (json['port'] as num).toInt(),
        expiresAt: DateTime.fromMillisecondsSinceEpoch(
          (json['expires'] as num).toInt(),
          isUtc: true,
        ),
        signature: _decode(json['signature'] as String),
      );

  static String _b64(List<int> bytes) =>
      base64UrlEncode(bytes).replaceAll('=', '');

  static List<int> _decode(String value) =>
      base64Url.decode(base64Url.normalize(value));
}

class LanTlsBinding {
  LanTlsBinding({
    required this.version,
    required this.deviceId,
    required List<int> publicKey,
    required this.spkiSha256,
    required this.certificateExpiresAt,
    required this.pairingNonce,
    required List<int> signature,
  }) : publicKey = List.unmodifiable(publicKey),
       signature = List.unmodifiable(signature);

  final int version;
  final String deviceId;
  final List<int> publicKey;
  final String spkiSha256;
  final DateTime certificateExpiresAt;
  final String pairingNonce;
  final List<int> signature;

  Map<String, dynamic> unsignedJson() => {
    'v': version,
    'deviceId': deviceId,
    'publicKey': base64UrlEncode(publicKey).replaceAll('=', ''),
    'spki': spkiSha256,
    'certExp': certificateExpiresAt.toUtc().millisecondsSinceEpoch,
    'nonce': pairingNonce,
  };

  Map<String, dynamic> toJson() => {
    ...unsignedJson(),
    'signature': base64UrlEncode(signature).replaceAll('=', ''),
  };

  factory LanTlsBinding.fromJson(Map<String, dynamic> json) => LanTlsBinding(
    version: (json['v'] as num).toInt(),
    deviceId: json['deviceId'] as String,
    publicKey: base64Url.decode(
      base64Url.normalize(json['publicKey'] as String),
    ),
    spkiSha256: json['spki'] as String,
    certificateExpiresAt: DateTime.fromMillisecondsSinceEpoch(
      (json['certExp'] as num).toInt(),
      isUtc: true,
    ),
    pairingNonce: json['nonce'] as String,
    signature: base64Url.decode(
      base64Url.normalize(json['signature'] as String),
    ),
  );
}
