import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:cryptography/cryptography.dart';
import 'package:lynai/services/backend_client.dart';
import 'package:lynai/services/device_identity_service.dart';
import 'package:lynai/services/device_registration_service.dart';
import 'package:lynai/services/secret_store.dart';
import 'package:lynai/services/sync_service.dart';

void main() {
  group('RemoteSyncService', () {
    test('sync request CBE1 fixed vector is stable', () async {
      final message = RemoteSyncService.buildSyncRequestMessage(
        protocolVersion: 1,
        userId: '42',
        sessionId: 'session-vector-1',
        deviceId: 'kzdvvj2umnduyauf35o36k6kw462mujvra46tn3uqgzovmihocga',
        requestId: 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYX',
        timestamp: 1700000000123,
        method: 'POST',
        target: '/sync/changes',
        bodySha256: List<int>.generate(32, (index) => index),
      );
      final keyPair = await Ed25519().newKeyPairFromSeed(
        List<int>.generate(32, (index) => index),
      );
      final signature = await Ed25519().sign(message, keyPair: keyPair);

      expect(
        message.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join(),
        '4c796e41492f76312f73796e632d72657175657374000001000000020001000200000002343200030000001073657373696f6e2d766563746f722d310004000000346b7a6476766a32756d6e64757961756633356f33366b366b773436326d756a7672613436746e337571677a6f766d69686f6367610005000000080000018bcfe5687b00060000002041414543417751464267634943516f4c4441304f4478415245684d5546525958000700000004504f535400080000000d2f73796e632f6368616e676573000900000020000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f',
      );
      expect(
        base64UrlEncode(signature.bytes).replaceAll('=', ''),
        'ijPzt7fLykodsX18MwAXhwlvPUMMdtWqraTQUUwREshEkGTXxu09x8Ziz8a3dqkU2dCL6GVLgRoBKxzcGXSaCw',
      );
    });

    test(
      'signed upload preserves raw bytes and request ID across retries',
      () async {
        final client = _FakeBackendClient(
          postResponses: {
            '/sync/changes': http.Response('{"latestSeq":1}', 200),
          },
        );
        final service = _remoteSyncService(client);
        final changes = [
          SyncChangeRecord(
            changeId: 'change-1',
            deviceId: 'device-1',
            clientCreatedAt: DateTime.utc(2026, 7, 16),
            mutationVersion: 3,
            table: 'messages',
            op: 'upsert',
            recordId: 'm1',
            data: const {'id': 'm1'},
          ),
        ];

        await service.uploadChanges(changes);
        await service.uploadChanges(changes);

        expect(client.jsonBodies[0], client.jsonBodies[1]);
        expect(
          client.jsonHeaders[0]?['X-LynAI-Request-ID'],
          client.jsonHeaders[1]?['X-LynAI-Request-ID'],
        );
        expect(client.jsonHeaders[0]?['X-LynAI-Signature'], isNotEmpty);
      },
    );

    test(
      'decodes exact legacy upload response as snapshot acknowledgement',
      () async {
        final client = _FakeBackendClient(
          postResponses: {
            '/sync/changes': http.Response(
              '{"latestSeq":1,"changes":[{"seq":1}]}',
              200,
            ),
          },
        );
        final result = await _remoteSyncService(client).uploadChanges([
          SyncChangeRecord(
            changeId: 'change-1',
            deviceId: 'device-1',
            clientCreatedAt: DateTime.utc(2026, 7, 16),
            mutationVersion: 1,
            table: 'messages',
            op: 'delete',
            recordId: 'm1',
          ),
        ]);

        expect(result.latestSeq, 1);
        expect(result.acknowledgements, isNull);
      },
    );

    test('explicit signature rejection never retries unsigned', () async {
      final client = _FakeBackendClient(
        postResponses: {
          '/sync/changes': http.Response(
            '{"code":"invalid_signature","error":"rejected"}',
            401,
          ),
        },
      );
      final service = _remoteSyncService(client);

      await expectLater(
        service.uploadChanges([
          SyncChangeRecord(
            changeId: 'change-1',
            deviceId: 'device-1',
            clientCreatedAt: DateTime.utc(2026, 7, 16),
            mutationVersion: 1,
            table: 'messages',
            op: 'delete',
            recordId: 'm1',
          ),
        ]),
        throwsException,
      );

      expect(client.jsonBodies, hasLength(1));
      expect(client.jsonHeaders.single?['X-LynAI-Signature'], isNotEmpty);
    });

    test(
      'required-mode blob upload signs exact raw bytes and replays',
      () async {
        final bytes = utf8.encode('signed raw blob');
        final hash = sha256.convert(bytes).toString();
        final client = _FakeBackendClient(
          postRawResponses: {'/sync/blobs/$hash': http.Response('{}', 200)},
        );
        final service = _remoteSyncService(client);

        await service.uploadBlob(hash, bytes);
        await service.uploadBlob(hash, bytes);

        expect(client.rawBodies, [bytes, bytes]);
        expect(
          client.rawHeaders[0]['X-LynAI-Body-SHA256'],
          sha256.convert(bytes).toString(),
        );
        expect(
          client.rawHeaders[0]['X-LynAI-Request-ID'],
          client.rawHeaders[1]['X-LynAI-Request-ID'],
        );
        expect(client.rawHeaders[0]['X-LynAI-Signature'], isNotEmpty);
      },
    );

    test('blob signature rejection never retries unsigned', () async {
      final bytes = utf8.encode('rejected blob');
      final hash = sha256.convert(bytes).toString();
      final client = _FakeBackendClient(
        postRawResponses: {
          '/sync/blobs/$hash': http.Response(
            '{"code":"invalid_signature","error":"rejected"}',
            401,
          ),
        },
      );
      final service = _remoteSyncService(client);

      await expectLater(service.uploadBlob(hash, bytes), throwsException);

      expect(client.rawBodies, hasLength(1));
      expect(client.rawHeaders.single['X-LynAI-Signature'], isNotEmpty);
    });

    test('keeps backend error message for status failures', () async {
      final service = _remoteSyncService(
        _FakeBackendClient(
          getResponses: {
            '/sync/status': _jsonResponse('{"error":"同步令牌失效"}', 401),
          },
        ),
      );

      await _expectExceptionContains(service.getStatus(), '同步令牌失效');
    });

    test('decodes every advertised sync limit', () async {
      final service = _remoteSyncService(
        _FakeBackendClient(
          getResponses: {
            '/sync/status': _jsonResponse(
              '{"lastSeq":2,"blobCount":3,"limits":{'
              '"maxBlobBytes":11,"maxChangesRequestBytes":12,'
              '"maxChangesPerRequest":13,"maxChangeDataBytes":14,'
              '"maxChangesPageSize":15,"maxBlobsPageSize":16}}',
              200,
            ),
          },
        ),
      );

      final limits = (await service.getStatus()).limits;
      expect(limits.maxBlobBytes, 11);
      expect(limits.maxChangesRequestBytes, 12);
      expect(limits.maxChangesPerRequest, 13);
      expect(limits.maxChangeDataBytes, 14);
      expect(limits.maxChangesPageSize, 15);
      expect(limits.maxBlobsPageSize, 16);
    });

    test('lists every blob page using backend nextAfter cursor', () async {
      final client = _FakeBackendClient(
        getResponses: {
          '/sync/blobs?after=0&limit=2': _jsonResponse(
            '{"blobs":[{"sha256":"a","size":1}],'
            '"nextAfter":4,"hasMore":true}',
            200,
          ),
          '/sync/blobs?after=4&limit=2': _jsonResponse(
            '{"blobs":[{"sha256":"b","size":2}],'
            '"nextAfter":7,"hasMore":false}',
            200,
          ),
        },
      );

      final blobs = await _remoteSyncService(client).listBlobs(limit: 2);

      expect(blobs.map((blob) => blob.sha256), ['a', 'b']);
      expect(client.getPaths, [
        '/sync/blobs?after=0&limit=2',
        '/sync/blobs?after=4&limit=2',
      ]);
    });

    test('rejects non-advancing blob pagination', () async {
      final service = _remoteSyncService(
        _FakeBackendClient(
          getResponses: {
            '/sync/blobs?after=0&limit=2': _jsonResponse(
              '{"blobs":[],"nextAfter":0,"hasMore":true}',
              200,
            ),
          },
        ),
      );

      await expectLater(
        service.listBlobs(limit: 2),
        throwsA(isA<StateError>()),
      );
    });

    test('keeps backend error message for upload failures', () async {
      final service = _remoteSyncService(
        _FakeBackendClient(
          postResponses: {
            '/sync/changes': http.Response(
              '{"error":"changes is required"}',
              400,
            ),
          },
        ),
      );

      await _expectExceptionContains(
        service.uploadChanges(const []),
        'changes is required',
      );
    });

    test('keeps backend error message for blob upload failures', () async {
      final client = _FakeBackendClient(
        postRawResponses: {
          '/sync/blobs/abc123': _jsonResponse(
            '{"error":"blob too large or unreadable"}',
            400,
          ),
        },
      );
      final service = _remoteSyncService(client);

      await _expectExceptionContains(
        service.uploadBlob('abc123', const [1, 2, 3]),
        'blob too large or unreadable',
      );
      expect(client.lastPostRawTimeout, RemoteSyncService.blobUploadTimeout);
    });

    test(
      'falls back when download failure body is not structured JSON',
      () async {
        final service = _remoteSyncService(
          _FakeBackendClient(
            getResponses: {
              '/sync/blobs/missing': http.Response('not found', 404),
            },
          ),
        );

        await _expectExceptionContains(
          service.downloadBlob('missing'),
          '下载 blob 失败',
        );
      },
    );
  });
}

RemoteSyncService _remoteSyncService(_FakeBackendClient client) {
  final identity = DeviceIdentityService(secretStore: InMemorySecretStore());
  return RemoteSyncService(
    client,
    identity: identity,
    registration: _EnrolledRegistration(client, identity),
  );
}

class _EnrolledRegistration extends DeviceRegistrationService {
  _EnrolledRegistration(BackendClient backend, DeviceIdentityService identity)
    : super(backend: backend, identity: identity);

  @override
  Future<bool> ensureEnrolled() async => true;
}

http.Response _jsonResponse(String body, int statusCode) {
  return http.Response.bytes(
    utf8.encode(body),
    statusCode,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

Future<void> _expectExceptionContains(Future<Object?> future, String message) {
  return expectLater(
    future,
    throwsA(
      isA<Exception>().having(
        (error) => error.toString(),
        'message',
        contains(message),
      ),
    ),
  );
}

class _FakeBackendClient extends BackendClient {
  _FakeBackendClient({
    this.getResponses = const {},
    this.postResponses = const {},
    this.postRawResponses = const {},
  });

  // 按路径返回预设响应，避免单测启动真实后端。
  final Map<String, http.Response> getResponses;
  final Map<String, http.Response> postResponses;
  final Map<String, http.Response> postRawResponses;
  Duration? lastPostRawTimeout;
  final List<List<int>> jsonBodies = [];
  final List<Map<String, String>?> jsonHeaders = [];
  final List<List<int>> rawBodies = [];
  final List<Map<String, String>> rawHeaders = [];
  final List<String> getPaths = [];

  @override
  String? get accessToken =>
      'header.${base64UrlEncode(utf8.encode(jsonEncode({'uid': '42', 'sid': 'session-vector-1'}))).replaceAll('=', '')}.signature';

  @override
  String get backendUrl => 'https://backend.example';

  @override
  Future<http.Response> get(String path, {Map<String, String>? headers}) async {
    getPaths.add(path);
    return getResponses[path] ?? http.Response('{}', 404);
  }

  @override
  Future<http.Response> post(
    String path, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    return postResponses[path] ?? http.Response('{}', 404);
  }

  @override
  Future<http.Response> postRaw(
    String path, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
  }) async {
    lastPostRawTimeout = timeout;
    rawBodies.add(List<int>.from(body! as List<int>));
    rawHeaders.add(Map<String, String>.from(headers ?? const {}));
    return postRawResponses[path] ?? http.Response('{}', 404);
  }

  @override
  Future<http.Response> postJsonBytes(
    String path, {
    Map<String, String>? headers,
    required List<int> bodyBytes,
  }) async {
    jsonBodies.add(List<int>.of(bodyBytes));
    jsonHeaders.add(headers == null ? null : Map.of(headers));
    return postResponses[path] ?? http.Response('{}', 404);
  }
}
