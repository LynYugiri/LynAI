import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lynai/models/model_config.dart';
import 'package:lynai/services/backend_client.dart';
import 'package:lynai/providers/model_config_provider.dart';

import 'support/memory_repositories.dart';

void main() {
  group('ModelConfigProvider.syncLynaiManagedProvider', () {
    test('parses schemaVersion 3 provider models without fallback', () async {
      final provider = memoryModelConfigProvider();
      final backend = _FakeBackendClient(
        responses: {
          '/relay/config': _jsonResponse({
            'object': 'relay_config',
            'schemaVersion': 3,
            'data': [
              {
                'providerId': 'provider-1',
                'name': '官方中转',
                'models': [
                  {
                    'id': 'gpt-rich',
                    'category': ModelConfig.categoryChat,
                    'capabilities': {
                      'vision': true,
                      'thinking': false,
                      'tools': true,
                    },
                    'advancedParams': {'maxTokens': 2048, 'temperature': 0.2},
                  },
                ],
              },
            ],
          }),
        },
      );

      expect(await provider.syncLynaiManagedProvider(backend), isTrue);

      final model = provider.models.single;
      expect(model.id, '__lynai_relay_provider-1_chat__');
      expect(model.name, 'LynAI 官方中转');
      expect(model.managed, isTrue);
      expect(model.relayProviderId, 'provider-1');
      expect(model.endpoint, 'https://api.example.com/relay');
      expect(model.apiType, isEmpty);
      expect(model.toJson().containsKey('apiType'), isFalse);
      expect(model.modelName, 'gpt-rich');
      expect(model.maxTokens, isNull);
      expect(model.temperature, isNull);
      expect(model.models.single.maxTokens, 2048);
      expect(model.models.single.temperature, 0.2);
      expect(model.models.single.supportsThinking, isFalse);
      expect(model.supportsNativeTools, isTrue);
      expect(backend.requestedPaths, ['/relay/config']);
    });

    test('rejects non-v3 relay config', () async {
      final provider = memoryModelConfigProvider();
      final backend = _FakeBackendClient(
        responses: {
          '/relay/config': _jsonResponse({'schemaVersion': 2, 'data': []}),
        },
      );

      expect(await provider.syncLynaiManagedProvider(backend), isFalse);
      expect(provider.models, isEmpty);
    });

    test('missing managed capabilities default false', () async {
      final provider = memoryModelConfigProvider();
      final backend = _FakeBackendClient(
        responses: {
          '/relay/config': _jsonResponse({
            'schemaVersion': 3,
            'data': [
              {
                'providerId': 'provider-1',
                'models': [
                  {'id': 'model-a', 'category': 'chat'},
                ],
              },
            ],
          }),
        },
      );

      expect(await provider.syncLynaiManagedProvider(backend), isTrue);
      final model = provider.models.single;
      expect(model.supportsVision, isFalse);
      expect(model.supportsThinking, isFalse);
      expect(model.supportsTools, isFalse);
    });

    test(
      'offline load normalizes legacy managed id and keeps migration',
      () async {
        final repository = MemoryModelConfigRepository();
        final first = ModelConfigProvider(repository: repository);
        await first.replaceModels([
          ModelConfig(
            id: '__lynai_relay_provider-1_openai_chat__',
            name: 'Legacy',
            endpoint: 'https://api.example.com/relay',
            apiKey: '',
            modelName: 'model-a',
            apiType: '',
            priority: 0,
            managed: true,
            relayProviderId: 'provider-1',
          ),
        ]);

        final provider = ModelConfigProvider(repository: repository);
        await provider.loadModels();
        expect(provider.models.single.id, '__lynai_relay_provider-1_chat__');
        expect(provider.peekManagedModelIdMigrations(), {
          '__lynai_relay_provider-1_openai_chat__':
              '__lynai_relay_provider-1_chat__',
        });
        expect(
          await provider.syncLynaiManagedProvider(
            _FakeBackendClient(connected: false),
          ),
          isTrue,
        );
        expect(provider.models, hasLength(1));
        expect(provider.peekManagedModelIdMigrations(), isNotEmpty);
      },
    );

    test('401 preserves managed config and pending migration', () async {
      final provider = memoryModelConfigProvider();
      provider.addModel(
        ModelConfig(
          id: '__lynai_relay_provider-1_openai_chat__',
          name: 'Legacy',
          endpoint: 'https://api.example.com/relay',
          apiKey: '',
          modelName: 'model-a',
          apiType: '',
          priority: 0,
          managed: true,
          relayProviderId: 'provider-1',
        ),
      );
      await provider.flushPendingSaves();
      await provider.loadModels();

      expect(
        await provider.syncLynaiManagedProvider(
          _FakeBackendClient(
            responses: {'/relay/config': _jsonResponse({}, statusCode: 401)},
          ),
        ),
        isTrue,
      );
      expect(provider.models.single.id, '__lynai_relay_provider-1_chat__');
      expect(provider.peekManagedModelIdMigrations(), isNotEmpty);
    });

    test(
      'managed advanced params are isolated and not forwarded as extras',
      () async {
        final provider = memoryModelConfigProvider();
        final backend = _FakeBackendClient(
          responses: {
            '/relay/config': _jsonResponse({
              'schemaVersion': 3,
              'data': [
                {
                  'providerId': 'provider-1',
                  'models': [
                    {
                      'id': 'model-a',
                      'category': 'chat',
                      'advancedParams': {
                        'maxTokens': 100,
                        'temperature': 0.1,
                        'presencePenalty': 0.8,
                        'seed': 7,
                        'stop': ['END'],
                        'user': 'backend-default',
                      },
                    },
                    {
                      'id': 'model-b',
                      'category': 'chat',
                      'advancedParams': {'maxTokens': 200, 'topP': 0.9},
                    },
                  ],
                },
              ],
            }),
          },
        );

        await provider.syncLynaiManagedProvider(backend);
        final model = provider.models.single;
        expect(model.extraParams, isEmpty);
        expect(model.models[0].maxTokens, 100);
        expect(model.models[0].temperature, 0.1);
        expect(model.models[0].topP, isNull);
        expect(model.models[1].maxTokens, 200);
        expect(model.models[1].temperature, isNull);
        expect(model.models[1].topP, 0.9);
      },
    );

    test(
      'schema3 model workflow is stored on the matching speech model',
      () async {
        final provider = memoryModelConfigProvider();
        final fixture = jsonDecode(
          await File(
            'test/fixtures/relay_config_schema3_vivo_lasr.json',
          ).readAsString(),
        );
        final backend = _FakeBackendClient(
          responses: {'/relay/config': _jsonResponse(fixture)},
        );

        await provider.syncLynaiManagedProvider(backend);
        final speech = provider.models.single;
        expect(speech.category, ModelConfig.categorySpeech);
        expect(speech.models[0].workflow, 'vivo_lasr');
        expect(speech.models[1].workflow, isNull);
        expect(speech.extraParams, isEmpty);
      },
    );

    test('managed capability overrides can only disable', () async {
      final provider = memoryModelConfigProvider();
      final backend = _FakeBackendClient(
        responses: {
          '/relay/config': _jsonResponse({
            'schemaVersion': 3,
            'data': [
              {
                'providerId': 'provider-1',
                'models': [
                  {
                    'id': 'model-a',
                    'category': 'chat',
                    'capabilities': {'vision': false, 'tools': true},
                  },
                ],
              },
            ],
          }),
        },
      );
      expect(await provider.syncLynaiManagedProvider(backend), isTrue);
      final id = provider.models.single.id;

      provider.setManagedUserOverride(id, 'supportsVision', true);
      provider.setManagedUserOverride(id, 'supportsTools', false);

      final model = provider.models.single;
      expect(model.supportsVision, isFalse);
      expect(model.supportsTools, isFalse);
      expect(model.userOverrides.containsKey('supportsVision'), isFalse);
      expect(model.userOverrides['supportsTools'], isFalse);
    });

    test('migrates local state from the old managed group id', () async {
      final provider = memoryModelConfigProvider();
      provider.addModel(
        ModelConfig(
          id: '__lynai_relay_provider-1_openai_chat__',
          name: 'LynAI',
          endpoint: 'https://api.example.com/relay',
          apiKey: '',
          modelName: 'model-b',
          apiType: 'openai',
          priority: 7,
          managed: true,
          relayProviderId: 'provider-1',
          disabledByUser: true,
          userOverrides: {'temperature': 0.4},
        ),
      );
      final backend = _FakeBackendClient(
        responses: {
          '/relay/config': _jsonResponse({
            'schemaVersion': 3,
            'data': [
              {
                'providerId': 'provider-1',
                'name': 'Relay',
                'models': [
                  {'id': 'model-a', 'category': 'chat'},
                  {'id': 'model-b', 'category': 'chat'},
                ],
              },
            ],
          }),
        },
      );

      expect(await provider.syncLynaiManagedProvider(backend), isTrue);

      final model = provider.models.single;
      expect(model.id, '__lynai_relay_provider-1_chat__');
      expect(model.priority, 7);
      expect(model.modelName, 'model-b');
      expect(model.disabledByUser, isTrue);
      expect(model.userOverrides, {'temperature': 0.4});
      final pending = provider.peekManagedModelIdMigrations();
      expect(pending, {
        '__lynai_relay_provider-1_openai_chat__':
            '__lynai_relay_provider-1_chat__',
      });
      expect(provider.peekManagedModelIdMigrations(), pending);
      await provider.ackManagedModelIdMigrations(pending);
      expect(provider.peekManagedModelIdMigrations(), isEmpty);
    });

    test('legacy relayProtocolVersion is ignored when decoding JSON', () {
      final decoded = ModelConfig.fromJson({
        'id': 'managed-provider',
        'name': 'LynAI',
        'endpoint': 'https://api.example.com/relay',
        'modelName': 'gpt-test',
        'apiType': 'openai',
        'priority': 0,
        'managed': true,
        'relayProviderId': 'provider-2',
        'relayProtocolVersion': 2,
      });

      expect(decoded.relayProviderId, 'provider-2');
      expect(decoded.toJson().containsKey('relayProtocolVersion'), isFalse);
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
  _FakeBackendClient({this.responses = const {}, this.connected = true});

  final Map<String, http.Response> responses;
  final bool connected;
  final List<String> requestedPaths = [];

  @override
  String get backendUrl => 'https://api.example.com/';

  @override
  String? get accessToken => 'token';

  @override
  bool get isConnected => connected;

  @override
  Future<http.Response> get(String path, {Map<String, String>? headers}) async {
    requestedPaths.add(path);
    return responses[path] ?? http.Response('{}', 404);
  }
}
