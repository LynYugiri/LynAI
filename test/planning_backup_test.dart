import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/anniversary.dart';
import 'package:lynai/models/backup_models.dart';
import 'package:lynai/models/calendar_event.dart';
import 'package:lynai/models/local_date.dart';
import 'package:lynai/models/schedule_item.dart';
import 'package:lynai/models/task.dart';
import 'package:lynai/models/task_list.dart';
import 'package:lynai/models/todo_list.dart' as legacy;
import 'package:lynai/providers/calendar_provider.dart';
import 'package:lynai/providers/conversation_provider.dart';
import 'package:lynai/providers/feature_provider.dart';
import 'package:lynai/providers/model_config_provider.dart';
import 'package:lynai/providers/roleplay_provider.dart';
import 'package:lynai/providers/settings_provider.dart';
import 'package:lynai/providers/task_provider.dart';
import 'package:lynai/services/backup_service.dart';
import 'package:lynai/services/storage_v2_service.dart';
import 'package:lynai/services/storage_v2_upgrade_service.dart';

void main() {
  test(
    'schema 9 writes canonical planning wire shape and round-trips',
    () async {
      final sourceRoot = await Directory.systemTemp.createTemp(
        'planning_backup_source_',
      );
      final targetRoot = await Directory.systemTemp.createTemp(
        'planning_backup_target_',
      );
      try {
        final sourceStorage = await _readyStorage(sourceRoot);
        final sourceTasks = TaskProvider(storageV2: sourceStorage);
        final sourceCalendar = CalendarProvider(storageV2: sourceStorage);
        final now = DateTime(2026, 7, 22, 9);
        await sourceTasks.replaceAll(
          tasks: [
            Task(
              id: 'task',
              title: 'Task',
              plannedDate: LocalDate(2026, 7, 23),
              createdAt: now,
              updatedAt: now,
            ),
          ],
          lists: [
            TaskList(
              id: 'list',
              title: 'List',
              sortOrder: 0,
              createdAt: now,
              updatedAt: now,
            ),
          ],
          entries: [
            TaskListEntry(
              taskListId: 'list',
              taskId: 'task',
              position: 0,
              updatedAt: now,
            ),
          ],
        );
        await sourceCalendar.replaceAll(
          events: [
            CalendarEvent(
              id: 'event',
              title: 'Event',
              spec: TimedCalendarEventSpec(
                start: now,
                end: now.add(const Duration(hours: 1)),
              ),
              createdAt: now,
              updatedAt: now,
            ),
          ],
          anniversaries: [
            Anniversary(
              id: 'anniversary',
              title: 'Anniversary',
              spec: YearlyAnniversarySpec(month: 7, day: 22),
              createdAt: now,
              updatedAt: now,
            ),
          ],
        );
        final bytes = await _service(sourceTasks, sourceCalendar, sourceStorage)
            .exportZipBytes(
              const BackupSelection(
                {BackupSection.tasks, BackupSection.calendar},
                taskIds: {'task'},
                taskListIds: {'list'},
                calendarEventIds: {'event'},
                anniversaryIds: {'anniversary'},
              ),
            );

        final zip = ZipDecoder().decodeBytes(bytes);
        Map<String, dynamic> jsonFile(String path) =>
            jsonDecode(
                  utf8.decode(
                    zip.files.singleWhere((file) => file.name == path).content
                        as List<int>,
                  ),
                )
                as Map<String, dynamic>;
        expect(jsonFile('manifest.json')['schemaVersion'], 9);
        expect(jsonFile('tasks.json')['entries'].single, {
          'id': 'task',
          'taskId': 'task',
          'listId': 'list',
          'sortOrder': 0,
          'updatedAt': now.toIso8601String(),
        });
        expect(
          jsonFile('calendar.json')['events'].single,
          containsPair('timeKind', 'timed'),
        );
        expect(
          jsonFile('calendar.json')['events'].single,
          isNot(contains('spec')),
        );

        final targetStorage = await _readyStorage(targetRoot);
        final targetTasks = TaskProvider(storageV2: targetStorage);
        final targetCalendar = CalendarProvider(storageV2: targetStorage);
        await targetTasks.replaceAll(
          tasks: [
            Task(
              id: 'extra-task',
              title: 'Extra task',
              createdAt: now,
              updatedAt: now,
            ),
          ],
          lists: [
            TaskList(
              id: 'extra-list',
              title: 'Extra list',
              sortOrder: 0,
              createdAt: now,
              updatedAt: now,
            ),
          ],
          entries: [
            TaskListEntry(
              taskListId: 'extra-list',
              taskId: 'extra-task',
              position: 0,
              updatedAt: now,
            ),
          ],
        );
        await targetCalendar.replaceAll(
          events: [
            CalendarEvent(
              id: 'extra-event',
              title: 'Extra event',
              spec: TimedCalendarEventSpec(
                start: now,
                end: now.add(const Duration(hours: 1)),
              ),
              createdAt: now,
              updatedAt: now,
            ),
          ],
          anniversaries: [
            Anniversary(
              id: 'extra-anniversary',
              title: 'Extra anniversary',
              spec: YearlyAnniversarySpec(month: 8, day: 1),
              createdAt: now,
              updatedAt: now,
            ),
          ],
        );
        final service = _service(targetTasks, targetCalendar, targetStorage);
        final archive = await service.readZipBytes(bytes);
        await service.importArchive(
          archive,
          ImportPlan(
            selection: BackupSelection.fromData(archive.data),
            mode: ImportMode.replaceSection,
          ),
        );
        expect(targetTasks.tasksForList('list').single.id, 'task');
        expect(targetTasks.tasks.map((item) => item.id), ['task']);
        expect(targetTasks.lists.map((item) => item.id), ['list']);
        expect(targetCalendar.events.single.id, 'event');
        expect(targetCalendar.anniversaries.single.id, 'anniversary');
      } finally {
        await sourceRoot.delete(recursive: true);
        await targetRoot.delete(recursive: true);
      }
    },
  );

  test(
    'schema 8 legacy planning conversion uses deterministic collision IDs',
    () async {
      final tasks = TaskProvider();
      final calendar = CalendarProvider();
      final service = _service(tasks, calendar, null);
      final at = DateTime(2026, 7, 22, 10);
      final schedulesBytes = utf8.encode(
        jsonEncode({
          'schedules': [
            ScheduleItem(
              id: 'same',
              title: 'Scheduled task',
              start: at,
              end: at.add(const Duration(minutes: 1)),
              kind: ScheduleItem.kindTask,
            ).toJson(),
          ],
        }),
      );
      final todosBytes = utf8.encode(
        jsonEncode({
          'todoLists': [
            legacy.TodoList(
              id: 'list',
              title: 'Legacy',
              items: const [legacy.TodoItem(id: 'same', text: 'Todo task')],
              createdAt: at,
              updatedAt: at,
            ).toJson(),
          ],
        }),
      );
      final zip = Archive()
        ..addFile(
          ArchiveFile('schedules.json', schedulesBytes.length, schedulesBytes),
        )
        ..addFile(
          ArchiveFile('todo_lists.json', todosBytes.length, todosBytes),
        );
      final manifest = {
        'type': 'lynai.backup',
        'schemaVersion': 8,
        'sections': {
          'schedules': {
            'enabled': true,
            'files': ['schedules.json'],
          },
          'todoLists': {
            'enabled': true,
            'files': ['todo_lists.json'],
          },
        },
      };
      final manifestBytes = utf8.encode(jsonEncode(manifest));
      zip.addFile(
        ArchiveFile('manifest.json', manifestBytes.length, manifestBytes),
      );

      final archive = await service.readZipBytes(ZipEncoder().encode(zip));
      expect(archive.data.tasks!.map((task) => task.id), [
        'same',
        'legacy-schedule-task-same',
      ]);
      expect(archive.data.taskEntries!.single.taskId, 'same');
      expect(archive.availableSections, contains(BackupSection.tasks));
    },
  );

  group('schema 9 mixed task/list conflict topology', () {
    late Directory root;
    late TaskProvider tasks;
    late BackupService service;
    final now = DateTime(2026, 7, 22);
    final localTask = Task(
      id: 'task',
      title: 'Local task',
      createdAt: now,
      updatedAt: now,
    );
    final localList = TaskList(
      id: 'list',
      title: 'Local list',
      sortOrder: 0,
      createdAt: now,
      updatedAt: now,
    );

    setUp(() async {
      root = await Directory.systemTemp.createTemp('planning_topology_');
      final storage = await _readyStorage(root);
      tasks = TaskProvider(storageV2: storage);
      await tasks.replaceAll(
        tasks: [localTask],
        lists: [localList],
        entries: [
          TaskListEntry(
            taskListId: 'list',
            taskId: 'task',
            position: 0,
            updatedAt: now,
          ),
        ],
      );
      service = _service(tasks, CalendarProvider(storageV2: storage), storage);
    });

    tearDown(() => root.delete(recursive: true));

    Future<ImportResult> importPlanning({
      required Task incomingTask,
      required TaskList incomingList,
      required ImportConflictAction taskAction,
      required ImportConflictAction listAction,
      ImportMode mode = ImportMode.merge,
    }) {
      return service.importArchive(
        BackupArchiveData(
          manifest: const {},
          data: BackupData(
            tasks: [incomingTask],
            taskLists: [incomingList],
            taskEntries: [
              TaskListEntry(
                taskListId: 'list',
                taskId: 'task',
                position: 0,
                updatedAt: now,
              ),
            ],
          ),
        ),
        ImportPlan(
          selection: const BackupSelection(
            {BackupSection.tasks},
            taskIds: {'task'},
            taskListIds: {'list'},
          ),
          mode: mode,
          conflictActions: {
            'tasks:list:list': listAction,
            'tasks:task:task': taskAction,
          },
        ),
      );
    }

    Task importedTask() => Task(
      id: 'task',
      title: 'Imported task',
      createdAt: now,
      updatedAt: now,
    );

    TaskList importedList() => TaskList(
      id: 'list',
      title: 'Imported list',
      sortOrder: 0,
      createdAt: now,
      updatedAt: now,
    );

    void expectNoDanglingEntries() {
      final taskIds = tasks.tasks.map((task) => task.id).toSet();
      final listIds = tasks.lists.map((list) => list.id).toSet();
      expect(
        tasks.entries.map((entry) => entry.taskId).toSet().length,
        tasks.entries.length,
      );
      expect(
        tasks.entries.every((entry) => taskIds.contains(entry.taskId)),
        isTrue,
      );
      expect(
        tasks.entries.every((entry) => listIds.contains(entry.taskListId)),
        isTrue,
      );
    }

    test('copied list clones an identical task instead of moving it', () async {
      final result = await importPlanning(
        incomingTask: localTask,
        incomingList: importedList(),
        taskAction: ImportConflictAction.keepLocal,
        listAction: ImportConflictAction.keepBoth,
      );

      final copiedList = tasks.lists.singleWhere((list) => list.id != 'list');
      expect(tasks.tasksForList('list').single.id, 'task');
      expect(tasks.tasksForList(copiedList.id).single.id, isNot('task'));
      expect(tasks.tasksForList(copiedList.id).single.title, 'Local task');
      expect((result.added, result.replaced, result.skipped), (1, 0, 1));
      expectNoDanglingEntries();
    });

    test('copied list clones a keepLocal task', () async {
      final result = await importPlanning(
        incomingTask: importedTask(),
        incomingList: importedList(),
        taskAction: ImportConflictAction.keepLocal,
        listAction: ImportConflictAction.keepBoth,
      );

      final copiedList = tasks.lists.singleWhere((list) => list.id != 'list');
      expect(tasks.tasksForList('list').single.id, 'task');
      expect(tasks.tasksForList(copiedList.id).single.title, 'Local task');
      expect((result.added, result.replaced, result.skipped), (1, 0, 1));
      expectNoDanglingEntries();
    });

    test(
      'copied task can join a local list without moving the local task',
      () async {
        final result = await importPlanning(
          incomingTask: importedTask(),
          incomingList: localList,
          taskAction: ImportConflictAction.keepBoth,
          listAction: ImportConflictAction.keepLocal,
        );

        expect(tasks.tasksForList('list').map((task) => task.title).toSet(), {
          'Local task',
          'Imported task',
        });
        expect((result.added, result.replaced, result.skipped), (1, 0, 1));
        expectNoDanglingEntries();
      },
    );

    test('copied task and copied list preserve both topologies', () async {
      final result = await importPlanning(
        incomingTask: importedTask(),
        incomingList: importedList(),
        taskAction: ImportConflictAction.keepBoth,
        listAction: ImportConflictAction.keepBoth,
      );

      final copiedList = tasks.lists.singleWhere((list) => list.id != 'list');
      expect(tasks.tasksForList('list').single.title, 'Local task');
      expect(tasks.tasksForList(copiedList.id).single.title, 'Imported task');
      expect((result.added, result.replaced, result.skipped), (2, 0, 0));
      expectNoDanglingEntries();
    });

    test(
      'addOnly ignores unresolved entries without leaving dangling topology',
      () async {
        final result = await service.importArchive(
          BackupArchiveData(
            manifest: const {},
            data: BackupData(
              taskEntries: [
                TaskListEntry(
                  taskListId: 'missing-list',
                  taskId: 'missing-task',
                  position: 0,
                  updatedAt: now,
                ),
              ],
            ),
          ),
          const ImportPlan(
            selection: BackupSelection(
              {BackupSection.tasks},
              taskIds: {'missing-task'},
              taskListIds: {'missing-list'},
            ),
            mode: ImportMode.addOnly,
          ),
        );

        expect(tasks.entries.single.taskId, 'task');
        expect((result.added, result.replaced, result.skipped), (0, 0, 0));
        expectNoDanglingEntries();
      },
    );
  });
}

Future<StorageV2Service> _readyStorage(Directory root) async {
  final storage = StorageV2Service(rootDirectory: root);
  await StorageV2UpgradeService(storageV2: storage).ensureReady();
  return storage;
}

BackupService _service(
  TaskProvider tasks,
  CalendarProvider calendar,
  StorageV2Service? storage,
) => BackupService(
  settingsProvider: SettingsProvider(storageV2: storage),
  modelConfigProvider: ModelConfigProvider(storageV2: storage),
  conversationProvider: ConversationProvider(storageV2: storage),
  featureProvider: FeatureProvider(storageV2: storage),
  roleplayProvider: RoleplayProvider(storageV2: storage),
  taskProvider: tasks,
  calendarProvider: calendar,
  storageV2: storage,
  appVersionLoader: () async => 'test',
);
