import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/model_catalog.dart';
import 'package:lynai/models/model_config.dart';
import 'package:lynai/models/reasoning_effort.dart';
import 'package:lynai/services/api_service.dart';
import 'package:lynai/services/backend_client.dart';

/// 起一个本地 loopback 服务，抓取一次非流式请求体并返回固定响应。
///
/// [buildConfig] 在服务绑定之后调用，测试可以用真实端口拼 endpoint。
Future<Map<String, dynamic>> captureBody({
  required ModelConfig Function(String endpoint) buildConfig,
  required Map<String, dynamic> responseBody,
  bool thinking = false,
  String? reasoningEffort,
  BackendClient? backend,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final captured = Completer<Map<String, dynamic>>();
  unawaited(
    server.first.then((request) async {
      final raw = await utf8.decoder.bind(request).join();
      final decoded = jsonDecode(raw);
      captured.complete(
        decoded is Map
            ? decoded.map((key, value) => MapEntry(key.toString(), value))
            : <String, dynamic>{'__not_object__': raw},
      );
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(responseBody));
      await request.response.close();
    }),
  );
  addTearDown(() async {
    await server.close(force: true);
  });

  final api = ApiService(backend: backend);
  await api.sendChatRequest(
    buildConfig('http://127.0.0.1:${server.port}'),
    [
      {'role': 'user', 'content': '你好'},
    ],
    thinking: thinking,
    reasoningEffort: reasoningEffort,
  );
  return captured.future;
}

Map<String, dynamic> openAiResponse() => {
  'choices': [
    {
      'message': {'content': 'ok'},
    },
  ],
};

Map<String, dynamic> anthropicResponse() => {
  'content': [
    {'type': 'text', 'text': 'ok'},
  ],
};

Map<String, dynamic> ollamaResponse() => {
  'message': {'content': 'ok'},
};

ModelCatalogHint hint({
  required String providerId,
  bool reasoning = true,
  List<String> effortValues = const ['low', 'medium', 'high'],
  int? contextWindow = 128000,
  int? maxOutputTokens = 32000,
}) {
  return ModelCatalogHint(
    providerId: providerId,
    modelId: 'test-model',
    contextWindow: contextWindow,
    maxOutputTokens: maxOutputTokens,
    supportsVision: true,
    supportsTools: true,
    supportsThinking: reasoning,
    reasoningOptions: [
      if (effortValues.isNotEmpty)
        ModelCatalogReasoningOption(
          kind: ModelCatalogReasoningKind.effort,
          values: effortValues,
        ),
      const ModelCatalogReasoningOption(
        kind: ModelCatalogReasoningKind.budgetTokens,
        minBudgetTokens: 1024,
      ),
    ],
  );
}

ModelConfig openAiConfig({
  String endpoint = '',
  ModelCatalogHint? catalog,
  Map<String, dynamic> extraParams = const {},
  int? maxTokens,
}) {
  return ModelConfig(
    id: 'openai-1',
    name: 'OpenAI',
    endpoint: endpoint,
    apiKey: 'sk-test',
    modelName: 'gpt-4o',
    apiType: 'openai',
    priority: 0,
    maxTokens: maxTokens,
    extraParams: extraParams,
    models: [
      ModelEntry(name: 'gpt-4o', enabled: true, catalog: catalog),
    ],
  );
}

void main() {
  group('强度换算', () {
    test('阶梯换算与夹取', () {
      expect(
        reasoningBudgetForEffort('minimal', maxTokens: 100000),
        1024,
      );
      expect(reasoningBudgetForEffort('medium', maxTokens: 100000), 8192);
      expect(reasoningBudgetForEffort('max', maxTokens: 100000), 49152);
      // Anthropic 要求预算小于 max_tokens。
      expect(reasoningBudgetForEffort('high', maxTokens: 4096), 4095);
      // 未知强度回退到目录给出的下限。
      expect(
        reasoningBudgetForEffort('unknown', min: 2048, maxTokens: 100000),
        2048,
      );
    });

    test('none 表示关闭思考', () {
      expect(isReasoningEffortDisabled('none'), isTrue);
      expect(isReasoningEffortDisabled('None'), isTrue);
      expect(isReasoningEffortDisabled('low'), isFalse);
      expect(normalizeReasoningEffort(' HIGH '), 'high');
    });

    test('强度只来自对话设置，没有设置就不指定', () {
      final config = ModelConfig(
        id: 'c',
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
            catalog: hint(providerId: 'openai'),
          ),
        ],
      );
      expect(config.resolveReasoningEffort('high'), 'high');
      expect(config.resolveReasoningEffort(null), isNull);
      expect(config.resolveReasoningEffort('  '), isNull);
      expect(config.resolveReasoningEffort('  HIGH '), 'high');

      final noCatalog = ModelConfig(
        id: 'c2',
        name: 'OpenAI',
        endpoint: 'https://api.openai.com/v1',
        apiKey: '',
        modelName: 'gpt-4o',
        apiType: 'openai',
        priority: 0,
        models: [ModelEntry(name: 'gpt-4o', enabled: true)],
      );
      // 没有目录数据时不做白名单校验，原样透传由服务端判断。
      expect(noCatalog.resolveReasoningEffort('whatever'), 'whatever');
      expect(noCatalog.resolveReasoningEffort(null), isNull);

      // 目录认识该模型但只有 toggle（没有任何档位）：残留档位同样不发出去。
      final toggleOnly = ModelConfig(
        id: 'c3',
        name: 'Zhipu',
        endpoint: 'https://open.bigmodel.cn/api/paas/v4',
        apiKey: '',
        modelName: 'glm-4.6',
        apiType: 'openai',
        priority: 0,
        models: [
          ModelEntry(
            name: 'glm-4.6',
            enabled: true,
            catalog: ModelCatalogHint(
              providerId: 'zhipuai',
              modelId: 'glm-4.6',
              supportsThinking: true,
              reasoningOptions: const [
                ModelCatalogReasoningOption(
                  kind: ModelCatalogReasoningKind.toggle,
                ),
              ],
            ),
          ),
        ],
      );
      expect(toggleOnly.resolveReasoningEffort('high'), isNull);
      expect(toggleOnly.resolveReasoningEffort('none'), 'none');
    });

    test('残留的强度不在当前模型支持列表里时落回不指定', () {
      ModelConfig build() => ModelConfig(
        id: 'c',
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
            catalog: hint(
              providerId: 'openai',
              effortValues: const ['low', 'medium'],
            ),
          ),
        ],
      );

      // 对话里的 high 是上一个模型留下的，当前模型只支持 low/medium。
      expect(build().resolveReasoningEffort('high'), isNull);
      expect(build().resolveReasoningEffort('medium'), 'medium');
      // none 是显式关闭思考，不受支持列表限制。
      expect(build().resolveReasoningEffort('none'), 'none');
      expect(build().resolveReasoningEffort('NONE'), 'none');
    });
  });

  group('OpenAI 兼容 wire', () {
    test('强度写进 reasoning_effort，开关仍写 thinking', () async {
      final body = await captureBody(
        buildConfig: (endpoint) => openAiConfig(
          endpoint: endpoint,
          catalog: hint(providerId: 'openai'),
        ),
        responseBody: openAiResponse(),
        thinking: true,
        reasoningEffort: 'medium',
      );

      expect(body['thinking'], {'type': 'enabled'});
      expect(body['reasoning_effort'], 'medium');
      expect(body.containsKey('reasoning'), isFalse);
    });

    test('OpenRouter 用 reasoning.effort', () async {
      final body = await captureBody(
        buildConfig: (endpoint) => openAiConfig(
          endpoint: endpoint,
          catalog: hint(providerId: 'openrouter'),
        ),
        responseBody: openAiResponse(),
        thinking: true,
        reasoningEffort: 'high',
      );

      expect(body['reasoning'], {'effort': 'high'});
      expect(body.containsKey('reasoning_effort'), isFalse);
    });

    test('目录说模型不支持推理时不发思考字段', () async {
      final body = await captureBody(
        buildConfig: (endpoint) => openAiConfig(
          endpoint: endpoint,
          catalog: hint(providerId: 'openai', reasoning: false),
        ),
        responseBody: openAiResponse(),
        thinking: true,
        reasoningEffort: 'high',
      );

      expect(body.containsKey('thinking'), isFalse);
      expect(body.containsKey('reasoning_effort'), isFalse);
    });

    test('用户显式开启的能力覆盖目录的"不支持推理"', () async {
      final body = await captureBody(
        buildConfig: (endpoint) => ModelConfig(
          id: 'openai-1',
          name: 'OpenAI',
          endpoint: endpoint,
          apiKey: 'sk-test',
          modelName: 'gpt-4o',
          apiType: 'openai',
          priority: 0,
          models: [
            ModelEntry(
              name: 'gpt-4o',
              enabled: true,
              catalog: hint(providerId: 'openai', reasoning: false),
              capabilityOverrides: const {'supportsThinking': true},
            ),
          ],
        ),
        responseBody: openAiResponse(),
        thinking: true,
        reasoningEffort: 'low',
      );

      expect(body['thinking'], {'type': 'enabled'});
      expect(body['reasoning_effort'], 'low');
    });

    test('强度为 none 时关闭思考且不发强度', () async {
      final body = await captureBody(
        buildConfig: (endpoint) => openAiConfig(
          endpoint: endpoint,
          catalog: hint(providerId: 'openai'),
        ),
        responseBody: openAiResponse(),
        thinking: true,
        reasoningEffort: 'none',
      );

      expect(body['thinking'], {'type': 'disabled'});
      expect(body.containsKey('reasoning_effort'), isFalse);
    });

    test('当前模型不支持该强度时不发 reasoning_effort', () async {
      final body = await captureBody(
        buildConfig: (endpoint) => openAiConfig(
          endpoint: endpoint,
          catalog: hint(
            providerId: 'openai',
            effortValues: const ['low', 'medium'],
          ),
        ),
        responseBody: openAiResponse(),
        thinking: true,
        reasoningEffort: 'xhigh',
      );

      // 思考开关仍然生效，但不会把服务端没声明支持的强度发出去。
      expect(body['thinking'], {'type': 'enabled'});
      expect(body.containsKey('reasoning_effort'), isFalse);
    });
  });

  group('Anthropic wire', () {
    test('目录给出 effort 的模型用 adaptive + output_config.effort', () async {
      final body = await captureBody(
        buildConfig: (endpoint) => ModelConfig(
          id: 'anthropic-1',
          name: 'Anthropic',
          endpoint: endpoint,
          apiKey: 'sk-ant',
          modelName: 'claude-opus-5',
          apiType: 'anthropic',
          priority: 0,
          maxTokens: 64000,
          models: [
            ModelEntry(
              name: 'claude-opus-5',
              enabled: true,
              catalog: hint(providerId: 'anthropic'),
            ),
          ],
        ),
        responseBody: anthropicResponse(),
        thinking: true,
        reasoningEffort: 'medium',
      );

      // 原生强度：adaptive thinking + output_config.effort，不再换算 token 预算。
      expect(body['thinking'], {'type': 'adaptive'});
      expect(body['output_config'], {'effort': 'medium'});
      expect(body.containsKey('temperature'), isFalse);
    });

    test('默认（不选档位）只发 adaptive，不发 effort', () async {
      final body = await captureBody(
        buildConfig: (endpoint) => ModelConfig(
          id: 'anthropic-1',
          name: 'Anthropic',
          endpoint: endpoint,
          apiKey: 'sk-ant',
          modelName: 'claude-opus-5',
          apiType: 'anthropic',
          priority: 0,
          maxTokens: 64000,
          models: [
            ModelEntry(
              name: 'claude-opus-5',
              enabled: true,
              catalog: hint(providerId: 'anthropic'),
            ),
          ],
        ),
        responseBody: anthropicResponse(),
        thinking: true,
      );

      expect(body['thinking'], {'type': 'adaptive'});
      expect(body.containsKey('output_config'), isFalse);
    });

    test('minimal 归一到 low', () async {
      final body = await captureBody(
        buildConfig: (endpoint) => ModelConfig(
          id: 'anthropic-1',
          name: 'Anthropic',
          endpoint: endpoint,
          apiKey: 'sk-ant',
          modelName: 'claude-opus-5',
          apiType: 'anthropic',
          priority: 0,
          maxTokens: 64000,
          models: [
            ModelEntry(
              name: 'claude-opus-5',
              enabled: true,
              catalog: hint(
                providerId: 'anthropic',
                effortValues: const [
                  'minimal',
                  'low',
                  'medium',
                  'high',
                ],
              ),
            ),
          ],
        ),
        responseBody: anthropicResponse(),
        thinking: true,
        reasoningEffort: 'minimal',
      );

      expect(body['output_config'], {'effort': 'low'});
    });

    test('预算型档位（目录只给 budget_tokens）换算成预算', () async {
      final body = await captureBody(
        buildConfig: (endpoint) => ModelConfig(
          id: 'anthropic-1',
          name: 'Anthropic',
          endpoint: endpoint,
          apiKey: 'sk-ant',
          modelName: 'claude-sonnet-4-5',
          apiType: 'anthropic',
          priority: 0,
          maxTokens: 64000,
          models: [
            ModelEntry(
              name: 'claude-sonnet-4-5',
              enabled: true,
              catalog: hint(
                providerId: 'anthropic',
                effortValues: const [],
              ),
            ),
          ],
        ),
        responseBody: anthropicResponse(),
        thinking: true,
        reasoningEffort: 'high',
      );

      expect(body['thinking'], {'type': 'enabled', 'budget_tokens': 24576});
      expect(body.containsKey('output_config'), isFalse);
    });

    test('extraParams.thinkingBudgetTokens 走预算路径并优先于强度', () async {
      final body = await captureBody(
        buildConfig: (endpoint) => ModelConfig(
          id: 'anthropic-1',
          name: 'Anthropic',
          endpoint: endpoint,
          apiKey: 'sk-ant',
          modelName: 'claude-sonnet-4-5',
          apiType: 'anthropic',
          priority: 0,
          maxTokens: 64000,
          extraParams: const {'thinkingBudgetTokens': 4096},
          models: [
            ModelEntry(
              name: 'claude-sonnet-4-5',
              enabled: true,
              catalog: hint(providerId: 'anthropic'),
            ),
          ],
        ),
        responseBody: anthropicResponse(),
        thinking: true,
        reasoningEffort: 'high',
      );

      expect(body['thinking'], {'type': 'enabled', 'budget_tokens': 4096});
    });

    test('强度为 none 时不发 thinking', () async {
      final body = await captureBody(
        buildConfig: (endpoint) => ModelConfig(
          id: 'anthropic-1',
          name: 'Anthropic',
          endpoint: endpoint,
          apiKey: 'sk-ant',
          modelName: 'claude-sonnet-4-5',
          apiType: 'anthropic',
          priority: 0,
          maxTokens: 64000,
          models: [ModelEntry(name: 'claude-sonnet-4-5', enabled: true)],
        ),
        responseBody: anthropicResponse(),
        thinking: true,
        reasoningEffort: 'none',
      );

      expect(body.containsKey('thinking'), isFalse);
    });
  });

  group('托管 relay wire', () {
    // 托管配置的 endpoint 由 ModelConfigProvider 从后端地址派生，这里照做。
    ModelConfig managedConfig(
      String endpoint, {
      Map<String, dynamic> extraParams = const {},
    }) {
      return ModelConfig(
        id: '__lynai_relay_chat__',
        name: 'LynAI',
        endpoint: '$endpoint/relay',
        apiKey: '',
        modelName: 'gpt-5',
        apiType: '',
        priority: 0,
        managed: true,
        extraParams: extraParams,
        models: [
          ModelEntry(
            name: 'gpt-5',
            enabled: true,
            catalog: hint(providerId: 'openai'),
          ),
        ],
      );
    }

    Future<Map<String, dynamic>> captureManagedBody(
      ModelConfig Function(String endpoint) buildConfig, {
      bool thinking = true,
      String? reasoningEffort,
    }) async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final origin = 'http://127.0.0.1:${server.port}';
      final backend = BackendClient()..configure(origin);
      final captured = Completer<Map<String, dynamic>>();
      unawaited(
        server.first.then((request) async {
          final raw = await utf8.decoder.bind(request).join();
          captured.complete(
            Map<String, dynamic>.from(jsonDecode(raw) as Map),
          );
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({'message': {'content': 'ok'}}));
          await request.response.close();
        }),
      );
      addTearDown(() async {
        backend.dispose();
        await server.close(force: true);
      });

      final api = ApiService(backend: backend);
      await api.sendChatRequest(
        buildConfig(origin),
        [
          {'role': 'user', 'content': '你好'},
        ],
        thinking: thinking,
        reasoningEffort: reasoningEffort,
      );
      return captured.future;
    }

    test('后端广告能力时才发 reasoning.effort', () async {
      final body = await captureManagedBody(
        (endpoint) => managedConfig(
          endpoint,
          extraParams: const {'relayReasoningEffort': true},
        ),
        reasoningEffort: 'medium',
      );
      expect(body['reasoning'], {'enabled': true, 'effort': 'medium'});
    });

    test('没有能力广告时不发 effort（兼容旧后端）', () async {
      final body = await captureManagedBody(
        managedConfig,
        reasoningEffort: 'medium',
      );
      expect(body['reasoning'], {'enabled': true});
    });

    test('显式 budgetTokens 与 effort 互斥，预算优先', () async {
      final body = await captureManagedBody(
        (endpoint) => managedConfig(
          endpoint,
          extraParams: const {
            'relayReasoningEffort': true,
            'thinkingBudgetTokens': 4096,
          },
        ),
        reasoningEffort: 'high',
      );
      expect(body['reasoning'], {'enabled': true, 'budgetTokens': 4096});
    });

    test('强度为 none 时关闭思考', () async {
      final body = await captureManagedBody(
        (endpoint) => managedConfig(
          endpoint,
          extraParams: const {'relayReasoningEffort': true},
        ),
        reasoningEffort: 'none',
      );
      expect(body['reasoning'], {'enabled': false});
    });
  });

  group('Ollama wire', () {
    test('强度映射成 think 档位', () async {
      ModelConfig ollamaConfig(String endpoint) => ModelConfig(
        id: 'ollama-1',
        name: 'Ollama',
        endpoint: endpoint,
        apiKey: '',
        modelName: 'qwen3',
        apiType: 'ollama',
        priority: 0,
        models: [
          ModelEntry(
            name: 'qwen3',
            enabled: true,
            catalog: hint(providerId: 'ollama-cloud'),
          ),
        ],
      );
      final body = await captureBody(
        buildConfig: ollamaConfig,
        responseBody: ollamaResponse(),
        thinking: true,
        reasoningEffort: 'high',
      );

      expect(body['think'], 'high');

      final offBody = await captureBody(
        buildConfig: ollamaConfig,
        responseBody: ollamaResponse(),
        thinking: true,
        reasoningEffort: 'none',
      );
      expect(offBody['think'], false);
    });
  });
}
