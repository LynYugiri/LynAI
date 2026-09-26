import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lynai/models/model_config.dart';
import 'package:lynai/services/backend_client.dart';
import 'package:lynai/services/model_catalog_service.dart';
import 'package:lynai/services/outbound_network_policy.dart';

/// 内置快照用的假 AssetBundle。
class _FakeBundle extends CachingAssetBundle {
  _FakeBundle(this.payload);

  final String payload;

  @override
  Future<ByteData> load(String key) async {
    if (key != ModelCatalogService.bundledAssetPath) {
      throw StateError('unexpected asset: $key');
    }
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(payload)));
  }
}

Map<String, dynamic> _provider(String id, String name, List<String> models) {
  return {
    'id': id,
    'name': name,
    'models': {
      for (final model in models)
        model: {
          'id': model,
          'name': model,
          'attachment': true,
          'tool_call': true,
          'reasoning': true,
          'reasoning_options': [
            {
              'type': 'effort',
              'values': ['low', 'medium', 'high'],
            },
          ],
          'limit': {'context': 128000, 'output': 32000},
        },
    },
  };
}

String _documentJson({String source = 'models.dev'}) {
  return jsonEncode({
    'schemaVersion': 1,
    'source': source,
    'fetchedAt': '2026-01-01T00:00:00Z',
    'providers': {
      'openai': _provider('openai', 'OpenAI', ['gpt-4o']),
      'unknown-provider': _provider('unknown-provider', 'Unknown', ['m']),
    },
  });
}

String _modelsDevApiJson() {
  return jsonEncode({
    'openai': {
      'id': 'openai',
      'name': 'OpenAI',
      'env': ['OPENAI_API_KEY'],
      'models': {
        'gpt-4o': {
          'id': 'gpt-4o',
          'name': 'GPT-4o',
          'description': 'should be trimmed',
          'cost': {'input': 1},
          'attachment': true,
          'tool_call': true,
          'reasoning': true,
          'limit': {'context': 128000, 'output': 16384},
        },
      },
    },
    'not-in-defaults': {
      'id': 'not-in-defaults',
      'name': 'Not In Defaults',
      'models': {
        'm': {'id': 'm', 'name': 'M'},
      },
    },
  });
}

OutboundNetworkPolicy _testPolicy() => OutboundNetworkPolicy(
  hostResolver: (host) async => const ['93.184.216.34'],
);

void main() {
  late Directory cacheDir;

  setUp(() async {
    cacheDir = await Directory.systemTemp.createTemp('lynai_catalog_');
  });

  tearDown(() async {
    if (await cacheDir.exists()) await cacheDir.delete(recursive: true);
  });

  ModelCatalogService buildService({
    String? bundled,
    http.Client? remoteClient,
    BackendClient? backend,
    bool enableRemote = false,
  }) {
    return ModelCatalogService(
      cacheDirectory: cacheDir,
      assetBundle: _FakeBundle(bundled ?? _documentJson()),
      clientFactory: remoteClient == null ? null : () => remoteClient,
      policy: _testPolicy(),
      backend: backend,
      enableRemote: enableRemote,
    );
  }

  test('没有缓存时使用内置快照', () async {
    final service = buildService();
    await service.ensureLoaded();

    expect(service.hasData, isTrue);
    expect(service.status.source, ModelCatalogLoadSource.bundled);
    expect(service.status.providerCount, 2);
    expect(service.status.modelCount, 2);
    expect(service.providers.map((item) => item.id), ['openai', 'unknown-provider']);
  });

  test('优先使用本地缓存文件', () async {
    final cached = jsonEncode({
      'schemaVersion': 1,
      'source': 'models.dev',
      'fetchedAt': '2026-02-02T00:00:00Z',
      'etag': 'cached-etag',
      'checkedAt': '2026-02-02T00:00:00Z',
      'providers': {
        'openai': _provider('openai', 'OpenAI', ['gpt-4o', 'gpt-4o-mini']),
      },
    });
    await File(
      '${cacheDir.path}/${ModelCatalogService.cacheFileName}',
    ).writeAsString(cached);

    final service = buildService();
    await service.ensureLoaded();

    expect(service.status.source, ModelCatalogLoadSource.cache);
    expect(service.status.modelCount, 2);
    expect(
      service.lookup(endpoint: 'https://api.openai.com/v1', modelName: 'gpt-4o-mini'),
      isNotNull,
    );
  });

  test('损坏的缓存文件回退到内置快照', () async {
    await File(
      '${cacheDir.path}/${ModelCatalogService.cacheFileName}',
    ).writeAsString('{"schemaVersion":1,"providers":"nope"}');

    final service = buildService();
    await service.ensureLoaded();

    expect(service.status.source, ModelCatalogLoadSource.bundled);
    expect(service.hasData, isTrue);
  });

  test('直连 models.dev：裁剪 provider、写缓存、再用 ETag 拿 304', () async {
    final requests = <http.BaseRequest>[];
    final client = MockClient((request) async {
      requests.add(request);
      return http.Response(_modelsDevApiJson(), 200, headers: {
        'etag': 'remote-etag',
        'content-type': 'application/json',
      });
    });
    final service = buildService(remoteClient: client);

    expect(await service.refresh(), isTrue);
    expect(service.status.source, ModelCatalogLoadSource.remote);
    expect(service.providers.map((item) => item.id), ['openai']);
    expect(service.lookup(endpoint: 'https://api.openai.com/v1', modelName: 'gpt-4o')
        ?.maxOutputTokens, 16384);

    final file = File('${cacheDir.path}/${ModelCatalogService.cacheFileName}');
    expect(await file.exists(), isTrue);
    final cached = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    expect(cached['etag'], 'remote-etag');
    expect(
      ((cached['providers'] as Map)['openai'] as Map)['models'],
      isA<Map>(),
    );
    expect(
      jsonEncode(cached).contains('should be trimmed'),
      isFalse,
    );

    // 第二次刷新带 If-None-Match，服务端回 304 时保留原数据。
    final notModified = MockClient((request) async {
      requests.add(request);
      return http.Response('', 304);
    });
    final second = buildService(remoteClient: notModified);
    await second.ensureLoaded();
    expect(await second.refresh(), isTrue);
    expect(requests.last.headers['If-None-Match'], 'remote-etag');
    expect(second.lookup(
      endpoint: 'https://api.openai.com/v1',
      modelName: 'gpt-4o',
    ), isNotNull);
  });

  test('后端代理优先，返回 404 时回退直连', () async {
    final backendRequests = <http.BaseRequest>[];
    final backend = BackendClient(
      client: MockClient((request) async {
        backendRequests.add(request);
        return http.Response(_documentJson(source: 'backend'), 200, headers: {
          'etag': 'backend-etag',
        });
      }),
    )..configure('https://backend.example.com');
    final remoteCalls = <http.BaseRequest>[];
    final remote = MockClient((request) async {
      remoteCalls.add(request);
      return http.Response(_modelsDevApiJson(), 200);
    });
    final service = buildService(backend: backend, remoteClient: remote);

    expect(await service.refresh(), isTrue);
    expect(service.status.source, ModelCatalogLoadSource.backend);
    expect(backendRequests.single.url.path, ModelCatalogService.backendPath);
    expect(remoteCalls, isEmpty);

    // 后端没有该接口时（404）回退到直连 models.dev。
    final missing = BackendClient(
      client: MockClient((request) async => http.Response('', 404)),
    )..configure('https://backend.example.com');
    final fallback = buildService(backend: missing, remoteClient: remote);
    expect(await fallback.refresh(), isTrue);
    expect(fallback.status.source, ModelCatalogLoadSource.remote);
    expect(remoteCalls, isNotEmpty);
  });

  test('刷新失败时保留旧数据并记录错误', () async {
    final failing = MockClient((request) async => http.Response('boom', 500));
    final service = buildService(remoteClient: failing);
    await service.ensureLoaded();
    expect(service.status.source, ModelCatalogLoadSource.bundled);

    expect(await service.refresh(), isTrue);
    expect(service.hasData, isTrue);
    expect(service.status.source, ModelCatalogLoadSource.bundled);
    expect(service.status.error, isNotNull);
  });

  test('清除缓存后回到内置快照', () async {
    final client = MockClient(
      (request) async => http.Response(_modelsDevApiJson(), 200),
    );
    final service = buildService(remoteClient: client);
    await service.refresh();
    expect(
      await File('${cacheDir.path}/${ModelCatalogService.cacheFileName}').exists(),
      isTrue,
    );

    await service.clearCache();
    expect(service.status.source, ModelCatalogLoadSource.bundled);
    expect(
      await File('${cacheDir.path}/${ModelCatalogService.cacheFileName}').exists(),
      isFalse,
    );
  });

  test('hintForEndpoint 只补空缺所需的目录值', () async {
    final service = buildService();
    await service.ensureLoaded();

    final hint = service.hintForEndpoint(
      endpoint: 'https://api.openai.com/v1',
      modelName: 'gpt-4o',
    )!;
    expect(hint.providerId, 'openai');
    expect(hint.contextWindow, 128000);
    expect(hint.maxOutputTokens, 32000);
    expect(hint.supportsThinking, isTrue);
    expect(hint.reasoningEffortValues, ['low', 'medium', 'high']);

    expect(
      service.hintForEndpoint(
        endpoint: 'http://localhost:11434',
        modelName: 'gpt-4o',
      ),
      isNull,
    );
  });

  test('目录建议写进 ModelEntry 后不覆盖手填值', () async {
    final service = buildService();
    await service.ensureLoaded();
    final hint = service.hintForEndpoint(
      endpoint: 'https://api.openai.com/v1',
      modelName: 'gpt-4o',
    )!;

    final manual = ModelConfig(
      id: 'c1',
      name: 'OpenAI',
      endpoint: 'https://api.openai.com/v1',
      apiKey: '',
      modelName: 'gpt-4o',
      apiType: 'openai',
      priority: 0,
      models: [
        ModelEntry(
          name: 'gpt-4o',
          enabled: true,
          contextWindow: 4096,
          maxTokens: 512,
          supportsVision: false,
          catalog: hint,
        ),
      ],
    );
    expect(manual.effectiveContextWindow, 4096);
    expect(manual.effectiveMaxTokens, 512);
    expect(manual.supportsVision, isFalse);
    expect(manual.supportsThinking, isTrue);

    final auto = ModelConfig(
      id: 'c2',
      name: 'OpenAI',
      endpoint: 'https://api.openai.com/v1',
      apiKey: '',
      modelName: 'gpt-4o',
      apiType: 'openai',
      priority: 0,
      models: [ModelEntry(name: 'gpt-4o', enabled: true, catalog: hint)],
    );
    expect(auto.effectiveContextWindow, 128000);
    expect(auto.effectiveMaxTokens, 32000);
    expect(auto.supportsThinking, isTrue);
  });

  test('重复 ensureLoaded 共享同一次加载', () async {
    final service = buildService();
    await Future.wait([service.ensureLoaded(), service.ensureLoaded()]);
    expect(service.hasData, isTrue);
  });
}
