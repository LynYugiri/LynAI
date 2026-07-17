import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:lynai/models/plugin_market_entry.dart';
import 'package:lynai/repositories/plugin_repository.dart';
import 'package:lynai/services/backend_client.dart';
import 'package:lynai/services/remote_market_service.dart';

void main() {
  test('submit rejects ZIP over 16 MiB before making a request', () async {
    final client = BackendClient();
    addTearDown(client.close);
    final service = RemoteMarketService(client);

    await expectLater(
      service.submitPlugin(
        List<int>.filled(RemoteMarketService.maxPluginSubmitBytes + 1, 0),
      ),
      throwsA(
        isA<MarketUnavailableException>().having(
          (error) => error.message,
          'message',
          contains('16 MiB'),
        ),
      ),
    );
  });

  test(
    'download rejects oversized Content-Length before reading body',
    () async {
      var listened = false;
      final transport = _MarketClient((_) async {
        return http.StreamedResponse(
          Stream<List<int>>.multi((controller) {
            listened = true;
            controller.add(const [1]);
            controller.close();
          }),
          200,
          contentLength: PluginRepository.maxPluginZipInputBytes + 1,
        );
      });
      final client = BackendClient(client: transport)
        ..configure('https://example.test');
      addTearDown(client.close);

      await expectLater(
        RemoteMarketService(client).downloadPlugin('large'),
        throwsA(
          isA<MarketUnavailableException>().having(
            (error) => error.message,
            'message',
            contains('32 MiB'),
          ),
        ),
      );
      expect(listened, isFalse);
    },
  );

  test('download aborts when streamed bytes exceed the limit', () async {
    final chunk = List<int>.filled(16 * 1024 * 1024, 1);
    final transport = _MarketClient(
      (_) async => http.StreamedResponse(
        Stream.fromIterable([
          chunk,
          chunk,
          const [1],
        ]),
        200,
      ),
    );
    final client = BackendClient(client: transport)
      ..configure('https://example.test');
    addTearDown(client.close);

    await expectLater(
      RemoteMarketService(client).downloadPlugin('large'),
      throwsA(isA<MarketUnavailableException>()),
    );
  });

  test('download refreshes a streamed 401 and retries with new auth', () async {
    var downloads = 0;
    final transport = _MarketClient((request) async {
      if (request.url.path == '/auth/refresh') {
        return _streamed(
          200,
          jsonEncode({
            'token': {
              'accessToken': 'new-access',
              'refreshToken': 'new-refresh',
            },
          }),
        );
      }
      downloads++;
      return request.headers['Authorization'] == 'Bearer new-access'
          ? _streamed(200, 'plugin bytes')
          : _streamed(401, 'expired');
    });
    final client = BackendClient(client: transport)
      ..configure('https://example.test')
      ..setTokens('old-access', 'old-refresh');
    addTearDown(client.close);

    final bytes = await RemoteMarketService(client).downloadPlugin('safe');

    expect(utf8.decode(bytes), 'plugin bytes');
    expect(downloads, 2);
    expect(client.accessToken, 'new-access');
  });
}

http.StreamedResponse _streamed(int statusCode, String body) {
  final bytes = utf8.encode(body);
  return http.StreamedResponse(
    Stream.value(bytes),
    statusCode,
    contentLength: bytes.length,
  );
}

class _MarketClient extends http.BaseClient {
  _MarketClient(this.handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest request)
  handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handler(request);
}
