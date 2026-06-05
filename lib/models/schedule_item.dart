/// 本地日程或任务。
///
/// 时间统一按本地时间存取。普通日程使用 [kindSchedule]，任务类项目使用
/// [kindTask]，方便工具调用和页面用不同方式展示。
class ScheduleItem {
  /// 日程类型的常量值。
  static const kindSchedule = 'schedule';

  /// 任务类型的常量值。
  static const kindTask = 'task';

  /// 日程唯一标识符。
  final String id;

  /// 日程标题。
  final String title;

  /// 日程开始时间。
  final DateTime start;

  /// 日程结束时间。
  final DateTime end;

  /// 日程备注信息。
  final String? note;

  /// 日程类型，默认为 [kindSchedule]。
  final String kind;

  /// 创建一个日程实例。
  const ScheduleItem({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
    this.note,
    this.kind = kindSchedule,
  });

  /// 从 JSON 数据创建 [ScheduleItem] 实例。
  factory ScheduleItem.fromJson(Map<String, dynamic> json) {
    return ScheduleItem(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      start: DateTime.parse(json['start'] as String).toLocal(),
      end: DateTime.parse(json['end'] as String).toLocal(),
      note: json['note'] as String?,
      kind: json['kind'] as String? ?? kindSchedule,
    );
  }

  /// 将当前实例序列化为 JSON Map。
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'start': start.toIso8601String(),
      'end': end.toIso8601String(),
      if (note != null) 'note': note,
      if (kind != kindSchedule) 'kind': kind,
    };
  }

  /// 创建当前实例的副本，可选择性更新部分字段。
  ScheduleItem copyWith({
    String? id,
    String? title,
    DateTime? start,
    DateTime? end,
    Object? note = _sentinel,
    String? kind,
  }) {
    return ScheduleItem(
      id: id ?? this.id,
      title: title ?? this.title,
      start: start ?? this.start,
      end: end ?? this.end,
      note: identical(note, _sentinel) ? this.note : note as String?,
      kind: kind ?? this.kind,
    );
  }

  /// 判断当前日程是否为任务类型。
  bool get isTask => kind == kindTask;

  static const _sentinel = Object();
}
