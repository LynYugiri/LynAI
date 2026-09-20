import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/composer_reference.dart';
import 'package:lynai/models/conversation.dart';
import 'package:lynai/models/message.dart';
import 'package:lynai/providers/conversation_provider.dart';

import 'support/memory_repositories.dart';

void main() {
  group('ConversationProvider.restoreWithdrawnMessages', () {
    test('前缀未变时把撤回的消息尾部原样放回', () {
      final provider = memoryConversationProvider();
      final cid = _seed(provider);
      final removed = provider.getConversation(cid)!.messages.sublist(2);

      provider.deleteMessagesFrom(cid, removed.first.id);
      expect(provider.getConversation(cid)!.messages.map((m) => m.content), [
        '第一条',
        '回复一',
      ]);

      final restored = provider.restoreWithdrawnMessages(
        cid,
        removed,
        expectedPrefixLength: 2,
      );

      expect(restored, isTrue);
      expect(provider.getConversation(cid)!.messages.map((m) => m.content), [
        '第一条',
        '回复一',
        '第二条',
        '回复二',
      ]);
      // 恢复的是同一批消息对象，内容、附件和引用片段都不能被改写。
      expect(provider.getConversation(cid)!.messages[2].content, '第二条');
      expect(
        provider.getConversation(cid)!.messages[1].modelContextContent,
        '回复上下文',
      );
    });

    test('撤回后对话又发生变化时拒绝恢复', () {
      final provider = memoryConversationProvider();
      final cid = _seed(provider);
      final removed = provider.getConversation(cid)!.messages.sublist(2);
      provider.deleteMessagesFrom(cid, removed.first.id);
      provider.addMessage(cid, 'user', '新的一条');

      final restored = provider.restoreWithdrawnMessages(
        cid,
        removed,
        expectedPrefixLength: 2,
      );

      expect(restored, isFalse);
      expect(provider.getConversation(cid)!.messages.map((m) => m.content), [
        '第一条',
        '回复一',
        '新的一条',
      ]);
    });

    test('对话不存在或尾部为空时不恢复', () {
      final provider = memoryConversationProvider();
      final cid = _seed(provider);

      expect(
        provider.restoreWithdrawnMessages(
          'missing',
          provider.getConversation(cid)!.messages,
          expectedPrefixLength: 0,
        ),
        isFalse,
      );
      expect(
        provider.restoreWithdrawnMessages(
          cid,
          const [],
          expectedPrefixLength: 0,
        ),
        isFalse,
      );
    });
  });
}

String _seed(ConversationProvider provider) {
  return provider.createConversationWithMessages(
    ConversationSettings(modelId: 'model'),
    messages: [
      (
        role: 'user',
        content: '第一条',
        images: const <MessageImage>[],
        composerSegments: const <ComposerSegment>[],
      ),
      (
        role: 'assistant',
        content: '回复一',
        images: const <MessageImage>[],
        composerSegments: const <ComposerSegment>[],
      ),
      (
        role: 'user',
        content: '第二条',
        images: const <MessageImage>[],
        composerSegments: const <ComposerSegment>[],
      ),
      (
        role: 'assistant',
        content: '回复二',
        images: const <MessageImage>[],
        composerSegments: const <ComposerSegment>[],
      ),
    ],
    modelContextByIndex: const {1: '回复上下文'},
  );
}
