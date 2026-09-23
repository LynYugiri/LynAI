import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/composer_draft.dart';
import 'package:lynai/models/composer_reference.dart';
import 'package:lynai/repositories/composer_draft_repository.dart';
import 'package:lynai/services/storage_v2_service.dart';

ComposerDraft _text(String text) =>
    ComposerDraft(segments: [ComposerTextSegment(text)]);

String _textOf(ComposerDraft draft) => draft.segments
    .whereType<ComposerTextSegment>()
    .map((segment) => segment.text)
    .join();

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('lynai_composer_draft_');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('草稿按对话隔离，空草稿等于删除', () async {
    final storage = StorageV2Service(rootDirectory: root);
    addTearDown(storage.close);
    final repository = ComposerDraftRepository(storageV2: storage);

    await repository.save({'a': _text('会话 A 的内容'), 'b': _text('会话 B')});
    final loaded = {
      for (final entry in await repository.load()) entry.slot: entry.draft,
    };
    expect(_textOf(loaded['a']!), '会话 A 的内容');
    expect(_textOf(loaded['b']!), '会话 B');

    await repository.save({'b': _text('会话 B')});
    final afterDelete = await repository.load();
    expect(afterDelete.map((entry) => entry.slot), ['b']);
  });

  test('未创建对话的槽位不带 conversationId', () async {
    final storage = StorageV2Service(rootDirectory: root);
    addTearDown(storage.close);
    final repository = ComposerDraftRepository(storageV2: storage);

    await repository.save({
      ComposerDraftRepository.newConversationSlot: _text('还没发出去'),
    });

    final raw = await storage.loadDataFile('composer_drafts.json');
    final rows = (raw['drafts'] as List).cast<Map>();
    expect(rows.single['id'], ComposerDraftRepository.newConversationSlot);
    expect(rows.single.containsKey('conversationId'), isFalse);
  });

  test('引用 Chip 与正文一起往返', () async {
    final storage = StorageV2Service(rootDirectory: root);
    addTearDown(storage.close);
    final repository = ComposerDraftRepository(storageV2: storage);
    const reference = ComposerReference(
      localId: 'ref-1',
      type: ComposerReferenceType.note,
      id: 'note-1',
      title: '笔记一',
      qualifiers: {'noteId': 'note-1'},
    );

    await repository.save({
      'a': const ComposerDraft(
        segments: [
          ComposerTextSegment('看下 '),
          ComposerReferenceSegment(reference),
        ],
      ),
    });

    final draft = (await repository.load()).single.draft;
    expect(_textOf(draft), '看下 ');
    final restored = draft.segments
        .whereType<ComposerReferenceSegment>()
        .single;
    expect(restored.reference.id, 'note-1');
    expect(restored.reference.qualifiers['noteId'], 'note-1');
  });

  test('只有路径的附件会补上 Resource 并解析回本机路径', () async {
    final storage = StorageV2Service(rootDirectory: root);
    addTearDown(storage.close);
    final repository = ComposerDraftRepository(storageV2: storage);
    final file = File('${root.path}/cat.png')..writeAsBytesSync([1, 2, 3, 4]);

    await repository.save({
      'a': ComposerDraft(
        attachments: [
          ComposerDraftAttachment(
            path: file.path,
            name: 'cat.png',
            size: 4,
            mimeType: 'image/png',
          ),
        ],
      ),
    });

    // 行里保存的是 Resource ID 与元数据，路径按 Resource 解析回来。
    final raw = await storage.loadDataFile('composer_drafts.json');
    final row = (raw['drafts'] as List).cast<Map>().single;
    final attachment = ((row['draft'] as Map)['attachments'] as List)
        .cast<Map>()
        .single;
    expect(attachment['resourceId'], isNotEmpty);
    expect(attachment['path'], file.path);

    // 读回时按 Resource 解析本机路径：内容一致，路径指向资源副本。
    final draft = (await repository.load()).single.draft;
    final restored = draft.attachments.single;
    expect(restored.resourceId, attachment['resourceId']);
    expect(restored.mimeType, 'image/png');
    expect(restored.name, 'cat.png');
    expect(File(restored.path).readAsBytesSync(), [1, 2, 3, 4]);
  });

  test('内容没变的槽位保留 updatedAt，改动后才更新', () async {
    final storage = StorageV2Service(rootDirectory: root);
    addTearDown(storage.close);
    final repository = ComposerDraftRepository(storageV2: storage);

    await repository.save({'a': _text('第一版'), 'b': _text('另一条')});
    final first = {
      for (final entry in await repository.load()) entry.slot: entry.updatedAt,
    };

    await Future<void>.delayed(const Duration(milliseconds: 5));
    await repository.save({'a': _text('第一版'), 'b': _text('改过的')});
    final second = {
      for (final entry in await repository.load()) entry.slot: entry.updatedAt,
    };

    expect(second['a'], first['a']);
    expect(second['b']!.isAfter(first['b']!), isTrue);
  });

  test('重新打开数据库后草稿仍在', () async {
    final first = StorageV2Service(rootDirectory: root);
    await ComposerDraftRepository(
      storageV2: first,
    ).save({'a': _text('重启后还要在')});
    await first.close();

    final second = StorageV2Service(rootDirectory: root);
    addTearDown(second.close);
    final reloaded = await ComposerDraftRepository(storageV2: second).load();
    expect(_textOf(reloaded.single.draft), '重启后还要在');
  });

  test('损坏的草稿行被跳过而不是让加载失败', () async {
    final storage = StorageV2Service(rootDirectory: root);
    addTearDown(storage.close);
    await storage.writeDataFile('composer_drafts.json', {
      'drafts': [
        {'id': 'a', 'draft': 'not a map'},
        {
          'id': 'b',
          'conversationId': 'b',
          'draft': {
            'segments': [
              {'t': 'text', 'v': '正常'},
            ],
          },
          'updatedAt': DateTime.utc(2026).toIso8601String(),
        },
      ],
    });

    final loaded = await ComposerDraftRepository(storageV2: storage).load();
    expect(loaded.map((entry) => entry.slot), ['b']);
    expect(_textOf(loaded.single.draft), '正常');
  });
}
