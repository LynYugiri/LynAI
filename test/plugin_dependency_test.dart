import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lynai/models/plugin.dart';
import 'package:lynai/providers/plugin_provider.dart';
import 'package:lynai/repositories/plugin_repository.dart';
import 'package:lynai/services/lynai_call_identity.dart';
import 'package:lynai/services/lynai_function_service.dart';
import 'package:lynai/services/lynai_permission_definitions.dart';

Map<String, dynamic> _manifest({
  String id = 'a',
  Map<String, String> dependencies = const {},
}) {
  return {
    'id': id,
    'name': id,
    'version': '1.0.0',
    'entry': 'main.lua',
    'permissions': const [],
    'dependencies': dependencies,
  };
}

Future<Directory> _pluginDir(
  String id,
  String lua, {
  String version = '1.0.0',
  List<Map<String, dynamic>>? functions,
  List<String> permissions = const [],
  Map<String, String> dependencies = const {},
}) async {
  final dir = await Directory.systemTemp.createTemp('lynai_dep_${id}_');
  await File('${dir.path}/main.lua').writeAsString(lua);
  await File('${dir.path}/plugin.json').writeAsString(
    jsonEncode({
      'id': id,
      'name': id,
      'version': version,
      'entry': 'main.lua',
      'permissions': permissions,
      'functions': ?functions,
      if (dependencies.isNotEmpty) 'dependencies': dependencies,
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
  test('plugin manifest parses dependencies and validates constraints', () {
    final manifest = PluginManifest.fromJson(
      _manifest(dependencies: {'b': '>=1.0.0 <2.0.0'}),
    );
    expect(manifest.dependencies['b'], '>=1.0.0 <2.0.0');
    expect(manifest.validate(), isNull);
    expect(manifest.toJson()['dependencies'], {'b': '>=1.0.0 <2.0.0'});

    final invalid = PluginManifest.fromJson(
      _manifest(dependencies: {'b': 'not-a-version'}),
    );
    expect(invalid.validate(), contains('版本约束不合法'));

    final selfDependency = PluginManifest.fromJson(
      _manifest(id: 'a', dependencies: {'a': '*'}),
    );
    expect(selfDependency.validate(), contains('不能依赖自身'));
  });

  test('pluginVersionMatches supports common semver constraints', () {
    expect(pluginVersionMatches('1.2.3', '^1.0.0'), isTrue);
    expect(pluginVersionMatches('2.0.0', '^1.0.0'), isFalse);
    expect(pluginVersionMatches('1.2.3', '>=1.0.0 <2.0.0'), isTrue);
    expect(pluginVersionMatches('2.0.0', '>=1.0.0 <2.0.0'), isFalse);
    expect(pluginVersionMatches('1.0.0', '=1.0.0'), isTrue);
    expect(pluginVersionMatches('1.0.0', '*'), isTrue);
    expect(pluginVersionMatches('1.0.0', 'bad'), isFalse);
  });

  test(
    'enable-time dependency check blocks missing, disabled and version mismatch',
    () async {
      SharedPreferences.setMockInitialValues({});
      final root = await Directory.systemTemp.createTemp('lynai_dep_enable_');
      try {
        final provider = PluginProvider(
          repository: PluginRepository(rootOverride: root),
        );

        final b = await _pluginDir(
          'b',
          'function double(args) args = args or {}; '
              'return { ok = true, value = (args.x or 0) * 2 } end',
          functions: [
            {
              'name': 'double',
              'handler': 'double',
              'expose': true,
              'parameters': {'type': 'object', 'properties': {}},
            },
          ],
        );
        final a = await _pluginDir(
          'a',
          'function noop() return { ok = true } end',
          permissions: const [LynAIPermissions.pluginCallFunction],
          dependencies: {'b': '>=1.0.0'},
        );
        final missing = await _pluginDir(
          'missing-dep',
          'function noop() return { ok = true } end',
          dependencies: {'ghost': '*'},
        );
        final mismatched = await _pluginDir(
          'mismatched',
          'function noop() return { ok = true } end',
          dependencies: {'b': '^2.0.0'},
        );

        await provider.importDirectory(b.path);
        await provider.importDirectory(a.path);
        await provider.importDirectory(missing.path);
        await provider.importDirectory(mismatched.path);

        // Missing dependency plugin.
        await expectLater(
          provider.setEnabled('missing-dep', true),
          throwsA(predicate((e) => e.toString().contains('缺少依赖插件 ghost'))),
        );

        // Dependency installed but not enabled yet.
        await expectLater(
          provider.setEnabled('a', true),
          throwsA(predicate((e) => e.toString().contains('未启用或加载失败'))),
        );

        await provider.setEnabled('b', true);

        // Version mismatch.
        await expectLater(
          provider.setEnabled('mismatched', true),
          throwsA(predicate((e) => e.toString().contains('版本不满足'))),
        );

        // Satisfied dependency enables successfully.
        await provider.setEnabled('a', true);
        expect(provider.pluginById('a')!.enabled, isTrue);
      } finally {
        await root.delete(recursive: true);
      }
    },
  );

  test('disabling a dependency used by an enabled plugin is blocked', () async {
    SharedPreferences.setMockInitialValues({});
    final root = await Directory.systemTemp.createTemp('lynai_dep_disable_');
    try {
      final provider = PluginProvider(
        repository: PluginRepository(rootOverride: root),
      );

      final b = await _pluginDir(
        'b',
        'function double(args) args = args or {}; '
            'return { ok = true, value = (args.x or 0) * 2 } end',
        functions: [
          {
            'name': 'double',
            'handler': 'double',
            'expose': true,
            'parameters': {'type': 'object', 'properties': {}},
          },
        ],
      );
      final a = await _pluginDir(
        'a',
        'function noop() return { ok = true } end',
        permissions: const [LynAIPermissions.pluginCallFunction],
        dependencies: {'b': '>=1.0.0'},
      );

      await provider.importDirectory(b.path);
      await provider.importDirectory(a.path);
      await provider.setEnabled('b', true);
      await provider.setEnabled('a', true);

      await expectLater(
        provider.setEnabled('b', false),
        throwsA(predicate((e) => e.toString().contains('被其他已启用插件依赖'))),
      );
      expect(provider.pluginById('b')!.enabled, isTrue);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test(
    'plugin.call validates declared dependency version and function requires',
    () async {
      SharedPreferences.setMockInitialValues({});
      final root = await Directory.systemTemp.createTemp('lynai_dep_runtime_');
      try {
        final provider = PluginProvider(
          repository: PluginRepository(rootOverride: root),
        );

        final b = await _pluginDir(
          'b',
          'function double(args) args = args or {}; '
              'return { ok = true, value = (args.x or 0) * 2 } end',
          functions: [
            {
              'name': 'double',
              'handler': 'double',
              'expose': true,
              'requires': [LynAIPermissions.notesRead],
              'parameters': {
                'type': 'object',
                'properties': {
                  'x': {'type': 'number'},
                },
              },
            },
          ],
        );
        final caller = await _pluginDir(
          'caller',
          'function noop() return { ok = true } end',
          permissions: const [LynAIPermissions.pluginCallFunction],
          dependencies: {'b': '>=1.0.0'},
        );
        final noGrant = await _pluginDir(
          'no-grant',
          'function noop() return { ok = true } end',
          permissions: const [LynAIPermissions.pluginCallFunction],
          dependencies: {'b': '>=1.0.0'},
        );
        final noDependency = await _pluginDir(
          'no-dependency',
          'function noop() return { ok = true } end',
          permissions: const [
            LynAIPermissions.pluginCallFunction,
            LynAIPermissions.notesRead,
          ],
        );
        final mismatched = await _pluginDir(
          'mismatched',
          'function noop() return { ok = true } end',
          permissions: const [LynAIPermissions.pluginCallFunction],
          dependencies: {'b': '^2.0.0'},
        );

        await provider.importDirectory(b.path);
        await provider.importDirectory(caller.path);
        await provider.importDirectory(noGrant.path);
        await provider.importDirectory(noDependency.path);
        await provider.importDirectory(mismatched.path);
        await provider.setEnabled('b', true);
        await provider.setEnabled('caller', true);
        await provider.setEnabled('no-grant', true);
        await provider.setEnabled('no-dependency', true);

        final callerPlugin = provider.pluginById('caller')!;
        final listable = provider.listablePermissionIds(callerPlugin);
        expect(
          listable,
          containsAll([
            LynAIPermissions.pluginCallFunction,
            LynAIPermissions.notesRead,
          ]),
        );
        await provider.setGrantedPermissions(
          'caller',
          listable.toList(growable: false),
        );
        await provider.setGrantedPermissions('no-grant', [
          LynAIPermissions.pluginCallFunction,
        ]);
        await provider.setGrantedPermissions('no-dependency', [
          LynAIPermissions.pluginCallFunction,
          LynAIPermissions.notesRead,
        ]);
        await provider.setGrantedPermissions('mismatched', [
          LynAIPermissions.pluginCallFunction,
        ]);

        final success = await _callAcross(provider, 'caller', 'b', 'double', {
          'x': 21,
        });
        expect(success['ok'], isTrue, reason: success.toString());
        expect(success['value'], 42);

        final missingPermission = await _callAcross(
          provider,
          'no-grant',
          'b',
          'double',
          {'x': 1},
        );
        expect(
          missingPermission['ok'],
          isFalse,
          reason: missingPermission.toString(),
        );
        expect(missingPermission['error'], contains('notes:read'));

        // 未声明依赖的插件仍可调用公开函数，只要权限满足。
        final noDependencyCall = await _callAcross(
          provider,
          'no-dependency',
          'b',
          'double',
          {'x': 2},
        );
        expect(
          noDependencyCall['ok'],
          isTrue,
          reason: noDependencyCall.toString(),
        );
        expect(noDependencyCall['value'], 4);

        // 声明了依赖版本约束时，运行时会校验目标插件版本。
        final versionMismatch = await _callAcross(
          provider,
          'mismatched',
          'b',
          'double',
          {'x': 1},
        );
        expect(
          versionMismatch['ok'],
          isFalse,
          reason: versionMismatch.toString(),
        );
        expect(versionMismatch['error'], contains('版本不满足'));
      } finally {
        await root.delete(recursive: true);
      }
    },
  );
}
