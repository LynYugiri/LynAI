import 'local_time.dart';

const _unset = Object();

/// 提醒相对于业务时间点的锚点。
enum ItemReminderAnchor {
  /// 日历事件开始时间。
  eventStart,

  /// 任务计划时间。
  taskPlanned,

  /// 任务截止时间。
  taskDue,

  /// 纪念日日期。
  anniversaryDate,
}

/// 相对于指定锚点的提醒；负偏移表示提前，正偏移表示延后。
final class ItemReminder {
  /// 提醒唯一标识符。
  final String id;

  /// 提醒所依附的业务时间点。
  final ItemReminderAnchor anchor;

  /// 相对锚点的有符号分钟偏移。
  final int offsetMinutes;

  /// 日期型锚点触发提醒时采用的可选本地时间。
  final LocalTime? dateOnlyTime;

  /// 创建提醒。
  const ItemReminder({
    required this.id,
    required this.anchor,
    required this.offsetMinutes,
    this.dateOnlyTime,
  });

  /// 从 JSON 创建提醒。
  factory ItemReminder.fromJson(Map<String, dynamic> json) {
    final anchorName = json['anchor'] as String?;
    return ItemReminder(
      id: json['id'] as String,
      anchor: ItemReminderAnchor.values.firstWhere(
        (value) => value.name == anchorName,
        orElse: () => throw FormatException('未知提醒锚点', anchorName),
      ),
      offsetMinutes: json['offsetMinutes'] as int,
      dateOnlyTime: switch (json['dateOnlyTime']) {
        final String value => LocalTime.fromJson(value),
        null => null,
        _ => throw const FormatException('提醒日期时间必须是字符串'),
      },
    );
  }

  /// 将提醒序列化为 JSON。
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'anchor': anchor.name,
      'offsetMinutes': offsetMinutes,
      'dateOnlyTime': dateOnlyTime?.toJson(),
    };
  }

  /// 创建修改后的提醒副本。
  ItemReminder copyWith({
    String? id,
    ItemReminderAnchor? anchor,
    int? offsetMinutes,
    Object? dateOnlyTime = _unset,
  }) {
    return ItemReminder(
      id: id ?? this.id,
      anchor: anchor ?? this.anchor,
      offsetMinutes: offsetMinutes ?? this.offsetMinutes,
      dateOnlyTime: identical(dateOnlyTime, _unset)
          ? this.dateOnlyTime
          : dateOnlyTime as LocalTime?,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ItemReminder &&
        id == other.id &&
        anchor == other.anchor &&
        offsetMinutes == other.offsetMinutes &&
        dateOnlyTime == other.dateOnlyTime;
  }

  @override
  int get hashCode => Object.hash(id, anchor, offsetMinutes, dateOnlyTime);
}

/// 校验提醒集合没有完全相同的项，并返回不可变副本。
List<ItemReminder> validatedReminders(Iterable<ItemReminder> reminders) {
  final values = List<ItemReminder>.of(reminders);
  if (values.toSet().length != values.length) {
    throw ArgumentError('提醒不能包含完全相同的重复项');
  }
  return List.unmodifiable(values);
}
