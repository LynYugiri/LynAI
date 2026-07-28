import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lynai/models/mcp_config.dart';
import 'package:lynai/services/agent_cancellation.dart';
import 'package:lynai/services/mcp/mcp_client.dart';
import 'package:lynai/services/mcp/mcp_http_transport.dart';
import 'package:lynai/services/mcp/mcp_transport.dart';
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

  test(
    'native MCP transport connects to the exact resolver-approved address',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requests = <HttpRequest>[];
      final subscription = server.listen((request) async {
        requests.add(request);
        request.response.headers.contentType = ContentType.json;
        request.response.write('{"jsonrpc":"2.0","id":1,"result":{}}');
        await request.response.close();
      });
      final transport = McpHttpTransport(
        config: McpServerConfig.streamableHttp(
          id: 'remote',
          displayName: 'Remote',
          endpoint: Uri.parse('http://approved-mcp.invalid:${server.port}/mcp'),
          allowHttp: true,
          allowPrivateNetwork: true,
          enableSseNotifications: false,
        ),
        credentials: McpHttpCredentials(),
        hostResolver: (host) async => const ['127.0.0.1'],
      );

      try {
        await transport.start();
        await transport.send({
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'initialize',
        });

        expect(requests, hasLength(1));
        expect(requests.single.headers.host, 'approved-mcp.invalid');
        expect(requests.single.requestedUri.port, server.port);
      } finally {
        await transport.dispose();
        await subscription.cancel();
        await server.close(force: true);
      }
    },
  );

  test(
    'native MCP redirects independently pin hops and strip credentials',
    () async {
      final first = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final second = await HttpServer.bind(InternetAddress('127.0.0.2'), 0);
      final secondUri = Uri.parse(
        'http://second-mcp.invalid:${second.port}/mcp',
      );
      final resolved = <String>[];
      final firstRequests = <HttpRequest>[];
      final secondRequests = <HttpRequest>[];
      final firstSubscription = first.listen((request) async {
        firstRequests.add(request);
        request.response.statusCode = HttpStatus.temporaryRedirect;
        request.response.headers.set(HttpHeaders.locationHeader, secondUri);
        await request.response.close();
      });
      final secondSubscription = second.listen((request) async {
        secondRequests.add(request);
        request.response.headers.contentType = ContentType.json;
        request.response.write('{"jsonrpc":"2.0","id":1,"result":{}}');
        await request.response.close();
      });
      final transport = McpHttpTransport(
        config: McpServerConfig.streamableHttp(
          id: 'remote',
          displayName: 'Remote',
          endpoint: Uri.parse('http://first-mcp.invalid:${first.port}/mcp'),
          allowHttp: true,
          allowPrivateNetwork: true,
          enableSseNotifications: false,
        ),
        credentials: McpHttpCredentials(
          headers: {'Authorization': 'Bearer secret'},
        ),
        hostResolver: (host) async {
          resolved.add(host);
          return host == 'first-mcp.invalid'
              ? const ['127.0.0.1']
              : const ['127.0.0.2'];
        },
      );

      try {
        await transport.start();
        await transport.send({
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'initialize',
        });

        expect(resolved, ['first-mcp.invalid', 'second-mcp.invalid']);
        expect(firstRequests, hasLength(1));
        expect(secondRequests, hasLength(1));
        expect(firstRequests.single.headers.host, 'first-mcp.invalid');
        expect(
          firstRequests.single.headers.value(HttpHeaders.authorizationHeader),
          'Bearer secret',
        );
        expect(secondRequests.single.headers.host, 'second-mcp.invalid');
        expect(
          secondRequests.single.headers.value(HttpHeaders.authorizationHeader),
          isNull,
        );
      } finally {
        await transport.dispose();
        await firstSubscription.cancel();
        await secondSubscription.cancel();
        await first.close(force: true);
        await second.close(force: true);
      }
    },
  );

  test(
    'rebound redirect is rejected before a client receives credentials',
    () async {
      final clients = <_RecordingClient>[];
      final transport = McpHttpTransport(
        config: McpServerConfig.streamableHttp(
          id: 'remote',
          displayName: 'Remote',
          endpoint: Uri.parse('https://public.example/mcp'),
          enableSseNotifications: false,
        ),
        credentials: McpHttpCredentials(
          headers: {'Authorization': 'Bearer secret'},
        ),
        clientFactory: (address) {
          final client = _RecordingClient(
            (request) async => http.StreamedResponse(
              const Stream.empty(),
              307,
              headers: {'location': 'https://rebound.example/mcp'},
            ),
          );
          clients.add(client);
          return client;
        },
        hostResolver: (host) async => host == 'public.example'
            ? const ['93.184.216.34']
            : const ['127.0.0.1'],
      );

      await transport.start();
      await expectLater(
        transport.send({'jsonrpc': '2.0', 'id': 1, 'method': 'initialize'}),
        throwsA(isA<Exception>()),
      );

      expect(clients, hasLength(1));
      expect(clients.single.requests, hasLength(1));
      expect(
        clients.single.requests.single.headers['Authorization'],
        'Bearer secret',
      );
      await transport.dispose();
    },
  );

  test('dispose closes an active MCP request client', () async {
    final client = _HangingClient();
    final transport = McpHttpTransport(
      config: McpServerConfig.streamableHttp(
        id: 'remote',
        displayName: 'Remote',
        endpoint: Uri.parse('https://example.com/mcp'),
        requestTimeout: const Duration(seconds: 5),
        enableSseNotifications: false,
      ),
      credentials: McpHttpCredentials(),
      clientFactory: (address) => client,
      hostResolver: _publicResolver,
    );

    await transport.start();
    final operation = transport.send({
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'initialize',
    });
    final outcome = operation.then<Object?>(
      (_) => null,
      onError: (error) => error,
    );
    await client.sent.future;
    await transport.dispose();

    expect(client.closed, isTrue);
    expect(await outcome, isA<Error>());
  });

  test(
    'token cancellation aborts a stalled POST SSE without affecting a concurrent request',
    () => _verifyStalledPostAbort(cancelWithToken: true),
  );

  test(
    'request timeout aborts a stalled POST SSE without affecting a concurrent request',
    () => _verifyStalledPostAbort(cancelWithToken: false),
  );
}

Future<void> _verifyStalledPostAbort({required bool cancelWithToken}) async {
  final server = _ConcurrentSseServer();
  final transport = McpHttpTransport(
    config: McpServerConfig.streamableHttp(
      id: 'remote',
      displayName: 'Remote',
      endpoint: Uri.parse('https://example.com/mcp'),
      requestTimeout: const Duration(seconds: 5),
      enableSseNotifications: false,
    ),
    credentials: McpHttpCredentials(),
    clientFactory: server.createClient,
    hostResolver: _publicResolver,
  );
  final client = McpClient(
    transport: transport,
    requestTimeout: const Duration(seconds: 5),
  );

  await client.initialize();
  final cancellation = AgentCancellationSource();
  final first = client.request(
    'tools/call',
    const {'name': 'first', 'arguments': <String, dynamic>{}},
    cancellationToken: cancelWithToken ? cancellation.token : null,
    timeout: cancelWithToken ? null : const Duration(milliseconds: 30),
  );
  final second = client.request('tools/call', const {
    'name': 'second',
    'arguments': <String, dynamic>{},
  });
  await Future.wait([server.started('first'), server.started('second')]);

  if (cancelWithToken) cancellation.cancel();
  await expectLater(
    first.timeout(const Duration(seconds: 1)),
    throwsA(
      cancelWithToken
          ? isA<AgentCancellationException>()
          : isA<TimeoutException>(),
    ),
  );
  expect(server.clientFor('first').closed, isTrue);
  expect(server.clientFor('second').closed, isFalse);
  expect(transport.status.state, McpTransportState.connected);

  server.respond('second');
  expect((await second)['isError'], isFalse);
  await server.cancellationSent.timeout(const Duration(seconds: 1));
  await client.dispose();
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

class _HangingClient extends http.BaseClient {
  final Completer<void> sent = Completer<void>();
  final Completer<http.StreamedResponse> _response = Completer();
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (!sent.isCompleted) sent.complete();
    return _response.future;
  }

  @override
  void close() {
    closed = true;
    if (!_response.isCompleted) {
      _response.completeError(StateError('client closed'));
    }
  }
}

class _ConcurrentSseServer {
  final List<String> methods = [];
  final Completer<void> _cancellationSent = Completer<void>();
  final Map<String, _AbortableClient> _clients = {};
  final Map<String, Completer<void>> _started = {};

  http.Client createClient(String? address) => _AbortableClient(_handle);

  Future<http.StreamedResponse> _handle(
    http.BaseRequest request,
    _AbortableClient client,
  ) async {
    final message = jsonDecode((request as http.Request).body);
    final method = message['method'] as String;
    methods.add(method);
    if (method == 'notifications/cancelled' && !_cancellationSent.isCompleted) {
      _cancellationSent.complete();
    }
    if (method == 'initialize') {
      return http.StreamedResponse(
        Stream.value(
          utf8.encode(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': message['id'],
              'result': {'protocolVersion': '2025-06-18'},
            }),
          ),
        ),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (method != 'tools/call') {
      return http.StreamedResponse(const Stream.empty(), 202);
    }
    final name = (message['params'] as Map)['name'] as String;
    _clients[name] = client;
    client.response = StreamController<List<int>>();
    (_started[name] ??= Completer<void>()).complete();
    return http.StreamedResponse(
      client.response!.stream,
      200,
      headers: {'content-type': 'text/event-stream'},
    );
  }

  Future<void> started(String name) =>
      (_started[name] ??= Completer<void>()).future;

  Future<void> get cancellationSent => _cancellationSent.future;

  _AbortableClient clientFor(String name) => _clients[name]!;

  void respond(String name) {
    final response = _clients[name]!.response!;
    response.add(
      utf8.encode(
        'data: ${jsonEncode({
          'jsonrpc': '2.0',
          'id': name == 'first' ? 2 : 3,
          'result': {'content': <Object>[], 'isError': false},
        })}\n\n',
      ),
    );
    unawaited(response.close());
  }
}

class _AbortableClient extends http.BaseClient {
  final Future<http.StreamedResponse> Function(
    http.BaseRequest,
    _AbortableClient,
  )
  handler;
  StreamController<List<int>>? response;
  bool closed = false;

  _AbortableClient(this.handler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handler(request, this);

  @override
  void close() {
    closed = true;
  }
}
