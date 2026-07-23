/// Android 日历小组件与通知消费的版本化完整投影。
final class CalendarPlatformProjection {
  static const currentVersion = 2;

  final int version;
  final String generatedAt;
  final String rangeStart;
  final String rangeEndExclusive;
  final List<CalendarWidgetOccurrenceProjection> widgetOccurrences;
  final List<CalendarNotificationTriggerProjection> notificationTriggers;

  const CalendarPlatformProjection({
    this.version = currentVersion,
    required this.generatedAt,
    required this.rangeStart,
    required this.rangeEndExclusive,
    required this.widgetOccurrences,
    required this.notificationTriggers,
  });

  Map<String, dynamic> toJson() => {
    'version': version,
    'generatedAt': generatedAt,
    'rangeStart': rangeStart,
    'rangeEndExclusive': rangeEndExclusive,
    'widgetOccurrences': widgetOccurrences
        .map((value) => value.toJson())
        .toList(),
    'notificationTriggers': notificationTriggers
        .map((value) => value.toJson())
        .toList(),
  };
}

/// 小组件只消费边界内的扁平发生记录，不读取领域持久化数据。
final class CalendarWidgetOccurrenceProjection {
  final String occurrenceId;
  final String sourceType;
  final String sourceId;
  final String title;
  final String? note;
  final String date;
  final String? startTime;
  final String? endAtLocal;
  final int? startAtEpochMillis;
  final int? endAtEpochMillis;
  final String endDateExclusive;
  final bool isCompleted;

  const CalendarWidgetOccurrenceProjection({
    required this.occurrenceId,
    required this.sourceType,
    required this.sourceId,
    required this.title,
    this.note,
    required this.date,
    this.startTime,
    this.endAtLocal,
    this.startAtEpochMillis,
    this.endAtEpochMillis,
    required this.endDateExclusive,
    this.isCompleted = false,
  });

  Map<String, dynamic> toJson() => {
    'occurrenceId': occurrenceId,
    'sourceType': sourceType,
    'sourceId': sourceId,
    'title': title,
    'note': note,
    'date': date,
    'startTime': startTime,
    'endAtLocal': endAtLocal,
    'startAtEpochMillis': startAtEpochMillis,
    'endAtEpochMillis': endAtEpochMillis,
    'endDateExclusive': endDateExclusive,
    'isCompleted': isCompleted,
  };
}

/// 一个显式 ItemReminder 对应一个独立原生触发器。
final class CalendarNotificationTriggerProjection {
  final String triggerId;
  final String sourceType;
  final String sourceId;
  final String occurrenceDate;
  final String reminderId;
  final String title;
  final String? note;
  final String triggerAtLocal;
  final int? triggerAtEpochMillis;

  const CalendarNotificationTriggerProjection({
    required this.triggerId,
    required this.sourceType,
    required this.sourceId,
    required this.occurrenceDate,
    required this.reminderId,
    required this.title,
    this.note,
    required this.triggerAtLocal,
    this.triggerAtEpochMillis,
  });

  Map<String, dynamic> toJson() => {
    'triggerId': triggerId,
    'sourceType': sourceType,
    'sourceId': sourceId,
    'occurrenceDate': occurrenceDate,
    'reminderId': reminderId,
    'title': title,
    'note': note,
    'triggerAtLocal': triggerAtLocal,
    'triggerAtEpochMillis': triggerAtEpochMillis,
  };
}
