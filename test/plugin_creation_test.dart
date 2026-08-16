import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/plugin.dart';
import 'package:lynai/providers/plugin_provider.dart';
import 'package:lynai/repositories/plugin_repository.dart';
import 'package:lynai/services/plugin_scaffold_service.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('lynai_plugin_create_');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('creates a disabled plugin from a scaffold template', () async {
    final provider = PluginProvider(
      repository: PluginRepository(rootOverride: root),
    );
    final plugin = await provider.createPlugin(
      id: 'created-plugin',
      name: '创建的插件',
      version: '0.1.0',
      author: 'LynAI',
      description: '测试创建',
      kind: PluginScaffoldKind.luaTool,
    );

    expect(plugin.id, 'created-plugin');
    expect(plugin.enabled, isFalse);
    expect(plugin.devState, PluginDevState.draft);
    expect(plugin.manifest.tools, hasLength(1));
    expect(await File('${plugin.path}/main.lua').exists(), isTrue);
    expect(provider.pluginById('created-plugin'), isNotNull);

    await provider.setDevState(plugin.id, PluginDevState.testing);
    expect(provider.pluginById(plugin.id)!.devState, PluginDevState.testing);
    await provider.setDevState(plugin.id, PluginDevState.active);
    expect(provider.pluginById(plugin.id)!.devState, PluginDevState.active);
  });

  test('rejects duplicate plugin id', () async {
    final provider = PluginProvider(
      repository: PluginRepository(rootOverride: root),
    );
    await provider.createPlugin(
      id: 'dup',
      name: '第一个',
      version: '0.1.0',
      author: '',
      description: '',
      kind: PluginScaffoldKind.blank,
    );
    expect(
      () => provider.createPlugin(
        id: 'dup',
        name: '第二个',
        version: '0.1.0',
        author: '',
        description: '',
        kind: PluginScaffoldKind.blank,
      ),
      throwsA(isA<Exception>()),
    );
  });
}
