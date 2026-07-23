import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/anniversary.dart';
import 'package:lynai/models/calendar_event.dart';
import 'package:lynai/models/recycle_bin_item.dart';
import 'package:lynai/models/schedule_item.dart';
import 'package:lynai/models/task.dart';
import 'package:lynai/models/task_list.dart';
import 'package:lynai/models/todo_list.dart' as legacy;
import 'package:lynai/pages/recycle_bin_page.dart';
import 'package:lynai/providers/calendar_provider.dart';
import 'package:lynai/providers/task_provider.dart';
import 'package:lynai/repositories/calendar_repository.dart';
import 'package:lynai/repositories/recycle_bin_repository.dart';
import 'package:lynai/repositories/task_repository.dart';

void main() {
  test('restores canonical task topology and calendar payloads', () async {
    final tasks = TaskProvider(
      repository: _TaskRepository(),
      recycleBinRepository: _RecycleBinRepository(),
    );
    final calendar = CalendarProvider(
      repository: _CalendarRepository(),
      recycleBinRepository: _RecycleBinRepository(),
    );
    final now = DateTime(2026, 7, 22);
    final list = TaskList(
      id: 'list',
      title: 'List',
      sortOrder: 0,
      createdAt: now,
      updatedAt: now,
    );
    await restorePlanningRecycleBinItem(
      RecycleBinItem(
        owner: RecycleBinOwners.core,
        category: RecycleBinCategories.todos,
        type: RecycleBinItemTypes.taskList,
        title: 'List',
        payload: {'list': list.toJson(), 'entries': const []},
      ),
      tasks: tasks,
      calendar: calendar,
    );
    final task = Task(
      id: 'task',
      title: 'Task',
      createdAt: now,
      updatedAt: now,
    );
    final entry = TaskListEntry(
      taskListId: 'list',
      taskId: 'task',
      position: 0,
      updatedAt: now,
    );
    await restorePlanningRecycleBinItem(
      RecycleBinItem(
        owner: RecycleBinOwners.core,
        category: RecycleBinCategories.todos,
        type: RecycleBinItemTypes.task,
        title: 'Task',
        payload: {'task': task.toJson(), 'entry': entry.toJson()},
      ),
      tasks: tasks,
      calendar: calendar,
    );
    final event = CalendarEvent(
      id: 'event',
      title: 'Event',
      spec: TimedCalendarEventSpec(
        start: now,
        end: now.add(const Duration(hours: 1)),
      ),
      createdAt: now,
      updatedAt: now,
    );
    final anniversary = Anniversary(
      id: 'anniversary',
      title: 'Anniversary',
      spec: YearlyAnniversarySpec(month: 7, day: 22),
      createdAt: now,
      updatedAt: now,
    );
    for (final item in [
      RecycleBinItem(
        owner: RecycleBinOwners.core,
        category: RecycleBinCategories.calendar,
        type: RecycleBinItemTypes.calendarEvent,
        title: 'Event',
        payload: {'event': event.toJson()},
      ),
      RecycleBinItem(
        owner: RecycleBinOwners.core,
        category: RecycleBinCategories.calendar,
        type: RecycleBinItemTypes.anniversary,
        title: 'Anniversary',
        payload: {'anniversary': anniversary.toJson()},
      ),
    ]) {
      await restorePlanningRecycleBinItem(
        item,
        tasks: tasks,
        calendar: calendar,
      );
    }
    expect(tasks.tasksForList('list').single.id, 'task');
    expect(calendar.events.single.id, 'event');
    expect(calendar.anniversaries.single.id, 'anniversary');
  });

  test(
    'restores legacy schedule and todo list through conversion service',
    () async {
      final tasks = TaskProvider(
        repository: _TaskRepository(),
        recycleBinRepository: _RecycleBinRepository(),
      );
      final calendar = CalendarProvider(
        repository: _CalendarRepository(),
        recycleBinRepository: _RecycleBinRepository(),
      );
      final now = DateTime(2026, 7, 22, 10);
      await restorePlanningRecycleBinItem(
        RecycleBinItem(
          owner: RecycleBinOwners.core,
          category: RecycleBinCategories.schedules,
          type: RecycleBinItemTypes.schedule,
          title: 'Event',
          payload: {
            'schedule': ScheduleItem(
              id: 'event',
              title: 'Event',
              start: now,
              end: now.add(const Duration(hours: 1)),
            ).toJson(),
          },
        ),
        tasks: tasks,
        calendar: calendar,
      );
      await restorePlanningRecycleBinItem(
        RecycleBinItem(
          owner: RecycleBinOwners.core,
          category: RecycleBinCategories.todos,
          type: RecycleBinItemTypes.todoList,
          title: 'Legacy',
          payload: {
            'todoList': legacy.TodoList(
              id: 'list',
              title: 'Legacy',
              items: const [legacy.TodoItem(id: 'task', text: 'Task')],
              createdAt: now,
              updatedAt: now,
            ).toJson(),
          },
        ),
        tasks: tasks,
        calendar: calendar,
      );
      expect(calendar.events.single.id, 'event');
      expect(tasks.tasksForList('list').single.id, 'task');
    },
  );
}

class _TaskRepository implements TaskRepository {
  @override
  Future<TaskLoadResult> load() async =>
      const TaskLoadResult(tasks: [], lists: [], entries: []);

  @override
  Future<void> save({
    required List<Task> tasks,
    required List<TaskList> lists,
    required List<TaskListEntry> entries,
  }) async {}
}

class _CalendarRepository implements CalendarRepository {
  @override
  Future<CalendarLoadResult> load() async =>
      const CalendarLoadResult(events: [], anniversaries: []);

  @override
  Future<void> save({
    required List<CalendarEvent> events,
    required List<Anniversary> anniversaries,
  }) async {}
}

class _RecycleBinRepository implements RecycleBinRepository {
  @override
  Future<void> add(RecycleBinItem item) async {}

  @override
  Future<List<RecycleBinItem>> load() async => const [];

  @override
  Future<void> remove(String id) async {}

  @override
  Future<void> save(List<RecycleBinItem> items) async {}
}
