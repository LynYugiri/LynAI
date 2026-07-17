import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/plugin.dart';
import 'package:lynai/providers/plugin_provider.dart';
import 'package:lynai/repositories/plugin_repository.dart';

void main() {
  late Directory root;
  late Directory source;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('lynai_plugin_queue_');
    source = Directory('${root.path}/source');
    await source.create(recursive: true);
    await File('${source.path}/plugin.json').writeAsString('''
{
  "id": "queued-plugin",
  "name": "Queued Plugin",
  "entry": "main.lua",
  "permissions": ["network:access"]
}
''');
    await File('${source.path}/main.lua').writeAsString('function noop() end');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test(
    'enabled and permissions mutations persist without lost updates',
    () async {
      final repository = _ReorderingPluginRepository(
        rootOverride: Directory('${root.path}/plugins'),
      );
      final provider = PluginProvider(repository: repository);
      await provider.importDirectory(source.path);
      repository.reorderMetadataSaves = true;

      await Future.wait([
        provider.setEnabled('queued-plugin', true),
        provider.setGrantedPermissions('queued-plugin', const [
          'network:access',
        ]),
      ]);

      final reloaded = PluginProvider(
        repository: PluginRepository(
          rootOverride: Directory('${root.path}/plugins'),
        ),
      );
      await reloaded.load();
      final plugin = reloaded.pluginById('queued-plugin')!;
      expect(plugin.enabled, isTrue);
      expect(plugin.grantedPermissions, ['network:access']);
    },
  );

  test(
    'settings and private storage retain concurrent different keys',
    () async {
      final repository = _ReorderingPluginRepository(
        rootOverride: Directory('${root.path}/plugins'),
      );
      final provider = PluginProvider(repository: repository);
      await provider.importDirectory(source.path);
      repository.reorderDataLoads = true;

      await Future.wait([
        provider.updateSetting('queued-plugin', 'theme', 'dark'),
        provider.updateSetting('queued-plugin', 'locale', 'zh-CN'),
        provider.writeStorageValue('queued-plugin', 'token', 'one'),
        provider.writeStorageValue('queued-plugin', 'counter', 2),
      ]);

      final reloaded = PluginProvider(
        repository: PluginRepository(
          rootOverride: Directory('${root.path}/plugins'),
        ),
      );
      expect(await reloaded.loadSettings('queued-plugin'), {
        'theme': 'dark',
        'locale': 'zh-CN',
      });
      expect(await reloaded.loadStorage('queued-plugin'), {
        'token': 'one',
        'counter': 2,
      });
    },
  );

  test(
    'uninstall waits for queued metadata and cannot be resurrected',
    () async {
      final repository = _BlockingPluginRepository(
        rootOverride: Directory('${root.path}/plugins'),
      );
      final provider = PluginProvider(repository: repository);
      await provider.importDirectory(source.path);
      repository.blockNextMetadataSave();

      final enabled = provider.setEnabled('queued-plugin', true);
      await repository.metadataSaveStarted.future;
      final uninstall = provider.uninstall('queued-plugin');
      repository.releaseMetadataSave();
      await Future.wait([enabled, uninstall]);

      expect(provider.pluginById('queued-plugin'), isNull);
      expect(
        (await repository.pluginDirectory('queued-plugin')).existsSync(),
        isFalse,
      );
      final reloaded = PluginProvider(
        repository: PluginRepository(
          rootOverride: Directory('${root.path}/plugins'),
        ),
      );
      await reloaded.load();
      expect(reloaded.pluginById('queued-plugin'), isNull);
    },
  );

  test(
    'uninstall removes queued settings and storage without revival',
    () async {
      final repository = _BlockingPluginRepository(
        rootOverride: Directory('${root.path}/plugins'),
      );
      final provider = PluginProvider(repository: repository);
      await provider.importDirectory(source.path);
      repository.blockNextSettingsSave();

      final setting = provider.updateSetting('queued-plugin', 'theme', 'dark');
      await repository.settingsSaveStarted.future;
      final storage = provider.writeStorageValue(
        'queued-plugin',
        'token',
        'one',
      );
      final uninstall = provider.uninstall('queued-plugin');
      repository.releaseSettingsSave();
      await Future.wait([setting, storage, uninstall]);

      expect(provider.pluginById('queued-plugin'), isNull);
      expect(
        File('${root.path}/plugins/settings/queued-plugin.json').existsSync(),
        isFalse,
      );
      expect(
        File('${root.path}/plugins/storage/queued-plugin.json').existsSync(),
        isFalse,
      );
      await expectLater(
        provider.updateSetting('queued-plugin', 'late', true),
        throwsException,
      );
      await expectLater(
        provider.writeStorageValue('queued-plugin', 'late', true),
        throwsException,
      );
    },
  );

  test(
    'queued market import applies before later permissions mutation',
    () async {
      final repository = _BlockingPluginRepository(
        rootOverride: Directory('${root.path}/plugins'),
      );
      final provider = PluginProvider(repository: repository);
      await provider.importDirectory(source.path);
      repository.blockNextImport();
      final updatedBytes = _pluginZip(version: '2.0.0');

      final update = provider.importZipBytes(updatedBytes);
      await repository.importStarted.future;
      final permissions = provider.setGrantedPermissions(
        'queued-plugin',
        const ['network:access'],
      );
      repository.releaseImport();
      await Future.wait([update, permissions]);

      final plugin = provider.pluginById('queued-plugin')!;
      expect(plugin.manifest.version, '2.0.0');
      expect(plugin.grantedPermissions, ['network:access']);
      final reloaded = PluginProvider(
        repository: PluginRepository(
          rootOverride: Directory('${root.path}/plugins'),
        ),
      );
      await reloaded.load();
      expect(reloaded.pluginById('queued-plugin')!.manifest.version, '2.0.0');
      expect(reloaded.pluginById('queued-plugin')!.grantedPermissions, [
        'network:access',
      ]);
    },
  );

  test(
    'multi-manifest ZIP leaves installed plugin and metadata unchanged',
    () async {
      final repository = PluginRepository(
        rootOverride: Directory('${root.path}/plugins'),
      );
      final provider = PluginProvider(repository: repository);
      await provider.importDirectory(source.path);
      await provider.setEnabled('queued-plugin', true);
      final installed = provider.pluginById('queued-plugin')!;
      final installedLua = File('${installed.path}/main.lua');
      final metadata = File('${root.path}/plugins/installed_plugins.json');
      final oldLua = await installedLua.readAsString();
      final oldMetadata = await metadata.readAsString();
      final archive = Archive()
        ..addFile(
          ArchiveFile.string(
            'plugin.json',
            jsonEncode({'id': 'other-plugin', 'name': 'Other Plugin'}),
          ),
        )
        ..addFile(
          ArchiveFile.string(
            'wrapped/plugin.json',
            jsonEncode({'id': 'queued-plugin', 'name': 'Replaced Plugin'}),
          ),
        )
        ..addFile(ArchiveFile.string('wrapped/main.lua', 'replaced'));

      await expectLater(
        provider.importZipBytes(ZipEncoder().encode(archive)),
        throwsA(isA<FormatException>()),
      );

      expect(await installedLua.readAsString(), oldLua);
      expect(await metadata.readAsString(), oldMetadata);
      expect(provider.pluginById('queued-plugin')!.enabled, isTrue);
      expect(
        provider.pluginById('queued-plugin')!.manifest.name,
        'Queued Plugin',
      );
      expect(
        (await repository.pluginDirectory('other-plugin')).existsSync(),
        isFalse,
      );
    },
  );
}

List<int> _pluginZip({required String version}) {
  final archive = Archive()
    ..addFile(
      ArchiveFile.string(
        'plugin.json',
        jsonEncode({
          'id': 'queued-plugin',
          'name': 'Queued Plugin',
          'version': version,
          'entry': 'main.lua',
          'permissions': ['network:access'],
        }),
      ),
    )
    ..addFile(ArchiveFile.string('main.lua', 'function noop() end'));
  return ZipEncoder().encode(archive);
}

class _ReorderingPluginRepository extends PluginRepository {
  _ReorderingPluginRepository({required super.rootOverride});

  bool reorderMetadataSaves = false;
  bool reorderDataLoads = false;
  int _metadataSaveCount = 0;
  int _settingsLoadCount = 0;
  int _storageLoadCount = 0;

  @override
  Future<void> saveInstalledPlugins(List<InstalledPlugin> plugins) async {
    if (reorderMetadataSaves && _metadataSaveCount++ == 0) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    await super.saveInstalledPlugins(plugins);
  }

  @override
  Future<Map<String, dynamic>> loadPluginSettings(String pluginId) async {
    if (reorderDataLoads) {
      final call = _settingsLoadCount++;
      await Future<void>.delayed(Duration(milliseconds: call == 0 ? 50 : 5));
    }
    return super.loadPluginSettings(pluginId);
  }

  @override
  Future<Map<String, dynamic>> loadPluginStorage(String pluginId) async {
    if (reorderDataLoads) {
      final call = _storageLoadCount++;
      await Future<void>.delayed(Duration(milliseconds: call == 0 ? 50 : 5));
    }
    return super.loadPluginStorage(pluginId);
  }
}

class _BlockingPluginRepository extends PluginRepository {
  _BlockingPluginRepository({required super.rootOverride});

  Completer<void> metadataSaveStarted = Completer<void>();
  Completer<void> settingsSaveStarted = Completer<void>();
  Completer<void> importStarted = Completer<void>();
  Completer<void>? _metadataSaveRelease;
  Completer<void>? _settingsSaveRelease;
  Completer<void>? _importRelease;

  void blockNextMetadataSave() {
    metadataSaveStarted = Completer<void>();
    _metadataSaveRelease = Completer<void>();
  }

  void releaseMetadataSave() {
    _metadataSaveRelease!.complete();
    _metadataSaveRelease = null;
  }

  void blockNextSettingsSave() {
    settingsSaveStarted = Completer<void>();
    _settingsSaveRelease = Completer<void>();
  }

  void releaseSettingsSave() {
    _settingsSaveRelease!.complete();
    _settingsSaveRelease = null;
  }

  void blockNextImport() {
    importStarted = Completer<void>();
    _importRelease = Completer<void>();
  }

  void releaseImport() {
    _importRelease!.complete();
    _importRelease = null;
  }

  @override
  Future<void> saveInstalledPlugins(List<InstalledPlugin> plugins) async {
    final release = _metadataSaveRelease;
    if (release != null) {
      metadataSaveStarted.complete();
      await release.future;
    }
    await super.saveInstalledPlugins(plugins);
  }

  @override
  Future<void> savePluginSettings(
    String pluginId,
    Map<String, dynamic> settings,
  ) async {
    final release = _settingsSaveRelease;
    if (release != null) {
      settingsSaveStarted.complete();
      await release.future;
    }
    await super.savePluginSettings(pluginId, settings);
  }

  @override
  Future<InstalledPlugin> importDirectory(
    String sourcePath, {
    PluginManifest? manifest,
  }) async {
    final release = _importRelease;
    if (release != null) {
      importStarted.complete();
      await release.future;
    }
    return super.importDirectory(sourcePath, manifest: manifest);
  }
}
