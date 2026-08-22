import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/composer_reference.dart';
import 'package:lynai/models/conversation.dart';
import 'package:lynai/models/conversation_plugin_artifact.dart';
import 'package:lynai/models/message.dart';
import 'package:lynai/providers/conversation_provider.dart';
import 'package:lynai/services/storage_v2_service.dart';

void main() {
  test(
    'full conversation replacement preserves visible and model context content',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'lynai_conversation_repository_test_',
      );
      final savedStorage = StorageV2Service(rootDirectory: root);
      try {
        final saved = ConversationProvider(storageV2: savedStorage);
        final timestamp = DateTime.utc(2026, 1, 1);

        await saved.replaceConversations([
          Conversation(
            id: 'conversation-1',
            title: 'OCR conversation',
            messages: [
              Message(
                id: 'message-1',
                role: 'user',
                content: 'visible attachment prompt',
                modelContextContent:
                    'visible attachment prompt\n[OCR result]\nhidden text',
                timestamp: timestamp,
              ),
            ],
            modelId: 'model-1',
            createdAt: timestamp,
            updatedAt: timestamp,
          ),
        ]);
        await savedStorage.close();

        final reloadedStorage = StorageV2Service(rootDirectory: root);
        try {
          final reloaded = ConversationProvider(storageV2: reloadedStorage);
          await reloaded.loadConversations();

          final message = reloaded.conversations.single.messages.single;
          expect(message.content, 'visible attachment prompt');
          expect(
            message.modelContextContent,
            'visible attachment prompt\n[OCR result]\nhidden text',
          );
        } finally {
          await reloadedStorage.close();
        }
      } finally {
        await savedStorage.close();
        if (await root.exists()) await root.delete(recursive: true);
      }
    },
  );

  test('composer segments survive a save/load round trip', () async {
    final root = await Directory.systemTemp.createTemp(
      'lynai_conversation_segments_test_',
    );
    final savedStorage = StorageV2Service(rootDirectory: root);
    try {
      final saved = ConversationProvider(storageV2: savedStorage);
      final timestamp = DateTime.utc(2026, 1, 1);
      await saved.replaceConversations([
        Conversation(
          id: 'conversation-1',
          title: 'reference conversation',
          messages: [
            Message(
              id: 'message-1',
              role: 'user',
              content: '总结 @项目规划',
              composerSegments: [
                const ComposerTextSegment('总结 '),
                ComposerReferenceSegment(
                  const ComposerReference(
                    localId: 'r1',
                    type: ComposerReferenceType.note,
                    id: 'note-1',
                    title: '项目规划',
                  ),
                ),
              ],
              timestamp: timestamp,
            ),
          ],
          modelId: 'model-1',
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
      ]);
      await savedStorage.close();

      final reloadedStorage = StorageV2Service(rootDirectory: root);
      try {
        final reloaded = ConversationProvider(storageV2: reloadedStorage);
        await reloaded.loadConversations();

        final message = reloaded.conversations.single.messages.single;
        expect(message.composerSegments, hasLength(2));
        final reference =
            message.composerSegments.last as ComposerReferenceSegment;
        expect(reference.reference.id, 'note-1');
        expect(reference.reference.title, '项目规划');
      } finally {
        await reloadedStorage.close();
      }
    } finally {
      await savedStorage.close();
      if (await root.exists()) await root.delete(recursive: true);
    }
  });

  test(
    'plugin workspace and artifacts survive a save/load round trip',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'lynai_conversation_plugin_workspace_test_',
      );
      final savedStorage = StorageV2Service(rootDirectory: root);
      try {
        final saved = ConversationProvider(storageV2: savedStorage);
        final timestamp = DateTime.utc(2026, 1, 1);
        await saved.replaceConversations([
          Conversation(
            id: 'conversation-1',
            title: 'plugin workspace conversation',
            messages: const [],
            modelId: 'model-1',
            pluginWorkspaceId: 'gen-plugin',
            pluginArtifacts: [
              ConversationPluginArtifact(
                pluginId: 'gen-plugin',
                assistantMessageId: 'message-1',
                createdAt: timestamp,
                writtenFiles: const ['plugin.json', 'main.lua'],
              ),
            ],
            createdAt: timestamp,
            updatedAt: timestamp,
          ),
        ]);
        await savedStorage.close();

        final reloadedStorage = StorageV2Service(rootDirectory: root);
        try {
          final reloaded = ConversationProvider(storageV2: reloadedStorage);
          await reloaded.loadConversations();

          final conversation = reloaded.conversations.single;
          expect(conversation.pluginWorkspaceId, 'gen-plugin');
          expect(conversation.pluginArtifacts, hasLength(1));
          expect(conversation.pluginArtifacts.single.pluginId, 'gen-plugin');
          expect(conversation.pluginArtifacts.single.writtenFiles, [
            'plugin.json',
            'main.lua',
          ]);
        } finally {
          await reloadedStorage.close();
        }
      } finally {
        await savedStorage.close();
        if (await root.exists()) await root.delete(recursive: true);
      }
    },
  );

  test('message updates preserve plugin workspace and artifacts', () async {
    final root = await Directory.systemTemp.createTemp(
      'lynai_conversation_workspace_preserve_',
    );
    final storage = StorageV2Service(rootDirectory: root);
    try {
      final provider = ConversationProvider(storageV2: storage);
      final timestamp = DateTime.utc(2026, 1, 1);
      final conversationId = provider.createConversation(
        ConversationSettings(modelId: 'model-1'),
      );
      provider.setPluginWorkspace(conversationId, 'gen-plugin');
      provider.addPluginArtifact(
        conversationId,
        ConversationPluginArtifact(
          pluginId: 'gen-plugin',
          createdAt: timestamp,
        ),
      );
      provider.addMessage(conversationId, 'user', '继续完善');
      provider.updateLastMessage(conversationId, '已完善', save: false);
      provider.updateConversationSettings(
        conversationId,
        ConversationSettings(modelId: 'model-2'),
      );

      final conversation = provider.getConversation(conversationId)!;
      expect(conversation.pluginWorkspaceId, 'gen-plugin');
      expect(conversation.pluginArtifacts, hasLength(1));
      expect(conversation.settings.modelId, 'model-2');
    } finally {
      await storage.close();
      if (await root.exists()) await root.delete(recursive: true);
    }
  });

  test('ensurePluginConversation reuses the bound conversation', () async {
    final root = await Directory.systemTemp.createTemp(
      'lynai_conversation_workspace_ensure_',
    );
    final storage = StorageV2Service(rootDirectory: root);
    try {
      final provider = ConversationProvider(storageV2: storage);
      final first = provider.ensurePluginConversation(
        pluginId: 'gen-plugin',
        pluginName: '生成的插件',
        settings: ConversationSettings(modelId: 'model-1'),
      );
      final second = provider.ensurePluginConversation(
        pluginId: 'gen-plugin',
        pluginName: '生成的插件',
        settings: ConversationSettings(modelId: 'model-1'),
      );
      expect(second, first);
      final conversation = provider.getConversation(first)!;
      expect(conversation.pluginWorkspaceId, 'gen-plugin');
      expect(conversation.title, '插件 · 生成的插件');
      expect(conversation.settings.agentEnabled, isTrue);
    } finally {
      await storage.close();
      if (await root.exists()) await root.delete(recursive: true);
    }
  });
}
