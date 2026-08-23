import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/services/storage_v2_database.dart';
import 'package:lynai/services/storage_v2_service.dart';
import 'package:lynai/services/storage_v2_upgrade_service.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('schema 34 migrates conversation workspace columns', () async {
    final root = await Directory.systemTemp.createTemp(
      'lynai_workspace_schema_',
    );
    final storageRoot = Directory('${root.path}/storage_v2');
    await storageRoot.create(recursive: true);
    final storage = StorageV2Database(storageRoot);
    try {
      await storage.loadDataFile('tasks.json');
      await storage.close();
      final raw = sqlite3.open('${storageRoot.path}/app.db');
      try {
        raw.execute('ALTER TABLE conversations DROP COLUMN workspace_id');
        raw.execute('ALTER TABLE conversations DROP COLUMN workspace_name');
        raw.execute('PRAGMA user_version = 33');
      } finally {
        raw.close();
      }

      final reopened = StorageV2Database(storageRoot);
      await reopened.loadDataFile('tasks.json');
      await reopened.close();

      final migrated = sqlite3.open('${storageRoot.path}/app.db');
      try {
        expect(
          migrated.userVersion,
          StorageV2DriftDatabase.currentSchemaVersion,
        );
        final columns = migrated
            .select('PRAGMA table_info(conversations)')
            .map((row) => row['name'])
            .toSet();
        expect(columns, containsAll({'workspace_id', 'workspace_name'}));
      } finally {
        migrated.close();
      }
    } finally {
      await storage.close();
      if (await root.exists()) await root.delete(recursive: true);
    }
  });

  test('workspaces.json generic file never enters sync outbox', () async {
    final root = await Directory.systemTemp.createTemp('lynai_workspace_sync_');
    final storage = StorageV2Service(rootDirectory: root);
    try {
      await StorageV2UpgradeService(storageV2: storage).ensureReady();
      await storage.activateSyncScope('lan:v1', deviceId: 'local-device');
      await storage.writeDataFile('workspaces.json', {
        'version': 1,
        'workspaces': [
          {
            'id': 'ws-1',
            'name': '项目A',
            'createdAt': DateTime.utc(2026).toIso8601String(),
            'updatedAt': DateTime.utc(2026).toIso8601String(),
          },
        ],
      });
      expect(await storage.loadSyncOutbox('lan:v1'), isEmpty);
      final loaded = await storage.loadDataFile('workspaces.json');
      expect(loaded['workspaces'], hasLength(1));
    } finally {
      await storage.close();
      if (await root.exists()) await root.delete(recursive: true);
    }
  });
}
