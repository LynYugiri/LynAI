import 'item_reminder.dart';
import 'local_date.dart';
import 'local_time.dart';

const _unset = Object();

/// 独立于清单归属的任务领域对象。
final class Task {
  /// 任务唯一标识符。
  final String id;

  /// 任务标题。
  final String title;

  /// 可选备注。
  final String? note;

  /// 可选计划日期。
  final LocalDate? plannedDate;

  /// 可选计划时间；仅在存在计划日期时有效。
  final LocalTime? plannedTime;

  /// 可选截止日期。
  final LocalDate? dueDate;

  /// 可选截止时间；仅在存在截止日期时有效。
  final LocalTime? dueTime;

  /// 完成时间；非空即表示任务已完成。
  final DateTime? completedAt;

  /// 创建时间。
  final DateTime createdAt;

  /// 最后更新时间。
  final DateTime updatedAt;

  /// 任务提醒。
  final List<ItemReminder> reminders;

  /// 创建任务并校验日期与时间的依赖关系。
  Task({
    required this.id,
    required this.title,
    this.note,
    this.plannedDate,
    this.plannedTime,
    this.dueDate,
    this.dueTime,
    this.completedAt,
    required this.createdAt,
    required this.updatedAt,
    List<ItemReminder> reminders = const [],
  }) : reminders = validatedReminders(reminders) {
    if (plannedTime != null && plannedDate == null) {
      throw ArgumentError('计划时间必须同时提供计划日期');
    }
    if (dueTime != null && dueDate == null) {
      throw ArgumentError('截止时间必须同时提供截止日期');
    }
    for (final reminder in this.reminders) {
      if (reminder.anchor == ItemReminderAnchor.taskPlanned &&
          plannedDate == null) {
        throw ArgumentError('计划提醒必须同时提供计划日期');
      }
      if (reminder.anchor == ItemReminderAnchor.taskDue && dueDate == null) {
        throw ArgumentError('截止提醒必须同时提供截止日期');
      }
      if (reminder.anchor != ItemReminderAnchor.taskPlanned &&
          reminder.anchor != ItemReminderAnchor.taskDue) {
        throw ArgumentError('任务提醒只能使用任务计划或截止锚点');
      }
      if (reminder.anchor == ItemReminderAnchor.taskPlanned &&
          plannedTime != null &&
          reminder.dateOnlyTime != null) {
        throw ArgumentError('具有计划时间的任务提醒不能设置日期型提醒时间');
      }
      if (reminder.anchor == ItemReminderAnchor.taskDue &&
          dueTime != null &&
          reminder.dateOnlyTime != null) {
        throw ArgumentError('具有截止时间的任务提醒不能设置日期型提醒时间');
      }
    }
  }

  /// 从 JSON 创建任务。
  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      id: json['id'] as String,
      title: json['title'] as String,
      note: json['note'] as String?,
      plannedDate: _dateFromJson(json['plannedDate']),
      plannedTime: _timeFromJson(json['plannedTime']),
      dueDate: _dateFromJson(json['dueDate']),
      dueTime: _timeFromJson(json['dueTime']),
      completedAt: _dateTimeFromJson(json['completedAt']),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      reminders: (json['reminders'] as List<dynamic>? ?? const [])
          .map((value) => ItemReminder.fromJson(value as Map<String, dynamic>))
          .toList(),
    );
  }

  /// 任务是否已经完成。
  bool get isCompleted => completedAt != null;

  /// 以当前本地时间判断任务是否逾期。
  bool get isOverdue => isOverdueAt(DateTime.now());

  /// 在给定本地时间判断任务是否逾期。
  ///
  /// 没有截止时间的任务在截止日期结束后才逾期。
  bool isOverdueAt(DateTime now) {
    if (isCompleted || dueDate == null) return false;
    if (dueTime != null) return now.isAfter(dueTime!.on(dueDate!));
    return LocalDate.fromDateTime(now).compareTo(dueDate!) > 0;
  }

  /// 将任务序列化为 JSON。
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'note': note,
      'plannedDate': plannedDate?.toJson(),
      'plannedTime': plannedTime?.toJson(),
      'dueDate': dueDate?.toJson(),
      'dueTime': dueTime?.toJson(),
      'completedAt': completedAt?.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'reminders': reminders.map((value) => value.toJson()).toList(),
    };
  }

  /// 创建修改后的任务副本。
  Task copyWith({
    String? id,
    String? title,
    Object? note = _unset,
    Object? plannedDate = _unset,
    Object? plannedTime = _unset,
    Object? dueDate = _unset,
    Object? dueTime = _unset,
    Object? completedAt = _unset,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<ItemReminder>? reminders,
  }) {
    return Task(
      id: id ?? this.id,
      title: title ?? this.title,
      note: identical(note, _unset) ? this.note : note as String?,
      plannedDate: identical(plannedDate, _unset)
          ? this.plannedDate
          : plannedDate as LocalDate?,
      plannedTime: identical(plannedTime, _unset)
          ? this.plannedTime
          : plannedTime as LocalTime?,
      dueDate: identical(dueDate, _unset)
          ? this.dueDate
          : dueDate as LocalDate?,
      dueTime: identical(dueTime, _unset)
          ? this.dueTime
          : dueTime as LocalTime?,
      completedAt: identical(completedAt, _unset)
          ? this.completedAt
          : completedAt as DateTime?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      reminders: reminders ?? this.reminders,
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

DateTime? _dateTimeFromJson(Object? value) => switch (value) {
  final String value => DateTime.parse(value),
  null => null,
  _ => throw const FormatException('时间戳必须是字符串'),
};
