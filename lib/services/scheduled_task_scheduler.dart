import 'dart:async';

import '../models/scheduled_task.dart';
import '../providers/calendar_provider.dart';
import '../providers/feature_provider.dart';
import '../providers/model_config_provider.dart';
import '../providers/plugin_provider.dart';
import '../providers/scheduled_task_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/task_provider.dart';
import 'agent_cancellation.dart';
import 'plugin_lua_runtime_service.dart';
import 'scheduled_task_plugin_source.dart';

/// 前台定时任务调度器。
///
/// 不做后台保活。App 存活期间用单个 [Timer] 指向最早到期任务；
/// App 恢复前台时由调用方触发 [tickNow] 补跑错过的 occurrence。
/// 到期判定为 `now >= task.nextRunAt`；只有执行成功才推进到下一次，
/// 因此 23:00 未执行的任务在跨零点后仍会补跑一次。
class ScheduledTaskScheduler {
  ScheduledTaskScheduler({
    required this.tasks,
    required this.plugins,
    this.runtimePlugins,
    this.features,
    this.calendar,
    this.modelConfigs,
    this.settings,
    this.taskProvider,
    PluginLuaRuntimeService? runtime,
    DateTime Function()? clock,
    DateTime Function()? wallClock,
    this.defaultTimeout = const Duration(seconds: 60),
  }) : _runtime = runtime ?? PluginLuaRuntimeService(),
       _clock = clock ?? DateTime.now,
       _wallClock = wallClock ?? DateTime.now;

  final ScheduledTaskProvider tasks;
  final ScheduledTaskPluginSource plugins;

  /// 供 Lua 运行时读取插件配置/私有存储的完整 [PluginProvider]；
  /// 测试注入轻量 [ScheduledTaskPluginSource] 时可为 null。
  final PluginProvider? runtimePlugins;
  final FeatureProvider? features;
  final CalendarProvider? calendar;
  final ModelConfigProvider? modelConfigs;
  final SettingsProvider? settings;
  final TaskProvider? taskProvider;
  final PluginLuaRuntimeService _runtime;
  final DateTime Function() _clock;
  final DateTime Function() _wallClock;
  final Duration defaultTimeout;

  Timer? _timer;
  bool _attached = false;
  bool _ticking = false;
  final Set<String> _running = {};
  final Map<String, AgentCancellationSource> _sources = {};

  DateTime now() => _clock();

  /// 挂载调度器：同步插件 manifest 任务并开始排列定时器。
  Future<void> attach() async {
    if (_attached) return;
    _attached = true;
    await tasks.syncManifestTasks(plugins.plugins, now: now());
    tasks.onSnapshotPersisted = _rearm;
    plugins.addListener(_onPluginsChanged);
    _rearm();
  }

  /// 移除监听并取消运行中任务。
  void dispose() {
    if (!_attached) return;
    _attached = false;
    plugins.removeListener(_onPluginsChanged);
    if (identical(tasks.onSnapshotPersisted, _rearm)) {
      tasks.onSnapshotPersisted = null;
    }
    _timer?.cancel();
    _timer = null;
    for (final source in _sources.values) {
      source.cancel(
        const AgentCancellationReason(
          code: 'disposed',
          message: 'scheduler disposed',
        ),
      );
    }
    _sources.clear();
  }

  /// 立即检查一次到期任务；App 恢复前台时调用。
  Future<void> tickNow() async {
    if (!_attached || _ticking) return;
    _ticking = true;
    try {
      while (true) {
        final due = _nextDueTask();
        if (due == null) break;
        await _executeOne(due, now());
      }
    } finally {
      _ticking = false;
      _rearm();
    }
  }

  /// 手动立即执行一次任务，不消耗当前计划 occurrence。
  ///
  /// 手动跑成功后，任务仍会在原定时间正常触发。
  Future<bool> runNow(String taskId) async {
    if (!_attached) return false;
    final task = tasks.taskById(taskId);
    if (task == null || !task.enabled || _running.contains(task.id)) {
      return false;
    }
    final plugin = plugins.pluginById(task.pluginId);
    if (plugin == null || !plugin.enabled || plugin.hasError) {
      return false;
    }
    await _executeOne(task, now(), consumeOccurrence: false);
    return true;
  }

  ScheduledTask? _nextDueTask() {
    final timestamp = now();
    for (final task in tasks.tasks) {
      if (!task.enabled ||
          !task.isDueAt(timestamp) ||
          !task.canAttemptAt(timestamp) ||
          _running.contains(task.id)) {
        continue;
      }
      return task;
    }
    return null;
  }

  Future<void> _executeOne(
    ScheduledTask task,
    DateTime timestamp, {
    bool consumeOccurrence = true,
  }) async {
    final plugin = plugins.pluginById(task.pluginId);
    if (plugin == null || !plugin.enabled || plugin.hasError) {
      if (consumeOccurrence) {
        await tasks.recordSkipped(task.id, '插件不可用', now: timestamp);
      }
      return;
    }
    _running.add(task.id);
    final source = AgentCancellationSource();
    _sources[task.id] = source;
    try {
      final deadline = _wallClock().add(defaultTimeout);
      final context = <String, dynamic>{
        'taskId': task.id,
        'name': task.name,
        'pluginId': task.pluginId,
        'scheduledAt': task.nextRunAt?.toIso8601String(),
        'now': timestamp.toIso8601String(),
      };
      final result = await _runtime.executeScheduledTask(
        plugin: plugin,
        scriptKind: task.scriptKind,
        script: task.script,
        taskArguments: context,
        features: features,
        tasks: taskProvider,
        calendar: calendar,
        modelConfigs: modelConfigs,
        plugins: runtimePlugins,
        settings: settings,
        scheduledTasks: tasks,
        runScheduledTaskNow: runNow,
        cancellationToken: source.token,
        deadline: deadline,
      );
      if (result['ok'] == true) {
        await tasks.recordSuccess(
          task.id,
          now: now(),
          advanceOccurrence: consumeOccurrence,
        );
      } else {
        final error = result['error']?.toString() ?? '脚本执行失败';
        await tasks.recordFailure(task.id, error, now: now());
      }
    } on AgentCancellationException catch (error) {
      if (consumeOccurrence) {
        await tasks.recordCancelled(task.id, error.reason.message, now: now());
      } else {
        await tasks.recordFailure(task.id, error.reason.message, now: now());
      }
    } catch (error) {
      await tasks.recordFailure(
        task.id,
        error.toString().replaceFirst('Exception: ', ''),
        now: now(),
      );
    } finally {
      _running.remove(task.id);
      _sources.remove(task.id)?.dispose();
    }
  }

  void _onPluginsChanged() {
    unawaited(
      tasks
          .syncManifestTasks(plugins.plugins, now: now())
          .then((_) => _rearm()),
    );
  }

  void _rearm() {
    if (!_attached) return;
    _timer?.cancel();
    _timer = null;
    final timestamp = now();
    final earliest = _nextWakeAt(timestamp);
    if (earliest == null) return;
    final delay = earliest.difference(timestamp);
    _timer = Timer(delay.isNegative ? Duration.zero : delay, () {
      unawaited(tickNow());
    });
  }

  /// 计算下一次需要唤醒检查的时间。
  ///
  /// 到期但处于失败退避期的任务按 `lastAttemptAt + retryMinutes` 唤醒，
  /// 避免 `now >= nextRunAt` 成立时零延迟 Timer 空转。
  DateTime? _nextWakeAt(DateTime timestamp) {
    DateTime? earliest;
    for (final task in tasks.tasks) {
      if (!task.enabled) continue;
      final due = task.nextRunAt;
      if (due == null) continue;
      var wake = due;
      if (!due.isAfter(timestamp)) {
        final attempt = task.lastAttemptAt;
        if (attempt != null) {
          final retryAt = attempt.add(Duration(minutes: task.retryMinutes));
          if (retryAt.isAfter(wake)) wake = retryAt;
        }
      }
      if (earliest == null || wake.isBefore(earliest)) earliest = wake;
    }
    return earliest;
  }
}
