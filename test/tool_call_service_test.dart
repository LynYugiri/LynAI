import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/app_settings.dart';
import 'package:lynai/models/conversation.dart';
import 'package:lynai/models/message.dart';
import 'package:lynai/models/plugin.dart';
import 'package:lynai/providers/conversation_provider.dart';
import 'package:lynai/providers/feature_provider.dart';
import 'package:lynai/providers/plugin_provider.dart';
import 'package:lynai/providers/settings_provider.dart';
import 'package:lynai/repositories/plugin_repository.dart';
import 'package:lynai/services/lynai_call_identity.dart';
import 'package:lynai/services/lynai_function_service.dart';
import 'package:lynai/services/lynai_permission_definitions.dart';
import 'package:lynai/services/lynai_permission_service.dart';
import 'package:lynai/services/storage_v2_service.dart';
import 'package:lynai/services/storage_v2_upgrade_service.dart';
import 'package:lynai/services/tool_call_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _tinyPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.root);

  final Directory root;

  @override
  Future<String?> getApplicationDocumentsPath() => _path('documents');

  @override
  Future<String?> getApplicationSupportPath() => _path('support');

  @override
  Future<String?> getTemporaryPath() => _path('temp');

  Future<String> _path(String name) async {
    final directory = Directory('${root.path}/$name');
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory.path;
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
    pathProviderRoot = await Directory.systemTemp.createTemp(
      'lynai_tool_path_provider_test_',
    );
    PathProviderPlatform.instance = _FakePathProviderPlatform(
      pathProviderRoot!,
    );
  });

  tearDown(() async {
    final root = pathProviderRoot;
    pathProviderRoot = null;
    if (root != null && await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test('fallback parser tolerates malformed tool arguments', () {
    final calls = ToolCallService.parseFallbackToolCalls(r'''
```json
{
  "tool_calls": [
    {"name": "list_notes", "arguments": "{\"query\":\"alpha\"}"},
    {"name": "save_note", "arguments": "{bad json"},
    {"name": "save_note", "arguments": {"title": "x"}},
    {"arguments": {"query": "drop"}}
  ]
}
```
''');

    expect(calls, hasLength(3));
    expect(calls[0].name, 'list_notes');
    expect(calls[0].arguments, {'query': 'alpha'});
    expect(calls[1].name, 'save_note');
    expect(calls[1].arguments, isEmpty);
    expect(calls[2].name, 'save_note');
    expect(calls[2].arguments, {'title': 'x'});
    expect(calls.map((call) => call.id).toSet(), hasLength(calls.length));
  });

  test('fallback parser converts non-object arguments to empty maps', () {
    final calls = ToolCallService.parseFallbackToolCalls(
      jsonEncode({
        'tool_calls': [
          {'name': 'list_schedules', 'arguments': []},
          {'name': 'list_notes', 'arguments': '[]'},
          {'name': 'list_todo_lists', 'arguments': null},
        ],
      }),
    );

    expect(calls, hasLength(3));
    expect(calls.every((call) => call.arguments.isEmpty), isTrue);
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
        final service = ToolCallService(features);

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
      final service = ToolCallService(features);
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
      expect(baseNames, contains('list_plugin_functions'));
      expect(baseNames, contains('list_plugin_skills'));
      expect(baseNames, contains('load_plugin_skill'));
      expect(baseNames, isNot(contains('call_plugin_function')));

      final grantedTools = ToolCallService.openAITools(const [], true, const [
        LynAICapabilities.pluginCallFunction,
      ]);
      final grantedNames = grantedTools
          .map((tool) => tool['function']?['name'])
          .whereType<String>()
          .toSet();
      expect(grantedNames, contains('call_plugin_function'));
    },
  );

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
    final settings = SettingsProvider();
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
      contains(LynAIPermissions.deviceControl),
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
    final conversations = ConversationProvider();
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

  test('generated images append to latest assistant message', () async {
    SharedPreferences.setMockInitialValues({});
    final conversations = ConversationProvider();
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
      final conversations = ConversationProvider();
      final cid = conversations.createConversation(
        ConversationSettings(modelId: 'chat-1', agentEnabled: true),
      );
      conversations.addMessage(cid, 'user', 'draw a cat');
      conversations.addMessage(cid, 'assistant', '', save: false);
      final settings = SettingsProvider();
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
    final conversations = ConversationProvider();
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
        final conversations = ConversationProvider();
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
}
