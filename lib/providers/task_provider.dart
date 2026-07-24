import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/item_reminder.dart';
import '../models/local_date.dart';
import '../models/local_time.dart';
import '../models/recycle_bin_item.dart';
import '../models/task.dart';
import '../models/task_list.dart';
import '../repositories/recycle_bin_repository.dart';
import '../repositories/task_repository.dart';
import '../services/storage_v2_service.dart';

/// 任务、清单元数据和清单归属条目的唯一内存所有者。
class TaskProvider extends ChangeNotifier {
  TaskProvider({
    StorageV2Service? storageV2,
    TaskRepository? repository,
    RecycleBinRepository? recycleBinRepository,
  }) : _repository = repository ?? TaskRepository(storageV2: storageV2),
       _recycleBinRepository =
           recycleBinRepository ?? RecycleBinRepository(storageV2: storageV2);

  final _uuid = const Uuid();
  final TaskRepository _repository;
  final RecycleBinRepository _recycleBinRepository;

  List<Task> _tasks = [];
  List<TaskList> _lists = [];
  List<TaskListEntry> _entries = [];
  int _mutationGeneration = 0;

  // tasks.json 的三类数据共享一条串行队列，避免旧快照覆盖连续操作的新状态。
  Future<void> _saveQueue = Future.value();
  Future<void> _pendingSave = Future.value();

  /// 完整任务快照成功持久化后触发；平台投影协调器据此串行同步。
  VoidCallback? onSnapshotPersisted;

  List<Task> get tasks => List.unmodifiable(_tasks);
  List<TaskList> get lists => List.unmodifiable(_lists);
  List<TaskListEntry> get entries => List.unmodifiable(_entries);

  Future<void> load() async {
    final generation = _mutationGeneration;
    await flushPendingSaves();
    final result = await _repository.load();
    if (generation != _mutationGeneration) return;
    _tasks = result.tasks;
    _lists = result.lists;
    _entries = result.entries;
    notifyListeners();
  }

  /// 用完整任务分区快照同步替换内存和持久化数据。
  Future<void> replaceAll({
    required List<Task> tasks,
    required List<TaskList> lists,
    required List<TaskListEntry> entries,
  }) async {
    _mutationGeneration++;
    _tasks = List.of(tasks);
    _lists = List.of(lists)..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final taskIds = _tasks.map((task) => task.id).toSet();
    final listIds = _lists.map((list) => list.id).toSet();
    _entries = entries
        .where(
          (entry) =>
              taskIds.contains(entry.taskId) &&
              listIds.contains(entry.taskListId),
        )
        .toList();
    notifyListeners();
    final replacementTasks = List<Task>.of(_tasks);
    final replacementLists = List<TaskList>.of(_lists);
    final replacementEntries = List<TaskListEntry>.of(_entries);
    await _queueSave(
      () => _repository.replace(
        tasks: replacementTasks,
        lists: replacementLists,
        entries: replacementEntries,
      ),
    );
  }

  Task? taskById(String id) => _firstOrNull(_tasks, (task) => task.id == id);

  TaskList? listById(String id) =>
      _firstOrNull(_lists, (list) => list.id == id);

  TaskListEntry? entryForTask(String taskId) =>
      _firstOrNull(_entries, (entry) => entry.taskId == taskId);

  List<Task> tasksForList(String listId) {
    final taskById = {for (final task in _tasks) task.id: task};
    final entries =
        _entries.where((entry) => entry.taskListId == listId).toList()
          ..sort((a, b) => a.position.compareTo(b.position));
    return List.unmodifiable([
      for (final entry in entries) ?taskById[entry.taskId],
    ]);
  }

  List<Task> get unlistedTasks {
    final listedIds = _entries.map((entry) => entry.taskId).toSet();
    return List.unmodifiable(
      _tasks.where((task) => !listedIds.contains(task.id)),
    );
  }

  List<Task> get unlisted => unlistedTasks;

  List<Task> get today => todayTasks();

  List<Task> get overdue => overdueTasks();

  List<Task> todayTasks([DateTime? now]) {
    final today = LocalDate.fromDateTime(now ?? DateTime.now());
    return List.unmodifiable(
      _tasks.where(
        (task) => task.plannedDate == today || task.dueDate == today,
      ),
    );
  }

  List<Task> overdueTasks([DateTime? now]) {
    final effectiveNow = now ?? DateTime.now();
    return List.unmodifiable(
      _tasks.where((task) => task.isOverdueAt(effectiveNow)),
    );
  }

  Future<String> addTask({
    required String title,
    String? note,
    LocalDate? plannedDate,
    LocalTime? plannedTime,
    LocalDate? dueDate,
    LocalTime? dueTime,
    List<ItemReminder> reminders = const [],
    String? listId,
  }) async {
    if (listId != null && listById(listId) == null) {
      throw ArgumentError.value(listId, 'listId', '任务清单不存在');
    }
    _mutationGeneration++;
    final now = DateTime.now();
    final task = Task(
      id: _uuid.v4(),
      title: title,
      note: note,
      plannedDate: plannedDate,
      plannedTime: plannedTime,
      dueDate: dueDate,
      dueTime: dueTime,
      createdAt: now,
      updatedAt: now,
      reminders: reminders,
    );
    _tasks.add(task);
    TaskListEntry? entry;
    if (listId != null) {
      entry = TaskListEntry(
        taskListId: listId,
        taskId: task.id,
        position: _nextPosition(listId),
        updatedAt: now,
      );
      _entries.add(entry);
    }
    notifyListeners();
    await _queueSave(
      () =>
          _repository.saveChanges(upsertTasks: [task], upsertEntries: [?entry]),
    );
    return task.id;
  }

  Future<void> updateTask(Task task) async {
    final index = _tasks.indexWhere((item) => item.id == task.id);
    if (index == -1) return;
    _mutationGeneration++;
    final updated = task.copyWith(
      createdAt: _tasks[index].createdAt,
      updatedAt: DateTime.now(),
    );
    _tasks[index] = updated;
    notifyListeners();
    await _queueSave(() => _repository.saveChanges(upsertTasks: [updated]));
  }

  Future<void> deleteTask(String id) async {
    final task = taskById(id);
    if (task == null) return;
    final entry = entryForTask(id);
    _mutationGeneration++;
    // 删除任务时连同可选归属条目进入回收站，确保恢复后顺序和清单归属可重建。
    await _recycleBinRepository.add(
      RecycleBinItem(
        owner: RecycleBinOwners.core,
        category: RecycleBinCategories.todos,
        type: RecycleBinItemTypes.task,
        title: task.title.isEmpty ? '未命名任务' : task.title,
        preview: task.note ?? '',
        payload: {
          'task': task.toJson(),
          if (entry != null) 'entry': entry.toJson(),
        },
      ),
    );
    _tasks.removeWhere((item) => item.id == id);
    _entries.removeWhere((item) => item.taskId == id);
    if (entry != null) _normalizeEntries(entry.taskListId, touch: true);
    final reorderedEntries = entry == null
        ? const <TaskListEntry>[]
        : _orderedEntries(entry.taskListId);
    notifyListeners();
    await _queueSave(
      () => _repository.saveChanges(
        deleteTaskIds: [id],
        deleteEntryTaskIds: [if (entry != null) id],
        upsertEntries: reorderedEntries,
      ),
    );
  }

  Future<void> restoreTask(Task task, {TaskListEntry? entry}) async {
    if (taskById(task.id) != null) return;
    _mutationGeneration++;
    _tasks.add(task);
    if (entry != null && listById(entry.taskListId) != null) {
      _entries.removeWhere((item) => item.taskId == task.id);
      final ordered = _orderedEntries(entry.taskListId);
      ordered.insert(
        entry.position.clamp(0, ordered.length),
        entry.copyWith(updatedAt: DateTime.now()),
      );
      _replaceEntries(entry.taskListId, ordered, touch: true);
    }
    final restoredEntry = entry == null || listById(entry.taskListId) == null
        ? const <TaskListEntry>[]
        : _orderedEntries(entry.taskListId);
    notifyListeners();
    await _queueSave(
      () => _repository.saveChanges(
        upsertTasks: [task],
        upsertEntries: restoredEntry,
      ),
    );
  }

  Future<void> completeTask(String id) => _setCompleted(id, true);

  Future<void> uncompleteTask(String id) => _setCompleted(id, false);

  Future<String> addList(String title) async {
    _mutationGeneration++;
    final now = DateTime.now();
    final list = TaskList(
      id: _uuid.v4(),
      title: title,
      sortOrder: _lists.length,
      createdAt: now,
      updatedAt: now,
    );
    _lists.add(list);
    notifyListeners();
    await _queueSave(() => _repository.saveChanges(upsertLists: [list]));
    return list.id;
  }

  Future<void> updateList(TaskList list) async {
    final index = _lists.indexWhere((item) => item.id == list.id);
    if (index == -1) return;
    _mutationGeneration++;
    final updated = list.copyWith(
      sortOrder: _lists[index].sortOrder,
      createdAt: _lists[index].createdAt,
      updatedAt: DateTime.now(),
    );
    _lists[index] = updated;
    notifyListeners();
    await _queueSave(() => _repository.saveChanges(upsertLists: [updated]));
  }

  Future<void> deleteList(String id) async {
    final list = listById(id);
    if (list == null) return;
    final entries = _entries.where((entry) => entry.taskListId == id).toList();
    _mutationGeneration++;
    // 删除清单只回收清单和归属条目；任务实体继续保留并转为未归类任务。
    await _recycleBinRepository.add(
      RecycleBinItem(
        owner: RecycleBinOwners.core,
        category: RecycleBinCategories.todos,
        type: RecycleBinItemTypes.taskList,
        title: list.title.isEmpty ? '未命名任务清单' : list.title,
        preview: '${entries.length} 个任务条目',
        payload: {
          'list': list.toJson(),
          'entries': entries.map((entry) => entry.toJson()).toList(),
        },
      ),
    );
    _lists.removeWhere((item) => item.id == id);
    _entries.removeWhere((entry) => entry.taskListId == id);
    _normalizeLists();
    final normalizedLists = List<TaskList>.of(_lists);
    notifyListeners();
    await _queueSave(
      () => _repository.saveChanges(
        deleteListIds: [id],
        deleteEntryTaskIds: entries.map((entry) => entry.taskId),
        upsertLists: normalizedLists,
      ),
    );
  }

  Future<void> restoreList(
    TaskList list, {
    Iterable<TaskListEntry> entries = const [],
  }) async {
    if (listById(list.id) != null) return;
    _mutationGeneration++;
    _lists.insert(
      list.sortOrder.clamp(0, _lists.length),
      list.copyWith(sortOrder: list.sortOrder.clamp(0, _lists.length)),
    );
    _normalizeLists();
    final affectedListIds = <String>{list.id};
    for (final entry in entries) {
      if (entry.taskListId != list.id || taskById(entry.taskId) == null) {
        continue;
      }
      final previous = entryForTask(entry.taskId);
      if (previous != null) affectedListIds.add(previous.taskListId);
      _entries.removeWhere((item) => item.taskId == entry.taskId);
      _entries.add(entry);
    }
    for (final listId in affectedListIds) {
      _normalizeEntries(listId, touch: true);
    }
    final normalizedLists = List<TaskList>.of(_lists);
    final affectedEntries = [
      for (final listId in affectedListIds) ..._orderedEntries(listId),
    ];
    notifyListeners();
    await _queueSave(
      () => _repository.saveChanges(
        upsertLists: normalizedLists,
        upsertEntries: affectedEntries,
      ),
    );
  }

  Future<void> moveTask(String taskId, String? listId, {int? position}) async {
    if (taskById(taskId) == null) return;
    if (listId != null && listById(listId) == null) {
      throw ArgumentError.value(listId, 'listId', '任务清单不存在');
    }
    _mutationGeneration++;
    final previous = entryForTask(taskId);
    _entries.removeWhere((entry) => entry.taskId == taskId);
    if (previous != null) _normalizeEntries(previous.taskListId, touch: true);
    if (listId != null) {
      final ordered = _orderedEntries(listId);
      ordered.insert(
        (position ?? ordered.length).clamp(0, ordered.length),
        TaskListEntry(
          taskListId: listId,
          taskId: taskId,
          position: 0,
          updatedAt: DateTime.now(),
        ),
      );
      _replaceEntries(listId, ordered, touch: true);
    }
    final affectedListIds = <String>{?previous?.taskListId, ?listId};
    final affectedEntries = [
      for (final affectedListId in affectedListIds)
        ..._orderedEntries(affectedListId),
    ];
    notifyListeners();
    await _queueSave(
      () => _repository.saveChanges(
        deleteEntryTaskIds: [if (listId == null && previous != null) taskId],
        upsertEntries: affectedEntries,
      ),
    );
  }

  Future<void> reorderTaskEntries(
    String listId,
    int oldIndex,
    int newIndex,
  ) async {
    final ordered = _orderedEntries(listId);
    if (oldIndex < 0 || oldIndex >= ordered.length) return;
    if (newIndex < 0 || newIndex >= ordered.length) return;
    _mutationGeneration++;
    final entry = ordered.removeAt(oldIndex);
    ordered.insert(newIndex, entry);
    _replaceEntries(listId, ordered, touch: true);
    final updatedEntries = _orderedEntries(listId);
    notifyListeners();
    await _queueSave(
      () => _repository.saveChanges(upsertEntries: updatedEntries),
    );
  }

  Future<void> reorderLists(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _lists.length) return;
    if (newIndex < 0 || newIndex >= _lists.length) return;
    _mutationGeneration++;
    final list = _lists.removeAt(oldIndex);
    _lists.insert(newIndex, list);
    _normalizeLists();
    final updatedLists = List<TaskList>.of(_lists);
    notifyListeners();
    await _queueSave(() => _repository.saveChanges(upsertLists: updatedLists));
  }

  Future<void> flushPendingSaves() => _pendingSave;

  Future<void> _setCompleted(String id, bool completed) async {
    final index = _tasks.indexWhere((task) => task.id == id);
    if (index == -1 || _tasks[index].isCompleted == completed) return;
    _mutationGeneration++;
    final now = DateTime.now();
    _tasks[index] = _tasks[index].copyWith(
      completedAt: completed ? now : null,
      updatedAt: now,
    );
    notifyListeners();
    final updated = _tasks[index];
    await _queueSave(() => _repository.saveChanges(upsertTasks: [updated]));
  }

  int _nextPosition(String listId) =>
      _entries.where((entry) => entry.taskListId == listId).length;

  void _normalizeEntries(String listId, {bool touch = false}) {
    _replaceEntries(listId, _orderedEntries(listId), touch: touch);
  }

  List<TaskListEntry> _orderedEntries(String listId) {
    return _entries.where((entry) => entry.taskListId == listId).toList()
      ..sort((a, b) => a.position.compareTo(b.position));
  }

  void _replaceEntries(
    String listId,
    List<TaskListEntry> ordered, {
    bool touch = false,
  }) {
    final now = DateTime.now();
    _entries.removeWhere((entry) => entry.taskListId == listId);
    _entries.addAll([
      for (var i = 0; i < ordered.length; i++)
        ordered[i].copyWith(
          position: i,
          updatedAt: touch ? now : ordered[i].updatedAt,
        ),
    ]);
  }

  void _normalizeLists() {
    final now = DateTime.now();
    _lists = [
      for (var i = 0; i < _lists.length; i++)
        _lists[i].copyWith(sortOrder: i, updatedAt: now),
    ];
  }

  Future<void> _queueSave(Future<void> Function() save) {
    final operation = _saveQueue.then((_) async {
      await save();
      onSnapshotPersisted?.call();
    });
    _pendingSave = operation;
    _saveQueue = operation.catchError((Object error) {
      debugPrint('保存任务分区失败: $error');
    });
    return operation;
  }
}

T? _firstOrNull<T>(Iterable<T> values, bool Function(T) test) {
  for (final value in values) {
    if (test(value)) return value;
  }
  return null;
}
