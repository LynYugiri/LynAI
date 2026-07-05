import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:lynai/providers/sync_provider.dart';
import 'package:lynai/services/backend_client.dart';
import 'package:lynai/services/sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('SyncProvider', () {
    test('captures status failures during flush upload', () async {
      SharedPreferences.setMockInitialValues({});
      final oldDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {};
      addTearDown(() => debugPrint = oldDebugPrint);

      final provider = SyncProvider(
        backend: _FakeBackendClient(
          responses: {
            '/sync/status': http.Response('{"error":"status down"}', 500),
          },
        ),
      );

      provider.recordChange(
        const SyncChangeRecord(
          table: 'messages',
          op: 'upsert',
          recordId: 'm1',
          data: {'id': 'm1'},
        ),
      );

      await expectLater(provider.flushUpload(), completes);
      expect(provider.syncing, isFalse);
      expect(provider.error, contains('status down'));
    });

    test('requires a non-empty access token', () {
      final provider = SyncProvider(
        backend: _FakeBackendClient(accessToken: ''),
      );

      expect(provider.canSync, isFalse);
    });
  });
}

class _FakeBackendClient extends BackendClient {
  _FakeBackendClient({this.responses = const {}, this.accessToken = 'token'});

  final Map<String, http.Response> responses;

  @override
  final String? accessToken;

  @override
  String get backendUrl => 'https://api.example.com';

  @override
  bool get isConnected => true;

  @override
  Future<http.Response> get(String path, {Map<String, String>? headers}) async {
    return responses[path] ?? http.Response('{}', 404);
  }
}
