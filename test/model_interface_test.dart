import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lynai/models/model_config.dart';
import 'package:lynai/providers/model_config_provider.dart';
import 'package:lynai/services/lynai_call_identity.dart';
import 'package:lynai/services/lynai_function_service.dart';

import 'support/memory_repositories.dart';

void main() {
  Future<Map<String, dynamic>> call(
    ModelConfigProvider models,
    String method,
    Map<String, dynamic> args,
  ) {
    return LynAIFunctionService().execute(
      LynAIFunctionCall(name: method, arguments: args),
      LynAIFunctionContext(
        identity: const LynAICallIdentity(type: LynAICallerType.system),
        modelConfigs: models,
      ),
    );
  }

  test('model.list returns provider+model identity', () async {
    SharedPreferences.setMockInitialValues({});
    final models = memoryModelConfigProvider();
    await models.replaceModels([
      ModelConfig(
        id: 'provider-a',
        name: 'Provider A',
        category: ModelConfig.categoryChat,
        endpoint: 'https://example.test',
        apiKey: '',
        modelName: 'gpt-4o',
        apiType: 'openai',
        priority: 0,
      ),
    ]);
    final result = await call(models, 'model.list', {});
    expect(result['ok'], isTrue);
    final list = (result['models'] as List).cast<Map>();
    expect(list, hasLength(1));
    expect(list.first['provider'], 'provider-a');
    expect(list.first['model'], 'gpt-4o');
  });

  test('model.current returns chat model with provider+model', () async {
    SharedPreferences.setMockInitialValues({});
    final models = memoryModelConfigProvider();
    await models.replaceModels([
      ModelConfig(
        id: 'provider-a',
        name: 'Provider A',
        category: ModelConfig.categoryChat,
        endpoint: 'https://example.test',
        apiKey: '',
        modelName: 'gpt-4o',
        apiType: 'openai',
        priority: 0,
      ),
    ]);
    final result = await call(models, 'model.current', {});
    expect(result['ok'], isTrue);
    expect(result['provider'], 'provider-a');
    expect(result['model'], 'gpt-4o');
  });
}
