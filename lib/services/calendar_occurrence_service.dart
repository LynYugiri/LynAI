import '../models/anniversary.dart';
import '../models/calendar_event.dart';
import '../models/calendar_occurrence.dart';
import '../models/local_date.dart';
import '../models/local_time.dart';
import '../models/task.dart';

/// 将领域对象投影为指定日期范围内的日历发生记录。
final class CalendarOccurrenceService {
  const CalendarOccurrenceService({this.toLocal = _toLocal});

  final DateTime Function(DateTime value) toLocal;

  /// 投影半开区间 `[startDate, endDateExclusive)` 内的记录。
  List<CalendarOccurrence> project({
    required LocalDate startDate,
    required LocalDate endDateExclusive,
    Iterable<CalendarEvent> events = const [],
    Iterable<Task> tasks = const [],
    Iterable<Anniversary> anniversaries = const [],
    DateTime? now,
  }) {
    if (endDateExclusive.compareTo(startDate) < 0) {
      throw ArgumentError('投影结束日期不能早于开始日期');
    }

    final projectionTime = now ?? DateTime.now();
    final occurrences = <CalendarOccurrence>[];
    for (final event in events) {
      final occurrence = _eventOccurrence(event, startDate, endDateExclusive);
      if (occurrence != null) occurrences.add(occurrence);
    }
    for (final task in tasks) {
      occurrences.addAll(
        _taskOccurrences(task, startDate, endDateExclusive, projectionTime),
      );
    }
    for (final anniversary in anniversaries) {
      occurrences.addAll(
        _anniversaryOccurrences(anniversary, startDate, endDateExclusive),
      );
    }

    occurrences.sort(_compareOccurrences);
    return occurrences;
  }

  CalendarOccurrence? _eventOccurrence(
    CalendarEvent event,
    LocalDate rangeStart,
    LocalDate rangeEnd,
  ) {
    return switch (event.spec) {
      TimedCalendarEventSpec spec => _timedEventOccurrence(
        event,
        spec,
        rangeStart,
        rangeEnd,
      ),
      AllDayCalendarEventSpec spec => _allDayEventOccurrence(
        event,
        spec,
        rangeStart,
        rangeEnd,
      ),
    };
  }

  CalendarOccurrence? _timedEventOccurrence(
    CalendarEvent event,
    TimedCalendarEventSpec spec,
    LocalDate rangeStart,
    LocalDate rangeEnd,
  ) {
    final localStart = toLocal(spec.start);
    final localEnd = toLocal(spec.end);
    final eventStartDate = LocalDate.fromDateTime(localStart);
    final eventEndExclusive = _timedEndDateExclusive(localEnd);
    if (!_overlaps(eventStartDate, eventEndExclusive, rangeStart, rangeEnd)) {
      return null;
    }
    return CalendarOccurrence(
      occurrenceId: _occurrenceId(
        CalendarOccurrenceKind.event,
        event.id,
        eventStartDate,
      ),
      sourceId: event.id,
      kind: CalendarOccurrenceKind.event,
      date: eventStartDate,
      title: event.title,
      note: event.note,
      startTime: LocalTime.fromDateTime(localStart),
      endTime: LocalTime.fromDateTime(localEnd),
      endDateExclusive: eventEndExclusive,
    );
  }

  CalendarOccurrence? _allDayEventOccurrence(
    CalendarEvent event,
    AllDayCalendarEventSpec spec,
    LocalDate rangeStart,
    LocalDate rangeEnd,
  ) {
    if (!_overlaps(
      spec.startDate,
      spec.endDateExclusive,
      rangeStart,
      rangeEnd,
    )) {
      return null;
    }
    return CalendarOccurrence(
      occurrenceId: _occurrenceId(
        CalendarOccurrenceKind.event,
        event.id,
        spec.startDate,
      ),
      sourceId: event.id,
      kind: CalendarOccurrenceKind.event,
      date: spec.startDate,
      title: event.title,
      note: event.note,
      endDateExclusive: spec.endDateExclusive,
    );
  }

  Iterable<CalendarOccurrence> _taskOccurrences(
    Task task,
    LocalDate rangeStart,
    LocalDate rangeEnd,
    DateTime now,
  ) sync* {
    final plannedInRange =
        task.plannedDate != null &&
        _contains(task.plannedDate!, rangeStart, rangeEnd);
    final dueInRange =
        task.dueDate != null && _contains(task.dueDate!, rangeStart, rangeEnd);

    if (plannedInRange && dueInRange && task.plannedDate == task.dueDate) {
      yield CalendarOccurrence(
        occurrenceId: _occurrenceId(
          CalendarOccurrenceKind.taskPlannedAndDue,
          task.id,
          task.plannedDate!,
        ),
        sourceId: task.id,
        kind: CalendarOccurrenceKind.taskPlannedAndDue,
        date: task.plannedDate!,
        title: task.title,
        note: task.note,
        startTime: task.plannedTime ?? task.dueTime,
        endTime: task.plannedTime != null && task.dueTime != null
            ? task.dueTime
            : null,
        isCompleted: task.isCompleted,
        isOverdue: task.isOverdueAt(now),
      );
      return;
    }
    if (plannedInRange) {
      yield CalendarOccurrence(
        occurrenceId: _occurrenceId(
          CalendarOccurrenceKind.taskPlanned,
          task.id,
          task.plannedDate!,
        ),
        sourceId: task.id,
        kind: CalendarOccurrenceKind.taskPlanned,
        date: task.plannedDate!,
        title: task.title,
        note: task.note,
        startTime: task.plannedTime,
        isCompleted: task.isCompleted,
        isOverdue: task.isOverdueAt(now),
      );
    }
    if (dueInRange) {
      yield CalendarOccurrence(
        occurrenceId: _occurrenceId(
          CalendarOccurrenceKind.taskDue,
          task.id,
          task.dueDate!,
        ),
        sourceId: task.id,
        kind: CalendarOccurrenceKind.taskDue,
        date: task.dueDate!,
        title: task.title,
        note: task.note,
        startTime: task.dueTime,
        isCompleted: task.isCompleted,
        isOverdue: task.isOverdueAt(now),
      );
    }
  }

  Iterable<CalendarOccurrence> _anniversaryOccurrences(
    Anniversary anniversary,
    LocalDate rangeStart,
    LocalDate rangeEnd,
  ) sync* {
    for (var year = rangeStart.year; year <= rangeEnd.year; year++) {
      final date = anniversary.occurrenceInYear(year);
      if (date != null && _contains(date, rangeStart, rangeEnd)) {
        yield CalendarOccurrence(
          occurrenceId: _occurrenceId(
            CalendarOccurrenceKind.anniversary,
            anniversary.id,
            date,
          ),
          sourceId: anniversary.id,
          kind: CalendarOccurrenceKind.anniversary,
          date: date,
          title: anniversary.title,
          note: anniversary.note,
        );
      }
    }
  }

  /// 恰好在午夜结束的定时事件不占用下一日。
  LocalDate _timedEndDateExclusive(DateTime end) {
    final endDate = LocalDate.fromDateTime(end);
    final isMidnight =
        end.hour == 0 &&
        end.minute == 0 &&
        end.second == 0 &&
        end.millisecond == 0 &&
        end.microsecond == 0;
    return isMidnight ? endDate : endDate.addDays(1);
  }

  bool _contains(LocalDate date, LocalDate start, LocalDate end) {
    return date.compareTo(start) >= 0 && date.compareTo(end) < 0;
  }

  bool _overlaps(
    LocalDate firstStart,
    LocalDate firstEnd,
    LocalDate secondStart,
    LocalDate secondEnd,
  ) {
    return firstStart.compareTo(secondEnd) < 0 &&
        secondStart.compareTo(firstEnd) < 0;
  }

  int _compareOccurrences(CalendarOccurrence first, CalendarOccurrence second) {
    final dateOrder = first.date.compareTo(second.date);
    if (dateOrder != 0) return dateOrder;
    if (first.startTime == null && second.startTime != null) return -1;
    if (first.startTime != null && second.startTime == null) return 1;
    final timeOrder = first.startTime?.compareTo(second.startTime!) ?? 0;
    if (timeOrder != 0) return timeOrder;
    final kindOrder = first.kind.index.compareTo(second.kind.index);
    if (kindOrder != 0) return kindOrder;
    return first.occurrenceId.compareTo(second.occurrenceId);
  }

  String _occurrenceId(
    CalendarOccurrenceKind kind,
    String sourceId,
    LocalDate date,
  ) {
    return '${kind.name}:$sourceId:${date.toJson()}';
  }
}

DateTime _toLocal(DateTime value) => value.toLocal();
