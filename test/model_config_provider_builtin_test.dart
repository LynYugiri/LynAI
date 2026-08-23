import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/model_config.dart';
import 'package:lynai/providers/model_config_provider.dart';
import 'package:lynai/services/on_device_llm_service.dart';

import 'support/fake_on_device_llm_backend.dart';
import 'support/memory_repositories.dart';

void main() {
  ModelConfig cloudModel() => ModelConfig(
    id: 'cloud-1',
    name: 'Cloud',
    endpoint: 'https://example.com/v1',
    apiKey: '',
    modelName: 'cloud-1',
    apiType: 'openai',
    priority: 0,
  );

  test('injects built-in local BlueLM only when status is visible', () async {
    final backend = FakeOnDeviceLlmBackend(
      status: FakeOnDeviceLlmBackend.statusWith('model_not_found'),
    );
    final service = OnDeviceLlmService(backend: backend);
    final provider = ModelConfigProvider(
      repository: MemoryModelConfigRepository(),
      onDeviceLlm: service,
    );

    expect(provider.models, isEmpty);

    backend.status = FakeOnDeviceLlmBackend.validatedStatus;
    await service.refreshStatus();

    expect(provider.models.single.id, ModelConfig.localBlueLmId);
    expect(provider.models.single.apiType, ModelConfig.localBlueLmApiType);
    expect(
      provider.enabledModelsByCategory(ModelConfig.categoryChat),
      hasLength(1),
    );

    backend.status = FakeOnDeviceLlmBackend.statusWith('invalid_model');
    await service.refreshStatus();
    expect(provider.models, isEmpty);

    service.dispose();
    provider.dispose();
  });

  test('built-in local model is never persisted by the repository', () async {
    final repository = MemoryModelConfigRepository()..seed([cloudModel()]);
    final backend = FakeOnDeviceLlmBackend(
      status: FakeOnDeviceLlmBackend.validatedStatus,
    );
    final service = OnDeviceLlmService(backend: backend);
    await service.refreshStatus();
    final provider = ModelConfigProvider(
      repository: repository,
      onDeviceLlm: service,
    );

    await provider.loadModels();
    expect(
      provider.models.map((model) => model.id),
      containsAll([ModelConfig.localBlueLmId, 'cloud-1']),
    );
    await provider.flushPendingSaves();

    final reloaded = ModelConfigProvider(repository: repository);
    await reloaded.loadModels();
    expect(reloaded.models.map((model) => model.id), ['cloud-1']);

    service.dispose();
    provider.dispose();
    reloaded.dispose();
  });

  test('local model capabilities disable tools, thinking and vision', () {
    final local = ModelConfig.localBlueLm();

    expect(local.supportsTools, isFalse);
    expect(local.supportsThinking, isFalse);
    expect(local.supportsVision, isFalse);
    expect(local.supportsNativeTools, isFalse);
    expect(local.effectiveMaxTokens, 200);
    expect(local.effectiveContextWindow, 4096);
    expect(local.effectiveTemperature, 0.0);
    expect(local.effectiveTopP, 1.0);
  });
}
