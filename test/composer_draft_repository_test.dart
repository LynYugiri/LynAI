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

    await repository.save({'b': _text('会话 B')}, removed: {'a'});
    final afterDelete = await repository.load();
    expect(afterDelete.map((entry) => entry.slot), ['b']);
  });

  test('未提到的槽位不会被部分保存删掉', () async {
    final storage = StorageV2Service(rootDirectory: root);
    addTearDown(storage.close);
    final repository = ComposerDraftRepository(storageV2: storage);

    await repository.save({'a': _text('会话 A'), 'b': _text('会话 B')});
    // 内存缓存可能是部分状态（启动时 loadConversations 提前返回，或草稿读取失败
    // 保留了空缓存），这时一次按键不能把其他对话的草稿一起删掉。
    await repository.save({'a': _text('会话 A 的新内容')});

    final loaded = {
      for (final entry in await repository.load()) entry.slot: entry.draft,
    };
    expect(_textOf(loaded['a']!), '会话 A 的新内容');
    expect(_textOf(loaded['b']!), '会话 B');
  });

  test('未提到的槽位原样写回，不刷新 updatedAt', () async {
    final storage = StorageV2Service(rootDirectory: root);
    addTearDown(storage.close);
    final repository = ComposerDraftRepository(storageV2: storage);

    Future<Map<String, Map>> rows() async {
      final raw = await storage.loadDataFile('composer_drafts.json');
      return {
        for (final row in (raw['drafts'] as List).cast<Map>())
          row['id'] as String: row,
      };
    }

    await repository.save({'a': _text('会话 A'), 'b': _text('会话 B')});
    final before = await rows();

    await repository.save({'a': _text('会话 A 的新内容')});
    final after = await rows();

    // 未提到的行逐字段一致，因此不会产生多余的同步变更。
    expect(after['b'], before['b']);
    expect(after['a']!['updatedAt'], isNot(before['a']!['updatedAt']));
  });

  test('removed 里的槽位被删除，之后重新写入仍然生效', () async {
    final storage = StorageV2Service(rootDirectory: root);
    addTearDown(storage.close);
    final repository = ComposerDraftRepository(storageV2: storage);

    await repository.save({'a': _text('会话 A'), 'b': _text('会话 B')});
    await repository.save(const {}, removed: {'a'});
    expect((await repository.load()).map((entry) => entry.slot), ['b']);

    await repository.save({'a': _text('会话 A 回来了')});
    final loaded = {
      for (final entry in await repository.load()) entry.slot: entry.draft,
    };
    expect(_textOf(loaded['a']!), '会话 A 回来了');
    expect(loaded.keys, containsAll(['a', 'b']));
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

  test('启动读回后按 Resource 解析的路径不会刷新 updatedAt', () async {
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
    final stored = (await repository.load()).single;

    // 模拟「启动时读回草稿，用户随后只改了正文」：读回后附件 path 已被解析成
    // Resource 私有路径，而存储行里还是选择时的暂存路径。文件身份没变，不该因此
    // 多推一条同步变更。
    final resolved = (await repository.load()).single.draft;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await repository.save({'a': resolved});

    expect((await repository.load()).single.updatedAt, stored.updatedAt);
  });

  test('内容没变的槽位保留 updatedAt，改动后才更新', () async {    final storage = StorageV2Service(rootDirectory: root);
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

  test('带附件的草稿重复保存不会刷新 updatedAt', () async {
    final storage = StorageV2Service(rootDirectory: root);
    addTearDown(storage.close);
    final repository = ComposerDraftRepository(storageV2: storage);
    final file = File('${root.path}/cat.png')..writeAsBytesSync([1, 2, 3, 4]);
    final draft = ComposerDraft(
      segments: const [ComposerTextSegment('看下 ')],
      attachments: [
        ComposerDraftAttachment(
          path: file.path,
          name: 'cat.png',
          size: 4,
          mimeType: 'image/png',
        ),
      ],
    );

    await repository.save({'a': draft});
    final first = (await repository.load()).single.updatedAt;

    await Future<void>.delayed(const Duration(milliseconds: 5));
    // 撤回消息、备份恢复拿到的附件只有路径，每次保存都会补 Resource；
    // 补齐本身不算内容变化，否则每次输入都会推一条同步变更。
    await repository.save({'a': draft});
    final second = (await repository.load()).single.updatedAt;
    expect(second, first);

    await Future<void>.delayed(const Duration(milliseconds: 5));
    await repository.save({
      'a': ComposerDraft(
        segments: const [ComposerTextSegment('看下这两个 ')],
        attachments: draft.attachments,
      ),
    });
    final third = (await repository.load()).single.updatedAt;
    expect(third.isAfter(first), isTrue);
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
