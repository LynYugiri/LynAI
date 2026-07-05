import 'package:flutter_test/flutter_test.dart';
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
}
