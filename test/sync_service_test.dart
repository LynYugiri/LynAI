import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lynai/services/backend_client.dart';
import 'package:lynai/services/sync_service.dart';

void main() {
  group('RemoteSyncService', () {
    test('keeps backend error message for status failures', () async {
      final service = RemoteSyncService(
        _FakeBackendClient(
          getResponses: {
            '/sync/status': _jsonResponse('{"error":"同步令牌失效"}', 401),
          },
        ),
      );

      await _expectExceptionContains(service.getStatus(), '同步令牌失效');
    });

    test('keeps backend error message for upload failures', () async {
      final service = RemoteSyncService(
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
      final service = RemoteSyncService(
        _FakeBackendClient(
          postRawResponses: {
            '/sync/blobs/abc123': _jsonResponse(
              '{"error":"blob too large or unreadable"}',
              400,
            ),
          },
        ),
      );

      await _expectExceptionContains(
        service.uploadBlob('abc123', const [1, 2, 3]),
        'blob too large or unreadable',
      );
    });

    test(
      'falls back when download failure body is not structured JSON',
      () async {
        final service = RemoteSyncService(
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

  @override
  Future<http.Response> get(String path, {Map<String, String>? headers}) async {
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
  }) async {
    return postRawResponses[path] ?? http.Response('{}', 404);
  }
}
