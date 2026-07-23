import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/calendar_event.dart';
import 'package:lynai/models/local_date.dart';
import 'package:lynai/models/local_time.dart';
import 'package:lynai/models/schedule_item.dart';
import 'package:lynai/models/todo_list.dart';
import 'package:lynai/services/legacy_calendar_conversion_service.dart';

void main() {
  const service = LegacyCalendarConversionService();

  test('converts a schedule event to a timed event', () {
    final start = DateTime(2026, 7, 1, 10);
    final end = DateTime(2026, 7, 1, 11);
    final converted = service.calendarEventFromSchedule(
      ScheduleItem(id: 'event', title: 'Meeting', start: start, end: end),
    );

    final spec = converted.spec as TimedCalendarEventSpec;
    expect(spec.start, start);
    expect(spec.end, end);
  });

  test('preserves schedule task note and discards synthetic end', () {
    final start = DateTime(2026, 7, 1, 10, 15);
    final converted = service.taskFromSchedule(
      ScheduleItem(
        id: 'task',
        title: 'Call',
        note: 'Bring context',
        start: start,
        end: start.add(const Duration(minutes: 1)),
        kind: ScheduleItem.kindTask,
      ),
    );

    expect(converted.note, 'Bring context');
    expect(converted.plannedDate, LocalDate(2026, 7, 1));
    expect(converted.plannedTime, LocalTime(10, 15));
    expect(converted.dueDate, isNull);
    expect(converted.dueTime, isNull);
  });

  test(
    'splits an embedded todo list while preserving order and completion',
    () {
      final createdAt = DateTime(2026, 1, 1);
      final updatedAt = DateTime(2026, 1, 2);
      final converted = service.todoList(
        TodoList(
          id: 'list',
          title: 'List',
          items: const [
            TodoItem(id: 'first', text: 'First'),
            TodoItem(id: 'second', text: 'Second', done: true),
          ],
          createdAt: createdAt,
          updatedAt: updatedAt,
        ),
      );

      expect(converted.taskList.id, 'list');
      expect(converted.taskList.sortOrder, 0);
      expect(converted.tasks.map((task) => task.id), ['first', 'second']);
      expect(converted.tasks[1].completedAt, updatedAt);
      expect(converted.entries.map((entry) => entry.position), [0, 1]);
      expect(converted.entries[1].taskListId, 'list');
      expect(converted.entries[1].taskId, 'second');
      expect(converted.entries[1].updatedAt, updatedAt);
    },
  );
}
