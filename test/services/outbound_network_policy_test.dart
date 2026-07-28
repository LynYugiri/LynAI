import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lynai/services/bounded_outbound_http_client.dart';
import 'package:lynai/services/outbound_network_policy.dart';

void main() {
  test(
    'rejects URL credentials, loopback, private DNS, and unresolved hosts',
    () async {
      final policy = OutboundNetworkPolicy(
        hostResolver: (host) async => switch (host) {
          'private.example' => const ['192.168.1.10'],
          'missing.example' => const [],
          _ => const ['93.184.216.34'],
        },
      );

      await expectLater(
        policy.validate(Uri.parse('https://user:pass@example.com')),
        throwsA(
          isA<OutboundNetworkPolicyException>().having(
            (error) => error.rejection,
            'rejection',
            OutboundNetworkRejection.credentialsInUrl,
          ),
        ),
      );
      await expectLater(
        policy.validate(Uri.parse('https://127.0.0.1')),
        throwsA(isA<OutboundNetworkPolicyException>()),
      );
      await expectLater(
        policy.validate(Uri.parse('https://private.example')),
        throwsA(
          isA<OutboundNetworkPolicyException>().having(
            (error) => error.rejection,
            'rejection',
            OutboundNetworkRejection.nonPublicAddress,
          ),
        ),
      );
      await expectLater(
        policy.validate(Uri.parse('https://missing.example')),
        throwsA(
          isA<OutboundNetworkPolicyException>().having(
            (error) => error.rejection,
            'rejection',
            OutboundNetworkRejection.unresolvedHost,
          ),
        ),
      );
    },
  );

  test('revalidates redirects and strips sensitive headers', () async {
    final requests = <http.BaseRequest>[];
    final client = _RecordingClient((request) async {
      if (request.url.host == 'first.example') {
        return http.StreamedResponse(
          const Stream.empty(),
          307,
          headers: {'location': 'https://second.example/search'},
        );
      }
      return http.StreamedResponse(Stream.value(utf8.encode('{}')), 200);
    }, requests);
    final outbound = BoundedOutboundHttpClient(
      policy: OutboundNetworkPolicy(
        hostResolver: (host) async => const ['93.184.216.34'],
      ),
      clientFactory: () => client,
    );

    await outbound.send(
      method: 'GET',
      uri: Uri.parse('https://first.example/search'),
      headers: const {
        'Authorization': 'Bearer secret',
        'X-Api-Key': 'secret-key',
      },
    );

    expect(requests, hasLength(2));
    expect(requests.first.headers['Authorization'], 'Bearer secret');
    expect(requests.last.headers.containsKey('Authorization'), isFalse);
    expect(requests.last.headers.containsKey('X-Api-Key'), isFalse);
  });

  test('rejects a redirect target resolving to a private address', () async {
    final requests = <http.BaseRequest>[];
    final outbound = BoundedOutboundHttpClient(
      policy: OutboundNetworkPolicy(
        hostResolver: (host) async => host == 'public.example'
            ? const ['93.184.216.34']
            : const ['127.0.0.1'],
      ),
      clientFactory: () => _RecordingClient(
        (request) async => http.StreamedResponse(
          const Stream.empty(),
          302,
          headers: {'location': 'https://internal.example/search'},
        ),
        requests,
      ),
    );

    await expectLater(
      outbound.send(
        method: 'GET',
        uri: Uri.parse('https://public.example/search'),
      ),
      throwsA(isA<OutboundNetworkPolicyException>()),
    );
    expect(requests, hasLength(1));
  });

  test('enforces request and streamed response byte limits', () async {
    final outbound = BoundedOutboundHttpClient(
      policy: OutboundNetworkPolicy(
        hostResolver: (host) async => const ['93.184.216.34'],
      ),
      clientFactory: () => _RecordingClient(
        (request) async => http.StreamedResponse(
          Stream.fromIterable([utf8.encode('1234'), utf8.encode('5678')]),
          200,
        ),
        [],
      ),
    );

    await expectLater(
      outbound.send(
        method: 'POST',
        uri: Uri.parse('https://example.com/search'),
        bodyBytes: utf8.encode('too large'),
        maxRequestBytes: 2,
      ),
      throwsA(isA<OutboundHttpException>()),
    );
    await expectLater(
      outbound.send(
        method: 'GET',
        uri: Uri.parse('https://example.com/search'),
        maxResponseBytes: 6,
      ),
      throwsA(isA<OutboundResponseTooLargeException>()),
    );
  });

  test('cancellation closes the active request client', () async {
    final cancellation = Completer<void>();
    late _HangingClient client;
    final outbound = BoundedOutboundHttpClient(
      policy: OutboundNetworkPolicy(
        hostResolver: (host) async => const ['93.184.216.34'],
      ),
      clientFactory: () => client = _HangingClient(),
    );

    final operation = outbound.send(
      method: 'GET',
      uri: Uri.parse('https://example.com/search'),
      cancellation: cancellation.future,
    );
    await Future<void>.delayed(Duration.zero);
    cancellation.complete();

    await expectLater(
      operation,
      throwsA(isA<OutboundRequestCancelledException>()),
    );
    expect(client.closed, isTrue);
  });

  test(
    'native transport connects to the exact resolver-approved address',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requests = <HttpRequest>[];
      final subscription = server.listen((request) async {
        requests.add(request);
        request.response.write('pinned');
        await request.response.close();
      });
      final uri = Uri.parse('http://rebind.invalid:${server.port}/resource');
      final outbound = BoundedOutboundHttpClient(
        policy: OutboundNetworkPolicy(
          allowedHttpOrigins: {outboundOrigin(uri)},
          allowPrivateNetwork: true,
          hostResolver: (host) async => const ['127.0.0.1'],
        ),
      );

      try {
        final response = await outbound.send(method: 'GET', uri: uri);

        expect(utf8.decode(response.bodyBytes), 'pinned');
        expect(requests, hasLength(1));
        expect(requests.single.headers.host, 'rebind.invalid');
        expect(requests.single.requestedUri.port, server.port);
      } finally {
        await subscription.cancel();
        await server.close(force: true);
      }
    },
  );

  test('native redirects resolve and pin every hop independently', () async {
    final first = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final second = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final firstUri = Uri.parse('http://first.invalid:${first.port}/start');
    final secondUri = Uri.parse('http://second.invalid:${second.port}/finish');
    final resolved = <String>[];
    final firstSubscription = first.listen((request) async {
      request.response.statusCode = HttpStatus.found;
      request.response.headers.set(HttpHeaders.locationHeader, secondUri);
      await request.response.close();
    });
    final secondSubscription = second.listen((request) async {
      request.response.write('redirected');
      await request.response.close();
    });
    final outbound = BoundedOutboundHttpClient(
      policy: OutboundNetworkPolicy(
        allowedHttpOrigins: {
          outboundOrigin(firstUri),
          outboundOrigin(secondUri),
        },
        allowPrivateNetwork: true,
        hostResolver: (host) async {
          resolved.add(host);
          return const ['127.0.0.1'];
        },
      ),
    );

    try {
      final response = await outbound.send(method: 'GET', uri: firstUri);

      expect(utf8.decode(response.bodyBytes), 'redirected');
      expect(resolved, ['first.invalid', 'second.invalid']);
      expect(response.uri, secondUri);
    } finally {
      await firstSubscription.cancel();
      await secondSubscription.cancel();
      await first.close(force: true);
      await second.close(force: true);
    }
  });

  test(
    'plain HTTP is denied before DNS unless its exact origin is allowed',
    () async {
      var resolutions = 0;
      final policy = OutboundNetworkPolicy(
        allowedHttpOrigins: const {'http://allowed.example:8080'},
        hostResolver: (host) async {
          resolutions++;
          return const ['93.184.216.34'];
        },
      );

      await expectLater(
        policy.resolve(Uri.parse('http://allowed.example/')),
        throwsA(
          isA<OutboundNetworkPolicyException>().having(
            (error) => error.rejection,
            'rejection',
            OutboundNetworkRejection.unsupportedScheme,
          ),
        ),
      );
      await expectLater(
        policy.resolve(Uri.parse('http://other.example:8080/')),
        throwsA(isA<OutboundNetworkPolicyException>()),
      );
      expect(resolutions, 0);

      await policy.resolve(Uri.parse('http://allowed.example:8080/path'));
      expect(resolutions, 1);
    },
  );
}

class _RecordingClient extends http.BaseClient {
  _RecordingClient(this.handler, this.requests);

  final Future<http.StreamedResponse> Function(http.BaseRequest) handler;
  final List<http.BaseRequest> requests;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requests.add(request);
    return handler(request);
  }
}

class _HangingClient extends http.BaseClient {
  final Completer<http.StreamedResponse> _response = Completer();
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _response.future;

  @override
  void close() {
    closed = true;
  }
}
