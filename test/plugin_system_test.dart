import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:lynai/models/conversation.dart';
import 'package:lynai/models/model_config.dart';
import 'package:lynai/models/plugin.dart';
import 'package:lynai/models/plugin_config_schema.dart';
import 'package:lynai/models/recycle_bin_item.dart';
import 'package:lynai/providers/feature_provider.dart';
import 'package:lynai/providers/plugin_provider.dart';
import 'package:lynai/repositories/plugin_repository.dart';
import 'package:lynai/repositories/recycle_bin_repository.dart';
import 'package:lynai/services/agent_lua_script_service.dart';
import 'package:lynai/services/lynai_call_identity.dart';
import 'package:lynai/services/lynai_function_service.dart';
import 'package:lynai/services/plugin_lua_runtime_service.dart';
import 'package:lynai/services/tool_call_service.dart';
import 'package:lynai/utils/plugin_path_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_path_provider.dart';
import 'support/memory_repositories.dart';

void main() {
  Directory? pathProviderRoot;

  setUp(() async {
    pathProviderRoot = await installFakePathProvider(
      'lynai_plugin_path_provider_test_',
    );
  });

  tearDown(() async {
    final root = pathProviderRoot;
    pathProviderRoot = null;
    await deleteFakePathProviderRoot(root);
  });

  test('built-in mobile agent skills plugin is declared', () {
    expect(PluginRepository.builtInPluginIds, contains('mobile-agent-skills'));
    expect(
      PluginRepository.builtInPluginFiles['mobile-agent-skills'],
      containsAll([
        'plugin.json',
        'main.lua',
        'defaults/skills/android_accessibility.md',
        'defaults/skills/messaging.md',
        'defaults/skills/qq.md',
        'defaults/skills/wechat.md',
        'defaults/skills/system_settings.md',
        'defaults/skills/browser_search.md',
        'defaults/skills/camera_ocr_scan.md',
        'defaults/skills/contacts_phone.md',
        'defaults/skills/clock_alarm.md',
        'defaults/skills/map_navigation.md',
        'defaults/skills/media_share.md',
        'defaults/skills/study_problem_solving.md',
        'defaults/skills/study_research_qa.md',
        'defaults/skills/note_taking.md',
        'defaults/skills/note_capture_to_kb.md',
      ]),
    );
  });

  test(
    'mobile-agent-skills manifest lists 15 skills with matching files',
    () async {
      const pluginId = 'mobile-agent-skills';
      const manifestPath = 'assets/plugins/$pluginId/plugin.json';
      final manifestRaw = await File(manifestPath).readAsString();
      final manifest = jsonDecode(manifestRaw) as Map<String, dynamic>;
      final skills = (manifest['skills'] as List).cast<Map<String, dynamic>>();
      final editables = (manifest['editableFiles'] as List)
          .cast<Map<String, dynamic>>();

      expect(skills.length, 15, reason: 'mobile-agent-skills 应有 15 个 skill');
      expect(editables.length, 15, reason: 'editableFiles 应与 skills 数量一致');

      final pathPattern = RegExp(r'^skills/([A-Za-z0-9_-]{1,64})\.md$');
      final savedFiles = PluginRepository.builtInPluginFiles[pluginId]!
          .where((f) => f.startsWith('defaults/skills/'))
          .toSet();
      final seenNames = <String>{};
      for (final skill in skills) {
        final name = skill['name'] as String;
        expect(seenNames, isNot(contains(name)), reason: 'skill 名重复: $name');
        seenNames.add(name);
        final defaultRel = 'defaults/skills/$name.md';
        expect(
          savedFiles,
          contains(defaultRel),
          reason: 'builtInPluginFiles 缺少 $defaultRel',
        );
        final assetPath = 'assets/plugins/$pluginId/$defaultRel';
        final assetFile = File(assetPath);
        expect(
          await assetFile.exists(),
          isTrue,
          reason: 'skill 资源文件不存在: $assetPath',
        );
        final content = await assetFile.readAsString();
        expect(content.trim(), isNotEmpty, reason: 'skill 文件为空: $name');
        expect(
          content,
          anyOf(
            contains('## 返回约定'),
            contains('## 失败处理'),
            contains('## 推荐返回结构'),
            contains('## 禁止行为'),
          ),
          reason: 'skill 文件缺少返回约定或失败处理: $name',
        );

        final editable = editables.firstWhere(
          (e) => e['path'] == 'skills/$name.md',
          orElse: () => fail('editableFiles 缺少 skills/$name.md'),
        );
        expect(editable['defaultPath'], defaultRel);
        expect(editable['type'], 'markdown');
        expect(pathPattern.hasMatch(editable['path'] as String), isTrue);
      }

      expect(
        manifest['description'] as String,
        isNot(contains('QQ 自动化工作流说明')),
        reason: 'manifest description 已更新不应再沿用旧文案',
      );
    },
  );

  test('user imported skill-only plugins are not auto-enabled', () async {
    final source = await Directory.systemTemp.createTemp(
      'lynai_skill_only_plugin_',
    );
    final installedRoot = await Directory.systemTemp.createTemp(
      'lynai_skill_only_installed_',
    );
    try {
      await Directory('${source.path}/skills').create(recursive: true);
      await File('${source.path}/main.lua').writeAsString('-- no handlers');
      await File('${source.path}/skills/sample.md').writeAsString('# Sample');
      await File('${source.path}/plugin.json').writeAsString(
        jsonEncode({
          'id': 'user-skill-only',
          'name': 'User Skill Only',
          'entry': 'main.lua',
          'permissions': const [],
          'skills': [
            {'name': 'sample', 'title': 'Sample'},
          ],
          'lynai': {'autoEnable': true},
        }),
      );

      final plugins = PluginProvider(
        repository: PluginRepository(rootOverride: installedRoot),
      );
      await plugins.importDirectory(source.path);

      expect(plugins.pluginById('user-skill-only')?.enabled, isFalse);
    } finally {
      if (await source.exists()) await source.delete(recursive: true);
      if (await installedRoot.exists()) {
        await installedRoot.delete(recursive: true);
      }
    }
  });

  test('RecycleBinRepository serializes concurrent writes', () async {
    SharedPreferences.setMockInitialValues({});
    final repository = RecycleBinRepository();

    await Future.wait([
      repository.add(
        RecycleBinItem(
          owner: RecycleBinOwners.core,
          category: RecycleBinCategories.todos,
          type: RecycleBinItemTypes.todoList,
          title: 'A',
        ),
      ),
      repository.add(
        RecycleBinItem(
          owner: RecycleBinOwners.core,
          category: RecycleBinCategories.schedules,
          type: RecycleBinItemTypes.schedule,
          title: 'B',
        ),
      ),
    ]);

    final items = await repository.load();
    expect(items.map((item) => item.title), containsAll(['A', 'B']));
  });

  test(
    'Plugin recycle bin file API stores and restores editable files',
    () async {
      SharedPreferences.setMockInitialValues({});
      final source = await Directory.systemTemp.createTemp(
        'lynai_recycle_src_',
      );
      final installedRoot = await Directory.systemTemp.createTemp(
        'lynai_recycle_installed_',
      );
      try {
        await Directory('${source.path}/prompts').create(recursive: true);
        await File(
          '${source.path}/prompts/system.md',
        ).writeAsString('original');
        await File('${source.path}/main.lua').writeAsString('return {}');
        await File('${source.path}/plugin.json').writeAsString(
          jsonEncode({
            'id': 'recycle_plugin',
            'name': 'Recycle Plugin',
            'entry': 'main.lua',
            'permissions': [
              'recycleBin:write',
              'recycleBin:read',
              'recycleBin:restore',
            ],
            'editableFiles': [
              {'path': 'prompts/system.md'},
            ],
          }),
        );

        final plugins = PluginProvider(
          repository: PluginRepository(rootOverride: installedRoot),
        );
        await plugins.importDirectory(source.path);
        await plugins.setEnabled('recycle_plugin', true);
        await plugins.setGrantedPermissions('recycle_plugin', [
          'recycleBin:write',
          'recycleBin:read',
          'recycleBin:restore',
        ]);
        final plugin = plugins.pluginById('recycle_plugin')!;
        final service = LynAIFunctionService();
        final context = LynAIFunctionContext(
          identity: const LynAICallIdentity(
            type: LynAICallerType.plugin,
            pluginId: 'recycle_plugin',
          ),
          plugins: plugins,
          plugin: plugin,
        );

        final put = await service.execute(
          const LynAIFunctionCall(
            name: 'recycleBin.putFile',
            arguments: {'path': 'prompts/system.md', 'deleteOriginal': true},
          ),
          context,
        );
        expect(put['ok'], isTrue);
        expect(File('${plugin.path}/prompts/system.md').existsSync(), isFalse);

        final list = await service.execute(
          const LynAIFunctionCall(name: 'recycleBin.list', arguments: {}),
          context,
        );
        final item = (list['items'] as List).single as Map<String, dynamic>;

        final restore = await service.execute(
          LynAIFunctionCall(
            name: 'recycleBin.restore',
            arguments: {'id': item['id']},
          ),
          context,
        );
        expect(restore['ok'], isTrue);
        expect(
          await plugins.readFile('recycle_plugin', 'prompts/system.md'),
          'original',
        );
        expect((await RecycleBinRepository().load()), isEmpty);
      } finally {
        if (await source.exists()) {
          await source.delete(recursive: true);
        }
        if (await installedRoot.exists()) {
          await installedRoot.delete(recursive: true);
        }
      }
    },
  );

  test('PluginManifest rejects feature page ids that break route keys', () {
    final manifest = PluginManifest.fromJson({
      'id': 'demo_plugin',
      'name': 'Demo Plugin',
      'entry': 'main.lua',
      'ui': {
        'featurePages': [
          {'id': 'bad:page', 'title': 'Bad', 'entry': 'web/index.html'},
        ],
      },
    });

    expect(manifest.validate(), contains('功能页 id'));
  });

  test('safePluginFilePath keeps plugin file references inside root', () {
    final root = '/tmp/lynai_plugin';

    expect(safePluginFilePath(root, 'web/index.html'), '$root/web/index.html');
    expect(safePluginFilePath(root, '../secret.txt'), isNull);
    expect(safePluginFilePath(root, '/tmp/secret.txt'), isNull);
    expect(safePluginFilePath(root, 'https://example.com/icon.png'), isNull);
  });

  test('PluginManifest parses config and editable file declarations', () {
    final manifest = PluginManifest.fromJson({
      'id': 'config_plugin',
      'name': 'Config Plugin',
      'entry': 'main.lua',
      'config': {'path': 'config.json', 'schema': 'config.schema.json'},
      'editableFiles': [
        {'path': 'prompts/system.md', 'title': 'Prompt', 'type': 'markdown'},
      ],
    });

    expect(manifest.validate(), isNull);
    expect(manifest.config.path, 'config.json');
    expect(manifest.config.schema, 'config.schema.json');
    expect(manifest.editableFiles.single.path, 'prompts/system.md');
  });

  test(
    'PluginManifest parses skills and allows cross-kind duplicate names',
    () {
      final manifest = PluginManifest.fromJson({
        'id': 'skill_plugin',
        'name': 'Skill Plugin',
        'entry': 'main.lua',
        'tools': [
          {'name': 'assist', 'description': 'tool', 'handler': 'assist'},
        ],
        'functions': [
          {'name': 'assist', 'title': 'Assist', 'handler': 'assist_func'},
        ],
        'skills': [
          {
            'name': 'assist',
            'title': 'Assist Skill',
            'description': 'Use when assistance is needed.',
            'whenToUse': 'assistant workflows',
            'tags': ['demo'],
          },
        ],
      });

      expect(manifest.validate(), isNull);
      expect(manifest.skills.single.name, 'assist');
      expect(manifest.skills.single.whenToUse, 'assistant workflows');
      expect(manifest.skills.single.editable, isTrue);
      final plugin = InstalledPlugin.fromJson({
        'manifest': manifest.toJson(),
        'path': '/tmp/skill_plugin',
        'enabled': true,
        'grantedPermissions': const [],
        'enabledFeaturePages': const [],
      });
      expect(plugin.enabledSkills, contains('assist'));
    },
  );

  test('PluginManifest parses read-only skill declarations', () {
    final manifest = PluginManifest.fromJson({
      'id': 'readonly_skill_plugin',
      'name': 'Read-only Skill Plugin',
      'entry': 'main.lua',
      'skills': [
        {'name': 'policy', 'title': 'Policy', 'editable': false},
      ],
    });

    expect(manifest.validate(), isNull);
    expect(manifest.skills.single.editable, isFalse);
    expect(manifest.toJson()['skills'], [
      {'name': 'policy', 'title': 'Policy', 'editable': false},
    ]);
  });

  test('PluginManifest rejects unsafe config paths', () {
    final manifest = PluginManifest.fromJson({
      'id': 'bad_config_plugin',
      'name': 'Bad Config Plugin',
      'entry': 'main.lua',
      'config': {'path': '../config.json'},
    });

    expect(manifest.validate(), contains('config.path'));
  });

  test(
    'PluginConfigSchema applies defaults and validates model selections',
    () {
      final schema = PluginConfigSchema.fromJson({
        'fields': [
          {'key': 'enabled', 'type': 'boolean', 'default': true},
          {'key': 'maxResults', 'type': 'integer', 'min': 1, 'max': 10},
          {
            'key': 'mode',
            'type': 'select',
            'options': [
              {'value': 'fast', 'label': 'Fast'},
              {'value': 'safe', 'label': 'Safe'},
            ],
          },
          {
            'key': 'chatModel',
            'type': 'model',
            'category': 'chat',
            'store': 'selection',
            'required': true,
          },
        ],
      });
      final model = ModelConfig(
        id: 'provider-1',
        name: 'Provider',
        endpoint: 'https://example.com',
        apiKey: 'key',
        modelName: 'gpt-a',
        apiType: 'openai',
        priority: 0,
        models: [
          ModelEntry(name: 'gpt-a', enabled: true),
          ModelEntry(name: 'gpt-b', enabled: true),
        ],
      );

      expect(schema.applyDefaults({})['enabled'], isTrue);
      final errors = schema.validateValues(
        {
          'enabled': true,
          'maxResults': 5,
          'mode': 'fast',
          'chatModel': {
            'modelId': 'provider-1',
            'modelName': 'gpt-b',
            'category': 'chat',
          },
        },
        models: [model],
      );
      expect(errors, isEmpty);

      final badErrors = schema.validateValues(
        {
          'maxResults': 11,
          'mode': 'missing',
          'chatModel': {'modelId': 'provider-1', 'modelName': 'missing'},
        },
        models: [model],
      );
      expect(badErrors.length, greaterThanOrEqualTo(3));
    },
  );

  test(
    'PluginRepository only writes config and declared editable files',
    () async {
      final root = await Directory.systemTemp.createTemp('lynai_repo_plugin_');
      try {
        await File('${root.path}/config.json').writeAsString('{}');
        await File('${root.path}/readonly.txt').writeAsString('read only');
        await Directory('${root.path}/prompts').create();
        await File('${root.path}/prompts/system.md').writeAsString('old');
        final manifest = PluginManifest.fromJson({
          'id': 'repo_plugin',
          'name': 'Repo Plugin',
          'entry': 'main.lua',
          'editableFiles': [
            {'path': 'prompts/system.md'},
          ],
        });
        final plugin = InstalledPlugin(
          manifest: manifest,
          path: root.path,
          enabled: true,
          grantedPermissions: const [],
          enabledFeaturePages: const [],
        );
        final repository = PluginRepository();

        expect(repository.isEditablePluginFile(plugin, 'config.json'), isFalse);
        expect(
          repository.isEditablePluginFile(plugin, 'prompts/system.md'),
          isTrue,
        );
        expect(
          repository.isEditablePluginFile(plugin, 'readonly.txt'),
          isFalse,
        );
        await repository.writePluginJsonFile(plugin, 'config.json', {
          'ok': true,
        });
        expect(
          () => repository.writePluginTextFile(
            plugin,
            'config.json',
            '{"ok":false}',
          ),
          throwsException,
        );
        await repository.writePluginTextFile(
          plugin,
          'prompts/system.md',
          'new',
        );
        expect(
          () => repository.writePluginTextFile(plugin, 'readonly.txt', 'bad'),
          throwsException,
        );
      } finally {
        await root.delete(recursive: true);
      }
    },
  );

  test(
    'PluginRepository exposes defaults as root overlay without allowing entry edits',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'lynai_overlay_plugin_',
      );
      try {
        await Directory('${root.path}/defaults').create();
        await File('${root.path}/plugin.json').writeAsString('{}');
        await File(
          '${root.path}/defaults/main.lua',
        ).writeAsString('default main');
        await File(
          '${root.path}/defaults/status.html',
        ).writeAsString('default html');
        await File(
          '${root.path}/defaults/status.css',
        ).writeAsString('default css');
        final manifest = PluginManifest.fromJson({
          'id': 'overlay_plugin',
          'name': 'Overlay Plugin',
          'entry': 'main.lua',
          'editableFiles': [
            {'path': 'status.html', 'defaultPath': 'defaults/status.html'},
            {'path': 'status.css', 'defaultPath': 'defaults/status.css'},
            {'path': 'main.lua', 'defaultPath': 'defaults/main.lua'},
          ],
        });
        final plugin = InstalledPlugin(
          manifest: manifest,
          path: root.path,
          enabled: true,
          grantedPermissions: const ['files:write'],
          enabledFeaturePages: const [],
        );
        final repository = PluginRepository();

        final files = await repository.listPluginFiles(plugin);
        expect(files.map((file) => file.path), contains('status.html'));
        expect(files.map((file) => file.path), contains('status.css'));
        expect(files.map((file) => file.path), isNot(contains('main.lua')));
        expect(files.map((file) => file.path), isNot(contains('plugin.json')));
        expect(
          files.singleWhere((file) => file.path == 'status.html').isDefault,
          isTrue,
        );

        expect(
          await repository.readPluginOverlayTextFile(plugin, 'status.html'),
          'default html',
        );
        await repository.writePluginTextFile(
          plugin,
          'status.html',
          'custom html',
        );
        expect(
          await File('${root.path}/status.html').readAsString(),
          'custom html',
        );
        expect(
          await repository.readPluginOverlayTextFile(plugin, 'status.html'),
          'custom html',
        );
        expect(
          () => repository.writePluginTextFile(plugin, 'main.lua', 'bad'),
          throwsException,
        );
      } finally {
        await root.delete(recursive: true);
      }
    },
  );

  test(
    'PluginProvider reports invalid config and schema instead of hiding it',
    () async {
      final source = await Directory.systemTemp.createTemp(
        'lynai_bad_config_src_',
      );
      final installedRoot = await Directory.systemTemp.createTemp(
        'lynai_bad_config_installed_',
      );
      try {
        await File('${source.path}/plugin.json').writeAsString(
          '{"id":"bad_config_runtime","name":"Bad Config Runtime","entry":"main.lua"}',
        );
        await File(
          '${source.path}/main.lua',
        ).writeAsString('function run(args) return { ok = true } end');
        await File('${source.path}/config.json').writeAsString('{bad json');
        await File('${source.path}/config.schema.json').writeAsString('''
{
  "fields": [
    { "type": "string" }
  ]
}
''');
        final provider = PluginProvider(
          repository: PluginRepository(rootOverride: installedRoot),
        );
        await provider.importDirectory(source.path);
        final pluginId = provider.plugins.single.id;

        await expectLater(provider.loadConfig(pluginId), throwsException);

        await File(
          '${installedRoot.path}/installed/$pluginId/config.json',
        ).writeAsString('{}');
        await expectLater(provider.loadConfigSchema(pluginId), throwsException);
      } finally {
        await source.delete(recursive: true);
        await installedRoot.delete(recursive: true);
      }
    },
  );

  test('PluginRepository file listing skips symlinks', () async {
    final root = await Directory.systemTemp.createTemp('lynai_symlink_plugin_');
    try {
      await File('${root.path}/notes.txt').writeAsString('ok');
      await Link(
        '${root.path}/linked_notes.txt',
      ).create('${root.path}/notes.txt');
      final manifest = PluginManifest.fromJson({
        'id': 'symlink_plugin',
        'name': 'Symlink Plugin',
        'entry': 'main.lua',
      });
      final plugin = InstalledPlugin(
        manifest: manifest,
        path: root.path,
        enabled: true,
        grantedPermissions: const [],
        enabledFeaturePages: const [],
        enabledTools: const ['calc_plugin_add_numbers'],
      );

      final files = await PluginRepository().listPluginFiles(plugin);
      expect(files.map((file) => file.path), contains('notes.txt'));
      expect(
        files.map((file) => file.path),
        isNot(contains('linked_notes.txt')),
      );
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('Lua plugin tools are exposed and executable', () async {
    final root = await Directory.systemTemp.createTemp('lynai_lua_plugin_');
    try {
      await File('${root.path}/main.lua').writeAsString(r'''
function add_numbers(args)
  return { ok = true, sum = args.a + args.b }
end
''');
      final manifest = PluginManifest.fromJson({
        'id': 'calc_plugin',
        'name': 'Calc Plugin',
        'entry': 'main.lua',
        'tools': [
          {
            'name': 'calc_plugin_add_numbers',
            'description': 'Add two numbers',
            'handler': 'add_numbers',
            'parameters': {
              'type': 'object',
              'properties': {
                'a': {'type': 'number'},
                'b': {'type': 'number'},
              },
            },
          },
        ],
      });
      final plugin = InstalledPlugin(
        manifest: manifest,
        path: root.path,
        enabled: true,
        grantedPermissions: const [],
        enabledFeaturePages: const [],
        enabledTools: const ['calc_plugin_add_numbers'],
      );

      final tools = ToolCallService.openAITools([plugin]);
      expect(
        tools.any(
          (tool) => tool['function']?['name'] == 'calc_plugin_add_numbers',
        ),
        isTrue,
      );

      final result = await PluginLuaRuntimeService().executeTool(
        plugin: plugin,
        tool: manifest.tools.single,
        arguments: {'a': 2, 'b': 3},
      );
      expect(result['ok'], isTrue);
      expect(result['sum'], 5);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('Lua plugin functions are executable through runtime', () async {
    final root = await Directory.systemTemp.createTemp('lynai_lua_function_');
    try {
      await File('${root.path}/main.lua').writeAsString(r'''
function lookup(args)
  return { ok = true, value = "hello " .. args.name }
end
''');
      final manifest = PluginManifest.fromJson({
        'id': 'function_plugin',
        'name': 'Function Plugin',
        'entry': 'main.lua',
        'functions': [
          {
            'name': 'lookup',
            'title': 'Lookup',
            'handler': 'lookup',
            'parameters': {
              'type': 'object',
              'properties': {
                'name': {'type': 'string'},
              },
            },
          },
        ],
      });
      final plugin = InstalledPlugin(
        manifest: manifest,
        path: root.path,
        enabled: true,
        grantedPermissions: const [],
        enabledFeaturePages: const [],
        enabledFunctions: const ['lookup'],
      );

      final result = await PluginLuaRuntimeService().executeFunction(
        plugin: plugin,
        function: manifest.functions.single,
        arguments: {'name': 'lynai'},
      );

      expect(result['ok'], isTrue);
      expect(result['value'], 'hello lynai');
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('Agent Lua can call plugin functions with continuation', () async {
    SharedPreferences.setMockInitialValues({});
    final source = await Directory.systemTemp.createTemp(
      'lynai_agent_lua_func_src_',
    );
    final installedRoot = await Directory.systemTemp.createTemp(
      'lynai_agent_lua_func_installed_',
    );
    try {
      await File('${source.path}/main.lua').writeAsString(r'''
function lookup(args)
  return { ok = true, value = "hello " .. args.name }
end
''');
      await File('${source.path}/plugin.json').writeAsString(
        jsonEncode({
          'id': 'agent_function_plugin',
          'name': 'Agent Function Plugin',
          'entry': 'main.lua',
          'functions': [
            {'name': 'lookup', 'title': 'Lookup', 'handler': 'lookup'},
          ],
        }),
      );
      final plugins = PluginProvider(
        repository: PluginRepository(rootOverride: installedRoot),
      );
      await plugins.importDirectory(source.path);
      await plugins.setEnabled('agent_function_plugin', true);
      await plugins.setFunctionEnabled('agent_function_plugin', 'lookup', true);
      final conversations = memoryConversationProvider();
      final settings = memorySettingsProvider();
      final cid = conversations.createConversation(
        ConversationSettings(modelId: 'm1', agentEnabled: true),
      );

      final result = await AgentLuaScriptService().execute(
        purpose: 'call plugin',
        plugins: plugins,
        settings: settings,
        conversations: conversations,
        conversationId: cid,
        code: r'''
function after_lookup(response, request)
  return { ok = response.ok, summary = response.value, requested = request.functionName }
end

return lynai.call("plugins.callFunction", {
  pluginId = "agent_function_plugin",
  functionName = "lookup",
  arguments = { name = "lynai" },
  __lynai_next = "after_lookup"
})
''',
      );

      expect(result['ok'], isTrue);
      final payload = result['result'] as Map;
      expect(payload['summary'], 'hello lynai');
      expect(payload['requested'], 'lookup');
    } finally {
      await source.delete(recursive: true);
      await installedRoot.delete(recursive: true);
    }
  });

  test(
    'Agent Lua returns structured error without plugin permission',
    () async {
      SharedPreferences.setMockInitialValues({});
      final conversations = memoryConversationProvider();
      final settings = memorySettingsProvider();
      await settings.replaceSettings(
        settings.settings.copyWith(agentGrantedPermissions: const []),
      );
      final cid = conversations.createConversation(
        ConversationSettings(modelId: 'm1', agentEnabled: true),
      );

      final result = await AgentLuaScriptService().execute(
        purpose: 'call plugin without permission',
        settings: settings,
        conversations: conversations,
        conversationId: cid,
        code: r'''
return lynai.call("plugins.callFunction", {
  pluginId = "missing",
  functionName = "lookup"
})
''',
      );

      expect(result['ok'], isFalse);
      final payload = result['result'] as Map;
      expect(payload['ok'], isFalse);
      expect(payload['error'], isA<Map>());
      expect((payload['error'] as Map)['code'], 'permission_denied');
      expect((result['error'] as Map)['code'], 'permission_denied');
    },
  );

  test(
    'Agent Lua reports missing continuation with structured error',
    () async {
      SharedPreferences.setMockInitialValues({});
      final source = await Directory.systemTemp.createTemp(
        'lynai_agent_lua_missing_next_src_',
      );
      final installedRoot = await Directory.systemTemp.createTemp(
        'lynai_agent_lua_missing_next_installed_',
      );
      try {
        await File('${source.path}/main.lua').writeAsString(r'''
function lookup(args)
  return { ok = true, value = "hello" }
end
''');
        await File('${source.path}/plugin.json').writeAsString(
          jsonEncode({
            'id': 'agent_missing_next_plugin',
            'name': 'Agent Missing Next Plugin',
            'entry': 'main.lua',
            'functions': [
              {'name': 'lookup', 'title': 'Lookup', 'handler': 'lookup'},
            ],
          }),
        );
        final plugins = PluginProvider(
          repository: PluginRepository(rootOverride: installedRoot),
        );
        await plugins.importDirectory(source.path);
        await plugins.setEnabled('agent_missing_next_plugin', true);
        await plugins.setFunctionEnabled(
          'agent_missing_next_plugin',
          'lookup',
          true,
        );
        final conversations = memoryConversationProvider();
        final settings = memorySettingsProvider();
        final cid = conversations.createConversation(
          ConversationSettings(modelId: 'm1', agentEnabled: true),
        );

        final result = await AgentLuaScriptService().execute(
          purpose: 'missing continuation',
          plugins: plugins,
          settings: settings,
          conversations: conversations,
          conversationId: cid,
          code: r'''
return lynai.call("plugins.callFunction", {
  pluginId = "agent_missing_next_plugin",
  functionName = "lookup",
  __lynai_next = "missing_next"
})
''',
        );

        expect(result['ok'], isFalse);
        final error = result['error'] as Map;
        expect(error['code'], 'continuation_not_found');
      } finally {
        await source.delete(recursive: true);
        await installedRoot.delete(recursive: true);
      }
    },
  );

  test('Agent Lua limits recursive continuations', () async {
    SharedPreferences.setMockInitialValues({});
    final source = await Directory.systemTemp.createTemp(
      'lynai_agent_lua_loop_src_',
    );
    final installedRoot = await Directory.systemTemp.createTemp(
      'lynai_agent_lua_loop_installed_',
    );
    try {
      await File('${source.path}/main.lua').writeAsString(r'''
function lookup(args)
  return { ok = true, value = "again" }
end
''');
      await File('${source.path}/plugin.json').writeAsString(
        jsonEncode({
          'id': 'agent_loop_plugin',
          'name': 'Agent Loop Plugin',
          'entry': 'main.lua',
          'functions': [
            {'name': 'lookup', 'title': 'Lookup', 'handler': 'lookup'},
          ],
        }),
      );
      final plugins = PluginProvider(
        repository: PluginRepository(rootOverride: installedRoot),
      );
      await plugins.importDirectory(source.path);
      await plugins.setEnabled('agent_loop_plugin', true);
      await plugins.setFunctionEnabled('agent_loop_plugin', 'lookup', true);
      final conversations = memoryConversationProvider();
      final settings = memorySettingsProvider();
      final cid = conversations.createConversation(
        ConversationSettings(modelId: 'm1', agentEnabled: true),
      );

      final result = await AgentLuaScriptService().execute(
        purpose: 'loop continuation',
        plugins: plugins,
        settings: settings,
        conversations: conversations,
        conversationId: cid,
        code: r'''
function loop_next(response, request)
  return lynai.call("plugins.callFunction", {
    pluginId = "agent_loop_plugin",
    functionName = "lookup",
    __lynai_next = "loop_next"
  })
end

return lynai.call("plugins.callFunction", {
  pluginId = "agent_loop_plugin",
  functionName = "lookup",
  __lynai_next = "loop_next"
})
''',
      );

      expect(result['ok'], isFalse);
      final error = result['error'] as Map;
      expect(error['code'], 'continuation_depth_exceeded');
    } finally {
      await source.delete(recursive: true);
      await installedRoot.delete(recursive: true);
    }
  });

  test(
    'Agent Lua executes async LynAI functions with global permissions',
    () async {
      SharedPreferences.setMockInitialValues({});
      final features = FeatureProvider();
      final settings = memorySettingsProvider();
      final conversations = memoryConversationProvider();
      final cid = conversations.createConversation(
        ConversationSettings(modelId: 'm1', agentEnabled: true),
      );

      final result = await AgentLuaScriptService().execute(
        purpose: 'save note',
        features: features,
        settings: settings,
        conversations: conversations,
        conversationId: cid,
        code: r'''
function after_save(response, request)
  return { ok = response.ok, title = response.note.title }
end

return lynai.call("notes.save", {
  title = "Agent Note",
  content = "created by lua",
  __lynai_next = "after_save"
})
''',
      );

      expect(result['ok'], isTrue);
      final payload = result['result'] as Map;
      expect(payload['title'], 'Agent Note');
      expect(features.notes.single.title, 'Agent Note');
    },
  );

  test('Agent Lua blocks delete functions until recycle bin exists', () async {
    SharedPreferences.setMockInitialValues({});
    final features = FeatureProvider();
    final noteId = await features.addNoteWithContent('Delete Me', 'content');
    final settings = memorySettingsProvider();
    final conversations = memoryConversationProvider();
    final cid = conversations.createConversation(
      ConversationSettings(modelId: 'm1', agentEnabled: true),
    );

    final result = await AgentLuaScriptService().execute(
      purpose: 'delete note',
      features: features,
      settings: settings,
      conversations: conversations,
      conversationId: cid,
      code:
          '''
return lynai.call("notes.delete", { id = "$noteId" })
''',
    );

    expect(result['ok'], isFalse);
    expect(result['error'].toString(), contains('回收站'));
    expect(features.notes.single.id, noteId);
  });

  test('Lua plugins can read real config through lynai.call', () async {
    final root = await Directory.systemTemp.createTemp('lynai_config_plugin_');
    try {
      await File('${root.path}/config.json').writeAsString('{"name":"demo"}');
      await File('${root.path}/config.schema.json').writeAsString('''
{
  "fields": [
    { "key": "enabled", "type": "boolean", "default": true },
    { "key": "name", "type": "string" }
  ]
}
''');
      await File('${root.path}/main.lua').writeAsString(r'''
function read_config(args)
  local config = lynai.call("plugin.config.read", {})
  return { ok = config.ok, enabled = config.values.enabled, name = config.values.name }
end
''');
      await File('${root.path}/plugin.json').writeAsString(
        '{"id":"lua_config_plugin","name":"Lua Config Plugin","entry":"main.lua","tools":[{"name":"lua_config_read","description":"Read config","handler":"read_config","parameters":{"type":"object"}}]}',
      );
      final installedRoot = await Directory.systemTemp.createTemp(
        'lynai_config_installed_',
      );
      final provider = PluginProvider(
        repository: PluginRepository(rootOverride: installedRoot),
      );
      await provider.importDirectory(root.path);
      final installed = provider.pluginById('lua_config_plugin')!;

      final result = await PluginLuaRuntimeService().executeTool(
        plugin: installed,
        tool: installed.manifest.tools.single,
        arguments: const {},
        plugins: provider,
      );

      expect(result['ok'], isTrue);
      expect(result['enabled'], isTrue);
      expect(result['name'], 'demo');
      await installedRoot.delete(recursive: true);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('Plugin tools require all manifest permissions before exposure', () {
    final manifest = PluginManifest.fromJson({
      'id': 'secure_plugin',
      'name': 'Secure Plugin',
      'entry': 'main.lua',
      'permissions': ['notes:read'],
      'tools': [
        {
          'name': 'secure_plugin_read_notes',
          'description': 'Read notes',
          'handler': 'read_notes',
          'parameters': {'type': 'object'},
        },
      ],
    });
    final locked = InstalledPlugin(
      manifest: manifest,
      path: '/tmp/secure_plugin',
      enabled: true,
      grantedPermissions: const [],
      enabledFeaturePages: const [],
      enabledTools: const ['secure_plugin_read_notes'],
    );
    final granted = locked.copyWith(grantedPermissions: const ['notes:read']);

    bool containsSecureTool(List<Map<String, dynamic>> tools) {
      return tools.any(
        (tool) => tool['function']?['name'] == 'secure_plugin_read_notes',
      );
    }

    expect(containsSecureTool(ToolCallService.openAITools([locked])), isFalse);
    expect(containsSecureTool(ToolCallService.openAITools([granted])), isTrue);
  });

  test('PluginManifest rejects invalid tool names and handlers', () {
    final badName = PluginManifest.fromJson({
      'id': 'bad_tool_plugin',
      'name': 'Bad Tool Plugin',
      'entry': 'main.lua',
      'tools': [
        {'name': 'bad.tool', 'handler': 'run'},
      ],
    });
    final badHandler = PluginManifest.fromJson({
      'id': 'bad_handler_plugin',
      'name': 'Bad Handler Plugin',
      'entry': 'main.lua',
      'tools': [
        {'name': 'good_tool', 'handler': 'bad.handler'},
      ],
    });

    expect(badName.validate(), contains('tool 名称'));
    expect(badHandler.validate(), contains('handler'));
  });

  test('PluginManifest rejects invalid function names and handlers', () {
    final badName = PluginManifest.fromJson({
      'id': 'bad_function_plugin',
      'name': 'Bad Function Plugin',
      'entry': 'main.lua',
      'functions': [
        {'name': 'bad.function', 'handler': 'run'},
      ],
    });
    final badHandler = PluginManifest.fromJson({
      'id': 'bad_function_handler_plugin',
      'name': 'Bad Function Handler Plugin',
      'entry': 'main.lua',
      'functions': [
        {'name': 'good_function', 'handler': 'bad.handler'},
      ],
    });

    expect(badName.validate(), contains('function 名称'));
    expect(badHandler.validate(), contains('handler'));
  });

  test('PluginManifest rejects duplicate names only within the same kind', () {
    final duplicateTools = PluginManifest.fromJson({
      'id': 'duplicate_tools_plugin',
      'name': 'Duplicate Tools Plugin',
      'entry': 'main.lua',
      'tools': [
        {'name': 'same_api', 'handler': 'first'},
        {'name': 'same_api', 'handler': 'second'},
      ],
    });
    final duplicateFunctions = PluginManifest.fromJson({
      'id': 'duplicate_functions_plugin',
      'name': 'Duplicate Functions Plugin',
      'entry': 'main.lua',
      'functions': [
        {'name': 'same_api', 'handler': 'first'},
        {'name': 'same_api', 'handler': 'second'},
      ],
    });
    final duplicateSkills = PluginManifest.fromJson({
      'id': 'duplicate_skills_plugin',
      'name': 'Duplicate Skills Plugin',
      'entry': 'main.lua',
      'skills': [
        {'name': 'same_api'},
        {'name': 'same_api'},
      ],
    });
    final duplicateAcrossTypes = PluginManifest.fromJson({
      'id': 'duplicate_api_plugin',
      'name': 'Duplicate API Plugin',
      'entry': 'main.lua',
      'tools': [
        {'name': 'same_api', 'handler': 'tool_run'},
      ],
      'functions': [
        {'name': 'same_api', 'handler': 'function_run'},
      ],
      'skills': [
        {'name': 'same_api'},
      ],
    });

    expect(duplicateTools.validate(), contains('tool 名称重复'));
    expect(duplicateFunctions.validate(), contains('function 名称重复'));
    expect(duplicateSkills.validate(), contains('skill 名称重复'));
    expect(duplicateAcrossTypes.validate(), isNull);
  });

  test('Lua plugin tools can read notes through lynai.notes', () async {
    SharedPreferences.setMockInitialValues({});
    final features = FeatureProvider();
    final noteId = await features.addNoteWithContent(
      'Daily Log',
      'ship plugin APIs',
    );
    final root = await Directory.systemTemp.createTemp('lynai_notes_plugin_');
    try {
      await File('${root.path}/main.lua').writeAsString(r'''
function read_notes(args)
  local listed = lynai.notes.list({ query = "daily", includeContent = true })
  local note = lynai.notes.read({ id = args.id })
  return { ok = true, count = #listed.notes, title = note.note.title, content = note.note.content }
end
''');
      final manifest = PluginManifest.fromJson({
        'id': 'notes_plugin',
        'name': 'Notes Plugin',
        'entry': 'main.lua',
        'permissions': ['notes:read'],
        'tools': [
          {
            'name': 'notes_plugin_read_notes',
            'description': 'Read notes',
            'handler': 'read_notes',
            'parameters': {'type': 'object'},
          },
        ],
      });
      final plugin = InstalledPlugin(
        manifest: manifest,
        path: root.path,
        enabled: true,
        grantedPermissions: const ['notes:read'],
        enabledFeaturePages: const [],
      );

      final result = await PluginLuaRuntimeService().executeTool(
        plugin: plugin,
        tool: manifest.tools.single,
        arguments: {'id': noteId},
        features: features,
      );

      expect(result['ok'], isTrue);
      expect(result['count'], 1);
      expect(result['title'], 'Daily Log');
      expect(result['content'], 'ship plugin APIs');
    } finally {
      await root.delete(recursive: true);
    }
  });

  test(
    'Built-in plugin source directories are valid plugin directories',
    () async {
      final installedRoot = await Directory.systemTemp.createTemp(
        'lynai_builtin_source_',
      );
      try {
        final repository = PluginRepository(rootOverride: installedRoot);

        final status = await repository.importDirectory(
          'assets/plugins/status-dashboard',
        );
        final weather = await repository.importDirectory(
          'assets/plugins/weather-query',
        );

        expect(status.id, 'status-dashboard');
        expect(weather.id, 'weather-query');
        expect(
          File(
            '${installedRoot.path}/installed/status-dashboard/plugin.json',
          ).existsSync(),
          isTrue,
        );
        expect(
          File(
            '${installedRoot.path}/installed/weather-query/main.lua',
          ).existsSync(),
          isTrue,
        );
      } finally {
        await installedRoot.delete(recursive: true);
      }
    },
  );

  test(
    'Built-in source sync updates defaults and keeps custom files',
    () async {
      final installedRoot = await Directory.systemTemp.createTemp(
        'lynai_builtin_sync_installed_',
      );
      final sourceV1 = await Directory.systemTemp.createTemp(
        'lynai_builtin_sync_source_v1_',
      );
      final sourceV2 = await Directory.systemTemp.createTemp(
        'lynai_builtin_sync_source_v2_',
      );
      try {
        await Directory('${sourceV1.path}/defaults').create(recursive: true);
        await File('${sourceV1.path}/plugin.json').writeAsString('''
{
  "id": "sync_builtin",
  "name": "Sync Builtin",
  "entry": "main.lua",
  "editableFiles": [
    {"path": "status.html", "defaultPath": "defaults/status.html"}
  ]
}
''');
        await File('${sourceV1.path}/main.lua').writeAsString('v1 main');
        await File(
          '${sourceV1.path}/defaults/status.html',
        ).writeAsString('default v1');
        await File('${sourceV1.path}/defaults/old.html').writeAsString('old');

        final repository = PluginRepository(rootOverride: installedRoot);
        final installed = await repository.importDirectory(sourceV1.path);
        await File('${installed.path}/status.html').writeAsString('custom');

        await Directory('${sourceV2.path}/defaults').create(recursive: true);
        await File('${sourceV2.path}/plugin.json').writeAsString('''
{
  "id": "sync_builtin",
  "name": "Sync Builtin",
  "entry": "main.lua",
  "editableFiles": [
    {"path": "status.html", "defaultPath": "defaults/status.html"}
  ]
}
''');
        await File('${sourceV2.path}/main.lua').writeAsString('v2 main');
        await File(
          '${sourceV2.path}/defaults/status.html',
        ).writeAsString('default v2');

        final synced = await repository.syncDirectory(sourceV2.path);

        expect(await File('${synced.path}/main.lua').readAsString(), 'v2 main');
        expect(
          await File('${synced.path}/defaults/status.html').readAsString(),
          'default v2',
        );
        expect(File('${synced.path}/defaults/old.html').existsSync(), isFalse);
        expect(
          await File('${synced.path}/status.html').readAsString(),
          'custom',
        );
      } finally {
        await installedRoot.delete(recursive: true);
        await sourceV1.delete(recursive: true);
        await sourceV2.delete(recursive: true);
      }
    },
  );

  test('PluginRepository ignores unsafe ZIP archive paths', () async {
    final installedRoot = await Directory.systemTemp.createTemp(
      'lynai_zip_path_root_',
    );
    try {
      final manifestBytes = utf8.encode(
        jsonEncode({
          'id': 'zip_path_plugin',
          'name': 'ZIP Path Plugin',
          'entry': 'main.lua',
        }),
      );
      final luaBytes = utf8.encode('function run(args) return {ok = true} end');
      final archive = Archive()
        ..addFile(
          ArchiveFile('plugin.json', manifestBytes.length, manifestBytes),
        )
        ..addFile(ArchiveFile('main.lua', luaBytes.length, luaBytes))
        ..addFile(ArchiveFile('../escape.txt', 3, utf8.encode('bad')))
        ..addFile(ArchiveFile('/absolute.txt', 3, utf8.encode('bad')))
        ..addFile(ArchiveFile('C:/absolute.txt', 3, utf8.encode('bad')))
        ..addFile(
          ArchiveFile('https://example.com/file.txt', 3, utf8.encode('bad')),
        );

      final repository = PluginRepository(rootOverride: installedRoot);
      final plugin = await repository.importZipBytes(
        ZipEncoder().encode(archive),
      );

      expect(plugin.id, 'zip_path_plugin');
      expect(File('${installedRoot.path}/escape.txt').existsSync(), isFalse);
      expect(
        File(
          '${installedRoot.path}/installed/zip_path_plugin/absolute.txt',
        ).existsSync(),
        isFalse,
      );
      expect(
        File(
          '${installedRoot.path}/installed/zip_path_plugin/C:/absolute.txt',
        ).existsSync(),
        isFalse,
      );
      expect(
        Directory(
          '${installedRoot.path}/installed/zip_path_plugin/https:',
        ).existsSync(),
        isFalse,
      );
    } finally {
      await installedRoot.delete(recursive: true);
    }
  });

  test(
    'Plugin snapshots, reset, bytes write and export preserve state',
    () async {
      final installedRoot = await Directory.systemTemp.createTemp(
        'lynai_plugin_snapshot_root_',
      );
      final sourceRoot = await Directory.systemTemp.createTemp(
        'lynai_plugin_snapshot_source_',
      );
      try {
        await Directory('${sourceRoot.path}/defaults').create(recursive: true);
        await File('${sourceRoot.path}/plugin.json').writeAsString('''
{
  "id": "snapshot_source",
  "name": "Snapshot Source",
  "entry": "main.lua",
  "permissions": ["files:write", "network:access"],
  "featurePages": [
    {"id": "main", "title": "Main", "entry": "index.html"}
  ],
  "editableFiles": [
    {"path": "index.html", "type": "html", "defaultPath": "defaults/index.html"}
  ]
}
''');
        await File(
          '${sourceRoot.path}/main.lua',
        ).writeAsString('function noop() end');
        await File(
          '${sourceRoot.path}/defaults/index.html',
        ).writeAsString('default page');

        final provider = PluginProvider(
          repository: PluginRepository(rootOverride: installedRoot),
        );
        await provider.importDirectory(sourceRoot.path);
        await provider.setGrantedPermissions('snapshot_source', [
          'files:write',
          'network:access',
        ]);
        await provider.renameDisplayName('snapshot_source', '显示名');
        await provider.writeEditableFile(
          'snapshot_source',
          'index.html',
          'custom v1',
        );
        await provider.writeFileBytes('snapshot_source', 'assets/logo.bin', [
          1,
          2,
          3,
        ]);

        final snapshot = await provider.createSnapshot('snapshot_source');
        expect(snapshot.id, 'snapshot_source-snapshot-1');
        expect(snapshot.enabled, isFalse);
        expect(snapshot.grantedPermissions, contains('files:write'));
        expect(snapshot.manifest.snapshotOf, 'snapshot_source');
        expect(snapshot.manifest.name, '显示名-快照 #1');
        await provider.updateSetting(snapshot.id, 'mode', 'before-rename');

        final renamed = await provider.updateSnapshotIdentity(
          snapshot.id,
          'renamed_snapshot',
          'Renamed Snapshot',
        );
        expect(renamed.id, 'renamed_snapshot');
        expect(provider.pluginById(snapshot.id), isNull);
        expect(provider.pluginById('renamed_snapshot'), isNotNull);
        final reloadedProvider = PluginProvider(
          repository: PluginRepository(rootOverride: installedRoot),
        );
        await reloadedProvider.load();
        expect(reloadedProvider.pluginById('renamed_snapshot'), isNotNull);
        expect(
          await reloadedProvider.loadSettings('renamed_snapshot'),
          containsPair('mode', 'before-rename'),
        );

        await provider.writeEditableFile(
          'snapshot_source',
          'index.html',
          'custom v2',
        );
        await provider.restoreSnapshotToSource('renamed_snapshot');
        final source = provider.pluginById('snapshot_source')!;
        expect(source.displayName, '显示名');
        expect(source.grantedPermissions, contains('network:access'));
        expect(source.manifest.name, 'Snapshot Source');
        expect(
          await File('${source.path}/index.html').readAsString(),
          'custom v1',
        );
        expect(
          await File('${source.path}/plugin.json').readAsString(),
          contains('snapshot_source'),
        );
        expect(
          await File('${source.path}/plugin.json').readAsString(),
          isNot(contains('snapshotOf')),
        );

        await provider.setGrantedPermissions('snapshot_source', const []);
        await provider.resetPluginDefaults('snapshot_source');
        expect(File('${source.path}/index.html').existsSync(), isFalse);
        expect(File('${source.path}/assets/logo.bin').existsSync(), isFalse);
        expect(
          await provider.readFile('snapshot_source', 'index.html'),
          'default page',
        );

        await provider.writeEditableFile(
          'snapshot_source',
          'index.html',
          'exported page',
        );
        final archive = ZipDecoder().decodeBytes(
          await provider.buildPluginZipBytes('snapshot_source'),
        );
        final names = archive.map((item) => item.name).toSet();
        expect(names, contains('plugin.json'));
        expect(names, contains('index.html'));
        final exportedIndex = archive.firstWhere(
          (item) => item.name == 'index.html',
        );
        expect(
          utf8.decode(exportedIndex.content as List<int>),
          'exported page',
        );
      } finally {
        await installedRoot.delete(recursive: true);
        await sourceRoot.delete(recursive: true);
      }
    },
  );

  test(
    'Plugin snapshots cannot enable duplicate tools and functions',
    () async {
      final installedRoot = await Directory.systemTemp.createTemp(
        'lynai_plugin_conflict_root_',
      );
      final sourceRoot = await Directory.systemTemp.createTemp(
        'lynai_plugin_conflict_source_',
      );
      try {
        await File('${sourceRoot.path}/plugin.json').writeAsString('''
{
  "id": "conflict_source",
  "name": "Conflict Source",
  "entry": "main.lua",
  "tools": [
    {"name": "same_tool", "handler": "same_tool", "parameters": {"type": "object"}}
  ],
  "functions": [
    {"name": "same_func", "handler": "same_func"}
  ]
}
''');
        await File('${sourceRoot.path}/main.lua').writeAsString('''
function same_tool(args) return {ok = true} end
function same_func(args) return {ok = true} end
''');

        final provider = PluginProvider(
          repository: PluginRepository(rootOverride: installedRoot),
        );
        await provider.importDirectory(sourceRoot.path);
        await provider.setEnabled('conflict_source', true);
        final snapshot = await provider.createSnapshot('conflict_source');

        expect(
          () => provider.setEnabled(snapshot.id, true),
          throwsA(
            isA<Exception>()
                .having((e) => e.toString(), 'message', contains('same_tool'))
                .having((e) => e.toString(), 'message', contains('same_func')),
          ),
        );

        await provider.setToolEnabled(snapshot.id, 'same_tool', false);
        await provider.setFunctionEnabled(snapshot.id, 'same_func', false);
        await provider.setEnabled(snapshot.id, true);
        expect(provider.pluginById(snapshot.id)?.enabled, isTrue);

        await provider.setEnabled('conflict_source', false);
        await provider.setToolEnabled(snapshot.id, 'same_tool', true);
        await provider.setFunctionEnabled(snapshot.id, 'same_func', true);
        await provider.setEnabled(snapshot.id, true);
        expect(provider.pluginById(snapshot.id)?.enabled, isTrue);
        expect(
          () => provider.setEnabled('conflict_source', true),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('API 名称冲突'),
            ),
          ),
        );
      } finally {
        await installedRoot.delete(recursive: true);
        await sourceRoot.delete(recursive: true);
      }
    },
  );

  testWidgets('Built-in plugin assets are bundled', (tester) async {
    expect(
      await rootBundle.loadString(
        'assets/plugins/status-dashboard/plugin.json',
      ),
      contains('status-dashboard'),
    );
    expect(
      await rootBundle.loadString(
        'assets/plugins/status-dashboard/defaults/main.lua',
      ),
      contains('status_files'),
    );
    expect(
      await rootBundle.loadString('assets/plugins/weather-query/plugin.json'),
      contains('weather-query'),
    );
    expect(
      await rootBundle.loadString('assets/plugins/weather-query/main.lua'),
      contains('query_weather'),
    );
    expect(
      await rootBundle.loadString(
        'assets/plugins/weather-query/defaults/skills/weather_research.md',
      ),
      contains('query_weather'),
    );
  });

  test('Trusted built-in state enables and grants permissions', () async {
    final installedRoot = await Directory.systemTemp.createTemp(
      'lynai_trusted_builtin_',
    );
    try {
      final provider = PluginProvider(
        repository: PluginRepository(rootOverride: installedRoot),
      );

      await provider.importDirectory('assets/plugins/weather-query');
      final plugin = await provider.trustInstalledBuiltIn('weather-query');

      expect(plugin.id, 'weather-query');
      expect(plugin.enabled, isTrue);
      expect(plugin.grantedPermissions, contains('network:access'));
      expect(plugin.hasAllPermissionsGranted, isTrue);
    } finally {
      await installedRoot.delete(recursive: true);
    }
  });

  test('Built-in plugin file lists skip source-only files', () {
    for (final files in PluginRepository.builtInPluginFiles.values) {
      expect(files, isNot(contains('README.md')));
      expect(files.where((file) => file.endsWith('/README.md')), isEmpty);
    }
  });

  test('Lua runtime supports JSON decode and command continuation', () async {
    final root = await Directory.systemTemp.createTemp('lynai_lua_next_');
    try {
      await File('${root.path}/main.lua').writeAsString(r'''
function read_info(args)
  return { __lynai_function = "plugin.info", args = {}, __lynai_next = "parse_info" }
end

function parse_info(response, original_args, request_args)
  local encoded = lynai.json.encode(response.plugin)
  local decoded = lynai.json.decode(encoded)
  return {
    ok = response.ok,
    pluginId = decoded.id,
    requestedMarker = original_args.marker,
    methodHadArgs = request_args ~= nil
  }
end
''');
      final manifest = PluginManifest.fromJson({
        'id': 'next_plugin',
        'name': 'Next Plugin',
        'entry': 'main.lua',
        'tools': [
          {
            'name': 'next_plugin_read_info',
            'description': 'Read plugin info through continuation',
            'handler': 'read_info',
            'parameters': {'type': 'object'},
          },
        ],
      });
      final plugin = InstalledPlugin(
        manifest: manifest,
        path: root.path,
        enabled: true,
        grantedPermissions: const [],
        enabledFeaturePages: const [],
      );

      final result = await PluginLuaRuntimeService().executeTool(
        plugin: plugin,
        tool: manifest.tools.single,
        arguments: {'marker': 'weather'},
      );

      expect(result['ok'], isTrue);
      expect(result['pluginId'], 'next_plugin');
      expect(result['requestedMarker'], 'weather');
      expect(result['methodHadArgs'], isTrue);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('Lua runtime removes dangerous globals', () async {
    final root = await Directory.systemTemp.createTemp('lynai_lua_globals_');
    try {
      await File('${root.path}/main.lua').writeAsString(r'''
function inspect_globals(args)
  return {
    ok = true,
    osMissing = os == nil,
    ioMissing = io == nil,
    packageMissing = package == nil,
    requireMissing = require == nil,
    loadMissing = load == nil,
    debugMissing = debug == nil,
    collectgarbageMissing = collectgarbage == nil
  }
end
''');
      final manifest = PluginManifest.fromJson({
        'id': 'globals_plugin',
        'name': 'Globals Plugin',
        'entry': 'main.lua',
        'tools': [
          {
            'name': 'globals_plugin_inspect',
            'description': 'Inspect Lua globals',
            'handler': 'inspect_globals',
            'parameters': {'type': 'object'},
          },
        ],
      });
      final plugin = InstalledPlugin(
        manifest: manifest,
        path: root.path,
        enabled: true,
        grantedPermissions: const [],
        enabledFeaturePages: const [],
      );

      final result = await PluginLuaRuntimeService().executeTool(
        plugin: plugin,
        tool: manifest.tools.single,
        arguments: const {},
      );

      expect(result['ok'], isTrue);
      expect(result['osMissing'], isTrue);
      expect(result['ioMissing'], isTrue);
      expect(result['packageMissing'], isTrue);
      expect(result['requireMissing'], isTrue);
      expect(result['loadMissing'], isTrue);
      expect(result['debugMissing'], isTrue);
      expect(result['collectgarbageMissing'], isTrue);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('Agent Lua runtime removes dangerous globals', () async {
    final result = await AgentLuaScriptService().execute(
      purpose: 'inspect globals',
      code: r'''
return {
  ok = true,
  osMissing = os == nil,
  ioMissing = io == nil,
  packageMissing = package == nil,
  requireMissing = require == nil,
  loadMissing = load == nil,
  debugMissing = debug == nil,
  collectgarbageMissing = collectgarbage == nil
}
''',
    );

    expect(result['ok'], isTrue);
    final payload = result['result'] as Map;
    expect(payload['osMissing'], isTrue);
    expect(payload['ioMissing'], isTrue);
    expect(payload['packageMissing'], isTrue);
    expect(payload['requireMissing'], isTrue);
    expect(payload['loadMissing'], isTrue);
    expect(payload['debugMissing'], isTrue);
    expect(payload['collectgarbageMissing'], isTrue);
  });

  test('Lua runtime limits recursive command continuations', () async {
    final root = await Directory.systemTemp.createTemp('lynai_lua_next_loop_');
    try {
      await File('${root.path}/main.lua').writeAsString(r'''
function loop(args)
  return { __lynai_function = "plugin.info", args = {}, __lynai_next = "loop_next" }
end

function loop_next(response, original_args, request_args)
  return { __lynai_function = "plugin.info", args = {}, __lynai_next = "loop_next" }
end
''');
      final manifest = PluginManifest.fromJson({
        'id': 'loop_plugin',
        'name': 'Loop Plugin',
        'entry': 'main.lua',
        'tools': [
          {
            'name': 'loop_plugin_loop',
            'description': 'Loop through continuations',
            'handler': 'loop',
            'parameters': {'type': 'object'},
          },
        ],
      });
      final plugin = InstalledPlugin(
        manifest: manifest,
        path: root.path,
        enabled: true,
        grantedPermissions: const [],
        enabledFeaturePages: const [],
      );

      final result = await PluginLuaRuntimeService().executeTool(
        plugin: plugin,
        tool: manifest.tools.single,
        arguments: const {},
      );

      expect(result['ok'], isFalse);
      expect(result['error'], contains('continuation 超过最大深度'));
    } finally {
      await root.delete(recursive: true);
    }
  });

  test(
    'Weather plugin builds URLs and returns compact parsed weather',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'lynai_weather_plugin_',
      );
      try {
        await File('${root.path}/main.lua').writeAsString(
          await File('assets/plugins/weather-query/main.lua').readAsString(),
        );
        final manifest = PluginManifest.fromJson({
          'id': 'weather-query',
          'name': 'Weather Query',
          'entry': 'main.lua',
        });
        final plugin = InstalledPlugin(
          manifest: manifest,
          path: root.path,
          enabled: true,
          grantedPermissions: const ['network:access'],
          enabledFeaturePages: const [],
        );

        final ipRequest = await PluginLuaRuntimeService().executeTool(
          plugin: plugin,
          tool: const PluginToolDefinition(
            name: 'weather_request_for_test',
            description: 'Build weather request',
            handler: 'weather_request_for_test',
            parameters: {'type': 'object'},
          ),
          arguments: const {},
        );
        final cityRequest = await PluginLuaRuntimeService().executeTool(
          plugin: plugin,
          tool: const PluginToolDefinition(
            name: 'weather_request_for_test',
            description: 'Build weather request',
            handler: 'weather_request_for_test',
            parameters: {'type': 'object'},
          ),
          arguments: {'location': '北京'},
        );
        final localeRequest = await PluginLuaRuntimeService().executeTool(
          plugin: plugin,
          tool: const PluginToolDefinition(
            name: 'weather_request_for_test',
            description: 'Build weather request',
            handler: 'weather_request_for_test',
            parameters: {'type': 'object'},
          ),
          arguments: {'language': 'zh-CN'},
        );
        final parsed = await PluginLuaRuntimeService().executeTool(
          plugin: plugin,
          tool: const PluginToolDefinition(
            name: 'parse_weather_for_test',
            description: 'Parse weather response',
            handler: 'parse_weather',
            parameters: {'type': 'object'},
          ),
          arguments: {
            'ok': true,
            'status': 200,
            'body': jsonEncode({
              'current_condition': [
                {
                  'observation_time': '08:30 AM',
                  'temp_C': '18',
                  'FeelsLikeC': '17',
                  'weatherDesc': [
                    {'value': 'Partly cloudy'},
                  ],
                  'humidity': '42',
                  'windspeedKmph': '11',
                  'winddir16Point': 'NE',
                  'pressure': '1012',
                  'visibility': '10',
                  'uvIndex': '3',
                },
              ],
              'nearest_area': [
                {
                  'areaName': [
                    {'value': 'Beijing'},
                  ],
                  'region': [
                    {'value': 'Beijing'},
                  ],
                  'country': [
                    {'value': 'China'},
                  ],
                  'latitude': '39.9042',
                  'longitude': '116.4074',
                },
              ],
            }),
          },
        );
        final invalidParsed = await PluginLuaRuntimeService().executeTool(
          plugin: plugin,
          tool: const PluginToolDefinition(
            name: 'parse_weather_for_test',
            description: 'Parse weather response',
            handler: 'parse_weather',
            parameters: {'type': 'object'},
          ),
          arguments: {'ok': true, 'status': 200, 'body': jsonEncode({})},
        );

        expect(ipRequest['ok'], isTrue, reason: ipRequest.toString());
        expect(cityRequest['ok'], isTrue, reason: cityRequest.toString());
        expect(ipRequest['url'], startsWith('https://wttr.in?'));
        expect(ipRequest['url'], contains('lang=zh'));
        expect(cityRequest['url'], contains('%E5%8C%97%E4%BA%AC'));
        expect(localeRequest['url'], contains('lang=zh'));
        expect(localeRequest['url'], isNot(contains('zh-CN')));
        expect(parsed['ok'], isTrue);
        expect(parsed['location'], 'Beijing');
        expect(parsed['temperatureC'], '18');
        expect(parsed['feelsLikeC'], '17');
        expect(parsed['condition'], 'Partly cloudy');
        expect(parsed['humidity'], '42');
        expect(parsed['source'], 'wttr.in');
        expect(parsed.containsKey('body'), isFalse);
        expect(parsed['phase'], 'weather_data_verified');
        expect(parsed['business_ok'], isTrue);
        expect(invalidParsed['ok'], isFalse);
        expect(invalidParsed['phase'], 'weather_data_not_verified');
        expect(invalidParsed['action_ok'], isTrue);
        expect(invalidParsed['business_ok'], isFalse);
      } finally {
        await root.delete(recursive: true);
      }
    },
  );

  test('Lua lynai.notes read APIs require permission', () async {
    SharedPreferences.setMockInitialValues({});
    final features = FeatureProvider();
    await features.addNoteWithContent('Secret', 'hidden');
    final root = await Directory.systemTemp.createTemp('lynai_notes_denied_');
    try {
      await File('${root.path}/main.lua').writeAsString(r'''
function read_notes(args)
  return lynai.notes.list({})
end
''');
      final manifest = PluginManifest.fromJson({
        'id': 'denied_notes_plugin',
        'name': 'Denied Notes Plugin',
        'entry': 'main.lua',
        'permissions': ['notes:read'],
        'tools': [
          {
            'name': 'denied_notes_plugin_read_notes',
            'description': 'Read notes',
            'handler': 'read_notes',
            'parameters': {'type': 'object'},
          },
        ],
      });
      final plugin = InstalledPlugin(
        manifest: manifest,
        path: root.path,
        enabled: true,
        grantedPermissions: const [],
        enabledFeaturePages: const [],
      );

      final result = await PluginLuaRuntimeService().executeTool(
        plugin: plugin,
        tool: manifest.tools.single,
        arguments: const {},
        features: features,
      );

      expect(result['ok'], isFalse);
      expect(result['error'], contains('notes:read'));
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('Lua notes.save updates existing notes through timeline', () async {
    SharedPreferences.setMockInitialValues({});
    final features = FeatureProvider();
    final noteId = await features.addNoteWithContent('Draft', 'old content');
    final root = await Directory.systemTemp.createTemp('lynai_notes_save_');
    try {
      await File('${root.path}/main.lua').writeAsString(r'''
function save_note(args)
  return lynai.notes.save({ id = args.id, content = args.content })
end
''');
      final manifest = PluginManifest.fromJson({
        'id': 'save_notes_plugin',
        'name': 'Save Notes Plugin',
        'entry': 'main.lua',
        'permissions': ['notes:write'],
        'tools': [
          {
            'name': 'save_notes_plugin_save_note',
            'description': 'Save note',
            'handler': 'save_note',
            'parameters': {'type': 'object'},
          },
        ],
      });
      final plugin = InstalledPlugin(
        manifest: manifest,
        path: root.path,
        enabled: true,
        grantedPermissions: const ['notes:write'],
        enabledFeaturePages: const [],
      );

      final result = await PluginLuaRuntimeService().executeTool(
        plugin: plugin,
        tool: manifest.tools.single,
        arguments: {'id': noteId, 'content': 'new content'},
        features: features,
      );

      expect(result['ok'], isTrue);
      expect(result['timelineSaved'], isTrue);
      expect(result['revisionId'], isNotNull);
      expect(features.getNote(noteId)?.content, 'new content');
      expect(features.getNoteTimeline(noteId).length, greaterThanOrEqualTo(2));
    } finally {
      await root.delete(recursive: true);
    }
  });

  test(
    'Lua notes.proposeEdit uses separate notes:propose permission',
    () async {
      SharedPreferences.setMockInitialValues({});
      final features = FeatureProvider();
      final noteId = await features.addNoteWithContent('Draft', 'old content');
      final root = await Directory.systemTemp.createTemp(
        'lynai_notes_propose_',
      );
      try {
        await File('${root.path}/main.lua').writeAsString(r'''
function propose_note(args)
  return lynai.notes.proposeEdit({
    id = args.id,
    edits = {
      { startLine = 1, deleteCount = 1, insertLines = { "new content" }, expectedLines = { "old content" } }
    }
  })
end
''');
        final manifest = PluginManifest.fromJson({
          'id': 'propose_notes_plugin',
          'name': 'Propose Notes Plugin',
          'entry': 'main.lua',
          'permissions': ['notes:propose'],
          'tools': [
            {
              'name': 'propose_notes_plugin_propose_note',
              'description': 'Propose note edit',
              'handler': 'propose_note',
              'parameters': {'type': 'object'},
            },
          ],
        });
        final plugin = InstalledPlugin(
          manifest: manifest,
          path: root.path,
          enabled: true,
          grantedPermissions: const ['notes:propose'],
          enabledFeaturePages: const [],
        );

        final result = await PluginLuaRuntimeService().executeTool(
          plugin: plugin,
          tool: manifest.tools.single,
          arguments: {'id': noteId},
          features: features,
        );

        expect(result['ok'], isTrue);
        expect(result['timelineSaved'], isFalse);
        expect(features.getNote(noteId)?.content, 'old content');
        expect(features.getNoteTimeline(noteId).length, 1);
        expect(features.getNoteEditProposal(noteId), isNotNull);

        final denied = plugin.copyWith(
          grantedPermissions: const ['notes:write'],
        );
        final deniedResult = await PluginLuaRuntimeService().executeTool(
          plugin: denied,
          tool: manifest.tools.single,
          arguments: {'id': noteId},
          features: features,
        );
        expect(deniedResult['ok'], isFalse);
        expect(deniedResult['error'], contains('notes:propose'));
      } finally {
        await root.delete(recursive: true);
      }
    },
  );
}
