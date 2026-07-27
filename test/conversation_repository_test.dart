import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/conversation.dart';
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
}
