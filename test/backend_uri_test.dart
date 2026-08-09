import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/services/backend_uri.dart';

void main() {
  group('normalizeBackendUri', () {
    test('canonicalizes scheme and host case, strips default ports', () {
      expect(normalizeBackendUri('HTTPS://Example.COM:443/api'), 'https://example.com/api');
      expect(normalizeBackendUri('http://example.com:80'), 'http://example.com');
    });

    test('preserves explicit non-default ports', () {
      expect(normalizeBackendUri('https://example.com:8443/api/'), 'https://example.com:8443/api');
    });

    test('keeps path prefix without trailing slash', () {
      expect(normalizeBackendUri('https://example.com/relay/'), 'https://example.com/relay');
      expect(normalizeBackendUri('https://example.com/a/b/c'), 'https://example.com/a/b/c');
    });

    test('strips a root-only path', () {
      expect(normalizeBackendUri('https://example.com/'), 'https://example.com');
    });

    test('rejects invalid inputs', () {
      expect(normalizeBackendUri(''), '');
      expect(normalizeBackendUri('   '), '');
      expect(normalizeBackendUri('not a url'), '');
      expect(normalizeBackendUri('ftp://example.com'), '');
      expect(normalizeBackendUri('https://'), '');
    });
  });

  group('normalizedBackendOrigin', () {
    test('returns origin without path', () {
      expect(normalizedBackendOrigin('https://example.com:8443/a/b'), 'https://example.com:8443');
      expect(normalizedBackendOrigin('https://example.com/api'), 'https://example.com');
    });

    test('returns empty for invalid input', () {
      expect(normalizedBackendOrigin(''), '');
    });
  });

  group('insecure http detection', () {
    test('flags http and not https', () {
      expect(isInsecureHttpBackend('http://example.com'), isTrue);
      expect(isInsecureHttpBackend('https://example.com'), isFalse);
      expect(isInsecureHttpBackend('garbage'), isFalse);
    });

    test('produces warning only for http', () {
      expect(insecureHttpBackendWarning('http://example.com'), isNotNull);
      expect(insecureHttpBackendWarning('https://example.com'), isNull);
    });
  });
}
