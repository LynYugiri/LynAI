import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lynai/models/app_settings.dart';
import 'package:lynai/models/backup_models.dart';
import 'package:lynai/models/conversation.dart';
import 'package:lynai/models/message.dart';
import 'package:lynai/models/model_config.dart';
import 'package:lynai/models/note.dart';
import 'package:lynai/models/schedule_item.dart';
import 'package:lynai/models/todo_list.dart';
import 'package:lynai/providers/conversation_provider.dart';
import 'package:lynai/providers/feature_provider.dart';
import 'package:lynai/providers/model_config_provider.dart';
import 'package:lynai/providers/settings_provider.dart';
import 'package:lynai/services/api_service.dart';
import 'package:lynai/services/backup_service.dart';
import 'package:lynai/services/storage_migration_service.dart';
import 'package:lynai/services/storage_v2_service.dart';
import 'package:lynai/services/tool_call_service.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('AppSettings preserves nullable fields through copyWith sentinel', () {
    final settings = AppSettings(
      themeColor: Colors.purple,
      baseThemeColor: Colors.purple,
      speechModelId: 'speech-1',
      imageModelId: 'ocr-1',
      imageRecognitionModelId: 'vision-1',
      lastChatModelId: 'chat-1',
    );

    expect(settings.copyWith().speechModelId, 'speech-1');
    expect(settings.copyWith(speechModelId: null).speechModelId, isNull);
    expect(settings.copyWith(imageModelId: null).imageModelId, isNull);
    expect(
      settings.copyWith(imageRecognitionModelId: null).imageRecognitionModelId,
      isNull,
    );
    expect(settings.copyWith(lastChatModelId: null).lastChatModelId, isNull);
  });

  test('Message serializes image attachments and thinking content', () {
    final message = Message(
      id: 'm1',
      role: 'user',
      content: 'hello',
      images: const [MessageImage(path: '/tmp/a.png', name: 'a.png', size: 12)],
      thinkingContent: 'reasoning trace',
      timestamp: DateTime.utc(2026),
    );

    final restored = Message.fromJson(message.toJson());

    expect(restored.images, hasLength(1));
    expect(restored.images.single.path, '/tmp/a.png');
    expect(restored.images.single.name, 'a.png');
    expect(restored.images.single.size, 12);
    expect(restored.thinkingContent, 'reasoning trace');
  });

  test(
    'ConversationProvider can replace and clear message thinking content',
    () {
      SharedPreferences.setMockInitialValues({});
      final provider = ConversationProvider();
      final conversationId = provider.createConversation(
        ConversationSettings(modelId: 'm1'),
      );
      provider.addMessage(
        conversationId,
        'assistant',
        'first',
        thinkingContent: 'old thinking',
      );
      final messageId = provider
          .getConversation(conversationId)!
          .messages
          .single
          .id;

      provider.updateMessageContent(
        conversationId,
        messageId,
        'second',
        thinkingContent: 'new thinking',
      );
      expect(
        provider
            .getConversation(conversationId)!
            .messages
            .single
            .thinkingContent,
        'new thinking',
      );

      provider.updateMessageContent(
        conversationId,
        messageId,
        'third',
        thinkingContent: null,
      );
      final message = provider.getConversation(conversationId)!.messages.single;
      expect(message.content, 'third');
      expect(message.thinkingContent, isNull);
    },
  );

  test('ConversationSettings reads legacy imagePrompt key', () {
    final settings = ConversationSettings.fromJson({
      'modelId': 'chat-1',
      'imagePrompt': 'legacy prompt',
    });

    expect(settings.imageRecognitionPrompt, 'legacy prompt');
  });

  test('OpenAI messages preserve assistant reasoning content', () {
    final messages = ApiService.openAICompatibleMessagesForTest([
      {
        'role': 'assistant',
        'content': '需要查日程',
        'reasoning_content': '先判断是否需要调用工具',
        'tool_calls': [
          {
            'id': 'call-1',
            'type': 'function',
            'function': {'name': 'list_schedules', 'arguments': '{}'},
          },
        ],
      },
      {'role': 'tool', 'tool_call_id': 'call-1', 'content': '{"ok":true}'},
    ]);

    expect(messages.first['reasoning_content'], '先判断是否需要调用工具');
    expect(messages.first.containsKey('tool_calls'), isTrue);
    expect(messages.first.containsKey('reasoningContent'), isFalse);
  });

  test('OpenAI response accepts structured content parts', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    Map<String, dynamic>? requestBody;
    unawaited(
      server.first.then((request) async {
        expect(request.uri.path, '/chat/completions');
        requestBody =
            jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, dynamic>;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'role': 'assistant',
                  'content': [
                    {'type': 'text', 'text': '你好'},
                    {'type': 'text', 'text': '，世界'},
                  ],
                  'reasoning_content': '结构化正文也要保留推理',
                },
              },
            ],
          }),
        );
        await request.response.close();
      }),
    );

    try {
      final response = await ApiService().sendChatRequest(
        ModelConfig(
          id: 'm1',
          name: 'Local',
          endpoint: 'http://${server.address.host}:${server.port}',
          apiKey: '',
          modelName: 'model-a',
          apiType: 'openai',
          priority: 0,
        ),
        const [
          {'role': 'user', 'content': 'hello'},
        ],
      );

      expect(response.content, '你好，世界');
      expect(response.reasoning, '结构化正文也要保留推理');
      expect(requestBody?['thinking'], {'type': 'disabled'});
    } finally {
      await server.close(force: true);
    }
  });

  test('Anthropic request sends thinking config when enabled', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    Map<String, dynamic>? requestBody;
    unawaited(
      server.first.then((request) async {
        requestBody =
            jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, dynamic>;
        expect(request.uri.path, '/messages');
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'content': [
              {'type': 'thinking', 'thinking': '先思考'},
              {'type': 'text', 'text': '再回答'},
            ],
          }),
        );
        await request.response.close();
      }),
    );

    try {
      final response = await ApiService().sendChatRequest(
        ModelConfig(
          id: 'm1',
          name: 'Claude',
          endpoint: 'http://${server.address.host}:${server.port}',
          apiKey: 'key',
          modelName: 'claude-test',
          apiType: 'anthropic',
          priority: 0,
          maxTokens: 128,
        ),
        const [
          {'role': 'system', 'content': 'system'},
          {'role': 'user', 'content': 'hello'},
        ],
        thinking: true,
      );

      expect(response.content, '再回答');
      expect(response.reasoning, '先思考');
      expect(requestBody?['thinking'], {
        'type': 'enabled',
        'budget_tokens': 127,
      });
      expect(requestBody?['system'], 'system');
    } finally {
      await server.close(force: true);
    }
  });

  test('ModelConfig defaults category and enabled model entry', () {
    final config = ModelConfig.fromJson({
      'id': '1',
      'name': 'Provider',
      'endpoint': 'https://example.com',
      'apiKey': 'key',
      'modelName': 'model-a',
      'apiType': 'openai',
      'priority': 0,
    });

    expect(config.category, ModelConfig.categoryChat);
    expect(config.enabledModelNames, ['model-a']);
  });

  test('ModelConfig copyWith can clear nullable generation parameters', () {
    final config = ModelConfig(
      id: '1',
      name: 'Provider',
      endpoint: 'https://example.com',
      apiKey: 'key',
      modelName: 'model-a',
      apiType: 'openai',
      priority: 0,
      maxTokens: 1024,
      temperature: 0.7,
      topP: 0.9,
    );

    final cleared = config.copyWith(
      maxTokens: null,
      temperature: null,
      topP: null,
    );

    expect(cleared.maxTokens, isNull);
    expect(cleared.temperature, isNull);
    expect(cleared.topP, isNull);
  });

  test(
    'Conversation skips malformed messages instead of dropping conversation',
    () {
      final conversation = Conversation.fromJson({
        'id': 'c1',
        'title': 'ok',
        'messages': [
          {
            'id': 'm1',
            'role': 'user',
            'content': 'hello',
            'timestamp': '2026-01-01T00:00:00.000Z',
          },
          {'id': 'broken'},
        ],
        'modelId': 'm1',
        'settings': {'modelId': 'm1'},
        'roleId': 'default',
        'createdAt': '2026-01-01T00:00:00.000Z',
        'updatedAt': '2026-01-01T00:00:00.000Z',
      });

      expect(conversation.messages, hasLength(1));
      expect(conversation.messages.single.content, 'hello');
    },
  );

  test('MessageImage derives legacy filePath name and mime type', () {
    final image = MessageImage.fromJson({'filePath': '/tmp/photo.jpg'});

    expect(image.path, '/tmp/photo.jpg');
    expect(image.name, 'photo.jpg');
    expect(image.mimeType, 'image/jpeg');
  });

  test('Loaders skip malformed persisted items', () async {
    SharedPreferences.setMockInitialValues({
      'conversations':
          '[{"id":"c1","title":"ok","messages":[],"modelId":"m1","settings":{"modelId":"m1"},"roleId":"default","createdAt":"2026-01-01T00:00:00.000Z","updatedAt":"2026-01-01T00:00:00.000Z"},{"id":"broken"}]',
      'model_configs':
          '[{"id":"m1","name":"Model","endpoint":"https://example.com","apiKey":"key","modelName":"model-a","apiType":"openai","priority":0},{"id":"broken"}]',
      'schedule_items':
          '[{"id":"s1","title":"demo","start":"2026-01-01T09:00:00.000Z","end":"2026-01-01T10:00:00.000Z"},{"id":"broken"}]',
      'notes':
          '[{"id":"n1","title":"note","content":"text","createdAt":"2026-01-01T00:00:00.000Z","updatedAt":"2026-01-01T00:00:00.000Z"},{"id":"broken"}]',
    });

    final conversationProvider = ConversationProvider();
    final modelProvider = ModelConfigProvider();
    final featureProvider = FeatureProvider();

    await conversationProvider.loadConversations();
    await modelProvider.loadModels();
    await featureProvider.load();

    expect(conversationProvider.conversations, hasLength(1));
    expect(modelProvider.models, hasLength(1));
    expect(featureProvider.schedules, hasLength(1));
    expect(featureProvider.notes, hasLength(1));
  });

  test('ScheduleItem preserves task kind and keeps legacy schedules', () {
    final legacy = ScheduleItem.fromJson({
      'id': 's1',
      'title': 'legacy',
      'start': '2026-01-01T09:00:00.000',
      'end': '2026-01-01T10:00:00.000',
    });
    final task = ScheduleItem.fromJson({
      'id': 't1',
      'title': 'task',
      'kind': 'task',
      'start': '2026-01-01T09:00:00.000',
      'end': '2026-01-01T09:01:00.000',
    });

    expect(legacy.kind, ScheduleItem.kindSchedule);
    expect(legacy.isTask, isFalse);
    expect(task.kind, ScheduleItem.kindTask);
    expect(task.isTask, isTrue);
    expect(task.toJson(), containsPair('kind', 'task'));
    expect(legacy.toJson().containsKey('kind'), isFalse);
  });

  test('ToolCallService creates schedule tasks with start only', () async {
    SharedPreferences.setMockInitialValues({});
    final featureProvider = FeatureProvider();
    await featureProvider.load();
    final service = ToolCallService(featureProvider);

    final taskResult = await service.execute(
      const ChatToolCall(
        id: 'create-task',
        name: 'create_schedule',
        arguments: {
          'kind': 'task',
          'title': '交材料',
          'start': '2026-01-01T09:00:00.000',
        },
      ),
      const [],
    );

    expect(taskResult['ok'], isTrue);
    expect(taskResult['schedule']['kind'], 'task');
    expect(taskResult['schedule'].containsKey('end'), isFalse);
    expect(featureProvider.schedules.single.isTask, isTrue);
    expect(
      featureProvider.schedules.single.end.difference(
        featureProvider.schedules.single.start,
      ),
      const Duration(minutes: 1),
    );
  });

  test('ToolCallService manages todo lists and items', () async {
    SharedPreferences.setMockInitialValues({});
    final featureProvider = FeatureProvider();
    await featureProvider.load();
    final service = ToolCallService(featureProvider);

    final createResult = await service.execute(
      const ChatToolCall(
        id: 'create-list',
        name: 'save_todo_list',
        arguments: {
          'title': '购物',
          'items': [
            {'text': '买牛奶', 'done': 'false'},
            {'text': '  '},
          ],
        },
      ),
      const [],
    );

    expect(createResult['ok'], isTrue);
    final list = createResult['todoList'] as Map<String, dynamic>;
    expect(list['title'], '购物');
    expect(list['items'], hasLength(1));
    final listId = list['id'] as String;
    final itemId = (list['items'] as List).single['id'] as String;

    final completeResult = await service.execute(
      ChatToolCall(
        id: 'complete-item',
        name: 'save_todo_item',
        arguments: {'listId': listId, 'itemId': itemId, 'done': 'true'},
      ),
      const [],
    );

    expect(completeResult['ok'], isTrue);
    expect(completeResult['item']['done'], isTrue);

    final addResult = await service.execute(
      ChatToolCall(
        id: 'add-item',
        name: 'save_todo_item',
        arguments: {'listId': listId, 'text': '买面包'},
      ),
      const [],
    );

    expect(addResult['ok'], isTrue);
    expect(addResult['todoList']['items'], hasLength(2));
    expect(addResult['todoList']['items'].first['text'], '买面包');

    final renameResult = await service.execute(
      ChatToolCall(
        id: 'rename-list',
        name: 'save_todo_list',
        arguments: {'id': listId, 'items': const []},
      ),
      const [],
    );

    expect(renameResult['ok'], isTrue);
    expect(renameResult['todoList']['title'], '购物');
    expect(renameResult['todoList']['items'], isEmpty);
  });

  test('Note folders persist and clean missing references', () async {
    SharedPreferences.setMockInitialValues({
      'notes':
          '[{"id":"n1","title":"orphan","content":"text","folderId":"missing","createdAt":"2026-01-01T00:00:00.000Z","updatedAt":"2026-01-01T00:00:00.000Z"}]',
      'note_folders': '[]',
    });
    final featureProvider = FeatureProvider();

    await featureProvider.load();

    expect(featureProvider.notes.single.folderId, isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('notes'), contains('"title":"orphan"'));
    expect(prefs.getString('notes'), isNot(contains('"folderId":"missing"')));
  });

  test('Note copyWith can clear folder without changing updatedAt', () {
    final updatedAt = DateTime.utc(2026, 1, 1);
    final note = Note(
      id: 'n1',
      title: 'note',
      content: 'text',
      folderId: 'f1',
      createdAt: updatedAt,
      updatedAt: updatedAt,
    );

    final cleaned = note.copyWith(folderId: null, preserveUpdatedAt: true);

    expect(cleaned.folderId, isNull);
    expect(cleaned.updatedAt, updatedAt);
  });

  test(
    'Note timeline protects current path and deletes branch descendants',
    () async {
      SharedPreferences.setMockInitialValues({});
      final featureProvider = FeatureProvider();
      await featureProvider.load();

      final noteId = await featureProvider.addNoteWithContent('note', 'root');
      final rootId = featureProvider.getNote(noteId)!.currentRevisionId!;
      final second = await featureProvider.saveNoteContent(noteId, 'second');
      final secondId = second!.id;
      final third = await featureProvider.saveNoteContent(noteId, 'third');
      final thirdId = third!.id;

      expect(featureProvider.getNoteCurrentRevisionPath(noteId), {
        rootId,
        secondId,
        thirdId,
      });
      expect(await featureProvider.deleteNoteRevision(noteId, rootId), isFalse);
      expect(
        await featureProvider.deleteNoteRevision(noteId, thirdId),
        isFalse,
      );

      final restored = await featureProvider.restoreNoteRevision(
        noteId,
        rootId,
      );
      final restoredId = restored!.id;

      expect(featureProvider.getNote(noteId)!.content, 'root');
      expect(featureProvider.getNoteCurrentRevisionPath(noteId), {
        rootId,
        restoredId,
      });
      expect(
        await featureProvider.deleteNoteRevision(noteId, secondId),
        isTrue,
      );

      final timelineIds = featureProvider
          .getNoteTimeline(noteId)
          .map((revision) => revision.id)
          .toSet();
      expect(timelineIds, containsAll([rootId, restoredId]));
      expect(timelineIds, isNot(contains(secondId)));
      expect(timelineIds, isNot(contains(thirdId)));
      expect(
        featureProvider.getNoteContentAtRevision(noteId, restoredId),
        'root',
      );
    },
  );

  test(
    'Note timeline can delete branches from a current path fork point',
    () async {
      SharedPreferences.setMockInitialValues({});
      final featureProvider = FeatureProvider();
      await featureProvider.load();

      final noteId = await featureProvider.addNoteWithContent('note', 'root');
      final rootId = featureProvider.getNote(noteId)!.currentRevisionId!;
      final main = await featureProvider.saveNoteContent(noteId, 'main');
      final mainId = main!.id;
      final branch = await featureProvider.restoreNoteRevision(noteId, rootId);
      final branchId = branch!.id;
      final branchChild = await featureProvider.saveNoteContent(
        noteId,
        'branch child',
      );
      final branchChildId = branchChild!.id;
      final mainAgain = await featureProvider.restoreNoteRevision(
        noteId,
        mainId,
      );
      final mainAgainId = mainAgain!.id;

      expect(featureProvider.getNoteCurrentRevisionPath(noteId), {
        rootId,
        mainId,
        mainAgainId,
      });
      expect(featureProvider.countNoteBranchRevisions(noteId, rootId), 2);

      final deleted = await featureProvider.deleteNoteBranchesFromRevision(
        noteId,
        rootId,
      );

      expect(deleted, 2);
      final timelineIds = featureProvider
          .getNoteTimeline(noteId)
          .map((revision) => revision.id)
          .toSet();
      expect(timelineIds, containsAll([rootId, mainId, mainAgainId]));
      expect(timelineIds, isNot(contains(branchId)));
      expect(timelineIds, isNot(contains(branchChildId)));
      expect(featureProvider.getNote(noteId)!.content, 'main');
    },
  );

  test('Note save falls back when base revision is missing', () async {
    SharedPreferences.setMockInitialValues({});
    final featureProvider = FeatureProvider();
    await featureProvider.load();

    final noteId = await featureProvider.addNoteWithContent('note', 'root');
    final first = await featureProvider.saveNoteContent(noteId, 'first');
    final second = await featureProvider.saveNoteContent(
      noteId,
      'second',
      baseRevisionId: 'missing-revision',
    );

    expect(first, isNotNull);
    expect(second, isNotNull);
    expect(featureProvider.getNote(noteId)!.content, 'second');
    expect(second!.parentRevisionId, first!.id);
    expect(featureProvider.getNoteTimeline(noteId), hasLength(3));
  });

  test('ToolCallService manages note folders and moves notes', () async {
    SharedPreferences.setMockInitialValues({});
    final featureProvider = FeatureProvider();
    await featureProvider.load();
    final service = ToolCallService(featureProvider);

    final folderResult = await service.execute(
      const ChatToolCall(
        id: 'folder',
        name: 'save_note_folder',
        arguments: {'title': '资料'},
      ),
      const [],
    );
    final folderId = folderResult['folder']['id'] as String;

    final noteResult = await service.execute(
      ChatToolCall(
        id: 'note',
        name: 'save_note',
        arguments: {'title': '会议', 'content': '内容', 'folderId': folderId},
      ),
      const [],
    );
    final noteId = noteResult['note']['id'] as String;

    expect(noteResult['note']['folderId'], folderId);

    final moveResult = await service.execute(
      ChatToolCall(
        id: 'move',
        name: 'save_note',
        arguments: {'id': noteId, 'folderId': ''},
      ),
      const [],
    );

    expect(moveResult['ok'], isTrue);
    expect(
      (moveResult['note'] as Map<String, dynamic>).containsKey('folderId'),
      isFalse,
    );

    final missingUpdate = await service.execute(
      const ChatToolCall(
        id: 'missing',
        name: 'save_note',
        arguments: {'id': 'missing', 'folderId': ''},
      ),
      const [],
    );

    expect(missingUpdate['ok'], isFalse);
  });

  test('ToolCallService edits notes by line and saves timeline', () async {
    SharedPreferences.setMockInitialValues({});
    final featureProvider = FeatureProvider();
    await featureProvider.load();
    final service = ToolCallService(featureProvider);

    final noteId = await featureProvider.addNoteWithContent(
      'note',
      'alpha\nbeta\ngamma',
    );
    final read = await service.execute(
      ChatToolCall(id: 'read', name: 'read_note', arguments: {'id': noteId}),
      const [],
    );

    final result = await service.execute(
      ChatToolCall(
        id: 'edit',
        name: 'edit_note',
        arguments: {
          'id': noteId,
          'expectedContentHash': read['contentHash'],
          'baseRevisionId': read['currentRevisionId'],
          'edits': [
            {
              'startLine': 2,
              'deleteCount': 1,
              'insertLines': ['BETA', 'delta'],
            },
          ],
        },
      ),
      const [],
    );

    expect(result['ok'], isTrue);
    expect(result['timelineSaved'], isTrue);
    expect(result['revisionId'], isNotNull);
    expect(result['lineDiffSummary'], '+2 / -1 行');
    expect(
      featureProvider.getNote(noteId)!.content,
      'alpha\nBETA\ndelta\ngamma',
    );
    expect(featureProvider.getNoteTimeline(noteId), hasLength(2));
  });

  test(
    'ToolCallService exposes numbered note lines and appends safely',
    () async {
      SharedPreferences.setMockInitialValues({});
      final featureProvider = FeatureProvider();
      await featureProvider.load();
      final service = ToolCallService(featureProvider);

      final noteId = await featureProvider.addNoteWithContent('note', 'a\nb');
      final read = await service.execute(
        ChatToolCall(id: 'read', name: 'read_note', arguments: {'id': noteId}),
        const [],
      );

      expect(read['lineNumberBase'], 1);
      expect(read['appendStartLine'], 3);
      expect(read['numberedLines'], [
        {'line': 1, 'text': 'a'},
        {'line': 2, 'text': 'b'},
      ]);

      final append = await service.execute(
        ChatToolCall(
          id: 'append',
          name: 'edit_note',
          arguments: {
            'id': noteId,
            'expectedContentHash': read['contentHash'],
            'edits': [
              {
                'startLine': read['appendStartLine'],
                'deleteCount': 0,
                'insertLines': ['c'],
                'expectedLines': const [],
              },
            ],
          },
        ),
        const [],
      );

      expect(append['ok'], isTrue);
      expect(featureProvider.getNote(noteId)!.content, 'a\nb\nc');
    },
  );

  test(
    'ToolCallService validates expected note lines before editing',
    () async {
      SharedPreferences.setMockInitialValues({});
      final featureProvider = FeatureProvider();
      await featureProvider.load();
      final service = ToolCallService(featureProvider);

      final noteId = await featureProvider.addNoteWithContent(
        'note',
        'a\nb\nc',
      );
      final read = await service.execute(
        ChatToolCall(id: 'read', name: 'read_note', arguments: {'id': noteId}),
        const [],
      );

      final wrongLine = await service.execute(
        ChatToolCall(
          id: 'wrong-line',
          name: 'edit_note',
          arguments: {
            'id': noteId,
            'expectedContentHash': read['contentHash'],
            'edits': [
              {
                'startLine': 2,
                'deleteCount': 1,
                'expectedLines': ['c'],
                'insertLines': ['B'],
              },
            ],
          },
        ),
        const [],
      );

      expect(wrongLine['ok'], isFalse);
      expect(wrongLine['error'], contains('原文不匹配'));
      expect(featureProvider.getNote(noteId)!.content, 'a\nb\nc');
    },
  );

  test('ToolCallService read_note prefers stronger title matches', () async {
    SharedPreferences.setMockInitialValues({});
    final featureProvider = FeatureProvider();
    await featureProvider.load();
    final service = ToolCallService(featureProvider);

    await featureProvider.addNoteWithContent('项目例会记录', 'older exact');
    await featureProvider.addNoteWithContent('项目例会记录补充', 'newer partial');

    final exact = await service.execute(
      const ChatToolCall(
        id: 'read-exact',
        name: 'read_note',
        arguments: {'title': '项目例会记录'},
      ),
      const [],
    );
    final partial = await service.execute(
      const ChatToolCall(
        id: 'read-partial',
        name: 'read_note',
        arguments: {'query': '补充'},
      ),
      const [],
    );

    expect(exact['ok'], isTrue);
    expect(exact['note']['title'], '项目例会记录');
    expect(exact['note']['content'], 'older exact');
    expect(partial['ok'], isTrue);
    expect(partial['note']['title'], '项目例会记录补充');
  });

  test('ToolCallService searches notes with regex syntax', () async {
    SharedPreferences.setMockInitialValues({});
    final featureProvider = FeatureProvider();
    await featureProvider.load();
    final service = ToolCallService(featureProvider);

    await featureProvider.addNoteWithContent('日志 2026-05-17', 'alpha');
    await featureProvider.addNoteWithContent('随手记', 'beta-42');

    final list = await service.execute(
      const ChatToolCall(
        id: 'list-regex',
        name: 'list_notes',
        arguments: {'query': r'/日志 \d{4}-\d{2}-\d{2}/'},
      ),
      const [],
    );
    final read = await service.execute(
      const ChatToolCall(
        id: 'read-regex',
        name: 'read_note',
        arguments: {'query': r're:beta-\d+'},
      ),
      const [],
    );

    expect(list['ok'], isTrue);
    expect(list['notes'], hasLength(1));
    expect(list['notes'].single['title'], '日志 2026-05-17');
    expect(read['ok'], isTrue);
    expect(read['note']['title'], '随手记');
  });

  test('ToolCallService proposes note edits without saving timeline', () async {
    SharedPreferences.setMockInitialValues({});
    final featureProvider = FeatureProvider();
    await featureProvider.load();
    final service = ToolCallService(featureProvider);

    final noteId = await featureProvider.addNoteWithContent('note', 'a\nb\nc');
    final read = await service.execute(
      ChatToolCall(id: 'read', name: 'read_note', arguments: {'id': noteId}),
      const [],
    );

    final result = await service.execute(
      ChatToolCall(
        id: 'proposal',
        name: 'propose_note_edit',
        arguments: {
          'id': noteId,
          'expectedContentHash': read['contentHash'],
          'baseRevisionId': read['currentRevisionId'],
          'edits': [
            {
              'startLine': 2,
              'deleteCount': 1,
              'insertLines': ['B'],
            },
          ],
        },
      ),
      const [],
    );

    expect(result['ok'], isTrue);
    expect(result['timelineSaved'], isFalse);
    expect(featureProvider.getNote(noteId)!.content, 'a\nb\nc');
    expect(featureProvider.getNoteTimeline(noteId), hasLength(1));
    final proposal = featureProvider.getNoteEditProposal(noteId);
    expect(proposal, isNotNull);
    expect(proposal!.blocks.single.startLine, 2);
    expect(proposal.blocks.single.deletedLines, ['b']);
    expect(proposal.blocks.single.insertLines, ['B']);
  });

  test('Note edit proposals are cleared when note content changes', () async {
    SharedPreferences.setMockInitialValues({});
    final featureProvider = FeatureProvider();
    await featureProvider.load();
    final service = ToolCallService(featureProvider);

    final noteId = await featureProvider.addNoteWithContent('note', 'a\nb');
    final read = await service.execute(
      ChatToolCall(id: 'read', name: 'read_note', arguments: {'id': noteId}),
      const [],
    );
    await service.execute(
      ChatToolCall(
        id: 'proposal',
        name: 'propose_note_edit',
        arguments: {
          'id': noteId,
          'expectedContentHash': read['contentHash'],
          'edits': [
            {
              'startLine': 2,
              'deleteCount': 1,
              'insertLines': ['B'],
            },
          ],
        },
      ),
      const [],
    );
    expect(featureProvider.getNoteEditProposal(noteId), isNotNull);

    await service.execute(
      ChatToolCall(
        id: 'edit',
        name: 'edit_note',
        arguments: {
          'id': noteId,
          'expectedContentHash': read['contentHash'],
          'edits': [
            {
              'startLine': 1,
              'deleteCount': 1,
              'insertLines': ['A'],
            },
          ],
        },
      ),
      const [],
    );

    expect(featureProvider.getNoteEditProposal(noteId), isNull);
  });

  test(
    'ToolCallService rejects stale and overlapping note line edits',
    () async {
      SharedPreferences.setMockInitialValues({});
      final featureProvider = FeatureProvider();
      await featureProvider.load();
      final service = ToolCallService(featureProvider);

      final noteId = await featureProvider.addNoteWithContent(
        'note',
        'a\nb\nc',
      );
      final stale = await service.execute(
        ChatToolCall(
          id: 'stale',
          name: 'edit_note',
          arguments: {
            'id': noteId,
            'expectedContentHash': 'stale',
            'edits': [
              {
                'startLine': 1,
                'deleteCount': 1,
                'insertLines': ['A'],
              },
            ],
          },
        ),
        const [],
      );
      expect(stale['ok'], isFalse);

      final overlap = await service.execute(
        ChatToolCall(
          id: 'overlap',
          name: 'edit_note',
          arguments: {
            'id': noteId,
            'edits': [
              {
                'startLine': 1,
                'deleteCount': 2,
                'insertLines': ['A'],
              },
              {
                'startLine': 2,
                'deleteCount': 1,
                'insertLines': ['B'],
              },
            ],
          },
        ),
        const [],
      );
      expect(overlap['ok'], isFalse);
      expect(featureProvider.getNote(noteId)!.content, 'a\nb\nc');
    },
  );

  test('Storage migration writes note pages and resource index', () async {
    SharedPreferences.setMockInitialValues({});
    final settingsProvider = SettingsProvider();
    final modelProvider = ModelConfigProvider();
    final conversationProvider = ConversationProvider();
    final featureProvider = FeatureProvider();
    await settingsProvider.loadSettings();
    await modelProvider.loadModels();
    await conversationProvider.loadConversations();
    await featureProvider.load();

    final root = await Directory.systemTemp.createTemp('lynai_migration_test_');
    final image = File('${root.path}/legacy.png');
    await image.writeAsBytes([1, 2, 3, 4], flush: true);
    await featureProvider.addNoteWithContent('分页测试', '# 标题\n正文');
    conversationProvider.createConversation(ConversationSettings(modelId: 'm'));
    final conversation = conversationProvider.conversations.first;
    conversationProvider.addMessage(
      conversation.id,
      'user',
      '带图消息',
      images: [
        MessageImage(
          path: image.path,
          name: 'legacy.png',
          size: 4,
          mimeType: 'image/png',
        ),
      ],
    );

    final service = StorageMigrationService(
      settingsProvider: settingsProvider,
      modelConfigProvider: modelProvider,
      conversationProvider: conversationProvider,
      featureProvider: featureProvider,
      rootDirectory: root,
    );
    final report = await service.migrate();

    expect(report.notes, 1);
    expect(report.notePages, 1);
    expect(report.resources, 1);
    final database = sqlite3.open('${root.path}/storage_v2/app.db');
    try {
      expect(
        database.select('SELECT COUNT(*) AS count FROM notes').single['count'],
        1,
      );
      expect(
        database
            .select('SELECT COUNT(*) AS count FROM message_attachments')
            .single['count'],
        1,
      );
      expect(
        database
            .select('SELECT COUNT(*) AS count FROM resources')
            .single['count'],
        1,
      );
    } finally {
      database.dispose();
    }
    final notesJson =
        jsonDecode(
              await File(
                '${root.path}/storage_v2/data/notes.json',
              ).readAsString(),
            )
            as Map<String, dynamic>;
    final page = (notesJson['pages'] as List<dynamic>).single as Map;
    final pageFile = File('${root.path}/storage_v2/${page['relativePath']}');
    expect(await pageFile.exists(), isTrue);
    expect(await pageFile.readAsString(), '# 标题\n正文');
    final resourcesJson =
        jsonDecode(
              await File(
                '${root.path}/storage_v2/data/resources.json',
              ).readAsString(),
            )
            as Map<String, dynamic>;
    final resources = resourcesJson['resources'] as List<dynamic>;
    expect(resources, hasLength(1));
    expect(resources.single['kind'], 'images');
    expect(resources.single['relativePath'], startsWith('assets/images/'));
    final conversationsJson =
        jsonDecode(
              await File(
                '${root.path}/storage_v2/data/conversations.json',
              ).readAsString(),
            )
            as Map<String, dynamic>;
    expect(conversationsJson['messageAttachments'], hasLength(1));
    await root.delete(recursive: true);
  });

  test('Storage migration keeps unsafe note ids inside storage root', () async {
    SharedPreferences.setMockInitialValues({});
    final settingsProvider = SettingsProvider();
    final modelProvider = ModelConfigProvider();
    final conversationProvider = ConversationProvider();
    final featureProvider = FeatureProvider();
    await settingsProvider.loadSettings();
    await modelProvider.loadModels();
    await conversationProvider.loadConversations();
    await featureProvider.load();

    final now = DateTime(2026);
    await featureProvider.replaceFeatureData(
      notes: [
        Note(
          id: '../escape',
          title: 'unsafe',
          content: 'secret',
          createdAt: now,
          updatedAt: now,
        ),
      ],
      noteFolders: const [],
      noteRevisions: const [],
    );

    final root = await Directory.systemTemp.createTemp(
      'lynai_migration_path_test_',
    );
    try {
      await StorageMigrationService(
        settingsProvider: settingsProvider,
        modelConfigProvider: modelProvider,
        conversationProvider: conversationProvider,
        featureProvider: featureProvider,
        rootDirectory: root,
      ).migrate();

      expect(await File('${root.path}/escape/unsafe.md').exists(), isFalse);
      final storage = StorageV2Service(rootDirectory: root);
      final notes = await storage.loadNotes();
      expect(notes.notes.single.id, '../escape');
      expect(notes.pages.single.relativePath, startsWith('notes/'));
      expect(notes.pages.single.relativePath, isNot(contains('..')));
      expect(await storage.readNotePage(notes.pages.single), 'secret');
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('StorageV2Service reads migrated notes and resources', () async {
    SharedPreferences.setMockInitialValues({});
    final settingsProvider = SettingsProvider();
    final modelProvider = ModelConfigProvider();
    final conversationProvider = ConversationProvider();
    final featureProvider = FeatureProvider();
    await settingsProvider.loadSettings();
    await modelProvider.loadModels();
    await conversationProvider.loadConversations();
    await featureProvider.load();

    final root = await Directory.systemTemp.createTemp(
      'lynai_storage_v2_test_',
    );
    final resource = File('${root.path}/legacy.txt');
    await resource.writeAsString('resource', flush: true);
    final noteId = await featureProvider.addNoteWithContent(
      'book',
      'page body',
    );
    conversationProvider.createConversation(ConversationSettings(modelId: 'm'));
    final conversation = conversationProvider.conversations.first;
    conversationProvider.addMessage(
      conversation.id,
      'user',
      'with file',
      images: [
        MessageImage(
          path: resource.path,
          name: 'legacy.txt',
          size: 8,
          mimeType: 'text/plain',
        ),
      ],
    );

    await StorageMigrationService(
      settingsProvider: settingsProvider,
      modelConfigProvider: modelProvider,
      conversationProvider: conversationProvider,
      featureProvider: featureProvider,
      rootDirectory: root,
    ).migrate();

    final storage = StorageV2Service(rootDirectory: root);
    expect(await storage.exists(), isTrue);
    final manifest = await storage.loadManifest();
    expect(manifest['type'], 'lynai.storage_v2');
    final notes = await storage.loadNotes();
    expect(notes.notes.single.id, noteId);
    expect(notes.pagesFor(noteId), hasLength(1));
    expect(await storage.readNotePage(notes.pages.single), 'page body');
    await storage.writeNotePage(notes.pages.single, 'updated body');
    expect(await storage.readNotePage(notes.pages.single), 'updated body');

    final resources = await storage.loadResources();
    expect(resources.single.kind, 'documents');
    final resourceFile = await storage.resourceFile(resources.single);
    expect(resourceFile, isNotNull);
    expect(await resourceFile!.exists(), isTrue);
    await root.delete(recursive: true);
  });

  test('StorageV2Service tolerates orphan storage v2 references', () async {
    final root = await Directory.systemTemp.createTemp(
      'lynai_storage_v2_orphan_test_',
    );
    final dataDir = Directory('${root.path}/storage_v2/data');
    final noteDir = Directory('${root.path}/storage_v2/notes/n1');
    await dataDir.create(recursive: true);
    await noteDir.create(recursive: true);
    await File('${root.path}/storage_v2/manifest.json').writeAsString(
      jsonEncode({'type': 'lynai.storage_v2', 'schemaVersion': 2}),
      flush: true,
    );
    await File(
      '${dataDir.path}/resources.json',
    ).writeAsString(jsonEncode({'resources': []}), flush: true);
    await File('${dataDir.path}/conversations.json').writeAsString(
      jsonEncode({
        'conversations': [
          {
            'id': 'c1',
            'title': 'c',
            'modelId': 'm',
            'settings': {'modelId': 'm'},
            'roleId': 'default',
            'createdAt': DateTime(2026).toIso8601String(),
            'updatedAt': DateTime(2026).toIso8601String(),
          },
        ],
        'messages': [
          {
            'id': 'm1',
            'conversationId': 'c1',
            'role': 'user',
            'content': 'hello',
            'timestamp': DateTime(2026).toIso8601String(),
            'sortOrder': 0,
          },
          {
            'id': 'orphan-message',
            'conversationId': 'missing-conversation',
            'role': 'user',
            'content': 'drop me',
            'timestamp': DateTime(2026).toIso8601String(),
            'sortOrder': 1,
          },
        ],
        'messageAttachments': [
          {
            'id': 'a1',
            'messageId': 'm1',
            'resourceId': 'missing-resource',
            'displayName': 'missing.txt',
            'mimeType': 'text/plain',
            'size': 1,
            'sortOrder': 0,
          },
          {
            'id': 'orphan-attachment',
            'messageId': 'missing-message',
            'displayName': 'drop.txt',
            'mimeType': 'text/plain',
            'size': 1,
            'sortOrder': 1,
          },
        ],
      }),
      flush: true,
    );
    await File('${dataDir.path}/notes.json').writeAsString(
      jsonEncode({
        'folders': [],
        'notes': [
          {
            'id': 'n1',
            'title': 'note',
            'currentPageId': 'p1',
            'createdAt': DateTime(2026).toIso8601String(),
            'updatedAt': DateTime(2026).toIso8601String(),
            'wrap': true,
          },
        ],
        'pages': [
          {
            'id': 'p1',
            'noteId': 'n1',
            'title': 'page',
            'fileName': 'page.md',
            'relativePath': 'notes/n1/page.md',
            'sortOrder': 0,
            'createdAt': DateTime(2026).toIso8601String(),
            'updatedAt': DateTime(2026).toIso8601String(),
          },
          {
            'id': 'orphan-page',
            'noteId': 'missing-note',
            'title': 'drop',
            'fileName': 'drop.md',
            'relativePath': 'notes/missing-note/drop.md',
            'sortOrder': 1,
            'createdAt': DateTime(2026).toIso8601String(),
            'updatedAt': DateTime(2026).toIso8601String(),
          },
        ],
        'revisions': [],
        'editProposals': [],
        'editBlocks': [],
      }),
      flush: true,
    );
    await File('${noteDir.path}/page.md').writeAsString('body', flush: true);
    await File(
      '${dataDir.path}/app_settings.json',
    ).writeAsString(jsonEncode(AppSettings.defaults().toJson()), flush: true);
    await File(
      '${dataDir.path}/model_configs.json',
    ).writeAsString(jsonEncode({'models': []}), flush: true);
    await File(
      '${dataDir.path}/schedules.json',
    ).writeAsString(jsonEncode({'schedules': []}), flush: true);
    await File('${dataDir.path}/todo_lists.json').writeAsString(
      jsonEncode({'todoLists': [], 'todoItems': []}),
      flush: true,
    );

    final storage = StorageV2Service(rootDirectory: root);
    expect(await storage.databaseExists(), isFalse);
    final conversations = await storage.loadDataFile('conversations.json');
    expect(await storage.databaseExists(), isTrue);
    expect(conversations['messages'], hasLength(1));
    final attachments = conversations['messageAttachments'] as List<dynamic>;
    expect(attachments, hasLength(1));
    expect((attachments.single as Map).containsKey('resourceId'), isFalse);

    final notes = await storage.loadNotes();
    expect(notes.notes.single.id, 'n1');
    expect(notes.pages, hasLength(1));
    expect(notes.pages.single.id, 'p1');
    await root.delete(recursive: true);
  });

  test(
    'StorageV2Service resource upsert preserves attachment references',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'lynai_storage_v2_resource_upsert_test_',
      );
      final storageRoot = Directory('${root.path}/storage_v2');
      final dataDir = Directory('${storageRoot.path}/data');
      await dataDir.create(recursive: true);
      await File('${storageRoot.path}/manifest.json').writeAsString(
        jsonEncode({'type': 'lynai.storage_v2', 'schemaVersion': 2}),
        flush: true,
      );
      final resource = {
        'id': 'res_1',
        'kind': 'documents',
        'role': 'message_attachment',
        'originalPath': '/tmp/a.txt',
        'originalName': 'a.txt',
        'relativePath': 'assets/documents/aa/a.txt',
        'mimeType': 'text/plain',
        'size': 1,
        'sha256': 'hash',
        'missing': false,
      };
      await File('${dataDir.path}/resources.json').writeAsString(
        jsonEncode({
          'resources': [resource],
        }),
        flush: true,
      );
      await File('${dataDir.path}/conversations.json').writeAsString(
        jsonEncode({
          'conversations': [
            {
              'id': 'c1',
              'title': 'c',
              'modelId': 'm',
              'settings': {'modelId': 'm'},
              'roleId': 'default',
              'createdAt': DateTime(2026).toIso8601String(),
              'updatedAt': DateTime(2026).toIso8601String(),
            },
          ],
          'messages': [
            {
              'id': 'm1',
              'conversationId': 'c1',
              'role': 'user',
              'content': 'hello',
              'timestamp': DateTime(2026).toIso8601String(),
              'sortOrder': 0,
            },
          ],
          'messageAttachments': [
            {
              'id': 'a1',
              'messageId': 'm1',
              'resourceId': 'res_1',
              'displayName': 'a.txt',
              'mimeType': 'text/plain',
              'size': 1,
              'sortOrder': 0,
            },
          ],
        }),
        flush: true,
      );
      await File(
        '${dataDir.path}/app_settings.json',
      ).writeAsString(jsonEncode(AppSettings.defaults().toJson()), flush: true);
      await File(
        '${dataDir.path}/model_configs.json',
      ).writeAsString(jsonEncode({'models': []}), flush: true);
      await File('${dataDir.path}/notes.json').writeAsString(
        jsonEncode({
          'folders': [],
          'notes': [],
          'pages': [],
          'revisions': [],
          'editProposals': [],
          'editBlocks': [],
        }),
        flush: true,
      );
      await File(
        '${dataDir.path}/schedules.json',
      ).writeAsString(jsonEncode({'schedules': []}), flush: true);
      await File('${dataDir.path}/todo_lists.json').writeAsString(
        jsonEncode({'todoLists': [], 'todoItems': []}),
        flush: true,
      );

      final storage = StorageV2Service(rootDirectory: root);
      await storage.importDataFilesToDatabase(overwrite: true);
      await storage.writeDataFile('resources.json', {
        'resources': [
          {...resource, 'originalName': 'renamed.txt'},
        ],
      });

      final conversations = await storage.loadDataFile('conversations.json');
      final attachments = conversations['messageAttachments'] as List<dynamic>;
      expect(attachments.single['resourceId'], 'res_1');
      final resources = await storage.loadResources();
      expect(resources.single.originalName, 'renamed.txt');
      await root.delete(recursive: true);
    },
  );

  test('FeatureProvider uses storage v2 notes after migration', () async {
    SharedPreferences.setMockInitialValues({});
    final settingsProvider = SettingsProvider();
    final modelProvider = ModelConfigProvider();
    final conversationProvider = ConversationProvider();
    final featureProvider = FeatureProvider();
    await settingsProvider.loadSettings();
    await modelProvider.loadModels();
    await conversationProvider.loadConversations();
    await featureProvider.load();

    final root = await Directory.systemTemp.createTemp(
      'lynai_feature_v2_test_',
    );
    final noteId = await featureProvider.addNoteWithContent('book', 'old body');
    await StorageMigrationService(
      settingsProvider: settingsProvider,
      modelConfigProvider: modelProvider,
      conversationProvider: conversationProvider,
      featureProvider: featureProvider,
      rootDirectory: root,
    ).migrate();

    final loaded = FeatureProvider(
      storageV2: StorageV2Service(rootDirectory: root),
    );
    await loaded.load();
    expect(loaded.usingStorageV2, isTrue);
    expect(loaded.getNote(noteId)!.content, 'old body');
    expect(loaded.notePages(noteId), hasLength(1));

    await loaded.saveNoteContent(noteId, 'new body');
    final page = loaded.activeNotePage(noteId)!;
    final firstPageId = page.id;
    final firstPageRevisionId = loaded.getNote(noteId)!.currentRevisionId;
    final storage = StorageV2Service(rootDirectory: root);
    expect(await storage.readNotePage(page), 'new body');

    final pageId = await loaded.addNotePage(noteId, 'chapter');
    expect(pageId, isNotNull);
    expect(loaded.notePages(noteId), hasLength(2));
    expect(loaded.getNote(noteId)!.content, '# chapter\n');
    final chapterRevision = await loaded.saveNoteContent(
      noteId,
      'chapter body',
    );
    expect(chapterRevision, isNotNull);
    expect(chapterRevision!.id, isNot(firstPageRevisionId));
    final service = ToolCallService(loaded);
    final pagesResult = await service.execute(
      ChatToolCall(
        id: 'pages',
        name: 'list_note_pages',
        arguments: {'id': noteId},
      ),
      const [],
    );
    expect(pagesResult['pages'], hasLength(2));
    final readChapter = await service.execute(
      ChatToolCall(
        id: 'read-page',
        name: 'read_note',
        arguments: {'id': noteId, 'pageId': pageId},
      ),
      const [],
    );
    expect(readChapter['note']['content'], 'chapter body');
    expect(readChapter['note']['pageId'], pageId);
    expect(readChapter['outline'], isA<List>());
    expect(loaded.getNoteTimeline(noteId).map((revision) => revision.id), [
      chapterRevision.id,
      chapterRevision.parentRevisionId,
    ]);
    await loaded.setNoteEditProposal(
      NoteEditProposal(
        id: 'chapter-proposal',
        noteId: noteId,
        pageId: pageId,
        baseRevisionId: chapterRevision.id,
        baseContentHash: 'hash',
        createdAt: DateTime(2026),
        blocks: const [
          NoteEditBlock(
            id: 'block',
            startLine: 1,
            deleteCount: 1,
            deletedLines: ['chapter body'],
            insertLines: ['updated chapter body'],
          ),
        ],
      ),
    );
    expect(loaded.getNoteEditProposal(noteId), isNotNull);
    await loaded.selectNotePage(noteId, firstPageId);
    expect(loaded.getNoteEditProposal(noteId), isNull);
    await loaded.selectNotePage(noteId, pageId!);
    expect(loaded.getNoteEditProposal(noteId)?.id, 'chapter-proposal');
    await loaded.renameNotePage(noteId, pageId, 'chapter renamed');
    expect(loaded.activeNotePage(noteId)!.title, 'chapter renamed');
    final exports = await loaded.notePageExports(noteId);
    expect(exports.map((page) => page.fileName), contains('chapter.md'));
    expect(
      await loaded.noteExportContent(noteId),
      contains('<!-- page: chapter renamed -->'),
    );
    expect(await loaded.deleteNotePage(noteId, pageId), isTrue);
    expect(loaded.notePages(noteId), hasLength(1));
    expect(
      loaded.noteRevisions.map((revision) => revision.id),
      isNot(contains(chapterRevision.id)),
    );
    await loaded.selectNotePage(noteId, firstPageId);
    expect(loaded.getNote(noteId)!.content, 'new body');
    expect(loaded.getNote(noteId)!.currentRevisionId, firstPageRevisionId);
    expect(
      loaded.getNoteTimeline(noteId).map((revision) => revision.id),
      contains(firstPageRevisionId),
    );
    await root.delete(recursive: true);
  });

  test('BackupService round-trips storage v2 note pages', () async {
    SharedPreferences.setMockInitialValues({});
    final sourceSettings = SettingsProvider();
    final sourceModels = ModelConfigProvider();
    final sourceConversations = ConversationProvider();
    final sourceFeatures = FeatureProvider();
    await sourceSettings.loadSettings();
    await sourceModels.loadModels();
    await sourceConversations.loadConversations();
    await sourceFeatures.load();

    final sourceRoot = await Directory.systemTemp.createTemp(
      'lynai_backup_v2_source_',
    );
    final targetRoot = await Directory.systemTemp.createTemp(
      'lynai_backup_v2_target_',
    );
    try {
      await StorageMigrationService(
        settingsProvider: sourceSettings,
        modelConfigProvider: sourceModels,
        conversationProvider: sourceConversations,
        featureProvider: sourceFeatures,
        rootDirectory: sourceRoot,
      ).migrate();

      final source = FeatureProvider(
        storageV2: StorageV2Service(rootDirectory: sourceRoot),
      );
      await source.load();
      final noteId = await source.addNoteWithContent('book', 'first page');
      final firstPageId = source.activeNotePage(noteId)!.id;
      final secondPageId = await source.addNotePage(noteId, 'chapter');
      expect(secondPageId, isNotNull);
      final secondRevision = await source.saveNoteContent(
        noteId,
        'second page',
      );
      expect(secondRevision, isNotNull);

      final archiveFile = await BackupService(
        settingsProvider: sourceSettings,
        modelConfigProvider: sourceModels,
        conversationProvider: sourceConversations,
        featureProvider: source,
        temporaryDirectory: sourceRoot,
        appVersionLoader: () async => '0.0.0-test',
      ).exportZip(BackupSelection({BackupSection.notes}, noteIds: {noteId}));

      SharedPreferences.setMockInitialValues({});
      final targetSettings = SettingsProvider();
      final targetModels = ModelConfigProvider();
      final targetConversations = ConversationProvider();
      final targetFeatures = FeatureProvider();
      await targetSettings.loadSettings();
      await targetModels.loadModels();
      await targetConversations.loadConversations();
      await targetFeatures.load();
      await StorageMigrationService(
        settingsProvider: targetSettings,
        modelConfigProvider: targetModels,
        conversationProvider: targetConversations,
        featureProvider: targetFeatures,
        rootDirectory: targetRoot,
      ).migrate();

      final target = FeatureProvider(
        storageV2: StorageV2Service(rootDirectory: targetRoot),
      );
      await target.load();
      final service = BackupService(
        settingsProvider: targetSettings,
        modelConfigProvider: targetModels,
        conversationProvider: targetConversations,
        featureProvider: target,
      );
      final archive = await service.readZip(archiveFile);
      await service.importArchive(
        archive,
        ImportPlan(
          selection: BackupSelection.fromData(archive.data),
          mode: ImportMode.merge,
        ),
      );

      final reloaded = FeatureProvider(
        storageV2: StorageV2Service(rootDirectory: targetRoot),
      );
      await reloaded.load();
      expect(reloaded.notePages(noteId), hasLength(2));
      expect(reloaded.activeNotePage(noteId)!.id, secondPageId);
      expect(reloaded.getNote(noteId)!.content, 'second page');
      await reloaded.selectNotePage(noteId, firstPageId);
      expect(reloaded.getNote(noteId)!.content, 'first page');
      expect(
        reloaded.noteRevisions.map((revision) => revision.pageId).toSet(),
        contains(secondPageId),
      );
    } finally {
      await sourceRoot.delete(recursive: true);
      await targetRoot.delete(recursive: true);
    }
  });

  test('BackupService handles storage v2 note conflicts', () async {
    SharedPreferences.setMockInitialValues({});
    final sourceSettings = SettingsProvider();
    final sourceModels = ModelConfigProvider();
    final sourceConversations = ConversationProvider();
    final sourceFeatures = FeatureProvider();
    await sourceSettings.loadSettings();
    await sourceModels.loadModels();
    await sourceConversations.loadConversations();
    await sourceFeatures.load();

    final sourceRoot = await Directory.systemTemp.createTemp(
      'lynai_backup_conflict_source_',
    );
    final targetRoot = await Directory.systemTemp.createTemp(
      'lynai_backup_conflict_target_',
    );
    try {
      await StorageMigrationService(
        settingsProvider: sourceSettings,
        modelConfigProvider: sourceModels,
        conversationProvider: sourceConversations,
        featureProvider: sourceFeatures,
        rootDirectory: sourceRoot,
      ).migrate();

      final source = FeatureProvider(
        storageV2: StorageV2Service(rootDirectory: sourceRoot),
      );
      await source.load();
      final noteId = await source.addNoteWithContent('conflict', 'first page');
      final firstPageId = source.activeNotePage(noteId)!.id;
      final secondPageId = await source.addNotePage(noteId, 'second');
      expect(secondPageId, isNotNull);
      await source.saveNoteContent(noteId, 'imported second page');

      final archiveFile = await BackupService(
        settingsProvider: sourceSettings,
        modelConfigProvider: sourceModels,
        conversationProvider: sourceConversations,
        featureProvider: source,
        temporaryDirectory: sourceRoot,
        appVersionLoader: () async => '0.0.0-test',
      ).exportZip(BackupSelection({BackupSection.notes}, noteIds: {noteId}));

      SharedPreferences.setMockInitialValues({});
      final targetSettings = SettingsProvider();
      final targetModels = ModelConfigProvider();
      final targetConversations = ConversationProvider();
      final targetFeatures = FeatureProvider();
      await targetSettings.loadSettings();
      await targetModels.loadModels();
      await targetConversations.loadConversations();
      await targetFeatures.load();
      await StorageMigrationService(
        settingsProvider: targetSettings,
        modelConfigProvider: targetModels,
        conversationProvider: targetConversations,
        featureProvider: targetFeatures,
        rootDirectory: targetRoot,
      ).migrate();

      final target = FeatureProvider(
        storageV2: StorageV2Service(rootDirectory: targetRoot),
      );
      await target.load();
      final service = BackupService(
        settingsProvider: targetSettings,
        modelConfigProvider: targetModels,
        conversationProvider: targetConversations,
        featureProvider: target,
      );
      final archive = await service.readZip(archiveFile);
      final selection = BackupSelection.fromData(archive.data);

      await service.importArchive(
        archive,
        ImportPlan(selection: selection, mode: ImportMode.merge),
      );
      await target.selectNotePage(noteId, firstPageId);
      await target.saveNoteContent(noteId, 'local first page');

      await service.importArchive(
        archive,
        ImportPlan(
          selection: selection,
          mode: ImportMode.merge,
          conflictActions: {
            'notes:note:$noteId': ImportConflictAction.keepBoth,
          },
        ),
      );

      var reloaded = FeatureProvider(
        storageV2: StorageV2Service(rootDirectory: targetRoot),
      );
      await reloaded.load();
      expect(reloaded.notes, hasLength(2));
      expect(reloaded.getNote(noteId)!.content, 'local first page');
      final importedCopy = reloaded.notes.firstWhere(
        (note) => note.id != noteId && note.title == 'conflict',
      );
      expect(reloaded.notePages(importedCopy.id), hasLength(2));
      expect(
        reloaded.getNote(importedCopy.id)!.content,
        'imported second page',
      );
      await reloaded.selectNotePage(
        importedCopy.id,
        reloaded.notePages(importedCopy.id).first.id,
      );
      expect(reloaded.getNote(importedCopy.id)!.content, 'first page');

      await service.importArchive(
        archive,
        ImportPlan(selection: selection, mode: ImportMode.replaceSection),
      );
      reloaded = FeatureProvider(
        storageV2: StorageV2Service(rootDirectory: targetRoot),
      );
      await reloaded.load();
      expect(reloaded.notes.map((note) => note.id), [noteId]);
      expect(reloaded.notePages(noteId), hasLength(2));
      expect(reloaded.getNote(noteId)!.content, 'imported second page');
    } finally {
      await sourceRoot.delete(recursive: true);
      await targetRoot.delete(recursive: true);
    }
  });

  test('BackupService rejects unsafe archive entries', () async {
    final root = await Directory.systemTemp.createTemp(
      'lynai_backup_unsafe_zip_test_',
    );
    final service = BackupService(
      settingsProvider: SettingsProvider(),
      modelConfigProvider: ModelConfigProvider(),
      conversationProvider: ConversationProvider(),
      featureProvider: FeatureProvider(),
    );
    try {
      for (final path in const [
        '../manifest.json',
        '/manifest.json',
        r'notes\manifest.json',
        'C:/manifest.json',
      ]) {
        final archive = Archive()
          ..addFile(ArchiveFile(path, 2, utf8.encode('{}')))
          ..addFile(
            ArchiveFile(
              'manifest.json',
              73,
              utf8.encode(
                '{"type":"lynai.backup","schemaVersion":2,"sections":{}}',
              ),
            ),
          );
        final file = File('${root.path}/${path.hashCode}.zip');
        await file.writeAsBytes(ZipEncoder().encode(archive), flush: true);

        expect(service.readZip(file), throwsA(isA<FormatException>()));
      }
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('Storage v2 note pages protect inactive page revisions', () async {
    SharedPreferences.setMockInitialValues({});
    final settingsProvider = SettingsProvider();
    final modelProvider = ModelConfigProvider();
    final conversationProvider = ConversationProvider();
    final featureProvider = FeatureProvider();
    await settingsProvider.loadSettings();
    await modelProvider.loadModels();
    await conversationProvider.loadConversations();
    await featureProvider.load();

    final root = await Directory.systemTemp.createTemp(
      'lynai_feature_v2_revision_guard_test_',
    );
    try {
      await StorageMigrationService(
        settingsProvider: settingsProvider,
        modelConfigProvider: modelProvider,
        conversationProvider: conversationProvider,
        featureProvider: featureProvider,
        rootDirectory: root,
      ).migrate();

      final loaded = FeatureProvider(
        storageV2: StorageV2Service(rootDirectory: root),
      );
      await loaded.load();
      final noteId = await loaded.addNoteWithContent('book', 'first page');
      final firstPageRevisionId = loaded.getNote(noteId)!.currentRevisionId!;
      final firstPageId = loaded.activeNotePage(noteId)!.id;

      final secondPageId = await loaded.addNotePage(noteId, 'second');
      expect(secondPageId, isNotNull);
      await loaded.saveNoteContent(noteId, 'second page');

      expect(
        loaded.getNoteCurrentRevisionPath(noteId),
        isNot(contains(firstPageRevisionId)),
      );
      expect(
        await loaded.deleteNoteRevision(noteId, firstPageRevisionId),
        isFalse,
      );

      await loaded.selectNotePage(noteId, firstPageId);
      expect(loaded.getNote(noteId)!.currentRevisionId, firstPageRevisionId);
      expect(
        loaded.getNoteTimeline(noteId).map((revision) => revision.id),
        contains(firstPageRevisionId),
      );
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('Storage v2 load clears page revision from another page', () async {
    SharedPreferences.setMockInitialValues({});
    final settingsProvider = SettingsProvider();
    final modelProvider = ModelConfigProvider();
    final conversationProvider = ConversationProvider();
    final featureProvider = FeatureProvider();
    await settingsProvider.loadSettings();
    await modelProvider.loadModels();
    await conversationProvider.loadConversations();
    await featureProvider.load();

    final root = await Directory.systemTemp.createTemp(
      'lynai_feature_v2_page_revision_normalize_test_',
    );
    try {
      await StorageMigrationService(
        settingsProvider: settingsProvider,
        modelConfigProvider: modelProvider,
        conversationProvider: conversationProvider,
        featureProvider: featureProvider,
        rootDirectory: root,
      ).migrate();

      final loaded = FeatureProvider(
        storageV2: StorageV2Service(rootDirectory: root),
      );
      await loaded.load();
      final noteId = await loaded.addNoteWithContent('book', 'first page');
      final firstPageId = loaded.activeNotePage(noteId)!.id;
      final secondPageId = await loaded.addNotePage(noteId, 'second');
      expect(secondPageId, isNotNull);
      final secondRevision = await loaded.saveNoteContent(
        noteId,
        'second page',
      );
      expect(secondRevision, isNotNull);

      final storage = StorageV2Service(rootDirectory: root);
      final data = await storage.loadNotesData();
      final notes = data['notes'] as List<dynamic>;
      final note = notes.single as Map<String, dynamic>;
      note['currentPageId'] = firstPageId;
      note['currentRevisionId'] = secondRevision!.id;
      final pages = data['pages'] as List<dynamic>;
      final firstPage = pages
          .whereType<Map>()
          .cast<Map<String, dynamic>>()
          .singleWhere((page) => page['id'] == firstPageId);
      firstPage['currentRevisionId'] = secondRevision.id;
      await storage.writeNotesData(data);

      final reloaded = FeatureProvider(
        storageV2: StorageV2Service(rootDirectory: root),
      );
      await reloaded.load();

      expect(reloaded.activeNotePage(noteId)!.id, firstPageId);
      expect(reloaded.activeNotePage(noteId)!.currentRevisionId, isNull);
      expect(reloaded.getNote(noteId)!.currentRevisionId, isNull);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('Storage v2 note pages insert after active page and move', () async {
    SharedPreferences.setMockInitialValues({});
    final settingsProvider = SettingsProvider();
    final modelProvider = ModelConfigProvider();
    final conversationProvider = ConversationProvider();
    final featureProvider = FeatureProvider();
    await settingsProvider.loadSettings();
    await modelProvider.loadModels();
    await conversationProvider.loadConversations();
    await featureProvider.load();

    final root = await Directory.systemTemp.createTemp(
      'lynai_feature_v2_page_order_test_',
    );
    try {
      await StorageMigrationService(
        settingsProvider: settingsProvider,
        modelConfigProvider: modelProvider,
        conversationProvider: conversationProvider,
        featureProvider: featureProvider,
        rootDirectory: root,
      ).migrate();

      final loaded = FeatureProvider(
        storageV2: StorageV2Service(rootDirectory: root),
      );
      await loaded.load();
      final noteId = await loaded.addNoteWithContent('book', 'first');
      final firstPageId = loaded.activeNotePage(noteId)!.id;
      final secondPageId = await loaded.addNotePage(noteId, 'second');
      expect(secondPageId, isNotNull);
      await loaded.selectNotePage(noteId, firstPageId);
      final insertedPageId = await loaded.addNotePage(noteId, 'inserted');
      expect(insertedPageId, isNotNull);

      expect(loaded.notePages(noteId).map((page) => page.id), [
        firstPageId,
        insertedPageId,
        secondPageId,
      ]);
      expect(loaded.notePages(noteId).map((page) => page.sortOrder), [0, 1, 2]);

      expect(await loaded.moveNotePage(noteId, secondPageId!, -1), isTrue);
      expect(loaded.notePages(noteId).map((page) => page.id), [
        firstPageId,
        secondPageId,
        insertedPageId,
      ]);
      expect(await loaded.moveNotePage(noteId, firstPageId, -1), isFalse);
      await loaded.selectNotePage(noteId, 'missing-page');
      expect(loaded.activeNotePage(noteId)!.id, insertedPageId);
      await loaded.selectNotePage(noteId, secondPageId);
      expect(await loaded.deleteNotePage(noteId, secondPageId), isTrue);
      expect(loaded.activeNotePage(noteId)!.id, insertedPageId);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('Storage v2 preserves note folder and note order', () async {
    SharedPreferences.setMockInitialValues({});
    final settingsProvider = SettingsProvider();
    final modelProvider = ModelConfigProvider();
    final conversationProvider = ConversationProvider();
    final featureProvider = FeatureProvider();
    await settingsProvider.loadSettings();
    await modelProvider.loadModels();
    await conversationProvider.loadConversations();
    await featureProvider.load();

    final root = await Directory.systemTemp.createTemp(
      'lynai_feature_v2_note_order_test_',
    );
    try {
      await StorageMigrationService(
        settingsProvider: settingsProvider,
        modelConfigProvider: modelProvider,
        conversationProvider: conversationProvider,
        featureProvider: featureProvider,
        rootDirectory: root,
      ).migrate();

      final loaded = FeatureProvider(
        storageV2: StorageV2Service(rootDirectory: root),
      );
      await loaded.load();
      final firstFolderId = await loaded.addNoteFolder('first folder');
      final secondFolderId = await loaded.addNoteFolder('second folder');
      await loaded.reorderNoteFolders(1, 0);
      final firstNoteId = await loaded.addNoteWithContent('first note', 'one');
      final secondNoteId = await loaded.addNoteWithContent(
        'second note',
        'two',
      );
      await loaded.reorderNotesInFolder(null, 1, 0);

      expect(loaded.noteFolders.map((folder) => folder.id), [
        firstFolderId,
        secondFolderId,
      ]);
      expect(loaded.notes.map((note) => note.id), [firstNoteId, secondNoteId]);

      final reloaded = FeatureProvider(
        storageV2: StorageV2Service(rootDirectory: root),
      );
      await reloaded.load();

      expect(reloaded.noteFolders.map((folder) => folder.id), [
        firstFolderId,
        secondFolderId,
      ]);
      expect(reloaded.notes.map((note) => note.id), [
        firstNoteId,
        secondNoteId,
      ]);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('Storage v2 migrates note order columns from schema 2', () async {
    final root = await Directory.systemTemp.createTemp(
      'lynai_feature_v2_schema3_migration_test_',
    );
    try {
      final storageRoot = Directory('${root.path}/storage_v2');
      await storageRoot.create(recursive: true);
      await File('${storageRoot.path}/manifest.json').writeAsString('{}');
      final db = sqlite3.open('${storageRoot.path}/app.db');
      try {
        db.execute('''
CREATE TABLE storage_meta (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
CREATE TABLE note_folders (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE TABLE notes (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  folder_id TEXT,
  current_revision_id TEXT,
  current_page_id TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  wrap INTEGER NOT NULL
);
PRAGMA user_version = 2;
''');
      } finally {
        db.dispose();
      }

      final storage = StorageV2Service(rootDirectory: root);
      final data = await storage.loadNotesData();

      expect(data['folders'], isEmpty);
      expect(data['notes'], isEmpty);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('Storage v2 schema 3 order migration is idempotent', () async {
    final root = await Directory.systemTemp.createTemp(
      'lynai_feature_v2_schema3_partial_test_',
    );
    try {
      final storageRoot = Directory('${root.path}/storage_v2');
      await storageRoot.create(recursive: true);
      await File('${storageRoot.path}/manifest.json').writeAsString('{}');
      final db = sqlite3.open('${storageRoot.path}/app.db');
      try {
        db.execute('''
CREATE TABLE storage_meta (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
CREATE TABLE note_folders (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE notes (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  folder_id TEXT,
  current_revision_id TEXT,
  current_page_id TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  wrap INTEGER NOT NULL
);
PRAGMA user_version = 2;
''');
      } finally {
        db.dispose();
      }

      final storage = StorageV2Service(rootDirectory: root);
      final data = await storage.loadNotesData();

      expect(data['folders'], isEmpty);
      expect(data['notes'], isEmpty);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('FeatureProvider batch replace persists storage v2 notes', () async {
    SharedPreferences.setMockInitialValues({});
    final settingsProvider = SettingsProvider();
    final modelProvider = ModelConfigProvider();
    final conversationProvider = ConversationProvider();
    final featureProvider = FeatureProvider();
    await settingsProvider.loadSettings();
    await modelProvider.loadModels();
    await conversationProvider.loadConversations();
    await featureProvider.load();

    final root = await Directory.systemTemp.createTemp(
      'lynai_feature_v2_replace_test_',
    );
    await StorageMigrationService(
      settingsProvider: settingsProvider,
      modelConfigProvider: modelProvider,
      conversationProvider: conversationProvider,
      featureProvider: featureProvider,
      rootDirectory: root,
    ).migrate();

    final loaded = FeatureProvider(
      storageV2: StorageV2Service(rootDirectory: root),
    );
    await loaded.load();
    final now = DateTime(2026, 1, 2, 3, 4, 5);
    await loaded.replaceFeatureData(
      notes: [
        Note(
          id: 'imported-note',
          title: 'imported',
          content: 'imported body',
          createdAt: now,
          updatedAt: now,
        ),
      ],
      noteFolders: const [],
      noteRevisions: const [],
    );

    final reloaded = FeatureProvider(
      storageV2: StorageV2Service(rootDirectory: root),
    );
    await reloaded.load();
    expect(reloaded.usingStorageV2, isTrue);
    expect(reloaded.getNote('imported-note')!.content, 'imported body');
    expect(reloaded.notePages('imported-note'), hasLength(1));
    expect(
      await StorageV2Service(
        rootDirectory: root,
      ).readNotePage(reloaded.activeNotePage('imported-note')!),
      'imported body',
    );
    await root.delete(recursive: true);
  });

  test(
    'Migration removes legacy large data and providers load storage v2',
    () async {
      SharedPreferences.setMockInitialValues({});
      final settingsProvider = SettingsProvider();
      final modelProvider = ModelConfigProvider();
      final conversationProvider = ConversationProvider();
      final featureProvider = FeatureProvider();
      await settingsProvider.loadSettings();
      await modelProvider.loadModels();
      await conversationProvider.loadConversations();
      await featureProvider.load();

      modelProvider.addModel(
        ModelConfig(
          id: 'm1',
          name: 'Provider',
          endpoint: 'https://example.com',
          apiKey: 'key',
          modelName: 'model-a',
          apiType: 'openai',
          priority: 0,
        ),
      );
      conversationProvider.createConversation(
        ConversationSettings(modelId: 'm1'),
      );
      final conversationId = conversationProvider.conversations.first.id;
      conversationProvider.addMessage(conversationId, 'user', 'hello');
      await featureProvider.addSchedule(
        'demo',
        DateTime(2026, 1, 1, 9),
        DateTime(2026, 1, 1, 10),
      );
      await featureProvider.addTodoListWithItems('todos', [
        const TodoItem(id: 't1', text: 'task'),
      ]);
      await featureProvider.addNoteWithContent('note', 'body');

      final root = await Directory.systemTemp.createTemp('lynai_full_v2_test_');
      await StorageMigrationService(
        settingsProvider: settingsProvider,
        modelConfigProvider: modelProvider,
        conversationProvider: conversationProvider,
        featureProvider: featureProvider,
        rootDirectory: root,
      ).migrate();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('conversations'), isNull);
      expect(prefs.getString('notes'), isNull);
      expect(prefs.getString('schedule_items'), isNull);
      expect(prefs.getString('todo_lists'), isNull);
      expect(prefs.getString('model_configs'), isNull);

      final loadedConversations = ConversationProvider(
        storageV2: StorageV2Service(rootDirectory: root),
      );
      final loadedModels = ModelConfigProvider(
        storageV2: StorageV2Service(rootDirectory: root),
      );
      final loadedFeatures = FeatureProvider(
        storageV2: StorageV2Service(rootDirectory: root),
      );
      await loadedConversations.loadConversations();
      await loadedModels.loadModels();
      await loadedFeatures.load();

      expect(loadedConversations.usingStorageV2, isTrue);
      expect(
        loadedConversations.conversations.single.messages.single.content,
        'hello',
      );
      expect(loadedModels.usingStorageV2, isTrue);
      expect(loadedModels.models.single.id, 'm1');
      expect(loadedFeatures.usingStorageV2, isTrue);
      expect(loadedFeatures.schedules.single.title, 'demo');
      expect(loadedFeatures.todoLists.single.items.single.text, 'task');
      expect(loadedFeatures.notes.single.content, 'body');
      await root.delete(recursive: true);
    },
  );

  test(
    'ConversationProvider stores new storage v2 attachments as resources',
    () async {
      SharedPreferences.setMockInitialValues({});
      final settingsProvider = SettingsProvider();
      final modelProvider = ModelConfigProvider();
      final conversationProvider = ConversationProvider();
      final featureProvider = FeatureProvider();
      await settingsProvider.loadSettings();
      await modelProvider.loadModels();
      await conversationProvider.loadConversations();
      await featureProvider.load();

      final root = await Directory.systemTemp.createTemp(
        'lynai_conversation_v2_attachment_test_',
      );
      await StorageMigrationService(
        settingsProvider: settingsProvider,
        modelConfigProvider: modelProvider,
        conversationProvider: conversationProvider,
        featureProvider: featureProvider,
        rootDirectory: root,
      ).migrate();

      final attachment = File('${root.path}/new.txt');
      await attachment.writeAsString('new attachment', flush: true);
      final loaded = ConversationProvider(
        storageV2: StorageV2Service(rootDirectory: root),
      );
      await loaded.loadConversations();
      final conversationId = loaded.createConversation(
        ConversationSettings(modelId: 'm'),
      );
      loaded.addMessage(
        conversationId,
        'user',
        'with new file',
        images: [
          MessageImage(
            path: attachment.path,
            name: 'new.txt',
            size: await attachment.length(),
            mimeType: 'text/plain',
          ),
        ],
      );
      await loaded.replaceConversations(loaded.conversations);

      final resourcesJson =
          jsonDecode(
                await File(
                  '${root.path}/storage_v2/data/resources.json',
                ).readAsString(),
              )
              as Map<String, dynamic>;
      final resources = resourcesJson['resources'] as List<dynamic>;
      expect(resources, hasLength(1));
      expect(resources.single['kind'], 'documents');
      expect(resources.single['relativePath'], startsWith('assets/documents/'));

      final conversationsJson =
          jsonDecode(
                await File(
                  '${root.path}/storage_v2/data/conversations.json',
                ).readAsString(),
              )
              as Map<String, dynamic>;
      final attachments =
          conversationsJson['messageAttachments'] as List<dynamic>;
      expect(attachments.single['resourceId'], resources.single['id']);
      expect(attachments.single.containsKey('path'), isFalse);

      final reloaded = ConversationProvider(
        storageV2: StorageV2Service(rootDirectory: root),
      );
      await reloaded.loadConversations();
      final image = reloaded.conversations.single.messages.single.images.single;
      expect(image.path, contains('/storage_v2/assets/documents/'));
      expect(await File(image.path).readAsString(), 'new attachment');
      await root.delete(recursive: true);
    },
  );

  test(
    'Migration restores existing storage v2 when activation fails',
    () async {
      SharedPreferences.setMockInitialValues({});
      final settingsProvider = SettingsProvider();
      final modelProvider = ModelConfigProvider();
      final conversationProvider = ConversationProvider();
      final featureProvider = FeatureProvider();
      await settingsProvider.loadSettings();
      await modelProvider.loadModels();
      await conversationProvider.loadConversations();
      await featureProvider.load();

      final root = await Directory.systemTemp.createTemp(
        'lynai_migration_restore_test_',
      );
      try {
        final existingStorage = Directory('${root.path}/storage_v2');
        await existingStorage.create(recursive: true);
        final marker = File('${existingStorage.path}/marker.txt');
        await marker.writeAsString('old storage');

        await expectLater(
          StorageMigrationService(
            settingsProvider: settingsProvider,
            modelConfigProvider: modelProvider,
            conversationProvider: conversationProvider,
            featureProvider: featureProvider,
            rootDirectory: root,
            afterActivateStorageForTest: () async => throw StateError('boom'),
          ).migrate(force: true),
          throwsA(isA<StateError>()),
        );

        expect(await marker.exists(), isTrue);
        expect(await marker.readAsString(), 'old storage');
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('storage_migration_status'), 'failed');
      } finally {
        await root.delete(recursive: true);
      }
    },
  );

  test('Markdown parser accepts nbsp-indented paragraph as paragraph', () {
    final document = md.Document(extensionSet: md.ExtensionSet.gitHubFlavored);
    final nbsp = String.fromCharCode(0x00A0);

    final nodes = document.parseLines(['$nbsp$nbsp$nbsp$nbsp普通段落']);

    expect(nodes.single, isA<md.Element>());
    expect((nodes.single as md.Element).tag, 'p');
  });
}
