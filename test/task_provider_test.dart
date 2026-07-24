import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/local_date.dart';
import 'package:lynai/models/recycle_bin_item.dart';
import 'package:lynai/models/task.dart';
import 'package:lynai/models/task_list.dart';
import 'package:lynai/providers/task_provider.dart';
import 'package:lynai/repositories/recycle_bin_repository.dart';
import 'package:lynai/repositories/task_repository.dart';
import 'package:lynai/services/storage_v2_service.dart';

void main() {
  test('mutations notify before one serialized snapshot save queue', () async {
    final repository = _TaskRepository(blockFirstSave: true);
    final provider = TaskProvider(
      repository: repository,
      recycleBinRepository: _RecycleBinRepository(),
    );
    var notifications = 0;
    provider.addListener(() => notifications++);

    final first = provider.addTask(title: 'first');
    await repository.firstSaveStarted.future;
    expect(provider.tasks.single.title, 'first');
    expect(notifications, 1);

    final second = provider.addTask(title: 'second');
    await Future<void>.delayed(Duration.zero);
    expect(provider.tasks, hasLength(2));
    expect(notifications, 2);
    expect(repository.concurrentSaves, 1);

    repository.allowFirstSave.complete();
    await Future.wait([first, second]);
    await provider.flushPendingSaves();
    expect(repository.maxConcurrentSaves, 1);
    expect(repository.snapshots.last.tasks, hasLength(2));
  });

  test('load waits for pending saves before reading the repository', () async {
    final repository = _TaskRepository(blockFirstSave: true);
    final provider = TaskProvider(
      repository: repository,
      recycleBinRepository: _RecycleBinRepository(),
    );

    final save = provider.addTask(title: 'pending');
    await repository.firstSaveStarted.future;
    final load = provider.load();
    await Future<void>.delayed(Duration.zero);

    expect(repository.loadCalls, 0);
    repository.allowFirstSave.complete();
    await Future.wait([save, load]);

    expect(repository.loadCalls, 1);
    expect(provider.tasks.single.title, 'pending');
  });

  test('mutation during a blocked load wins in memory and storage', () async {
    final repository = _TaskRepository(blockLoad: true);
    final provider = TaskProvider(
      repository: repository,
      recycleBinRepository: _RecycleBinRepository(),
    );
    await provider.addTask(title: 'existing');

    final load = provider.load();
    await repository.loadStarted.future;
    final mutation = provider.addTask(title: 'concurrent');
    await mutation;
    repository.allowLoad.complete();
    await load;

    expect(provider.tasks.map((task) => task.title), [
      'existing',
      'concurrent',
    ]);
    expect(repository.persistedSnapshot!.tasks.map((task) => task.title), [
      'existing',
      'concurrent',
    ]);
  });

  test('failed load preserves current memory', () async {
    final repository = _TaskRepository(loadError: StateError('load failed'));
    final provider = TaskProvider(
      repository: repository,
      recycleBinRepository: _RecycleBinRepository(),
    );
    await provider.addTask(title: 'current');

    await expectLater(provider.load(), throwsStateError);

    expect(provider.tasks.single.title, 'current');
  });

  test(
    'queries, movement, completion, and ordering use domain entries',
    () async {
      final provider = TaskProvider(
        repository: _TaskRepository(),
        recycleBinRepository: _RecycleBinRepository(),
      );
      final firstList = await provider.addList('First');
      final secondList = await provider.addList('Second');
      final today = DateTime(2026, 7, 22, 12);
      final firstTask = await provider.addTask(
        title: 'Today',
        listId: firstList,
        plannedDate: LocalDate(2026, 7, 22),
      );
      final overdue = await provider.addTask(
        title: 'Overdue',
        listId: firstList,
        dueDate: LocalDate(2026, 7, 21),
      );

      await provider.reorderTaskEntries(firstList, 1, 0);
      expect(provider.tasksForList(firstList).map((task) => task.id), [
        overdue,
        firstTask,
      ]);
      await provider.moveTask(firstTask, secondList);
      expect(provider.tasksForList(secondList).single.id, firstTask);
      await provider.moveTask(overdue, null);
      expect(provider.unlistedTasks.single.id, overdue);
      expect(provider.todayTasks(today).single.id, firstTask);
      expect(provider.overdueTasks(today).single.id, overdue);

      await provider.completeTask(overdue);
      expect(provider.taskById(overdue)!.isCompleted, isTrue);
      expect(provider.overdueTasks(today), isEmpty);
      await provider.uncompleteTask(overdue);
      expect(provider.taskById(overdue)!.isCompleted, isFalse);

      await provider.reorderLists(1, 0);
      expect(provider.lists.map((list) => list.id), [secondList, firstList]);
      expect(provider.lists.map((list) => list.sortOrder), [0, 1]);
    },
  );

  test(
    'task deletion recycles task and entry then restore rebuilds both',
    () async {
      final recycleBin = _RecycleBinRepository();
      final provider = TaskProvider(
        repository: _TaskRepository(),
        recycleBinRepository: recycleBin,
      );
      final listId = await provider.addList('List');
      final taskId = await provider.addTask(title: 'Task', listId: listId);

      await provider.deleteTask(taskId);

      expect(provider.tasks, isEmpty);
      expect(provider.entries, isEmpty);
      final recycled = recycleBin.items.single;
      expect(recycled.type, RecycleBinItemTypes.task);
      expect(recycled.payload['task'], isA<Map>());
      expect(recycled.payload['entry'], isA<Map>());

      await provider.restoreTask(
        Task.fromJson(
          Map<String, dynamic>.from(recycled.payload['task'] as Map),
        ),
        entry: TaskListEntry.fromJson(
          Map<String, dynamic>.from(recycled.payload['entry'] as Map),
        ),
      );
      expect(provider.tasksForList(listId).single.id, taskId);
    },
  );

  test('list deletion recycles list and entries but preserves tasks', () async {
    final recycleBin = _RecycleBinRepository();
    final provider = TaskProvider(
      repository: _TaskRepository(),
      recycleBinRepository: recycleBin,
    );
    final listId = await provider.addList('List');
    final taskId = await provider.addTask(title: 'Task', listId: listId);

    await provider.deleteList(listId);

    expect(provider.lists, isEmpty);
    expect(provider.entries, isEmpty);
    expect(provider.tasks.single.id, taskId);
    expect(provider.unlistedTasks.single.id, taskId);
    final recycled = recycleBin.items.single;
    expect(recycled.type, RecycleBinItemTypes.taskList);
    expect(recycled.payload['list'], isA<Map>());
    expect(recycled.payload['entries'], hasLength(1));
  });

  test('runtime mutations capture task and entry row outbox changes', () async {
    final root = await Directory.systemTemp.createTemp('lynai_task_rows_');
    final storage = StorageV2Service(rootDirectory: root);
    const scope = 'server|task-provider';
    try {
      await storage.activateSyncScope(scope, deviceId: 'device-task');
      final provider = TaskProvider(
        storageV2: storage,
        recycleBinRepository: _RecycleBinRepository(),
      );
      final firstList = await provider.addList('First');
      final secondList = await provider.addList('Second');
      final firstTask = await provider.addTask(
        title: 'First task',
        listId: firstList,
      );
      final secondTask = await provider.addTask(
        title: 'Second task',
        listId: firstList,
      );
      await _ackOutbox(storage, scope);

      await provider.completeTask(firstTask);
      var outbox = await storage.loadSyncOutbox(scope);
      expect(outbox, hasLength(1));
      expect(outbox.single.table, 'tasks');
      expect(outbox.single.data?['completedAt'], isNotNull);
      await _ackOutbox(storage, scope);

      await provider.reorderTaskEntries(firstList, 1, 0);
      outbox = await storage.loadSyncOutbox(scope);
      expect(
        outbox.map((entry) => '${entry.table}:${entry.recordId}'),
        unorderedEquals([
          'task_list_entries:$firstTask',
          'task_list_entries:$secondTask',
        ]),
      );
      expect(
        outbox.singleWhere((entry) => entry.recordId == secondTask).data,
        containsPair('sortOrder', 0),
      );
      await _ackOutbox(storage, scope);

      await provider.moveTask(firstTask, secondList);
      outbox = await storage.loadSyncOutbox(scope);
      expect(
        outbox.map((entry) => '${entry.table}:${entry.recordId}'),
        unorderedEquals([
          'task_list_entries:$firstTask',
          'task_list_entries:$secondTask',
        ]),
      );
      expect(
        outbox.singleWhere((entry) => entry.recordId == firstTask).data,
        containsPair('listId', secondList),
      );
      await _ackOutbox(storage, scope);

      await provider.deleteTask(secondTask);
      outbox = await storage.loadSyncOutbox(scope);
      expect(
        outbox.map((entry) => '${entry.table}:${entry.recordId}:${entry.op}'),
        containsAll([
          'tasks:$secondTask:delete',
          'task_list_entries:$secondTask:delete',
        ]),
      );
      final loaded = await TaskRepository(storageV2: storage).load();
      expect(loaded.tasks.map((task) => task.id), isNot(contains(secondTask)));
      expect(loaded.entries.map((entry) => entry.taskId), [firstTask]);
    } finally {
      await storage.close();
      if (await root.exists()) await root.delete(recursive: true);
    }
  });
}

Future<void> _ackOutbox(StorageV2Service storage, String scope) async {
  await storage.acknowledgeSyncOutbox(
    scope,
    await storage.loadSyncOutbox(scope),
  );
}

final class _TaskSnapshot {
  const _TaskSnapshot(this.tasks, this.lists, this.entries);

  final List<Task> tasks;
  final List<TaskList> lists;
  final List<TaskListEntry> entries;
}

final class _TaskRepository implements TaskRepository {
  _TaskRepository({
    this.blockFirstSave = false,
    this.blockLoad = false,
    this.loadError,
  });

  final bool blockFirstSave;
  final bool blockLoad;
  final Object? loadError;
  final firstSaveStarted = Completer<void>();
  final allowFirstSave = Completer<void>();
  final loadStarted = Completer<void>();
  final allowLoad = Completer<void>();
  final List<_TaskSnapshot> snapshots = [];
  int concurrentSaves = 0;
  int maxConcurrentSaves = 0;
  int loadCalls = 0;
  _TaskSnapshot? persistedSnapshot;

  @override
  Future<TaskLoadResult> load() async {
    loadCalls++;
    final snapshot = persistedSnapshot;
    if (!loadStarted.isCompleted) loadStarted.complete();
    if (blockLoad) await allowLoad.future;
    if (loadError case final error?) throw error;
    return TaskLoadResult(
      tasks: snapshot?.tasks ?? const [],
      lists: snapshot?.lists ?? const [],
      entries: snapshot?.entries ?? const [],
    );
  }

  @override
  Future<void> replace({
    required List<Task> tasks,
    required List<TaskList> lists,
    required List<TaskListEntry> entries,
  }) {
    return _persist(() {
      persistedSnapshot = _TaskSnapshot(tasks, lists, entries);
    });
  }

  @override
  Future<void> saveChanges({
    Iterable<Task> upsertTasks = const [],
    Iterable<String> deleteTaskIds = const [],
    Iterable<TaskList> upsertLists = const [],
    Iterable<String> deleteListIds = const [],
    Iterable<TaskListEntry> upsertEntries = const [],
    Iterable<String> deleteEntryTaskIds = const [],
  }) {
    return _persist(() {
      final tasks = {
        for (final task in persistedSnapshot?.tasks ?? const <Task>[])
          task.id: task,
      };
      final lists = {
        for (final list in persistedSnapshot?.lists ?? const <TaskList>[])
          list.id: list,
      };
      final entries = {
        for (final entry
            in persistedSnapshot?.entries ?? const <TaskListEntry>[])
          entry.taskId: entry,
      };
      for (final id in deleteEntryTaskIds) {
        entries.remove(id);
      }
      for (final id in deleteTaskIds) {
        tasks.remove(id);
        entries.remove(id);
      }
      for (final id in deleteListIds) {
        lists.remove(id);
        entries.removeWhere((_, entry) => entry.taskListId == id);
      }
      for (final task in upsertTasks) {
        tasks[task.id] = task;
      }
      for (final list in upsertLists) {
        lists[list.id] = list;
      }
      for (final entry in upsertEntries) {
        entries[entry.taskId] = entry;
      }
      persistedSnapshot = _TaskSnapshot(
        tasks.values.toList(),
        lists.values.toList(),
        entries.values.toList(),
      );
    });
  }

  Future<void> _persist(void Function() apply) async {
    concurrentSaves++;
    if (concurrentSaves > maxConcurrentSaves) {
      maxConcurrentSaves = concurrentSaves;
    }
    if (!firstSaveStarted.isCompleted) {
      firstSaveStarted.complete();
      if (blockFirstSave) await allowFirstSave.future;
    }
    apply();
    snapshots.add(persistedSnapshot!);
    concurrentSaves--;
  }
}

final class _RecycleBinRepository implements RecycleBinRepository {
  final List<RecycleBinItem> items = [];

  @override
  Future<void> add(RecycleBinItem item) async => items.add(item);

  @override
  Future<List<RecycleBinItem>> load() async => List.of(items);

  @override
  Future<void> remove(String id) async {
    items.removeWhere((item) => item.id == id);
  }

  @override
  Future<void> save(List<RecycleBinItem> items) async {
    this.items
      ..clear()
      ..addAll(items);
  }
}
