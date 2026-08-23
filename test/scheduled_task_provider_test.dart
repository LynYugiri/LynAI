import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/local_time.dart';
import 'package:lynai/models/plugin.dart';
import 'package:lynai/models/scheduled_task.dart';
import 'package:lynai/providers/scheduled_task_provider.dart';
import 'package:lynai/repositories/scheduled_task_repository.dart';

final class _FakeRepository implements ScheduledTaskRepository {
  _FakeRepository({this.blockFirstSave = false});

  final bool blockFirstSave;
  Completer<void>? firstSaveStarted;
  Completer<void>? allowFirstSave;
  Completer<void>? loadStarted;
  Completer<void>? allowLoad;
  Object? loadError;
  List<ScheduledTask> persisted = [];
  int loadCalls = 0;
  int maxConcurrentSaves = 0;
  int activeSaves = 0;

  @override
  Future<ScheduledTaskLoadResult> load() async {
    loadCalls++;
    if (loadError != null) throw loadError!;
    if (loadStarted != null) {
      loadStarted!.complete();
      await allowLoad!.future;
    }
    return ScheduledTaskLoadResult(tasks: List.of(persisted));
  }

  @override
  Future<void> replace(Iterable<ScheduledTask> tasks) async {
    activeSaves++;
    maxConcurrentSaves = activeSaves > maxConcurrentSaves
        ? activeSaves
        : maxConcurrentSaves;
    if (blockFirstSave && firstSaveStarted != null) {
      if (!firstSaveStarted!.isCompleted) firstSaveStarted!.complete();
      await allowFirstSave!.future;
    }
    persisted = List.of(tasks);
    activeSaves--;
  }
}

void main() {
  test('mutations notify before serialized snapshot save completes', () async {
    final repository = _FakeRepository(blockFirstSave: true);
    repository.firstSaveStarted = Completer<void>();
    repository.allowFirstSave = Completer<void>();
    final provider = ScheduledTaskProvider(repository: repository);
    var notifications = 0;
    provider.addListener(() => notifications++);

    final first = provider.create(
      name: 'first',
      pluginId: 'p1',
      time: LocalTime(21, 0),
      script: 'function run(ctx) end',
    );
    await repository.firstSaveStarted!.future;
    expect(provider.tasks, hasLength(1));
    expect(notifications, 1);

    final second = provider.create(
      name: 'second',
      pluginId: 'p1',
      time: LocalTime(22, 0),
      script: 'function run(ctx) end',
    );
    await Future<void>.delayed(Duration.zero);
    expect(provider.tasks, hasLength(2));
    expect(notifications, 2);

    repository.allowFirstSave!.complete();
    await Future.wait([first, second]);
    await provider.flushPendingSaves();
    expect(repository.persisted, hasLength(2));
  });

  test('record success advances occurrence', () async {
    final repository = _FakeRepository();
    final provider = ScheduledTaskProvider(repository: repository);
    final task = await provider.create(
      name: 'daily',
      pluginId: 'p1',
      time: LocalTime(23, 0),
      script: 'function run(ctx) end',
    );
    final due = task.nextRunAt!;
    await provider.recordSuccess(
      task.id,
      now: due.add(const Duration(minutes: 1)),
    );
    final updated = provider.taskById(task.id)!;
    expect(updated.nextRunAt, task.nextOccurrenceAfter(due));
    expect(updated.lastStatus, ScheduledTaskRunStatus.success);
  });

  test('manual success does not consume occurrence', () async {
    final repository = _FakeRepository();
    final provider = ScheduledTaskProvider(repository: repository);
    final task = await provider.create(
      name: 'daily',
      pluginId: 'p1',
      time: LocalTime(23, 0),
      script: 'function run(ctx) end',
    );
    await provider.recordSuccess(
      task.id,
      now: task.nextRunAt!.subtract(const Duration(hours: 1)),
      advanceOccurrence: false,
    );
    expect(provider.taskById(task.id)!.nextRunAt, task.nextRunAt);
  });

  test('record failure keeps occurrence and auto disables at limit', () async {
    final repository = _FakeRepository();
    final provider = ScheduledTaskProvider(repository: repository);
    final task = await provider.create(
      name: 'daily',
      pluginId: 'p1',
      time: LocalTime(23, 0),
      script: 'function run(ctx) end',
    );
    for (var i = 0; i < ScheduledTask.defaultMaxConsecutiveFailures; i++) {
      await provider.recordFailure(task.id, 'boom');
    }
    final updated = provider.taskById(task.id)!;
    expect(updated.enabled, isFalse);
    expect(updated.lastError, 'boom');
  });

  test(
    'sync manifest tasks is idempotent and disables on plugin uninstall',
    () async {
      final repository = _FakeRepository();
      final provider = ScheduledTaskProvider(repository: repository);
      final plugin = InstalledPlugin(
        manifest: PluginManifest(
          id: 'p1',
          name: '插件',
          version: '1.0.0',
          author: '',
          description: '',
          icon: '',
          entry: 'main.lua',
          permissions: const [],
          tools: const [],
          functions: const [],
          scheduledTasks: const [
            PluginScheduledTaskDefinition(
              name: '每日总结',
              time: '21:00',
              script: 'tasks/daily.lua',
            ),
          ],
          featurePages: const [],
          settings: const [],
        ),
        path: '/tmp/p1',
        enabled: true,
        grantedPermissions: const [],
        enabledFeaturePages: const [],
      );
      await provider.syncManifestTasks([
        plugin,
      ], now: DateTime(2026, 2, 23, 10));
      expect(provider.tasks, hasLength(1));
      final id = provider.tasks.single.id;
      final snapshots = repository.persisted.length;

      await provider.syncManifestTasks([
        plugin,
      ], now: DateTime(2026, 2, 23, 10));
      expect(provider.tasks.single.id, id);
      expect(repository.persisted.length, snapshots);

      await provider.syncManifestTasks([
        plugin.copyWith(enabled: false),
      ], now: DateTime(2026, 2, 23, 10));
      expect(provider.tasks, hasLength(1));
      expect(provider.tasks.single.enabled, isFalse);

      await provider.syncManifestTasks(
        const [],
        now: DateTime(2026, 2, 23, 10),
      );
      expect(provider.tasks, isEmpty);
    },
  );

  test('manifest tasks only allow enabled toggles', () async {
    final repository = _FakeRepository();
    final provider = ScheduledTaskProvider(repository: repository);
    final task = await provider.create(
      name: 'manifest task',
      pluginId: 'p1',
      time: LocalTime(21, 0),
      script: 'function run(ctx) end',
      source: ScheduledTaskSource.manifest,
    );
    await expectLater(
      provider.update(id: task.id, name: 'new name'),
      throwsStateError,
    );
    await expectLater(
      provider.update(id: task.id, time: LocalTime(22, 0)),
      throwsStateError,
    );
    await expectLater(provider.delete(task.id), throwsStateError);

    final toggled = await provider.setEnabled(task.id, false);
    expect(toggled?.enabled, isFalse);
    expect(provider.taskById(task.id)?.enabled, isFalse);
  });

  test('load repairs enabled tasks with missing nextRunAt', () async {
    final repository = _FakeRepository();
    final now = DateTime(2026, 2, 23, 10);
    final broken = ScheduledTask(
      id: 'broken',
      name: 'broken',
      pluginId: 'p1',
      repeat: ScheduledTaskRepeat.daily,
      time: LocalTime(21, 0),
      scriptKind: ScheduledTaskScriptKind.inline,
      script: 'function run(ctx) end',
      source: ScheduledTaskSource.user,
      enabled: true,
      createdAt: now.subtract(const Duration(days: 1)),
      updatedAt: now.subtract(const Duration(days: 1)),
    );
    final disabled = broken.copyWith(id: 'disabled', enabled: false);
    repository.persisted = [broken, disabled];

    final provider = ScheduledTaskProvider(repository: repository);
    await provider.load(now: now);

    expect(provider.taskById('broken')!.nextRunAt, DateTime(2026, 2, 23, 21));
    expect(provider.taskById('disabled')!.nextRunAt, isNull);
    expect(repository.persisted.any((task) => task.id == 'broken'), isTrue);
  });
}
