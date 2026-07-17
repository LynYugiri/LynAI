import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/app_settings.dart';
import 'package:lynai/models/model_config.dart';
import 'package:lynai/models/shared_sync_models.dart';
import 'package:lynai/models/sync_change.dart';
import 'package:lynai/providers/settings_provider.dart';
import 'package:lynai/services/storage_v2_database.dart';
import 'package:lynai/services/storage_v2_service.dart';

void main() {
  group('shared settings projection', () {
    test('v1 excludes device-local settings', () {
      final local = AppSettings.defaults()
          .copyWith(
            themeColor: Colors.purple,
            backendUrl: 'https://device.example',
            hasConfiguredBackend: true,
            hasSeenLoginGuide: true,
            lastFeature: 'notes',
            lastSeenChangelogVersion: '9.9.9',
            agentGrantedPermissions: const ['device:control'],
            floatingAssistant: const FloatingAssistantSettings(
              enabled: true,
              bubbleX: 321,
            ),
          )
          .toJson();
      local['storageV2'] = {'backgroundResourceId': 'background-1'};

      final projection = SharedSettingsV1.fromLocalJson(local).data;

      expect(projection['schemaVersion'], 1);
      expect(projection['themeColor'], Colors.purple.toARGB32());
      expect(projection['backgroundResourceId'], 'background-1');
      expect(
        projection.keys,
        isNot(
          containsAll([
            'backendUrl',
            'hasConfiguredBackend',
            'hasSeenLoginGuide',
            'lastFeature',
            'lastSeenChangelogVersion',
            'agentGrantedPermissions',
            'floatingAssistant',
            'backgroundImagePath',
          ]),
        ),
      );
    });

    test('remote merge preserves every device-local setting', () {
      final local = AppSettings.defaults()
          .copyWith(
            backendUrl: 'https://device.example',
            hasConfiguredBackend: true,
            hasSeenLoginGuide: true,
            lastFeature: 'notes',
            lastSeenChangelogVersion: '9.9.9',
            agentGrantedPermissions: const ['device:control'],
            floatingAssistant: const FloatingAssistantSettings(
              enabled: true,
              bubbleX: 321,
            ),
          )
          .toJson();

      final merged = SharedSettingsV1.fromRemote({
        'id': SharedSettingsV1.recordId,
        'schemaVersion': 1,
        'themeColor': Colors.orange.toARGB32(),
        'baseThemeColor': Colors.orange.toARGB32(),
        'themeMode': 'dark',
        'blurEnabled': true,
        'blurAmount': 12.0,
        'systemPrompts': const [],
        'roles': const [],
        'roleGroups': const [],
      }).mergeIntoLocal(local);
      final restored = AppSettings.fromJson(merged);

      expect(restored.themeColor.toARGB32(), Colors.orange.toARGB32());
      expect(restored.backendUrl, 'https://device.example');
      expect(restored.hasConfiguredBackend, isTrue);
      expect(restored.hasSeenLoginGuide, isTrue);
      expect(restored.lastFeature, 'notes');
      expect(restored.lastSeenChangelogVersion, '9.9.9');
      expect(restored.agentGrantedPermissions, contains('device:control'));
      expect(restored.floatingAssistant.enabled, isTrue);
      expect(restored.floatingAssistant.bubbleX, 321);
    });
  });

  group('synced model projection', () {
    test('v1 never contains API keys, secret refs, or credential params', () {
      final model = _model(
        'provider-1',
        endpoint: 'https://user:password@example.com/v1',
        extraParams: {
          'apiKey': 'nested-secret',
          'headers': {'Authorization': 'Bearer secret', 'X-Mode': 'fast'},
          'debugSse': true,
        },
      );

      final data = SyncedModelConfigV1.fromLocal(model).data;
      final encoded = data.toString().toLowerCase();

      expect(data['schemaVersion'], 1);
      expect(data, isNot(contains('apiKey')));
      expect(data, isNot(contains('apiKeySecretRef')));
      expect(data['endpoint'], 'https://example.com/v1');
      expect(encoded, isNot(contains('nested-secret')));
      expect(encoded, isNot(contains('bearer secret')));
      expect((data['extraParams']['headers'] as Map)['X-Mode'], 'fast');
    });
  });

  group('storage sync domains', () {
    late Directory root;
    late StorageV2Database database;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('lynai_shared_sync_');
      database = StorageV2Database(Directory('${root.path}/storage_v2'));
      await database.activateSyncScope('server|user', deviceId: _deviceId);
      await database.loadSyncOutbox('server|user');
    });

    tearDown(() async {
      await database.close();
      if (await root.exists()) await root.delete(recursive: true);
    });

    test(
      'outbox contains projections only and skips managed configs',
      () async {
        await database.writeDataFile(
          'app_settings.json',
          AppSettings.defaults()
              .copyWith(
                backendUrl: 'https://local-only.example',
                hasConfiguredBackend: true,
                floatingAssistant: const FloatingAssistantSettings(
                  enabled: true,
                ),
              )
              .toJson(),
        );
        await database.writeDataFile('model_configs.json', {
          'models': [
            _model('synced').toJson(),
            _model('device-only', cloudSyncEnabled: false).toJson(),
            _model('managed', managed: true).toJson(),
          ],
        });

        final outbox = await database.loadSyncOutbox('server|user');
        final settings = outbox.singleWhere(
          (entry) => entry.table == 'shared_settings',
        );
        final models = outbox.where(
          (entry) => entry.table == 'synced_model_configs',
        );
        final encoded = outbox.map((entry) => entry.data).toString();

        expect(settings.data?['schemaVersion'], 1);
        expect(settings.data, isNot(contains('backendUrl')));
        expect(settings.data, isNot(contains('floatingAssistant')));
        expect(models.map((entry) => entry.recordId), ['synced']);
        expect(encoded, isNot(contains('top-secret')));
        expect(encoded, isNot(contains('apiKeySecretRef')));
      },
    );

    test(
      'remote apply preserves local settings and model secret reference',
      () async {
        await database.writeDataFile(
          'app_settings.json',
          AppSettings.defaults()
              .copyWith(
                backendUrl: 'https://local-only.example',
                hasConfiguredBackend: true,
                lastFeature: 'notes',
              )
              .toJson(),
        );
        await database.writeDataFile('model_configs.json', {
          'models': [_model('synced').toJson()],
        });
        final pending = await database.loadSyncOutbox('server|user');
        await database.acknowledgeSyncOutbox('server|user', pending);

        await database.batchIncremental(
          [
            _remote('shared_settings', 'app-settings', {
              'id': 'app-settings',
              'schemaVersion': 1,
              'themeColor': Colors.orange.toARGB32(),
              'baseThemeColor': Colors.orange.toARGB32(),
              'themeMode': 'dark',
              'blurEnabled': true,
              'blurAmount': 8.0,
              'systemPrompts': const [],
              'roles': const [],
              'roleGroups': const [],
              'lastChatModelId': 'missing-model',
            }, seq: 1),
            _remote('synced_model_configs', 'synced', {
              'id': 'synced',
              'schemaVersion': 1,
              'name': 'Remote provider',
              'category': ModelConfig.categoryChat,
              'endpoint': 'https://remote.example/v1',
              'modelName': 'remote-model',
              'apiType': 'openai',
              'priority': 0,
              'models': [
                {'name': 'remote-model', 'enabled': true},
              ],
              'cloudSyncEnabled': true,
            }, seq: 2),
          ],
          remote: true,
          scope: 'server|user',
          nextSince: 2,
        );

        final settingsJson = await database.loadDataFile('app_settings.json');
        final settings = AppSettings.fromJson(settingsJson!);
        final modelsJson = await database.loadDataFile('model_configs.json');
        final model = ModelConfig.fromJson(
          Map<String, dynamic>.from((modelsJson!['models'] as List).single),
        );

        expect(settings.themeColor.toARGB32(), Colors.orange.toARGB32());
        expect(settings.backendUrl, 'https://local-only.example');
        expect(settings.hasConfiguredBackend, isTrue);
        expect(settings.lastFeature, 'notes');
        expect(model.name, 'Remote provider');
        expect(
          model.apiKeySecretRef,
          ModelConfig.secretReferenceForId('synced'),
        );
        expect(model.apiKey, isEmpty);
      },
    );

    test(
      'pending local projection requires explicit remote resolution',
      () async {
        await database.writeDataFile(
          'app_settings.json',
          AppSettings.defaults().copyWith(themeMode: 'light').toJson(),
        );
        final pending = await database.loadSyncOutbox('server|user');

        await database.batchIncremental(
          [
            _remote('shared_settings', 'app-settings', {
              'id': 'app-settings',
              'schemaVersion': 1,
              'themeMode': 'dark',
              'systemPrompts': const [],
              'roles': const [],
              'roleGroups': const [],
            }, seq: 1),
          ],
          remote: true,
          scope: 'server|user',
          nextSince: 1,
        );
        var local = AppSettings.fromJson(
          (await database.loadDataFile('app_settings.json'))!,
        );
        expect(local.themeMode, 'light');

        await database.acknowledgeSyncOutbox('server|user', pending);
        local = AppSettings.fromJson(
          (await database.loadDataFile('app_settings.json'))!,
        );
        expect(local.themeMode, 'light');

        final conflicts = await database.loadSyncConflicts('server|user');
        expect(conflicts, hasLength(1));
        await database.resolveSyncConflict(
          'server|user',
          conflicts.single.seq,
          SyncConflictResolution.useRemote,
        );
        local = AppSettings.fromJson(
          (await database.loadDataFile('app_settings.json'))!,
        );
        expect(local.themeMode, 'dark');
      },
    );

    test('remote model reload can repair synced settings reference', () async {
      final storage = StorageV2Service(rootDirectory: root);
      await database.writeDataFile(
        'app_settings.json',
        AppSettings.defaults().copyWith(lastChatModelId: 'missing').toJson(),
      );
      await database.writeDataFile('model_configs.json', {
        'models': [_model('available').toJson()],
      });
      final settings = SettingsProvider(storageV2: storage);
      await settings.loadSettings();

      settings.repairMediaModelSelections([_model('available')]);
      await settings.flushPendingSaves();

      expect(settings.settings.lastChatModelId, 'available');
    });

    test('remote model does not replace a device-local ID collision', () async {
      await database.writeDataFile('model_configs.json', {
        'models': [_model('collision', cloudSyncEnabled: false).toJson()],
      });

      await database.batchIncremental(
        [
          _remote('synced_model_configs', 'collision', {
            'id': 'collision',
            'schemaVersion': 1,
            'name': 'Remote replacement',
            'category': ModelConfig.categoryChat,
            'endpoint': 'https://user:secret@remote.example/v1',
            'modelName': 'remote-model',
            'apiType': 'openai',
            'priority': 0,
            'models': [
              {'name': 'remote-model', 'enabled': true},
            ],
            'cloudSyncEnabled': true,
          }, seq: 1),
        ],
        remote: true,
        scope: 'server|user',
        nextSince: 1,
      );

      final data = await database.loadDataFile('model_configs.json');
      final model = ModelConfig.fromJson(
        Map<String, dynamic>.from((data!['models'] as List).single),
      );
      expect(model.name, 'collision');
      expect(model.cloudSyncEnabled, isFalse);
    });
  });
}

const _deviceId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

ModelConfig _model(
  String id, {
  String endpoint = 'https://api.example/v1',
  Map<String, dynamic> extraParams = const {},
  bool managed = false,
  bool cloudSyncEnabled = true,
}) => ModelConfig(
  id: id,
  name: id,
  endpoint: endpoint,
  apiKey: 'top-secret',
  modelName: 'model-1',
  apiType: 'openai',
  priority: 0,
  managed: managed,
  cloudSyncEnabled: cloudSyncEnabled,
  extraParams: extraParams,
);

SyncRemoteOperation _remote(
  String table,
  String recordId,
  Map<String, dynamic> data, {
  required int seq,
}) => (
  table: table,
  op: 'upsert',
  data: data,
  change: SyncChange(
    seq: seq,
    changeId: 'remote-$seq',
    deviceId: _deviceId,
    clientCreatedAt: DateTime.utc(2026, 7, 16),
    table: table,
    op: 'upsert',
    recordId: recordId,
    data: data,
  ),
);
