import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lynai/models/model_config.dart';
import 'package:lynai/services/backend_client.dart';

import 'support/memory_repositories.dart';

void main() {
  group('ModelConfigProvider.syncLynaiManagedProvider', () {
    test('uses providerName from flat relay model payloads', () async {
      final provider = memoryModelConfigProvider();
      final backend = _FakeBackendClient(
        responses: {
          '/relay/config': http.Response('{}', 404),
          '/relay/models': _jsonResponse({
            'object': 'list',
            'data': [
              {
                'id': 'gpt-rich',
                'api_type': 'openai',
                'category': ModelConfig.categoryChat,
                'providerId': 'provider-1',
                'providerName': '官方中转',
                'capabilities': {'vision': true, 'thinking': false},
                'advancedParams': {'maxTokens': 2048, 'temperature': 0.2},
              },
            ],
          }),
        },
      );

      expect(await provider.syncLynaiManagedProvider(backend), isTrue);

      final model = provider.models.single;
      expect(model.name, 'LynAI 官方中转');
      expect(model.managed, isTrue);
      expect(model.endpoint, 'https://api.example.com/relay');
      expect(model.apiType, 'openai');
      expect(model.category, ModelConfig.categoryChat);
      expect(model.modelName, 'gpt-rich');
      expect(model.maxTokens, 2048);
      expect(model.temperature, 0.2);
      expect(model.models.single.supportsThinking, isFalse);
    });
  });
}

http.Response _jsonResponse(Object body, {int statusCode = 200}) {
  return http.Response.bytes(
    utf8.encode(jsonEncode(body)),
    statusCode,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

class _FakeBackendClient extends BackendClient {
  _FakeBackendClient({required this.responses});

  final Map<String, http.Response> responses;

  @override
  String get backendUrl => 'https://api.example.com/';

  @override
  String? get accessToken => 'token';

  @override
  bool get isConnected => true;

  @override
  Future<http.Response> get(String path, {Map<String, String>? headers}) async {
    return responses[path] ?? http.Response('{}', 404);
  }
}
