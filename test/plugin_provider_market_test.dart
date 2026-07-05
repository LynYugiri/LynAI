import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lynai/providers/plugin_provider.dart';
import 'package:lynai/repositories/plugin_repository.dart';

import 'support/fake_path_provider.dart';

void main() {
  Directory? pathProviderRoot;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    pathProviderRoot = await installFakePathProvider(
      'lynai_plugin_market_test_',
    );
  });

  tearDown(() async {
    final root = pathProviderRoot;
    pathProviderRoot = null;
    await deleteFakePathProviderRoot(root);
  });

  Future<Directory> createMiniPlugin(String id) async {
    final source = await Directory.systemTemp.createTemp('lynai_mini_plugin_');
    await File('${source.path}/main.lua').writeAsString('-- handler');
    await File('${source.path}/plugin.json').writeAsString(
      jsonEncode({
        'id': id,
        'name': 'Test Plugin $id',
        'version': '1.0.0',
        'entry': 'main.lua',
        'permissions': const <String>[],
      }),
    );
    return source;
  }

  test('uninstall removes plugin from provider', () async {
    final installedRoot = await Directory.systemTemp.createTemp(
      'lynai_uninstall_installed_',
    );
    try {
      final source = await createMiniPlugin('test-uninstall');
      final provider = PluginProvider(
        repository: PluginRepository(rootOverride: installedRoot),
      );
      await provider.importDirectory(source.path);

      expect(provider.pluginById('test-uninstall'), isNotNull);
      expect(provider.plugins.length, 1);

      await provider.uninstall('test-uninstall');

      expect(provider.pluginById('test-uninstall'), isNull);
      expect(provider.plugins.length, 0);

      if (await source.exists()) await source.delete(recursive: true);
    } finally {
      if (await installedRoot.exists()) {
        await installedRoot.delete(recursive: true);
      }
    }
  });

  test('uninstall is equivalent to deletePlugin', () async {
    final installedRoot = await Directory.systemTemp.createTemp(
      'lynai_uninstall_equiv_',
    );
    try {
      final source1 = await createMiniPlugin('test-equiv-1');
      final source2 = await createMiniPlugin('test-equiv-2');
      final provider = PluginProvider(
        repository: PluginRepository(rootOverride: installedRoot),
      );
      await provider.importDirectory(source1.path);
      await provider.importDirectory(source2.path);

      expect(provider.plugins.length, 2);

      await provider.uninstall('test-equiv-1');
      expect(provider.pluginById('test-equiv-1'), isNull);
      expect(provider.pluginById('test-equiv-2'), isNotNull);

      await provider.deletePlugin('test-equiv-2');
      expect(provider.pluginById('test-equiv-2'), isNull);
      expect(provider.plugins.length, 0);

      if (await source1.exists()) await source1.delete(recursive: true);
      if (await source2.exists()) await source2.delete(recursive: true);
    } finally {
      if (await installedRoot.exists()) {
        await installedRoot.delete(recursive: true);
      }
    }
  });

  test('uninstall on non-existent id is a no-op', () async {
    final installedRoot = await Directory.systemTemp.createTemp(
      'lynai_uninstall_noop_',
    );
    try {
      final provider = PluginProvider(
        repository: PluginRepository(rootOverride: installedRoot),
      );
      await provider.uninstall('does-not-exist');
      expect(provider.plugins.length, 0);
    } finally {
      if (await installedRoot.exists()) {
        await installedRoot.delete(recursive: true);
      }
    }
  });
}
