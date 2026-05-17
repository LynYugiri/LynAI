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

  test('Markdown parser accepts nbsp-indented paragraph as paragraph', () {
    final document = md.Document(extensionSet: md.ExtensionSet.gitHubFlavored);
    final nbsp = String.fromCharCode(0x00A0);

    final nodes = document.parseLines(['$nbsp$nbsp$nbsp$nbsp普通段落']);

    expect(nodes.single, isA<md.Element>());
    expect((nodes.single as md.Element).tag, 'p');
  });
}
