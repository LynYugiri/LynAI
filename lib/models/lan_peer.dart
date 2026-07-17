import 'dart:convert';

class LanPeer {
  LanPeer({
    required this.deviceId,
    required List<int> publicKey,
    required this.spkiSha256,
    required this.displayName,
    required this.trustedAt,
    required this.certificateExpiresAt,
    this.lastSeenAt,
    this.revokedAt,
    this.lastAcknowledgedChangeId,
  }) : publicKey = List.unmodifiable(publicKey);

  final String deviceId;
  final List<int> publicKey;
  final String spkiSha256;
  final String displayName;
  final DateTime trustedAt;
  final DateTime certificateExpiresAt;
  final DateTime? lastSeenAt;
  final DateTime? revokedAt;
  final String? lastAcknowledgedChangeId;

  bool get revoked => revokedAt != null;

  String get fingerprint => deviceId
      .replaceAllMapped(RegExp(r'.{4}'), (match) => '${match.group(0)} ')
      .trim();

  LanPeer copyWith({
    String? displayName,
    DateTime? lastSeenAt,
    Object? revokedAt = _unset,
    String? lastAcknowledgedChangeId,
    DateTime? certificateExpiresAt,
  }) => LanPeer(
    deviceId: deviceId,
    publicKey: publicKey,
    spkiSha256: spkiSha256,
    displayName: displayName ?? this.displayName,
    trustedAt: trustedAt,
    certificateExpiresAt: certificateExpiresAt ?? this.certificateExpiresAt,
    lastSeenAt: lastSeenAt ?? this.lastSeenAt,
    revokedAt: identical(revokedAt, _unset)
        ? this.revokedAt
        : revokedAt as DateTime?,
    lastAcknowledgedChangeId:
        lastAcknowledgedChangeId ?? this.lastAcknowledgedChangeId,
  );

  Map<String, dynamic> toJson() => {
    'deviceId': deviceId,
    'publicKey': base64UrlEncode(publicKey).replaceAll('=', ''),
    'spkiSha256': spkiSha256,
    'displayName': displayName,
    'trustedAt': trustedAt.toUtc().toIso8601String(),
    'certificateExpiresAt': certificateExpiresAt.toUtc().toIso8601String(),
    if (lastSeenAt != null) 'lastSeenAt': lastSeenAt!.toUtc().toIso8601String(),
    if (revokedAt != null) 'revokedAt': revokedAt!.toUtc().toIso8601String(),
    if (lastAcknowledgedChangeId != null)
      'lastAcknowledgedChangeId': lastAcknowledgedChangeId,
  };

  factory LanPeer.fromJson(Map<String, dynamic> json) => LanPeer(
    deviceId: json['deviceId'] as String,
    publicKey: base64Url.decode(
      base64Url.normalize(json['publicKey'] as String),
    ),
    spkiSha256: json['spkiSha256'] as String,
    displayName: json['displayName'] as String? ?? 'LynAI device',
    trustedAt: DateTime.parse(json['trustedAt'] as String),
    certificateExpiresAt: DateTime.parse(
      json['certificateExpiresAt'] as String? ?? json['trustedAt'] as String,
    ),
    lastSeenAt: DateTime.tryParse(json['lastSeenAt']?.toString() ?? ''),
    revokedAt: DateTime.tryParse(json['revokedAt']?.toString() ?? ''),
    lastAcknowledgedChangeId: json['lastAcknowledgedChangeId'] as String?,
  );

  static const _unset = Object();
}

class LanPairingSession {
  const LanPairingSession({
    required this.nonce,
    required this.createdAt,
    required this.expiresAt,
    this.consumedAt,
    this.consumedByDeviceId,
  });

  final String nonce;
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime? consumedAt;
  final String? consumedByDeviceId;

  bool get consumed => consumedAt != null;

  Map<String, dynamic> toJson() => {
    'nonce': nonce,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    if (consumedAt != null) 'consumedAt': consumedAt!.toUtc().toIso8601String(),
    if (consumedByDeviceId != null) 'consumedByDeviceId': consumedByDeviceId,
  };

  factory LanPairingSession.fromJson(Map<String, dynamic> json) =>
      LanPairingSession(
        nonce: json['nonce'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        expiresAt: DateTime.parse(json['expiresAt'] as String),
        consumedAt: DateTime.tryParse(json['consumedAt']?.toString() ?? ''),
        consumedByDeviceId: json['consumedByDeviceId'] as String?,
      );
}

class LanDiscoveredPeer {
  const LanDiscoveredPeer({
    required this.deviceId,
    required this.displayName,
    required this.addresses,
    required this.port,
    required this.protocolVersion,
  });

  final String deviceId;
  final String displayName;
  final List<String> addresses;
  final int port;
  final int protocolVersion;
}
