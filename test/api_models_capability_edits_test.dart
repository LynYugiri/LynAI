import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/model_config.dart';
import 'package:lynai/pages/api_models_page.dart';

ModelCatalogHint _hint({
  bool vision = false,
  bool tools = true,
  bool thinking = false,
}) {
  return ModelCatalogHint(
    providerId: 'openai',
    modelId: 'gpt-4o',
    supportsVision: vision,
    supportsTools: tools,
    supportsThinking: thinking,
  );
}

void main() {
  group('resolveCapabilityEdits', () {
    test('没动过的开关不写回手填字段，也不新增覆盖', () {
      final result = resolveCapabilityEdits(
        existingOverrides: const {},
        catalogValues: const {
          'supportsVision': false,
          'supportsTools': true,
          'supportsThinking': false,
        },
        chosen: const {
          'supportsVision': false,
          'supportsTools': true,
          'supportsThinking': false,
        },
        touched: const {},
      );

      // 目录推导出来的值不能写进手填字段，否则会变成「用户显式关闭」。
      expect(result.configured, isEmpty);
      expect(result.overrides, isEmpty);
    });

    test('目录没有数据时用户打开的能力会被固定下来', () {
      final result = resolveCapabilityEdits(
        existingOverrides: const {},
        catalogValues: const {
          'supportsVision': null,
          'supportsTools': null,
          'supportsThinking': null,
        },
        chosen: const {
          'supportsVision': true,
          'supportsTools': true,
          'supportsThinking': true,
        },
        touched: const {'supportsVision'},
      );

      expect(result.configured, {'supportsVision': true});
      expect(result.overrides, {'supportsVision': true});
    });

    test('与目录建议不同的选择固定成覆盖', () {
      final result = resolveCapabilityEdits(
        existingOverrides: const {},
        catalogValues: const {'supportsThinking': false},
        chosen: const {'supportsThinking': true},
        touched: const {'supportsThinking'},
      );

      expect(result.overrides, {'supportsThinking': true});
    });

    test('与目录建议相同的选择不写多余覆盖，并清掉旧覆盖', () {
      final result = resolveCapabilityEdits(
        existingOverrides: const {'supportsTools': false},
        catalogValues: const {'supportsTools': true},
        chosen: const {'supportsTools': true},
        touched: const {'supportsTools'},
      );

      expect(result.overrides, isEmpty);
      expect(result.configured, {'supportsTools': true});
    });

    test('没动过的开关保留原有覆盖，目录刷新不会改回去', () {
      final result = resolveCapabilityEdits(
        existingOverrides: const {'supportsVision': true},
        catalogValues: const {'supportsVision': false},
        chosen: const {'supportsVision': true},
        touched: const {},
      );

      expect(result.overrides, {'supportsVision': true});
      expect(result.configured, isEmpty);
    });
  });

  group('能力生效规则（ModelConfig）', () {
    ModelConfig build({
      ModelCatalogHint? catalog,
      Map<String, bool> overrides = const {},
      bool entryVision = true,
    }) {
      return ModelConfig(
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
            supportsVision: entryVision,
            catalog: catalog,
            capabilityOverrides: overrides,
          ),
        ],
      );
    }

    test('显式覆盖优先于目录建议', () {
      final config = build(
        catalog: _hint(vision: false),
        overrides: const {'supportsVision': true},
      );
      expect(config.supportsVision, isTrue);
    });

    test('目录建议优先于历史默认值 true，但改不动显式关闭', () {
      expect(build(catalog: _hint(vision: false)).supportsVision, isFalse);
      expect(
        build(catalog: _hint(vision: true), entryVision: false).supportsVision,
        isFalse,
      );
      expect(build(catalog: _hint(vision: true)).supportsVision, isTrue);
      // 没有目录数据时保持原语义：默认开启。
      expect(build().supportsVision, isTrue);
    });
  });
}
