import 'item_reminder.dart';
import 'local_date.dart';

const _unset = Object();

/// 日历事件的时间规格。
sealed class CalendarEventSpec {
  const CalendarEventSpec();

  /// 从 JSON 创建事件时间规格。
  factory CalendarEventSpec.fromJson(Map<String, dynamic> json) {
    return switch (json['type']) {
      'timed' => TimedCalendarEventSpec.fromJson(json),
      'allDay' => AllDayCalendarEventSpec.fromJson(json),
      final value => throw FormatException('未知事件时间规格', value),
    };
  }

  /// 将事件时间规格序列化为 JSON。
  Map<String, dynamic> toJson();
}

/// 具有精确开始和结束时刻的事件规格。
final class TimedCalendarEventSpec extends CalendarEventSpec {
  /// 开始时刻。
  final DateTime start;

  /// 结束时刻，必须晚于开始时刻。
  final DateTime end;

  /// 创建定时事件规格。
  TimedCalendarEventSpec({required this.start, required this.end}) {
    if (!end.isAfter(start)) {
      throw ArgumentError('事件结束时刻必须晚于开始时刻');
    }
  }

  /// 从 JSON 创建定时事件规格。
  factory TimedCalendarEventSpec.fromJson(Map<String, dynamic> json) {
    return TimedCalendarEventSpec(
      start: DateTime.parse(json['start'] as String),
      end: DateTime.parse(json['end'] as String),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'timed',
    'start': start.toIso8601String(),
    'end': end.toIso8601String(),
  };

  /// 创建修改后的定时事件规格副本。
  TimedCalendarEventSpec copyWith({DateTime? start, DateTime? end}) {
    return TimedCalendarEventSpec(
      start: start ?? this.start,
      end: end ?? this.end,
    );
  }
}

/// 按本地日期表示的全天事件规格。
final class AllDayCalendarEventSpec extends CalendarEventSpec {
  /// 首个包含的日期。
  final LocalDate startDate;

  /// 首个不包含的日期；单日事件应为开始日期的下一天。
  final LocalDate endDateExclusive;

  /// 创建采用半开区间 `[startDate, endDateExclusive)` 的全天事件规格。
  AllDayCalendarEventSpec({
    required this.startDate,
    required this.endDateExclusive,
  }) {
    if (endDateExclusive.compareTo(startDate) <= 0) {
      throw ArgumentError('全天事件结束日期必须晚于开始日期');
    }
  }

  /// 从 JSON 创建全天事件规格。
  factory AllDayCalendarEventSpec.fromJson(Map<String, dynamic> json) {
    return AllDayCalendarEventSpec(
      startDate: LocalDate.fromJson(json['startDate'] as String),
      endDateExclusive: LocalDate.fromJson(json['endDateExclusive'] as String),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'allDay',
    'startDate': startDate.toJson(),
    'endDateExclusive': endDateExclusive.toJson(),
  };

  /// 创建修改后的全天事件规格副本。
  AllDayCalendarEventSpec copyWith({
    LocalDate? startDate,
    LocalDate? endDateExclusive,
  }) {
    return AllDayCalendarEventSpec(
      startDate: startDate ?? this.startDate,
      endDateExclusive: endDateExclusive ?? this.endDateExclusive,
    );
  }
}

/// 日历事件。
final class CalendarEvent {
  /// 事件唯一标识符。
  final String id;

  /// 事件标题。
  final String title;

  /// 可选备注。
  final String? note;

  /// 事件时间规格。
  final CalendarEventSpec spec;

  /// 事件提醒。
  final List<ItemReminder> reminders;

  /// 创建时间。
  final DateTime createdAt;

  /// 最后更新时间。
  final DateTime updatedAt;

  /// 创建日历事件。
  CalendarEvent({
    required this.id,
    required this.title,
    this.note,
    required this.spec,
    List<ItemReminder> reminders = const [],
    required this.createdAt,
    required this.updatedAt,
  }) : reminders = validatedReminders(reminders) {
    if (this.reminders.any(
      (value) => value.anchor != ItemReminderAnchor.eventStart,
    )) {
      throw ArgumentError('事件提醒只能使用事件开始锚点');
    }
    if (spec is TimedCalendarEventSpec &&
        this.reminders.any((value) => value.dateOnlyTime != null)) {
      throw ArgumentError('定时事件提醒不能设置日期型提醒时间');
    }
  }

  /// 从 JSON 创建日历事件。
  factory CalendarEvent.fromJson(Map<String, dynamic> json) {
    return CalendarEvent(
      id: json['id'] as String,
      title: json['title'] as String,
      note: json['note'] as String?,
      spec: CalendarEventSpec.fromJson(json['spec'] as Map<String, dynamic>),
      reminders: (json['reminders'] as List<dynamic>? ?? const [])
          .map((value) => ItemReminder.fromJson(value as Map<String, dynamic>))
          .toList(),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  /// 将日历事件序列化为 JSON。
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'note': note,
    'spec': spec.toJson(),
    'reminders': reminders.map((value) => value.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  /// 创建修改后的日历事件副本。
  CalendarEvent copyWith({
    String? id,
    String? title,
    Object? note = _unset,
    CalendarEventSpec? spec,
    List<ItemReminder>? reminders,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CalendarEvent(
      id: id ?? this.id,
      title: title ?? this.title,
      note: identical(note, _unset) ? this.note : note as String?,
      spec: spec ?? this.spec,
      reminders: reminders ?? this.reminders,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
