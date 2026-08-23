import 'local_date.dart';
import 'local_time.dart';

/// 定时任务重复规则。
enum ScheduledTaskRepeat {
  daily('daily', '每天'),
  weekly('weekly', '每周');

  const ScheduledTaskRepeat(this.value, this.label);

  final String value;
  final String label;

  static ScheduledTaskRepeat fromJson(Object? value) => switch (value) {
    'weekly' => weekly,
    _ => daily,
  };
}

/// 定时任务脚本来源。
enum ScheduledTaskScriptKind {
  /// 脚本保存在任务记录中，由用户在管理页创建。
  inline('inline'),

  /// 脚本是插件包内相对路径，随插件 manifest 声明。
  file('file');

  const ScheduledTaskScriptKind(this.value);

  final String value;

  static ScheduledTaskScriptKind fromJson(Object? value) =>
      value == 'file' ? file : inline;
}

/// 定时任务来源。
enum ScheduledTaskSource {
  manifest('manifest'),
  user('user');

  const ScheduledTaskSource(this.value);

  final String value;

  static ScheduledTaskSource fromJson(Object? value) =>
      value == 'manifest' ? manifest : user;
}

/// 最近一次执行状态。
enum ScheduledTaskRunStatus {
  success('success'),
  failed('failed'),
  skipped('skipped'),
  cancelled('cancelled');

  const ScheduledTaskRunStatus(this.value);

  final String value;

  static ScheduledTaskRunStatus? fromJson(Object? value) => switch (value) {
    'success' => success,
    'failed' => failed,
    'skipped' => skipped,
    'cancelled' => cancelled,
    _ => null,
  };
}

/// 单次执行历史记录。
final class ScheduledTaskRunRecord {
  /// 执行尝试时间。
  final DateTime at;

  /// 执行状态。
  final ScheduledTaskRunStatus status;

  /// 失败/跳过/取消原因。
  final String? error;

  const ScheduledTaskRunRecord({
    required this.at,
    required this.status,
    this.error,
  });

  factory ScheduledTaskRunRecord.fromJson(Map<String, dynamic> json) {
    final at = _dateTimeFromJson(json['at']);
    final status = ScheduledTaskRunStatus.fromJson(json['status']);
    if (at == null || status == null) {
      throw const FormatException('定时任务历史记录不完整');
    }
    return ScheduledTaskRunRecord(
      at: at,
      status: status,
      error: json['error'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'at': at.toIso8601String(),
    'status': status.value,
    if (error != null && error!.isNotEmpty) 'error': error,
  };
}

/// 本地定时任务。
///
/// 任务只在 App 前台或恢复时由 [ScheduledTaskScheduler] 检查执行：
/// 当 `now >= nextRunAt` 时执行一次，成功后以旧 occurrence 为基准推算
/// 下一次，因此当天错过、跨零点后仍会补跑一次。
final class ScheduledTask {
  static const daily = ScheduledTaskRepeat.daily;
  static const weekly = ScheduledTaskRepeat.weekly;
  static const scriptKindInline = ScheduledTaskScriptKind.inline;
  static const scriptKindFile = ScheduledTaskScriptKind.file;
  static const sourceManifest = ScheduledTaskSource.manifest;
  static const sourceUser = ScheduledTaskSource.user;

  static const defaultRetryMinutes = 30;
  static const defaultMaxConsecutiveFailures = 3;
  static const minRetryMinutes = 1;
  static const maxRetryMinutes = 24 * 60;
  static const maxNameChars = 100;
  static const maxInlineScriptChars = 100000;
  static const maxRunHistory = 20;

  /// 任务唯一标识符。
  final String id;

  /// 任务显示名称。
  final String name;

  /// 执行环境插件 ID。
  final String pluginId;

  /// 重复规则。
  final ScheduledTaskRepeat repeat;

  /// 每天触发时间（本地时间，`HH:mm`）。
  final LocalTime time;

  /// weekly 规则下触发星期（1=周一，7=周日）。
  final List<int> daysOfWeek;

  /// 脚本来源。
  final ScheduledTaskScriptKind scriptKind;

  /// 内联 Lua 代码或插件包内脚本相对路径。
  final String script;

  /// 任务来源：插件 manifest 或用户/Agent 创建。
  final ScheduledTaskSource source;

  /// 是否启用。
  final bool enabled;

  /// 下一次尚未执行成功的计划 occurrence。
  final DateTime? nextRunAt;

  /// 最近一次执行尝试时间。
  final DateTime? lastAttemptAt;

  /// 最近一次执行成功时间。
  final DateTime? lastRunAt;

  /// 最近一次执行状态。
  final ScheduledTaskRunStatus? lastStatus;

  /// 最近一次失败信息。
  final String? lastError;

  /// 最近执行历史（新的在前），最多保留 [maxRunHistory] 条。
  final List<ScheduledTaskRunRecord> runHistory;

  /// 连续失败次数。
  final int consecutiveFailures;

  /// 失败后的最小重试间隔（分钟）。
  final int retryMinutes;

  /// 连续失败自动停用阈值；0 表示不自动停用。
  final int maxConsecutiveFailures;

  /// 创建时间。
  final DateTime createdAt;

  /// 最后更新时间。
  final DateTime updatedAt;

  /// 创建任务并校验字段。
  ScheduledTask({
    required this.id,
    required this.name,
    required this.pluginId,
    required this.repeat,
    required this.time,
    this.daysOfWeek = const [],
    required this.scriptKind,
    required this.script,
    this.source = ScheduledTaskSource.user,
    this.enabled = true,
    this.nextRunAt,
    this.lastAttemptAt,
    this.lastRunAt,
    this.lastStatus,
    this.lastError,
    this.runHistory = const [],
    this.consecutiveFailures = 0,
    this.retryMinutes = defaultRetryMinutes,
    this.maxConsecutiveFailures = defaultMaxConsecutiveFailures,
    required this.createdAt,
    required this.updatedAt,
  }) {
    if (id.trim().isEmpty) throw ArgumentError('定时任务缺少 id');
    if (name.trim().isEmpty) throw ArgumentError('定时任务缺少 name');
    if (name.length > maxNameChars) {
      throw ArgumentError('定时任务名称不能超过 $maxNameChars 个字符');
    }
    if (pluginId.trim().isEmpty) throw ArgumentError('定时任务缺少 pluginId');
    final days = List<int>.unmodifiable(daysOfWeek);
    if (repeat == weekly && days.isEmpty) {
      throw ArgumentError('每周任务必须至少选择一天');
    }
    if (days.any((day) => day < 1 || day > 7)) {
      throw ArgumentError('星期必须在 1-7 之间');
    }
    if (script.trim().isEmpty) throw ArgumentError('定时任务缺少 script');
    if (scriptKind == ScheduledTaskScriptKind.inline &&
        script.length > maxInlineScriptChars) {
      throw ArgumentError('内联脚本不能超过 $maxInlineScriptChars 个字符');
    }
    if (retryMinutes < minRetryMinutes || retryMinutes > maxRetryMinutes) {
      throw ArgumentError(
        'retryMinutes 必须在 $minRetryMinutes-$maxRetryMinutes 之间',
      );
    }
    if (maxConsecutiveFailures < 0) {
      throw ArgumentError('maxConsecutiveFailures 不能小于 0');
    }
    if (consecutiveFailures < 0) {
      throw ArgumentError('consecutiveFailures 不能小于 0');
    }
    if (runHistory.length > maxRunHistory) {
      throw ArgumentError('runHistory 不能超过 $maxRunHistory 条');
    }
  }

  /// 从 JSON 创建任务。
  factory ScheduledTask.fromJson(Map<String, dynamic> json) {
    final timeValue = json['time'];
    if (timeValue is! String) {
      throw const FormatException('定时任务 time 必须是 HH:mm 字符串');
    }
    final repeat = ScheduledTaskRepeat.fromJson(json['repeat']);
    final days = _intList(json['daysOfWeek'] ?? json['days']);
    return ScheduledTask(
      id: json['id'] as String,
      name: json['name'] as String,
      pluginId: json['pluginId'] as String,
      repeat: repeat,
      time: LocalTime.parse(timeValue),
      daysOfWeek: days,
      scriptKind: ScheduledTaskScriptKind.fromJson(json['scriptKind']),
      script: json['script'] as String,
      source: ScheduledTaskSource.fromJson(json['source']),
      enabled: json['enabled'] as bool? ?? true,
      nextRunAt: _dateTimeFromJson(json['nextRunAt']),
      lastAttemptAt: _dateTimeFromJson(json['lastAttemptAt']),
      lastRunAt: _dateTimeFromJson(json['lastRunAt']),
      lastStatus: ScheduledTaskRunStatus.fromJson(json['lastStatus']),
      lastError: json['lastError'] as String?,
      runHistory: _runHistoryFromJson(json['runHistory']),
      consecutiveFailures: (json['consecutiveFailures'] as num?)?.toInt() ?? 0,
      retryMinutes:
          (json['retryMinutes'] as num?)?.toInt() ?? defaultRetryMinutes,
      maxConsecutiveFailures:
          (json['maxConsecutiveFailures'] as num?)?.toInt() ??
          defaultMaxConsecutiveFailures,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  /// 序列化为 JSON Map。
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'pluginId': pluginId,
    'repeat': repeat.value,
    'time': time.toJson(),
    if (repeat == weekly) 'daysOfWeek': daysOfWeek,
    'scriptKind': scriptKind.value,
    'script': script,
    if (source != sourceUser) 'source': source.value,
    if (!enabled) 'enabled': false,
    if (nextRunAt != null) 'nextRunAt': nextRunAt!.toIso8601String(),
    if (lastAttemptAt != null)
      'lastAttemptAt': lastAttemptAt!.toIso8601String(),
    if (lastRunAt != null) 'lastRunAt': lastRunAt!.toIso8601String(),
    if (lastStatus != null) 'lastStatus': lastStatus!.value,
    if (lastError != null && lastError!.isNotEmpty) 'lastError': lastError,
    if (runHistory.isNotEmpty)
      'runHistory': runHistory.map((item) => item.toJson()).toList(),
    if (consecutiveFailures != 0) 'consecutiveFailures': consecutiveFailures,
    if (retryMinutes != defaultRetryMinutes) 'retryMinutes': retryMinutes,
    if (maxConsecutiveFailures != defaultMaxConsecutiveFailures)
      'maxConsecutiveFailures': maxConsecutiveFailures,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  /// 在给定本地时间是否已到期。
  bool isDueAt(DateTime now) {
    final due = nextRunAt;
    return due != null && !now.isBefore(due);
  }

  /// 失败后是否已过重试退避期。
  bool canAttemptAt(DateTime now) {
    final attempt = lastAttemptAt;
    if (attempt == null) return true;
    return !now.isBefore(attempt.add(Duration(minutes: retryMinutes)));
  }

  /// 连续失败是否达到自动停用阈值。
  bool get reachedFailureLimit =>
      maxConsecutiveFailures > 0 &&
      consecutiveFailures >= maxConsecutiveFailures;

  /// 计算从 [now] 起（含）最近的计划 occurrence。
  ///
  /// 用于创建/更新时间后的首次排期；已经过了当天时间时排到下一周期，
  /// 避免刚创建就突然执行。
  DateTime? nextOccurrenceOnOrAfter(DateTime now) {
    switch (repeat) {
      case daily:
        final today = occurrenceOn(LocalDate.fromDateTime(now));
        return today.isBefore(now)
            ? occurrenceOn(LocalDate.fromDateTime(now).addDays(1))
            : today;
      case weekly:
        for (var offset = 0; offset < 7; offset++) {
          final date = LocalDate.fromDateTime(now).addDays(offset);
          final candidate = occurrenceOn(date);
          if (daysOfWeek.contains(candidate.weekday) &&
              !candidate.isBefore(now)) {
            return candidate;
          }
        }
        return null;
    }
  }

  /// 以旧 occurrence 为基准，计算它之后的下一次 occurrence。
  DateTime? nextOccurrenceAfter(DateTime occurrence) {
    final date = LocalDate.fromDateTime(occurrence);
    switch (repeat) {
      case daily:
        return occurrenceOn(date.addDays(1));
      case weekly:
        for (var offset = 1; offset <= 7; offset++) {
          final candidate = occurrenceOn(date.addDays(offset));
          if (daysOfWeek.contains(candidate.weekday)) return candidate;
        }
        return null;
    }
  }

  /// 按任务时间构建给定日期的 occurrence。
  DateTime occurrenceOn(LocalDate date) => time.on(date);

  /// 执行成功后推进 occurrence 并记录结果。
  ScheduledTask completedAt(DateTime now) {
    final due = nextRunAt;
    final next = due == null ? null : nextOccurrenceAfter(due);
    return _recordRun(now, ScheduledTaskRunStatus.success).copyWith(
      nextRunAt: next,
      lastAttemptAt: now,
      lastRunAt: now,
      lastStatus: ScheduledTaskRunStatus.success,
      lastError: null,
      consecutiveFailures: 0,
      updatedAt: now,
    );
  }

  /// 执行失败后保留 occurrence，记录退避与连续失败次数。
  ScheduledTask failedAt(DateTime now, String error) {
    final failures = consecutiveFailures + 1;
    final disable =
        maxConsecutiveFailures > 0 && failures >= maxConsecutiveFailures;
    return _recordRun(now, ScheduledTaskRunStatus.failed, error).copyWith(
      enabled: disable ? false : enabled,
      lastAttemptAt: now,
      lastStatus: ScheduledTaskRunStatus.failed,
      lastError: error,
      consecutiveFailures: failures,
      updatedAt: now,
    );
  }

  /// 跳过本次 occurrence（任务/插件不可用），推进到下一次。
  ScheduledTask skippedAt(DateTime now, String reason) {
    final due = nextRunAt;
    final next = due == null ? null : nextOccurrenceAfter(due);
    return _recordRun(now, ScheduledTaskRunStatus.skipped, reason).copyWith(
      nextRunAt: next,
      lastAttemptAt: now,
      lastStatus: ScheduledTaskRunStatus.skipped,
      lastError: reason,
      updatedAt: now,
    );
  }

  /// 取消后保留 occurrence。
  ScheduledTask cancelledAt(DateTime now, String reason) {
    return _recordRun(now, ScheduledTaskRunStatus.cancelled, reason).copyWith(
      lastAttemptAt: now,
      lastStatus: ScheduledTaskRunStatus.cancelled,
      lastError: reason,
      updatedAt: now,
    );
  }

  /// 记录一条执行历史（新记录在前），并限制在 [maxRunHistory] 条内。
  ScheduledTask _recordRun(
    DateTime now,
    ScheduledTaskRunStatus status, [
    String? error,
  ]) {
    final history = [
      ScheduledTaskRunRecord(at: now, status: status, error: error),
      ...runHistory,
    ];
    if (history.length > maxRunHistory) {
      history.removeRange(maxRunHistory, history.length);
    }
    return copyWith(runHistory: List.unmodifiable(history));
  }

  /// 创建修改后的任务副本。
  ScheduledTask copyWith({
    String? id,
    String? name,
    String? pluginId,
    ScheduledTaskRepeat? repeat,
    LocalTime? time,
    List<int>? daysOfWeek,
    ScheduledTaskScriptKind? scriptKind,
    String? script,
    ScheduledTaskSource? source,
    bool? enabled,
    Object? nextRunAt = _unset,
    Object? lastAttemptAt = _unset,
    Object? lastRunAt = _unset,
    Object? lastStatus = _unset,
    Object? lastError = _unset,
    List<ScheduledTaskRunRecord>? runHistory,
    int? consecutiveFailures,
    int? retryMinutes,
    int? maxConsecutiveFailures,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ScheduledTask(
      id: id ?? this.id,
      name: name ?? this.name,
      pluginId: pluginId ?? this.pluginId,
      repeat: repeat ?? this.repeat,
      time: time ?? this.time,
      daysOfWeek: daysOfWeek ?? this.daysOfWeek,
      scriptKind: scriptKind ?? this.scriptKind,
      script: script ?? this.script,
      source: source ?? this.source,
      enabled: enabled ?? this.enabled,
      nextRunAt: identical(nextRunAt, _unset)
          ? this.nextRunAt
          : nextRunAt as DateTime?,
      lastAttemptAt: identical(lastAttemptAt, _unset)
          ? this.lastAttemptAt
          : lastAttemptAt as DateTime?,
      lastRunAt: identical(lastRunAt, _unset)
          ? this.lastRunAt
          : lastRunAt as DateTime?,
      lastStatus: identical(lastStatus, _unset)
          ? this.lastStatus
          : lastStatus as ScheduledTaskRunStatus?,
      lastError: identical(lastError, _unset)
          ? this.lastError
          : lastError as String?,
      runHistory: runHistory ?? this.runHistory,
      consecutiveFailures: consecutiveFailures ?? this.consecutiveFailures,
      retryMinutes: retryMinutes ?? this.retryMinutes,
      maxConsecutiveFailures:
          maxConsecutiveFailures ?? this.maxConsecutiveFailures,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

const _unset = Object();

List<int> _intList(Object? raw) {
  if (raw is! List) return const [];
  return List.unmodifiable(raw.whereType<num>().map((item) => item.toInt()));
}

List<ScheduledTaskRunRecord> _runHistoryFromJson(Object? raw) {
  if (raw is! List) return const [];
  final records = <ScheduledTaskRunRecord>[];
  for (final item in raw.take(ScheduledTask.maxRunHistory)) {
    try {
      if (item is Map) {
        records.add(
          ScheduledTaskRunRecord.fromJson(Map<String, dynamic>.from(item)),
        );
      }
    } on FormatException {
      // 跳过损坏的单条历史，不阻断任务本身加载。
    }
  }
  return List.unmodifiable(records);
}

DateTime? _dateTimeFromJson(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value);
}
