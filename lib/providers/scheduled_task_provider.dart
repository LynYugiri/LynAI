import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/local_time.dart';
import '../models/plugin.dart';
import '../models/scheduled_task.dart';
import '../repositories/scheduled_task_repository.dart';
import '../services/storage_v2_service.dart';
import '../utils/collection_utils.dart';
import 'serialized_save_queue.dart';

/// 定时任务内存状态的唯一所有者。
class ScheduledTaskProvider extends ChangeNotifier with SerializedSaveQueue {
  ScheduledTaskProvider({
    StorageV2Service? storageV2,
    ScheduledTaskRepository? repository,
  }) : _repository =
           repository ?? ScheduledTaskRepository(storageV2: storageV2);

  final _uuid = const Uuid();
  final ScheduledTaskRepository _repository;

  List<ScheduledTask> _tasks = const [];
  int _mutationGeneration = 0;

  /// 完整任务快照成功持久化后触发；调度器据此重新排列定时器。
  VoidCallback? onSnapshotPersisted;

  /// 全部任务，按下次执行时间升序排列。
  List<ScheduledTask> get tasks {
    final values = List<ScheduledTask>.of(_tasks);
    values.sort(_compareTasks);
    return List.unmodifiable(values);
  }

  ScheduledTask? taskById(String id) =>
      firstWhereOrNull(_tasks, (task) => task.id == id);

  List<ScheduledTask> tasksForPlugin(String pluginId) =>
      List.unmodifiable(_tasks.where((task) => task.pluginId == pluginId));

  Future<void> load({DateTime? now}) async {
    final generation = _mutationGeneration;
    await flushPendingSaves();
    final result = await _repository.load();
    if (generation != _mutationGeneration) return;
    final timestamp = now ?? DateTime.now();
    var repaired = false;
    _tasks = List.of(result.tasks);
    for (var i = 0; i < _tasks.length; i++) {
      final task = _tasks[i];
      if (!task.enabled || task.nextRunAt != null) continue;
      _tasks[i] = task.copyWith(
        nextRunAt: task.nextOccurrenceOnOrAfter(timestamp),
        updatedAt: timestamp,
      );
      repaired = true;
    }
    notifyListeners();
    if (repaired) {
      await _queueSave(
        () => _repository.replace(List<ScheduledTask>.of(_tasks)),
      );
    }
  }

  /// 用完整分区快照替换内存与持久化数据（备份/恢复等场景）。
  Future<void> replaceAll(List<ScheduledTask> tasks) async {
    _mutationGeneration++;
    _tasks = List.of(tasks);
    notifyListeners();
    final snapshot = List<ScheduledTask>.of(_tasks);
    await _queueSave(() => _repository.replace(snapshot));
  }

  /// 创建定时任务并返回任务 ID。
  Future<ScheduledTask> create({
    required String name,
    required String pluginId,
    ScheduledTaskRepeat repeat = ScheduledTaskRepeat.daily,
    required LocalTime time,
    List<int> daysOfWeek = const [],
    ScheduledTaskScriptKind scriptKind = ScheduledTaskScriptKind.inline,
    required String script,
    ScheduledTaskSource source = ScheduledTaskSource.user,
    bool enabled = true,
    int retryMinutes = ScheduledTask.defaultRetryMinutes,
    int maxConsecutiveFailures = ScheduledTask.defaultMaxConsecutiveFailures,
    DateTime? now,
  }) async {
    final timestamp = now ?? DateTime.now();
    final task = ScheduledTask(
      id: _uuid.v4(),
      name: name.trim(),
      pluginId: pluginId.trim(),
      repeat: repeat,
      time: time,
      daysOfWeek: daysOfWeek,
      scriptKind: scriptKind,
      script: script,
      source: source,
      enabled: enabled,
      retryMinutes: retryMinutes,
      maxConsecutiveFailures: maxConsecutiveFailures,
      createdAt: timestamp,
      updatedAt: timestamp,
    );
    final scheduled = task.copyWith(
      nextRunAt: task.nextOccurrenceOnOrAfter(timestamp),
    );
    _mutationGeneration++;
    _tasks = [..._tasks, scheduled];
    notifyListeners();
    final snapshot = List<ScheduledTask>.of(_tasks);
    await _queueSave(() => _repository.replace(snapshot));
    return scheduled;
  }

  /// 更新任务字段；计划字段变化时按当前时间重新计算下次执行。
  ///
  /// manifest 任务是插件包声明定义的，只允许改 [enabled]；
  /// 其他字段应通过插件更新和 [syncManifestTasks] 同步。
  Future<ScheduledTask> update({
    required String id,
    String? name,
    LocalTime? time,
    ScheduledTaskRepeat? repeat,
    List<int>? daysOfWeek,
    ScheduledTaskScriptKind? scriptKind,
    String? script,
    bool? enabled,
    int? retryMinutes,
    int? maxConsecutiveFailures,
    DateTime? now,
  }) async {
    final current = taskById(id);
    if (current == null) {
      throw ArgumentError.value(id, 'id', '定时任务不存在');
    }
    if (current.source == ScheduledTaskSource.manifest) {
      final hasDefinitionChanges =
          name != null ||
          time != null ||
          repeat != null ||
          daysOfWeek != null ||
          scriptKind != null ||
          script != null ||
          retryMinutes != null ||
          maxConsecutiveFailures != null;
      if (hasDefinitionChanges) {
        throw StateError('插件 manifest 定时任务只能修改启用状态');
      }
    }
    final timestamp = now ?? DateTime.now();
    var updated = current.copyWith(
      name: name?.trim(),
      time: time,
      repeat: repeat,
      daysOfWeek: daysOfWeek,
      scriptKind: scriptKind,
      script: script,
      enabled: enabled,
      retryMinutes: retryMinutes,
      maxConsecutiveFailures: maxConsecutiveFailures,
      updatedAt: timestamp,
    );
    final scheduleChanged =
        time != null || repeat != null || daysOfWeek != null;
    if (scheduleChanged || updated.nextRunAt == null) {
      updated = updated.copyWith(
        nextRunAt: updated.nextOccurrenceOnOrAfter(timestamp),
        consecutiveFailures: 0,
      );
    }
    _replaceInMemory(updated);
    notifyListeners();
    await _saveSnapshot();
    return updated;
  }

  /// 启用或停用任务；启用时补算缺失的 [ScheduledTask.nextRunAt]。
  Future<ScheduledTask?> setEnabled(String id, bool enabled) async {
    final current = taskById(id);
    if (current == null || current.enabled == enabled) return current;
    var updated = current.copyWith(enabled: enabled, updatedAt: DateTime.now());
    if (enabled && updated.nextRunAt == null) {
      updated = updated.copyWith(
        nextRunAt: updated.nextOccurrenceOnOrAfter(DateTime.now()),
      );
    }
    _replaceInMemory(updated);
    notifyListeners();
    await _saveSnapshot();
    return updated;
  }

  /// 删除任务；manifest 任务只能随插件卸载由 [syncManifestTasks] 删除。
  Future<bool> delete(String id) async {
    final current = taskById(id);
    if (current == null) return false;
    if (current.source == ScheduledTaskSource.manifest) {
      throw StateError('插件 manifest 定时任务不能单独删除');
    }
    final before = _tasks.length;
    _tasks = _tasks.where((task) => task.id != id).toList();
    if (_tasks.length == before) return false;
    _mutationGeneration++;
    notifyListeners();
    await _saveSnapshot();
    return true;
  }

  /// 立即执行一次（调度器负责真正执行；这里只返回任务）。
  ScheduledTask? markForImmediateRun(String id) => taskById(id);

  /// 记录一次成功执行。
  ///
  /// 定时触发时 [advanceOccurrence] 为 true，把 occurrence 推进到下一次；
  /// 手动 runNow 为 false，只记录结果、不消耗当天计划。
  Future<void> recordSuccess(
    String id, {
    DateTime? now,
    bool advanceOccurrence = true,
  }) async {
    final current = taskById(id);
    if (current == null) return;
    final timestamp = now ?? DateTime.now();
    final updated = advanceOccurrence
        ? current.completedAt(timestamp)
        : current.completedAt(timestamp).copyWith(nextRunAt: current.nextRunAt);
    _replaceInMemory(updated);
    notifyListeners();
    await _saveSnapshot();
  }

  /// 记录一次失败执行；occurrence 保持不变，按退避期重试。
  Future<void> recordFailure(String id, String error, {DateTime? now}) async {
    final current = taskById(id);
    if (current == null) return;
    _replaceInMemory(current.failedAt(now ?? DateTime.now(), error));
    notifyListeners();
    await _saveSnapshot();
  }

  /// 记录一次跳过（插件/脚本不可用），推进 occurrence。
  Future<void> recordSkipped(String id, String reason, {DateTime? now}) async {
    final current = taskById(id);
    if (current == null) return;
    _replaceInMemory(current.skippedAt(now ?? DateTime.now(), reason));
    notifyListeners();
    await _saveSnapshot();
  }

  /// 记录取消；occurrence 保持不变，下次 tick 会再次到期。
  Future<void> recordCancelled(
    String id,
    String reason, {
    DateTime? now,
  }) async {
    final current = taskById(id);
    if (current == null) return;
    _replaceInMemory(current.cancelledAt(now ?? DateTime.now(), reason));
    notifyListeners();
    await _saveSnapshot();
  }

  /// 按已安装插件清单同步 manifest 任务。
  ///
  /// 幂等：无变化时不触发保存。manifest 定义变化会更新字段并重新计算
  /// 下次执行时间；已删除或所属插件不可用的 manifest 任务会被停用。
  /// 用户手动停用的任务在同步中保持停用。
  Future<void> syncManifestTasks(
    Iterable<InstalledPlugin> plugins, {
    DateTime? now,
  }) async {
    final timestamp = now ?? DateTime.now();
    final desired = <String, ({String pluginId, ScheduledTask manifest})>{};
    for (final plugin in plugins) {
      final usable = plugin.enabled && !plugin.hasError;
      for (final definition in plugin.manifest.scheduledTasks) {
        final id = manifestTaskId(plugin.id, definition.name);
        final task = manifestTaskForDefinition(
          plugin: plugin,
          definition: definition,
          id: id,
          now: timestamp,
          enabled: usable,
        );
        if (task != null) desired[id] = (pluginId: plugin.id, manifest: task);
      }
    }

    var changed = false;
    final next = <ScheduledTask>[];
    for (final task in _tasks) {
      if (task.source != ScheduledTaskSource.manifest) {
        next.add(task);
        continue;
      }
      final match = desired[task.id];
      if (match == null) {
        if (task.enabled) {
          next.add(task.copyWith(enabled: false, updatedAt: timestamp));
          changed = true;
        } else {
          next.add(task);
        }
        continue;
      }
      var merged = match.manifest.copyWith(
        enabled: task.enabled && match.manifest.enabled,
        lastAttemptAt: task.lastAttemptAt,
        lastRunAt: task.lastRunAt,
        lastStatus: task.lastStatus,
        lastError: task.lastError,
        runHistory: task.runHistory,
        consecutiveFailures: task.consecutiveFailures,
        retryMinutes: task.retryMinutes,
        maxConsecutiveFailures: task.maxConsecutiveFailures,
        createdAt: task.createdAt,
      );
      final scheduleChanged =
          merged.time != task.time ||
          merged.repeat != task.repeat ||
          !_sameInts(merged.daysOfWeek, task.daysOfWeek) ||
          merged.script != task.script;
      if (scheduleChanged || merged.nextRunAt == null) {
        merged = merged.copyWith(
          nextRunAt: merged.nextOccurrenceOnOrAfter(timestamp),
          consecutiveFailures: 0,
        );
      }
      if (_sameTask(merged, task)) {
        next.add(task);
      } else {
        next.add(merged);
        changed = true;
      }
    }
    final existingIds = {for (final task in next) task.id};
    for (final entry in desired.entries) {
      if (existingIds.contains(entry.key)) continue;
      next.add(entry.value.manifest);
      changed = true;
    }
    // 已卸载插件的 manifest 任务直接移除。
    final desiredIds = desired.keys.toSet();
    if (next.any(
      (task) =>
          task.source == ScheduledTaskSource.manifest &&
          !desiredIds.contains(task.id),
    )) {
      next.removeWhere(
        (task) =>
            task.source == ScheduledTaskSource.manifest &&
            !desiredIds.contains(task.id),
      );
      changed = true;
    }
    if (!changed) return;
    _mutationGeneration++;
    _tasks = List.of(next);
    notifyListeners();
    await _saveSnapshot();
  }

  /// 生成稳定的 manifest 任务 ID。
  static String manifestTaskId(String pluginId, String name) {
    final digest = sha256
        .convert(utf8.encode('$pluginId/$name'))
        .toString()
        .substring(0, 16);
    return 'plugin:$pluginId:$digest';
  }

  ScheduledTask? manifestTaskForDefinition({
    required InstalledPlugin plugin,
    required PluginScheduledTaskDefinition definition,
    required String id,
    required DateTime now,
    required bool enabled,
  }) {
    final time = LocalTime.tryParse(definition.time);
    if (time == null) return null;
    final repeat =
        definition.repeat == PluginScheduledTaskDefinition.repeatWeekly
        ? ScheduledTaskRepeat.weekly
        : ScheduledTaskRepeat.daily;
    final task = ScheduledTask(
      id: id,
      name: definition.name,
      pluginId: plugin.id,
      repeat: repeat,
      time: time,
      daysOfWeek: definition.days,
      scriptKind: ScheduledTaskScriptKind.file,
      script: definition.script,
      source: ScheduledTaskSource.manifest,
      enabled: enabled,
      createdAt: now,
      updatedAt: now,
    );
    return task.copyWith(nextRunAt: task.nextOccurrenceOnOrAfter(now));
  }

  Future<void> _queueSave(Future<void> Function() save) {
    return enqueueSave(() async {
      await save();
      onSnapshotPersisted?.call();
    });
  }

  void _replaceInMemory(ScheduledTask updated) {
    _mutationGeneration++;
    _tasks = [
      for (final task in _tasks)
        if (task.id == updated.id) updated else task,
    ];
  }

  Future<void> _saveSnapshot() {
    final snapshot = List<ScheduledTask>.of(_tasks);
    return _queueSave(() => _repository.replace(snapshot));
  }
}

int _compareTasks(ScheduledTask a, ScheduledTask b) {
  final aNext = a.nextRunAt;
  final bNext = b.nextRunAt;
  if (aNext != null && bNext != null) {
    final order = aNext.compareTo(bNext);
    if (order != 0) return order;
  } else if (aNext != null) {
    return -1;
  } else if (bNext != null) {
    return 1;
  }
  return a.name.compareTo(b.name);
}

bool _sameInts(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _sameRunHistory(
  List<ScheduledTaskRunRecord> a,
  List<ScheduledTaskRunRecord> b,
) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].at != b[i].at ||
        a[i].status != b[i].status ||
        a[i].error != b[i].error) {
      return false;
    }
  }
  return true;
}

bool _sameTask(ScheduledTask a, ScheduledTask b) {
  return a.name == b.name &&
      a.pluginId == b.pluginId &&
      a.repeat == b.repeat &&
      a.time == b.time &&
      _sameInts(a.daysOfWeek, b.daysOfWeek) &&
      a.scriptKind == b.scriptKind &&
      a.script == b.script &&
      a.source == b.source &&
      a.enabled == b.enabled &&
      a.nextRunAt == b.nextRunAt &&
      a.lastAttemptAt == b.lastAttemptAt &&
      a.lastRunAt == b.lastRunAt &&
      a.lastStatus == b.lastStatus &&
      a.lastError == b.lastError &&
      _sameRunHistory(a.runHistory, b.runHistory) &&
      a.consecutiveFailures == b.consecutiveFailures &&
      a.retryMinutes == b.retryMinutes &&
      a.maxConsecutiveFailures == b.maxConsecutiveFailures;
}
