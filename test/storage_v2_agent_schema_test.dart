import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/agent_persistence.dart';
import 'package:lynai/models/agent_runtime.dart';
import 'package:lynai/repositories/agent_persistence_repository.dart';
import 'package:lynai/services/storage_v2_database.dart';
import 'package:lynai/services/storage_v2_service.dart';
import 'package:lynai/services/storage_v2_upgrade_service.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('schema 21 migrates Agent tables and permission policy index', () async {
    final root = await Directory.systemTemp.createTemp('lynai_agent_schema_');
    final storageRoot = Directory('${root.path}/storage_v2');
    await storageRoot.create(recursive: true);
    final storage = StorageV2Database(storageRoot);
    try {
      await storage.loadDataFile('tasks.json');
      await storage.close();
      final raw = sqlite3.open('${storageRoot.path}/app.db');
      try {
        for (final table in [
          'runs',
          'turns',
          'items',
          'tool_calls',
          'snapshots',
          'mcp_servers',
        ]) {
          raw.execute('DROP TABLE $table');
        }
        raw.execute('PRAGMA user_version = 21');
      } finally {
        raw.close();
      }

      final reopened = StorageV2Database(storageRoot);
      await reopened.loadDataFile('tasks.json');
      await reopened.close();
      final migrated = sqlite3.open('${storageRoot.path}/app.db');
      try {
        expect(migrated.userVersion, 24);
        final tables = migrated
            .select("SELECT name FROM sqlite_master WHERE type = 'table'")
            .map((row) => row['name'])
            .toSet();
        expect(
          tables,
          containsAll({
            'runs',
            'turns',
            'items',
            'tool_calls',
            'snapshots',
            'mcp_servers',
          }),
        );
        final indexes = migrated
            .select("SELECT name FROM sqlite_master WHERE type = 'index'")
            .map((row) => row['name'])
            .toSet();
        expect(
          indexes,
          containsAll({
            'idx_turns_run_index',
            'idx_items_turn_index',
            'idx_tool_calls_item',
            'idx_snapshots_run_created',
            'idx_snapshots_permission_policy_run',
          }),
        );
      } finally {
        migrated.close();
      }
    } finally {
      await storage.close();
      if (await root.exists()) await root.delete(recursive: true);
    }
  });

  test('Agent rows never enter sync outbox', () async {
    final root = await Directory.systemTemp.createTemp('lynai_agent_sync_');
    final storage = StorageV2Service(rootDirectory: root);
    try {
      await StorageV2UpgradeService(storageV2: storage).ensureReady();
      await storage.activateSyncScope('lan:v1', deviceId: 'local-device');
      final now = DateTime.utc(2026, 7, 27);
      await AgentPersistenceRepository(storage).createRun(
        AgentRunRecord(
          id: 'local-run',
          status: AgentRunStatus.queued,
          createdAt: now,
          updatedAt: now,
        ),
      );

      expect(await storage.loadSyncOutbox('lan:v1'), isEmpty);
      await storage.close();
      final db = sqlite3.open('${root.path}/storage_v2/app.db');
      try {
        expect(db.select('SELECT * FROM runs'), hasLength(1));
        expect(
          db.select("SELECT * FROM snapshots WHERE kind = 'permission_policy'"),
          hasLength(1),
        );
        expect(db.select('SELECT * FROM sync_outbox'), isEmpty);
      } finally {
        db.close();
      }
    } finally {
      await storage.close();
      if (await root.exists()) await root.delete(recursive: true);
    }
  });
}
