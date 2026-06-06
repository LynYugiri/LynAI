import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/model_config.dart';
import 'package:lynai/models/plugin.dart';
import 'package:lynai/models/plugin_config_schema.dart';
import 'package:lynai/providers/feature_provider.dart';
import 'package:lynai/providers/plugin_provider.dart';
import 'package:lynai/repositories/plugin_repository.dart';
import 'package:lynai/services/plugin_lua_runtime_service.dart';
import 'package:lynai/services/tool_call_service.dart';
import 'package:lynai/utils/plugin_path_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
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

        expect(ipRequest['ok'], isTrue, reason: ipRequest.toString());
        expect(cityRequest['ok'], isTrue, reason: cityRequest.toString());
        expect(ipRequest['url'], startsWith('https://wttr.in?'));
        expect(cityRequest['url'], contains('%E5%8C%97%E4%BA%AC'));
        expect(parsed['ok'], isTrue);
        expect(parsed['location'], 'Beijing');
        expect(parsed['temperatureC'], '18');
        expect(parsed['feelsLikeC'], '17');
        expect(parsed['condition'], 'Partly cloudy');
        expect(parsed['humidity'], '42');
        expect(parsed['source'], 'wttr.in');
        expect(parsed.containsKey('body'), isFalse);
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
