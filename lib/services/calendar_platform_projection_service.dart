import '../models/anniversary.dart';
import '../models/calendar_event.dart';
import '../models/calendar_occurrence.dart';
import '../models/calendar_platform_projection.dart';
import '../models/item_reminder.dart';
import '../models/local_date.dart';
import '../models/local_time.dart';
import '../models/task.dart';
import 'calendar_occurrence_service.dart';

/// 从任务与日历内存权威生成 Android 唯一可消费的完整投影。
final class CalendarPlatformProjectionService {
  const CalendarPlatformProjectionService({
    this.occurrenceService = const CalendarOccurrenceService(),
  });

  final CalendarOccurrenceService occurrenceService;

  CalendarPlatformProjection build({
    required Iterable<Task> tasks,
    required Iterable<CalendarEvent> events,
    required Iterable<Anniversary> anniversaries,
    DateTime? now,
  }) {
    final effectiveNow = (now ?? DateTime.now()).toLocal();
    final rangeStart = LocalDate(effectiveNow.year, effectiveNow.month, 1);
    final rangeEnd = _addMonths(rangeStart, 18);
    final occurrences = occurrenceService.project(
      startDate: rangeStart,
      endDateExclusive: rangeEnd,
      tasks: tasks,
      events: events,
      anniversaries: anniversaries,
      now: effectiveNow,
    );
    final timedEvents = {
      for (final event in events)
        if (event.spec case final TimedCalendarEventSpec spec) event.id: spec,
    };
    final triggers =
        <CalendarNotificationTriggerProjection>[
          for (final task in tasks)
            if (!task.isCompleted) ..._taskTriggers(task),
          for (final event in events) ..._eventTriggers(event),
          for (final anniversary in anniversaries)
            ..._anniversaryTriggers(anniversary, rangeStart, rangeEnd),
        ]..sort((a, b) {
          final timeOrder = a.triggerAtLocal.compareTo(b.triggerAtLocal);
          return timeOrder != 0
              ? timeOrder
              : a.triggerId.compareTo(b.triggerId);
        });

    return CalendarPlatformProjection(
      generatedAt: effectiveNow.toIso8601String(),
      rangeStart: rangeStart.toJson(),
      rangeEndExclusive: rangeEnd.toJson(),
      widgetOccurrences: occurrences
          .map(
            (occurrence) => _widgetOccurrence(
              occurrence,
              timedEvent: occurrence.kind == CalendarOccurrenceKind.event
                  ? timedEvents[occurrence.sourceId]
                  : null,
            ),
          )
          .toList(),
      notificationTriggers: triggers,
    );
  }

  CalendarWidgetOccurrenceProjection _widgetOccurrence(
    CalendarOccurrence occurrence, {
    TimedCalendarEventSpec? timedEvent,
  }) {
    return CalendarWidgetOccurrenceProjection(
      occurrenceId: occurrence.occurrenceId,
      sourceType: occurrence.kind.name,
      sourceId: occurrence.sourceId,
      title: occurrence.title,
      note: occurrence.note,
      date: occurrence.date.toJson(),
      startTime: occurrence.startTime?.toJson(),
      endAtLocal: _occurrenceEndAtLocal(occurrence),
      startAtEpochMillis: timedEvent?.start.isUtc == true
          ? timedEvent!.start.millisecondsSinceEpoch
          : null,
      endAtEpochMillis: timedEvent?.end.isUtc == true
          ? timedEvent!.end.millisecondsSinceEpoch
          : null,
      endDateExclusive:
          occurrence.endDateExclusive?.toJson() ??
          occurrence.date.addDays(1).toJson(),
      isCompleted: occurrence.isCompleted,
    );
  }

  String? _occurrenceEndAtLocal(CalendarOccurrence occurrence) {
    final endTime = occurrence.endTime;
    if (endTime == null) return null;
    final endDateExclusive = occurrence.endDateExclusive;
    if (endDateExclusive == null) {
      return _localMinute(endTime.on(occurrence.date));
    }
    final endsAtMidnight = endTime == LocalTime(0, 0);
    final endDate = endsAtMidnight
        ? endDateExclusive
        : endDateExclusive.addDays(-1);
    return _localMinute(endTime.on(endDate));
  }

  Iterable<CalendarNotificationTriggerProjection> _taskTriggers(
    Task task,
  ) sync* {
    for (final reminder in task.reminders) {
      final anchor = switch (reminder.anchor) {
        ItemReminderAnchor.taskPlanned => (
          type: 'taskPlanned',
          date: task.plannedDate,
          time: task.plannedTime,
        ),
        ItemReminderAnchor.taskDue => (
          type: 'taskDue',
          date: task.dueDate,
          time: task.dueTime,
        ),
        _ => null,
      };
      if (anchor == null || anchor.date == null) continue;
      yield _trigger(
        sourceType: anchor.type,
        sourceId: task.id,
        occurrenceDate: anchor.date!,
        anchorTime: anchor.time,
        reminder: reminder,
        title: task.title,
        note: task.note,
      );
    }
  }

  Iterable<CalendarNotificationTriggerProjection> _eventTriggers(
    CalendarEvent event,
  ) sync* {
    final spec = event.spec;
    final (date, time) = switch (spec) {
      TimedCalendarEventSpec value => (
        LocalDate.fromDateTime(value.start.toLocal()),
        LocalTime.fromDateTime(value.start.toLocal()),
      ),
      AllDayCalendarEventSpec value => (value.startDate, null),
    };
    for (final reminder in event.reminders) {
      final trigger = _trigger(
        sourceType: 'event',
        sourceId: event.id,
        occurrenceDate: date,
        anchorTime: time,
        reminder: reminder,
        title: event.title,
        note: event.note,
      );
      yield CalendarNotificationTriggerProjection(
        triggerId: trigger.triggerId,
        sourceType: trigger.sourceType,
        sourceId: trigger.sourceId,
        occurrenceDate: trigger.occurrenceDate,
        reminderId: trigger.reminderId,
        title: trigger.title,
        note: trigger.note,
        triggerAtLocal: trigger.triggerAtLocal,
        triggerAtEpochMillis: spec is TimedCalendarEventSpec && spec.start.isUtc
            ? spec.start
                  .add(Duration(minutes: reminder.offsetMinutes))
                  .millisecondsSinceEpoch
            : null,
      );
    }
  }

  Iterable<CalendarNotificationTriggerProjection> _anniversaryTriggers(
    Anniversary anniversary,
    LocalDate rangeStart,
    LocalDate rangeEnd,
  ) sync* {
    for (var year = rangeStart.year; year <= rangeEnd.year; year++) {
      final date = anniversary.occurrenceInYear(year);
      if (date == null ||
          date.compareTo(rangeStart) < 0 ||
          date.compareTo(rangeEnd) >= 0) {
        continue;
      }
      for (final reminder in anniversary.reminders) {
        yield _trigger(
          sourceType: 'anniversary',
          sourceId: anniversary.id,
          occurrenceDate: date,
          anchorTime: null,
          reminder: reminder,
          title: anniversary.title,
          note: anniversary.note,
        );
      }
    }
  }

  CalendarNotificationTriggerProjection _trigger({
    required String sourceType,
    required String sourceId,
    required LocalDate occurrenceDate,
    required LocalTime? anchorTime,
    required ItemReminder reminder,
    required String title,
    required String? note,
  }) {
    final time = anchorTime ?? reminder.dateOnlyTime ?? LocalTime(9, 0);
    final triggerAt = time
        .on(occurrenceDate)
        .add(Duration(minutes: reminder.offsetMinutes));
    // ID 只由稳定领域身份组成，原生端才能可靠取消同一提醒的旧 PendingIntent。
    final triggerId = [
      sourceType,
      sourceId,
      occurrenceDate.toJson(),
      reminder.id,
    ].join(':');
    return CalendarNotificationTriggerProjection(
      triggerId: triggerId,
      sourceType: sourceType,
      sourceId: sourceId,
      occurrenceDate: occurrenceDate.toJson(),
      reminderId: reminder.id,
      title: title,
      note: note,
      triggerAtLocal: _localMinute(triggerAt),
    );
  }

  LocalDate _addMonths(LocalDate date, int months) {
    final value = DateTime.utc(date.year, date.month + months, 1);
    return LocalDate(value.year, value.month, value.day);
  }

  String _localMinute(DateTime value) {
    return '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}T'
        '${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}';
  }
}
