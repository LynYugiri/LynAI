import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/conversation.dart';
import 'package:lynai/models/message.dart';
import 'package:lynai/services/agent_resource_service.dart';
import 'package:lynai/services/attachment_read_service.dart';
import 'package:lynai/services/storage_v2_service.dart';

void main() {
  late Directory root;
  late Directory sourceRoot;
  late StorageV2Service storage;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('lynai_attachment_read_test_');
    sourceRoot = await Directory.systemTemp.createTemp(
      'lynai_attachment_read_source_test_',
    );
    storage = StorageV2Service(rootDirectory: root);
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
    if (await sourceRoot.exists()) await sourceRoot.delete(recursive: true);
  });

  test(
    'resolves an attachment only through conversation/message IDs and index',
    () async {
      final source = File('${sourceRoot.path}/readme.txt');
      await source.writeAsString('attachment body', flush: true);
      final resource = await storage.importResourceFile(
        source.path,
        originalName: 'readme.txt',
        mimeType: 'text/plain',
        role: 'message_attachment',
      );
      final path = await storage.resourcePath(resource);
      final conversation = _conversation(
        MessageImage(
          path: path!,
          name: 'readme.txt',
          size: resource.size,
          mimeType: 'text/plain',
        ),
      );
      final service = AttachmentReadService(
        storage: storage,
        findConversation: (id) async =>
            id == conversation.id ? conversation : null,
      );

      final result = await service.readText(
        conversationId: 'conversation-1',
        messageId: 'message-1',
        attachmentIndex: 0,
      );

      expect(result.text, 'attachment body');
      expect(result.metadata.id, resource.id);
    },
  );

  test(
    'rejects out-of-range indexes and attachment/resource MIME mismatch',
    () async {
      final source = File('${sourceRoot.path}/readme.txt');
      await source.writeAsString('attachment body', flush: true);
      final resource = await storage.importResourceFile(
        source.path,
        originalName: 'readme.txt',
        mimeType: 'text/plain',
        role: 'message_attachment',
      );
      final conversation = _conversation(
        MessageImage(
          path: (await storage.resourcePath(resource))!,
          name: 'readme.txt',
          size: resource.size,
          mimeType: 'application/json',
        ),
      );
      final service = AttachmentReadService(
        storage: storage,
        findConversation: (_) async => conversation,
      );

      await expectLater(
        service.metadata(
          conversationId: conversation.id,
          messageId: 'message-1',
          attachmentIndex: 1,
        ),
        throwsA(
          isA<AgentResourceException>().having(
            (error) => error.code,
            'code',
            'attachment_not_found',
          ),
        ),
      );
      await expectLater(
        service.metadata(
          conversationId: conversation.id,
          messageId: 'message-1',
          attachmentIndex: 0,
        ),
        throwsA(
          isA<AgentResourceException>().having(
            (error) => error.code,
            'code',
            'mime_mismatch',
          ),
        ),
      );
    },
  );
}

Conversation _conversation(MessageImage image) {
  final timestamp = DateTime(2026);
  return Conversation(
    id: 'conversation-1',
    title: 'Test',
    messages: [
      Message(
        id: 'message-1',
        role: 'user',
        content: '',
        images: [image],
        timestamp: timestamp,
      ),
    ],
    modelId: 'model-1',
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}
