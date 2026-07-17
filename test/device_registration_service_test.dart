import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:lynai/services/backend_client.dart';
import 'package:lynai/services/device_identity_service.dart';
import 'package:lynai/services/device_registration_service.dart';
import 'package:lynai/services/secret_store.dart';

void main() {
  test('enrollment fixed vector matches the Go implementation', () async {
    final seed = _hex(
      '000102030405060708090a0b0c0d0e0f'
      '101112131415161718191a1b1c1d1e1f',
    );
    final keyPair = await Ed25519().newKeyPairFromSeed(seed);
    final publicKey = (await keyPair.extractPublicKey()).bytes;
    final deviceId = _base32(sha256.convert(publicKey).bytes);
    expect(deviceId, 'kzdvvj2umnduyauf35o36k6kw462mujvra46tn3uqgzovmihocga');
    final message = DeviceRegistrationService.buildEnrollmentMessage(
      protocolVersion: 1,
      challengeId: 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYX',
      challenge: seed,
      userId: '42',
      sessionId: 'session-vector-1',
      deviceId: deviceId,
      publicKey: publicKey,
      displayName: 'LynAI Test Device',
      platform: 'linux',
    );
    final signature = await Ed25519().sign(message, keyPair: keyPair);

    expect(
      _hexString(message),
      '4c796e41492f76312f656e726f6c6c6d656e7400000100000002000100020000002041414543417751464267634943516f4c4441304f4478415245684d5546525958000300000020000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f000400000002343200050000001073657373696f6e2d766563746f722d310006000000346b7a6476766a32756d6e64757961756633356f33366b366b773436326d756a7672613436746e337571677a6f766d69686f63676100070000002003a107bff3ce10be1d70dd18e74bc09967e4d6309ba50d5f1ddc8664125531b80008000000114c796e41492054657374204465766963650009000000056c696e7578',
    );
    expect(
      base64UrlEncode(signature.bytes).replaceAll('=', ''),
      '6Mr7DylNhi4lvmRlcAkODJoRmQx0XbJlocqFS2oWate0HRz-jM_0ZbblRzaBZvMHL4R-hyrMPcFAYKyF7PjZDg',
    );
  });

  test('automatic enrollment uses BackendClient and is idempotent', () async {
    var challengeCalls = 0;
    var enrollCalls = 0;
    final transport = _RegistrationClient((request) async {
      if (request.url.path == '/devices/challenge') {
        challengeCalls++;
        return _jsonResponse(200, {
          'challengeId': 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYX',
          'challenge': base64UrlEncode(
            List<int>.generate(32, (i) => i),
          ).replaceAll('=', ''),
          'userId': '42',
          'sessionId': 'session-1',
        });
      }
      if (request.url.path == '/devices/enroll') {
        enrollCalls++;
        return _jsonResponse(200, {'device': {}});
      }
      return _jsonResponse(404, {'error': 'not found'});
    });
    final backend = BackendClient(client: transport)
      ..configure('http://localhost:8080')
      ..setTokens(_token('42', 'session-1'), 'refresh');
    final service = DeviceRegistrationService(
      backend: backend,
      identity: DeviceIdentityService(secretStore: InMemorySecretStore()),
      platform: 'linux',
      displayName: 'Test device',
    );

    expect(await service.ensureEnrolled(), isTrue);
    expect(await service.ensureEnrolled(), isTrue);
    expect(challengeCalls, 2);
    expect(enrollCalls, 2);
    backend.dispose();
  });

  test('offline and legacy backends do not throw', () async {
    final offline = BackendClient();
    final offlineService = DeviceRegistrationService(
      backend: offline,
      identity: DeviceIdentityService(secretStore: InMemorySecretStore()),
    );
    expect(await offlineService.ensureEnrolled(), isFalse);
    offline.dispose();

    final legacy =
        BackendClient(
            client: _RegistrationClient(
              (_) async => _jsonResponse(404, {'error': 'not found'}),
            ),
          )
          ..configure('http://localhost:8080')
          ..setTokens(_token('42', 'session-1'), 'refresh');
    final legacyService = DeviceRegistrationService(
      backend: legacy,
      identity: DeviceIdentityService(secretStore: InMemorySecretStore()),
    );
    expect(await legacyService.ensureEnrolled(), isFalse);
    legacy.dispose();
  });
}

String _token(String userId, String sessionId) {
  final payload = base64UrlEncode(
    utf8.encode(jsonEncode({'uid': userId, 'sid': sessionId})),
  ).replaceAll('=', '');
  return 'header.$payload.signature';
}

List<int> _hex(String value) => [
  for (var i = 0; i < value.length; i += 2)
    int.parse(value.substring(i, i + 2), radix: 16),
];

String _hexString(List<int> value) =>
    value.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

String _base32(List<int> bytes) {
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
  if (bits > 0) output.write(alphabet[(buffer << (5 - bits)) & 31]);
  return output.toString();
}

http.StreamedResponse _jsonResponse(int statusCode, Map<String, dynamic> body) {
  final encoded = utf8.encode(jsonEncode(body));
  return http.StreamedResponse(
    Stream.value(encoded),
    statusCode,
    contentLength: encoded.length,
    headers: {'content-type': 'application/json'},
  );
}

class _RegistrationClient extends http.BaseClient {
  _RegistrationClient(this._send);

  final Future<http.StreamedResponse> Function(http.BaseRequest request) _send;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _send(request);
}
