import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/services/outbound_http_client_factory.dart';
import 'package:lynai/services/outbound_network_policy.dart';

class _RealHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.connectionTimeout = const Duration(seconds: 5);
    return client;
  }
}

void main() {
  group('OutboundNetworkPolicy.resolve', () {
    test('returns every validated address', () async {
      final policy = OutboundNetworkPolicy(
        hostResolver: (host) async => ['1.2.3.4', '5.6.7.8', '2606:4700::1'],
      );
      final target = await policy.resolve(Uri.parse('https://example.com'));
      expect(target.uri, Uri.parse('https://example.com'));
      expect(target.addresses, ['1.2.3.4', '5.6.7.8', '2606:4700::1']);
    });

    test('rejects when any resolved address is non-public', () async {
      final policy = OutboundNetworkPolicy(
        hostResolver: (host) async => ['1.2.3.4', '127.0.0.1'],
      );
      await expectLater(
        policy.resolve(Uri.parse('https://example.com')),
        throwsA(isA<OutboundNetworkPolicyException>()),
      );
    });
  });

  group('createOutboundHttpClient', () {
    test('falls back to a later address when the first is unreachable',
        () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        request.response.statusCode = HttpStatus.ok;
        await request.response.close();
      });

      await HttpOverrides.runZoned(() async {
        final client = createOutboundHttpClient(['127.0.0.2', '127.0.0.1']);
        addTearDown(client.close);
        final response = await client.get(
          Uri.parse('http://127.0.0.1:${server.port}/'),
        );
        expect(response.statusCode, 200);
      }, createHttpClient: _RealHttpOverrides().createHttpClient);
    });

    test('connects over IPv4 even when IPv6 addresses are listed first',
        () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        request.response.statusCode = HttpStatus.ok;
        await request.response.close();
      });

      await HttpOverrides.runZoned(() async {
        final client = createOutboundHttpClient(['::1', '127.0.0.1']);
        addTearDown(client.close);
        final response = await client.get(
          Uri.parse('http://127.0.0.1:${server.port}/'),
        );
        expect(response.statusCode, 200);
      }, createHttpClient: _RealHttpOverrides().createHttpClient);
    });

    test('throws the connect error when every address fails', () async {
      await HttpOverrides.runZoned(() async {
        final client = createOutboundHttpClient(['127.0.0.2']);
        addTearDown(client.close);
        await expectLater(
          client.get(Uri.parse('http://127.0.0.1:1/')),
          throwsA(isA<SocketException>()),
        );
      }, createHttpClient: _RealHttpOverrides().createHttpClient);
    });
  });
}
