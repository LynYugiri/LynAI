import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/local_date.dart';
import 'package:lynai/models/task.dart';
import 'package:lynai/models/task_list.dart';
import 'package:lynai/repositories/task_repository.dart';
import 'package:lynai/services/storage_v2_service.dart';

void main() {
  test('TaskRepository round-trips the canonical tasks.json shape', () async {
    final root = await Directory.systemTemp.createTemp('lynai_tasks_repo_');
    final storage = StorageV2Service(rootDirectory: root);
    try {
      final repository = TaskRepository(storageV2: storage);
      final createdAt = DateTime(2026, 7, 22, 8);
      final task = Task(
        id: 'task-1',
        title: 'Plan',
        plannedDate: LocalDate(2026, 7, 23),
        createdAt: createdAt,
        updatedAt: createdAt,
      );
      final list = TaskList(
        id: 'list-1',
        title: 'Inbox',
        sortOrder: 0,
        createdAt: createdAt,
        updatedAt: createdAt,
      );
      final entry = TaskListEntry(
        taskListId: list.id,
        taskId: task.id,
        position: 0,
        updatedAt: createdAt,
      );

      await repository.save(tasks: [task], lists: [list], entries: [entry]);

      final raw = await storage.loadDataFile('tasks.json');
      expect(raw.keys, containsAll(['tasks', 'lists', 'entries']));
      expect((raw['entries'] as List).single, {
        'id': 'task-1',
        'taskId': 'task-1',
        'listId': 'list-1',
        'sortOrder': 0,
        'updatedAt': createdAt.toIso8601String(),
      });

      final loaded = await repository.load();
      expect(loaded.tasks.single.toJson(), task.toJson());
      expect(loaded.lists.single.toJson(), list.toJson());
      expect(loaded.entries.single.toJson(), entry.toJson());
    } finally {
      await storage.close();
      if (await root.exists()) await root.delete(recursive: true);
    }
  });
}
