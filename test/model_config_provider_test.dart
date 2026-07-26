import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lynai/models/model_config.dart';
import 'package:lynai/providers/model_config_provider.dart';
import 'package:lynai/services/backend_client.dart';

import 'support/memory_repositories.dart';

void main() {
  test('load normalizes provider-scoped managed IDs by category', () async {
    final repository = MemoryModelConfigRepository();
    repository.seed([
      ModelConfig(
        id: '__lynai_relay_provider-1_openai_chat__',
        name: 'Legacy One',
        endpoint: 'https://one.example/relay',
        apiKey: '',
        modelName: 'shared',
        apiType: '',
        priority: 1,
        managed: true,
        disabledByUser: true,
        userOverrides: const {'temperature': 0.4},
        models: [
          ModelEntry(name: 'one', enabled: true),
          ModelEntry(name: 'shared', enabled: true),
        ],
      ),
      ModelConfig(
        id: '__lynai_relay_provider-2_chat__',
        name: 'Legacy Two',
        endpoint: 'https://two.example/relay',
        apiKey: '',
        modelName: 'two',
        apiType: '',
        priority: 0,
        managed: true,
        models: [
          ModelEntry(name: 'two', enabled: false),
          ModelEntry(name: 'shared', enabled: true),
        ],
      ),
    ]);
    final provider = ModelConfigProvider(repository: repository);

    await provider.loadModels();

    final model = provider.models.single;
    expect(model.id, '__lynai_relay_chat__');
    expect(model.name, 'LynAI');
    expect(model.endpoint, 'https://two.example/relay');
    expect(model.priority, 0);
    expect(model.modelName, 'two');
    expect(model.models.map((entry) => entry.name), ['two', 'shared', 'one']);
    expect(provider.peekManagedModelIdMigrations(), {
      '__lynai_relay_provider-1_openai_chat__': '__lynai_relay_chat__',
      '__lynai_relay_provider-2_chat__': '__lynai_relay_chat__',
    });

    final reloaded = ModelConfigProvider(repository: repository);
    await reloaded.loadModels();
    expect(reloaded.models.single.id, '__lynai_relay_chat__');
    expect(reloaded.peekManagedModelIdMigrations(), isNotEmpty);
  });

  group('ModelConfigProvider.syncLynaiManagedModels', () {
    test('groups schemaVersion 4 flat models by normalized category', () async {
      final provider = memoryModelConfigProvider();
      final backend = _FakeBackendClient(
        responses: {
          '/relay/config': _jsonResponse({
            'object': 'relay_config',
            'schemaVersion': 4,
            'data': [
              {
                'id': 'gpt-rich',
                'category': ModelConfig.categoryChat,
                'displayName': 'Rich Chat',
                'description': 'Chat model',
                'capabilities': {
                  'vision': true,
                  'thinking': false,
                  'tools': true,
                },
                'advancedParams': {'maxTokens': 2048, 'temperature': 0.2},
                'enabled': true,
              },
              {
                'id': 'fallback-chat',
                'category': 'unknown',
                'displayName': 'Fallback Chat',
                'description': '',
                'capabilities': {},
                'advancedParams': {},
                'enabled': false,
              },
              {
                'id': 'image-a',
                'category': ModelConfig.categoryImageGeneration,
                'displayName': 'Image',
                'description': '',
                'capabilities': {},
                'advancedParams': {},
                'enabled': true,
              },
            ],
          }),
        },
      );

      expect(await provider.syncLynaiManagedModels(backend), isTrue);

      expect(provider.models, hasLength(2));
      final chat = provider.models.firstWhere(
        (model) => model.category == ModelConfig.categoryChat,
      );
      expect(chat.id, '__lynai_relay_chat__');
      expect(chat.name, 'LynAI');
      expect(chat.managed, isTrue);
      expect(chat.endpoint, 'https://api.example.com/relay');
      expect(chat.apiType, isEmpty);
      expect(chat.toJson().containsKey('apiType'), isFalse);
      expect(chat.toJson().containsKey('relayProviderId'), isFalse);
      expect(chat.modelName, 'gpt-rich');
      expect(chat.models.map((entry) => entry.name), [
        'gpt-rich',
        'fallback-chat',
      ]);
      expect(chat.models[1].enabled, isFalse);
      expect(chat.models.first.maxTokens, 2048);
      expect(chat.models.first.temperature, 0.2);
      expect(chat.models.first.supportsThinking, isFalse);
      expect(chat.supportsNativeTools, isTrue);
      expect(backend.requestedPaths, ['/relay/config']);
    });

    test('invalid, failed, and offline sync retain managed models', () async {
      final provider = memoryModelConfigProvider();
      provider.addModel(_managedModel());
      await provider.flushPendingSaves();

      expect(
        await provider.syncLynaiManagedModels(
          _FakeBackendClient(
            responses: {
              '/relay/config': _jsonResponse({
                'object': 'relay_config',
                'schemaVersion': 3,
                'data': [],
              }),
            },
          ),
        ),
        isFalse,
      );
      expect(provider.models.single.modelName, 'model-a');

      expect(
        await provider.syncLynaiManagedModels(
          _FakeBackendClient(
            responses: {
              '/relay/config': _jsonResponse({
                'object': 'relay_config',
                'schemaVersion': 4,
                'data': [
                  {'id': 'incomplete'},
                ],
              }),
            },
          ),
        ),
        isFalse,
      );
      expect(provider.models.single.modelName, 'model-a');

      expect(
        await provider.syncLynaiManagedModels(
          _FakeBackendClient(
            responses: {'/relay/config': http.Response('bad json', 200)},
          ),
        ),
        isFalse,
      );
      expect(provider.models.single.modelName, 'model-a');

      expect(
        await provider.syncLynaiManagedModels(
          _FakeBackendClient(
            responses: {'/relay/config': _jsonResponse({}, statusCode: 500)},
          ),
        ),
        isFalse,
      );
      expect(provider.models.single.modelName, 'model-a');

      expect(
        await provider.syncLynaiManagedModels(
          _FakeBackendClient(connected: false),
        ),
        isTrue,
      );
      expect(provider.models.single.modelName, 'model-a');
    });

    test('preserves category-local state and replaces managed set', () async {
      final provider = memoryModelConfigProvider();
      provider.addModel(
        _managedModel(
          modelName: 'model-b',
          priority: 7,
          disabledByUser: true,
          userOverrides: {'temperature': 0.4},
        ),
      );
      provider.addModel(
        ModelConfig(
          id: '__lynai_relay_speech__',
          name: 'LynAI',
          category: ModelConfig.categorySpeech,
          endpoint: 'https://old.example/relay',
          apiKey: '',
          modelName: 'old-speech',
          apiType: '',
          priority: 2,
          managed: true,
        ),
      );
      final backend = _FakeBackendClient(
        responses: {
          '/relay/config': _jsonResponse({
            'object': 'relay_config',
            'schemaVersion': 4,
            'data': [_relayModel('model-a'), _relayModel('model-b')],
          }),
        },
      );

      expect(await provider.syncLynaiManagedModels(backend), isTrue);

      final model = provider.models.single;
      expect(model.id, '__lynai_relay_chat__');
      expect(model.priority, 7);
      expect(model.modelName, 'model-b');
      expect(model.disabledByUser, isTrue);
      expect(model.userOverrides, {'temperature': 0.4});
    });

    test(
      'chooses legacy state whose selected model remains available',
      () async {
        final provider = memoryModelConfigProvider();
        provider.addModel(
          ModelConfig(
            id: '__lynai_relay_provider-1_openai_chat__',
            name: 'Legacy One',
            endpoint: 'https://old.example/relay',
            apiKey: '',
            modelName: 'removed-model',
            apiType: '',
            priority: 0,
            managed: true,
            disabledByUser: true,
          ),
        );
        provider.addModel(
          ModelConfig(
            id: '__lynai_relay_provider-2_chat__',
            name: 'Legacy Two',
            endpoint: 'https://old.example/relay',
            apiKey: '',
            modelName: 'model-b',
            apiType: '',
            priority: 4,
            managed: true,
            userOverrides: const {'temperature': 0.3},
          ),
        );
        await provider.flushPendingSaves();

        expect(
          await provider.syncLynaiManagedModels(
            _FakeBackendClient(
              responses: {
                '/relay/config': _jsonResponse({
                  'object': 'relay_config',
                  'schemaVersion': 4,
                  'data': [_relayModel('model-a'), _relayModel('model-b')],
                }),
              },
            ),
          ),
          isTrue,
        );

        final model = provider.models.single;
        expect(model.id, '__lynai_relay_chat__');
        expect(model.modelName, 'model-b');
        expect(model.priority, 4);
        expect(model.disabledByUser, isFalse);
        expect(model.userOverrides, {'temperature': 0.3});
        expect(provider.peekManagedModelIdMigrations(), {
          '__lynai_relay_provider-1_openai_chat__': '__lynai_relay_chat__',
          '__lynai_relay_provider-2_chat__': '__lynai_relay_chat__',
        });
      },
    );

    test('stores workflow and isolates advanced params per model', () async {
      final provider = memoryModelConfigProvider();
      final fixture = jsonDecode(
        await File(
          'test/fixtures/relay_config_schema4_vivo_lasr.json',
        ).readAsString(),
      );

      expect(
        await provider.syncLynaiManagedModels(
          _FakeBackendClient(
            responses: {'/relay/config': _jsonResponse(fixture)},
          ),
        ),
        isTrue,
      );

      final speech = provider.models.single;
      expect(speech.id, '__lynai_relay_speech__');
      expect(speech.models[0].workflow, 'vivo_lasr');
      expect(speech.models[1].workflow, isNull);
      expect(speech.models[0].maxTokens, 4096);
      expect(speech.models[1].temperature, 0.2);
      expect(speech.extraParams, isEmpty);
    });

    test('managed capability overrides can only disable', () async {
      final provider = memoryModelConfigProvider();
      final backend = _FakeBackendClient(
        responses: {
          '/relay/config': _jsonResponse({
            'object': 'relay_config',
            'schemaVersion': 4,
            'data': [
              _relayModel(
                'model-a',
                capabilities: {'vision': false, 'tools': true},
              ),
            ],
          }),
        },
      );
      expect(await provider.syncLynaiManagedModels(backend), isTrue);
      final id = provider.models.single.id;

      provider.setManagedUserOverride(id, 'supportsVision', true);
      provider.setManagedUserOverride(id, 'supportsTools', false);

      final model = provider.models.single;
      expect(model.supportsVision, isFalse);
      expect(model.supportsTools, isFalse);
      expect(model.userOverrides.containsKey('supportsVision'), isFalse);
      expect(model.userOverrides['supportsTools'], isFalse);
    });

    test(
      'discards a delayed response after managed models are removed',
      () async {
        final provider = memoryModelConfigProvider();
        final response = Completer<http.Response>();
        final backend = _FakeBackendClient(
          responseHandler: (_) => response.future,
        );

        final sync = provider.syncLynaiManagedModels(backend);
        await provider.removeLynaiManagedModels();
        response.complete(
          _jsonResponse({
            'object': 'relay_config',
            'schemaVersion': 4,
            'data': [_relayModel('stale-model')],
          }),
        );

        expect(await sync, isFalse);
        expect(provider.models, isEmpty);
      },
    );

    test('latest sync wins after backend and token switch', () async {
      final provider = memoryModelConfigProvider();
      final oldResponse = Completer<http.Response>();
      final newResponse = Completer<http.Response>();
      var requestCount = 0;
      final backend = _FakeBackendClient(
        responseHandler: (_) {
          requestCount++;
          return requestCount == 1 ? oldResponse.future : newResponse.future;
        },
      );

      final oldSync = provider.syncLynaiManagedModels(backend);
      backend
        ..url = 'https://new.example.com/base/'
        ..token = 'new-token';
      final newSync = provider.syncLynaiManagedModels(backend);
      newResponse.complete(
        _jsonResponse({
          'object': 'relay_config',
          'schemaVersion': 4,
          'data': [_relayModel('new-model')],
        }),
      );
      expect(await newSync, isTrue);
      oldResponse.complete(
        _jsonResponse({
          'object': 'relay_config',
          'schemaVersion': 4,
          'data': [_relayModel('old-model')],
        }),
      );

      expect(await oldSync, isFalse);
      expect(provider.models.single.modelName, 'new-model');
      expect(
        provider.models.single.endpoint,
        'https://new.example.com/base/relay',
      );
    });
  });
}

ModelConfig _managedModel({
  String modelName = 'model-a',
  int priority = 0,
  bool disabledByUser = false,
  Map<String, dynamic> userOverrides = const {},
}) {
  return ModelConfig(
    id: '__lynai_relay_chat__',
    name: 'LynAI',
    endpoint: 'https://api.example.com/relay',
    apiKey: '',
    modelName: modelName,
    apiType: '',
    priority: priority,
    managed: true,
    disabledByUser: disabledByUser,
    userOverrides: userOverrides,
    models: [
      ModelEntry(name: 'model-a', enabled: true),
      ModelEntry(name: 'model-b', enabled: true),
    ],
  );
}

Map<String, dynamic> _relayModel(
  String id, {
  Map<String, dynamic> capabilities = const {},
}) {
  return {
    'id': id,
    'category': ModelConfig.categoryChat,
    'displayName': id,
    'description': '',
    'capabilities': capabilities,
    'advancedParams': <String, dynamic>{},
    'enabled': true,
  };
}

http.Response _jsonResponse(Object body, {int statusCode = 200}) {
  return http.Response.bytes(
    utf8.encode(jsonEncode(body)),
    statusCode,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

class _FakeBackendClient extends BackendClient {
  _FakeBackendClient({
    this.responses = const {},
    this.connected = true,
    this.responseHandler,
  });

  final Map<String, http.Response> responses;
  final bool connected;
  final FutureOr<http.Response> Function(String path)? responseHandler;
  final List<String> requestedPaths = [];
  String url = 'https://api.example.com/';
  String? token = 'token';

  @override
  String get backendUrl => url;

  @override
  String get backendOrigin => BackendClient.normalizeOrigin(url);

  @override
  String get backendScope => BackendClient.normalizeUrl(url);

  @override
  String? get accessToken => token;

  @override
  bool get isConnected => connected;

  @override
  Future<http.Response> get(String path, {Map<String, String>? headers}) async {
    requestedPaths.add(path);
    final handler = responseHandler;
    if (handler != null) return handler(path);
    return responses[path] ?? http.Response('{}', 404);
  }
}
