import 'package:flutter/foundation.dart';

import '../models/anniversary.dart';
import '../models/calendar_event.dart';
import '../models/local_date.dart';
import '../services/storage_v2_service.dart';

/// `calendar.json` 分区的完整领域快照。
final class CalendarLoadResult {
  const CalendarLoadResult({required this.events, required this.anniversaries});

  final List<CalendarEvent> events;
  final List<Anniversary> anniversaries;
}

/// 日历分区仓储；只读写 `calendar.json` 的事件和纪念日。
class CalendarRepository {
  CalendarRepository({StorageV2Service? storageV2})
    : _storageV2 = storageV2 ?? StorageV2Service();

  static const fileName = 'calendar.json';

  final StorageV2Service _storageV2;

  Future<CalendarLoadResult> load() async {
    final data = await _storageV2.loadDataFile(fileName);
    final events = <CalendarEvent>[];
    final anniversaries = <Anniversary>[];
    for (final item in data['events'] as List<dynamic>? ?? const []) {
      try {
        if (item is Map) {
          events.add(_eventFromPartition(Map<String, dynamic>.from(item)));
        }
      } catch (error) {
        debugPrint('跳过损坏的日历事件: $error');
      }
    }
    for (final item in data['anniversaries'] as List<dynamic>? ?? const []) {
      try {
        if (item is Map) {
          anniversaries.add(
            _anniversaryFromPartition(Map<String, dynamic>.from(item)),
          );
        }
      } catch (error) {
        debugPrint('跳过损坏的纪念日: $error');
      }
    }
    return CalendarLoadResult(
      events: List.unmodifiable(events),
      anniversaries: List.unmodifiable(anniversaries),
    );
  }

  Future<void> save({
    required List<CalendarEvent> events,
    required List<Anniversary> anniversaries,
  }) {
    return _storageV2.writeDataFile(fileName, {
      'events': events.map(_eventToPartition).toList(),
      'anniversaries': anniversaries.map(_anniversaryToPartition).toList(),
    });
  }

  CalendarEvent _eventFromPartition(Map<String, dynamic> json) {
    final spec = switch (json['timeKind']) {
      'timed' => TimedCalendarEventSpec(
        start: DateTime.parse(json['startAt'] as String),
        end: DateTime.parse(json['endAt'] as String),
      ),
      'allDay' => AllDayCalendarEventSpec(
        startDate: LocalDate.fromJson(json['startDate'] as String),
        endDateExclusive: LocalDate.fromJson(
          json['endDateExclusive'] as String,
        ),
      ),
      final value => throw FormatException('未知日历事件时间类型', value),
    };
    return CalendarEvent.fromJson({...json, 'spec': spec.toJson()});
  }

  Map<String, dynamic> _eventToPartition(CalendarEvent event) {
    final time = switch (event.spec) {
      TimedCalendarEventSpec spec => {
        'timeKind': 'timed',
        'startAt': spec.start.toIso8601String(),
        'endAt': spec.end.toIso8601String(),
      },
      AllDayCalendarEventSpec spec => {
        'timeKind': 'allDay',
        'startDate': spec.startDate.toJson(),
        // 全天结束日期为首个不包含的日期，持久化时不得转成闭区间。
        'endDateExclusive': spec.endDateExclusive.toJson(),
      },
    };
    return {
      'id': event.id,
      'title': event.title,
      if (event.note != null) 'note': event.note,
      ...time,
      'reminders': event.reminders.map((value) => value.toJson()).toList(),
      'createdAt': event.createdAt.toIso8601String(),
      'updatedAt': event.updatedAt.toIso8601String(),
    };
  }

  Anniversary _anniversaryFromPartition(Map<String, dynamic> json) {
    final month = json['month'] as int;
    final day = json['day'] as int;
    final year = json['year'] as int?;
    final spec = switch (json['recurrence']) {
      'once' => OnceAnniversarySpec(
        date: LocalDate(
          year ?? (throw const FormatException('一次性纪念日缺少年份')),
          month,
          day,
        ),
      ),
      'yearly' => YearlyAnniversarySpec(
        month: month,
        day: day,
        sourceYear: year,
      ),
      final value => throw FormatException('未知纪念日重复类型', value),
    };
    return Anniversary.fromJson({...json, 'spec': spec.toJson()});
  }

  Map<String, dynamic> _anniversaryToPartition(Anniversary anniversary) {
    final date = switch (anniversary.spec) {
      OnceAnniversarySpec spec => {
        'month': spec.date.month,
        'day': spec.date.day,
        'year': spec.date.year,
        'recurrence': 'once',
      },
      YearlyAnniversarySpec spec => {
        'month': spec.month,
        'day': spec.day,
        if (spec.sourceYear != null) 'year': spec.sourceYear,
        'recurrence': 'yearly',
      },
    };
    return {
      'id': anniversary.id,
      'title': anniversary.title,
      if (anniversary.note != null) 'note': anniversary.note,
      ...date,
      'showYearCount': anniversary.showYearCount,
      'reminders': anniversary.reminders
          .map((value) => value.toJson())
          .toList(),
      'createdAt': anniversary.createdAt.toIso8601String(),
      'updatedAt': anniversary.updatedAt.toIso8601String(),
    };
  }
}
