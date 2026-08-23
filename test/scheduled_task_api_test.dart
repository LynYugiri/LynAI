import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/local_time.dart';
import 'package:lynai/models/plugin.dart';
import 'package:lynai/models/scheduled_task.dart';
import 'package:lynai/providers/scheduled_task_provider.dart';
import 'package:lynai/repositories/scheduled_task_repository.dart';
import 'package:lynai/services/lynai_call_identity.dart';
import 'package:lynai/services/lynai_function_service.dart';
import 'package:lynai/services/lynai_permission_definitions.dart';
import 'package:lynai/services/plugin_lua_runtime_service.dart';

final class _FakeRepository implements ScheduledTaskRepository {
  @override
  Future<ScheduledTaskLoadResult> load() async {
    return ScheduledTaskLoadResult(tasks: const []);
  }

  @override
  Future<void> replace(Iterable<ScheduledTask> tasks) async {}
}

InstalledPlugin _plugin({
  List<String> granted = const [
    LynAIPermissions.scheduledTasksRead,
    LynAIPermissions.scheduledTasksWrite,
  ],
}) {
  return InstalledPlugin(
    manifest: PluginManifest(
      id: 'p1',
      name: '插件',
      version: '1.0.0',
      author: '',
      description: '',
      icon: '',
      entry: 'main.lua',
      permissions: granted,
      tools: const [],
      functions: const [],
      featurePages: const [],
      settings: const [],
    ),
    path: '/tmp/p1',
    enabled: true,
    grantedPermissions: granted,
    enabledFeaturePages: const [],
  );
}

LynAIFunctionContext _pluginContext({
  required ScheduledTaskProvider provider,
  InstalledPlugin? plugin,
}) {
  return LynAIFunctionContext(
    identity: LynAICallIdentity(
      type: plugin == null ? LynAICallerType.agent : LynAICallerType.plugin,
      pluginId: plugin?.id,
    ),
    plugin: plugin,
    scheduledTasks: provider,
    runScheduledTaskNow: (_) async => true,
  );
}

void main() {
  test('plugin can list and create scheduled tasks with permissions', () async {
    final provider = ScheduledTaskProvider(repository: _FakeRepository());
    final context = _pluginContext(provider: provider, plugin: _plugin());
    final service = LynAIFunctionService();

    final list = service.executeSync(
      const LynAIFunctionCall(name: 'scheduledTasks.list', arguments: {}),
      context,
    );
    expect(list['ok'], isTrue);
    expect(list['tasks'], isEmpty);

    final created = await service.execute(
      const LynAIFunctionCall(
        name: 'scheduledTasks.create',
        arguments: {
          'name': '每日总结',
          'time': '21:00',
          'script': 'function run(ctx) return {ok=true} end',
        },
      ),
      context,
    );
    expect(created['ok'], isTrue);
    final task = (created['task'] as Map)['pluginId'];
    expect(task, 'p1');
    expect(provider.tasks, hasLength(1));
  });

  test(
    'plugin cannot create scheduled tasks without write permission',
    () async {
      final provider = ScheduledTaskProvider(repository: _FakeRepository());
      final plugin = _plugin(
        granted: const [LynAIPermissions.scheduledTasksRead],
      );
      final service = LynAIFunctionService();
      final result = await service.execute(
        const LynAIFunctionCall(
          name: 'scheduledTasks.create',
          arguments: {
            'name': 'x',
            'time': '21:00',
            'script': 'function run(ctx) end',
          },
        ),
        _pluginContext(provider: provider, plugin: plugin),
      );
      expect(result['ok'], isFalse);
      expect(provider.tasks, isEmpty);
    },
  );

  test('agent delete is blocked while plugin can delete own task', () async {
    final provider = ScheduledTaskProvider(repository: _FakeRepository());
    final plugin = _plugin();
    final created = await provider.create(
      name: '每日总结',
      pluginId: plugin.id,
      time: LocalTime(21, 0),
      script: 'function run(ctx) end',
      source: ScheduledTaskSource.user,
    );

    final service = LynAIFunctionService();
    final agentResult = await service.execute(
      LynAIFunctionCall(
        name: 'scheduledTasks.delete',
        arguments: {'id': created.id},
      ),
      _pluginContext(provider: provider),
    );
    expect(agentResult['ok'], isFalse);

    final pluginResult = await service.execute(
      LynAIFunctionCall(
        name: 'scheduledTasks.delete',
        arguments: {'id': created.id},
      ),
      _pluginContext(provider: provider, plugin: plugin),
    );
    expect(pluginResult['ok'], isTrue);
    expect(provider.tasks, isEmpty);
  });

  test('plugin Lua can call lynai.scheduledTasks.create', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'lynai_scheduled_api_',
    );
    final pluginDir = Directory('${tempDir.path}/plugin')..createSync();
    File('${pluginDir.path}/main.lua').writeAsStringSync('''
function create_scheduled()
  return lynai.scheduledTasks.create({
    name = "每日总结",
    time = "21:00",
    script = "function run(ctx) return {ok=true} end"
  })
end
''');
    addTearDown(() => tempDir.delete(recursive: true));
    final plugin = InstalledPlugin(
      manifest: PluginManifest(
        id: 'p1',
        name: '插件',
        version: '1.0.0',
        author: '',
        description: '',
        icon: '',
        entry: 'main.lua',
        permissions: const [LynAIPermissions.scheduledTasksWrite],
        tools: const [],
        functions: const [
          PluginFunctionDefinition(
            name: 'createScheduled',
            title: '创建定时任务',
            handler: 'create_scheduled',
          ),
        ],
        featurePages: const [],
        settings: const [],
      ),
      path: pluginDir.path,
      enabled: true,
      grantedPermissions: const [LynAIPermissions.scheduledTasksWrite],
      enabledFeaturePages: const [],
      enabledFunctions: const ['createScheduled'],
    );
    final provider = ScheduledTaskProvider(repository: _FakeRepository());
    final result = await PluginLuaRuntimeService().executeFunction(
      plugin: plugin,
      function: plugin.manifest.functions.single,
      arguments: const {},
      scheduledTasks: provider,
      runScheduledTaskNow: (_) async => true,
    );
    expect(result['ok'], isTrue);
    expect(provider.tasks, hasLength(1));
    expect(provider.tasks.single.name, '每日总结');
  });
}
