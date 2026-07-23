import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/anniversary.dart';
import 'package:lynai/models/calendar_event.dart';
import 'package:lynai/models/calendar_occurrence.dart';
import 'package:lynai/models/item_reminder.dart';
import 'package:lynai/models/local_date.dart';
import 'package:lynai/models/local_time.dart';
import 'package:lynai/models/task.dart';
import 'package:lynai/models/task_list.dart';

void main() {
  final createdAt = DateTime(2026, 1, 1, 9);
  final updatedAt = DateTime(2026, 1, 2, 10);

  group('Local values', () {
    test(
      'LocalDate parses, serializes, copies, and rejects invalid values',
      () {
        final date = LocalDate.parse('2024-02-29');

        expect(date.toJson(), '2024-02-29');
        expect(LocalDate.fromJson(date.toJson()), date);
        expect(date.copyWith(day: 28), LocalDate(2024, 2, 28));
        expect(LocalDate.tryParse('2023-02-29'), isNull);
        expect(LocalDate.tryParse('2024-2-09'), isNull);
        expect(LocalDate(2024, 2, 28).addDays(1), date);
      },
    );

    test(
      'LocalTime parses, serializes, copies, and rejects invalid values',
      () {
        final time = LocalTime.parse('09:05');

        expect(time.toJson(), '09:05');
        expect(LocalTime.fromJson(time.toJson()), time);
        expect(time.copyWith(minute: 30), LocalTime(9, 30));
        expect(LocalTime.tryParse('9:05'), isNull);
        expect(LocalTime.tryParse('24:00'), isNull);
      },
    );
  });

  test('ItemReminder has stable identity and nullable time persistence', () {
    final reminder = ItemReminder(
      id: 'reminder',
      anchor: ItemReminderAnchor.taskDue,
      offsetMinutes: -15,
      dateOnlyTime: LocalTime(9, 0),
    );

    expect(ItemReminder.fromJson(reminder.toJson()), reminder);
    expect(reminder.copyWith(dateOnlyTime: null).dateOnlyTime, isNull);
    expect(reminder.copyWith().id, 'reminder');
  });

  group('Task', () {
    test('round-trips and copyWith clears nullable fields', () {
      final task = Task(
        id: 'task',
        title: 'Task',
        note: 'Note',
        plannedDate: LocalDate(2026, 1, 5),
        dueDate: LocalDate(2026, 1, 10),
        dueTime: LocalTime(12, 30),
        completedAt: updatedAt,
        createdAt: createdAt,
        updatedAt: updatedAt,
        reminders: const [
          ItemReminder(
            id: 'due',
            anchor: ItemReminderAnchor.taskDue,
            offsetMinutes: -30,
          ),
        ],
      );

      final decoded = Task.fromJson(task.toJson());
      expect(decoded.toJson(), task.toJson());
      final cleared = task.copyWith(
        note: null,
        plannedDate: null,
        dueTime: null,
        completedAt: null,
      );
      expect(cleared.note, isNull);
      expect(cleared.plannedDate, isNull);
      expect(cleared.dueTime, isNull);
      expect(cleared.completedAt, isNull);
    });

    test('validates reminder anchors and exact duplicates', () {
      const reminder = ItemReminder(
        id: 'planned',
        anchor: ItemReminderAnchor.taskPlanned,
        offsetMinutes: 0,
      );

      expect(
        () => Task(
          id: 'task',
          title: 'Task',
          createdAt: createdAt,
          updatedAt: updatedAt,
          reminders: const [reminder],
        ),
        throwsArgumentError,
      );
      expect(
        () => Task(
          id: 'task',
          title: 'Task',
          plannedDate: LocalDate(2026, 1, 1),
          createdAt: createdAt,
          updatedAt: updatedAt,
          reminders: const [reminder, reminder],
        ),
        throwsArgumentError,
      );
    });

    test('date-only and timed due state is computed correctly', () {
      final dateOnly = Task(
        id: 'date-only',
        title: 'Task',
        dueDate: LocalDate(2026, 1, 10),
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
      final timed = dateOnly.copyWith(id: 'timed', dueTime: LocalTime(12, 30));
      final completed = dateOnly.copyWith(completedAt: updatedAt);

      expect(dateOnly.isOverdueAt(DateTime(2026, 1, 10, 23, 59)), isFalse);
      expect(dateOnly.isOverdueAt(DateTime(2026, 1, 11)), isTrue);
      expect(timed.isOverdueAt(DateTime(2026, 1, 10, 12, 31)), isTrue);
      expect(completed.isOverdueAt(DateTime(2026, 1, 11)), isFalse);
    });
  });

  test('TaskList and TaskListEntry persist ordering metadata', () {
    final list = TaskList(
      id: 'list',
      title: 'List',
      sortOrder: 7,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
    final entry = TaskListEntry(
      taskListId: 'list',
      taskId: 'task',
      position: 2,
      updatedAt: updatedAt,
    );

    expect(TaskList.fromJson(list.toJson()).toJson(), list.toJson());
    expect(TaskListEntry.fromJson(entry.toJson()).toJson(), entry.toJson());
    expect(list.copyWith(sortOrder: 8).sortOrder, 8);
    expect(entry.copyWith(position: 3).position, 3);
  });

  test('CalendarEvent specs and nullable note round-trip', () {
    final event = CalendarEvent(
      id: 'event',
      title: 'Event',
      note: 'Note',
      spec: TimedCalendarEventSpec(
        start: DateTime(2026, 1, 1, 10),
        end: DateTime(2026, 1, 2, 11),
      ),
      reminders: const [
        ItemReminder(
          id: 'start',
          anchor: ItemReminderAnchor.eventStart,
          offsetMinutes: -10,
        ),
      ],
      createdAt: createdAt,
      updatedAt: updatedAt,
    );

    expect(CalendarEvent.fromJson(event.toJson()).toJson(), event.toJson());
    expect(event.copyWith(note: null).note, isNull);
    final allDay = AllDayCalendarEventSpec(
      startDate: LocalDate(2026, 2, 1),
      endDateExclusive: LocalDate(2026, 2, 3),
    );
    expect(
      CalendarEventSpec.fromJson(allDay.toJson()).toJson(),
      allDay.toJson(),
    );
  });

  group('Anniversary', () {
    test('yearly dates allow no source year and leap-day fallback', () {
      final anniversary = Anniversary(
        id: 'leap',
        title: 'Leap day',
        spec: YearlyAnniversarySpec(month: 2, day: 29),
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

      expect(anniversary.occurrenceInYear(2025), LocalDate(2025, 2, 28));
      expect(anniversary.occurrenceInYear(2028), LocalDate(2028, 2, 29));
      expect(
        Anniversary.fromJson(anniversary.toJson()).toJson(),
        anniversary.toJson(),
      );
    });

    test('once requires a full date and year counts require a source year', () {
      final once = Anniversary(
        id: 'once',
        title: 'Once',
        spec: OnceAnniversarySpec(date: LocalDate(2026, 3, 4)),
        showYearCount: true,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

      expect(once.occurrenceInYear(2025), isNull);
      expect(once.occurrenceInYear(2026), LocalDate(2026, 3, 4));
      expect(once.yearCountIn(2026), 0);
      expect(
        () => Anniversary(
          id: 'yearly',
          title: 'Yearly',
          spec: YearlyAnniversarySpec(month: 3, day: 4),
          showYearCount: true,
          createdAt: createdAt,
          updatedAt: updatedAt,
        ),
        throwsArgumentError,
      );
    });
  });

  test('CalendarOccurrence preserves status and multi-day values', () {
    final occurrence = CalendarOccurrence(
      occurrenceId: 'event:event:2026-01-01',
      sourceId: 'event',
      kind: CalendarOccurrenceKind.event,
      date: LocalDate(2026, 1, 1),
      title: 'Event',
      note: 'Note',
      startTime: LocalTime(23, 0),
      endTime: LocalTime(1, 0),
      endDateExclusive: LocalDate(2026, 1, 3),
      isCompleted: true,
      isOverdue: true,
    );

    expect(
      CalendarOccurrence.fromJson(occurrence.toJson()).toJson(),
      occurrence.toJson(),
    );
    expect(occurrence.copyWith(note: null, endTime: null).note, isNull);
    expect(occurrence.copyWith(endTime: null).endTime, isNull);
  });
}
