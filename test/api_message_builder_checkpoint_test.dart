import 'package:flutter_test/flutter_test.dart';

import 'package:lynai/models/conversation.dart';
import 'package:lynai/models/conversation_context.dart';
import 'package:lynai/models/message.dart';
import 'package:lynai/services/api_message_builder.dart';

Conversation _conversation({
  List<Message>? messages,
  ConversationContextCheckpoint? checkpoint,
}) {
  final now = DateTime(2026, 3, 1);
  return Conversation(
    id: 'conv-1',
    title: '标题',
    messages:
        messages ??
        [
          Message(id: 'm0', role: 'user', content: '第一问', timestamp: now),
          Message(id: 'm1', role: 'assistant', content: '第一答', timestamp: now),
          Message(id: 'm2', role: 'user', content: '第二问', timestamp: now),
          Message(id: 'm3', role: 'assistant', content: '', timestamp: now),
        ],
    modelId: 'model-1',
    contextCheckpoint: checkpoint,
    createdAt: now,
    updatedAt: now,
  );
}

List<Map<String, dynamic>> _nonSystem(List<Map<String, dynamic>> messages) =>
    messages.where((message) => message['role'] != 'system').toList();

void main() {
  test('被检查点覆盖的历史换成一条 system 摘要', () {
    final conversation = _conversation(
      checkpoint: ConversationContextCheckpoint(
        summary: '之前聊了发布计划',
        coveredMessageIds: const ['m0', 'm1'],
        createdAt: DateTime(2026, 3, 1),
      ),
    );
    final messages = buildApiMessages(conversation, const []);

    // 原始消息一条不删，但发送副本里只剩未被覆盖的部分。
    expect(conversation.messages, hasLength(4));
    expect(
      _nonSystem(messages).map((message) => message['content']),
      ['第二问'],
    );
    final checkpointMessages = messages
        .where(
          (message) =>
              message['role'] == 'system' &&
              message['content'].toString().contains('Context checkpoint:'),
        )
        .toList();
    expect(checkpointMessages, hasLength(1));
    expect(
      checkpointMessages.single['content'],
      contains('之前聊了发布计划'),
    );
    // 摘要插在第一条被覆盖消息的位置，而不是永远追加在末尾。
    final checkpointIndex = messages.indexWhere(
      (message) => message['content'].toString().contains('Context checkpoint:'),
    );
    final firstKeptIndex = messages.indexWhere(
      (message) => message['content'] == '第二问',
    );
    expect(checkpointIndex, lessThan(firstKeptIndex));
  });

  test('覆盖集合与现存消息完全不相交时检查点按失效处理', () {
    final conversation = _conversation(
      checkpoint: ConversationContextCheckpoint(
        summary: '描述一段已经不存在的历史',
        coveredMessageIds: const ['gone-1', 'gone-2'],
        createdAt: DateTime(2026, 3, 1),
      ),
    );
    final messages = buildApiMessages(conversation, const []);
    expect(
      messages.any(
        (message) => message['content'].toString().contains('Context checkpoint:'),
      ),
      isFalse,
    );
    expect(_nonSystem(messages), hasLength(3));
  });

  test('部分失效的覆盖集合只顶替仍存在的消息', () {
    final conversation = _conversation(
      checkpoint: ConversationContextCheckpoint(
        summary: '摘要',
        coveredMessageIds: const ['m0', 'gone'],
        createdAt: DateTime(2026, 3, 1),
      ),
    );
    final messages = buildApiMessages(conversation, const []);
    expect(
      _nonSystem(messages).map((message) => message['content']),
      ['第一答', '第二问'],
    );
  });

  test('没有检查点时消息组装与既有行为一致', () {
    final conversation = _conversation();
    final messages = buildApiMessages(conversation, const []);
    // 空内容 assistant 占位被跳过。
    expect(
      _nonSystem(messages).map((message) => message['content']),
      ['第一问', '第一答', '第二问'],
    );
  });
}
