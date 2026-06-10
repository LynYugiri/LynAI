import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/conversation.dart';
import 'package:lynai/providers/conversation_provider.dart';
import 'package:lynai/providers/feature_provider.dart';
import 'package:lynai/providers/model_config_provider.dart';
import 'package:lynai/providers/settings_provider.dart';
import 'package:lynai/services/storage_migration_service.dart';
import 'package:lynai/services/storage_v2_service.dart';
import 'package:lynai/services/tool_call_service.dart';
import 'package:lynai/services/lynai_permission_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
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
      SharedPreferences.setMockInitialValues({});
      final features = FeatureProvider();
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
    },
  );

  test('save_note_page moves note pages', () async {
    SharedPreferences.setMockInitialValues({});
    final settingsProvider = SettingsProvider();
    final modelProvider = ModelConfigProvider();
    final conversationProvider = ConversationProvider();
    final featureProvider = FeatureProvider();
    await settingsProvider.loadSettings();
    await modelProvider.loadModels();
    await conversationProvider.loadConversations();
    await featureProvider.load();
    final noteId = await featureProvider.addNoteWithContent('note', 'body');

    final root = await Directory.systemTemp.createTemp(
      'lynai_tool_page_move_test_',
    );
    try {
      await StorageMigrationService(
        settingsProvider: settingsProvider,
        modelConfigProvider: modelProvider,
        conversationProvider: conversationProvider,
        featureProvider: featureProvider,
        rootDirectory: root,
      ).migrate();

      final features = FeatureProvider(
        storageV2: StorageV2Service(rootDirectory: root),
      );
      await features.load();
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
}
