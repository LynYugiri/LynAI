import 'package:flutter/foundation.dart';

import '../models/task.dart';
import '../models/task_list.dart';
import '../services/storage_v2_service.dart';

final class TaskLoadResult {
  const TaskLoadResult({
    required this.tasks,
    required this.lists,
    required this.entries,
  });

  final List<Task> tasks;
  final List<TaskList> lists;
  final List<TaskListEntry> entries;
}

/// Canonical persistence boundary for the `tasks.json` partition.
class TaskRepository {
  factory TaskRepository({StorageV2Service? storageV2}) {
    return TaskRepository._(storageV2 ?? StorageV2Service());
  }

  TaskRepository._(this._storageV2);

  static const _fileName = 'tasks.json';

  final StorageV2Service _storageV2;

  Future<TaskLoadResult> load() async {
    final data = await _storageV2.loadDataFile(_fileName);
    final tasks = _decodeList(data['tasks'], Task.fromJson, '任务');
    final lists = _decodeList(data['lists'], TaskList.fromJson, '任务清单')
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final taskIds = tasks.map((task) => task.id).toSet();
    final listIds = lists.map((list) => list.id).toSet();
    final entries = <TaskListEntry>[];
    for (final item in data['entries'] as List<dynamic>? ?? const []) {
      try {
        if (item is! Map) continue;
        final json = Map<String, dynamic>.from(item);
        final entry = TaskListEntry(
          taskListId: json['listId'] as String,
          taskId: json['taskId'] as String? ?? json['id'] as String,
          position: (json['sortOrder'] as num).toInt(),
          updatedAt: DateTime.parse(json['updatedAt'] as String),
        );
        if (taskIds.contains(entry.taskId) &&
            listIds.contains(entry.taskListId)) {
          entries.add(entry);
        }
      } catch (error) {
        debugPrint('跳过损坏的任务清单条目: $error');
      }
    }
    entries.sort((a, b) {
      final listOrder = a.taskListId.compareTo(b.taskListId);
      return listOrder != 0 ? listOrder : a.position.compareTo(b.position);
    });
    return TaskLoadResult(tasks: tasks, lists: lists, entries: entries);
  }

  Future<void> save({
    required List<Task> tasks,
    required List<TaskList> lists,
    required List<TaskListEntry> entries,
  }) {
    return _storageV2.writeDataFile(_fileName, {
      'tasks': tasks.map((task) => task.toJson()).toList(),
      'lists': lists.map((list) => list.toJson()).toList(),
      'entries': entries
          .map(
            (entry) => {
              'id': entry.taskId,
              'taskId': entry.taskId,
              'listId': entry.taskListId,
              'sortOrder': entry.position,
              'updatedAt': entry.updatedAt.toIso8601String(),
            },
          )
          .toList(),
    });
  }
}

List<T> _decodeList<T>(
  Object? raw,
  T Function(Map<String, dynamic>) decode,
  String label,
) {
  final result = <T>[];
  for (final item in raw as List<dynamic>? ?? const []) {
    try {
      if (item is Map) result.add(decode(Map<String, dynamic>.from(item)));
    } catch (error) {
      debugPrint('跳过损坏的$label: $error');
    }
  }
  return result;
}
