import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lynai/models/composer_draft.dart';
import 'package:lynai/models/composer_reference.dart';
import 'package:lynai/models/conversation.dart';
import 'package:lynai/models/message.dart';
import 'package:lynai/providers/conversation_provider.dart';

import 'support/memory_repositories.dart';

String _seedConversation(ConversationProvider conversations) =>
    conversations.createConversationWithMessages(
      ConversationSettings(modelId: 'model-1'),
      messages: [
        (
          role: 'user',
          content: '一个问题',
          images: const <MessageImage>[],
          composerSegments: const <ComposerSegment>[],
        ),
      ],
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('收录引用会刷新对话的 updatedAt', () async {
    final conversations = memoryConversationProvider();
    final id = _seedConversation(conversations);
    final before = conversations.getConversation(id)!.updatedAt;

    await Future<void>.delayed(const Duration(milliseconds: 2));
    conversations.rememberComposerReferences(id, const [
      ComposerReference(
        localId: 'ref-1',
        type: ComposerReferenceType.note,
        id: 'note-1',
        title: '项目规划',
      ),
    ]);

    // 引用池是对话记录的一部分：只改池子也必须刷新 updatedAt，否则这条对话
    // 会带着过期时间戳参与同步与排序。
    final after = conversations.getConversation(id)!.updatedAt;
    expect(after.isAfter(before), isTrue);
  });

  test('对话已存在时恢复仍会把回收站里的草稿写回', () async {
    final conversations = memoryConversationProvider();
    final id = _seedConversation(conversations);
    final conversation = conversations.getConversation(id)!;

    // 删除对话时草稿随快照进回收站；恢复路径发现对话行已存在时也必须写回草稿，
    // 不能因为提前返回而把它静默丢掉。
    await conversations.deleteConversation(id);
    conversations.restoreConversation(
      conversation,
      draft: const ComposerDraft(
        segments: [ComposerTextSegment('回收站里的草稿')],
      ),
    );
    await conversations.flushPendingSaves();

    final restored = conversations.composerDraftFor(id);
    expect(
      restored.segments.whereType<ComposerTextSegment>().single.text,
      '回收站里的草稿',
    );
  });
}
