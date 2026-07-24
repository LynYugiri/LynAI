import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/anniversary.dart';
import 'package:lynai/models/calendar_event.dart';
import 'package:lynai/models/item_reminder.dart';
import 'package:lynai/models/local_date.dart';
import 'package:lynai/models/recycle_bin_item.dart';
import 'package:lynai/models/task.dart';
import 'package:lynai/models/task_list.dart';
import 'package:lynai/providers/calendar_provider.dart';
import 'package:lynai/providers/task_provider.dart';
import 'package:lynai/repositories/calendar_repository.dart';
import 'package:lynai/repositories/recycle_bin_repository.dart';
import 'package:lynai/repositories/task_repository.dart';
import 'package:lynai/services/lynai_function_service.dart';

void main() {
  late _MemoryTaskRepository taskRepository;
  late _MemoryCalendarRepository calendarRepository;
  late TaskProvider tasks;
  late CalendarProvider calendar;
  late LynAIFunctionService service;
  late LynAIFunctionContext context;

  setUp(() {
    taskRepository = _MemoryTaskRepository();
    calendarRepository = _MemoryCalendarRepository();
    tasks = TaskProvider(
      repository: taskRepository,
      recycleBinRepository: _MemoryRecycleBinRepository(),
    );
    calendar = CalendarProvider(
      repository: calendarRepository,
      recycleBinRepository: _MemoryRecycleBinRepository(),
    );
    service = LynAIFunctionService();
    context = LynAIFunctionContext(tasks: tasks, calendar: calendar);
  });

  test(
    'canonical reminders generate ids and support preserve replace clear',
    () async {
      final created = await service.execute(
        const LynAIFunctionCall(
          name: 'tasks.create',
          arguments: {
            'title': 'Submit report',
            'dueDate': '2026-07-23',
            'dueTime': '12:00',
            'reminders': [
              {'anchor': 'taskDue', 'offsetMinutes': -30},
            ],
          },
        ),
        context,
      );
      final task = created['task'] as Map;
      final id = task['id'] as String;
      final reminder = (task['reminders'] as List).single as Map;
      expect(reminder['id'], isNotEmpty);
      expect(reminder['anchor'], 'taskDue');
      expect(reminder['offsetMinutes'], -30);

      final listed = service.executeSync(
        const LynAIFunctionCall(name: 'tasks.list', arguments: {}),
        context,
      );
      expect(
        (((listed['tasks'] as List).single as Map)['reminders'] as List).single,
        reminder,
      );

      await service.execute(
        LynAIFunctionCall(
          name: 'tasks.update',
          arguments: {'id': id, 'title': 'Submit final report'},
        ),
        context,
      );
      expect(tasks.taskById(id)!.reminders.single.id, reminder['id']);

      await service.execute(
        LynAIFunctionCall(
          name: 'tasks.update',
          arguments: {
            'id': id,
            'reminders': [
              {'id': 'replacement', 'anchor': 'taskDue', 'offsetMinutes': -60},
            ],
          },
        ),
        context,
      );
      expect(tasks.taskById(id)!.reminders.single.id, 'replacement');

      await service.execute(
        LynAIFunctionCall(
          name: 'tasks.update',
          arguments: {'id': id, 'reminders': const []},
        ),
        context,
      );
      expect(tasks.taskById(id)!.reminders, isEmpty);
    },
  );

  test(
    'canonical reminder anchors and date-only times are validated',
    () async {
      final invalidAnchor = await service.execute(
        const LynAIFunctionCall(
          name: 'calendar.create',
          arguments: {
            'title': 'Meeting',
            'start': '2026-07-23T10:00:00',
            'end': '2026-07-23T11:00:00',
            'reminders': [
              {'anchor': 'taskDue', 'offsetMinutes': -10},
            ],
          },
        ),
        context,
      );
      expect(invalidAnchor['ok'], isFalse);
      expect(invalidAnchor['error'], contains('锚点'));

      final anniversary = await service.execute(
        const LynAIFunctionCall(
          name: 'anniversaries.create',
          arguments: {
            'title': 'Launch day',
            'type': 'yearly',
            'month': 7,
            'day': 23,
            'reminders': [
              {
                'anchor': 'anniversaryDate',
                'offsetMinutes': 0,
                'dateOnlyTime': '09:15',
              },
            ],
          },
        ),
        context,
      );
      final reminder =
          ((anniversary['anniversary'] as Map)['reminders'] as List).single
              as Map;
      expect(reminder['dateOnlyTime'], '09:15');

      final event = await service.execute(
        const LynAIFunctionCall(
          name: 'calendar.create',
          arguments: {
            'title': 'Holiday',
            'allDay': true,
            'startDate': '2026-07-24',
            'reminders': [
              {
                'anchor': 'eventStart',
                'offsetMinutes': 0,
                'dateOnlyTime': '08:30',
              },
            ],
          },
        ),
        context,
      );
      expect(event['ok'], isTrue);

      final listedEvents = service.executeSync(
        const LynAIFunctionCall(name: 'calendar.list', arguments: {}),
        context,
      );
      final listedAnniversaries = service.executeSync(
        const LynAIFunctionCall(name: 'anniversaries.list', arguments: {}),
        context,
      );
      expect(
        ((((listedEvents['events'] as List).single as Map)['reminders'] as List)
                .single
            as Map)['dateOnlyTime'],
        '08:30',
      );
      expect(
        (((listedAnniversaries['anniversaries'] as List).single
                    as Map)['reminders']
                as List)
            .single,
        reminder,
      );
    },
  );

  test('legacy schedule task projections use half-open from and to', () async {
    for (final day in [22, 23, 24]) {
      await tasks.addTask(
        title: 'Task $day',
        plannedDate: LocalDate(2026, 7, day),
      );
    }

    final result = service.executeSync(
      const LynAIFunctionCall(
        name: 'schedules.list',
        arguments: {'from': '2026-07-23T00:00:00', 'to': '2026-07-24T00:00:00'},
      ),
      context,
    );

    expect((result['schedules'] as List).map((item) => item['title']), [
      'Task 23',
    ]);
  });

  test(
    'legacy update schedule converts task and event under the same id',
    () async {
      final taskId = await tasks.addTask(
        title: 'Task source',
        plannedDate: LocalDate(2026, 7, 23),
        reminders: const [
          ItemReminder(
            id: 'task-reminder',
            anchor: ItemReminderAnchor.taskPlanned,
            offsetMinutes: -15,
          ),
        ],
      );
      final toEvent = await service.execute(
        LynAIFunctionCall(
          name: 'schedules.update',
          arguments: {
            'id': taskId,
            'kind': 'schedule',
            'start': '2026-07-23T09:00:00',
            'end': '2026-07-23T10:00:00',
          },
        ),
        context,
      );
      expect(toEvent['ok'], isTrue);
      expect(tasks.taskById(taskId), isNull);
      expect(calendar.getEvent(taskId)?.id, taskId);
      expect(
        calendar.getEvent(taskId)?.reminders.single.anchor,
        ItemReminderAnchor.eventStart,
      );

      final toTask = await service.execute(
        LynAIFunctionCall(
          name: 'schedules.update',
          arguments: {'id': taskId, 'kind': 'task'},
        ),
        context,
      );
      expect(toTask['ok'], isTrue);
      expect(calendar.getEvent(taskId), isNull);
      expect(tasks.taskById(taskId)?.id, taskId);
      expect(
        tasks.taskById(taskId)?.reminders.single.anchor,
        ItemReminderAnchor.taskPlanned,
      );
    },
  );

  test('task to event retains source when target save fails', () async {
    final taskId = await tasks.addTask(
      title: 'Retained task',
      plannedDate: LocalDate(2026, 7, 23),
    );
    calendarRepository.failNextSave = true;

    final result = await _convertTaskToEvent(service, context, taskId);

    expect(result['ok'], isFalse);
    expect(result['error'], contains('目标分区保存失败'));
    expect(tasks.taskById(taskId), isNotNull);
    expect(calendar.getEvent(taskId), isNull);
    await _expectPersistedState(
      taskRepository,
      calendarRepository,
      taskId: taskId,
      hasTask: true,
      hasEvent: false,
    );
  });

  test('event to task retains source when target save fails', () async {
    final eventId = await _addEvent(calendar);
    taskRepository.failNextSave = true;

    final result = await _convertEventToTask(service, context, eventId);

    expect(result['ok'], isFalse);
    expect(result['error'], contains('目标分区保存失败'));
    expect(tasks.taskById(eventId), isNull);
    expect(calendar.getEvent(eventId), isNotNull);
    await _expectPersistedState(
      taskRepository,
      calendarRepository,
      taskId: eventId,
      hasTask: false,
      hasEvent: true,
    );
  });

  test('task to event rolls back target when source removal fails', () async {
    final taskId = await tasks.addTask(
      title: 'Retained task',
      plannedDate: LocalDate(2026, 7, 23),
    );
    taskRepository.failNextSave = true;

    final result = await _convertTaskToEvent(service, context, taskId);

    expect(result['ok'], isFalse);
    expect(result['error'], contains('源分区移除保存失败'));
    expect(tasks.taskById(taskId), isNotNull);
    expect(calendar.getEvent(taskId), isNull);
    await _expectPersistedState(
      taskRepository,
      calendarRepository,
      taskId: taskId,
      hasTask: true,
      hasEvent: false,
    );
  });

  test('event to task rolls back target when source removal fails', () async {
    final eventId = await _addEvent(calendar);
    calendarRepository.failNextSave = true;

    final result = await _convertEventToTask(service, context, eventId);

    expect(result['ok'], isFalse);
    expect(result['error'], contains('源分区移除保存失败'));
    expect(tasks.taskById(eventId), isNull);
    expect(calendar.getEvent(eventId), isNotNull);
    await _expectPersistedState(
      taskRepository,
      calendarRepository,
      taskId: eventId,
      hasTask: false,
      hasEvent: true,
    );
  });
}

Future<Map<String, dynamic>> _convertTaskToEvent(
  LynAIFunctionService service,
  LynAIFunctionContext context,
  String id,
) {
  return service.execute(
    LynAIFunctionCall(
      name: 'schedules.update',
      arguments: {
        'id': id,
        'kind': 'schedule',
        'start': '2026-07-23T09:00:00',
        'end': '2026-07-23T10:00:00',
      },
    ),
    context,
  );
}

Future<Map<String, dynamic>> _convertEventToTask(
  LynAIFunctionService service,
  LynAIFunctionContext context,
  String id,
) {
  return service.execute(
    LynAIFunctionCall(
      name: 'schedules.update',
      arguments: {'id': id, 'kind': 'task'},
    ),
    context,
  );
}

Future<String> _addEvent(CalendarProvider calendar) {
  return calendar.addEvent(
    title: 'Retained event',
    spec: TimedCalendarEventSpec(
      start: DateTime(2026, 7, 23, 9),
      end: DateTime(2026, 7, 23, 10),
    ),
  );
}

Future<void> _expectPersistedState(
  _MemoryTaskRepository taskRepository,
  _MemoryCalendarRepository calendarRepository, {
  required String taskId,
  required bool hasTask,
  required bool hasEvent,
}) async {
  final reloadedTasks = TaskProvider(
    repository: taskRepository,
    recycleBinRepository: _MemoryRecycleBinRepository(),
  );
  final reloadedCalendar = CalendarProvider(
    repository: calendarRepository,
    recycleBinRepository: _MemoryRecycleBinRepository(),
  );
  await Future.wait([reloadedTasks.load(), reloadedCalendar.load()]);
  expect(reloadedTasks.taskById(taskId) != null, hasTask);
  expect(reloadedCalendar.getEvent(taskId) != null, hasEvent);
}

final class _MemoryTaskRepository implements TaskRepository {
  List<Task> savedTasks = const [];
  List<TaskList> savedLists = const [];
  List<TaskListEntry> savedEntries = const [];
  bool failNextSave = false;

  @override
  Future<TaskLoadResult> load() async {
    return TaskLoadResult(
      tasks: List.of(savedTasks),
      lists: List.of(savedLists),
      entries: List.of(savedEntries),
    );
  }

  @override
  Future<void> replace({
    required List<Task> tasks,
    required List<TaskList> lists,
    required List<TaskListEntry> entries,
  }) async {
    if (failNextSave) {
      failNextSave = false;
      throw Exception('task save failed');
    }
    savedTasks = List.of(tasks);
    savedLists = List.of(lists);
    savedEntries = List.of(entries);
  }

  @override
  Future<void> saveChanges({
    Iterable<Task> upsertTasks = const [],
    Iterable<String> deleteTaskIds = const [],
    Iterable<TaskList> upsertLists = const [],
    Iterable<String> deleteListIds = const [],
    Iterable<TaskListEntry> upsertEntries = const [],
    Iterable<String> deleteEntryTaskIds = const [],
  }) async {
    if (failNextSave) {
      failNextSave = false;
      throw Exception('task save failed');
    }
    final tasks = {for (final task in savedTasks) task.id: task};
    final lists = {for (final list in savedLists) list.id: list};
    final entries = {for (final entry in savedEntries) entry.taskId: entry};
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
    savedTasks = tasks.values.toList();
    savedLists = lists.values.toList();
    savedEntries = entries.values.toList();
  }
}

final class _MemoryCalendarRepository extends CalendarRepository {
  List<CalendarEvent> savedEvents = const [];
  List<Anniversary> savedAnniversaries = const [];
  bool failNextSave = false;

  @override
  Future<CalendarLoadResult> load() async {
    return CalendarLoadResult(
      events: List.of(savedEvents),
      anniversaries: List.of(savedAnniversaries),
    );
  }

  @override
  Future<void> replace({
    required List<CalendarEvent> events,
    required List<Anniversary> anniversaries,
  }) async {
    if (failNextSave) {
      failNextSave = false;
      throw Exception('target save failed');
    }
    savedEvents = List.of(events);
    savedAnniversaries = List.of(anniversaries);
  }

  @override
  Future<void> saveChanges({
    Iterable<CalendarEvent> upsertEvents = const [],
    Iterable<String> deleteEventIds = const [],
    Iterable<Anniversary> upsertAnniversaries = const [],
    Iterable<String> deleteAnniversaryIds = const [],
  }) async {
    if (failNextSave) {
      failNextSave = false;
      throw Exception('target save failed');
    }
    final events = {for (final event in savedEvents) event.id: event};
    final anniversaries = {
      for (final anniversary in savedAnniversaries) anniversary.id: anniversary,
    };
    for (final id in deleteEventIds) {
      events.remove(id);
    }
    for (final id in deleteAnniversaryIds) {
      anniversaries.remove(id);
    }
    for (final event in upsertEvents) {
      events[event.id] = event;
    }
    for (final anniversary in upsertAnniversaries) {
      anniversaries[anniversary.id] = anniversary;
    }
    savedEvents = events.values.toList();
    savedAnniversaries = anniversaries.values.toList();
  }
}

final class _MemoryRecycleBinRepository implements RecycleBinRepository {
  @override
  Future<void> add(RecycleBinItem item) async {}

  @override
  Future<List<RecycleBinItem>> load() async => const [];

  @override
  Future<void> remove(String id) async {}

  @override
  Future<void> save(List<RecycleBinItem> items) async {}
}
