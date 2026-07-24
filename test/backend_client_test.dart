import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lynai/services/backend_client.dart';

void main() {
  group('BackendClient.extractErrorMessage', () {
    test('reads plain backend error strings', () {
      expect(BackendClient.extractErrorMessage('{"error":"登录失败"}'), '登录失败');
    });

    test('reads relay style nested error messages', () {
      expect(
        BackendClient.extractErrorMessage(
          '{"error":{"message":"上游不可用","type":"upstream_error"}}',
        ),
        '上游不可用',
      );
    });

    test('falls back to nested error type and top-level message', () {
      expect(
        BackendClient.extractErrorMessage(
          '{"error":{"type":"invalid_request_error"}}',
        ),
        'invalid_request_error',
      );
      expect(BackendClient.extractErrorMessage('{"message":"请求失败"}'), '请求失败');
    });

    test('skips empty error fields', () {
      expect(
        BackendClient.extractErrorMessage(
          '{"error":{"message":"","type":"rate_limit_error"}}',
        ),
        'rate_limit_error',
      );
      expect(BackendClient.extractErrorMessage('{"error":"   "}'), isNull);
    });

    test('reads decoded error objects', () {
      expect(
        BackendClient.extractErrorMessageFromDecoded({
          'error': {'message': '流式错误', 'type': 'upstream_error'},
        }),
        '流式错误',
      );
    });

    test('returns null for malformed or empty responses', () {
      expect(BackendClient.extractErrorMessage('not-json'), isNull);
      expect(BackendClient.extractErrorMessage('{}'), isNull);
      expect(BackendClient.extractErrorMessage('[]'), isNull);
    });
  });

  group('BackendClient requests', () {
    test('has no hard-coded default backend address', () {
      expect(BackendClient.defaultBackendUrl, isEmpty);
    });

    test('canonicalizes backend URLs and origins', () {
      expect(
        BackendClient.normalizeUrl(
          ' HTTPS://user:pass@Example.COM:443/api///?ignored=1#fragment ',
        ),
        'https://example.com/api',
      );
      expect(
        BackendClient.normalizeOrigin('https://example.com:443/api'),
        'https://example.com',
      );
      final client = BackendClient()
        ..configure('https://example.com:443/api///');
      expect(client.backendScope, 'https://example.com/api');
      expect(client.backendOrigin, 'https://example.com');
      client.dispose();
    });

    test(
      'uses injected client and keeps HTTP backend addresses available',
      () async {
        late Uri requestedUri;
        final transport = _TestClient((request) async {
          requestedUri = request.url;
          return _response(200, 'ok');
        });
        final client = BackendClient(client: transport)
          ..configure('http://127.0.0.1:8080');

        final response = await client.get('/health');

        expect(response.body, 'ok');
        expect(requestedUri, Uri.parse('http://127.0.0.1:8080/health'));
        client.dispose();
        expect(transport.closed, isTrue);
      },
    );

    test('close owns injected client and is idempotent', () {
      final transport = _TestClient((_) async => _response(200, 'ok'));
      final client = BackendClient(client: transport);

      client.close();
      client.close();
      client.dispose();

      expect(transport.closeCount, 1);
    });

    test('ordinary, refresh, and multipart requests use the timeout', () async {
      final transport = _TestClient(
        (_) => Completer<http.StreamedResponse>().future,
      );
      final client = BackendClient(
        client: transport,
        requestTimeout: const Duration(milliseconds: 10),
      )..configure('http://localhost:8080');
      client.setTokens('access', 'refresh');

      await expectLater(client.get('/slow'), throwsA(isA<TimeoutException>()));
      await expectLater(client.refreshAccessToken(), completion(isFalse));
      client.setTokens('access', 'refresh');
      await expectLater(
        client.multipartRequest('POST', '/upload').send(),
        throwsA(isA<TimeoutException>()),
      );
      client.dispose();
    });

    test('postRaw can override the default request timeout', () async {
      final transport = _TestClient((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        return _response(200, 'ok');
      });
      final client = BackendClient(
        client: transport,
        requestTimeout: const Duration(milliseconds: 10),
      )..configure('http://localhost:8080');

      await expectLater(client.get('/slow'), throwsA(isA<TimeoutException>()));
      final response = await client.postRaw(
        '/blob',
        body: const [1, 2, 3],
        timeout: const Duration(milliseconds: 100),
      );

      expect(response.body, 'ok');
      client.dispose();
    });

    test('same-origin path changes clear credentials', () {
      final client = BackendClient()
        ..configure('https://EXAMPLE.com:443/api/')
        ..setTokens('access', 'refresh');

      client.configure('https://example.com/v2');

      expect(client.backendUrl, 'https://example.com/v2');
      expect(client.backendOrigin, 'https://example.com');
      expect(client.backendScope, 'https://example.com/v2');
      expect(client.accessToken, isNull);
      expect(client.refreshToken, isNull);
      client.dispose();
    });

    test('transient refresh failure keeps the current session', () async {
      final transport = _TestClient((request) async {
        if (request.url.path == '/auth/refresh') {
          return _response(503, 'unavailable');
        }
        return _response(401, 'expired');
      });
      var cleared = false;
      final client = BackendClient(client: transport)
        ..configure('https://example.com')
        ..setTokens('access', 'refresh')
        ..onSessionCleared = (_) async => cleared = true;

      expect((await client.get('/protected')).statusCode, 401);

      expect(client.accessToken, 'access');
      expect(client.refreshToken, 'refresh');
      expect(cleared, isFalse);
      client.dispose();
    });

    test('403 refresh failure keeps the current session', () async {
      final transport = _TestClient((request) async {
        if (request.url.path == '/api/auth/refresh') {
          return _response(403, 'rejected');
        }
        return _response(401, 'expired');
      });
      String? clearedOrigin;
      final client = BackendClient(client: transport)
        ..configure('https://example.com/api')
        ..setTokens('access', 'refresh')
        ..onSessionCleared = (origin) async => clearedOrigin = origin;

      expect((await client.get('/protected')).statusCode, 401);

      expect(client.accessToken, 'access');
      expect(client.refreshToken, 'refresh');
      expect(clearedOrigin, isNull);
      client.dispose();
    });

    test('401 refresh rejection clears the full backend scope', () async {
      final transport = _TestClient((request) async {
        if (request.url.path == '/api/auth/refresh') {
          return _response(401, 'rejected');
        }
        return _response(401, 'expired');
      });
      String? clearedScope;
      final client = BackendClient(client: transport)
        ..configure('https://example.com/api')
        ..setTokens('access', 'refresh')
        ..onSessionCleared = (scope) async => clearedScope = scope;

      expect((await client.get('/protected')).statusCode, 401);

      expect(client.accessToken, isNull);
      expect(client.refreshToken, isNull);
      expect(clearedScope, 'https://example.com/api');
      client.dispose();
    });

    test(
      'refresh completion cannot restore tokens after origin switch',
      () async {
        final refreshResponse = Completer<http.StreamedResponse>();
        final transport = _TestClient((request) async {
          if (request.url.path == '/auth/refresh') {
            return refreshResponse.future;
          }
          return _response(404, 'not found');
        });
        var persisted = false;
        final client = BackendClient(client: transport)
          ..configure('https://old.example.com')
          ..setTokens('old-access', 'old-refresh')
          ..onTokensRefreshed = (_, _, _) async => persisted = true;

        final refresh = client.refreshAccessToken();
        await Future<void>.delayed(Duration.zero);
        client.configure('https://new.example.com');
        refreshResponse.complete(
          _response(
            200,
            jsonEncode({
              'token': {
                'accessToken': 'stale-access',
                'refreshToken': 'stale-refresh',
              },
            }),
          ),
        );

        expect(await refresh, isFalse);
        expect(client.accessToken, isNull);
        expect(client.refreshToken, isNull);
        expect(persisted, isFalse);
        client.dispose();
      },
    );

    test('refresh completion cannot restore tokens after logout', () async {
      final refreshResponse = Completer<http.StreamedResponse>();
      final transport = _TestClient((request) async {
        if (request.url.path == '/auth/refresh') {
          return refreshResponse.future;
        }
        return _response(404, 'not found');
      });
      var persisted = false;
      final client = BackendClient(client: transport)
        ..configure('https://example.com')
        ..setTokens('old-access', 'old-refresh')
        ..onTokensRefreshed = (_, _, _) async => persisted = true;

      final refresh = client.refreshAccessToken();
      await Future<void>.delayed(Duration.zero);
      client.clearTokens();
      refreshResponse.complete(
        _response(
          200,
          jsonEncode({
            'token': {
              'accessToken': 'stale-access',
              'refreshToken': 'stale-refresh',
            },
          }),
        ),
      );

      expect(await refresh, isFalse);
      expect(client.accessToken, isNull);
      expect(client.refreshToken, isNull);
      expect(persisted, isFalse);
      client.dispose();
    });

    test(
      'concurrent 401 responses share one refresh and retry with new token',
      () async {
        var refreshCount = 0;
        final firstResponses = <String, Completer<http.StreamedResponse>>{};
        final refreshResponse = Completer<http.StreamedResponse>();
        final transport = _TestClient((request) async {
          if (request.url.path == '/auth/refresh') {
            refreshCount++;
            return refreshResponse.future;
          }
          if (request.headers['Authorization'] == 'Bearer new-access') {
            return _response(200, request.url.path);
          }
          return (firstResponses[request.url.path] ??= Completer()).future;
        });
        final client = BackendClient(client: transport)
          ..configure('http://localhost:8080')
          ..setTokens('old-access', 'old-refresh');

        final first = client.get('/one');
        final second = client.get('/two');
        await Future<void>.delayed(Duration.zero);
        firstResponses['/one']!.complete(_response(401, 'unauthorized'));
        firstResponses['/two']!.complete(_response(401, 'unauthorized'));
        await Future<void>.delayed(Duration.zero);
        expect(refreshCount, 1);
        refreshResponse.complete(
          _response(
            200,
            jsonEncode({
              'token': {
                'accessToken': 'new-access',
                'refreshToken': 'new-refresh',
              },
            }),
          ),
        );

        final responses = await Future.wait([first, second]);
        expect(
          responses.map((response) => response.statusCode),
          everyElement(200),
        );
        expect(refreshCount, 1);
        expect(client.accessToken, 'new-access');
        expect(client.refreshToken, 'new-refresh');
        client.dispose();
      },
    );

    test(
      'authenticated multipart request rebuilds body after refresh',
      () async {
        var uploadCalls = 0;
        final bodies = <String>[];
        final transport = _TestClient((request) async {
          if (request.url.path == '/auth/refresh') {
            return _response(
              200,
              jsonEncode({
                'token': {
                  'accessToken': 'new-access',
                  'refreshToken': 'new-refresh',
                },
              }),
            );
          }
          uploadCalls++;
          bodies.add(await request.finalize().bytesToString());
          return request.headers['Authorization'] == 'Bearer new-access'
              ? _response(200, 'ok')
              : _response(401, 'expired');
        });
        final client = BackendClient(client: transport)
          ..configure('http://localhost:8080')
          ..setTokens('old-access', 'old-refresh');

        final response = await client.sendAuthenticatedStreamed(() {
          final request = http.MultipartRequest(
            'POST',
            Uri.parse('http://localhost:8080/upload'),
          );
          request.fields['kind'] = 'ocr';
          request.files.add(
            http.MultipartFile.fromBytes('file', const [1, 2, 3]),
          );
          return request;
        });

        expect(response.statusCode, 200);
        expect(uploadCalls, 2);
        expect(bodies, everyElement(contains('name="kind"')));
        expect(bodies, everyElement(contains('ocr')));
        client.dispose();
      },
    );

    test(
      'replayable bytes POST rebuilds async headers and preserves body',
      () async {
        var headerBuilds = 0;
        final bodies = <List<int>>[];
        final signedTokens = <String?>[];
        final transport = _TestClient((request) async {
          if (request.url.path == '/auth/refresh') {
            return _response(
              200,
              jsonEncode({
                'token': {
                  'accessToken': 'new-access',
                  'refreshToken': 'new-refresh',
                },
              }),
            );
          }
          bodies.add(await request.finalize().toBytes());
          signedTokens.add(request.headers['X-Signed-Token']);
          return request.headers['Authorization'] == 'Bearer new-access'
              ? _response(200, 'ok')
              : _response(401, 'expired');
        });
        final client = BackendClient(client: transport)
          ..configure('http://localhost:8080')
          ..setTokens('old-access', 'old-refresh');
        final body = <int>[1, 2, 3];

        final response = await client.postReplayableBytes(
          '/signed',
          buildHeaders: () async {
            headerBuilds++;
            return {'X-Signed-Token': client.accessToken ?? ''};
          },
          bodyBytes: body,
        );
        body[0] = 9;

        expect(response.statusCode, 200);
        expect(headerBuilds, 2);
        expect(signedTokens, ['old-access', 'new-access']);
        expect(bodies, [
          [1, 2, 3],
          [1, 2, 3],
        ]);
        client.dispose();
      },
    );
  });
}

http.StreamedResponse _response(int statusCode, String body) {
  return http.StreamedResponse(
    Stream.value(utf8.encode(body)),
    statusCode,
    contentLength: utf8.encode(body).length,
  );
}

class _TestClient extends http.BaseClient {
  _TestClient(this._send);

  final Future<http.StreamedResponse> Function(http.BaseRequest request) _send;
  int closeCount = 0;

  bool get closed => closeCount > 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _send(request);

  @override
  void close() {
    closeCount++;
  }
}
