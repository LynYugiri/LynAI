import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lynai/models/composer_reference.dart';
import 'package:lynai/providers/feature_provider.dart';
import 'package:lynai/providers/task_provider.dart';
import 'package:lynai/services/composer_selector_registry.dart';
import 'package:lynai/services/storage_v2_service.dart';
import 'package:lynai/services/storage_v2_upgrade_service.dart';

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

      final inFolder = await registry
          .selector('notes')!
          .load('', [folders.first.key.split(':').last]);
      expect(inFolder.map((i) => i.title), contains('项目规划'));
      final value = inFolder.first.value!;
      expect(value.type, ComposerReferenceType.note);
      expect(value.id, isNotEmpty);
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

      final inList = await registry
          .selector('tasks')!
          .load('', [folder.key.split(':').last]);
      expect(inList.map((i) => i.title), contains('完成发布说明'));
      expect(inList.first.value!.type, ComposerReferenceType.task);
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
    expect(parsePluginCommandItems({'ok': true, 'result': 'not-a-list'}), isEmpty);
    expect(parsePluginCommandItems({'ok': true, 'result': [{'type': 'bad'}]}), isEmpty);
  });
}
