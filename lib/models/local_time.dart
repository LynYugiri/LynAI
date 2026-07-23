import 'local_date.dart';

/// 不带日期和时区的分钟精度本地时间，字符串形式固定为 `HH:mm`。
final class LocalTime implements Comparable<LocalTime> {
  /// 小时，范围为 0 到 23。
  final int hour;

  /// 分钟，范围为 0 到 59。
  final int minute;

  /// 创建并校验一个本地时间。
  factory LocalTime(int hour, int minute) {
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      throw ArgumentError.value('$hour:$minute', 'time', '无效时间');
    }
    return LocalTime._(hour, minute);
  }

  const LocalTime._(this.hour, this.minute);

  /// 从严格的 `HH:mm` 字符串解析时间。
  factory LocalTime.parse(String value) {
    final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(value);
    if (match == null) {
      throw FormatException('时间必须使用 HH:mm 格式', value);
    }
    try {
      return LocalTime(int.parse(match.group(1)!), int.parse(match.group(2)!));
    } on ArgumentError {
      throw FormatException('无效时间', value);
    }
  }

  /// 尝试从严格的 `HH:mm` 字符串解析时间，失败时返回空值。
  static LocalTime? tryParse(String value) {
    try {
      return LocalTime.parse(value);
    } on FormatException {
      return null;
    }
  }

  /// 从 JSON 字符串创建时间。
  factory LocalTime.fromJson(String value) => LocalTime.parse(value);

  /// 从 [DateTime] 的时钟字段创建分钟精度时间。
  factory LocalTime.fromDateTime(DateTime value) {
    return LocalTime(value.hour, value.minute);
  }

  /// 将日期和时间组合为本地 [DateTime]。
  DateTime on(LocalDate date) {
    return DateTime(date.year, date.month, date.day, hour, minute);
  }

  /// 创建修改后的时间副本。
  LocalTime copyWith({int? hour, int? minute}) {
    return LocalTime(hour ?? this.hour, minute ?? this.minute);
  }

  /// 将时间序列化为适合 JSON 的字符串。
  String toJson() => toString();

  @override
  int compareTo(LocalTime other) {
    final hourOrder = hour.compareTo(other.hour);
    return hourOrder != 0 ? hourOrder : minute.compareTo(other.minute);
  }

  @override
  bool operator ==(Object other) {
    return other is LocalTime && hour == other.hour && minute == other.minute;
  }

  @override
  int get hashCode => Object.hash(hour, minute);

  @override
  String toString() {
    return '${hour.toString().padLeft(2, '0')}:'
        '${minute.toString().padLeft(2, '0')}';
  }
}
