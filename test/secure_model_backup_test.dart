import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'package:lynai/models/backup_models.dart';
import 'package:lynai/models/model_config.dart';
import 'package:lynai/providers/conversation_provider.dart';
import 'package:lynai/providers/feature_provider.dart';
import 'package:lynai/providers/model_config_provider.dart';
import 'package:lynai/providers/roleplay_provider.dart';
import 'package:lynai/providers/settings_provider.dart';
import 'package:lynai/repositories/model_config_repository.dart';
import 'package:lynai/services/backup_encryption.dart';
import 'package:lynai/services/backup_service.dart';
import 'package:lynai/services/secret_store.dart';
import 'package:lynai/services/storage_v2_service.dart';
import 'package:lynai/services/storage_v2_upgrade_service.dart';
import 'package:sqlite3/sqlite3.dart';

import 'support/memory_repositories.dart';

const _apiKey = 'sk-plaintext-must-never-leak';

ModelConfig _model({String apiKey = _apiKey}) => ModelConfig(
  id: 'model-1',
  name: 'Provider',
  endpoint: 'https://example.com/v1',
  apiKey: apiKey,
  modelName: 'model-a',
  apiType: 'openai',
  priority: 0,
);

BackupService _backupService(
  ModelConfigProvider models, {
  BackupEncryption? encryption,
  StorageV2Service? storage,
}) {
  return BackupService(
    settingsProvider: SettingsProvider(),
    modelConfigProvider: models,
    conversationProvider: ConversationProvider(),
    featureProvider: FeatureProvider(),
    roleplayProvider: RoleplayProvider(),
    backupEncryption: encryption,
    storageV2: storage,
    appVersionLoader: () async => 'test',
  );
}

void main() {
  test(
    'plaintext model config migration is idempotent and scrubs SQLite',
    () async {
      final root = await Directory.systemTemp.createTemp('lynai_model_secret_');
      final storage = StorageV2Service(rootDirectory: root);
      final secrets = InMemorySecretStore();
      try {
        await StorageV2UpgradeService(storageV2: storage).ensureReady();
        await storage.writeDataFile('model_configs.json', {
          'models': [_model().toJson()..['apiKey'] = _apiKey],
        });
        final repository = ModelConfigRepository(
          storageV2: storage,
          secretStore: secrets,
        );

        final first = await repository.load();
        final second = await repository.load();

        expect(first.models.single.apiKey, _apiKey);
        expect(second.models.single.apiKey, _apiKey);
        final ref = ModelConfig.secretReferenceForId('model-1');
        expect(await secrets.read(ref), _apiKey);
        final db = sqlite3.open('${root.path}/storage_v2/app.db');
        try {
          final configJson =
              db.select('SELECT config_json FROM model_configs WHERE id = ?', [
                    'model-1',
                  ]).single['config_json']
                  as String;
          expect(configJson, isNot(contains(_apiKey)));
          expect(jsonDecode(configJson), containsPair('apiKeySecretRef', ref));
        } finally {
          db.close();
        }
      } finally {
        await storage.close();
        await root.delete(recursive: true);
      }
    },
  );

  test('model persistence cannot enqueue API keys for cloud sync', () async {
    final root = await Directory.systemTemp.createTemp('lynai_model_sync_');
    final storage = StorageV2Service(rootDirectory: root);
    try {
      await StorageV2UpgradeService(storageV2: storage).ensureReady();
      await storage.activateSyncScope('user-1', deviceId: 'device-1');
      final repository = ModelConfigRepository(
        storageV2: storage,
        secretStore: InMemorySecretStore(),
      );
      await repository.save([_model()], usingStorageV2: true);

      final outbox = await storage.loadSyncOutbox('user-1');
      expect(outbox, isEmpty);
      expect(jsonEncode(_model().toJson()), isNot(contains(_apiKey)));
      expect(_model().toJson(), isNot(containsPair('apiKey', anything)));
    } finally {
      await storage.close();
      await root.delete(recursive: true);
    }
  });

  test('ordinary backup excludes API keys', () async {
    final models = memoryModelConfigProvider();
    await models.replaceModels([_model()]);
    final bytes = await _backupService(models).exportZipBytes(
      const BackupSelection(
        {BackupSection.settings},
        settingsParts: {BackupSettingsPart.apiConfigs},
      ),
    );

    expect(utf8.decode(bytes, allowMalformed: true), isNot(contains(_apiKey)));
    final archive = ZipDecoder().decodeBytes(bytes);
    final modelFile = archive.files.singleWhere(
      (file) => file.name == 'model_configs.json',
    );
    final json = jsonDecode(utf8.decode(modelFile.content as List<int>)) as Map;
    expect(
      (json['models'] as List).single,
      isNot(containsPair('apiKey', anything)),
    );
    expect(
      archive.files.map((file) => file.name),
      isNot(contains('secrets/model_api_keys.json')),
    );
  });

  test(
    'encrypted backup restores API keys and authenticates exact ZIP bytes',
    () async {
      final encryption = BackupEncryption(
        memoryKiB: BackupEncryption.minMemoryKiB,
        iterations: BackupEncryption.minIterations,
      );
      final sourceModels = memoryModelConfigProvider();
      await sourceModels.replaceModels([_model()]);
      final source = _backupService(sourceModels, encryption: encryption);
      final encrypted = await source.exportEncryptedBytes(
        const BackupSelection(
          {BackupSection.settings},
          settingsParts: {BackupSettingsPart.apiConfigs},
        ),
        password: 'correct horse battery staple',
        includeApiKeys: true,
      );

      expect(BackupEncryption.isEncrypted(encrypted), isTrue);
      expect(
        utf8.decode(encrypted, allowMalformed: true),
        isNot(contains(_apiKey)),
      );
      final targetModels = memoryModelConfigProvider();
      final target = _backupService(targetModels, encryption: encryption);
      final archive = await target.readEncryptedBytes(
        encrypted,
        password: 'correct horse battery staple',
      );
      await target.importArchive(
        archive,
        const ImportPlan(
          selection: BackupSelection(
            {BackupSection.settings},
            settingsParts: {BackupSettingsPart.apiConfigs},
          ),
          mode: ImportMode.replaceSection,
        ),
      );

      expect(targetModels.models.single.apiKey, _apiKey);
      final zip = await source.exportZipBytes(
        const BackupSelection(
          {BackupSection.settings},
          settingsParts: {BackupSettingsPart.apiConfigs},
        ),
      );
      final envelope = await encryption.encrypt(zip, 'password');
      expect(
        await encryption.decrypt(envelope, 'password'),
        orderedEquals(zip),
      );
    },
  );

  test(
    'encrypted backup uses one generic error for password and tamper',
    () async {
      final encryption = BackupEncryption(
        memoryKiB: BackupEncryption.minMemoryKiB,
        iterations: BackupEncryption.minIterations,
      );
      final envelope = await encryption.encrypt([1, 2, 3], 'password');

      await expectLater(
        encryption.decrypt(envelope, 'wrong'),
        throwsA(isA<BackupDecryptionException>()),
      );
      final tampered = Uint8List.fromList(envelope)..[envelope.length - 1] ^= 1;
      await expectLater(
        encryption.decrypt(tampered, 'password'),
        throwsA(isA<BackupDecryptionException>()),
      );
    },
  );

  test(
    'encrypted backup rejects version and Argon2 limits before KDF',
    () async {
      final encryption = BackupEncryption(
        memoryKiB: BackupEncryption.minMemoryKiB,
        iterations: BackupEncryption.minIterations,
      );
      final envelope = await encryption.encrypt([1], 'password');
      final badVersion = Uint8List.fromList(envelope);
      ByteData.sublistView(
        badVersion,
      ).setUint16(8, BackupEncryption.version + 1);
      final badMemory = Uint8List.fromList(envelope);
      ByteData.sublistView(
        badMemory,
      ).setUint32(12, BackupEncryption.maxMemoryKiB + 1);

      await expectLater(
        encryption.decrypt(badVersion, 'password'),
        throwsA(isA<BackupDecryptionException>()),
      );
      await expectLater(
        encryption.decrypt(badMemory, 'password'),
        throwsA(isA<BackupDecryptionException>()),
      );
    },
  );

  test('schema 5 ZIP backups remain readable without API keys', () async {
    final archive = Archive();
    void addJson(String name, Object value) {
      final bytes = utf8.encode(jsonEncode(value));
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    }

    addJson('manifest.json', {
      'type': 'lynai.backup',
      'schemaVersion': 5,
      'sections': {
        'settings': {
          'enabled': true,
          'files': ['model_configs.json'],
          'parts': ['apiConfigs'],
        },
      },
    });
    addJson('model_configs.json', {
      'models': [_model().toJson()..['apiKey'] = _apiKey],
    });

    final parsed = await _backupService(
      memoryModelConfigProvider(),
    ).readZipBytes(ZipEncoder().encode(archive));
    expect(parsed.data.modelConfigs, hasLength(1));
    expect(parsed.data.modelConfigs!.single.apiKey, isEmpty);
  });

  test('schema 8 rejects plugin size or hash mismatch while reading', () async {
    final archive = Archive();
    void add(String name, List<int> bytes) {
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    }

    final pluginBytes = utf8.encode('return true');
    add('plugins/installed/p/main.lua', pluginBytes);
    add(
      'plugins/installed_plugins.json',
      utf8.encode(
        jsonEncode({
          'plugins': [
            {
              'plugin': {'id': 'p'},
              'files': [
                {
                  'path': 'main.lua',
                  'archivePath': 'plugins/installed/p/main.lua',
                  'size': pluginBytes.length,
                  'sha256': '0' * 64,
                },
              ],
            },
          ],
        }),
      ),
    );
    add(
      'manifest.json',
      utf8.encode(
        jsonEncode({
          'type': 'lynai.backup',
          'schemaVersion': 8,
          'sections': {
            'plugins': {
              'enabled': true,
              'files': ['plugins/installed_plugins.json'],
            },
          },
        }),
      ),
    );

    await expectLater(
      _backupService(
        memoryModelConfigProvider(),
      ).readZipBytes(ZipEncoder().encode(archive)),
      throwsA(isA<FormatException>()),
    );
  });

  test('backup ZIP rejects duplicates, traversal, and symlinks', () async {
    final service = _backupService(memoryModelConfigProvider());
    final archives = <List<int>>[
      ZipEncoder().encode(
        Archive()
          ..addFile(ArchiveFile.string('manifest.json', '{}'))
          ..addFile(ArchiveFile.string('second__.json', '{}')),
      ),
      ZipEncoder().encode(
        Archive()..addFile(ArchiveFile.string('../manifest.json', '{}')),
      ),
      _markFirstZipEntryAsSymlink(
        Archive()..addFile(ArchiveFile.string('manifest.json', '../outside')),
      ),
    ];
    archives[0] = _renameZipEntry(
      archives[0],
      from: 'second__.json',
      to: 'manifest.json',
    );

    for (final bytes in archives) {
      await expectLater(
        service.readZipBytes(bytes),
        throwsA(isA<FormatException>()),
      );
    }
  });

  test('read and preview stage note blobs without installing them', () async {
    final root = await Directory.systemTemp.createTemp('lynai_backup_stage_');
    final storage = StorageV2Service(rootDirectory: root);
    try {
      await StorageV2UpgradeService(storageV2: storage).ensureReady();
      final content = utf8.encode('staged note');
      final hash = sha256.convert(content).toString();
      final blobPath = 'notes/blobs/${hash.substring(0, 2)}/$hash';
      final archive = Archive();
      void add(String name, List<int> bytes) {
        archive.addFile(ArchiveFile(name, bytes.length, bytes));
      }

      add(
        'notes/revisions.json',
        utf8.encode(
          jsonEncode({
            'revisions': [
              {
                'id': 'r1',
                'noteId': 'n1',
                'parentIds': const <String>[],
                'authorDeviceId': 'test',
                'contentHash': hash,
                'createdAt': '2026-01-01T00:00:00Z',
              },
            ],
          }),
        ),
      );
      add(blobPath, content);
      add(
        'manifest.json',
        utf8.encode(
          jsonEncode({
            'type': 'lynai.backup',
            'schemaVersion': 8,
            'sections': {
              'notes': {
                'enabled': true,
                'files': ['notes/revisions.json', blobPath],
              },
            },
          }),
        ),
      );
      final service = _backupService(
        memoryModelConfigProvider(),
        storage: storage,
      );

      final parsed = await service.readZipBytes(ZipEncoder().encode(archive));
      service.preview(parsed, BackupSelection.fromData(parsed.data));

      expect(parsed.noteBlobs[hash], orderedEquals(content));
      expect(await storage.hasNoteBlob(hash), isFalse);
    } finally {
      await storage.close();
      await root.delete(recursive: true);
    }
  });
}

List<int> _markFirstZipEntryAsSymlink(Archive archive) {
  final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
  final data = ByteData.sublistView(bytes);
  for (var offset = 0; offset <= bytes.length - 46; offset++) {
    if (data.getUint32(offset, Endian.little) != 0x02014b50) continue;
    data.setUint16(offset + 4, (3 << 8) | 20, Endian.little);
    data.setUint32(offset + 38, 0xa000 << 16, Endian.little);
    return bytes;
  }
  throw StateError('ZIP central directory not found');
}

List<int> _renameZipEntry(
  List<int> encoded, {
  required String from,
  required String to,
}) {
  if (from.length != to.length) throw ArgumentError('names must match length');
  final bytes = Uint8List.fromList(encoded);
  final source = utf8.encode(from);
  final replacement = utf8.encode(to);
  var replacements = 0;
  for (var offset = 0; offset <= bytes.length - source.length; offset++) {
    var matches = true;
    for (var index = 0; index < source.length; index++) {
      if (bytes[offset + index] != source[index]) {
        matches = false;
        break;
      }
    }
    if (!matches) continue;
    bytes.setRange(offset, offset + replacement.length, replacement);
    replacements++;
  }
  if (replacements < 2) throw StateError('ZIP entry name not found');
  return bytes;
}
