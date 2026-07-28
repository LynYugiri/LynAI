import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:lynai/models/physical_dataset.dart';
import 'package:lynai/services/dataset_secret_store.dart';
import 'package:lynai/services/secret_store.dart';
import 'package:lynai/services/storage_v2_service.dart';
import 'package:lynai/services/storage_v2_upgrade_service.dart';

void main() {
  late Directory root;
  late StorageV2Service storage;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('lynai_dataset_test_');
    storage = StorageV2Service(rootDirectory: root);
  });

  tearDown(() async {
    await storage.close();
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('account dataset ID uses normalized origin and full SHA-256', () {
    final first = PhysicalDatasetIdentity.account(
      backendUrl: 'HTTPS://Example.COM:443/api',
      userId: 'opaque/User ID',
    );
    final second = PhysicalDatasetIdentity.account(
      backendUrl: 'https://example.com/other',
      userId: 'opaque/User ID',
    );

    expect(first.id, hasLength(64));
    expect(first.id, matches(RegExp(r'^[a-f0-9]{64}$')));
    expect(first.id, second.id);
    expect(first.backendOrigin, 'https://example.com');
  });

  test('legacy storage is copied once and retained', () async {
    await StorageV2UpgradeService(storageV2: storage).ensureReady();
    await storage.writeDataFile('tasks.json', {
      'tasks': [
        {'id': 'legacy'},
      ],
    });
    final legacyPlugin = File('${root.path}/plugins/example/plugin.json');
    await legacyPlugin.parent.create(recursive: true);
    await legacyPlugin.writeAsString('{}');
    await storage.close();

    storage = StorageV2Service(rootDirectory: root);
    await StorageV2UpgradeService(storageV2: storage).ensureDatasetsReady();

    expect(await Directory('${root.path}/storage_v2').exists(), isTrue);
    expect(storage.activeDatasetId, PhysicalDatasetIdentity.localId);
    expect((await storage.loadDataFile('tasks.json'))['tasks'], isNotEmpty);
    expect(
      await File(
        '${root.path}/datasets/local/plugins/example/plugin.json',
      ).exists(),
      isTrue,
    );
    final journal =
        jsonDecode(
              await File(
                '${root.path}/datasets/local/migration.json',
              ).readAsString(),
            )
            as Map<String, dynamic>;
    expect(journal['state'], 'complete');
    expect(await File('${root.path}/datasets/registry.json').exists(), isTrue);
  });

  test('local and account databases remain physically isolated', () async {
    await StorageV2UpgradeService(storageV2: storage).ensureDatasetsReady();
    await storage.writeDataFile('dataset_marker.json', {'value': 'local'});
    await storage.activateSyncScope('offline', deviceId: 'device-local');
    await storage.applyLocalRowChanges([
      (
        table: 'tasks',
        op: 'upsert',
        data: {
          'id': 'local-task',
          'title': 'local',
          'note': null,
          'plannedDate': null,
          'plannedTime': null,
          'dueDate': null,
          'dueTime': null,
          'completedAt': null,
          'reminders': const [],
          'createdAt': '2026-01-01T00:00:00Z',
          'updatedAt': '2026-01-01T00:00:00Z',
        },
        change: null,
      ),
    ]);

    await storage.activateAccountDataset(
      backendUrl: 'https://example.com/api',
      userId: '42',
    );
    await StorageV2UpgradeService(storageV2: storage).ensureReady();
    expect(await storage.loadDataFile('dataset_marker.json'), isEmpty);
    expect(await storage.loadSyncOutbox('offline'), isEmpty);
    await storage.writeDataFile('dataset_marker.json', {'value': 'account'});

    await storage.activateLocalDataset();
    expect(
      (await storage.loadDataFile('dataset_marker.json'))['value'],
      'local',
    );
    expect(await storage.loadSyncOutbox('offline'), hasLength(1));
    await storage.activateAccountDataset(
      backendUrl: 'https://example.com/other',
      userId: '42',
    );
    expect(
      (await storage.loadDataFile('dataset_marker.json'))['value'],
      'account',
    );
  });

  test('dataset metadata mismatch fails closed', () async {
    await StorageV2UpgradeService(storageV2: storage).ensureDatasetsReady();
    final identity = PhysicalDatasetIdentity.account(
      backendUrl: 'https://example.com',
      userId: '42',
    );
    final datasetRoot = Directory('${root.path}/datasets/${identity.id}');
    await datasetRoot.create(recursive: true);
    await File('${datasetRoot.path}/dataset.json').writeAsString(
      jsonEncode({
        'type': 'lynai.dataset',
        'version': 1,
        ...const PhysicalDatasetIdentity.local().toJson(),
      }),
    );

    await expectLater(storage.activateDataset(identity), throwsStateError);
    expect(storage.activeDatasetId, PhysicalDatasetIdentity.localId);
  });

  test('database ownership mismatch fails closed', () async {
    await StorageV2UpgradeService(storageV2: storage).ensureDatasetsReady();
    await storage.close();
    final database = sqlite3.open(
      '${root.path}/datasets/local/storage_v2/app.db',
    );
    database.execute(
      "UPDATE storage_meta SET value = 'different-dataset' "
      "WHERE key = 'physical_dataset_id'",
    );
    database.close();
    storage = StorageV2Service(rootDirectory: root);
    await storage.initializeDatasets();

    await expectLater(storage.validateDatabaseOwnership(), throwsStateError);
  });

  test('an old database lease becomes unwritable after a switch', () async {
    await StorageV2UpgradeService(storageV2: storage).ensureDatasetsReady();
    final localLease = await storage.storageDatabase();

    await storage.activateAccountDataset(
      backendUrl: 'https://example.com',
      userId: '42',
    );
    await StorageV2UpgradeService(storageV2: storage).ensureReady();
    await expectLater(
      localLease.writeDataFile('lease_marker.json', {'value': 'stale'}),
      throwsStateError,
    );
    expect(await storage.loadDataFile('lease_marker.json'), isEmpty);
    await storage.activateLocalDataset();
    expect(await storage.loadDataFile('lease_marker.json'), isEmpty);
  });

  test('model and MCP-style secrets follow the active dataset', () async {
    await StorageV2UpgradeService(storageV2: storage).ensureDatasetsReady();
    final scoped = DatasetSecretStore(storage, InMemorySecretStore());
    await scoped.write('model.secret', 'local');

    await storage.activateAccountDataset(
      backendUrl: 'https://example.com',
      userId: '42',
    );
    expect(await scoped.read('model.secret'), isNull);
    await scoped.write('model.secret', 'account');

    await storage.activateLocalDataset();
    expect(await scoped.read('model.secret'), 'local');
  });

  test('local dataset adopts legacy unscoped secrets only', () async {
    await StorageV2UpgradeService(storageV2: storage).ensureDatasetsReady();
    final delegate = InMemorySecretStore({'model.secret': 'legacy'});
    final scoped = DatasetSecretStore(storage, delegate);

    expect(await scoped.read('model.secret'), 'legacy');
    await storage.activateAccountDataset(
      backendUrl: 'https://example.com',
      userId: '42',
    );
    expect(await scoped.read('model.secret'), isNull);
  });
}
