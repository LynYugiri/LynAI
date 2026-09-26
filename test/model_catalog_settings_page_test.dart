import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lynai/models/model_catalog.dart';
import 'package:lynai/models/model_config.dart';
import 'package:lynai/pages/model_catalog_settings_page.dart';
import 'package:lynai/providers/model_config_provider.dart';
import 'package:lynai/services/model_catalog_service.dart';
import 'package:lynai/services/outbound_network_policy.dart';
import 'package:provider/provider.dart';

import 'support/memory_repositories.dart';

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

String _catalogDocument({required int contextWindow}) {
  return jsonEncode({
    'schemaVersion': 1,
    'source': 'models.dev',
    'fetchedAt': '2026-01-01T00:00:00Z',
    'providers': {
      'openai': {
        'id': 'openai',
        'name': 'OpenAI',
        'models': {
          'gpt-4o': {
            'id': 'gpt-4o',
            'name': 'GPT-4o',
            'attachment': true,
            'tool_call': true,
            'reasoning': true,
            'reasoning_options': [
              {
                'type': 'effort',
                'values': ['low', 'medium', 'high'],
              },
            ],
            'limit': {'context': contextWindow, 'output': 16384},
          },
        },
      },
    },
  });
}

void main() {
  late Directory cacheDir;

  setUp(() async {
    cacheDir = await Directory.systemTemp.createTemp('lynai_catalog_page_');
  });

  tearDown(() async {
    if (await cacheDir.exists()) await cacheDir.delete(recursive: true);
  });

  testWidgets('展示目录状态与操作入口', (tester) async {
    final remote = MockClient((request) async {
      return http.Response(
        _catalogDocument(contextWindow: 128000),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final service = ModelCatalogService(
      cacheDirectory: cacheDir,
      assetBundle: _FakeBundle(_catalogDocument(contextWindow: 64000)),
      clientFactory: () => remote,
      policy: OutboundNetworkPolicy(
        hostResolver: (host) async => const ['93.184.216.34'],
      ),
      enableRemote: false,
    );
    final models = memoryModelConfigProvider();
    models.addModel(
      ModelConfig(
        id: 'openai-config',
        name: 'OpenAI',
        endpoint: 'https://api.openai.com/v1',
        apiKey: '',
        modelName: 'gpt-4o',
        apiType: 'openai',
        priority: 0,
        models: [ModelEntry(name: 'gpt-4o', enabled: true)],
      ),
    );

    service.debugSeedDocument(
      ModelCatalogDocument.tryParseDocument(
        jsonDecode(_catalogDocument(contextWindow: 64000)),
      )!,
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ModelCatalogService>.value(value: service),
          ChangeNotifierProvider<ModelConfigProvider>.value(value: models),
        ],
        child: const MaterialApp(home: ModelCatalogSettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(service.hasData, isTrue);
    expect(find.text('models.dev 模型信息'), findsOneWidget);
    expect(find.textContaining('来源：内置快照'), findsOneWidget);
    expect(find.textContaining('1 个 provider'), findsOneWidget);
    expect(find.text('立即刷新'), findsOneWidget);
    expect(find.text('为已配置模型补全参数'), findsOneWidget);
    expect(find.text('清除本地目录缓存'), findsOneWidget);
    expect(find.textContaining('不上传 API Key'), findsOneWidget);

    // 补全逻辑只写目录建议，不覆盖用户字段（页面按钮走同一入口）。
    final updated = applyModelCatalogHints(models.models.single, service);
    expect(updated, isNotNull);
    models.updateModel(updated!);
    await tester.pumpAndSettle();

    final entry = models.models.single.models.single;
    expect(entry.catalog?.contextWindow, 64000);
    expect(entry.catalog?.maxOutputTokens, 16384);
    expect(entry.catalog?.reasoningEffortValues, ['low', 'medium', 'high']);
    expect(entry.contextWindow, isNull);
    expect(models.models.single.effectiveContextWindow, 64000);
  });

  testWidgets('没有目录服务时显示不可用而不是崩溃', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: ModelCatalogSettingsPage()),
    );
    await tester.pumpAndSettle();

    expect(find.text('模型目录服务不可用'), findsOneWidget);
  });
}
