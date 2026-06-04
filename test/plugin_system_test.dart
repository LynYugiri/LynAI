import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/plugin.dart';
import 'package:lynai/providers/feature_provider.dart';
import 'package:lynai/services/plugin_lua_runtime_service.dart';
import 'package:lynai/services/tool_call_service.dart';
import 'package:lynai/utils/plugin_path_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

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
}
