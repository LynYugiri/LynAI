import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'backend_client.dart';
import 'device_identity_service.dart';

/// Enrolls the backend-origin and account-scoped Ed25519 identity.
class DeviceRegistrationService {
  DeviceRegistrationService({
    required BackendClient backend,
    required DeviceIdentityService identity,
    String? platform,
    String? displayName,
  }) : _backend = backend,
       _identity = identity,
       platform = platform ?? _currentPlatform(),
       displayName = displayName ?? 'LynAI ${platform ?? _currentPlatform()}';

  static const protocolVersion = 1;
  static const _domain = 'LynAI/v1/enrollment\x00';

  final BackendClient _backend;
  final DeviceIdentityService _identity;
  final String platform;
  final String displayName;
  final Map<String, Future<bool>> _inFlight = {};

  /// Enrolls after authentication. A successful result is required for sync.
  Future<bool> ensureEnrolled() {
    if (!_backend.isConnected || _backend.accessToken == null) {
      return Future.value(false);
    }
    final claims = accessTokenClaims(_backend.accessToken);
    if (claims == null) return Future.value(false);
    final scope = DeviceIdentityService.accountScope(
      _backend.backendUrl,
      claims.userId,
    );
    return _inFlight[scope] ??= _enroll(scope).whenComplete(() {
      _inFlight.remove(scope);
    });
  }

  Future<bool> _enroll(String scope) async {
    try {
      final identity = await _identity.initialize(scope: scope);
      final publicKey = _base64Url(identity.publicKey);
      final proposal = <String, dynamic>{
        'deviceId': identity.deviceId,
        'publicKey': publicKey,
        'displayName': displayName,
        'platform': platform,
        'protocolVersion': protocolVersion,
      };
      final challengeResponse = await _backend.post(
        '/devices/challenge',
        body: proposal,
      );
      if (challengeResponse.statusCode != 200) return false;
      final challengeJson = Map<String, dynamic>.from(
        jsonDecode(challengeResponse.body) as Map,
      );
      final challengeId = challengeJson['challengeId'] as String? ?? '';
      final challengeValue = challengeJson['challenge'] as String? ?? '';
      final userId = challengeJson['userId'] as String? ?? '';
      final sessionId = challengeJson['sessionId'] as String? ?? '';
      final challenge = _decodeBase64Url(challengeValue);
      if (challengeId.isEmpty ||
          userId.isEmpty ||
          sessionId.isEmpty ||
          challenge.length != 32) {
        return false;
      }
      final message = buildEnrollmentMessage(
        protocolVersion: protocolVersion,
        challengeId: challengeId,
        challenge: challenge,
        userId: userId,
        sessionId: sessionId,
        deviceId: identity.deviceId,
        publicKey: identity.publicKey,
        displayName: displayName,
        platform: platform,
      );
      final signature = await _identity.sign(message, scope: scope);
      final response = await _backend.post(
        '/devices/enroll',
        body: {
          ...proposal,
          'challengeId': challengeId,
          'challenge': challengeValue,
          'signature': _base64Url(signature),
        },
      );
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  static ({String userId, String sessionId})? accessTokenClaims(String? token) {
    if (token == null) return null;
    final parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      if (payload is! Map) return null;
      final userId = payload['uid']?.toString() ?? '';
      final sessionId = payload['sid']?.toString() ?? '';
      if (userId.isEmpty || sessionId.isEmpty) return null;
      return (userId: userId, sessionId: sessionId);
    } catch (_) {
      return null;
    }
  }

  /// Builds the exact domain-separated CBE1 bytes shared with the Go backend.
  static List<int> buildEnrollmentMessage({
    required int protocolVersion,
    required String challengeId,
    required List<int> challenge,
    required String userId,
    required String sessionId,
    required String deviceId,
    required List<int> publicKey,
    required String displayName,
    required String platform,
  }) {
    final version = ByteData(2)..setUint16(0, protocolVersion);
    final fields = <List<int>>[
      version.buffer.asUint8List(),
      utf8.encode(challengeId),
      challenge,
      utf8.encode(userId),
      utf8.encode(sessionId),
      utf8.encode(deviceId),
      publicKey,
      utf8.encode(displayName),
      utf8.encode(platform),
    ];
    final output = BytesBuilder(copy: false)..add(utf8.encode(_domain));
    for (var index = 0; index < fields.length; index++) {
      final field = fields[index];
      final header = ByteData(6)
        ..setUint16(0, index + 1)
        ..setUint32(2, field.length);
      output
        ..add(header.buffer.asUint8List())
        ..add(field);
    }
    return output.takeBytes();
  }

  static String _base64Url(List<int> bytes) =>
      base64UrlEncode(bytes).replaceAll('=', '');

  static List<int> _decodeBase64Url(String value) {
    if (value.isEmpty || value.contains('=')) throw const FormatException();
    final decoded = base64Url.decode(base64Url.normalize(value));
    if (_base64Url(decoded) != value) throw const FormatException();
    return decoded;
  }

  static String _currentPlatform() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }
}
