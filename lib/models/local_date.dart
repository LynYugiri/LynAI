/// 不带时区和时刻的公历日期，字符串形式固定为 `YYYY-MM-DD`。
final class LocalDate implements Comparable<LocalDate> {
  /// 年。
  final int year;

  /// 月，范围为 1 到 12。
  final int month;

  /// 日，范围由对应年月决定。
  final int day;

  /// 创建并校验一个公历日期。
  factory LocalDate(int year, int month, int day) {
    final normalized = DateTime.utc(year, month, day);
    if (normalized.year != year ||
        normalized.month != month ||
        normalized.day != day) {
      throw ArgumentError.value('$year-$month-$day', 'date', '无效日期');
    }
    return LocalDate._(year, month, day);
  }

  const LocalDate._(this.year, this.month, this.day);

  /// 从严格的 `YYYY-MM-DD` 字符串解析日期。
  factory LocalDate.parse(String value) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (match == null) {
      throw FormatException('日期必须使用 YYYY-MM-DD 格式', value);
    }
    try {
      return LocalDate(
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
        int.parse(match.group(3)!),
      );
    } on ArgumentError {
      throw FormatException('无效日期', value);
    }
  }

  /// 尝试从严格的 `YYYY-MM-DD` 字符串解析日期，失败时返回空值。
  static LocalDate? tryParse(String value) {
    try {
      return LocalDate.parse(value);
    } on FormatException {
      return null;
    }
  }

  /// 从 JSON 字符串创建日期。
  factory LocalDate.fromJson(String value) => LocalDate.parse(value);

  /// 从 [DateTime] 的同一时区日历字段创建日期。
  factory LocalDate.fromDateTime(DateTime value) {
    return LocalDate(value.year, value.month, value.day);
  }

  /// 按公历日期推进天数，不以固定 24 小时时长计算。
  LocalDate addDays(int days) {
    final value = DateTime.utc(year, month, day + days);
    return LocalDate(value.year, value.month, value.day);
  }

  /// 创建修改后的日期副本。
  LocalDate copyWith({int? year, int? month, int? day}) {
    return LocalDate(year ?? this.year, month ?? this.month, day ?? this.day);
  }

  /// 返回当天本地午夜。
  DateTime atStartOfDay() => DateTime(year, month, day);

  /// 将日期序列化为适合 JSON 的字符串。
  String toJson() => toString();

  @override
  int compareTo(LocalDate other) {
    final yearOrder = year.compareTo(other.year);
    if (yearOrder != 0) return yearOrder;
    final monthOrder = month.compareTo(other.month);
    if (monthOrder != 0) return monthOrder;
    return day.compareTo(other.day);
  }

  @override
  bool operator ==(Object other) {
    return other is LocalDate &&
        year == other.year &&
        month == other.month &&
        day == other.day;
  }

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() {
    return '${year.toString().padLeft(4, '0')}-'
        '${month.toString().padLeft(2, '0')}-'
        '${day.toString().padLeft(2, '0')}';
  }
}
