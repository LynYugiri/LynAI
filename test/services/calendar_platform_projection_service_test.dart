import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/anniversary.dart';
import 'package:lynai/models/calendar_event.dart';
import 'package:lynai/models/item_reminder.dart';
import 'package:lynai/models/local_date.dart';
import 'package:lynai/models/local_time.dart';
import 'package:lynai/models/task.dart';
import 'package:lynai/services/calendar_platform_projection_service.dart';

void main() {
  const service = CalendarPlatformProjectionService();
  final timestamp = DateTime(2026, 1, 1);

  test('projects widgets and explicit reminder anchors with stable IDs', () {
    final projection = service.build(
      now: DateTime(2026, 7, 22, 12),
      tasks: [
        Task(
          id: 'task-1',
          title: 'Ship',
          plannedDate: LocalDate(2026, 7, 23),
          dueDate: LocalDate(2026, 7, 24),
          dueTime: LocalTime(18, 30),
          reminders: [
            ItemReminder(
              id: 'planned-reminder',
              anchor: ItemReminderAnchor.taskPlanned,
              offsetMinutes: -30,
              dateOnlyTime: LocalTime(8, 15),
            ),
            const ItemReminder(
              id: 'due-reminder',
              anchor: ItemReminderAnchor.taskDue,
              offsetMinutes: -60,
            ),
          ],
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
      ],
      events: [
        CalendarEvent(
          id: 'event-1',
          title: 'All day',
          spec: AllDayCalendarEventSpec(
            startDate: LocalDate(2026, 7, 25),
            endDateExclusive: LocalDate(2026, 7, 26),
          ),
          reminders: const [
            ItemReminder(
              id: 'event-reminder',
              anchor: ItemReminderAnchor.eventStart,
              offsetMinutes: 0,
            ),
          ],
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
      ],
      anniversaries: const [],
    );

    expect(projection.version, 2);
    expect(projection.rangeStart, '2026-07-01');
    expect(projection.rangeEndExclusive, '2028-01-01');
    expect(projection.widgetOccurrences, hasLength(3));
    expect(
      projection.notificationTriggers.map((value) => value.triggerId),
      containsAll([
        'taskPlanned:task-1:2026-07-23:planned-reminder',
        'taskDue:task-1:2026-07-24:due-reminder',
        'event:event-1:2026-07-25:event-reminder',
      ]),
    );
    expect(
      projection.notificationTriggers
          .singleWhere((value) => value.reminderId == 'planned-reminder')
          .triggerAtLocal,
      '2026-07-23T07:45',
    );
    expect(
      projection.notificationTriggers
          .singleWhere((value) => value.reminderId == 'event-reminder')
          .triggerAtLocal,
      '2026-07-25T09:00',
    );
  });

  test(
    'completed tasks have no triggers and yearly anniversaries span 18 months',
    () {
      final projection = service.build(
        now: DateTime(2026, 7, 22),
        tasks: [
          Task(
            id: 'done',
            title: 'Done',
            dueDate: LocalDate(2026, 7, 23),
            completedAt: DateTime(2026, 7, 20),
            reminders: const [
              ItemReminder(
                id: 'ignored',
                anchor: ItemReminderAnchor.taskDue,
                offsetMinutes: 0,
              ),
            ],
            createdAt: timestamp,
            updatedAt: timestamp,
          ),
        ],
        events: const [],
        anniversaries: [
          Anniversary(
            id: 'annual',
            title: 'Annual',
            spec: YearlyAnniversarySpec(month: 12, day: 1),
            reminders: const [
              ItemReminder(
                id: 'annual-reminder',
                anchor: ItemReminderAnchor.anniversaryDate,
                offsetMinutes: 0,
              ),
            ],
            createdAt: timestamp,
            updatedAt: timestamp,
          ),
        ],
      );

      expect(projection.notificationTriggers.map((value) => value.triggerId), [
        'anniversary:annual:2026-12-01:annual-reminder',
        'anniversary:annual:2027-12-01:annual-reminder',
      ]);
    },
  );

  test('timed widget occurrence includes its exact local end timestamp', () {
    final projection = service.build(
      now: DateTime(2026, 7, 22),
      tasks: const [],
      events: [
        CalendarEvent(
          id: 'meeting',
          title: 'Meeting',
          spec: TimedCalendarEventSpec(
            start: DateTime(2026, 7, 23, 10),
            end: DateTime(2026, 7, 23, 11),
          ),
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
      ],
      anniversaries: const [],
    );

    final occurrence = projection.widgetOccurrences.single;
    expect(occurrence.endAtLocal, '2026-07-23T11:00');
    expect(occurrence.endDateExclusive, '2026-07-24');
    expect(occurrence.toJson()['endAtLocal'], '2026-07-23T11:00');
  });

  test('timed events preserve absolute widget and reminder instants', () {
    final start = DateTime.parse('2026-07-23T10:00:00Z');
    final end = DateTime.parse('2026-07-23T11:00:00Z');
    final projection = service.build(
      now: DateTime(2026, 7, 22),
      tasks: const [],
      events: [
        CalendarEvent(
          id: 'absolute-meeting',
          title: 'Absolute meeting',
          spec: TimedCalendarEventSpec(start: start, end: end),
          reminders: const [
            ItemReminder(
              id: 'before',
              anchor: ItemReminderAnchor.eventStart,
              offsetMinutes: -30,
            ),
          ],
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
      ],
      anniversaries: const [],
    );

    final occurrence = projection.widgetOccurrences.single;
    final trigger = projection.notificationTriggers.single;
    expect(occurrence.startAtEpochMillis, start.millisecondsSinceEpoch);
    expect(occurrence.endAtEpochMillis, end.millisecondsSinceEpoch);
    expect(
      trigger.triggerAtEpochMillis,
      start.subtract(const Duration(minutes: 30)).millisecondsSinceEpoch,
    );
  });

  test('same-day task range also projects its exact end time', () {
    final projection = service.build(
      now: DateTime(2026, 7, 22),
      tasks: [
        Task(
          id: 'task-range',
          title: 'Task range',
          plannedDate: LocalDate(2026, 7, 23),
          plannedTime: LocalTime(10, 0),
          dueDate: LocalDate(2026, 7, 23),
          dueTime: LocalTime(11, 0),
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
      ],
      events: const [],
      anniversaries: const [],
    );

    final occurrence = projection.widgetOccurrences.single;
    expect(occurrence.endAtLocal, '2026-07-23T11:00');
    expect(occurrence.endDateExclusive, '2026-07-24');
  });
}
