import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lynai/models/app_settings.dart';
import 'package:lynai/models/conversation.dart';
import 'package:lynai/models/message.dart';
import 'package:lynai/models/model_config.dart';
import 'package:lynai/models/note.dart';
import 'package:lynai/providers/conversation_provider.dart';
import 'package:lynai/providers/feature_provider.dart';
import 'package:lynai/providers/model_config_provider.dart';
import 'package:lynai/services/tool_call_service.dart';
import 'package:markdown/markdown.dart' as md;

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

  test('ConversationSettings reads legacy imagePrompt key', () {
    final settings = ConversationSettings.fromJson({
      'modelId': 'chat-1',
      'imagePrompt': 'legacy prompt',
    });

    expect(settings.imageRecognitionPrompt, 'legacy prompt');
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

  test('Markdown parser accepts nbsp-indented paragraph as paragraph', () {
    final document = md.Document(extensionSet: md.ExtensionSet.gitHubFlavored);
    final nbsp = String.fromCharCode(0x00A0);

    final nodes = document.parseLines(['$nbsp$nbsp$nbsp$nbsp普通段落']);

    expect(nodes.single, isA<md.Element>());
    expect((nodes.single as md.Element).tag, 'p');
  });
}
