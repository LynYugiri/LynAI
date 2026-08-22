import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/agent_runtime.dart';
import 'package:lynai/models/agent_trace.dart';
import 'package:lynai/models/agent_user_interaction.dart';
import 'package:lynai/models/app_settings.dart';
import 'package:lynai/models/conversation.dart';
import 'package:lynai/models/knowledge_base.dart';
import 'package:lynai/models/knowledge_category.dart';
import 'package:lynai/models/knowledge_entry.dart';
import 'package:lynai/models/knowledge_explanation.dart';
import 'package:lynai/models/knowledge_source.dart';
import 'package:lynai/models/message.dart';
import 'package:lynai/models/model_config.dart';
import 'package:lynai/models/plugin.dart';
import 'package:lynai/providers/conversation_provider.dart';
import 'package:lynai/providers/calendar_provider.dart';
import 'package:lynai/providers/feature_provider.dart';
import 'package:lynai/providers/knowledge_provider.dart';
import 'package:lynai/providers/model_config_provider.dart';
import 'package:lynai/providers/plugin_provider.dart';
import 'package:lynai/providers/settings_provider.dart';
import 'package:lynai/providers/task_provider.dart';
import 'package:lynai/repositories/knowledge_repository.dart';
import 'package:lynai/repositories/plugin_repository.dart';
import 'package:lynai/services/device_control_service.dart';
import 'package:lynai/services/agent_cancellation.dart';
import 'package:lynai/services/agent_loop_runtime.dart';
import 'package:lynai/services/agent_protocol_codec.dart';
import 'package:lynai/services/agent_tool_registry.dart';
import 'package:lynai/services/agent_user_interaction_broker.dart';
import 'package:lynai/services/bounded_outbound_http_client.dart';
import 'package:lynai/services/floating_chat_session_controller.dart';
import 'package:lynai/services/lynai_call_identity.dart';
import 'package:lynai/services/lynai_function_service.dart';
import 'package:lynai/services/lynai_permission_definitions.dart';
import 'package:lynai/services/lynai_permission_service.dart';
import 'package:lynai/services/outbound_network_policy.dart';
import 'package:lynai/services/plugin_scaffold_service.dart';
import 'package:lynai/services/storage_v2_service.dart';
import 'package:lynai/services/storage_v2_upgrade_service.dart';
import 'package:lynai/services/tool_call_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_path_provider.dart';
import 'support/memory_repositories.dart';

const _tinyPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';

class _RealHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.connectionTimeout = const Duration(seconds: 5);
    return client;
  }
}

class _FakeDeviceBackend implements DeviceControlBackend {
  @override
  Future<Map<String, dynamic>> execute(
    String name,
    Map<String, dynamic> args,
  ) async {
    return {
      'ok': true,
      'result': {'text': '当前页面文本', 'packageName': 'com.example'},
    };
  }
}

Future<StorageV2Service> _readyStorageV2(Directory root) async {
  final storage = StorageV2Service(rootDirectory: root);
  await StorageV2UpgradeService(storageV2: storage).ensureReady();
  return storage;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Directory? pathProviderRoot;

  setUp(() async {
    pathProviderRoot = await installFakePathProvider(
      'lynai_tool_path_provider_test_',
      temporaryDirectoryName: 'temp',
    );
  });

  tearDown(() async {
    final root = pathProviderRoot;
    pathProviderRoot = null;
    await deleteFakePathProviderRoot(root);
  });

  test(
    'list_notes requires query before returning full note contents',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'lynai_tool_list_notes_test_',
      );
      try {
        final storage = await _readyStorageV2(root);
        final features = FeatureProvider(storageV2: storage);
        await features.load();
        await features.addNoteWithContent('secret', 'private body');
        final service = ToolCallService(
          features,
          agentIdentity: const LynAICallIdentity(type: LynAICallerType.system),
        );

        final blocked = await service.execute(
          const ChatToolCall(
            id: 'list-all-content',
            name: 'list_notes',
            arguments: {'includeContent': true},
          ),
          const [],
        );
        final allowed = await service.execute(
          const ChatToolCall(
            id: 'list-filtered-content',
            name: 'list_notes',
            arguments: {'query': 'secret', 'includeContent': true},
          ),
          const [],
        );

        expect(blocked['ok'], isFalse);
        expect(allowed['ok'], isTrue);
        expect(allowed['notes'], hasLength(1));
        expect(allowed['notes'].single['content'], 'private body');
      } finally {
        await root.delete(recursive: true);
      }
    },
  );

  test('save_note_page moves note pages', () async {
    final root = await Directory.systemTemp.createTemp(
      'lynai_tool_page_move_test_',
    );
    try {
      final storage = await _readyStorageV2(root);
      final features = FeatureProvider(storageV2: storage);
      await features.load();
      final noteId = await features.addNoteWithContent('note', 'body');
      final service = ToolCallService(
        features,
        agentIdentity: const LynAICallIdentity(type: LynAICallerType.system),
      );
      final secondPage = await features.addNotePage(noteId, 'second');
      expect(secondPage, isNotNull);
      final initialPageIds = features
          .notePages(noteId)
          .map((page) => page.id)
          .toList();
      expect(initialPageIds, hasLength(2));
      expect(initialPageIds.first, isNot(secondPage));
      expect(initialPageIds.last, secondPage);

      final result = await service.execute(
        ChatToolCall(
          id: 'move-page',
          name: 'save_note_page',
          arguments: {'id': noteId, 'pageId': secondPage, 'move': 'up'},
        ),
        const [],
      );

      expect(result['ok'], isTrue);
      final movedPageIds = (result['pages'] as List)
          .map((page) => page['id'] as String)
          .toList();
      expect(movedPageIds, hasLength(2));
      expect(movedPageIds.first, secondPage);
      expect(movedPageIds.last, isNot(secondPage));
    } finally {
      await root.delete(recursive: true);
    }
  });

  test(
    'Agent tools expose notes and plugin calls according to permissions',
    () {
      final baseTools = ToolCallService.openAITools(const [], true, const []);
      final baseNames = baseTools
          .map((tool) => tool['function']?['name'])
          .whereType<String>()
          .toSet();

      expect(baseNames, contains('add_agent_note'));
      expect(baseNames, contains('create_plan'));
      expect(baseNames, contains('update_plan'));
      expect(baseNames, contains('read_agent_memory'));
      expect(baseNames, contains('update_agent_memory'));
      expect(baseNames, contains('list_plugin_functions'));
      expect(baseNames, contains('list_plugin_skills'));
      expect(baseNames, contains('load_plugin_skill'));
      expect(baseNames, isNot(contains('save_plugin_skill')));
      expect(baseNames, contains('run_subagent'));
      expect(baseNames, isNot(contains('call_plugin_function')));
      expect(baseNames, isNot(contains('plugin_file_write')));
      expect(baseNames, isNot(contains('create_plugin')));

      final grantedTools = ToolCallService.openAITools(const [], true, const [
        LynAICapabilities.pluginCallFunction,
        LynAIPermissions.pluginSkillFilesWrite,
        LynAIPermissions.pluginsFilesWrite,
      ]);
      final grantedNames = grantedTools
          .map((tool) => tool['function']?['name'])
          .whereType<String>()
          .toSet();
      expect(grantedNames, contains('call_plugin_function'));
      expect(grantedNames, contains('save_plugin_skill'));
      expect(grantedNames, contains('plugin_file_write'));
      expect(grantedNames, contains('create_plugin'));
    },
  );

  test('create_plugin 生成禁用草稿插件并可继续写入文件', () async {
    final root = await Directory.systemTemp.createTemp(
      'lynai_create_plugin_tool_',
    );
    try {
      final plugins = PluginProvider(
        repository: PluginRepository(rootOverride: root),
      );
      final conversations = memoryConversationProvider();
      final cid = conversations.createConversation(
        ConversationSettings(modelId: 'm1', agentEnabled: true),
      );
      conversations.addMessage(cid, 'user', '生成一个插件');
      conversations.addMessage(cid, 'assistant', '', save: false);
      final service = ToolCallService(
        FeatureProvider(),
        plugins: plugins,
        conversations: conversations,
        conversationId: cid,
      );

      final created = await service.execute(
        const ChatToolCall(
          id: 'create',
          name: 'create_plugin',
          arguments: {
            'id': 'gen-plugin',
            'name': '生成的插件',
            'kind': 'blank',
            'files': {
              'plugin.json':
                  '{"id":"gen-plugin","name":"生成的插件","version":"0.1.0","entry":"main.lua","permissions":[],"tools":[{"name":"hello","description":"打招呼","handler":"hello","parameters":{"type":"object","properties":{}}}]}',
              'main.lua': 'function hello(args) return { ok = true } end',
              'skills/demo.md': '# Demo',
            },
          },
        ),
        const [],
      );
      expect(created['ok'], isTrue);
      final createdResult = created['result'] as Map;
      expect(createdResult['pluginId'], 'gen-plugin');
      expect(createdResult['enabled'], isFalse);
      expect(
        createdResult['writtenFiles'],
        containsAll(<String>['plugin.json', 'main.lua', 'skills/demo.md']),
      );
      expect(
        conversations.getConversation(cid)?.pluginWorkspaceId,
        'gen-plugin',
      );

      final plugin = plugins.pluginById('gen-plugin');
      expect(plugin, isNotNull);
      expect(plugin!.devState, PluginDevState.draft);
      // files 中写入的完整 plugin.json 应被重载，声明了一个 hello 工具。
      expect(plugin.manifest.tools.map((tool) => tool.name), contains('hello'));

      // 工作区绑定后，plugin_file_read 可省略 pluginId。
      final read = await service.execute(
        const ChatToolCall(
          id: 'read',
          name: 'plugin_file_read',
          arguments: {'path': 'main.lua'},
        ),
        const [],
      );
      expect(read['ok'], isTrue);
      expect((read['result'] as Map)['content'], contains('hello'));

      // 重复创建同名插件应失败。
      final duplicate = await service.execute(
        const ChatToolCall(
          id: 'dup',
          name: 'create_plugin',
          arguments: {'id': 'gen-plugin', 'name': '重复'},
        ),
        const [],
      );
      expect(duplicate['ok'], isFalse);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('plugin_file_write 使用工作区插件并优先显式 pluginId', () async {
    final root = await Directory.systemTemp.createTemp(
      'lynai_plugin_workspace_tool_',
    );
    try {
      final plugins = PluginProvider(
        repository: PluginRepository(rootOverride: root),
      );
      await plugins.createPlugin(
        id: 'workspace-plugin',
        name: '工作区插件',
        version: '0.1.0',
        author: '',
        description: '',
        kind: PluginScaffoldKind.blank,
      );
      final conversations = memoryConversationProvider();
      final cid = conversations.createConversation(
        ConversationSettings(modelId: 'm1', agentEnabled: true),
      );
      conversations.setPluginWorkspace(cid, 'workspace-plugin');
      final service = ToolCallService(
        FeatureProvider(),
        plugins: plugins,
        conversations: conversations,
        conversationId: cid,
      );

      final written = await service.execute(
        const ChatToolCall(
          id: 'write',
          name: 'plugin_file_write',
          arguments: {'path': 'README.md', 'content': '# 工作区'},
        ),
        const [],
      );
      expect(written['ok'], isTrue);
      expect((written['result'] as Map)['pluginId'], 'workspace-plugin');
      expect(
        await plugins.readDeveloperFile('workspace-plugin', 'README.md'),
        contains('工作区'),
      );
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('web_fetch is exposed as a regular built-in tool', () {
    final tools = ToolCallService.openAITools();
    final webFetch = tools
        .map((tool) => tool['function'])
        .whereType<Map>()
        .firstWhere((function) => function['name'] == 'web_fetch');

    expect(webFetch['description'], contains('GET'));
    expect(webFetch['parameters'], isA<Map>());
    expect((webFetch['parameters'] as Map)['required'], contains('url'));
  });

  test('list_apps is exposed and open_app points at it for package names', () {
    final functions = ToolCallService.openAITools()
        .map((tool) => tool['function'])
        .whereType<Map>()
        .toList();
    final listApps = functions.firstWhere((f) => f['name'] == 'list_apps');
    final openApp = functions.firstWhere((f) => f['name'] == 'open_app');

    expect(listApps['parameters'], isA<Map>());
    expect(openApp['description'], contains('list_apps'));
  });

  test('foundation catalog has exactly four logical names', () {
    final service = ToolCallService(
      FeatureProvider(),
      permissionSnapshot: AgentPermissionSnapshot(
        permissions: const [
          LynAIPermissions.networkAccess,
          LynAIPermissions.storageRead,
        ],
      ),
      webSearchConfigured: true,
    );
    final snapshot = service.createRunSnapshot(
      agentEnabled: true,
      imageGenerationEnabled: false,
    );
    final foundation = snapshot.tools.registrations
        .map((registration) => registration.descriptor.name)
        .where(
          const {
            'ask_user',
            'web_search',
            'read_attachment',
            'resource',
            'resource_metadata',
            'resource_search',
            'resource_read_text',
            'resource_recognize',
          }.contains,
        )
        .toSet();

    expect(foundation, {
      'ask_user',
      'web_search',
      'read_attachment',
      'resource',
    });
    final resource = snapshot.tools['resource']!;
    expect(resource.descriptor.parameters['required'], contains('operation'));
    final webProperties =
        snapshot.tools['web_search']!.descriptor.parameters['properties']
            as Map<String, dynamic>;
    expect(webProperties, isNot(contains('route')));
    expect(webProperties, isNot(contains('provider')));
  });

  test('knowledge_search registration requires knowledge and storage read', () {
    final knowledge = KnowledgeProvider(
      repository: _MemoryKnowledgeRepository(),
    );
    final withoutKnowledge = ToolCallService(
      FeatureProvider(),
      permissionSnapshot: AgentPermissionSnapshot(
        permissions: const [LynAIPermissions.storageRead],
      ),
    ).createRunSnapshot(agentEnabled: true, imageGenerationEnabled: false);
    final denied = ToolCallService(
      FeatureProvider(),
      knowledge: knowledge,
      permissionSnapshot: AgentPermissionSnapshot(permissions: const []),
    ).createRunSnapshot(agentEnabled: true, imageGenerationEnabled: false);
    final allowed = ToolCallService(
      FeatureProvider(),
      knowledge: knowledge,
      permissionSnapshot: AgentPermissionSnapshot(
        permissions: const [LynAIPermissions.storageRead],
      ),
    ).createRunSnapshot(agentEnabled: true, imageGenerationEnabled: false);

    expect(withoutKnowledge.tools['knowledge_search'], isNull);
    expect(denied.tools['knowledge_search'], isNull);
    final registration = allowed.tools['knowledge_search'];
    expect(registration, isNotNull);
    expect(registration!.descriptor.sideEffect, AgentToolSideEffect.read);
    expect(
      registration.descriptor.concurrency,
      AgentToolConcurrency.parallelSafe,
    );
    expect(registration.spec.semantics.operation, AgentToolOperation.read);
    expect(registration.spec.semantics.risk, AgentToolRisk.low);
    expect(registration.spec.permissionRequirements.permissions, [
      LynAIPermissions.storageRead,
    ]);
    final schema = registration.descriptor.parameters;
    expect(schema['required'], contains('query'));
    final properties = schema['properties'] as Map;
    expect(
      properties.keys,
      containsAll([
        'query',
        'knowledgeBaseId',
        'categoryId',
        'limit',
        'includeContent',
      ]),
    );
    expect((properties['query'] as Map)['maxLength'], 256);
    expect((properties['knowledgeBaseId'] as Map)['maxLength'], 128);
    expect((properties['categoryId'] as Map)['maxLength'], 128);
  });

  test('knowledge_search rejects arguments above schema limits', () async {
    final service = ToolCallService(
      FeatureProvider(),
      knowledge: KnowledgeProvider(repository: _MemoryKnowledgeRepository()),
    );

    final longQuery = await service.execute(
      ChatToolCall(
        id: 'long-query',
        name: 'knowledge_search',
        arguments: {'query': 'q' * 257},
      ),
      const [],
    );
    final longBaseId = await service.execute(
      ChatToolCall(
        id: 'long-base-id',
        name: 'knowledge_search',
        arguments: {'query': 'q', 'knowledgeBaseId': 'b' * 129},
      ),
      const [],
    );

    expect(longQuery['ok'], isFalse);
    expect(longBaseId['ok'], isFalse);
  });

  test(
    'knowledge_search ranks titles and filters disabled knowledge data',
    () async {
      final now = DateTime.utc(2026, 8, 9);
      final knowledge = KnowledgeProvider(
        repository: _MemoryKnowledgeRepository(),
      );
      await knowledge.replaceAll(
        knowledgeBases: [
          _knowledgeBase('base-enabled', 'Enabled', now),
          _knowledgeBase('base-disabled', 'Disabled', now, enabled: false),
        ],
        categories: [
          _knowledgeCategory('category-enabled', 'base-enabled', now),
          _knowledgeCategory(
            'category-disabled',
            'base-enabled',
            now,
            enabled: false,
          ),
        ],
        entries: [
          _knowledgeEntry(
            'title-match',
            'base-enabled',
            'category-enabled',
            'Flutter handbook',
            'secondary text',
            now,
            sortOrder: 5,
          ),
          _knowledgeEntry(
            'content-match',
            'base-enabled',
            'category-enabled',
            'Reference',
            'Flutter appears in the body',
            now,
            sortOrder: 0,
          ),
          _knowledgeEntry(
            'uncategorized',
            'base-enabled',
            null,
            'Uncategorized Flutter',
            'available without a category',
            now,
          ),
          _knowledgeEntry(
            'disabled-entry',
            'base-enabled',
            'category-enabled',
            'Flutter disabled entry',
            'hidden',
            now,
            enabled: false,
          ),
          _knowledgeEntry(
            'disabled-category-entry',
            'base-enabled',
            'category-disabled',
            'Flutter disabled category',
            'hidden',
            now,
          ),
          _knowledgeEntry(
            'disabled-base-entry',
            'base-disabled',
            null,
            'Flutter disabled base',
            'hidden',
            now,
          ),
        ],
        sources: const <KnowledgeSource>[],
        explanations: const <KnowledgeExplanation>[],
      );
      final service = ToolCallService(FeatureProvider(), knowledge: knowledge);

      final result = await service.execute(
        const ChatToolCall(
          id: 'knowledge-search',
          name: 'knowledge_search',
          arguments: {'query': 'flutter'},
        ),
        const [],
      );
      final results = result['results'] as List;

      expect(result['ok'], isTrue);
      expect(results.map((item) => item['id']), [
        'uncategorized',
        'title-match',
        'content-match',
      ]);
      expect(results.last['matchedIn'], 'content');
      expect(results.first, isNot(contains('content')));
    },
  );

  test('knowledge_search applies filters limit and bounded content', () async {
    final now = DateTime.utc(2026, 8, 9);
    final knowledge = KnowledgeProvider(
      repository: _MemoryKnowledgeRepository(),
    );
    await knowledge.replaceAll(
      knowledgeBases: [
        _knowledgeBase('base', 'Base', now),
        _knowledgeBase('other-base', 'Other Base', now),
      ],
      categories: [
        _knowledgeCategory('category', 'base', now),
        _knowledgeCategory('other-category', 'base', now),
      ],
      entries: List.generate(
        12,
        (index) => _knowledgeEntry(
          'entry-$index',
          'base',
          index == 11 ? 'other-category' : 'category',
          'Query $index',
          index == 0
              ? '${List.filled(600, 'x').join()}query${List.filled(2200, 'y').join()}'
              : 'query body $index',
          now,
          sortOrder: index,
        ),
      ),
      sources: const <KnowledgeSource>[],
      explanations: const <KnowledgeExplanation>[],
    );
    await knowledge.replaceAll(
      knowledgeBases: knowledge.knowledgeBases,
      categories: knowledge.categories,
      entries: [
        ...knowledge.entries,
        _knowledgeEntry(
          'beyond-scan-limit',
          'base',
          'category',
          'No title match',
          '${'x' * 20000}query',
          now,
          sortOrder: 20,
        ),
      ],
      sources: knowledge.sources,
      explanations: knowledge.explanations,
    );
    final service = ToolCallService(FeatureProvider(), knowledge: knowledge);

    final previewOnly = await service.execute(
      const ChatToolCall(
        id: 'preview',
        name: 'knowledge_search',
        arguments: {'query': 'query', 'categoryId': 'category', 'limit': 2},
      ),
      const [],
    );
    final withContent = await service.execute(
      const ChatToolCall(
        id: 'content',
        name: 'knowledge_search',
        arguments: {
          'query': 'query',
          'knowledgeBaseId': 'base',
          'categoryId': 'category',
          'limit': 10,
          'includeContent': true,
        },
      ),
      const [],
    );
    final missing = await service.execute(
      const ChatToolCall(
        id: 'missing',
        name: 'knowledge_search',
        arguments: {'query': 'query', 'categoryId': 'missing'},
      ),
      const [],
    );
    final mismatch = await service.execute(
      const ChatToolCall(
        id: 'mismatch',
        name: 'knowledge_search',
        arguments: {
          'query': 'query',
          'knowledgeBaseId': 'other-base',
          'categoryId': 'category',
        },
      ),
      const [],
    );

    expect(previewOnly['count'], 2);
    expect((previewOnly['results'] as List).first, isNot(contains('content')));
    expect(
      ((previewOnly['results'] as List).first['preview'] as String).length,
      lessThanOrEqualTo(506),
    );
    expect(withContent['count'], 10);
    expect(
      (withContent['results'] as List).map((item) => item['id']),
      isNot(contains('beyond-scan-limit')),
    );
    expect(
      ((withContent['results'] as List).first['content'] as String).length,
      lessThanOrEqualTo(2003),
    );
    expect((withContent['results'] as List).first['contentTruncated'], isTrue);
    expect(missing['reason'], 'category_not_found');
    expect(missing['results'], isEmpty);
    expect(mismatch['reason'], 'category_base_mismatch');
    expect(mismatch['message'], contains('other-base'));
    expect(ToolCallService.nativeSystemPrompt, contains('检索已启用的本地知识库'));
  });

  test('knowledge_search captured execution honors pre-cancellation', () async {
    final knowledge = KnowledgeProvider(
      repository: _MemoryKnowledgeRepository(),
    );
    final service = ToolCallService(
      FeatureProvider(),
      knowledge: knowledge,
      permissionSnapshot: AgentPermissionSnapshot(
        permissions: const [LynAIPermissions.storageRead],
      ),
    );
    final snapshot = service.createRunSnapshot(
      agentEnabled: true,
      imageGenerationEnabled: false,
    );
    final cancellation = AgentCancellationSource()..cancel();

    final results = await service.executeCapturedBatch(
      snapshot,
      [
        AgentToolInvocation(
          id: 'knowledge-pre-cancelled',
          name: 'knowledge_search',
          arguments: const {'query': 'query'},
        ),
      ],
      identity: const AgentTurnIdentity(
        runId: 'run',
        turnId: 'turn',
        turnIndex: 0,
      ),
      cancellationToken: cancellation.token,
    );

    expect(results.single.status, AgentToolResultStatus.cancelled);
  });

  test(
    'knowledge_search captured execution yields and cancels a large scan',
    () async {
      final now = DateTime.utc(2026, 8, 9);
      final knowledge = KnowledgeProvider(
        repository: _MemoryKnowledgeRepository(),
      );
      await knowledge.replaceAll(
        knowledgeBases: [_knowledgeBase('base', 'Base', now)],
        categories: const [],
        entries: List.generate(
          10000,
          (index) => _knowledgeEntry(
            'entry-$index',
            'base',
            null,
            'Entry $index',
            'unmatched body',
            now,
          ),
        ),
        sources: const [],
        explanations: const [],
      );
      final service = ToolCallService(
        FeatureProvider(),
        knowledge: knowledge,
        permissionSnapshot: AgentPermissionSnapshot(
          permissions: const [LynAIPermissions.storageRead],
        ),
      );
      final snapshot = service.createRunSnapshot(
        agentEnabled: true,
        imageGenerationEnabled: false,
      );
      final cancellation = AgentCancellationSource();
      final execution = service.executeCapturedBatch(
        snapshot,
        [
          AgentToolInvocation(
            id: 'knowledge-cancelled-mid-scan',
            name: 'knowledge_search',
            arguments: const {'query': 'missing'},
          ),
        ],
        identity: const AgentTurnIdentity(
          runId: 'run',
          turnId: 'turn',
          turnIndex: 0,
        ),
        cancellationToken: cancellation.token,
      );
      Timer.run(cancellation.cancel);

      final results = await execution;

      expect(results.single.status, AgentToolResultStatus.cancelled);
    },
  );

  test(
    'ask_user run cancellation removes only its exact broker request',
    () async {
      final broker = AgentUserInteractionBroker();
      final service = ToolCallService(
        FeatureProvider(),
        userInteractionBroker: broker,
      );
      final snapshot = service.createRunSnapshot(
        agentEnabled: true,
        imageGenerationEnabled: false,
      );
      final cancellation = AgentCancellationSource();
      final execution = service.executeCapturedBatch(
        snapshot,
        [
          AgentToolInvocation(
            id: 'ask-cancelled',
            name: 'ask_user',
            arguments: const {'kind': 'confirm', 'prompt': 'Continue?'},
          ),
        ],
        identity: const AgentTurnIdentity(
          runId: 'run-cancelled',
          turnId: 'turn-cancelled',
          turnIndex: 0,
        ),
        cancellationToken: cancellation.token,
      );
      for (var i = 0; i < 100; i++) {
        if (broker.pendingFor(AgentUserInteractionSurface.mainChat) != null) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      expect(
        broker.pendingFor(AgentUserInteractionSurface.mainChat),
        isNotNull,
      );

      cancellation.cancel();
      await execution;

      expect(broker.pendingFor(AgentUserInteractionSurface.mainChat), isNull);
      final next = broker.ask(
        surface: AgentUserInteractionSurface.mainChat,
        identity: const AgentUserInteractionIdentity(
          runId: 'next-run',
          turnId: 'next-turn',
          toolCallId: 'next-call',
          toolName: 'ask_user',
        ),
        question: AgentUserQuestion(
          kind: AgentUserQuestionKind.confirm,
          prompt: 'Next?',
        ),
      );
      final nextRequest = broker.pendingFor(
        AgentUserInteractionSurface.mainChat,
      )!;
      broker.cancel(
        surface: AgentUserInteractionSurface.mainChat,
        requestId: nextRequest.id,
      );
      await next;
      broker.dispose();
    },
  );

  test('canonical organizer tools and legacy aliases are exposed', () {
    final tools = ToolCallService.openAITools();
    final names = tools
        .map((tool) => tool['function']?['name'])
        .whereType<String>()
        .toSet();

    expect(
      names,
      containsAll(const [
        'list_tasks',
        'create_task',
        'update_task',
        'delete_task',
        'list_task_lists',
        'create_task_list',
        'update_task_list',
        'delete_task_list',
        'list_calendar_events',
        'create_calendar_event',
        'update_calendar_event',
        'delete_calendar_event',
        'list_anniversaries',
        'create_anniversary',
        'update_anniversary',
        'delete_anniversary',
        'list_schedules',
        'create_schedule',
        'update_schedule',
        'list_todo_lists',
      ]),
    );
    expect(ToolCallService.nativeSystemPrompt, contains('YYYY-MM-DD'));
    expect(ToolCallService.nativeSystemPrompt, contains('只调用一次 create_task'));
    expect(ToolCallService.nativeSystemPrompt, contains('list_task_lists'));
    for (final name in const [
      'create_task',
      'update_task',
      'create_calendar_event',
      'update_calendar_event',
      'create_anniversary',
      'update_anniversary',
    ]) {
      final function = tools
          .map((tool) => tool['function'])
          .whereType<Map>()
          .firstWhere((value) => value['name'] == name);
      final properties = (function['parameters'] as Map)['properties'] as Map;
      final reminders = properties['reminders'] as Map;
      final items = reminders['items'] as Map;
      expect(reminders['type'], 'array');
      expect(items['required'], containsAll(['anchor', 'offsetMinutes']));
      expect(items['required'], isNot(contains('id')));
      expect(
        ((items['properties'] as Map)['anchor'] as Map)['enum'],
        containsAll([
          'eventStart',
          'taskPlanned',
          'taskDue',
          'anniversaryDate',
        ]),
      );
      expect(
        (((items['properties'] as Map)['dateOnlyTime'] as Map)['pattern']),
        isNotEmpty,
      );
    }
  });

  test(
    'canonical task CRUD and schedule task alias share TaskProvider',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'lynai_canonical_task_',
      );
      try {
        final storage = await _readyStorageV2(root);
        final features = FeatureProvider(storageV2: storage);
        final tasks = TaskProvider(storageV2: storage);
        final calendar = CalendarProvider(storageV2: storage);
        await Future.wait([features.load(), tasks.load(), calendar.load()]);
        final service = ToolCallService(
          features,
          tasks: tasks,
          calendar: calendar,
          agentIdentity: const LynAICallIdentity(type: LynAICallerType.system),
        );

        final created = await service.execute(
          const ChatToolCall(
            id: 'canonical-task',
            name: 'create_task',
            arguments: {
              'title': '提交报告',
              'plannedDate': '2026-07-23',
              'plannedTime': '09:30',
            },
          ),
          const [],
        );
        final compatibility = await service.execute(
          const ChatToolCall(
            id: 'legacy-task',
            name: 'create_schedule',
            arguments: {
              'kind': 'task',
              'title': '准备材料',
              'start': '2026-07-24T10:15:00',
            },
          ),
          const [],
        );

        expect(created['ok'], isTrue);
        expect(compatibility['ok'], isTrue);
        expect(tasks.tasks, hasLength(2));
        expect(calendar.events, isEmpty);
        expect((compatibility['schedule'] as Map), isNot(contains('end')));
      } finally {
        await root.delete(recursive: true);
      }
    },
  );

  test(
    'canonical organizer permissions reuse todos and schedules grants',
    () async {
      SharedPreferences.setMockInitialValues({});
      final settings = memorySettingsProvider();
      await settings.replaceSettings(
        AppSettings.defaults().copyWith(agentGrantedPermissions: const []),
      );
      final service = LynAIFunctionService();
      final deniedTask = await service.execute(
        const LynAIFunctionCall(name: 'tasks.list', arguments: {}),
        LynAIFunctionContext(
          identity: const LynAICallIdentity(type: LynAICallerType.agentLua),
          tasks: TaskProvider(),
          settings: settings,
        ),
      );
      final deniedCalendar = await service.execute(
        const LynAIFunctionCall(name: 'calendar.list', arguments: {}),
        LynAIFunctionContext(
          identity: const LynAICallIdentity(type: LynAICallerType.agentLua),
          calendar: CalendarProvider(),
          settings: settings,
        ),
      );

      expect(deniedTask['error'], contains(LynAIPermissions.todosRead));
      expect(deniedCalendar['error'], contains(LynAIPermissions.schedulesRead));
    },
  );

  test('Agent semantic delete variants fail closed before mutation', () async {
    final root = await Directory.systemTemp.createTemp(
      'lynai_semantic_delete_',
    );
    try {
      final storage = await _readyStorageV2(root);
      final features = FeatureProvider(storageV2: storage);
      final tasks = TaskProvider(storageV2: storage);
      await Future.wait([features.load(), tasks.load()]);
      final noteId = await features.addNoteWithContent('note', 'body');
      final pageId = await features.addNotePage(noteId, 'second');
      final folderId = await features.addNoteFolder('folder');
      final listId = await tasks.addList('list');
      final firstItemId = await tasks.addTask(title: 'first', listId: listId);
      final secondItemId = await tasks.addTask(title: 'second', listId: listId);
      final service = LynAIFunctionService();
      final context = LynAIFunctionContext(
        identity: const LynAICallIdentity(type: LynAICallerType.agent),
        agentPermissionSnapshot: AgentPermissionSnapshot(
          permissions: const [
            LynAIPermissions.notesWrite,
            LynAIPermissions.todosWrite,
          ],
        ),
        features: features,
        tasks: tasks,
      );

      for (final call in [
        LynAIFunctionCall(
          name: 'notes.pages.save',
          arguments: {'id': noteId, 'pageId': pageId, 'delete': true},
        ),
        LynAIFunctionCall(
          name: 'notes.folders.save',
          arguments: {'id': folderId, 'delete': true},
        ),
        LynAIFunctionCall(
          name: 'todos.saveItem',
          arguments: {'listId': listId, 'itemId': firstItemId, 'delete': true},
        ),
        LynAIFunctionCall(
          name: 'todos.saveList',
          arguments: {
            'id': listId,
            'items': [
              {'id': firstItemId, 'text': 'first'},
            ],
          },
        ),
      ]) {
        final result = await service.execute(call, context);
        expect(result['ok'], isFalse, reason: call.name);
        expect(result['error'].toString(), contains('删除操作'));
      }

      expect(
        features.notePages(noteId).map((page) => page.id),
        contains(pageId),
      );
      expect(features.getNoteFolder(folderId), isNotNull);
      expect(tasks.taskById(firstItemId), isNotNull);
      expect(tasks.taskById(secondItemId), isNotNull);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('http.fetch uses bounded SSRF policy', () async {
    final result = await LynAIFunctionService().execute(
      const LynAIFunctionCall(
        name: 'http.fetch',
        arguments: {'url': 'http://127.0.0.1/private'},
      ),
      LynAIFunctionContext(
        identity: const LynAICallIdentity(type: LynAICallerType.agent),
        agentPermissionSnapshot: AgentPermissionSnapshot(
          permissions: const [LynAIPermissions.networkAccess],
        ),
        outboundHttpClient: BoundedOutboundHttpClient(
          policy: OutboundNetworkPolicy(
            allowedHttpOrigins: const {'http://127.0.0.1'},
          ),
        ),
      ),
    );

    expect(result['ok'], isFalse);
    expect(result['error'].toString(), contains('默认仅允许 HTTPS'));
  });

  test(
    'http.fetch plaintext opt-in is explicit and still policy bounded',
    () async {
      final result = await LynAIFunctionService().execute(
        const LynAIFunctionCall(
          name: 'http.fetch',
          arguments: {'url': 'http://127.0.0.1/private'},
        ),
        LynAIFunctionContext(
          identity: const LynAICallIdentity(type: LynAICallerType.agent),
          agentPermissionSnapshot: AgentPermissionSnapshot(
            permissions: const [LynAIPermissions.networkAccess],
          ),
          outboundHttpClient: BoundedOutboundHttpClient(
            policy: OutboundNetworkPolicy(
              allowedHttpOrigins: const {'http://127.0.0.1'},
            ),
          ),
          allowPlaintextHttpFetch: true,
        ),
      );

      expect(result['ok'], isFalse);
      expect(result['error'].toString(), contains('privateHost'));
    },
  );

  test('call identity children preserve Agent correlation', () {
    const identity = LynAICallIdentity(
      type: LynAICallerType.agent,
      conversationId: 'conversation',
      runId: 'run',
      turnId: 'turn',
      toolCallId: 'outer-call',
    );

    final child = identity.child(
      type: LynAICallerType.agentLua,
      toolCallId: 'inner-call',
      toolName: 'notes.list',
    );

    expect(child.conversationId, 'conversation');
    expect(child.runId, 'run');
    expect(child.turnId, 'turn');
    expect(child.toolCallId, 'inner-call');
    expect(child.toolName, 'notes.list');
    expect(child.parent, same(identity));
  });

  test(
    'model-reachable direct dispatch fails closed without explicit trusted identity',
    () async {
      SharedPreferences.setMockInitialValues({});
      final settings = memorySettingsProvider();
      await settings.replaceSettings(
        AppSettings.defaults().copyWith(agentGrantedPermissions: const []),
      );
      final conversations = memoryConversationProvider();
      final cid = conversations.createConversation(
        ConversationSettings(modelId: 'm1', agentEnabled: true),
      );
      final features = FeatureProvider();
      const call = ChatToolCall(
        id: 'list-notes',
        name: 'list_notes',
        arguments: {},
      );

      final agentResult = await ToolCallService(
        features,
        settings: settings,
        conversations: conversations,
        conversationId: cid,
        agentIdentity: const LynAICallIdentity(
          type: LynAICallerType.agent,
          conversationId: 'correlated-conversation',
          runId: 'run-1',
          turnId: 'turn-1',
        ),
      ).execute(call, const []);
      final ordinaryResult = await ToolCallService(
        features,
        settings: settings,
        agentIdentity: const LynAICallIdentity(type: LynAICallerType.system),
      ).execute(call, const []);
      final agentOpenApp =
          await ToolCallService(
            features,
            settings: settings,
            conversations: conversations,
            conversationId: cid,
          ).execute(
            const ChatToolCall(
              id: 'open-app',
              name: 'open_app',
              arguments: {'packageName': 'com.example.app'},
            ),
            const [],
          );

      expect(agentResult['ok'], isFalse);
      expect(
        agentResult['error'].toString(),
        contains(LynAIPermissions.notesRead),
      );
      expect(ordinaryResult['ok'], isTrue);
      final missingIdentity = await ToolCallService(
        features,
        settings: settings,
      ).execute(call, const []);
      expect(missingIdentity['ok'], isFalse);
      expect(
        missingIdentity['error'].toString(),
        contains(LynAIPermissions.notesRead),
      );
      expect(agentOpenApp['ok'], isFalse);
      expect(
        agentOpenApp['error'].toString(),
        contains(LynAIPermissions.deviceControl),
      );
      final agentListApps =
          await ToolCallService(
            features,
            settings: settings,
            conversations: conversations,
            conversationId: cid,
          ).execute(
            const ChatToolCall(
              id: 'list-apps',
              name: 'list_apps',
              arguments: {},
            ),
            const [],
          );
      expect(agentListApps['ok'], isFalse);
      expect(
        agentListApps['error'].toString(),
        contains(LynAIPermissions.deviceControl),
      );
    },
  );

  test('list_apps returns apps when deviceControl is granted', () async {
    const channel = MethodChannel('lynai/native_tools');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'queryApps') {
            return {
              'ok': true,
              'apps': [
                {'packageName': 'com.tencent.mm', 'label': '微信'},
                {'packageName': 'com.android.chrome', 'label': 'Chrome'},
              ],
            };
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    final service = ToolCallService(
      FeatureProvider(),
      agentIdentity: const LynAICallIdentity(type: LynAICallerType.system),
      permissionSnapshot: AgentPermissionSnapshot(
        permissions: const [LynAIPermissions.deviceControl],
      ),
    );
    final result = await service.execute(
      const ChatToolCall(id: 'list-apps', name: 'list_apps', arguments: {}),
      const [],
    );

    expect(result['ok'], isTrue);
    expect(result['apps'], hasLength(2));
    expect((result['apps'] as List).first['packageName'], 'com.tencent.mm');
  });

  test('invalid core tool arguments are blocked before dispatch', () async {
    final result = await ToolCallService(FeatureProvider()).execute(
      const ChatToolCall(
        id: 'bad-open-app',
        name: 'open_app',
        arguments: {'packageName': 42},
      ),
      const [],
    );

    expect(result['ok'], isFalse);
    expect(result['error'].toString(), contains(r'$.packageName'));
    expect(result['error'].toString(), contains('expected string'));
  });

  test('compatibility execution maps structured external failures', () async {
    final registry = AgentToolRegistry();
    registry.register(
      AgentToolDescriptor(
        name: 'external_failure',
        description: 'fails',
        source: AgentToolSource.mcp,
        sideEffect: AgentToolSideEffect.external,
        concurrency: AgentToolConcurrency.parallelSafe,
      ),
      (invocation, token) async => throw StateError('remote detail'),
    );

    final results =
        await ToolCallService(
          FeatureProvider(),
          externalToolRegistry: registry,
        ).executeSequentialCompatibility(
          [AgentToolInvocation(id: 'failure', name: 'external_failure')],
          const [],
          identity: const AgentTurnIdentity(
            runId: 'run',
            turnId: 'turn',
            turnIndex: 0,
          ),
          cancellationToken: AgentCancellationSource().token,
        );

    expect(results.single.status, AgentToolResultStatus.failure);
    expect(results.single.errorCode, 'tool_execution_failed');
    expect(results.single.errorMessage, contains('remote detail'));
    expect(results.single.value.toString(), contains('remote detail'));
    final payload = jsonDecode(
      const AgentProtocolCodec().toolResultMessage(results.single)['content']
          as String,
    );
    expect(payload['error'], contains('remote detail'));
  });

  test(
    'compatibility cancellation reaches external handler and ignores late result',
    () async {
      final registry = AgentToolRegistry();
      final started = Completer<void>();
      final release = Completer<Object?>();
      AgentCancellationToken? receivedToken;
      registry.register(
        AgentToolDescriptor(
          name: 'slow_external',
          description: 'slow',
          source: AgentToolSource.mcp,
          sideEffect: AgentToolSideEffect.external,
          concurrency: AgentToolConcurrency.parallelSafe,
        ),
        (invocation, token) {
          receivedToken = token;
          started.complete();
          return release.future;
        },
      );
      final service = ToolCallService(
        FeatureProvider(),
        externalToolRegistry: registry,
      );
      var modelTurns = 0;
      final handle = const AgentLoopRuntime().start(
        messages: const [],
        maxToolRounds: 2,
        model: (request) async* {
          modelTurns++;
          yield AgentModelToolCalls([
            AgentToolInvocation(id: 'slow', name: 'slow_external'),
          ]);
          yield const AgentModelStreamCompleted();
        },
        executeTools: (calls, identity, cancellationToken) =>
            service.executeSequentialCompatibility(
              calls,
              const [],
              identity: identity,
              cancellationToken: cancellationToken,
            ),
      );

      await started.future;
      handle.cancel();
      final result = await handle.result.timeout(const Duration(seconds: 1));
      expect(receivedToken?.isCancellationRequested, isTrue);
      expect(result.status, AgentRunStatus.cancelled);
      release.complete({'late': true});
      await Future<void>.delayed(Duration.zero);
      expect(modelTurns, 1);
    },
  );

  test(
    'run snapshot is permission-filtered and resolves live MCP handler',
    () async {
      final registry = AgentToolRegistry();
      registry.register(
        AgentToolDescriptor(
          name: 'mcp_snapshot_lookup',
          description: 'Snapshot MCP',
          source: AgentToolSource.mcp,
          sideEffect: AgentToolSideEffect.external,
          concurrency: AgentToolConcurrency.parallelSafe,
        ),
        (invocation, cancellationToken) async => {'version': 1},
      );
      final service = ToolCallService(
        FeatureProvider(),
        externalToolRegistry: registry,
        externalToolSnapshot: registry.snapshot(),
        permissionSnapshot: AgentPermissionSnapshot(
          permissions: const [LynAIPermissions.networkAccess],
        ),
        webSearchConfigured: true,
      );
      final snapshot = service.createRunSnapshot(
        agentEnabled: false,
        imageGenerationEnabled: false,
      );
      registry.register(
        AgentToolDescriptor(
          name: 'mcp_snapshot_lookup',
          description: 'Replacement MCP',
          source: AgentToolSource.mcp,
          sideEffect: AgentToolSideEffect.external,
          concurrency: AgentToolConcurrency.parallelSafe,
        ),
        (invocation, cancellationToken) async => {'version': 2},
      );
      final cancellation = AgentCancellationSource();
      final results = await service.executeCapturedBatch(
        snapshot,
        [AgentToolInvocation(id: 'mcp', name: 'mcp_snapshot_lookup')],
        identity: const AgentTurnIdentity(
          runId: 'run',
          turnId: 'turn',
          turnIndex: 0,
        ),
        cancellationToken: cancellation.token,
      );

      expect(snapshot.tools['web_search'], isNotNull);
      expect(snapshot.tools['list_notes'], isNull);
      expect(snapshot.tools['mcp_snapshot_lookup'], isNotNull);
      expect((results.single.value as Map)['version'], 2);
    },
  );

  test(
    'non-Agent run executes organizer tools against the permission snapshot',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'lynai_non_agent_tools_',
      );
      try {
        final storage = await _readyStorageV2(root);
        final features = FeatureProvider(storageV2: storage);
        final tasks = TaskProvider(storageV2: storage);
        final calendar = CalendarProvider(storageV2: storage);
        await Future.wait([features.load(), tasks.load(), calendar.load()]);
        SharedPreferences.setMockInitialValues({});
        final conversations = memoryConversationProvider();
        final settings = memorySettingsProvider();
        await settings.replaceSettings(
          AppSettings.defaults().copyWith(
            agentGrantedPermissions: const [LynAIPermissions.todosWrite],
          ),
        );
        final cid = conversations.createConversation(
          ConversationSettings(
            modelId: 'm1',
            agentEnabled: false,
          ),
        );
        final service = ToolCallService(
          features,
          tasks: tasks,
          calendar: calendar,
          conversations: conversations,
          conversationId: cid,
          settings: settings,
        );
        final snapshot = service.createRunSnapshot(
          agentEnabled: false,
          imageGenerationEnabled: false,
        );
        expect(snapshot.tools['ask_user'], isNull);
        expect(snapshot.tools['create_task'], isNotNull);

        final cancellation = AgentCancellationSource();
        final created = await service.executeCapturedBatch(
          snapshot,
          [
            AgentToolInvocation(
              id: 'non-agent-task',
              name: 'create_task',
              arguments: const {
                'title': '非 Agent 创建',
                'plannedDate': '2026-07-23',
              },
            ),
          ],
          identity: const AgentTurnIdentity(
            runId: 'run',
            turnId: 'turn',
            turnIndex: 0,
          ),
          cancellationToken: cancellation.token,
        );
        expect((created.single.value as Map)['ok'], isTrue);
        expect(tasks.tasks, hasLength(1));

        // 删除类操作对所有模型驱动调用拒绝。
        final denied = await service.executeCapturedBatch(
          snapshot,
          [
            AgentToolInvocation(
              id: 'non-agent-delete',
              name: 'delete_task',
              arguments: {'id': tasks.tasks.single.id},
            ),
          ],
          identity: const AgentTurnIdentity(
            runId: 'run',
            turnId: 'turn-2',
            turnIndex: 1,
          ),
          cancellationToken: cancellation.token,
        );
        expect((denied.single.value as Map)['ok'], isFalse);
        expect(tasks.tasks, hasLength(1));
      } finally {
        await root.delete(recursive: true);
      }
    },
  );

  test('run identity stays fixed when conversation toggles mid-run', () async {
    SharedPreferences.setMockInitialValues({});
    final root = await Directory.systemTemp.createTemp(
      'lynai_test_run_identity_',
    );
    final storage = StorageV2Service(rootDirectory: root);
    await StorageV2UpgradeService(storageV2: storage).ensureReady();
    final features = FeatureProvider(storageV2: storage);
    final tasks = TaskProvider(storageV2: storage);
    final calendar = CalendarProvider(storageV2: storage);
    await Future.wait([features.load(), tasks.load(), calendar.load()]);
    final conversations = memoryConversationProvider();
    final settings = memorySettingsProvider();
    await settings.replaceSettings(
      AppSettings.defaults().copyWith(
        agentGrantedPermissions: const [LynAIPermissions.todosWrite],
      ),
    );
    final cid = conversations.createConversation(
      ConversationSettings(
        modelId: 'm1',
        agentEnabled: false,
      ),
    );
    final service = ToolCallService(
      features,
      tasks: tasks,
      calendar: calendar,
      conversations: conversations,
      conversationId: cid,
      settings: settings,
    );
    final snapshot = service.createRunSnapshot(
      agentEnabled: false,
      imageGenerationEnabled: false,
    );
    conversations.updateConversationSettings(
      cid,
      conversations.getConversation(cid)!.settings.copyWith(agentEnabled: true),
    );
    final cancellation = AgentCancellationSource();
    try {
      final created = await service.executeCapturedBatch(
        snapshot,
        [
          AgentToolInvocation(
            id: 'fixed-run-task',
            name: 'create_task',
            arguments: const {
              'title': '固定 run 身份',
              'plannedDate': '2026-07-23',
            },
          ),
        ],
        identity: const AgentTurnIdentity(
          runId: 'run',
          turnId: 'turn',
          turnIndex: 0,
        ),
        cancellationToken: cancellation.token,
      );
      expect((created.single.value as Map)['ok'], isTrue);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('run snapshot resolves permissions from global settings live', () async {
    SharedPreferences.setMockInitialValues({});
    final conversations = memoryConversationProvider();
    final settings = memorySettingsProvider();
    await settings.replaceSettings(
      AppSettings.defaults().copyWith(
        agentGrantedPermissions: const [LynAIPermissions.todosWrite],
      ),
    );
    final cid = conversations.createConversation(
      ConversationSettings(
        modelId: 'm1',
        agentEnabled: true,
      ),
    );
    final service = ToolCallService(
      FeatureProvider(),
      conversations: conversations,
      conversationId: cid,
      settings: settings,
    );
    final snapshot = service.createRunSnapshot(
      agentEnabled: true,
      imageGenerationEnabled: false,
    );
    expect(snapshot.tools['create_task'], isNotNull);

    // 修改全局权限后，新 snapshot 立即反映变化。
    await settings.replaceSettings(
      AppSettings.defaults().copyWith(
        agentGrantedPermissions: const [],
      ),
    );
    final cleared = service.createRunSnapshot(
      agentEnabled: true,
      imageGenerationEnabled: false,
    );
    expect(cleared.tools['create_task'], isNull);
  });

  test('web_search is not registered when web search is not configured', () {
    final service = ToolCallService(
      FeatureProvider(),
      permissionSnapshot: AgentPermissionSnapshot(
        permissions: const [LynAIPermissions.networkAccess],
      ),
    );
    final snapshot = service.createRunSnapshot(
      agentEnabled: true,
      imageGenerationEnabled: false,
    );
    expect(snapshot.tools['web_search'], isNull);
    expect(snapshot.tools['web_fetch'], isNotNull);
    expect(snapshot.tools['ask_user'], isNotNull);
  });

  test('get_current_screen is exposed only for floating screen context', () {
    final regularTools = ToolCallService.openAITools();
    final floatingTools = ToolCallService.openAITools(
      const [],
      false,
      const [],
      false,
      true,
    );

    String toolName(Map<String, dynamic> tool) {
      return (tool['function'] as Map)['name'] as String;
    }

    expect(regularTools.map(toolName), isNot(contains('get_current_screen')));
    expect(floatingTools.map(toolName), contains('get_current_screen'));
  });

  test(
    'get_current_screen execution requires floating authorization',
    () async {
      DeviceControlService.instance.setBackendForTesting(_FakeDeviceBackend());
      try {
        final denied = await ToolCallService(FeatureProvider()).execute(
          const ChatToolCall(
            id: 'screen-denied',
            name: 'get_current_screen',
            arguments: {},
          ),
          const [],
        );
        final allowed =
            await ToolCallService(
              FeatureProvider(),
              allowScreenContextTool: true,
            ).execute(
              const ChatToolCall(
                id: 'screen-allowed',
                name: 'get_current_screen',
                arguments: {},
              ),
              const [],
            );

        expect(denied['ok'], isFalse);
        expect(denied['error'], contains('未允许'));
        expect(allowed['ok'], isTrue);
        expect((allowed['result'] as Map)['text'], '当前页面文本');
      } finally {
        DeviceControlService.instance.setBackendForTesting(null);
      }
    },
  );

  test('floating chat respects disabled screen context mode', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider();
    await settings.replaceSettings(
      AppSettings.defaults().copyWith(
        floatingAssistant: const FloatingAssistantSettings(
          allowScreenContext: true,
          screenContextMode: FloatingAssistantSettings.screenContextDisabled,
        ),
      ),
    );
    final controller = FloatingChatSessionController(
      settings: settings,
      conversations: ConversationProvider(),
      models: ModelConfigProvider(),
      features: FeatureProvider(),
      knowledge: KnowledgeProvider(),
      tasks: TaskProvider(),
      calendar: CalendarProvider(),
      plugins: PluginProvider(),
    );
    try {
      expect(controller.screenContextToolAllowed, isFalse);
      expect(controller.stateJson()['screenContextEnabled'], isFalse);
    } finally {
      await controller.dispose();
    }
  });

  test('web_fetch rejects non-http URLs', () async {
    final service = ToolCallService(FeatureProvider());
    final result = await service.execute(
      const ChatToolCall(
        id: 'fetch-file',
        name: 'web_fetch',
        arguments: {'url': 'file:///etc/passwd'},
      ),
      const [],
    );

    expect(result['ok'], isFalse);
    expect(result['error'], contains('http/https'));
  });

  test('web_fetch fetches and truncates response body', () async {
    HttpServer? server;
    await HttpOverrides.runZoned(() async {
      try {
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final methods = <String>[];
        server!.listen((request) async {
          methods.add(request.method);
          request.response.headers.contentType = ContentType.text;
          request.response.write('abcdef');
          await request.response.close();
        });

        final service = ToolCallService(
          FeatureProvider(),
          agentIdentity: const LynAICallIdentity(type: LynAICallerType.system),
          outboundHttpClient: BoundedOutboundHttpClient(
            policy: OutboundNetworkPolicy(
              allowedHttpOrigins: {'http://127.0.0.1:${server!.port}'},
              allowPrivateNetwork: true,
            ),
          ),
          allowPlaintextHttpFetch: true,
        );
        final result = await service.execute(
          ChatToolCall(
            id: 'fetch-local',
            name: 'web_fetch',
            arguments: {
              'url': 'http://${server!.address.host}:${server!.port}/page',
              'maxChars': 4,
            },
          ),
          const [],
        );

        expect(result['ok'], isTrue);
        expect(result['status'], 200);
        expect(result['body'], 'abcd');
        expect(result['bodyLength'], 6);
        expect(result['truncated'], isTrue);
        expect(result['contentType'], contains('text/plain'));
        expect(methods, ['GET']);
      } finally {
        await server?.close(force: true);
      }
    }, createHttpClient: _RealHttpOverrides().createHttpClient);
  });

  test(
    'web_fetch falls back when the first resolved address is unreachable',
    () async {
      HttpServer? server;
      await HttpOverrides.runZoned(() async {
        try {
          server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
          server!.listen((request) async {
            request.response.headers.contentType = ContentType.text;
            request.response.write('ok');
            await request.response.close();
          });

          final service = ToolCallService(
            FeatureProvider(),
            agentIdentity: const LynAICallIdentity(
              type: LynAICallerType.system,
            ),
            outboundHttpClient: BoundedOutboundHttpClient(
              policy: OutboundNetworkPolicy(
                allowedHttpOrigins: {'http://127.0.0.1:${server!.port}'},
                allowPrivateNetwork: true,
                hostResolver: (host) async => ['127.0.0.2', '127.0.0.1'],
              ),
            ),
            allowPlaintextHttpFetch: true,
          );
          final result = await service.execute(
            ChatToolCall(
              id: 'fetch-fallback',
              name: 'web_fetch',
              arguments: {'url': 'http://127.0.0.1:${server!.port}/page'},
            ),
            const [],
          );

          expect(result['ok'], isTrue);
          expect(result['status'], 200);
          expect(result['body'], 'ok');
        } finally {
          await server?.close(force: true);
        }
      }, createHttpClient: _RealHttpOverrides().createHttpClient);
    },
  );

  test('modelVisibleToolResult strips nested binary payloads', () {
    final visible =
        ToolCallService.modelVisibleToolResult({
              'ok': true,
              'result': {
                'text': 'OCR text',
                'image': {
                  'mimeType': 'image/png',
                  'dataBase64': _tinyPngBase64,
                },
                'items': [
                  {'content': 'vision result', 'base64': 'secret'},
                  {'content': 'image result', 'b64_json': 'secret'},
                  {'content': 'upper result', 'ImageBase64': 'secret'},
                ],
              },
            })
            as Map;

    expect(visible['binaryContentOmitted'], isTrue);
    final result = visible['result'] as Map;
    expect(result['text'], 'OCR text');
    expect((result['image'] as Map), isNot(contains('dataBase64')));
    expect(((result['items'] as List).first as Map), isNot(contains('base64')));
    expect(((result['items'] as List)[1] as Map), isNot(contains('b64_json')));
    expect(
      ((result['items'] as List)[2] as Map),
      isNot(contains('ImageBase64')),
    );
  });

  test('read-only device queries use screen-read permission', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = memorySettingsProvider();
    await settings.replaceSettings(
      AppSettings.defaults().copyWith(
        agentGrantedPermissions: const [LynAIPermissions.deviceScreenRead],
      ),
    );
    final service = LynAIFunctionService();
    final context = LynAIFunctionContext(
      identity: const LynAICallIdentity(type: LynAICallerType.agentLua),
      settings: settings,
    );

    final query = await service.execute(
      const LynAIFunctionCall(name: 'device.node.find', arguments: {}),
      context,
    );
    final action = await service.execute(
      const LynAIFunctionCall(name: 'device.inputText', arguments: {}),
      context,
    );

    expect(query['ok'], isFalse);
    expect(query['error'].toString(), isNot(contains('未授权')));
    expect(action['ok'], isFalse);
    expect(
      action['error'].toString(),
      contains(LynAIPermissions.deviceControl),
    );
  });

  test('execute_lua tool describes async multi-step device scripts', () {
    final tools = ToolCallService.openAITools(const [], true, const [
      LynAICapabilities.luaExecute,
    ]);
    final executeLua = tools
        .map((tool) => tool['function'])
        .whereType<Map>()
        .firstWhere((function) => function['name'] == 'execute_lua');
    final description = executeLua['description'] as String;

    expect(description, contains('异步线性执行'));
    expect(description, contains('agent.plan.update'));
    expect(description, contains('agent.memory.update'));
    expect(description, contains('一次 execute_lua'));
    expect(description, contains('agent.note.add'));
    expect(description, contains('device.waitForNode'));
    expect(description, contains('model.ocr'));
    expect(description, contains('model.recognizeFile'));
    expect(description, contains('model.generateImage'));
  });

  test('image generation tool is appended last when enabled', () {
    final tools = ToolCallService.openAITools(const [], false, const [], true);
    final names = tools
        .map((tool) => tool['function'])
        .whereType<Map>()
        .map((function) => function['name'])
        .toList();

    expect(names.last, 'generate_image');
  });

  test('model recognition functions require dedicated permissions', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = memorySettingsProvider();
    await settings.replaceSettings(
      AppSettings.defaults().copyWith(agentGrantedPermissions: const []),
    );
    final result = await LynAIFunctionService().execute(
      const LynAIFunctionCall(
        name: 'model.ocr',
        arguments: {'imageBase64': 'AA=='},
      ),
      LynAIFunctionContext(
        identity: const LynAICallIdentity(type: LynAICallerType.agentLua),
        settings: settings,
      ),
    );

    expect(result['ok'], isFalse);
    expect(result['error'], contains(LynAIPermissions.modelOcr));
  });

  test('settings migration preserves disabled model permissions', () {
    final settings = AppSettings.fromJson({
      'themeColor': 0xFF2196F3,
      'baseThemeColor': 0xFF2196F3,
      'agentGrantedPermissions': const [LynAIPermissions.notesRead],
    });

    expect(
      settings.agentGrantedPermissions,
      contains(LynAIPermissions.notesRead),
    );
    expect(
      settings.agentGrantedPermissions,
      isNot(contains(LynAIPermissions.deviceControl)),
    );
    expect(
      settings.agentGrantedPermissions,
      isNot(contains(LynAIPermissions.modelChat)),
    );
    expect(
      settings.agentGrantedPermissions,
      isNot(contains(LynAIPermissions.modelOcr)),
    );
    expect(
      settings.agentGrantedPermissions,
      isNot(contains(LynAIPermissions.modelGenerateImage)),
    );
  });

  test(
    'permission service separates Agent defaults and plugin webview grants',
    () {
      const service = LynAIPermissionService();
      expect(
        service.canUsePermission(
          identity: const LynAICallIdentity(type: LynAICallerType.agentLua),
          permission: LynAIPermissions.notesRead,
        ),
        isTrue,
      );
      final manifest = PluginManifest.fromJson({
        'id': 'webview_perm_plugin',
        'name': 'WebView Permission Plugin',
        'entry': 'main.lua',
        'permissions': ['notes:read'],
      });
      final plugin = InstalledPlugin(
        manifest: manifest,
        path: '/tmp/webview_perm_plugin',
        enabled: true,
        grantedPermissions: const [],
        enabledFeaturePages: const [],
      );
      expect(
        service.canUsePermission(
          identity: const LynAICallIdentity(
            type: LynAICallerType.pluginWebview,
            pluginId: 'webview_perm_plugin',
          ),
          permission: LynAIPermissions.notesRead,
          plugin: plugin,
        ),
        isFalse,
      );
    },
  );

  test('add_agent_note appends assistant trace without permissions', () async {
    SharedPreferences.setMockInitialValues({});
    final conversations = memoryConversationProvider();
    final cid = conversations.createConversation(
      ConversationSettings(modelId: 'm1', agentEnabled: true),
    );
    conversations.addMessage(cid, 'user', 'do work');
    conversations.addMessage(cid, 'assistant', '', save: false);
    final service = ToolCallService(
      FeatureProvider(),
      conversations: conversations,
      conversationId: cid,
    );

    final result = await service.execute(
      const ChatToolCall(
        id: 'note',
        name: 'add_agent_note',
        arguments: {'content': '我先查看可用插件。'},
      ),
      const [],
    );

    expect(result['ok'], isTrue);
    expect(result['result'], {'noted': true});
    final trace = conversations.getConversation(cid)!.messages.last.agentTrace;
    expect(trace?.events, hasLength(1));
    expect(trace?.events.single.content, '我先查看可用插件。');
  });

  test('Agent memory tools persist conversation working memory', () async {
    SharedPreferences.setMockInitialValues({});
    final conversations = memoryConversationProvider();
    final cid = conversations.createConversation(
      ConversationSettings(modelId: 'm1', agentEnabled: true),
    );
    conversations.addMessage(cid, 'user', 'reply qq');
    conversations.addMessage(cid, 'assistant', '', save: false);
    final service = ToolCallService(
      FeatureProvider(),
      conversations: conversations,
      conversationId: cid,
    );

    final updated = await service.execute(
      const ChatToolCall(
        id: 'memory-update',
        name: 'update_agent_memory',
        arguments: {
          'goal': '回复 QQ 消息',
          'entries': [
            {'kind': 'fact', 'content': '目标联系人是 foo'},
          ],
        },
      ),
      const [],
    );
    final read = await service.execute(
      const ChatToolCall(
        id: 'memory-read',
        name: 'read_agent_memory',
        arguments: {},
      ),
      const [],
    );

    expect(updated['ok'], isTrue);
    expect(read['ok'], isTrue);
    final memory = conversations.getConversation(cid)!.agentWorkingMemory!;
    expect(memory.goal, '回复 QQ 消息');
    expect(memory.entries.single.content, '目标联系人是 foo');
    expect(
      conversations
          .getConversation(cid)!
          .messages
          .last
          .agentTrace
          ?.events
          .where((event) => event.type == AgentTraceEvent.memoryUpdate),
      isNotEmpty,
    );
  });

  test('generated images append to latest assistant message', () async {
    SharedPreferences.setMockInitialValues({});
    final conversations = memoryConversationProvider();
    final cid = conversations.createConversation(
      ConversationSettings(modelId: 'm1'),
    );
    conversations.addMessage(cid, 'user', 'draw a cat');
    conversations.addMessage(cid, 'assistant', 'working', save: false);

    conversations.appendImagesToLastAssistantMessage(cid, const [
      MessageImage(path: '/tmp/generated.png', name: 'generated.png', size: 12),
    ]);

    final message = conversations.getConversation(cid)!.messages.last;
    expect(message.role, 'assistant');
    expect(message.images, hasLength(1));
    expect(message.images.single.name, 'generated.png');
  });

  test('execute_lua ignores arbitrary generated image payloads', () async {
    SharedPreferences.setMockInitialValues({});
    final imageFile = File('${Directory.systemTemp.path}/lynai_generated.png');
    await imageFile.writeAsBytes(base64Decode(_tinyPngBase64));
    try {
      final conversations = memoryConversationProvider();
      final cid = conversations.createConversation(
        ConversationSettings(
          modelId: 'chat-1',
          agentEnabled: true,
        ),
      );
      conversations.addMessage(cid, 'user', 'draw a cat');
      conversations.addMessage(cid, 'assistant', '', save: false);
      final settings = memorySettingsProvider();
      await settings.replaceSettings(
        AppSettings.defaults().copyWith(
          agentGrantedPermissions: const [LynAIPermissions.luaExecute],
        ),
      );
      final service = ToolCallService(
        FeatureProvider(),
        settings: settings,
        conversations: conversations,
        conversationId: cid,
        agentIdentity: const LynAICallIdentity(
          type: LynAICallerType.agent,
          runId: 'run-lua-image',
          turnId: 'turn-lua-image',
        ),
        permissionSnapshot: AgentPermissionSnapshot(
          permissions: const [LynAIPermissions.luaExecute],
        ),
      );

      final result = await service.execute(
        ChatToolCall(
          id: 'lua-image',
          name: 'execute_lua',
          arguments: {
            'purpose': 'generate image',
            'code':
                '''
return {
  ok = true,
  generatedImages = {
    {
      path = "${imageFile.path}",
      name = "generated_image.png",
      size = 12,
      mimeType = "image/png"
    }
  }
}
''',
          },
        ),
        const [],
        cancellationToken: AgentCancellationSource().token,
      );

      expect(result['ok'], isTrue);
      final message = conversations.getConversation(cid)!.messages.last;
      expect(message.images, isEmpty);
    } finally {
      if (await imageFile.exists()) await imageFile.delete();
    }
  });

  test('Agent tools use structured success and error payloads', () async {
    SharedPreferences.setMockInitialValues({});
    final conversations = memoryConversationProvider();
    final disabledCid = conversations.createConversation(
      ConversationSettings(modelId: 'm1'),
    );
    final disabledService = ToolCallService(
      FeatureProvider(),
      conversations: conversations,
      conversationId: disabledCid,
    );

    final disabled = await disabledService.execute(
      const ChatToolCall(
        id: 'functions-disabled',
        name: 'list_plugin_functions',
        arguments: {},
      ),
      const [],
    );

    expect(disabled['ok'], isFalse);
    expect(disabled['error'], isA<Map>());
    expect((disabled['error'] as Map)['code'], 'agent_disabled');

    final cid = conversations.createConversation(
      ConversationSettings(modelId: 'm1', agentEnabled: true),
    );
    conversations.addMessage(cid, 'user', 'list functions');
    conversations.addMessage(cid, 'assistant', '', save: false);
    final service = ToolCallService(
      FeatureProvider(),
      conversations: conversations,
      conversationId: cid,
    );

    final listed = await service.execute(
      const ChatToolCall(
        id: 'functions',
        name: 'list_plugin_functions',
        arguments: {},
      ),
      const [],
    );

    expect(listed['ok'], isTrue);
    expect(listed['result'], isA<Map>());
    expect((listed['result'] as Map)['functions'], isA<List>());
  });

  test(
    'Agent can list and load plugin skills without extra permission',
    () async {
      SharedPreferences.setMockInitialValues({});
      final source = await Directory.systemTemp.createTemp(
        'lynai_skill_source_',
      );
      final installRoot = await Directory.systemTemp.createTemp(
        'lynai_skill_root_',
      );
      try {
        await Directory('${source.path}/skills').create();
        await File('${source.path}/plugin.json').writeAsString(
          jsonEncode({
            'id': 'skill-plugin',
            'name': 'Skill Plugin',
            'entry': 'main.lua',
            'skills': [
              {
                'name': 'weather__inner',
                'title': 'Weather Inner',
                'description': 'Use for weather planning.',
                'whenToUse': 'weather plans',
                'tags': ['weather'],
              },
            ],
          }),
        );
        await File('${source.path}/main.lua').writeAsString('return {}');
        await File(
          '${source.path}/skills/weather__inner.md',
        ).writeAsString('# Weather\n\nUse the weather tool.');
        final plugins = PluginProvider(
          repository: PluginRepository(rootOverride: installRoot),
        );
        await plugins.importDirectory(source.path);
        await plugins.setEnabled('skill-plugin', true);
        final conversations = memoryConversationProvider();
        final cid = conversations.createConversation(
          ConversationSettings(modelId: 'm1', agentEnabled: true),
        );
        conversations.addMessage(cid, 'user', 'load skill');
        conversations.addMessage(cid, 'assistant', '', save: false);
        final service = ToolCallService(
          FeatureProvider(),
          plugins: plugins,
          conversations: conversations,
          conversationId: cid,
        );

        final listed = await service.execute(
          const ChatToolCall(
            id: 'skills',
            name: 'list_plugin_skills',
            arguments: {},
          ),
          const [],
        );
        expect(listed['ok'], isTrue);
        final skills = ((listed['result'] as Map)['skills'] as List)
            .cast<Map>();
        expect(skills.single['qualifiedName'], 'skill-plugin__weather__inner');
        expect(
          ToolCallService.pluginSkillDisplayName(plugins.plugins, {
            'qualifiedName': 'skill-plugin__weather__inner',
          }),
          'Weather Inner',
        );

        final loaded = await service.execute(
          const ChatToolCall(
            id: 'load-skill',
            name: 'load_plugin_skill',
            arguments: {'qualifiedName': 'skill-plugin__weather__inner'},
          ),
          const [],
        );
        expect(loaded['ok'], isTrue);
        final result = loaded['result'] as Map;
        expect(result['name'], 'weather__inner');
        expect(result['content'], contains('Use the weather tool'));
      } finally {
        await source.delete(recursive: true);
        await installRoot.delete(recursive: true);
      }
    },
  );

  test('tool round limit message preserves existing assistant text', () {
    expect(ToolCallService.maxToolRounds, 24);
    expect(
      ToolCallService.toolRoundLimitMessage('partial answer'),
      allOf(contains('partial answer'), contains('24 轮上限')),
    );
  });

  test('Subagent stops consecutive tool calls at the shared limit', () async {
    SharedPreferences.setMockInitialValues({});
    await HttpOverrides.runZoned(() async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var requests = 0;
      unawaited(() async {
        await for (final request in server) {
          requests++;
          await utf8.decoder.bind(request).join();
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            'data: ${jsonEncode({
              'choices': [
                {
                  'delta': {'content': 'working $requests'},
                  'finish_reason': null,
                },
              ],
            })}\n\n',
          );
          request.response.write(
            'data: ${jsonEncode({
              'choices': [
                {
                  'delta': {
                    'tool_calls': [
                      {
                        'index': 0,
                        'id': 'call_$requests',
                        'type': 'function',
                        'function': {
                          'name': 'get_current_time',
                          'arguments': '{}',
                        },
                      },
                    ],
                  },
                  'finish_reason': 'tool_calls',
                },
              ],
            })}\n\n',
          );
          await request.response.close();
        }
      }());

      try {
        final conversations = memoryConversationProvider();
        final cid = conversations.createConversation(
          ConversationSettings(modelId: 'm1', agentEnabled: true),
        );
        conversations.addMessage(cid, 'assistant', '', save: false);
        final models = memoryModelConfigProvider()
          ..addModel(
            ModelConfig(
              id: 'm1',
              name: 'test',
              endpoint: 'http://${server.address.host}:${server.port}',
              apiKey: '',
              modelName: 'model',
              apiType: 'openai',
              priority: 0,
            ),
          );
        final service = ToolCallService(
          FeatureProvider(),
          modelConfigs: models,
          conversations: conversations,
          conversationId: cid,
        );

        final result = await service.execute(
          const ChatToolCall(
            id: 'subagent',
            name: 'run_subagent',
            arguments: {'task': 'keep calling tools'},
          ),
          const [],
        );

        expect(result['ok'], isFalse);
        expect((result['error'] as Map)['code'], 'tool_round_limit_reached');
        expect(requests, ToolCallService.maxToolRounds + 1);
      } finally {
        await server.close(force: true);
      }
    }, createHttpClient: _RealHttpOverrides().createHttpClient);
  });
}

class _MemoryKnowledgeRepository extends KnowledgeRepository {
  KnowledgeLoadResult _value = const KnowledgeLoadResult(
    bases: [],
    categories: [],
    entries: [],
    sources: [],
    explanations: [],
  );

  @override
  Future<KnowledgeLoadResult> load() async => _value;

  @override
  Future<void> replace(KnowledgeLoadResult value) async {
    _value = value;
  }

  @override
  Future<void> saveChanges({
    Iterable<KnowledgeBase> upsertBases = const [],
    Iterable<String> deleteBaseIds = const [],
    Iterable<KnowledgeCategory> upsertCategories = const [],
    Iterable<String> deleteCategoryIds = const [],
    Iterable<KnowledgeEntry> upsertEntries = const [],
    Iterable<String> deleteEntryIds = const [],
    Iterable<KnowledgeSource> upsertSources = const [],
    Iterable<String> deleteSourceIds = const [],
    Iterable<KnowledgeExplanation> upsertExplanations = const [],
    Iterable<String> deleteExplanationIds = const [],
  }) async {}
}

KnowledgeBase _knowledgeBase(
  String id,
  String name,
  DateTime now, {
  bool enabled = true,
  int sortOrder = 0,
}) => KnowledgeBase(
  id: id,
  name: name,
  enabled: enabled,
  sortOrder: sortOrder,
  createdAt: now,
  updatedAt: now,
);

KnowledgeCategory _knowledgeCategory(
  String id,
  String knowledgeBaseId,
  DateTime now, {
  bool enabled = true,
  int sortOrder = 0,
}) => KnowledgeCategory(
  id: id,
  knowledgeBaseId: knowledgeBaseId,
  name: id,
  alias: id.replaceAll('-', '_'),
  enabled: enabled,
  sortOrder: sortOrder,
  createdAt: now,
  updatedAt: now,
);

KnowledgeEntry _knowledgeEntry(
  String id,
  String knowledgeBaseId,
  String? categoryId,
  String title,
  String content,
  DateTime now, {
  bool enabled = true,
  int sortOrder = 0,
}) => KnowledgeEntry(
  id: id,
  knowledgeBaseId: knowledgeBaseId,
  categoryId: categoryId,
  title: title,
  content: content,
  enabled: enabled,
  sortOrder: sortOrder,
  createdAt: now,
  updatedAt: now,
);
