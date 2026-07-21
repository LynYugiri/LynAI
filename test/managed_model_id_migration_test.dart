import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/app_settings.dart';
import 'package:lynai/models/chat_role.dart';
import 'package:lynai/models/conversation.dart';
import 'package:lynai/models/message.dart';
import 'package:lynai/models/model_config.dart';
import 'package:lynai/models/roleplay.dart';
import 'package:lynai/models/plugin_config_schema.dart';
import 'package:lynai/providers/model_config_provider.dart';
import 'package:lynai/providers/plugin_provider.dart';
import 'package:lynai/providers/settings_provider.dart';
import 'package:lynai/repositories/plugin_repository.dart';
import 'package:lynai/repositories/settings_repository.dart';
import 'package:lynai/utils/managed_model_id_migration.dart';

import 'support/memory_repositories.dart';

const oldId = '__lynai_relay_provider-1_openai_chat__';
const newId = '__lynai_relay_provider-1_chat__';
const unknownId = 'unknown-model';
const migrations = {oldId: newId};

void main() {
  test(
    'settings migrates only exact model ID fields and is idempotent',
    () async {
      final provider = memorySettingsProvider();
      final settings = AppSettings(
        themeColor: Colors.teal,
        baseThemeColor: Colors.indigo,
        lastChatModelId: oldId,
        speechModelId: oldId,
        imageModelId: oldId,
        imageRecognitionModelId: unknownId,
        imageGenerationModelId: oldId,
        systemPrompt: 'global prompt',
        roles: const [
          ChatRole(
            id: 'role-1',
            name: 'Role',
            systemPrompt: 'role prompt',
            modelId: oldId,
            modelName: 'snapshot-name',
          ),
          ChatRole(
            id: 'role-2',
            name: 'Unknown',
            systemPrompt: 'unknown prompt',
            modelId: unknownId,
            modelName: 'unknown-name',
          ),
        ],
        floatingAssistant: const FloatingAssistantSettings(
          enabled: true,
          translationModelId: oldId,
        ),
      );
      await provider.replaceSettings(settings);
      final expected = settings.toJson();
      expected['lastChatModelId'] = newId;
      expected['speechModelId'] = newId;
      expected['imageModelId'] = newId;
      expected['imageGenerationModelId'] = newId;
      (expected['floatingAssistant']
              as Map<String, dynamic>)['translationModelId'] =
          newId;
      ((expected['roles'] as List)[0] as Map<String, dynamic>)['modelId'] =
          newId;

      expect(await provider.migrateModelIds(migrations), isTrue);
      expect(provider.settings.toJson(), expected);
      final once = provider.settings.toJson();
      expect(await provider.migrateModelIds(migrations), isFalse);
      expect(provider.settings.toJson(), once);
    },
  );

  test(
    'conversation migration preserves all JSON except exact ID fields',
    () async {
      final provider = memoryConversationProvider();
      final now = DateTime.utc(2026, 7, 21, 12, 30);
      final conversation = Conversation(
        id: 'conversation-1',
        title: 'Historical conversation',
        messages: [
          Message(
            id: 'message-1',
            role: 'user',
            content: 'Do not change this history.',
            timestamp: now,
          ),
        ],
        modelId: oldId,
        settings: ConversationSettings(
          modelId: oldId,
          modelName: 'snapshot-name',
          thinking: false,
          systemPrompt: 'snapshot prompt',
          speechModelId: oldId,
          imageModelId: oldId,
          imageRecognitionModelId: unknownId,
          imageGenerationModelId: oldId,
          imageGenerationEnabled: true,
        ),
        roleId: 'role-1',
        createdAt: now,
        updatedAt: now.add(const Duration(minutes: 3)),
      );
      await provider.replaceConversations([conversation]);
      final expected = conversation.toJson();
      expected['modelId'] = newId;
      final expectedSettings = expected['settings'] as Map<String, dynamic>;
      expectedSettings['modelId'] = newId;
      expectedSettings['speechModelId'] = newId;
      expectedSettings['imageModelId'] = newId;
      expectedSettings['imageGenerationModelId'] = newId;

      expect(await provider.migrateModelIds(migrations), isTrue);
      expect(provider.conversations.single.toJson(), expected);
      final once = provider.conversations.single.toJson();
      expect(await provider.migrateModelIds(migrations), isFalse);
      expect(provider.conversations.single.toJson(), once);
    },
  );

  test(
    'roleplay migration preserves scenario and thread snapshot JSON',
    () async {
      final provider = memoryRoleplayProvider();
      final now = DateTime.utc(2026, 7, 21, 13);
      const oldModel = RoleplayModelSelection(
        modelId: oldId,
        modelName: 'snapshot-name',
      );
      const unknownModel = RoleplayModelSelection(
        modelId: unknownId,
        modelName: 'unknown-name',
      );
      const director = RoleplayDirector(
        name: 'Director',
        systemPrompt: 'director prompt',
        model: oldModel,
      );
      const player = RoleplayParticipant(
        id: 'player',
        name: 'Player',
        systemPrompt: 'player prompt',
        model: unknownModel,
        isPlayer: true,
      );
      const character = RoleplayParticipant(
        id: 'character',
        name: 'Character',
        description: 'description',
        systemPrompt: 'character prompt',
        model: oldModel,
      );
      final scenario = RoleplayScenario(
        id: 'scenario-1',
        title: 'Scenario',
        description: 'scenario description',
        scenario: 'scenario snapshot',
        director: director,
        defaultPlayer: player,
        defaultParticipants: const [character],
        pinned: true,
        createdAt: now,
        updatedAt: now.add(const Duration(minutes: 1)),
      );
      final thread = RoleplayThread(
        id: 'thread-1',
        scenarioId: scenario.id,
        title: 'Thread',
        scenarioTitle: scenario.title,
        scenario: 'thread scenario snapshot',
        director: director,
        participants: const [player, character],
        playerParticipantId: player.id,
        messages: [
          RoleplayMessage(
            id: 'roleplay-message-1',
            speakerId: character.id,
            speakerName: character.name,
            content: 'Historical roleplay message.',
            kind: RoleplayMessageKind.character,
            timestamp: now,
          ),
        ],
        createdAt: now,
        updatedAt: now.add(const Duration(minutes: 2)),
      );
      await provider.replaceData(scenarios: [scenario], threads: [thread]);
      final expectedScenario = scenario.toJson();
      _replaceSelectionId(expectedScenario['director'], newId);
      _replaceSelectionId(
        (expectedScenario['defaultParticipants'] as List)[0],
        newId,
      );
      final expectedThread = thread.toJson();
      _replaceSelectionId(expectedThread['director'], newId);
      _replaceSelectionId((expectedThread['participants'] as List)[1], newId);

      expect(await provider.migrateModelIds(migrations), isTrue);
      expect(provider.scenarios.single.toJson(), expectedScenario);
      expect(provider.threads.single.toJson(), expectedThread);
      final onceScenario = provider.scenarios.single.toJson();
      final onceThread = provider.threads.single.toJson();
      expect(await provider.migrateModelIds(migrations), isFalse);
      expect(provider.scenarios.single.toJson(), onceScenario);
      expect(provider.threads.single.toJson(), onceThread);
    },
  );

  test('plugin schema migrates only declared model selections', () {
    final schema = PluginConfigSchema.fromJson({
      'fields': [
        {'key': 'direct', 'type': 'model', 'store': 'id'},
        {'key': 'selection', 'type': 'model', 'store': 'selection'},
        {
          'key': 'nested',
          'type': 'object',
          'fields': [
            {
              'key': 'models',
              'type': 'array',
              'item': {'type': 'model', 'store': 'selection'},
            },
            {'key': 'plain', 'type': 'string'},
          ],
        },
        {'key': 'unrelated', 'type': 'string'},
      ],
    });
    final values = <String, dynamic>{
      'direct': oldId,
      'selection': {'modelId': oldId, 'modelName': 'snapshot-name'},
      'nested': {
        'models': [
          {'modelId': oldId, 'modelName': 'nested-name'},
        ],
        'plain': oldId,
      },
      'unrelated': oldId,
      'undeclared': {'modelId': oldId},
    };

    final migrated = schema.migrateModelIds(values, migrations);

    expect(migrated['direct'], newId);
    expect((migrated['selection'] as Map)['modelId'], newId);
    final nested = migrated['nested'] as Map;
    expect(((nested['models'] as List).single as Map)['modelId'], newId);
    expect(nested['plain'], oldId);
    expect(migrated['unrelated'], oldId);
    expect((migrated['undeclared'] as Map)['modelId'], oldId);
  });

  test('plugin provider persists schema-directed model selections', () async {
    final source = await Directory.systemTemp.createTemp('lynai_model_plugin_');
    final root = await Directory.systemTemp.createTemp(
      'lynai_model_plugin_db_',
    );
    try {
      await File('${source.path}/plugin.json').writeAsString(
        jsonEncode({
          'id': 'model-config-plugin',
          'name': 'Model Config Plugin',
          'entry': 'main.lua',
          'config': {'path': 'config.json', 'schema': 'config.schema.json'},
        }),
      );
      await File('${source.path}/main.lua').writeAsString('return {}');
      await File('${source.path}/config.schema.json').writeAsString(
        jsonEncode({
          'fields': [
            {'key': 'direct', 'type': 'model', 'store': 'id'},
            {'key': 'selection', 'type': 'model'},
            {'key': 'plain', 'type': 'string'},
          ],
        }),
      );
      await File('${source.path}/config.json').writeAsString(
        jsonEncode({
          'direct': oldId,
          'selection': {'modelId': oldId, 'modelName': 'snapshot'},
          'plain': oldId,
        }),
      );
      final provider = PluginProvider(
        repository: PluginRepository(rootOverride: root),
      );
      await provider.importDirectory(source.path);

      expect(await provider.migrateModelIds(migrations), isTrue);

      final reloaded = PluginProvider(
        repository: PluginRepository(rootOverride: root),
      );
      await reloaded.load();
      final config = await reloaded.loadConfig('model-config-plugin');
      expect(config['direct'], newId);
      expect((config['selection'] as Map)['modelId'], newId);
      expect(config['plain'], oldId);
    } finally {
      await source.delete(recursive: true);
      await root.delete(recursive: true);
    }
  });

  test('failed persistence keeps pending migration for retry', () async {
    final modelRepository = MemoryModelConfigRepository();
    final writer = ModelConfigProvider(repository: modelRepository);
    await writer.replaceModels([
      ModelConfig(
        id: oldId,
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
    final models = ModelConfigProvider(repository: modelRepository);
    await models.loadModels();
    final settingsRepository = _RetrySettingsRepository();
    final settings = SettingsProvider(repository: settingsRepository);
    await settings.replaceSettings(
      AppSettings.defaults().copyWith(lastChatModelId: oldId),
    );
    settingsRepository.remainingFailures = 1;
    final conversations = memoryConversationProvider();
    final roleplay = memoryRoleplayProvider();
    final plugins = PluginProvider();

    await expectLater(
      applyPendingManagedModelIdMigrations(
        models: models,
        settings: settings,
        conversations: conversations,
        roleplay: roleplay,
        plugins: plugins,
      ),
      throwsStateError,
    );
    expect(models.peekManagedModelIdMigrations(), migrations);

    await applyPendingManagedModelIdMigrations(
      models: models,
      settings: settings,
      conversations: conversations,
      roleplay: roleplay,
      plugins: plugins,
    );
    expect(models.peekManagedModelIdMigrations(), isEmpty);
    expect(settingsRepository.savedSettings?.lastChatModelId, newId);
  });
}

void _replaceSelectionId(Object? owner, String modelId) {
  final json = owner as Map<String, dynamic>;
  (json['model'] as Map<String, dynamic>)['modelId'] = modelId;
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
