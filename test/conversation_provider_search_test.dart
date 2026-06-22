import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/conversation.dart';
import 'package:lynai/models/message.dart';
import 'package:lynai/providers/conversation_provider.dart';

import 'support/memory_repositories.dart';

void main() {
  group('ConversationProvider searchConversations', () {
    test('returns all conversations for empty query', () {
      final provider = memoryConversationProvider();
      _createConversation(provider, titleText: 'Alpha');
      _createConversation(provider, titleText: 'Beta');

      final results = provider.searchConversations('');

      expect(results, hasLength(2));
      expect(
        results.every(
          (result) => result.matchType == ConversationSearchMatchType.none,
        ),
        isTrue,
      );
    });

    test('matches title and reports highlighted ranges', () {
      final provider = memoryConversationProvider();
      _createConversation(provider, titleText: 'The Needle title');

      final results = provider.searchConversations('needle');

      expect(results, hasLength(1));
      expect(results.single.matchType, ConversationSearchMatchType.title);
      expect(results.single.snippet, 'The Needle title');
      expect(
        results.single.snippetRanges.map((range) => [range.start, range.end]),
        [
          [4, 10],
        ],
      );
    });

    test('matches newest message content before older content', () {
      final provider = memoryConversationProvider();
      _createConversation(
        provider,
        titleText: 'Question',
        messages: [
          (
            role: 'user',
            content: 'plain question',
            images: const <MessageImage>[],
          ),
          (
            role: 'assistant',
            content: 'old needle content',
            images: const <MessageImage>[],
          ),
          (role: 'user', content: 'follow up', images: const <MessageImage>[]),
          (
            role: 'assistant',
            content: 'new needle answer',
            images: const <MessageImage>[],
          ),
        ],
      );

      final results = provider.searchConversations('needle');

      expect(results, hasLength(1));
      expect(results.single.matchType, ConversationSearchMatchType.message);
      expect(results.single.snippet, contains('new needle answer'));
      expect(results.single.snippet, isNot(contains('old needle content')));
    });

    test('matches attachment names', () {
      final provider = memoryConversationProvider();
      _createConversation(
        provider,
        titleText: '',
        messages: [
          (
            role: 'user',
            content: 'plain attachment message',
            images: const [
              MessageImage(
                path: '/tmp/file.pdf',
                name: 'needle-report.pdf',
                size: 12,
              ),
            ],
          ),
        ],
      );

      final results = provider.searchConversations('report');

      expect(results, hasLength(1));
      expect(results.single.matchType, ConversationSearchMatchType.attachment);
      expect(results.single.snippet, 'needle-report.pdf');
    });

    test('supports regex search and ignores invalid regex', () {
      final provider = memoryConversationProvider();
      _createConversation(provider, titleText: 'abc-123');

      expect(provider.searchConversations(r're:\d+'), hasLength(1));
      expect(provider.searchConversations('re:['), isEmpty);
    });
  });
}

String _createConversation(
  ConversationProvider provider, {
  required String titleText,
  List<({String role, String content, List<MessageImage> images})>? messages,
}) {
  return provider.createConversationWithMessages(
    ConversationSettings(modelId: 'model'),
    messages:
        messages ??
        [(role: 'user', content: titleText, images: const <MessageImage>[])],
  );
}
