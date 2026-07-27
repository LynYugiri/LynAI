import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lynai/models/mcp_config.dart';
import 'package:lynai/services/mcp/mcp_http_transport.dart';
import 'package:lynai/services/mcp/mcp_transport_secrets.dart';

void main() {
  test(
    'posts JSON-RPC with injected credentials and emits bounded response',
    () async {
      final client = _RecordingClient(
        (request) async => http.StreamedResponse(
          Stream.value(utf8.encode('{"jsonrpc":"2.0","id":1,"result":{}}')),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      final transport = McpHttpTransport(
        config: McpServerConfig.streamableHttp(
          id: 'remote',
          displayName: 'Remote',
          endpoint: Uri.parse('https://example.com/mcp'),
        ),
        credentials: McpHttpCredentials(
          headers: {'Authorization': 'Bearer secret'},
        ),
        client: client,
        hostResolver: _publicResolver,
      );
      await transport.start();
      expect(
        transport.messages,
        emits(predicate<Map<String, dynamic>>((message) => message['id'] == 1)),
      );
      await transport.send({'jsonrpc': '2.0', 'id': 1, 'method': 'initialize'});
      expect(client.requests.single.headers['Authorization'], 'Bearer secret');
      await transport.dispose();
    },
  );

  test('does not forward credentials across redirects', () async {
    final client = _RecordingClient((request) async {
      if (request.url.host == 'first.example') {
        return http.StreamedResponse(
          const Stream.empty(),
          307,
          headers: {'location': 'https://second.example/mcp'},
        );
      }
      return http.StreamedResponse(
        Stream.value(utf8.encode('{"jsonrpc":"2.0","id":1,"result":{}}')),
        200,
      );
    });
    final transport = McpHttpTransport(
      config: McpServerConfig.streamableHttp(
        id: 'remote',
        displayName: 'Remote',
        endpoint: Uri.parse('https://first.example/mcp'),
      ),
      credentials: McpHttpCredentials(
        headers: {'Authorization': 'Bearer secret'},
      ),
      client: client,
      hostResolver: _publicResolver,
    );
    await transport.start();
    await transport.send({'jsonrpc': '2.0', 'id': 1, 'method': 'initialize'});
    expect(client.requests.first.headers['Authorization'], 'Bearer secret');
    expect(client.requests.last.headers.containsKey('Authorization'), isFalse);
    await transport.dispose();
  });

  test('rejects responses larger than the configured bound', () async {
    final payload = jsonEncode({
      'jsonrpc': '2.0',
      'id': 1,
      'result': {'value': 'x' * 100},
    });
    final client = _RecordingClient(
      (request) async =>
          http.StreamedResponse(Stream.value(utf8.encode(payload)), 200),
    );
    final transport = McpHttpTransport(
      config: McpServerConfig.streamableHttp(
        id: 'remote',
        displayName: 'Remote',
        endpoint: Uri.parse('https://example.com/mcp'),
        maxMessageBytes: 64,
        maxResponseBytes: 64,
      ),
      credentials: McpHttpCredentials(),
      client: client,
      hostResolver: _publicResolver,
    );
    await transport.start();
    await expectLater(
      transport.send({'jsonrpc': '2.0', 'id': 1, 'method': 'x'}),
      throwsA(isA<Exception>()),
    );
    await transport.dispose();
  });

  test(
    'rejects URL credentials and private HTTP without explicit allowance',
    () {
      expect(
        () => McpServerConfig.streamableHttp(
          id: 'bad',
          displayName: 'Bad',
          endpoint: Uri.parse('https://user:pass@example.com/mcp'),
        ),
        throwsArgumentError,
      );
      expect(
        () => McpServerConfig.streamableHttp(
          id: 'bad',
          displayName: 'Bad',
          endpoint: Uri.parse('http://127.0.0.1/mcp'),
          allowHttp: true,
        ),
        throwsArgumentError,
      );
    },
  );

  test('rejects a hostname resolving to a private address', () async {
    final client = _RecordingClient(
      (request) async => http.StreamedResponse(const Stream.empty(), 204),
    );
    final transport = McpHttpTransport(
      config: McpServerConfig.streamableHttp(
        id: 'remote',
        displayName: 'Remote',
        endpoint: Uri.parse('https://public-name.example/mcp'),
      ),
      credentials: McpHttpCredentials(),
      client: client,
      hostResolver: (host) async => const ['192.168.1.20'],
    );

    await transport.start();
    await expectLater(
      transport.send({'jsonrpc': '2.0', 'id': 1, 'method': 'initialize'}),
      throwsA(isA<Exception>()),
    );
    expect(client.requests, isEmpty);
    await transport.dispose();
  });

  test('validates a redirect target before sending the next request', () async {
    final resolvedHosts = <String>[];
    final client = _RecordingClient(
      (request) async => http.StreamedResponse(
        const Stream.empty(),
        307,
        headers: {'location': 'https://internal.example/mcp'},
      ),
    );
    final transport = McpHttpTransport(
      config: McpServerConfig.streamableHttp(
        id: 'remote',
        displayName: 'Remote',
        endpoint: Uri.parse('https://public.example/mcp'),
      ),
      credentials: McpHttpCredentials(),
      client: client,
      hostResolver: (host) async {
        resolvedHosts.add(host);
        return host == 'public.example'
            ? const ['93.184.216.34']
            : const ['127.0.0.1'];
      },
    );

    await transport.start();
    await expectLater(
      transport.send({'jsonrpc': '2.0', 'id': 1, 'method': 'initialize'}),
      throwsA(isA<Exception>()),
    );
    expect(resolvedHosts, ['public.example', 'internal.example']);
    expect(client.requests, hasLength(1));
    await transport.dispose();
  });
}

Future<List<String>> _publicResolver(String host) async => const [
  '93.184.216.34',
];

class _RecordingClient extends http.BaseClient {
  final Future<http.StreamedResponse> Function(http.BaseRequest) handler;
  final List<http.BaseRequest> requests = [];

  _RecordingClient(this.handler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requests.add(request);
    return handler(request);
  }
}
