import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lynai/models/composer_reference.dart';
import 'package:lynai/models/conversation.dart';
import 'package:lynai/models/message.dart';
import 'package:lynai/providers/feature_provider.dart';
import 'package:lynai/providers/knowledge_provider.dart';
import 'package:lynai/providers/task_provider.dart';
import 'package:lynai/services/composer_selector_registry.dart';
import 'package:lynai/services/storage_v2_service.dart';
import 'package:lynai/services/storage_v2_upgrade_service.dart';

import 'support/memory_repositories.dart';

Future<StorageV2Service> _readyStorage(Directory root) async {
  final storage = StorageV2Service(rootDirectory: root);
  await StorageV2UpgradeService(storageV2: storage).ensureReady();
  return storage;
}

void main() {
  test('notes selector returns folders and note items without body', () async {
    SharedPreferences.setMockInitialValues({});
    final root = await Directory.systemTemp.createTemp('lynai_sel_notes_');
    final storage = await _readyStorage(root);
    try {
      final features = FeatureProvider(storageV2: storage);
      await features.load();
      final folderId = await features.addNoteFolder('工作');
      await features.addNoteWithContent(
        '项目规划',
        '本周需要完成版本发布准备，包括回归测试。',
        folderId: folderId,
      );
      await features.addNoteWithContent('灵感', '随手记录');

      final registry = buildBuiltInSelectorRegistry(
        features: features,
        tasks: TaskProvider(storageV2: storage),
      );
      final rootItems = await registry.selector('notes')!.load('', const []);
      final folders = rootItems
          .where((i) => i.kind == ComposerSelectorItemKind.folder)
          .toList();
      final unfiled = rootItems
          .where((i) => i.kind == ComposerSelectorItemKind.item)
          .toList();
      expect(folders.map((i) => i.title), contains('工作'));
      expect(unfiled.map((i) => i.title), contains('灵感'));

      final inFolder = await registry.selector('notes')!.load('', [
        folders.first.key.split(':').last,
      ]);
      expect(inFolder.map((i) => i.title), contains('项目规划'));
      final value = inFolder.first.value!;
      expect(value.type, ComposerReferenceType.note);
      expect(value.id, isNotEmpty);
      expect(value.snippet, '本周需要完成版本发布准备，包括回归测试。');
    } finally {
      await storage.close();
      await root.delete(recursive: true);
    }
  });

  test('note-pages selector lists notes first so pages stay reachable', () async {
    SharedPreferences.setMockInitialValues({});
    final root = await Directory.systemTemp.createTemp('lynai_sel_pages_');
    final storage = await _readyStorage(root);
    try {
      final features = FeatureProvider(storageV2: storage);
      await features.load();
      final noteId = await features.addNoteWithContent('项目规划', '正文');
      await features.addNotePage(noteId, '第一页');

      final registry = buildBuiltInSelectorRegistry(
        features: features,
        tasks: TaskProvider(storageV2: storage),
      );
      // 页面挂在笔记下：源的第一层必须给出可下钻的笔记，否则笔记页永远不可达。
      final notes = await registry.selector('note-pages')!.load('', const []);
      final folder = notes.firstWhere(
        (item) => item.kind == ComposerSelectorItemKind.folder,
      );
      expect(folder.title, '项目规划');

      final pages = await registry.selector('note-pages')!.load('', [
        folder.key.split(':').last,
      ]);
      expect(pages.map((item) => item.title), contains('第一页'));
      expect(pages.first.value!.type, ComposerReferenceType.notePage);
      expect(pages.first.value!.qualifiers['noteId'], isNotEmpty);
    } finally {
      await storage.close();
      await root.delete(recursive: true);
    }
  });

  test('task-lists selector returns task list references', () async {
    SharedPreferences.setMockInitialValues({});
    final root = await Directory.systemTemp.createTemp('lynai_sel_lists_');
    final storage = await _readyStorage(root);
    try {
      final tasks = TaskProvider(storageV2: storage);
      await tasks.load();
      await tasks.addList('项目发布');

      final registry = buildBuiltInSelectorRegistry(
        features: FeatureProvider(storageV2: storage),
        tasks: tasks,
      );
      final items = await registry.selector('task-lists')!.load('', const []);
      expect(items, hasLength(1));
      expect(items.first.value!.type, ComposerReferenceType.taskList);
      expect(items.first.value!.id, isNotEmpty);
    } finally {
      await storage.close();
      await root.delete(recursive: true);
    }
  });

  test('tasks selector navigates lists to task items', () async {
    SharedPreferences.setMockInitialValues({});
    final root = await Directory.systemTemp.createTemp('lynai_sel_tasks_');
    final storage = await _readyStorage(root);
    try {
      final tasks = TaskProvider(storageV2: storage);
      await tasks.load();
      final listId = await tasks.addList('项目发布');
      await tasks.addTask(title: '完成发布说明', listId: listId);
      await tasks.addTask(title: '未分类任务');

      final registry = buildBuiltInSelectorRegistry(
        features: FeatureProvider(storageV2: storage),
        tasks: tasks,
      );
      final rootItems = await registry.selector('tasks')!.load('', const []);
      final folder = rootItems.firstWhere(
        (i) => i.kind == ComposerSelectorItemKind.folder,
      );
      expect(folder.title, '项目发布');

      final inList = await registry.selector('tasks')!.load('', [
        folder.key.split(':').last,
      ]);
      expect(inList.map((i) => i.title), contains('完成发布说明'));
      expect(inList.first.value!.type, ComposerReferenceType.task);
    } finally {
      await storage.close();
      await root.delete(recursive: true);
    }
  });

  test('notes selector exposes folders as referenceable scope values', () async {
    SharedPreferences.setMockInitialValues({});
    final root = await Directory.systemTemp.createTemp('lynai_sel_scope_');
    final storage = await _readyStorage(root);
    try {
      final features = FeatureProvider(storageV2: storage);
      await features.load();
      final folderId = await features.addNoteFolder('工作');
      await features.addNoteWithContent('项目规划', '正文', folderId: folderId);

      final registry = buildBuiltInSelectorRegistry(
        features: features,
        tasks: TaskProvider(storageV2: storage),
      );
      final selector = registry.selector('notes')!;

      // 停在文件夹层：文件夹条目本身就能产生「整个文件夹」引用，同时保留下钻。
      final rootItems = await selector.load('', const []);
      final folder = rootItems.firstWhere(
        (item) => item.kind == ComposerSelectorItemKind.folder,
      );
      expect(folder.value, isNotNull);
      expect(folder.value!.type, ComposerReferenceType.note);
      expect(folder.value!.id, folderId);
      expect(folder.value!.scope, ComposerReferenceScope.folder);

      // 仍可下钻到文件夹内的具体笔记。
      final inFolder = await selector.load('', [folderId]);
      expect(inFolder.map((item) => item.title), contains('项目规划'));
      expect(
        inFolder.single.value!.scope,
        ComposerReferenceScope.entity,
      );

      // 范围行的取值与文件夹条目一致。
      final rootValue = selector.rootValue!(const []);
      expect(rootValue, isNull);
      final scopedRoot = selector.rootValue!([folderId]);
      expect(scopedRoot!.scope, ComposerReferenceScope.folder);
      expect(scopedRoot.title, '工作');
    } finally {
      await storage.close();
      await root.delete(recursive: true);
    }
  });

  test('conversations selector lists history and skips the current one', () async {
    SharedPreferences.setMockInitialValues({});
    final root = await Directory.systemTemp.createTemp('lynai_sel_conv_');
    final storage = await _readyStorage(root);
    try {
      final conversations = memoryConversationProvider();
      final first = conversations.createConversationWithMessages(
        ConversationSettings(modelId: 'model-1'),
        messages: [
          (
            role: 'user',
            content: '讨论发布计划',
            images: const <MessageImage>[],
            composerSegments: const <ComposerSegment>[],
          ),
        ],
      );
      final second = conversations.createConversationWithMessages(
        ConversationSettings(modelId: 'model-1'),
        messages: [
          (
            role: 'user',
            content: '另一段对话',
            images: const <MessageImage>[],
            composerSegments: const <ComposerSegment>[],
          ),
        ],
      );

      final registry = buildBuiltInSelectorRegistry(
        features: FeatureProvider(storageV2: storage),
        tasks: TaskProvider(storageV2: storage),
        conversations: conversations,
        currentConversationId: first,
        include: const {BuiltInComposerSelector.conversations},
      );

      final items = await registry.selector('conversations')!.load('', const []);
      // 当前对话不出现：引用「正在写的这段对话」没有意义。
      expect(items, hasLength(1));
      expect(items.single.value!.type, ComposerReferenceType.conversation);
      expect(items.single.value!.id, second);

      // 过滤词同时匹配标题与首条正文。
      expect(
        await registry.selector('conversations')!.load('另一段', const []),
        hasLength(1),
      );
      expect(
        await registry.selector('conversations')!.load('不存在的关键词', const []),
        isEmpty,
      );
    } finally {
      await storage.close();
      await root.delete(recursive: true);
    }
  });

  test('registry can be trimmed to jotting-compatible selectors', () async {
    SharedPreferences.setMockInitialValues({});
    final root = await Directory.systemTemp.createTemp('lynai_sel_trim_');
    final storage = await _readyStorage(root);
    try {
      final registry = buildBuiltInSelectorRegistry(
        features: FeatureProvider(storageV2: storage),
        tasks: TaskProvider(storageV2: storage),
        knowledge: KnowledgeProvider(storageV2: storage),
        include: const {
          BuiltInComposerSelector.notes,
          BuiltInComposerSelector.tasks,
          BuiltInComposerSelector.knowledgeEntries,
        },
      );
      expect(registry.names.toList(), ['notes', 'tasks', 'knowledge-entries']);
      expect(registry.selector('note-pages'), isNull);
      expect(registry.selector('task-lists'), isNull);
      expect(registry.selector('knowledge-bases'), isNull);
    } finally {
      await storage.close();
      await root.delete(recursive: true);
    }
  });

  test('parsePluginCommandItems maps plugin command results to items', () {
    final items = parsePluginCommandItems({
      'ok': true,
      'result': [
        {'key': 'folder:x', 'kind': 'folder', 'title': 'X'},
        {
          'key': 'item:n',
          'kind': 'item',
          'title': 'Note',
          'type': 'note',
          'id': 'n1',
          'qualifiers': {'pluginId': 'p1'},
        },
      ],
    });

    expect(items, hasLength(2));
    expect(items.first.kind, ComposerSelectorItemKind.folder);
    expect(items.last.value!.type, ComposerReferenceType.note);
    expect(items.last.value!.id, 'n1');
    expect(items.last.value!.qualifiers, {'pluginId': 'p1'});
  });

  test('parsePluginCommandItems fails closed on error or malformed data', () {
    expect(parsePluginCommandItems({'ok': false, 'error': 'denied'}), isEmpty);
    expect(
      parsePluginCommandItems({'ok': true, 'result': 'not-a-list'}),
      isEmpty,
    );
    expect(
      parsePluginCommandItems({
        'ok': true,
        'result': [
          {'type': 'bad'},
        ],
      }),
      isEmpty,
    );
  });
}
