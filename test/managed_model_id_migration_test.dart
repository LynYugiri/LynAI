import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/app_settings.dart';
import 'package:lynai/models/chat_role.dart';
import 'package:lynai/models/conversation.dart';
import 'package:lynai/models/model_config.dart';
import 'package:lynai/models/plugin_config_schema.dart';
import 'package:lynai/models/roleplay.dart';
import 'package:lynai/providers/model_config_provider.dart';
import 'package:lynai/providers/plugin_provider.dart';
import 'package:lynai/providers/settings_provider.dart';
import 'package:lynai/repositories/settings_repository.dart';
import 'package:lynai/utils/managed_model_id_migration.dart';

import 'support/memory_repositories.dart';

const oldId = '__lynai_relay_provider-1_openai_chat__';
const secondOldId = '__lynai_relay_provider-2_chat__';
const newId = '__lynai_relay_chat__';
const unknownId = 'unknown-model';
const migrations = {oldId: newId};

void main() {
  test('settings migrates only exact model ID fields', () async {
    final provider = memorySettingsProvider();
    await provider.replaceSettings(
      AppSettings(
        themeColor: Colors.teal,
        baseThemeColor: Colors.indigo,
        lastChatModelId: oldId,
        speechModelId: oldId,
        imageModelId: oldId,
        imageRecognitionModelId: unknownId,
        imageGenerationModelId: oldId,
        roles: const [
          ChatRole(
            id: 'role-1',
            name: 'Role',
            systemPrompt: 'prompt',
            modelId: oldId,
            modelName: 'snapshot',
          ),
        ],
        floatingAssistant: const FloatingAssistantSettings(
          translationModelId: oldId,
        ),
      ),
    );

    expect(await provider.migrateModelIds(migrations), isTrue);
    expect(provider.settings.lastChatModelId, newId);
    expect(provider.settings.speechModelId, newId);
    expect(provider.settings.imageModelId, newId);
    expect(provider.settings.imageRecognitionModelId, unknownId);
    expect(provider.settings.imageGenerationModelId, newId);
    expect(provider.settings.roles.single.modelId, newId);
    expect(provider.settings.roles.single.modelName, 'snapshot');
    expect(provider.settings.floatingAssistant.translationModelId, newId);
  });

  test('conversation and roleplay migrate exact snapshot IDs', () async {
    final conversations = memoryConversationProvider();
    final now = DateTime.utc(2026, 7, 21);
    await conversations.replaceConversations([
      Conversation(
        id: 'conversation-1',
        title: 'History',
        messages: const [],
        modelId: oldId,
        settings: ConversationSettings(
          modelId: oldId,
          modelName: 'snapshot',
          speechModelId: oldId,
          imageRecognitionModelId: unknownId,
        ),
        roleId: 'role-1',
        createdAt: now,
        updatedAt: now,
      ),
    ]);
    final roleplay = memoryRoleplayProvider();
    const oldSelection = RoleplayModelSelection(
      modelId: oldId,
      modelName: 'snapshot',
    );
    const unknownSelection = RoleplayModelSelection(
      modelId: unknownId,
      modelName: 'unknown',
    );
    final scenario = RoleplayScenario(
      id: 'scenario-1',
      title: 'Scenario',
      description: '',
      scenario: '',
      director: const RoleplayDirector(name: 'Director', model: oldSelection),
      defaultPlayer: const RoleplayParticipant(
        id: 'player',
        name: 'Player',
        systemPrompt: '',
        model: unknownSelection,
        isPlayer: true,
      ),
      defaultParticipants: const [
        RoleplayParticipant(
          id: 'character',
          name: 'Character',
          systemPrompt: '',
          model: oldSelection,
        ),
      ],
      createdAt: now,
      updatedAt: now,
    );
    final thread = RoleplayThread(
      id: 'thread-1',
      scenarioId: scenario.id,
      title: 'Thread',
      scenarioTitle: scenario.title,
      scenario: '',
      director: scenario.director,
      participants: const [
        RoleplayParticipant(
          id: 'character',
          name: 'Character',
          systemPrompt: '',
          model: oldSelection,
        ),
      ],
      playerParticipantId: 'player',
      messages: const [],
      createdAt: now,
      updatedAt: now,
    );
    await roleplay.replaceData(scenarios: [scenario], threads: [thread]);

    expect(await conversations.migrateModelIds(migrations), isTrue);
    expect(await roleplay.migrateModelIds(migrations), isTrue);
    final conversation = conversations.conversations.single;
    expect(conversation.modelId, newId);
    expect(conversation.settings.modelId, newId);
    expect(conversation.settings.speechModelId, newId);
    expect(conversation.settings.imageRecognitionModelId, unknownId);
    expect(roleplay.scenarios.single.director.model.modelId, newId);
    expect(
      roleplay.scenarios.single.defaultParticipants.single.model.modelId,
      newId,
    );
    expect(roleplay.scenarios.single.defaultPlayer.model.modelId, unknownId);
    expect(roleplay.threads.single.director.model.modelId, newId);
  });

  test('plugin schema migrates only declared model selections', () {
    final schema = PluginConfigSchema.fromJson({
      'fields': [
        {'key': 'direct', 'type': 'model', 'store': 'id'},
        {'key': 'selection', 'type': 'model', 'store': 'selection'},
        {'key': 'plain', 'type': 'string'},
      ],
    });
    final migrated = schema.migrateModelIds({
      'direct': oldId,
      'selection': {'modelId': oldId, 'modelName': 'snapshot'},
      'plain': oldId,
      'undeclared': {'modelId': oldId},
    }, migrations);

    expect(migrated['direct'], newId);
    expect((migrated['selection'] as Map)['modelId'], newId);
    expect(migrated['plain'], oldId);
    expect((migrated['undeclared'] as Map)['modelId'], oldId);
  });

  test(
    'offline imported configs normalize before references migrate',
    () async {
      final repository = MemoryModelConfigRepository();
      final models = ModelConfigProvider(repository: repository);
      await models.replaceModels([
        _legacyModel(oldId, 'model-a', priority: 1),
        _legacyModel(secondOldId, 'model-b', priority: 0),
      ]);
      final settings = memorySettingsProvider();
      await settings.replaceSettings(
        AppSettings.defaults().copyWith(lastChatModelId: oldId),
      );

      await applyPendingManagedModelIdMigrations(
        models: models,
        settings: settings,
        conversations: memoryConversationProvider(),
        roleplay: memoryRoleplayProvider(),
        plugins: PluginProvider(),
      );

      expect(models.models.single.id, newId);
      expect(models.models.single.models.map((entry) => entry.name), [
        'model-b',
        'model-a',
      ]);
      expect(settings.settings.lastChatModelId, newId);
      expect(models.peekManagedModelIdMigrations(), isEmpty);
    },
  );

  test('failed persistence keeps pending migration for retry', () async {
    final repository = MemoryModelConfigRepository();
    final models = ModelConfigProvider(repository: repository);
    await models.replaceModels([_legacyModel(oldId, 'model-a')]);
    final settingsRepository = _RetrySettingsRepository();
    final settings = SettingsProvider(repository: settingsRepository);
    await settings.replaceSettings(
      AppSettings.defaults().copyWith(lastChatModelId: oldId),
    );
    settingsRepository.remainingFailures = 1;
    final arguments = (
      conversations: memoryConversationProvider(),
      roleplay: memoryRoleplayProvider(),
      plugins: PluginProvider(),
    );

    await expectLater(
      applyPendingManagedModelIdMigrations(
        models: models,
        settings: settings,
        conversations: arguments.conversations,
        roleplay: arguments.roleplay,
        plugins: arguments.plugins,
      ),
      throwsStateError,
    );
    expect(models.peekManagedModelIdMigrations(), migrations);

    await applyPendingManagedModelIdMigrations(
      models: models,
      settings: settings,
      conversations: arguments.conversations,
      roleplay: arguments.roleplay,
      plugins: arguments.plugins,
    );
    expect(models.peekManagedModelIdMigrations(), isEmpty);
    expect(settingsRepository.savedSettings?.lastChatModelId, newId);
  });
}

ModelConfig _legacyModel(String id, String modelName, {int priority = 0}) {
  return ModelConfig(
    id: id,
    name: 'Legacy',
    endpoint: 'https://api.example.com/relay',
    apiKey: '',
    modelName: modelName,
    apiType: '',
    priority: priority,
    managed: true,
  );
}

class _RetrySettingsRepository implements SettingsRepository {
  AppSettings? savedSettings;
  int remainingFailures = 0;

  @override
  Future<SettingsLoadResult> load(AppSettings fallback) async {
    return SettingsLoadResult(
      settings: savedSettings ?? fallback,
      usingStorageV2: false,
    );
  }

  @override
  Future<void> save(
    AppSettings settings, {
    required bool usingStorageV2,
  }) async {
    if (remainingFailures > 0) {
      remainingFailures--;
      throw StateError('injected settings save failure');
    }
    savedSettings = settings;
  }
}
