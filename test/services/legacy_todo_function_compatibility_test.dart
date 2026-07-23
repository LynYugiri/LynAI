import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/plugin.dart';
import 'package:lynai/models/recycle_bin_item.dart';
import 'package:lynai/models/task.dart';
import 'package:lynai/models/task_list.dart';
import 'package:lynai/providers/plugin_provider.dart';
import 'package:lynai/providers/task_provider.dart';
import 'package:lynai/repositories/recycle_bin_repository.dart';
import 'package:lynai/repositories/task_repository.dart';
import 'package:lynai/services/lynai_function_service.dart';

void main() {
  group('legacy todo function compatibility', () {
    late TaskProvider tasks;
    late LynAIFunctionService service;
    late LynAIFunctionContext context;

    setUp(() {
      tasks = TaskProvider(
        repository: _MemoryTaskRepository(),
        recycleBinRepository: _MemoryRecycleBinRepository(),
      );
      service = LynAIFunctionService();
      context = LynAIFunctionContext(tasks: tasks);
    });

    test(
      'list and read expose canonical lists as legacy nested items',
      () async {
        final listId = await tasks.addList('Shopping');
        final milkId = await tasks.addTask(title: 'Milk', listId: listId);
        await tasks.completeTask(milkId);

        final listed = service.executeSync(
          const LynAIFunctionCall(
            name: 'todos.list',
            arguments: {'includeItems': true},
          ),
          context,
        );
        final list = (listed['todoLists'] as List).single as Map;

        expect(list['id'], listId);
        expect(list['title'], 'Shopping');
        expect(list['totalItems'], 1);
        expect(list['doneItems'], 1);
        expect((list['items'] as List).single, {
          'id': milkId,
          'text': 'Milk',
          'done': true,
        });

        final read = service.executeSync(
          LynAIFunctionCall(name: 'todos.read', arguments: {'id': listId}),
          context,
        );
        expect((read['todoList'] as Map)['items'], list['items']);
      },
    );

    test(
      'save item requires list and mutates canonical task membership',
      () async {
        final listId = await tasks.addList('Inbox');

        final missingList = await service.execute(
          const LynAIFunctionCall(
            name: 'todos.saveItem',
            arguments: {'text': 'No list'},
          ),
          context,
        );
        expect(missingList['ok'], isFalse);
        expect(missingList['error'], contains('listId'));

        final created = await service.execute(
          LynAIFunctionCall(
            name: 'todos.saveItem',
            arguments: {'listId': listId, 'text': 'First', 'done': 'true'},
          ),
          context,
        );
        final item = created['item'] as Map;
        final itemId = item['id'] as String;
        expect(item, {'id': itemId, 'text': 'First', 'done': true});
        expect(tasks.taskById(itemId)?.completedAt, isNotNull);
        expect(tasks.entryForTask(itemId)?.taskListId, listId);

        final updated = await service.execute(
          LynAIFunctionCall(
            name: 'todos.saveItem',
            arguments: {
              'listId': listId,
              'itemId': itemId,
              'text': 'Renamed',
              'done': false,
            },
          ),
          context,
        );
        expect(updated['item'], {
          'id': itemId,
          'text': 'Renamed',
          'done': false,
        });
        expect(tasks.taskById(itemId)?.completedAt, isNull);

        final deleted = await service.execute(
          LynAIFunctionCall(
            name: 'todos.saveItem',
            arguments: {'listId': listId, 'itemId': itemId, 'delete': true},
          ),
          context,
        );
        expect(deleted['ok'], isTrue);
        expect(tasks.taskById(itemId), isNull);
        expect((deleted['todoList'] as Map)['items'], isEmpty);
      },
    );

    test('save list replaces only selected canonical list contents', () async {
      final targetId = await tasks.addList('Target');
      final unrelatedId = await tasks.addList('Unrelated');
      final retainedId = await tasks.addTask(
        title: 'Old title',
        listId: targetId,
      );
      final removedId = await tasks.addTask(title: 'Removed', listId: targetId);
      final unrelatedTaskId = await tasks.addTask(
        title: 'Untouched',
        listId: unrelatedId,
      );
      final unrelatedBefore = tasks.taskById(unrelatedTaskId)!;

      final replaced = await service.execute(
        LynAIFunctionCall(
          name: 'todos.saveList',
          arguments: {
            'id': targetId,
            'title': 'Replaced',
            'items': [
              {'id': retainedId, 'text': 'New title', 'done': true},
              {'text': 'New task', 'done': false},
            ],
          },
        ),
        context,
      );
      final list = replaced['todoList'] as Map;
      final items = list['items'] as List;

      expect(list['title'], 'Replaced');
      expect(items, hasLength(2));
      expect(items.first, {
        'id': retainedId,
        'text': 'New title',
        'done': true,
      });
      expect(tasks.taskById(retainedId)?.completedAt, isNotNull);
      expect(tasks.taskById(removedId), isNull);
      expect(tasks.listById(unrelatedId)?.title, 'Unrelated');
      expect(tasks.taskById(unrelatedTaskId), same(unrelatedBefore));
      expect(tasks.entryForTask(unrelatedTaskId)?.taskListId, unrelatedId);
    });

    test(
      'save list creates a canonical list with caller-supplied item ids',
      () async {
        final result = await service.execute(
          const LynAIFunctionCall(
            name: 'todos.saveList',
            arguments: {
              'title': 'Created',
              'items': [
                {'id': 'legacy-item', 'text': 'Imported', 'done': true},
              ],
            },
          ),
          context,
        );
        final list = result['todoList'] as Map;

        expect(result['ok'], isTrue);
        expect(tasks.listById(list['id'] as String)?.title, 'Created');
        expect(tasks.taskById('legacy-item')?.completedAt, isNotNull);
        expect(tasks.entryForTask('legacy-item')?.taskListId, list['id']);
        expect((list['items'] as List).single, {
          'id': 'legacy-item',
          'text': 'Imported',
          'done': true,
        });
      },
    );

    test('legacy plugin stats count canonical tasks', () async {
      final completedId = await tasks.addTask(title: 'Completed');
      await tasks.completeTask(completedId);
      await tasks.addTask(title: 'Pending');
      final plugin = InstalledPlugin(
        manifest: PluginManifest.fromJson(const {
          'id': 'stats-test',
          'name': 'Stats test',
          'entry': 'main.lua',
        }),
        path: '.',
        enabled: true,
        grantedPermissions: const [],
        enabledFeaturePages: const [],
        enabledFunctions: const ['stats'],
      );

      final result = await service.execute(
        const LynAIFunctionCall(
          name: 'plugin.func',
          arguments: {'name': 'stats'},
        ),
        LynAIFunctionContext(
          tasks: tasks,
          plugins: _StatsPluginProvider(plugin),
          plugin: plugin,
        ),
      );

      expect(result['todos_done'], 1);
      expect(result['todos_total'], 2);
    });
  });
}

final class _StatsPluginProvider extends PluginProvider {
  _StatsPluginProvider(this.plugin);

  final InstalledPlugin plugin;

  @override
  InstalledPlugin? pluginById(String id) => id == plugin.id ? plugin : null;

  @override
  bool isFunctionEnabled(String pluginId, String functionName) {
    return pluginId == plugin.id && functionName == 'stats';
  }
}

final class _MemoryTaskRepository implements TaskRepository {
  @override
  Future<TaskLoadResult> load() async {
    return const TaskLoadResult(tasks: [], lists: [], entries: []);
  }

  @override
  Future<void> save({
    required List<Task> tasks,
    required List<TaskList> lists,
    required List<TaskListEntry> entries,
  }) async {}
}

final class _MemoryRecycleBinRepository implements RecycleBinRepository {
  final List<RecycleBinItem> _items = [];

  @override
  Future<void> add(RecycleBinItem item) async => _items.add(item);

  @override
  Future<List<RecycleBinItem>> load() async => List.of(_items);

  @override
  Future<void> remove(String id) async {
    _items.removeWhere((item) => item.id == id);
  }

  @override
  Future<void> save(List<RecycleBinItem> items) async {
    _items
      ..clear()
      ..addAll(items);
  }
}
