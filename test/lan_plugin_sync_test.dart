import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/sync_change.dart';
import 'package:lynai/services/plugin_sync_validation.dart';
import 'package:lynai/services/lan_sync_storage.dart';
import 'package:lynai/services/storage_v2_service.dart';
import 'package:lynai/services/storage_v2_upgrade_service.dart';

void main() {
  test(
    'LAN plugin metadata, blobs, tombstones, and hashes roundtrip',
    () async {
      final root = await Directory.systemTemp.createTemp('lynai_lan_plugin_');
      final source = StorageV2Service(
        rootDirectory: Directory('${root.path}/source'),
      );
      final target = StorageV2Service(
        rootDirectory: Directory('${root.path}/target'),
      );
      final sourceBlobs = <String, List<int>>{};
      final targetBlobs = <String, List<int>>{};
      try {
        await StorageV2UpgradeService(storageV2: source).ensureReady();
        await StorageV2UpgradeService(storageV2: target).ensureReady();
        final reads = <String>[];
        final sourceLan = _lan(source, sourceBlobs, reads: reads);
        final targetLan = _lan(target, targetBlobs);
        await sourceLan.activate('source-device');
        await targetLan.activate('target-device');
        final fileBytes = utf8.encode('plugin file');
        final settingsBytes = utf8.encode('{"theme":"dark"}');
        final configBytes = utf8.encode('{"endpoint":"https://example.test"}');
        final fileHash = sha256.convert(fileBytes).toString();
        final settingsHash = sha256.convert(settingsBytes).toString();
        final configHash = sha256.convert(configBytes).toString();
        final packageVersion = sha256
            .convert(utf8.encode('review-plugin-v1'))
            .toString();
        sourceBlobs[fileHash] = fileBytes;
        sourceBlobs[settingsHash] = settingsBytes;
        sourceBlobs[configHash] = configBytes;
        await source.replacePluginSyncRows('review-plugin', [
          {
            'id': 'review-plugin',
            'pluginId': 'review-plugin',
            'kind': 'package',
            'builtIn': false,
            'manifestVersion': 1,
            'state': 'installed',
            'packageVersion': packageVersion,
            'pluginJsonSha256': fileHash,
            'files': [
              {
                'path': 'plugin.json',
                'sha256': fileHash,
                'size': fileBytes.length,
              },
            ],
          },
          {
            'id': 'review-plugin/plugin.json',
            'pluginId': 'review-plugin',
            'path': 'plugin.json',
            'sha256': fileHash,
            'size': fileBytes.length,
            'packageVersion': packageVersion,
            'kind': 'content',
            'builtIn': false,
          },
          {
            'id': 'review-plugin',
            'pluginId': 'review-plugin',
            'sha256': settingsHash,
            'size': settingsBytes.length,
            'kind': 'plugin_settings',
            'domain': 'plugin_settings',
          },
          {
            'id': 'review-plugin',
            'pluginId': 'review-plugin',
            'sha256': configHash,
            'size': configBytes.length,
            'kind': 'plugin_config',
            'domain': 'plugin_config',
          },
        ]);

        final entries = await sourceLan.changesForPeer(const {});
        expect(
          entries.map((entry) => entry.table).toSet(),
          containsAll({'plugin_files', 'plugin_settings', 'plugin_config'}),
        );
        expect(
          entries.any((entry) => entry.table == 'plugin_storage'),
          isFalse,
        );
        final blobs = await sourceLan.blobsForChanges(entries);
        expect(blobs.keys, containsAll({fileHash, settingsHash, configHash}));
        expect(blobs.values.every((blob) => blob.kind == 'plugin'), isTrue);
        expect(reads, isEmpty);
        for (final entry in blobs.entries) {
          final bytes = <int>[];
          await for (final chunk in sourceLan.readBlobChunks(
            entry.key,
            entry.value,
            4,
          )) {
            expect(chunk.length, lessThanOrEqualTo(4));
            bytes.addAll(chunk);
          }
          expect(sha256.convert(bytes).toString(), entry.key);
          await targetLan.installBlob(entry.key, entry.value.kind, bytes);
        }
        expect(reads.toSet(), blobs.keys.toSet());
        await targetLan.apply(entries.map(_change).toList());
        final restored = await target.loadPluginSyncRows();
        expect(restored, hasLength(4));
        expect(
          targetBlobs.keys,
          containsAll({fileHash, settingsHash, configHash}),
        );
        expect(
          restored.singleWhere(
            (row) => row['id'] == 'review-plugin' && row['kind'] == 'package',
          )['builtIn'],
          isFalse,
        );

        await source.replacePluginSyncRows('review-plugin', const [
          {
            'id': 'review-plugin',
            'pluginId': 'review-plugin',
            'kind': 'package',
            'builtIn': false,
            'manifestVersion': 1,
            'state': 'deleted',
            'files': <Map<String, dynamic>>[],
          },
        ]);
        final tombstones = await sourceLan.changesForPeer(const {});
        expect(tombstones, isNotEmpty);
        expect(
          tombstones.any(
            (entry) =>
                entry.recordId == 'review-plugin' &&
                entry.op == 'upsert' &&
                entry.data?['state'] == 'deleted',
          ),
          isTrue,
        );
        await targetLan.apply(tombstones.map(_change).toList());
        expect((await target.loadPluginSyncRows()).single['state'], 'deleted');
      } finally {
        await source.close();
        await target.close();
        if (await root.exists()) await root.delete(recursive: true);
      }
    },
  );

  test(
    'LAN rejects malicious plugin identity before applying metadata',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'lynai_lan_plugin_bad_',
      );
      final storage = StorageV2Service(rootDirectory: root);
      final blobs = <String, List<int>>{};
      try {
        await StorageV2UpgradeService(storageV2: storage).ensureReady();
        final lan = _lan(storage, blobs);
        await lan.activate('target-device');

        await expectLater(
          lan.apply([
            SyncChange(
              seq: 1,
              changeId: 'malicious-plugin',
              deviceId: 'source-device',
              clientCreatedAt: DateTime.utc(2026),
              table: 'plugin_files',
              op: 'upsert',
              recordId: '../../outside/main.lua',
              data: const {
                'id': '../../outside/main.lua',
                'pluginId': '../../outside',
                'path': 'main.lua',
                'sha256':
                    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
                'size': 1,
                'kind': 'content',
                'builtIn': false,
              },
            ),
          ]),
          throwsStateError,
        );

        expect(await storage.loadPluginSyncRows(), isEmpty);
      } finally {
        await storage.close();
        if (await root.exists()) await root.delete(recursive: true);
      }
    },
  );

  test('LAN resource blobs are read from storage in bounded chunks', () async {
    final root = await Directory.systemTemp.createTemp('lynai_lan_resource_');
    final storage = StorageV2Service(rootDirectory: root);
    var pluginReads = 0;
    try {
      await StorageV2UpgradeService(storageV2: storage).ensureReady();
      final bytes = List<int>.generate(19, (index) => index);
      final hash = sha256.convert(bytes).toString();
      await storage.installResourceBlob(hash, bytes);
      final lan = LanSyncStorage(
        storage: storage,
        readPluginBlob: (_) async {
          pluginReads++;
          return const [];
        },
        hasPluginBlob: (_) async => false,
        installPluginBlob: (_, _) async {},
      );

      final chunks = await lan
          .readBlobChunks(
            hash,
            LanSyncBlob(size: bytes.length, kind: 'resource'),
            5,
          )
          .toList();

      expect(chunks.map((chunk) => chunk.length), [5, 5, 5, 4]);
      expect(chunks.expand((chunk) => chunk), bytes);
      expect(pluginReads, 0);
    } finally {
      await storage.close();
      if (await root.exists()) await root.delete(recursive: true);
    }
  });

  test('plugin sync paths use canonical platform-independent segments', () {
    const hash =
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    SyncChange change(String path) => SyncChange(
      seq: 1,
      changeId: 'path-$path',
      deviceId: 'source-device',
      clientCreatedAt: DateTime.utc(2026),
      table: 'plugin_files',
      op: 'upsert',
      recordId: 'plugin/$path',
      data: {
        'id': 'plugin/$path',
        'pluginId': 'plugin',
        'path': path,
        'sha256': hash,
        'size': 1,
        'packageVersion': hash,
        'kind': 'content',
        'builtIn': false,
      },
    );

    expect(
      () => validatePluginSyncChange(change('web/main.lua')),
      returnsNormally,
    );
    for (final path in const [
      '../main.lua',
      'web/../main.lua',
      './main.lua',
      'web//main.lua',
      '/main.lua',
      r'C:\main.lua',
      r'web\main.lua',
      r'\\server\share\main.lua',
      'https://example.test/main.lua',
      ' main.lua',
      'main.lua ',
    ]) {
      expect(
        () => validatePluginSyncChange(change(path)),
        throwsStateError,
        reason: path,
      );
    }
  });
}

LanSyncStorage _lan(
  StorageV2Service storage,
  Map<String, List<int>> blobs, {
  List<String>? reads,
}) => LanSyncStorage(
  storage: storage,
  readPluginBlob: (hash) async {
    reads?.add(hash);
    return blobs[hash]!;
  },
  hasPluginBlob: (hash) async => blobs.containsKey(hash),
  installPluginBlob: (hash, bytes) async => blobs[hash] = List.of(bytes),
);

SyncChange _change(dynamic entry) => SyncChange(
  seq: 1,
  changeId: entry.changeId,
  deviceId: entry.deviceId,
  clientCreatedAt: entry.clientCreatedAt,
  table: entry.table,
  op: entry.op,
  recordId: entry.recordId,
  data: entry.data,
);
