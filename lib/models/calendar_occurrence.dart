import 'local_date.dart';
import 'local_time.dart';

const _unset = Object();

/// 日历投影中一次发生记录的来源类型。
enum CalendarOccurrenceKind {
  /// 日历事件。
  event,

  /// 任务计划日期。
  taskPlanned,

  /// 任务截止日期。
  taskDue,

  /// 同一天的任务计划和截止日期合并结果。
  taskPlannedAndDue,

  /// 纪念日。
  anniversary,
}

/// 可供日历消费的扁平发生记录。
final class CalendarOccurrence {
  /// 发生记录的稳定标识符。
  final String occurrenceId;

  /// 来源对象标识符。
  final String sourceId;

  /// 来源类型。
  final CalendarOccurrenceKind kind;

  /// 发生日期；多日事件保留其原始开始日期。
  final LocalDate date;

  /// 标题。
  final String title;

  /// 可选备注。
  final String? note;

  /// 可选开始时间；全天项目为空。
  final LocalTime? startTime;

  /// 可选结束时间；定时事件或合并任务可用。
  final LocalTime? endTime;

  /// 首个不包含的结束日期；任务和纪念日为空。
  final LocalDate? endDateExclusive;

  /// 来源任务是否已经完成。
  final bool isCompleted;

  /// 来源任务在投影时刻是否已经逾期。
  final bool isOverdue;

  /// 创建日历发生记录。
  const CalendarOccurrence({
    required this.occurrenceId,
    required this.sourceId,
    required this.kind,
    required this.date,
    required this.title,
    this.note,
    this.startTime,
    this.endTime,
    this.endDateExclusive,
    this.isCompleted = false,
    this.isOverdue = false,
  });

  /// 从 JSON 创建发生记录。
  factory CalendarOccurrence.fromJson(Map<String, dynamic> json) {
    return CalendarOccurrence(
      occurrenceId: json['occurrenceId'] as String,
      sourceId: json['sourceId'] as String,
      kind: CalendarOccurrenceKind.values.firstWhere(
        (value) => value.name == json['kind'],
        orElse: () => throw FormatException('未知发生记录类型', json['kind']),
      ),
      date: LocalDate.fromJson(json['date'] as String),
      title: json['title'] as String,
      note: json['note'] as String?,
      startTime: _timeFromJson(json['startTime']),
      endTime: _timeFromJson(json['endTime']),
      endDateExclusive: _dateFromJson(json['endDateExclusive']),
      isCompleted: json['isCompleted'] as bool? ?? false,
      isOverdue: json['isOverdue'] as bool? ?? false,
    );
  }

  /// 是否为全天发生记录。
  bool get isAllDay => startTime == null;

  /// 将发生记录序列化为 JSON。
  Map<String, dynamic> toJson() => {
    'occurrenceId': occurrenceId,
    'sourceId': sourceId,
    'kind': kind.name,
    'date': date.toJson(),
    'title': title,
    'note': note,
    'startTime': startTime?.toJson(),
    'endTime': endTime?.toJson(),
    'endDateExclusive': endDateExclusive?.toJson(),
    'isCompleted': isCompleted,
    'isOverdue': isOverdue,
  };

  /// 创建修改后的发生记录副本。
  CalendarOccurrence copyWith({
    String? occurrenceId,
    String? sourceId,
    CalendarOccurrenceKind? kind,
    LocalDate? date,
    String? title,
    Object? note = _unset,
    Object? startTime = _unset,
    Object? endTime = _unset,
    Object? endDateExclusive = _unset,
    bool? isCompleted,
    bool? isOverdue,
  }) {
    return CalendarOccurrence(
      occurrenceId: occurrenceId ?? this.occurrenceId,
      sourceId: sourceId ?? this.sourceId,
      kind: kind ?? this.kind,
      date: date ?? this.date,
      title: title ?? this.title,
      note: identical(note, _unset) ? this.note : note as String?,
      startTime: identical(startTime, _unset)
          ? this.startTime
          : startTime as LocalTime?,
      endTime: identical(endTime, _unset)
          ? this.endTime
          : endTime as LocalTime?,
      endDateExclusive: identical(endDateExclusive, _unset)
          ? this.endDateExclusive
          : endDateExclusive as LocalDate?,
      isCompleted: isCompleted ?? this.isCompleted,
      isOverdue: isOverdue ?? this.isOverdue,
    );
  }
}

LocalDate? _dateFromJson(Object? value) => switch (value) {
  final String value => LocalDate.fromJson(value),
  null => null,
  _ => throw const FormatException('日期必须是字符串'),
};

LocalTime? _timeFromJson(Object? value) => switch (value) {
  final String value => LocalTime.fromJson(value),
  null => null,
  _ => throw const FormatException('时间必须是字符串'),
};
