import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/plugin.dart';
import 'package:lynai/providers/plugin_provider.dart';
import 'package:lynai/repositories/plugin_repository.dart';
import 'package:lynai/services/storage_v2_service.dart';
import 'package:lynai/services/storage_v2_upgrade_service.dart';

void main() {
  group('plugin content sync', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('lynai_plugin_sync_');
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    test('built-ins include overlays but exclude bundled source', () async {
      final repo = PluginRepository(rootOverride: Directory('${root.path}/p'));
      final plugin = await _install(repo, 'status-dashboard');
      await repo.writePluginTextFile(plugin, 'status.css', 'custom');

      final rows = await repo.buildSyncRows(plugin);
      final paths = rows.map((row) => row['path']).whereType<String>().toSet();

      expect(paths, contains('status.css'));
      expect(paths, isNot(contains('plugin.json')));
      expect(paths, isNot(contains('defaults/main.lua')));
      expect(paths, isNot(contains('main.lua')));
      expect(paths, isNot(contains('config.schema.json')));
    });

    test(
      'third-party roundtrip clears local grants and requires review',
      () async {
        final sourceRepo = PluginRepository(
          rootOverride: Directory('${root.path}/source_plugins'),
        );
        final source = await _install(sourceRepo, 'third-party');
        await sourceRepo.writePluginTextFile(source, 'editable.txt', 'changed');
        final rows = await sourceRepo.buildSyncRows(source);

        final targetStorage = StorageV2Service(
          rootDirectory: Directory('${root.path}/target_storage'),
        );
        await StorageV2UpgradeService(storageV2: targetStorage).ensureReady();
        await targetStorage.activateSyncScope(
          'server|user',
          deviceId: 'device-b',
        );
        await targetStorage.replacePluginSyncRows('third-party', rows);
        final targetRepo = PluginRepository(
          rootOverride: Directory('${root.path}/target_plugins'),
        );
        for (final row in rows) {
          final hash = row['sha256'] as String?;
          if (hash != null) {
            await targetRepo.installSyncBlob(
              hash,
              await sourceRepo.readSyncBlob(hash),
            );
          }
        }
        final provider = PluginProvider(
          repository: targetRepo,
          storageV2: targetStorage,
        );
        await provider.applyRemoteSync('server|user');

        final restored = provider.pluginById('third-party')!;
        expect(restored.enabled, isFalse);
        expect(restored.needsReview, isTrue);
        expect(restored.grantedPermissions, isEmpty);
        expect(restored.enabledTools, isEmpty);
        expect(restored.enabledFunctions, isEmpty);
        expect(restored.enabledSkills, isEmpty);
        expect(restored.enabledFeaturePages, isEmpty);
        expect(
          await provider.readFile('third-party', 'editable.txt'),
          'changed',
        );
        expect(
          File('${restored.path}/config.schema.json').existsSync(),
          isTrue,
        );
        await expectLater(
          provider.setEnabled('third-party', true),
          throwsException,
        );

        await targetStorage.close();
      },
    );

    test('settings-only remote apply preserves local trust state', () async {
      final repo = PluginRepository(rootOverride: Directory('${root.path}/p'));
      final storage = StorageV2Service(
        rootDirectory: Directory('${root.path}/storage'),
      );
      await StorageV2UpgradeService(storageV2: storage).ensureReady();
      await storage.activateSyncScope('server|user', deviceId: 'device-a');
      final provider = PluginProvider(repository: repo, storageV2: storage);
      await provider.importDirectory((await _source('trusted')).path);
      await provider.markReviewed('trusted');
      await provider.setGrantedPermissions('trusted', const ['network']);
      await provider.setEnabled('trusted', true);
      final before = provider.pluginById('trusted')!;
      final rows = await repo.buildSyncRows(before);
      final settings = rows.singleWhere(
        (row) => row['domain'] == 'plugin_settings',
      );
      final remoteSettings = utf8.encode('{"theme":"remote"}');
      final remoteHash = await repo.storeSyncBlob(remoteSettings);
      settings['sha256'] = remoteHash;
      settings['size'] = remoteSettings.length;
      await storage.replacePluginSyncRows('trusted', rows);

      await provider.applyRemoteSync('server|user');

      final after = provider.pluginById('trusted')!;
      expect(after.enabled, isTrue);
      expect(after.needsReview, isFalse);
      expect(after.grantedPermissions, ['network']);
      expect(after.enabledTools, before.enabledTools);
      expect(await provider.loadSettings('trusted'), {'theme': 'remote'});
      await storage.close();
    });

    test('third-party package without versioned marker fails closed', () async {
      final repo = PluginRepository(rootOverride: Directory('${root.path}/p'));
      final original = await _install(repo, 'third-party');
      await File('${original.path}/marker.txt').writeAsString('old');
      final storage = StorageV2Service(
        rootDirectory: Directory('${root.path}/storage'),
      );
      await StorageV2UpgradeService(storageV2: storage).ensureReady();
      await storage.activateSyncScope('server|user', deviceId: 'device-a');
      final provider = PluginProvider(repository: repo, storageV2: storage);
      await provider.importDirectory((await _source('third-party')).path);
      await File('${original.path}/marker.txt').writeAsString('old');
      final rows = await repo.buildSyncRows(
        provider.pluginById('third-party')!,
      );
      await storage.replacePluginSyncRows(
        'third-party',
        rows.where((row) => row['kind'] != 'package').toList(),
      );

      await provider.applyRemoteSync('server|user');

      expect(await File('${original.path}/marker.txt').readAsString(), 'old');
      expect(provider.pluginById('third-party'), isNotNull);
      await storage.close();
    });

    test(
      'exact allowlist rejects undeclared file and preserves install',
      () async {
        final repo = PluginRepository(
          rootOverride: Directory('${root.path}/p'),
        );
        final original = await _install(repo, 'third-party');
        await File('${original.path}/marker.txt').writeAsString('old');
        final rows = await repo.buildSyncRows(original);
        final extraBytes = utf8.encode('undeclared');
        final extraHash = await repo.storeSyncBlob(extraBytes);
        final marker = rows.singleWhere((row) => row['kind'] == 'package');
        rows.add({
          'id': 'third-party/extra.lua',
          'pluginId': 'third-party',
          'path': 'extra.lua',
          'sha256': extraHash,
          'size': extraBytes.length,
          'packageVersion': marker['packageVersion'],
          'kind': 'content',
          'builtIn': false,
        });
        final storage = StorageV2Service(
          rootDirectory: Directory('${root.path}/storage'),
        );
        await StorageV2UpgradeService(storageV2: storage).ensureReady();
        await storage.activateSyncScope('server|user', deviceId: 'device-a');
        await storage.replacePluginSyncRows('third-party', rows);
        final provider = PluginProvider(repository: repo, storageV2: storage);
        await provider.load();

        await provider.applyRemoteSync('server|user');

        expect(await File('${original.path}/marker.txt').readAsString(), 'old');
        expect(File('${original.path}/extra.lua').existsSync(), isFalse);
        await storage.close();
      },
    );

    test('secret-like config keys never enter cloud payload', () async {
      final repo = PluginRepository(rootOverride: Directory('${root.path}/p'));
      final plugin = await _install(repo, 'third-party');
      await repo.writePluginJsonFile(plugin, plugin.manifest.config.path, {
        'endpoint': 'https://example.test',
        'apiToken': 'nope',
        'nested': {'password': 'nope', 'theme': 'dark'},
      });

      final rows = await repo.buildSyncRows(plugin);
      final config = rows.singleWhere(
        (row) => row['domain'] == 'plugin_config',
      );
      final decoded =
          jsonDecode(
                utf8.decode(
                  await repo.readSyncBlob(config['sha256'] as String),
                ),
              )
              as Map;

      expect(decoded['endpoint'], 'https://example.test');
      expect(decoded, isNot(contains('apiToken')));
      expect(decoded['nested'], {'theme': 'dark'});
    });

    test('ordinary plugin representation excludes private artifacts', () async {
      final repo = PluginRepository(rootOverride: Directory('${root.path}/p'));
      final plugin = await _install(repo, 'third-party');
      await File('${plugin.path}/.env').writeAsString('API_KEY=nope');
      await File('${plugin.path}/private.pem').writeAsString('private');
      await File('${plugin.path}/credentials.json').writeAsString('{}');
      await File('${plugin.path}/cache.db').writeAsString('cache');
      await repo.savePluginSettings('third-party', {
        'Authorization': 'Bearer settings-secret',
        'theme': 'dark',
      });
      await repo.savePluginStorage('third-party', {
        'Authorization': 'Bearer x',
      });

      final rows = await repo.buildSyncRows(plugin);
      final paths = rows.map((row) => row['path']).whereType<String>().toSet();
      final encoded = jsonEncode(rows);

      expect(paths, isNot(contains('.env')));
      expect(paths, isNot(contains('private.pem')));
      expect(paths, isNot(contains('credentials.json')));
      expect(paths, isNot(contains('cache.db')));
      expect(rows.any((row) => row['domain'] == 'plugin_storage'), isFalse);
      expect(encoded, isNot(contains('Authorization')));
      expect(encoded, isNot(contains('settings-secret')));
      expect(encoded, isNot(contains('API_KEY')));
    });

    test('malicious path is rejected and old install is preserved', () async {
      final repo = PluginRepository(rootOverride: Directory('${root.path}/p'));
      final original = await _install(repo, 'third-party');
      await File('${original.path}/marker.txt').writeAsString('old');
      final manifest = utf8.encode(jsonEncode(original.manifest.toJson()));

      await expectLater(
        repo.restorePluginDirectory('third-party', {
          'plugin.json': manifest,
          '../escape.lua': utf8.encode('bad'),
        }),
        throwsStateError,
      );

      expect(await File('${original.path}/marker.txt').readAsString(), 'old');
      expect(File('${root.path}/escape.lua').existsSync(), isFalse);
    });

    test(
      'malicious plugin ID cannot write or delete outside plugin roots',
      () async {
        final pluginsRoot = Directory('${root.path}/plugins');
        final repo = PluginRepository(rootOverride: pluginsRoot);
        final outsideDirectory = Directory('${root.path}/outside');
        final outsideSettings = File('${root.path}/escape.json');
        await outsideDirectory.create();
        await File('${outsideDirectory.path}/keep.txt').writeAsString('keep');
        await outsideSettings.writeAsString('keep');
        final manifest = utf8.encode(
          jsonEncode({
            'id': '../../outside',
            'name': 'malicious',
            'version': '1.0.0',
            'entry': 'main.lua',
          }),
        );

        await expectLater(
          repo.restorePluginDirectory('../../outside', {
            'plugin.json': manifest,
            'main.lua': utf8.encode('return {}'),
          }),
          throwsArgumentError,
        );
        await expectLater(
          repo.savePluginSettings('../../escape', const {'owned': true}),
          throwsArgumentError,
        );
        await expectLater(
          repo.deletePluginDirectory('../../outside'),
          throwsArgumentError,
        );
        await expectLater(
          repo.deletePluginDataFiles('../../escape'),
          throwsArgumentError,
        );

        expect(
          await File('${outsideDirectory.path}/keep.txt').readAsString(),
          'keep',
        );
        expect(await outsideSettings.readAsString(), 'keep');
        expect(await pluginsRoot.exists(), isFalse);
      },
    );

    test('plugin uninstall emits an explicit deleted marker', () async {
      final storage = StorageV2Service(
        rootDirectory: Directory('${root.path}/storage'),
      );
      await StorageV2UpgradeService(storageV2: storage).ensureReady();
      await storage.activateSyncScope('server|user', deviceId: 'device-a');
      final repo = PluginRepository(rootOverride: Directory('${root.path}/p'));
      final provider = PluginProvider(repository: repo, storageV2: storage);
      await provider.importDirectory((await _source('p')).path);
      await provider.deletePlugin('p');

      final outbox = await storage.loadSyncOutbox('server|user');
      final marker = outbox.singleWhere(
        (entry) =>
            entry.table == 'plugin_files' &&
            entry.recordId == 'p' &&
            entry.op == 'upsert',
      );
      expect(marker.data?['state'], 'deleted');
      expect(marker.data?['manifestVersion'], 1);
      await storage.close();
    });

    test('explicit remote tombstone uninstalls a package', () async {
      final repo = PluginRepository(rootOverride: Directory('${root.path}/p'));
      final storage = StorageV2Service(
        rootDirectory: Directory('${root.path}/storage'),
      );
      await StorageV2UpgradeService(storageV2: storage).ensureReady();
      await storage.activateSyncScope('server|user', deviceId: 'device-a');
      final provider = PluginProvider(repository: repo, storageV2: storage);
      await provider.importDirectory((await _source('p')).path);
      await repo.saveInstalledPlugins([
        provider
            .pluginById('p')!
            .copyWith(syncedOrigin: true, syncOriginScope: 'server|user'),
      ]);
      await provider.load();
      expect(provider.pluginById('p'), isNotNull);
      await storage.replacePluginSyncRows('p', [
        repo.buildDeletedSyncMarker('p'),
      ]);

      await provider.applyRemoteSync('server|user');

      expect(provider.pluginById('p'), isNull);
      expect((await repo.pluginDirectory('p')).existsSync(), isFalse);
      await storage.close();
    });

    test('remote tombstone preserves an independent local install', () async {
      final repo = PluginRepository(rootOverride: Directory('${root.path}/p'));
      final storage = StorageV2Service(
        rootDirectory: Directory('${root.path}/storage'),
      );
      await StorageV2UpgradeService(storageV2: storage).ensureReady();
      await storage.activateSyncScope('server|user', deviceId: 'device-a');
      final provider = PluginProvider(repository: repo, storageV2: storage);
      await provider.importDirectory((await _source('p')).path);
      await provider.writeStorageValue('p', 'local', true);
      await storage.replacePluginSyncRows('p', [
        repo.buildDeletedSyncMarker('p'),
      ]);

      await provider.applyRemoteSync('server|user');

      expect(provider.pluginById('p'), isNotNull);
      expect((await repo.pluginDirectory('p')).existsSync(), isTrue);
      expect(await provider.loadStorage('p'), {'local': true});
      await storage.close();
    });

    test('A tombstone preserves a plugin installed from B sync', () async {
      final repo = PluginRepository(rootOverride: Directory('${root.path}/p'));
      final storage = StorageV2Service(
        rootDirectory: Directory('${root.path}/storage'),
      );
      await StorageV2UpgradeService(storageV2: storage).ensureReady();
      await storage.activateSyncScope('server|user-a', deviceId: 'device-a');
      final provider = PluginProvider(repository: repo, storageV2: storage);
      await provider.importDirectory((await _source('p')).path);
      await repo.saveInstalledPlugins([
        provider
            .pluginById('p')!
            .copyWith(syncedOrigin: true, syncOriginScope: 'server|user-b'),
      ]);
      await provider.load();
      await storage.replacePluginSyncRows('p', [
        repo.buildDeletedSyncMarker('p'),
      ]);

      await provider.applyRemoteSync('server|user-a');

      expect(provider.pluginById('p'), isNotNull);
      expect((await repo.pluginDirectory('p')).existsSync(), isTrue);
      await storage.close();
    });

    test('identical plugin bytes reuse one content-addressed blob', () async {
      final repo = PluginRepository(rootOverride: Directory('${root.path}/p'));
      final first = await repo.storeSyncBlob(utf8.encode('same'));
      final second = await repo.storeSyncBlob(utf8.encode('same'));
      final blobs = Directory('${root.path}/p/sync_blobs');

      expect(second, first);
      expect(
        await blobs
            .list(recursive: true)
            .where((entry) => entry is File)
            .length,
        1,
      );
    });
  });
}

Future<InstalledPlugin> _install(PluginRepository repo, String id) async {
  final source = await _source(id);
  addTearDown(() async {
    if (await source.exists()) await source.delete(recursive: true);
  });
  return repo.importDirectory(source.path);
}

Future<Directory> _source(String id) async {
  final source = await Directory.systemTemp.createTemp('lynai_plugin_source_');
  addTearDown(() async {
    if (await source.exists()) await source.delete(recursive: true);
  });
  final manifest = {
    'id': id,
    'name': id,
    'version': '1.0.0',
    'entry': 'main.lua',
    'permissions': ['network'],
    'tools': [
      {'name': 'tool', 'handler': 'tool'},
    ],
    'functions': [
      {'name': 'function', 'handler': 'function'},
    ],
    'skills': [
      {'name': 'skill'},
    ],
    'ui': {
      'featurePages': [
        {'id': 'page', 'title': 'Page', 'entry': 'page.html'},
      ],
    },
    'editableFiles': [
      {'path': id == 'status-dashboard' ? 'status.css' : 'editable.txt'},
    ],
  };
  await File('${source.path}/plugin.json').writeAsString(jsonEncode(manifest));
  await File('${source.path}/main.lua').writeAsString('return {}');
  await File('${source.path}/page.html').writeAsString('<html></html>');
  await File('${source.path}/config.schema.json').writeAsString('{}');
  await File(
    '${source.path}/${id == 'status-dashboard' ? 'status.css' : 'editable.txt'}',
  ).writeAsString('initial');
  await Directory('${source.path}/defaults').create();
  await File('${source.path}/defaults/main.lua').writeAsString('bundled');
  return source;
}
