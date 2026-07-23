import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/anniversary.dart';
import 'package:lynai/models/calendar_event.dart';
import 'package:lynai/models/calendar_occurrence.dart';
import 'package:lynai/models/local_date.dart';
import 'package:lynai/models/local_time.dart';
import 'package:lynai/models/task.dart';
import 'package:lynai/services/calendar_occurrence_service.dart';

void main() {
  final timestamp = DateTime(2026, 1, 1);
  const service = CalendarOccurrenceService();

  test('projects sources and merges same-day task plan and due', () {
    final occurrences = service.project(
      startDate: LocalDate(2025, 2, 28),
      endDateExclusive: LocalDate(2025, 3, 2),
      events: [
        CalendarEvent(
          id: 'event',
          title: 'Event',
          spec: AllDayCalendarEventSpec(
            startDate: LocalDate(2025, 2, 28),
            endDateExclusive: LocalDate(2025, 3, 1),
          ),
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
      ],
      tasks: [
        Task(
          id: 'task',
          title: 'Task',
          plannedDate: LocalDate(2025, 3, 1),
          plannedTime: LocalTime(9, 0),
          dueDate: LocalDate(2025, 3, 1),
          dueTime: LocalTime(18, 0),
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
      ],
      anniversaries: [
        Anniversary(
          id: 'anniversary',
          title: 'Anniversary',
          spec: YearlyAnniversarySpec(month: 2, day: 29, sourceYear: 2024),
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
      ],
    );

    expect(occurrences, hasLength(3));
    expect(
      occurrences.map((value) => value.kind),
      containsAll([
        CalendarOccurrenceKind.event,
        CalendarOccurrenceKind.anniversary,
        CalendarOccurrenceKind.taskPlannedAndDue,
      ]),
    );
    final taskOccurrence = occurrences.singleWhere(
      (value) => value.sourceId == 'task',
    );
    expect(taskOccurrence.date, LocalDate(2025, 3, 1));
    expect(taskOccurrence.startTime, LocalTime(9, 0));
    expect(taskOccurrence.endTime, LocalTime(18, 0));
    expect(taskOccurrence.occurrenceId, 'taskPlannedAndDue:task:2025-03-01');
  });

  test('uses half-open ranges for all-day events', () {
    final event = CalendarEvent(
      id: 'event',
      title: 'Event',
      spec: AllDayCalendarEventSpec(
        startDate: LocalDate(2026, 4, 10),
        endDateExclusive: LocalDate(2026, 4, 12),
      ),
      createdAt: timestamp,
      updatedAt: timestamp,
    );

    expect(
      service.project(
        startDate: LocalDate(2026, 4, 12),
        endDateExclusive: LocalDate(2026, 4, 13),
        events: [event],
      ),
      isEmpty,
    );
    expect(
      service.project(
        startDate: LocalDate(2026, 4, 11),
        endDateExclusive: LocalDate(2026, 4, 12),
        events: [event],
      ),
      hasLength(1),
    );
  });

  test('keeps distinct task plan and due occurrences on different days', () {
    final task = Task(
      id: 'task',
      title: 'Task',
      plannedDate: LocalDate(2026, 5, 1),
      dueDate: LocalDate(2026, 5, 2),
      createdAt: timestamp,
      updatedAt: timestamp,
    );

    final occurrences = service.project(
      startDate: LocalDate(2026, 5, 1),
      endDateExclusive: LocalDate(2026, 5, 3),
      tasks: [task],
    );

    expect(occurrences.map((value) => value.kind), [
      CalendarOccurrenceKind.taskPlanned,
      CalendarOccurrenceKind.taskDue,
    ]);
  });

  test('keeps completed and overdue tasks and marks their state', () {
    final occurrences = service.project(
      startDate: LocalDate(2026, 5, 1),
      endDateExclusive: LocalDate(2026, 5, 3),
      now: DateTime(2026, 5, 3),
      tasks: [
        Task(
          id: 'overdue',
          title: 'Overdue',
          dueDate: LocalDate(2026, 5, 1),
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
        Task(
          id: 'completed',
          title: 'Completed',
          dueDate: LocalDate(2026, 5, 2),
          completedAt: DateTime(2026, 5, 2),
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
      ],
    );

    expect(occurrences, hasLength(2));
    expect(
      occurrences.singleWhere((value) => value.sourceId == 'overdue').isOverdue,
      isTrue,
    );
    expect(
      occurrences
          .singleWhere((value) => value.sourceId == 'completed')
          .isCompleted,
      isTrue,
    );
  });

  test('preserves multi-day timed event dates and clock values', () {
    final occurrence = service
        .project(
          startDate: LocalDate(2026, 6, 2),
          endDateExclusive: LocalDate(2026, 6, 3),
          events: [
            CalendarEvent(
              id: 'event',
              title: 'Overnight',
              spec: TimedCalendarEventSpec(
                start: DateTime(2026, 6, 1, 23),
                end: DateTime(2026, 6, 2, 1),
              ),
              createdAt: timestamp,
              updatedAt: timestamp,
            ),
          ],
        )
        .single;

    expect(occurrence.date, LocalDate(2026, 6, 1));
    expect(occurrence.startTime, LocalTime(23, 0));
    expect(occurrence.endTime, LocalTime(1, 0));
    expect(occurrence.endDateExclusive, LocalDate(2026, 6, 3));
  });

  test('converts UTC timed event boundaries before deriving local values', () {
    final localService = CalendarOccurrenceService(
      toLocal: (value) => value.toUtc().add(const Duration(hours: 8)),
    );
    final occurrence = localService
        .project(
          startDate: LocalDate(2026, 6, 2),
          endDateExclusive: LocalDate(2026, 6, 4),
          events: [
            CalendarEvent(
              id: 'utc-event',
              title: 'UTC boundary',
              spec: TimedCalendarEventSpec(
                start: DateTime.utc(2026, 6, 1, 17, 30),
                end: DateTime.utc(2026, 6, 2, 16),
              ),
              createdAt: timestamp,
              updatedAt: timestamp,
            ),
          ],
        )
        .single;

    expect(occurrence.date, LocalDate(2026, 6, 2));
    expect(occurrence.startTime, LocalTime(1, 30));
    expect(occurrence.endTime, LocalTime(0, 0));
    expect(occurrence.endDateExclusive, LocalDate(2026, 6, 3));
  });

  test('converts offset instants across the previous local date boundary', () {
    final localService = CalendarOccurrenceService(
      toLocal: (value) => value.toUtc().subtract(const Duration(hours: 7)),
    );
    final occurrence = localService
        .project(
          startDate: LocalDate(2026, 5, 31),
          endDateExclusive: LocalDate(2026, 6, 2),
          events: [
            CalendarEvent(
              id: 'offset-event',
              title: 'Offset boundary',
              spec: TimedCalendarEventSpec(
                start: DateTime.parse('2026-06-01T01:00:00+02:00'),
                end: DateTime.parse('2026-06-01T03:00:00+02:00'),
              ),
              createdAt: timestamp,
              updatedAt: timestamp,
            ),
          ],
        )
        .single;

    expect(occurrence.date, LocalDate(2026, 5, 31));
    expect(occurrence.startTime, LocalTime(16, 0));
    expect(occurrence.endTime, LocalTime(18, 0));
    expect(occurrence.endDateExclusive, LocalDate(2026, 6, 1));
  });
}
