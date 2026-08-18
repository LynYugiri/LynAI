import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/plugin.dart';
import 'package:lynai/providers/plugin_provider.dart';
import 'package:lynai/repositories/plugin_repository.dart';
import 'package:lynai/services/plugin_scaffold_service.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('lynai_manifest_edit_');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  PluginProvider buildProvider() =>
      PluginProvider(repository: PluginRepository(rootOverride: root));

  test('setManifest* rewrites plugin.json and reloads in memory', () async {
    final provider = buildProvider();
    final plugin = await provider.createPlugin(
      id: 'editable-plugin',
      name: '可编辑插件',
      version: '0.1.0',
      author: '',
      description: '',
      kind: PluginScaffoldKind.blank,
    );

    await provider.setManifestTools(plugin.id, [
      const PluginToolDefinition(
        name: 'greet',
        description: '打招呼',
        handler: 'greet',
        parameters: {
          'type': 'object',
          'properties': <String, dynamic>{},
        },
      ),
    ]);
    await provider.setManifestFunctions(plugin.id, [
      const PluginFunctionDefinition(
        name: 'helper',
        title: '辅助函数',
        handler: 'helper',
        expose: true,
      ),
    ]);
    await provider.setManifestCommands(plugin.id, [
      const PluginCommandDefinition(name: 'pick', title: '选择', handler: 'pick'),
    ]);
    await provider.setManifestSkills(plugin.id, [
      const PluginSkillDefinition(name: 'workflow', title: '工作流'),
    ]);
    await provider.setManifestFeaturePages(plugin.id, [
      const PluginFeaturePageDefinition(
        id: 'main',
        title: '主页',
        icon: '',
        entry: 'index.html',
      ),
    ]);
    await provider.setManifestSettings(plugin.id, [
      const PluginSettingDefinition(key: 'mode', type: 'string', title: '模式'),
    ]);

    final loaded = provider.pluginById(plugin.id)!;
    expect(loaded.manifest.tools.single.name, 'greet');
    expect(loaded.manifest.functions.single.name, 'helper');
    expect(loaded.manifest.functions.single.expose, isTrue);
    expect(loaded.manifest.commands.single.name, 'pick');
    expect(loaded.manifest.skills.single.name, 'workflow');
    expect(loaded.manifest.featurePages.single.id, 'main');
    expect(loaded.manifest.settings.single.key, 'mode');

    // 持久化到 plugin.json，重启后仍可读回。
    final raw = jsonDecode(
      await File('${plugin.path}/plugin.json').readAsString(),
    ) as Map<String, dynamic>;
    expect(raw['tools'], isA<List>());
    expect(raw['functions'], isA<List>());
    expect(raw['commands'], isA<List>());
    expect(raw['skills'], isA<List>());
    expect(raw['featurePages'], isA<List>());
    expect(raw['settings'], isA<List>());
  });

  test('setManifest* rejects invalid definitions', () async {
    final provider = buildProvider();
    final plugin = await provider.createPlugin(
      id: 'invalid-edit',
      name: '非法编辑',
      version: '0.1.0',
      author: '',
      description: '',
      kind: PluginScaffoldKind.blank,
    );

    await expectLater(
      provider.setManifestTools(plugin.id, [
        const PluginToolDefinition(
          name: '',
          description: '',
          handler: 'not a lua name!',
          parameters: {'type': 'object'},
        ),
      ]),
      throwsA(isA<Exception>()),
    );

    await expectLater(
      provider.setManifestFeaturePages(plugin.id, [
        const PluginFeaturePageDefinition(id: 'x', title: 'X', icon: '', entry: ''),
      ]),
      throwsA(isA<Exception>()),
    );
  });
}
