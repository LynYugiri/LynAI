import 'item_reminder.dart';
import 'local_date.dart';

const _unset = Object();

/// 纪念日日期规格，将一次性日期和每年重复日期分开表示。
sealed class AnniversarySpec {
  const AnniversarySpec();

  /// 从 JSON 创建纪念日日期规格。
  factory AnniversarySpec.fromJson(Map<String, dynamic> json) {
    return switch (json['type']) {
      'once' => OnceAnniversarySpec.fromJson(json),
      'yearly' => YearlyAnniversarySpec.fromJson(json),
      final value => throw FormatException('未知纪念日日期规格', value),
    };
  }

  /// 返回指定年份的发生日期。
  LocalDate? occurrenceInYear(int year);

  /// 将日期规格序列化为 JSON。
  Map<String, dynamic> toJson();
}

/// 具有完整年份且只发生一次的纪念日日期。
final class OnceAnniversarySpec extends AnniversarySpec {
  /// 唯一发生日期。
  final LocalDate date;

  /// 创建一次性纪念日日期规格。
  const OnceAnniversarySpec({required this.date});

  /// 从 JSON 创建一次性纪念日日期规格。
  factory OnceAnniversarySpec.fromJson(Map<String, dynamic> json) {
    return OnceAnniversarySpec(
      date: LocalDate.fromJson(json['date'] as String),
    );
  }

  @override
  LocalDate? occurrenceInYear(int year) => year == date.year ? date : null;

  @override
  Map<String, dynamic> toJson() => {'type': 'once', 'date': date.toJson()};

  /// 创建修改后的一次性日期规格副本。
  OnceAnniversarySpec copyWith({LocalDate? date}) {
    return OnceAnniversarySpec(date: date ?? this.date);
  }
}

/// 每年发生一次、可选来源年份的纪念日日期。
final class YearlyAnniversarySpec extends AnniversarySpec {
  /// 月，范围为 1 到 12。
  final int month;

  /// 日，范围由闰年可表达的对应月份决定。
  final int day;

  /// 可选来源年份；存在时也限定首次发生年份。
  final int? sourceYear;

  /// 创建按年重复的纪念日日期规格。
  factory YearlyAnniversarySpec({
    required int month,
    required int day,
    int? sourceYear,
  }) {
    LocalDate(sourceYear ?? 2000, month, day);
    return YearlyAnniversarySpec._(month, day, sourceYear);
  }

  const YearlyAnniversarySpec._(this.month, this.day, this.sourceYear);

  /// 从 JSON 创建按年重复的纪念日日期规格。
  factory YearlyAnniversarySpec.fromJson(Map<String, dynamic> json) {
    return YearlyAnniversarySpec(
      month: json['month'] as int,
      day: json['day'] as int,
      sourceYear: json['sourceYear'] as int?,
    );
  }

  @override
  LocalDate? occurrenceInYear(int year) {
    if (sourceYear != null && year < sourceYear!) return null;
    if (month == 2 && day == 29 && !_isLeapYear(year)) {
      return LocalDate(year, 2, 28);
    }
    return LocalDate(year, month, day);
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'yearly',
    'month': month,
    'day': day,
    'sourceYear': sourceYear,
  };

  /// 创建修改后的按年重复日期规格副本。
  YearlyAnniversarySpec copyWith({
    int? month,
    int? day,
    Object? sourceYear = _unset,
  }) {
    return YearlyAnniversarySpec(
      month: month ?? this.month,
      day: day ?? this.day,
      sourceYear: identical(sourceYear, _unset)
          ? this.sourceYear
          : sourceYear as int?,
    );
  }
}

/// 一次性或按年重复的纪念日。
final class Anniversary {
  /// 纪念日唯一标识符。
  final String id;

  /// 纪念日标题。
  final String title;

  /// 可选备注。
  final String? note;

  /// 纪念日日期规格。
  final AnniversarySpec spec;

  /// 是否显示基于来源年份计算的周年数。
  final bool showYearCount;

  /// 纪念日提醒。
  final List<ItemReminder> reminders;

  /// 创建时间。
  final DateTime createdAt;

  /// 最后更新时间。
  final DateTime updatedAt;

  /// 创建纪念日。
  Anniversary({
    required this.id,
    required this.title,
    this.note,
    required this.spec,
    this.showYearCount = false,
    List<ItemReminder> reminders = const [],
    required this.createdAt,
    required this.updatedAt,
  }) : reminders = validatedReminders(reminders) {
    if (this.reminders.any(
      (value) => value.anchor != ItemReminderAnchor.anniversaryDate,
    )) {
      throw ArgumentError('纪念日提醒只能使用纪念日日期锚点');
    }
    if (showYearCount &&
        spec is YearlyAnniversarySpec &&
        (spec as YearlyAnniversarySpec).sourceYear == null) {
      throw ArgumentError('显示周年数时必须提供来源年份');
    }
  }

  /// 从 JSON 创建纪念日。
  factory Anniversary.fromJson(Map<String, dynamic> json) {
    return Anniversary(
      id: json['id'] as String,
      title: json['title'] as String,
      note: json['note'] as String?,
      spec: AnniversarySpec.fromJson(json['spec'] as Map<String, dynamic>),
      showYearCount: json['showYearCount'] as bool? ?? false,
      reminders: (json['reminders'] as List<dynamic>? ?? const [])
          .map((value) => ItemReminder.fromJson(value as Map<String, dynamic>))
          .toList(),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  /// 返回指定年份的发生日期。
  LocalDate? occurrenceInYear(int year) => spec.occurrenceInYear(year);

  /// 返回指定发生年份的周年数；无法计算时返回空值。
  int? yearCountIn(int year) {
    if (!showYearCount) return null;
    final sourceYear = switch (spec) {
      OnceAnniversarySpec value => value.date.year,
      YearlyAnniversarySpec value => value.sourceYear,
    };
    if (sourceYear == null || year < sourceYear) return null;
    return year - sourceYear;
  }

  /// 将纪念日序列化为 JSON。
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'note': note,
    'spec': spec.toJson(),
    'showYearCount': showYearCount,
    'reminders': reminders.map((value) => value.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  /// 创建修改后的纪念日副本。
  Anniversary copyWith({
    String? id,
    String? title,
    Object? note = _unset,
    AnniversarySpec? spec,
    bool? showYearCount,
    List<ItemReminder>? reminders,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Anniversary(
      id: id ?? this.id,
      title: title ?? this.title,
      note: identical(note, _unset) ? this.note : note as String?,
      spec: spec ?? this.spec,
      showYearCount: showYearCount ?? this.showYearCount,
      reminders: reminders ?? this.reminders,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

bool _isLeapYear(int year) {
  return year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
}
