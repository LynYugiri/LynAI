import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:crypto/crypto.dart' as dart_crypto;

import 'device_identity_service.dart';

class LanPeerProof {
  LanPeerProof({
    required this.version,
    required this.deviceId,
    required List<int> publicKey,
    required this.sessionId,
    required this.localNonce,
    required this.remoteNonce,
    required this.purpose,
    required this.signerRole,
    required this.initiatorDeviceId,
    required this.responderDeviceId,
    required List<int> signature,
  }) : publicKey = List.unmodifiable(publicKey),
       signature = List.unmodifiable(signature);

  final int version;
  final String deviceId;
  final List<int> publicKey;
  final String sessionId;
  final String localNonce;
  final String remoteNonce;
  final String purpose;
  final String signerRole;
  final String initiatorDeviceId;
  final String responderDeviceId;
  final List<int> signature;

  Map<String, dynamic> toJson() => {
    'v': version,
    'deviceId': deviceId,
    'publicKey': _b64(publicKey),
    'sessionId': sessionId,
    'localNonce': localNonce,
    'remoteNonce': remoteNonce,
    'purpose': purpose,
    'signerRole': signerRole,
    'initiatorDeviceId': initiatorDeviceId,
    'responderDeviceId': responderDeviceId,
    'signature': _b64(signature),
  };

  factory LanPeerProof.fromJson(Map<String, dynamic> json) => LanPeerProof(
    version: (json['v'] as num).toInt(),
    deviceId: json['deviceId'] as String,
    publicKey: _decode(json['publicKey'] as String),
    sessionId: json['sessionId'] as String,
    localNonce: json['localNonce'] as String,
    remoteNonce: json['remoteNonce'] as String,
    purpose: json['purpose'] as String,
    signerRole: json['signerRole'] as String,
    initiatorDeviceId: json['initiatorDeviceId'] as String,
    responderDeviceId: json['responderDeviceId'] as String,
    signature: _decode(json['signature'] as String),
  );

  static String _b64(List<int> bytes) =>
      base64UrlEncode(bytes).replaceAll('=', '');
  static List<int> _decode(String value) =>
      base64Url.decode(base64Url.normalize(value));
}

class LanPeerProofService {
  LanPeerProofService(this._identity);

  static const protocolVersion = 1;
  static const _domain = 'LynAI/LAN/peer-proof/v1\x00';

  final DeviceIdentityService _identity;
  final Ed25519 _ed25519 = Ed25519();

  String randomNonce() {
    final random = Random.secure();
    return base64UrlEncode(
      List<int>.generate(24, (_) => random.nextInt(256)),
    ).replaceAll('=', '');
  }

  Future<LanPeerProof> create({
    required String sessionId,
    required String localNonce,
    required String remoteNonce,
    required String purpose,
    required String signerRole,
    required String initiatorDeviceId,
    required String responderDeviceId,
    required List<int> initiatorPublicKey,
    required List<int> responderPublicKey,
  }) async {
    final identity = await _identity.initialize();
    final transcript = _transcript(
      sessionId: sessionId,
      purpose: purpose,
      initiatorDeviceId: initiatorDeviceId,
      initiatorPublicKey: initiatorPublicKey,
      initiatorNonce: signerRole == 'initiator' ? localNonce : remoteNonce,
      responderDeviceId: responderDeviceId,
      responderPublicKey: responderPublicKey,
      responderNonce: signerRole == 'responder' ? localNonce : remoteNonce,
    );
    return LanPeerProof(
      version: protocolVersion,
      deviceId: identity.deviceId,
      publicKey: identity.publicKey,
      sessionId: sessionId,
      localNonce: localNonce,
      remoteNonce: remoteNonce,
      purpose: purpose,
      signerRole: signerRole,
      initiatorDeviceId: initiatorDeviceId,
      responderDeviceId: responderDeviceId,
      signature: await _identity.sign(_proofMessage(transcript, signerRole)),
    );
  }

  Future<bool> verify(
    LanPeerProof proof, {
    required String expectedSessionId,
    required String expectedLocalNonce,
    required String expectedRemoteNonce,
    required String expectedPurpose,
    required String expectedSignerRole,
    required String initiatorDeviceId,
    required List<int> initiatorPublicKey,
    required String responderDeviceId,
    required List<int> responderPublicKey,
    String? expectedDeviceId,
    List<int>? expectedPublicKey,
  }) async {
    if (proof.version != protocolVersion ||
        proof.sessionId != expectedSessionId ||
        proof.localNonce != expectedLocalNonce ||
        proof.remoteNonce != expectedRemoteNonce ||
        proof.purpose != expectedPurpose ||
        proof.signerRole != expectedSignerRole ||
        proof.initiatorDeviceId != initiatorDeviceId ||
        proof.responderDeviceId != responderDeviceId ||
        (expectedDeviceId != null && proof.deviceId != expectedDeviceId) ||
        (expectedPublicKey != null &&
            !_constantTimeEquals(proof.publicKey, expectedPublicKey)) ||
        DeviceIdentityService.deviceIdForPublicKey(proof.publicKey) !=
            proof.deviceId) {
      return false;
    }
    final transcript = _transcript(
      sessionId: proof.sessionId,
      purpose: proof.purpose,
      initiatorDeviceId: initiatorDeviceId,
      initiatorPublicKey: initiatorPublicKey,
      initiatorNonce: expectedSignerRole == 'initiator'
          ? proof.localNonce
          : proof.remoteNonce,
      responderDeviceId: responderDeviceId,
      responderPublicKey: responderPublicKey,
      responderNonce: expectedSignerRole == 'responder'
          ? proof.localNonce
          : proof.remoteNonce,
    );
    return _ed25519.verify(
      _proofMessage(transcript, proof.signerRole),
      signature: Signature(
        proof.signature,
        publicKey: SimplePublicKey(proof.publicKey, type: KeyPairType.ed25519),
      ),
    );
  }

  String sas({
    required String sessionId,
    required String purpose,
    required String initiatorDeviceId,
    required List<int> initiatorPublicKey,
    required String initiatorNonce,
    required String responderDeviceId,
    required List<int> responderPublicKey,
    required String responderNonce,
  }) {
    final digest = dart_crypto.sha256
        .convert(
          _transcript(
            sessionId: sessionId,
            purpose: purpose,
            initiatorDeviceId: initiatorDeviceId,
            initiatorPublicKey: initiatorPublicKey,
            initiatorNonce: initiatorNonce,
            responderDeviceId: responderDeviceId,
            responderPublicKey: responderPublicKey,
            responderNonce: responderNonce,
          ),
        )
        .bytes;
    final value = ((digest[0] << 16) | (digest[1] << 8) | digest[2]) % 1000000;
    return value.toString().padLeft(6, '0');
  }

  List<int> _transcript({
    required String sessionId,
    required String purpose,
    required String initiatorDeviceId,
    required List<int> initiatorPublicKey,
    required String initiatorNonce,
    required String responderDeviceId,
    required List<int> responderPublicKey,
    required String responderNonce,
  }) => utf8.encode(
    '$_domain$purpose\x00$sessionId\x00initiator\x00$initiatorDeviceId\x00'
    '${_b64(initiatorPublicKey)}\x00$initiatorNonce\x00responder\x00'
    '$responderDeviceId\x00${_b64(responderPublicKey)}\x00$responderNonce',
  );

  List<int> _proofMessage(List<int> transcript, String signerRole) => [
    ...transcript,
    ...utf8.encode('\x00proof\x00$signerRole'),
  ];

  static String _b64(List<int> bytes) =>
      base64UrlEncode(bytes).replaceAll('=', '');

  bool _constantTimeEquals(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    var difference = 0;
    for (var index = 0; index < left.length; index++) {
      difference |= left[index] ^ right[index];
    }
    return difference == 0;
  }
}
