import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/services/outbound_http_client_factory.dart';
import 'package:lynai/services/outbound_http_client_factory_io.dart'
    as io_factory;
import 'package:lynai/services/outbound_network_policy.dart';

class _RealHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.connectionTimeout = const Duration(seconds: 5);
    return client;
  }
}

/// 测试专用自签名证书（RSA-2048，有效期 100 年，仅用于本地 TLS 集成测试）。
const _testCertificatePem = '''
-----BEGIN CERTIFICATE-----
MIIDHDCCAgSgAwIBAgIUYtsUUW/0MTEKH1F71EwjPzlq8kAwDQYJKoZIhvcNAQEL
BQAwFDESMBAGA1UEAwwJMTI3LjAuMC4xMCAXDTI2MDgwNzExNDAxOVoYDzIxMjYw
NzE0MTE0MDE5WjAUMRIwEAYDVQQDDAkxMjcuMC4wLjEwggEiMA0GCSqGSIb3DQEB
AQUAA4IBDwAwggEKAoIBAQCmEzDErXC0Et+JhtdbIeGxvUC0elpFPH2j9840hBh9
GfI8RUnF5PF+roXTQgt+q3o/TPZoBNVwxhJuaegSu6OF2TxtzzHhVJwVlkEmXXO2
+C+mrzwX9o/g+Hafc8p2K22MFlwTYzePqKFYpLObsKetXKqTCei4EDzZS3mlhebW
/5zpyTEjenVh4LhuILVwZ64vgZydBKZnyMTd9T6S3nbtkDkxKn5kPI74/86EM/CD
5jSth/Pi0CTTJ84YHx3g9vaBFtrYRGxIecOg7DMdc2v5m+ae0kglt5+Wv0IqahC4
BnfYNBoM0upOvNHVZI2CZlW5wxrJ5h6BvMvitb9WKO/xAgMBAAGjZDBiMB0GA1Ud
DgQWBBRcNn0yiq8eY9dO5Kk0lEqHHUOG7DAfBgNVHSMEGDAWgBRcNn0yiq8eY9dO
5Kk0lEqHHUOG7DAPBgNVHRMBAf8EBTADAQH/MA8GA1UdEQQIMAaHBH8AAAEwDQYJ
KoZIhvcNAQELBQADggEBADJqoDARlHyOH94MhxeP9yR0RSJqiX7NCiYMvCGFjIEn
3BGXya5MspBSk+qnU+u62LiMO5hBa9ctEI7wsGrB86bp/dWlTBjW2HBQ2VxRM+g5
os0t4BSuZ4SWXgy1E6JtJGLDJZtt9SKrqs0pbVTgYjxNeLjzhNpYGMJC9VXCnPOk
/4X4MlQeyB6V3J60fx2lseXv+Q2pWcJsdKYW5EyEUi0GTLLRiiAmiUmAYNvaqJNj
JH57hXrbztJeLES/p9xo0QQURs3wFlKh8AhDYfpL0rtZTXYlV8t1FExh+dnSLLqu
ZjXnChKXgHUIELywH1ElYFyhfBjkCLUjiH8lOG39BxI=
-----END CERTIFICATE-----
''';

const _testPrivateKeyPem = '''
-----BEGIN PRIVATE KEY-----
MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQCmEzDErXC0Et+J
htdbIeGxvUC0elpFPH2j9840hBh9GfI8RUnF5PF+roXTQgt+q3o/TPZoBNVwxhJu
aegSu6OF2TxtzzHhVJwVlkEmXXO2+C+mrzwX9o/g+Hafc8p2K22MFlwTYzePqKFY
pLObsKetXKqTCei4EDzZS3mlhebW/5zpyTEjenVh4LhuILVwZ64vgZydBKZnyMTd
9T6S3nbtkDkxKn5kPI74/86EM/CD5jSth/Pi0CTTJ84YHx3g9vaBFtrYRGxIecOg
7DMdc2v5m+ae0kglt5+Wv0IqahC4BnfYNBoM0upOvNHVZI2CZlW5wxrJ5h6BvMvi
tb9WKO/xAgMBAAECggEAFZ6O7TOU5eRFFF6o31S4UE6OQ1BgOv4mbvd98Qk3NOXx
SlZMxcXJiE/I3RkObQV+qwnmU+E5Ne6bDKOd0f56SZzfiH3+BNLiZM8EGS32N930
OhM60/XFgihmLNjChQKfRqrMfrueSoXNxz/dn8lt8pwLGowiLv/yI+l24wzc4aT8
MDN47D9bNkbJ7wOe4mDXb674IjCFjMsub3qVVK14mLqvDrx29PjcwsQplr8pz4Fi
a95mq6y/PM3ggDIgdw+/DAEG0AOG+tpgE1h9el10SYay+IQu8H5XvujbpiZMGBJl
KEXi+B1qiTEfpmc8iak9cJlArtUPGXbS04mD08+f3wKBgQDaCVo+cRh4yqEB5d0c
Q0KN08F5OcnrrUgQ8dsPF7wK7LqpPVhQxIwEUpLkwhFLR6W3m8G6pFmBuhZnmI3Y
80y6FRb/ByzbbNY65X4HQBovgM0wv8HgElUH2eX9e2SqRIkrF8kH1NMFRUFETOTE
nZqhHdwACCDpy2u6iH2UbB+b3wKBgQDC/brYesW+jGqhhMgcH+AaJXTq5U19ws6+
InkxDGqneFOUrkufnsPMevp5Do3fLDj9OChrJHcerY0q9p08q8O1T3I0J494yAiw
H71sdTaW1j95iXN5YlawIBeHqGgCUtPoEzCQ+x607veW2XHolWfEGN+zESzV0Otx
NlJK1M7uLwKBgDsUWa2du4HPdf0rqdQkrX38qOoOLJZ9p49f2Xmndr6HErUU+D86
Yq4xKbhulX0Odurfe4j1S4OJRtTfU2A73Mh3Onn0GcWDIjFnSdTxG6dPgUn6S7BJ
h1zPQDCFJOu2EmzozwIeOuesslitdTeJdQK/MoOXsENpaVFr9osnGRGFAoGAEUxd
JRNPM6ZVV1rmPch+IxOrmaMaCswbdzartbQ6Sf0cvRXxU4nMKPnH+rFV2LSdoak3
vLmRb8FJwsP6EwXR6OXRZdsUmUx1qNpH/bUwUJVVMD0HZ39X3WwbakeAYqRidDYv
ms0MXlTM1i8YMd//QqBKSCJ/7cAJAxQknMrgSLUCgYEAw74kS9rRO53eSyUnZvsK
R26Fg2Nc50z7Lf+1uK00QD1dH12BuykJpWsx8hNhx7Z/iRa5kLKCvvmPUXlvP0FT
N3kkU/Ld0FG1FAtVxzzZ8yf1oUTpMqS/Agv6gghO3kU8tzMwmwOMVQWRE/jHHhr4
HrrfOEE1C+60NP6V5dd0JjE=
-----END PRIVATE KEY-----
''';

SecurityContext _serverContext() => SecurityContext()
  ..useCertificateChainBytes(_testCertificatePem.codeUnits)
  ..usePrivateKeyBytes(_testPrivateKeyPem.codeUnits);

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

    test('performs a TLS handshake for HTTPS requests', () async {
      final server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        _serverContext(),
      );
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        expect(request.requestedUri.host, '127.0.0.1');
        request.response.statusCode = HttpStatus.ok;
        request.response.write('tls-ok');
        await request.response.close();
      });

      await HttpOverrides.runZoned(() async {
        final client = io_factory.createOutboundHttpClient(
          ['127.0.0.1'],
          onBadCertificate: (_) => true,
        );
        addTearDown(client.close);
        final response = await client.get(
          Uri.parse('https://127.0.0.1:${server.port}/'),
        );
        expect(response.statusCode, 200);
        expect(response.body, 'tls-ok');
      }, createHttpClient: _RealHttpOverrides().createHttpClient);
    });

    test('falls back to a later address when TLS fails on the first',
        () async {
      final plain = await HttpServer.bind(
        InternetAddress('127.0.0.1'),
        0,
      );
      addTearDown(() => plain.close(force: true));
      plain.listen((request) async {
        request.response.statusCode = HttpStatus.badRequest;
        await request.response.close();
      });

      final secure = await HttpServer.bindSecure(
        InternetAddress('127.0.0.2'),
        plain.port,
        _serverContext(),
      );
      addTearDown(() => secure.close(force: true));
      secure.listen((request) async {
        request.response.statusCode = HttpStatus.ok;
        request.response.write('tls-fallback');
        await request.response.close();
      });

      await HttpOverrides.runZoned(() async {
        final client = io_factory.createOutboundHttpClient(
          ['127.0.0.1', '127.0.0.2'],
          onBadCertificate: (_) => true,
        );
        addTearDown(client.close);
        final response = await client.get(
          Uri.parse('https://127.0.0.1:${plain.port}/'),
        );
        expect(response.statusCode, 200);
        expect(response.body, 'tls-fallback');
      }, createHttpClient: _RealHttpOverrides().createHttpClient);
    });

    test('rejects HTTPS requests whose certificate cannot be verified',
        () async {
      final server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        _serverContext(),
      );
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        request.response.statusCode = HttpStatus.ok;
        await request.response.close();
      });

      await HttpOverrides.runZoned(() async {
        final client = io_factory.createOutboundHttpClient(['127.0.0.1']);
        addTearDown(client.close);
        await expectLater(
          client.get(Uri.parse('https://127.0.0.1:${server.port}/')),
          throwsA(isA<HandshakeException>()),
        );
      }, createHttpClient: _RealHttpOverrides().createHttpClient);
    });
  });
}
