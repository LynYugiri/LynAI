import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lynai/providers/plugin_provider.dart';
import 'package:lynai/repositories/plugin_repository.dart';
import 'package:lynai/services/lynai_permission_definitions.dart';

void main() {
  test('auto-grant classification marks only public network as free', () {
    expect(
      isAutoGrantedPluginPermission(LynAIPermissions.networkPublic),
      isTrue,
    );
    expect(
      isAutoGrantedPluginPermission(LynAIPermissions.networkAccess),
      isFalse,
    );
    expect(isAutoGrantedPluginPermission(LynAIPermissions.notesRead), isFalse);
    expect(
      autoGrantedPluginPermissions(const [
        LynAIPermissions.networkPublic,
        LynAIPermissions.networkAccess,
        LynAIPermissions.notesRead,
      ]),
      {LynAIPermissions.networkPublic},
    );
  });

  test('third-party install auto-grants only auto-grant permissions', () async {
    SharedPreferences.setMockInitialValues({});
    final installedRoot = await Directory.systemTemp.createTemp(
      'lynai_autogrant_',
    );
    final source = await Directory.systemTemp.createTemp('lynai_autogrant_src_');
    try {
      await File('${source.path}/main.lua').writeAsString('-- handler');
      await File('${source.path}/plugin.json').writeAsString(
        jsonEncode({
          'id': 'sample',
          'name': 'Sample',
          'version': '1.0.0',
          'entry': 'main.lua',
          'permissions': [
            LynAIPermissions.networkPublic,
            LynAIPermissions.notesRead,
          ],
        }),
      );

      final provider = PluginProvider(
        repository: PluginRepository(rootOverride: installedRoot),
      );
      await provider.importDirectory(source.path);
      final plugin = provider.pluginById('sample')!;

      expect(
        plugin.grantedPermissions,
        contains(LynAIPermissions.networkPublic),
      );
      expect(
        plugin.grantedPermissions,
        isNot(contains(LynAIPermissions.notesRead)),
      );
    } finally {
      await installedRoot.delete(recursive: true);
      await source.delete(recursive: true);
    }
  });

  test('setGrantedPermissions keeps auto-grant permissions', () async {
    SharedPreferences.setMockInitialValues({});
    final installedRoot = await Directory.systemTemp.createTemp(
      'lynai_autogrant_set_',
    );
    final source = await Directory.systemTemp.createTemp(
      'lynai_autogrant_src2_',
    );
    try {
      await File('${source.path}/main.lua').writeAsString('-- handler');
      await File('${source.path}/plugin.json').writeAsString(
        jsonEncode({
          'id': 'sample',
          'name': 'Sample',
          'version': '1.0.0',
          'entry': 'main.lua',
          'permissions': [
            LynAIPermissions.networkPublic,
            LynAIPermissions.notesRead,
          ],
        }),
      );

      final provider = PluginProvider(
        repository: PluginRepository(rootOverride: installedRoot),
      );
      await provider.importDirectory(source.path);
      final pluginId = provider.pluginById('sample')!.id;

      await provider.setGrantedPermissions(pluginId, const []);
      final plugin = provider.pluginById(pluginId)!;
      expect(
        plugin.grantedPermissions,
        contains(LynAIPermissions.networkPublic),
      );
      expect(
        plugin.grantedPermissions,
        isNot(contains(LynAIPermissions.notesRead)),
      );
    } finally {
      await installedRoot.delete(recursive: true);
      await source.delete(recursive: true);
    }
  });
}
