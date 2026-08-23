import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/local_time.dart';
import 'package:lynai/models/plugin.dart';
import 'package:lynai/models/scheduled_task.dart';
import 'package:lynai/providers/scheduled_task_provider.dart';
import 'package:lynai/repositories/scheduled_task_repository.dart';
import 'package:lynai/services/scheduled_task_plugin_source.dart';
import 'package:lynai/services/scheduled_task_scheduler.dart';

final class _FakeRepository implements ScheduledTaskRepository {
  List<ScheduledTask> persisted = [];

  @override
  Future<ScheduledTaskLoadResult> load() async {
    return ScheduledTaskLoadResult(tasks: List.of(persisted));
  }

  @override
  Future<void> replace(Iterable<ScheduledTask> tasks) async {
    persisted = List.of(tasks);
  }
}

final class _FakePluginSource extends ChangeNotifier
    implements ScheduledTaskPluginSource {
  _FakePluginSource(this._plugins);

  List<InstalledPlugin> _plugins;

  @override
  List<InstalledPlugin> get plugins => List.unmodifiable(_plugins);

  @override
  InstalledPlugin? pluginById(String id) {
    for (final plugin in _plugins) {
      if (plugin.id == id) return plugin;
    }
    return null;
  }

  void replace(List<InstalledPlugin> plugins) {
    _plugins = List.of(plugins);
    notifyListeners();
  }
}

void main() {
  late Directory tempDir;
  late InstalledPlugin plugin;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lynai_scheduled_');
    final pluginDir = Directory('${tempDir.path}/plugin')..createSync();
    File('${pluginDir.path}/main.lua').writeAsStringSync('''
function plugin_helper()
  return 42
end
''');
    plugin = InstalledPlugin(
      manifest: PluginManifest(
        id: 'p1',
        name: '测试插件',
        version: '1.0.0',
        author: '',
        description: '',
        icon: '',
        entry: 'main.lua',
        permissions: const [],
        tools: const [],
        functions: const [],
        featurePages: const [],
        settings: const [],
      ),
      path: pluginDir.path,
      enabled: true,
      grantedPermissions: const [],
      enabledFeaturePages: const [],
    );
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  ScheduledTaskProvider providerWith(ScheduledTask task, {DateTime? now}) {
    final provider = ScheduledTaskProvider(repository: _FakeRepository());
    provider.replaceAll([task]);
    return provider;
  }

  ScheduledTask dueTask(DateTime nextRunAt) {
    final timestamp = nextRunAt.subtract(const Duration(days: 1));
    return ScheduledTask(
      id: 'st_1',
      name: '每日任务',
      pluginId: 'p1',
      repeat: ScheduledTaskRepeat.daily,
      time: LocalTime.fromDateTime(nextRunAt),
      scriptKind: ScheduledTaskScriptKind.inline,
      script: 'function run(ctx) return {ok=true, value=plugin_helper()} end',
      source: ScheduledTaskSource.user,
      nextRunAt: nextRunAt,
      createdAt: timestamp,
      updatedAt: timestamp,
    );
  }

  test(
    'missed 23:00 occurrence runs after midnight and advances to next day',
    () async {
      final occurrence = DateTime(2026, 2, 23, 23);
      final afterMidnight = DateTime(2026, 2, 24, 0, 30);
      var current = afterMidnight;
      final provider = providerWith(dueTask(occurrence));
      final plugins = _FakePluginSource([plugin]);
      final scheduler = ScheduledTaskScheduler(
        tasks: provider,
        plugins: plugins,
        clock: () => current,
      );
      await scheduler.attach();

      await scheduler.tickNow();
      final task = provider.taskById('st_1')!;
      expect(task.lastStatus, ScheduledTaskRunStatus.success);
      expect(task.nextRunAt, DateTime(2026, 2, 24, 23));
      scheduler.dispose();
    },
  );

  test(
    'script runs inside plugin environment and can call plugin globals',
    () async {
      final occurrence = DateTime(2026, 2, 23, 23);
      var current = occurrence;
      final provider = providerWith(dueTask(occurrence));
      final plugins = _FakePluginSource([plugin]);
      final scheduler = ScheduledTaskScheduler(
        tasks: provider,
        plugins: plugins,
        clock: () => current,
      );
      await scheduler.attach();
      await scheduler.tickNow();

      final task = provider.taskById('st_1')!;
      expect(task.lastStatus, ScheduledTaskRunStatus.success);
      expect(task.lastError, isNull);
      scheduler.dispose();
    },
  );

  test('failed script keeps occurrence and respects retry backoff', () async {
    final occurrence = DateTime(2026, 2, 23, 23);
    var current = occurrence;
    final provider = providerWith(
      dueTask(
        occurrence,
      ).copyWith(script: 'function run(ctx) error("boom") end'),
    );
    final plugins = _FakePluginSource([plugin]);
    final scheduler = ScheduledTaskScheduler(
      tasks: provider,
      plugins: plugins,
      clock: () => current,
    );
    await scheduler.attach();
    await scheduler.tickNow();
    var task = provider.taskById('st_1')!;
    expect(task.lastStatus, ScheduledTaskRunStatus.failed);
    expect(task.nextRunAt, occurrence);

    // 仍在退避期内，不重试。
    current = occurrence.add(const Duration(minutes: 1));
    await scheduler.tickNow();
    task = provider.taskById('st_1')!;
    expect(task.consecutiveFailures, 1);

    // 退避期过后重试。
    current = occurrence.add(
      Duration(minutes: ScheduledTask.defaultRetryMinutes + 1),
    );
    await scheduler.tickNow();
    task = provider.taskById('st_1')!;
    expect(task.consecutiveFailures, 2);
    scheduler.dispose();
  });

  test('disabled plugin skips the occurrence and advances', () async {
    final occurrence = DateTime(2026, 2, 23, 23);
    var current = occurrence;
    final provider = providerWith(dueTask(occurrence));
    final disabledPlugin = plugin.copyWith(enabled: false);
    final plugins = _FakePluginSource([disabledPlugin]);
    final scheduler = ScheduledTaskScheduler(
      tasks: provider,
      plugins: plugins,
      clock: () => current,
    );
    await scheduler.attach();
    await scheduler.tickNow();

    final task = provider.taskById('st_1')!;
    expect(task.lastStatus, ScheduledTaskRunStatus.skipped);
    expect(task.nextRunAt, DateTime(2026, 2, 24, 23));
    scheduler.dispose();
  });

  test('runNow does not consume the planned occurrence', () async {
    final occurrence = DateTime(2026, 2, 23, 23);
    var current = occurrence.subtract(const Duration(hours: 1));
    final provider = providerWith(dueTask(occurrence));
    final plugins = _FakePluginSource([plugin]);
    final scheduler = ScheduledTaskScheduler(
      tasks: provider,
      plugins: plugins,
      clock: () => current,
    );
    await scheduler.attach();
    final ran = await scheduler.runNow('st_1');
    expect(ran, isTrue);

    final task = provider.taskById('st_1')!;
    expect(task.lastStatus, ScheduledTaskRunStatus.success);
    expect(task.nextRunAt, occurrence);
    scheduler.dispose();
  });
}
