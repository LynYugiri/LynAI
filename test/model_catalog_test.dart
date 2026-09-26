import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/model_catalog.dart';
import 'package:lynai/models/model_config.dart';

void main() {
  group('ModelCatalogReasoningOption', () {
    test('解析 toggle / effort / budget_tokens', () {
      expect(
        ModelCatalogReasoningOption.tryParse({'type': 'toggle'})?.kind,
        ModelCatalogReasoningKind.toggle,
      );
      final effort = ModelCatalogReasoningOption.tryParse({
        'type': 'effort',
        'values': ['low', 'medium', 'high'],
      });
      expect(effort?.kind, ModelCatalogReasoningKind.effort);
      expect(effort?.values, ['low', 'medium', 'high']);
      final budget = ModelCatalogReasoningOption.tryParse({
        'type': 'budget_tokens',
        'min': 1024,
      });
      expect(budget?.kind, ModelCatalogReasoningKind.budgetTokens);
      expect(budget?.minBudgetTokens, 1024);
    });

    test('未知 type 与空 effort 取值被跳过', () {
      expect(ModelCatalogReasoningOption.tryParse({'type': 'mystery'}), isNull);
      expect(
        ModelCatalogReasoningOption.tryParse({'type': 'effort', 'values': []}),
        isNull,
      );
      expect(ModelCatalogReasoningOption.tryParse('toggle'), isNull);
    });

    test('序列化保持 models.dev 的键名', () {
      const option = ModelCatalogReasoningOption(
        kind: ModelCatalogReasoningKind.effort,
        values: ['low', 'high'],
      );
      expect(option.toJson(), {
        'type': 'effort',
        'values': ['low', 'high'],
      });
    });
  });

  group('ModelCatalogDocument', () {
    final apiJson = {
      'openai': {
        'id': 'openai',
        'name': 'OpenAI',
        'env': ['OPENAI_API_KEY'],
        'npm': '@ai-sdk/openai',
        'doc': 'https://platform.openai.com',
        'models': {
          'gpt-5': {
            'id': 'gpt-5',
            'name': 'GPT-5',
            'description': '旗舰模型',
            'family': 'gpt',
            'attachment': true,
            'reasoning': true,
            'reasoning_options': [
              {
                'type': 'effort',
                'values': ['minimal', 'low', 'medium', 'high'],
              },
            ],
            'tool_call': true,
            'structured_output': true,
            'temperature': false,
            'modalities': {
              'input': ['text', 'image'],
              'output': ['text'],
            },
            'limit': {'context': 400000, 'output': 128000},
            'cost': {'input': 1.25, 'output': 10},
            'release_date': '2025-08-07',
            'last_updated': '2025-08-07',
          },
          'o4-mini': {
            'id': 'o4-mini',
            'name': 'o4-mini',
            'attachment': false,
            'reasoning': true,
            'tool_call': true,
            'modalities': {
              'input': ['text'],
              'output': ['text'],
            },
            'limit': {'context': 200000, 'output': 100000},
          },
        },
      },
      'unused-provider': {
        'id': 'unused-provider',
        'name': 'Unused',
        'models': {
          'x': {'id': 'x', 'name': 'X'},
        },
      },
    };

    test('从 models.dev api.json 解析并裁剪 provider', () {
      final document = ModelCatalogDocument.tryParseModelsDevApi(
        apiJson,
        providerFilter: {'openai'},
      )!;
      expect(document.providers.keys, ['openai']);
      final model = document.providers['openai']!.models['gpt-5']!;
      expect(model.contextWindow, 400000);
      expect(model.maxOutputTokens, 128000);
      expect(model.supportsVision, isTrue);
      expect(model.toolCall, isTrue);
      expect(model.reasoning, isTrue);
      expect(model.reasoningEffortValues, [
        'minimal',
        'low',
        'medium',
        'high',
      ]);
      expect(model.temperature, isFalse);
      expect(model.updatedAt, DateTime.utc(2025, 8, 7));
    });

    test('裁剪掉的字段不会写回文档', () {
      final document = ModelCatalogDocument.tryParseModelsDevApi(apiJson)!;
      final encoded = jsonDecode(document.encode()) as Map<String, dynamic>;
      final provider =
          (encoded['providers'] as Map)['openai'] as Map<String, dynamic>;
      expect(provider.containsKey('env'), isFalse);
      expect(provider.containsKey('npm'), isFalse);
      final model =
          (provider['models'] as Map)['gpt-5'] as Map<String, dynamic>;
      expect(model.containsKey('description'), isFalse);
      expect(model.containsKey('cost'), isFalse);
      expect(model.containsKey('family'), isFalse);
      expect(model['limit'], {'context': 400000, 'output': 128000});
    });

    test('解析本地缓存/快照文档并忽略未知字段', () {
      final document = ModelCatalogDocument.tryParseDocument({
        'schemaVersion': 1,
        'source': 'models.dev',
        'fetchedAt': '2026-01-02T03:04:05Z',
        'etag': 'abc',
        'checkedAt': '2026-01-02T03:04:05Z',
        'providers': apiJson,
      })!;
      expect(document.providers.length, 2);
      expect(document.fetchedAt, DateTime.utc(2026, 1, 2, 3, 4, 5));
    });

    test('结构不可识别或版本过新时返回 null', () {
      expect(ModelCatalogDocument.tryParseDocument('nope'), isNull);
      expect(ModelCatalogDocument.tryParseDocument({}), isNull);
      expect(
        ModelCatalogDocument.tryParseDocument({
          'schemaVersion': modelCatalogSchemaVersion + 1,
          'providers': apiJson,
        }),
        isNull,
      );
    });

    test('单条损坏记录被跳过而不影响整份文档', () {
      final document = ModelCatalogDocument.tryParseModelsDevApi({
        'openai': {
          'id': 'openai',
          'name': 'OpenAI',
          'models': {
            'broken': 'not-a-map',
            'empty': {'name': 'no-id'},
            'gpt-5': {'id': 'gpt-5', 'name': 'GPT-5'},
          },
        },
        'junk': 'not-a-map',
      })!;
      expect(
        document.providers['openai']!.models.keys,
        ['empty', 'gpt-5'],
      );
      expect(
        document.providers['openai']!.models['empty']!.name,
        'no-id',
      );
    });

    test('provider 的 api 字段缺失时省略而不是写 null', () {
      final document = ModelCatalogDocument.tryParseModelsDevApi(apiJson)!;
      final encoded = jsonDecode(document.encode()) as Map<String, dynamic>;
      final provider = (encoded['providers'] as Map)['openai'] as Map;
      expect(provider.containsKey('api'), isFalse);
    });
  });

  group('ModelCatalogIndex 匹配', () {
    ModelCatalogDocument document() => ModelCatalogDocument.tryParseDocument({
      'schemaVersion': 1,
      'providers': {
        'openai': {
          'id': 'openai',
          'name': 'OpenAI',
          'models': {
            'gpt-4o': {'id': 'gpt-4o', 'name': 'GPT-4o'},
            'claude-3-5-sonnet-20241022': {
              'id': 'claude-3-5-sonnet-20241022',
              'name': 'Claude 3.5 Sonnet (20241022)',
            },
          },
        },
        'openrouter': {
          'id': 'openrouter',
          'name': 'OpenRouter',
          'models': {
            'anthropic/claude-sonnet-4.5': {
              'id': 'anthropic/claude-sonnet-4.5',
              'name': 'Claude Sonnet 4.5',
            },
          },
        },
        'deepseek': {
          'id': 'deepseek',
          'name': 'DeepSeek',
          'models': {
            'deepseek-chat': {'id': 'deepseek-chat', 'name': 'DeepSeek Chat'},
            'deepseek-v3-20240101': {
              'id': 'deepseek-v3-20240101',
              'name': 'DeepSeek V3 (20240101)',
            },
            'deepseek-v3-20250101': {
              'id': 'deepseek-v3-20250101',
              'name': 'DeepSeek V3 (20250101)',
            },
          },
        },
      },
    })!;

    test('精确命中优先', () {
      final index = ModelCatalogIndex(document());
      final match = index.match(providerId: 'openai', modelName: 'gpt-4o')!;
      expect(match.exact, isTrue);
      expect(match.model.id, 'gpt-4o');
    });

    test('用户模型名不带日期时命中带日期的目录记录', () {
      final index = ModelCatalogIndex(document());
      final match = index.match(
        providerId: 'openai',
        modelName: 'claude-3-5-sonnet',
      )!;
      expect(match.model.id, 'claude-3-5-sonnet-20241022');
      expect(match.exact, isFalse);
    });

    test('去 vendor 前缀匹配聚合 provider 的模型', () {
      final index = ModelCatalogIndex(document());
      final match = index.match(
        providerId: 'openrouter',
        modelName: 'claude-sonnet-4.5',
      )!;
      expect(match.model.id, 'anthropic/claude-sonnet-4.5');
    });

    test('归一化后仍有多个候选时不做猜测', () {
      final index = ModelCatalogIndex(document());
      expect(index.match(providerId: 'deepseek', modelName: 'deepseek-v3'), isNull);
      expect(
        index
            .candidates(providerId: 'deepseek', modelName: 'deepseek-v3')
            .map((model) => model.id),
        containsAll(['deepseek-v3-20240101', 'deepseek-v3-20250101']),
      );
    });

    test('provider 不存在时返回 null', () {
      final index = ModelCatalogIndex(document());
      expect(index.match(providerId: 'nope', modelName: 'gpt-4o'), isNull);
    });
  });

  group('ModelCatalogProviderResolver', () {
    const resolver = ModelCatalogProviderResolver();
    final document = ModelCatalogDocument.tryParseDocument({
      'schemaVersion': 1,
      'providers': {
        'openai': {
          'id': 'openai',
          'name': 'OpenAI',
          'models': {
            'gpt-4o': {'id': 'gpt-4o', 'name': 'GPT-4o'},
          },
        },
        'some-vendor': {
          'id': 'some-vendor',
          'name': 'Some Vendor',
          'api': 'https://api.some-vendor.example/v1',
          'models': {
            'vendor-model': {'id': 'vendor-model', 'name': 'Vendor Model'},
          },
        },
      },
    })!;

    test('已知 endpoint host 映射', () {
      expect(
        resolver.resolve(endpoint: 'https://api.openai.com/v1'),
        'openai',
      );
      expect(
        resolver.resolve(endpoint: 'https://api.deepseek.com/v1'),
        'deepseek',
      );
    });

    test('子域回退匹配', () {
      expect(
        resolver.resolve(endpoint: 'https://api.moonshot.cn/v1'),
        'moonshotai-cn',
      );
    });

    test('目录里的 api host 参与匹配', () {
      expect(
        resolver.resolve(
          endpoint: 'https://api.some-vendor.example/v1',
          document: document,
        ),
        'some-vendor',
      );
    });

    test('本地/未知 endpoint 不猜 provider', () {
      expect(resolver.resolve(endpoint: 'http://localhost:11434'), isNull);
      expect(
        resolver.resolve(endpoint: 'https://unknown.example/v1'),
        isNull,
      );
    });

    test('显式指定优先，且必须在目录里存在', () {
      expect(
        resolver.resolve(
          explicitProviderId: 'some-vendor',
          endpoint: 'https://api.openai.com/v1',
          document: document,
        ),
        'some-vendor',
      );
      expect(
        resolver.resolve(
          explicitProviderId: 'missing',
          endpoint: 'https://api.openai.com/v1',
          document: document,
        ),
        isNull,
      );
    });
  });

  group('ModelCatalogHint', () {
    test('从目录记录构造并保留强度选项', () {
      final document = ModelCatalogDocument.tryParseModelsDevApi({
        'anthropic': {
          'id': 'anthropic',
          'name': 'Anthropic',
          'models': {
            'claude-sonnet-4-5': {
              'id': 'claude-sonnet-4-5',
              'name': 'Claude Sonnet 4.5',
              'attachment': true,
              'tool_call': true,
              'reasoning': true,
              'reasoning_options': [
                {'type': 'budget_tokens', 'min': 1024},
                {
                  'type': 'effort',
                  'values': ['low', 'medium', 'high'],
                },
              ],
              'limit': {'context': 200000, 'output': 64000},
            },
          },
        },
      })!;
      final model = document.providers['anthropic']!.models.values.first;
      final hint = ModelCatalogHint.fromModel(
        model,
        providerId: 'anthropic',
        fetchedAt: DateTime.utc(2026, 1, 1),
      );
      expect(hint.contextWindow, 200000);
      expect(hint.maxOutputTokens, 64000);
      expect(hint.supportsVision, isTrue);
      expect(hint.supportsTools, isTrue);
      expect(hint.supportsThinking, isTrue);
      expect(hint.reasoningEffortValues, ['low', 'medium', 'high']);
      expect(hint.supportsThinkingBudget, isTrue);

      final decoded = ModelCatalogHint.fromJson(
        jsonDecode(jsonEncode(hint.toJson())) as Map<String, dynamic>,
      );
      expect(decoded.contextWindow, 200000);
      expect(decoded.reasoningEffortValues, ['low', 'medium', 'high']);
      expect(decoded.supportsThinkingBudget, isTrue);
      expect(decoded.fetchedAt, DateTime.utc(2026, 1, 1));
    });
  });
}
