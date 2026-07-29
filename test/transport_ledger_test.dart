import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/sync_change.dart';
import 'package:lynai/services/storage_v2_database.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('v23 migration completes a partial transport ledger idempotently', () async {
    final root = await Directory.systemTemp.createTemp(
      'lynai_transport_migration_',
    );
    final storageRoot = Directory('${root.path}/storage_v2');
    var database = StorageV2Database(storageRoot);
    try {
      await database.ensureDatasetOwnership('dataset-a');
      await database.activateSyncScope('lan:v1', deviceId: 'device-a');
      await database.batchIncremental([
        (
          table: 'tasks',
          op: 'upsert',
          data: _task('pending-task', 'pending'),
          change: null,
        ),
        (
          table: 'tasks',
          op: 'upsert',
          data: _task('missing-task', 'missing'),
          change: null,
        ),
      ]);
      await database.close();

      var raw = sqlite3.open('${storageRoot.path}/app.db');
      try {
        raw.execute('''
DELETE FROM transport_change_heads WHERE record_id = 'missing-task';
UPDATE transport_change_heads
SET change_id = 'migrated-pending-id', mutation_version = 7
WHERE record_id = 'pending-task';
INSERT OR REPLACE INTO sync_outbox(
  scope, table_name, record_id, op, data_json, selection_data_json, change_id,
  device_id, client_created_at, mutation_version, updated_at
) SELECT 'lan:v1', table_name, record_id, op, data_json, selection_data_json,
         change_id, device_id, client_created_at, mutation_version, updated_at
FROM transport_change_heads WHERE record_id = 'pending-task';
INSERT OR REPLACE INTO sync_applied_changes(scope, change_id, source, applied_at)
VALUES ('lan:v1', 'received-change', 'lan', '2026-07-28T00:00:00Z');
INSERT OR REPLACE INTO transport_change_receipts(
  change_id, payload_hash, source, source_scope, lineage, received_at
) VALUES (
  'received-change', 'existing-hash', 'lan', 'existing-scope', 'dataset-a',
  '2026-07-28T00:00:00Z'
);
INSERT OR REPLACE INTO transport_peer_acks(
  peer_device_id, change_id, mutation_version, acknowledged_at
) VALUES ('peer-a', 'migrated-pending-id', 7, '2026-07-28T00:00:00Z');
DROP INDEX idx_transport_change_heads_change;
DROP INDEX idx_transport_peer_acks_change;
PRAGMA user_version = 23;
''');
      } finally {
        raw.close();
      }

      for (var attempt = 0; attempt < 2; attempt++) {
        database = StorageV2Database(storageRoot);
        await database.loadDataFile('tasks.json');
        await database.close();
        raw = sqlite3.open('${storageRoot.path}/app.db');
        try {
          final heads = {
            for (final row in raw.select(
              'SELECT record_id, change_id, mutation_version '
              'FROM transport_change_heads WHERE table_name = \'tasks\'',
            ))
              row['record_id'] as String: row,
          };
          expect(heads.keys, containsAll({'pending-task', 'missing-task'}));
          expect(heads['pending-task']!['change_id'], 'migrated-pending-id');
          expect(heads['pending-task']!['mutation_version'], 7);
          expect(
            raw
                .select(
                  "SELECT payload_hash FROM transport_change_receipts WHERE change_id = 'received-change'",
                )
                .single['payload_hash'],
            'existing-hash',
          );
          expect(
            raw
                .select(
                  "SELECT mutation_version FROM transport_peer_acks WHERE peer_device_id = 'peer-a' AND change_id = 'migrated-pending-id'",
                )
                .single['mutation_version'],
            7,
          );
          final indexes = raw
              .select("SELECT name FROM sqlite_master WHERE type = 'index'")
              .map((row) => row['name']);
          expect(
            indexes,
            containsAll({
              'idx_transport_change_heads_change',
              'idx_transport_peer_acks_change',
            }),
          );
          expect(
            raw.select("SELECT * FROM sync_outbox WHERE scope = 'lan:v1'"),
            isEmpty,
          );
          raw.execute('PRAGMA user_version = 23');
        } finally {
          raw.close();
        }
      }
    } finally {
      await database.close();
      if (await root.exists()) await root.delete(recursive: true);
    }
  });

  group('durable transport ledger', () {
    late Directory root;
    late StorageV2Database database;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('lynai_transport_ledger_');
      database = StorageV2Database(Directory('${root.path}/storage_v2'));
      await database.ensureDatasetOwnership('dataset-a');
      await database.activateSyncScope('lan:v1', deviceId: 'device-a');
      await database.activateSyncScope(
        'https://cloud.example|user-a',
        deviceId: 'device-a',
      );
      final initialCloud = await database.loadSyncOutbox(
        'https://cloud.example|user-a',
      );
      await database.acknowledgeSyncOutbox(
        'https://cloud.example|user-a',
        initialCloud,
      );
    });

    tearDown(() async {
      await database.close();
      if (await root.exists()) await root.delete(recursive: true);
    });

    test(
      'local mutation has one change id across LAN head and cloud outbox',
      () async {
        await database.batchIncremental([
          (
            table: 'tasks',
            op: 'upsert',
            data: _task('task-a', 'local'),
            change: null,
          ),
        ]);

        final lan = (await database.loadTransportHeadsForPeer(
          'peer-b',
        )).where((entry) => entry.table == 'tasks').toList();
        final cloud = await database.loadSyncOutbox(
          'https://cloud.example|user-a',
        );

        expect(lan.single.changeId, cloud.single.changeId);
        expect(lan.single.lineage, 'dataset-a');
      },
    );

    test('cloud ingress becomes LAN-sendable without cloud echo', () async {
      final change = _change('cloud-change', 'cloud', lineage: 'dataset-a');
      await database.batchIncremental(
        [_operation(change)],
        remote: true,
        scope: 'https://cloud.example|user-a',
        nextSince: 1,
      );

      expect(
        await database.loadSyncOutbox('https://cloud.example|user-a'),
        isEmpty,
      );
      expect(
        (await database.loadTransportHeadsForPeer(
          'peer-b',
        )).singleWhere((entry) => entry.changeId == 'cloud-change').changeId,
        'cloud-change',
      );
    });

    test(
      'LAN ingress routes once to matching cloud and not back to source peer',
      () async {
        final change = _change('flow-a-b-c', 'from A', lineage: 'dataset-a');
        await database.batchIncremental(
          [_operation(change)],
          remote: true,
          scope: 'lan:v1',
          nextSince: 0,
          appliedSource: 'lan',
          appliedSourcePeer: 'peer-a',
        );

        final cloud = await database.loadSyncOutbox(
          'https://cloud.example|user-a',
        );
        expect(cloud.single.changeId, 'flow-a-b-c');
        expect(
          (await database.loadTransportHeadsForPeer(
            'peer-a',
          )).where((entry) => entry.changeId == 'flow-a-b-c'),
          isEmpty,
        );
        expect(
          (await database.loadTransportHeadsForPeer(
            'peer-c',
          )).singleWhere((entry) => entry.changeId == 'flow-a-b-c').changeId,
          'flow-a-b-c',
        );

        await database.close();
        database = StorageV2Database(Directory('${root.path}/storage_v2'));
        expect(
          (await database.loadSyncOutbox(
            'https://cloud.example|user-a',
          )).single.changeId,
          'flow-a-b-c',
        );
      },
    );

    test(
      'foreign or absent lineage is never routed into the account cloud',
      () async {
        for (final change in [
          _change('foreign', 'foreign', lineage: 'dataset-b'),
          _change('legacy', 'legacy'),
        ]) {
          await database.batchIncremental(
            [_operation(change)],
            remote: true,
            scope: 'lan:v1',
            nextSince: 0,
            appliedSource: 'lan',
            appliedSourcePeer: 'peer-a',
          );
        }

        expect(
          await database.loadSyncOutbox('https://cloud.example|user-a'),
          isEmpty,
        );
      },
    );

    test(
      'durable peer ACK state is not bounded to 10000 entries',
      () async {
        await database.importLegacyLanTransportState(const [], {
          'peer-b': List.generate(10050, (index) => 'change-$index'),
        });
        await database.close();
        final raw = sqlite3.open('${root.path}/storage_v2/app.db');
        try {
          expect(
            raw
                .select(
                  "SELECT COUNT(*) AS count FROM transport_peer_acks WHERE peer_device_id = 'peer-b'",
                )
                .single['count'],
            10050,
          );
        } finally {
          raw.close();
        }
        database = StorageV2Database(Directory('${root.path}/storage_v2'));
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test('LAN conflict waits for resolution before forwarding', () async {
      await database.batchIncremental([
        (
          table: 'conversations',
          op: 'upsert',
          data: _conversation('conversation-a', 'local'),
          change: null,
        ),
      ]);
      final incoming = SyncChange(
        seq: 7,
        changeId: 'lan-conflict',
        deviceId: 'remote-device',
        clientCreatedAt: DateTime.utc(2026, 7, 28),
        table: 'conversations',
        op: 'upsert',
        recordId: 'conversation-a',
        data: _conversation('conversation-a', 'remote'),
        lineage: 'dataset-a',
      );
      await database.batchIncremental(
        [_operation(incoming)],
        remote: true,
        scope: 'lan:v1',
        nextSince: 0,
        appliedSource: 'lan',
        appliedSourcePeer: 'peer-a',
      );

      expect(
        (await database.loadSyncOutbox(
          'https://cloud.example|user-a',
        )).where((entry) => entry.changeId == 'lan-conflict'),
        isEmpty,
      );
      final conflict = (await database.loadSyncConflicts('lan:v1')).single;
      await database.resolveSyncConflict(
        'lan:v1',
        conflict.seq,
        SyncConflictResolution.useRemote,
      );

      expect(
        (await database.loadSyncOutbox(
          'https://cloud.example|user-a',
        )).single.changeId,
        'lan-conflict',
      );
      expect(
        (await database.loadTransportHeadsForPeer(
          'peer-a',
        )).where((entry) => entry.changeId == 'lan-conflict'),
        isEmpty,
      );
    });
  });
}

Map<String, dynamic> _task(String id, String title) => {
  'id': id,
  'title': title,
  'createdAt': '2026-01-01T00:00:00Z',
  'updatedAt': '2026-01-01T00:00:00Z',
};

Map<String, dynamic> _conversation(String id, String title) => {
  'id': id,
  'title': title,
  'modelId': '',
  'settings': const <String, dynamic>{},
  'roleId': 'default',
  'createdAt': '2026-01-01T00:00:00Z',
  'updatedAt': '2026-01-01T00:00:00Z',
};

SyncChange _change(String changeId, String title, {String? lineage}) =>
    SyncChange(
      seq: 1,
      changeId: changeId,
      deviceId: 'remote-device',
      clientCreatedAt: DateTime.utc(2026, 7, 28),
      table: 'tasks',
      op: 'upsert',
      recordId: changeId,
      data: _task(changeId, title),
      lineage: lineage,
    );

SyncRemoteOperation _operation(SyncChange change) =>
    (table: change.table, op: change.op, data: change.data, change: change);
