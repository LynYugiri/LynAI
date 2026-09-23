import 'package:flutter_test/flutter_test.dart';

import 'package:lynai/models/composer_reference.dart';
import 'package:lynai/models/conversation.dart';
import 'package:lynai/models/conversation_context.dart';
import 'package:lynai/models/message.dart';

ComposerReference _noteRef(String id, {String title = '笔记'}) =>
    ComposerReference(
      localId: 'ref-$id',
      type: ComposerReferenceType.note,
      id: id,
      title: title,
    );

void main() {
  group('会话引用池', () {
    test('同键条目只保留一条并刷新为最近引用', () {
      final pool = const ConversationReferencePool()
          .merged([_noteRef('a', title: '旧标题')], now: DateTime(2026, 1, 1))
          .merged([_noteRef('a', title: '新标题')], now: DateTime(2026, 1, 2));
      expect(pool.length, 1);
      expect(pool.entries.single.title, '新标题');
      expect(pool.entries.single.addedAt, DateTime(2026, 1, 2));
    });

    test('文件夹层级与实体层级算不同条目', () {
      final pool = const ConversationReferencePool()
          .merged([
            _noteRef('folder-1'),
            const ComposerReference(
              localId: 'ref-folder',
              type: ComposerReferenceType.note,
              id: 'folder-1',
              title: '文件夹',
              scope: ComposerReferenceScope.folder,
            ),
          ], now: DateTime(2026, 1, 1));
      expect(pool.length, 2);
    });

    test('超过上限时淘汰最久未引用的条目', () {
      var pool = const ConversationReferencePool();
      for (var i = 0; i < ConversationReferencePool.maxEntries + 5; i++) {
        pool = pool.merged([
          _noteRef('note-$i'),
        ], now: DateTime(2026, 1, 1).add(Duration(minutes: i)));
      }
      expect(pool.length, ConversationReferencePool.maxEntries);
      // 最早的 5 条被淘汰，最新一条仍在。
      expect(
        pool.entries.map((entry) => entry.id),
        isNot(contains('note-0')),
      );
      expect(
        pool.entries.map((entry) => entry.id),
        contains('note-${ConversationReferencePool.maxEntries + 4}'),
      );
    });

    test('池子随对话 JSON 往返，非法条目跳过', () {
      final conversation = Conversation(
        id: 'conv-1',
        title: '标题',
        messages: const [],
        modelId: 'model-1',
        referencePool: const ConversationReferencePool().merged(
          [_noteRef('note-1', title: '项目规划')],
          now: DateTime(2026, 3, 1),
        ),
        createdAt: DateTime(2026, 3, 1),
        updatedAt: DateTime(2026, 3, 1),
      );
      final restored = Conversation.fromJson(conversation.toJson());
      expect(restored.referencePool.length, 1);
      final entry = restored.referencePool.entries.single;
      expect(entry.type, ComposerReferenceType.note);
      expect(entry.id, 'note-1');
      expect(entry.title, '项目规划');
      expect(entry.addedAt, DateTime(2026, 3, 1));
    });
  });

  group('上下文检查点', () {
    Conversation conversationWithCheckpoint({
      required List<String> covered,
      required List<String> alive,
    }) => Conversation(
      id: 'conv-1',
      title: '标题',
      messages: [
        for (var i = 0; i < alive.length; i++)
          Message(
            id: alive[i],
            role: i.isEven ? 'user' : 'assistant',
            content: '消息 $i',
            timestamp: DateTime(2026, 3, 1),
          ),
      ],
      modelId: 'model-1',
      contextCheckpoint: ConversationContextCheckpoint(
        summary: '之前聊了发布计划',
        coveredMessageIds: covered,
        createdAt: DateTime(2026, 3, 1),
      ),
      createdAt: DateTime(2026, 3, 1),
      updatedAt: DateTime(2026, 3, 1),
    );

    test('检查点随对话 JSON 往返', () {
      final conversation = conversationWithCheckpoint(
        covered: ['m0', 'm1'],
        alive: ['m0', 'm1', 'm2'],
      );
      final restored = Conversation.fromJson(conversation.toJson());
      final checkpoint = restored.contextCheckpoint;
      expect(checkpoint, isNotNull);
      expect(checkpoint!.summary, '之前聊了发布计划');
      expect(checkpoint.coveredMessageIds, ['m0', 'm1']);
      expect(checkpoint.coveredCount, 2);
    });

    test('覆盖集合收敛到现存消息，清空则失效', () {
      final checkpoint = ConversationContextCheckpoint(
        summary: '摘要',
        coveredMessageIds: const ['m0', 'm1', 'm2'],
        createdAt: DateTime(2026, 3, 1),
      );
      expect(checkpoint.withCoveredMessages(['m0', 'm2'])!.coveredMessageIds, [
        'm0',
        'm2',
      ]);
      expect(checkpoint.withCoveredMessages(['m9']), isNull);
    });

    test('摘要为空或没有覆盖消息时不构成有效检查点', () {
      expect(
        ConversationContextCheckpoint(
          summary: '   ',
          coveredMessageIds: const ['m0'],
          createdAt: DateTime(2026, 3, 1),
        ).isEmpty,
        isTrue,
      );
      expect(
        ConversationContextCheckpoint(
          summary: '摘要',
          coveredMessageIds: const [],
          createdAt: DateTime(2026, 3, 1),
        ).isEmpty,
        isTrue,
      );
    });
  });
}
