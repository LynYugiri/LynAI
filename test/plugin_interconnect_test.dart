import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lynai/providers/plugin_provider.dart';
import 'package:lynai/repositories/plugin_repository.dart';
import 'package:lynai/services/lynai_call_identity.dart';
import 'package:lynai/services/lynai_function_service.dart';
import 'package:lynai/services/lynai_permission_definitions.dart';

Future<Directory> _pluginDir(
  String id,
  String lua,
  List<Map<String, dynamic>> functions,
  List<String> permissions,
) async {
  final dir = await Directory.systemTemp.createTemp('lynai_ic_${id}_');
  await File('${dir.path}/main.lua').writeAsString(lua);
  await File('${dir.path}/plugin.json').writeAsString(
    jsonEncode({
      'id': id,
      'name': id,
      'version': '1.0.0',
      'entry': 'main.lua',
      'permissions': permissions,
      'functions': functions,
    }),
  );
  return dir;
}

Future<Map<String, dynamic>> _callAcross(
  PluginProvider provider,
  String fromPlugin,
  String targetPlugin,
  String function,
  Map<String, dynamic> args,
) {
  return LynAIFunctionService().execute(
    LynAIFunctionCall(
      name: 'plugin.call',
      arguments: {
        'pluginId': targetPlugin,
        'functionName': function,
        'arguments': args,
      },
    ),
    LynAIFunctionContext(
      identity: LynAICallIdentity(
        type: LynAICallerType.plugin,
        pluginId: fromPlugin,
      ),
      plugins: provider,
      plugin: provider.pluginById(fromPlugin),
    ),
  );
}

void main() {
  test('plugin.call crosses plugin boundaries when exposed', () async {
    SharedPreferences.setMockInitialValues({});
    final root = await Directory.systemTemp.createTemp('lynai_ic_ok_');
    try {
      final provider = PluginProvider(
        repository: PluginRepository(rootOverride: root),
      );
      final b = await _pluginDir(
        'b',
        'function double(args) args = args or {}; '
        'return { ok = true, value = (args.x or 0) * 2 } end',
        [
          {
            'name': 'double',
            'handler': 'double',
            'expose': true,
            'parameters': {
              'type': 'object',
              'properties': {
                'x': {'type': 'number'},
              },
            },
          },
        ],
        const [],
      );
      final a = await _pluginDir(
        'a',
        'function noop() return { ok = true } end',
        [
          {'name': 'noop', 'handler': 'noop'},
        ],
        const [LynAIPermissions.pluginCallFunction],
      );
      await provider.importDirectory(b.path);
      await provider.importDirectory(a.path);
      await provider.trustInstalledBuiltIn('b');
      await provider.trustInstalledBuiltIn('a');

      final result = await _callAcross(provider, 'a', 'b', 'double', {
        'x': 21,
      });
      expect(result['ok'], isTrue, reason: result.toString());
      expect(result['value'], 42);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('plugin.call requires plugins.callFunction on the caller', () async {
    SharedPreferences.setMockInitialValues({});
    final root = await Directory.systemTemp.createTemp('lynai_ic_perm_');
    try {
      final provider = PluginProvider(
        repository: PluginRepository(rootOverride: root),
      );
      final b = await _pluginDir(
        'b',
        'function double(args) args = args or {}; '
        'return { ok = true, value = (args.x or 0) * 2 } end',
        [
          {
            'name': 'double',
            'handler': 'double',
            'expose': true,
            'parameters': {'type': 'object', 'properties': {}},
          },
        ],
        const [],
      );
      final a = await _pluginDir(
        'a',
        'function noop() return { ok = true } end',
        [
          {'name': 'noop', 'handler': 'noop'},
        ],
        const [],
      );
      await provider.importDirectory(b.path);
      await provider.importDirectory(a.path);
      await provider.trustInstalledBuiltIn('b');
      await provider.trustInstalledBuiltIn('a');

      final result = await _callAcross(provider, 'a', 'b', 'double', {
        'x': 1,
      });
      expect(result['ok'], isFalse, reason: result.toString());
      expect(result['error'], contains('plugins.callFunction'));
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('plugin.call rejects functions that are not exposed', () async {
    SharedPreferences.setMockInitialValues({});
    final root = await Directory.systemTemp.createTemp('lynai_ic_expose_');
    try {
      final provider = PluginProvider(
        repository: PluginRepository(rootOverride: root),
      );
      final b = await _pluginDir(
        'b',
        'function hidden(args) args = args or {}; return { ok = true } end',
        [
          {
            'name': 'hidden',
            'handler': 'hidden',
            'parameters': {'type': 'object', 'properties': {}},
          },
        ],
        const [],
      );
      final a = await _pluginDir(
        'a',
        'function noop() return { ok = true } end',
        [
          {'name': 'noop', 'handler': 'noop'},
        ],
        const [LynAIPermissions.pluginCallFunction],
      );
      await provider.importDirectory(b.path);
      await provider.importDirectory(a.path);
      await provider.trustInstalledBuiltIn('b');
      await provider.trustInstalledBuiltIn('a');

      final result = await _callAcross(provider, 'a', 'b', 'hidden', const {});
      expect(result['ok'], isFalse, reason: result.toString());
      expect(result['error'], contains('未对外暴露'));
    } finally {
      await root.delete(recursive: true);
    }
  });
}
