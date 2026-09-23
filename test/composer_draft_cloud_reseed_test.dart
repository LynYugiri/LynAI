import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/sync_change.dart';
import 'package:lynai/models/sync_data_selection.dart';
import 'package:lynai/services/storage_v2_database.dart';

void main() {
  group('composer draft cloud reseed', () {
    late Directory root;
    late StorageV2Database database;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('lynai_draft_reseed_');
      database = StorageV2Database(Directory('${root.path}/storage_v2'));
    });

    tearDown(() async {
      await database.close();
      if (await root.exists()) await root.delete(recursive: true);
    });

    test('every table accepted from a projection is authoritative', () {
      const selection = SyncDataSelection.all;
      final authoritative = _tablesForSelection(selection);
      for (final table in SyncDataRegistry.syncedTables) {
        if (!SyncDataRegistry.allowsChange(
          selection,
          table,
          _projectionRecord(table),
        )) {
          continue;
        }
        expect(
          authoritative,
          contains(table),
          reason:
              '$table accepts projection records but never becomes '
              'authoritative, so reseed throws on it',
        );
      }
    });

    test('inbound draft deletes follow the conversations selection', () {      const conversations = SyncDataSelection({SyncDataCategory.conversations});
      const notes = SyncDataSelection({SyncDataCategory.notes});
      // 删除变更只带 id（LAN 甚至连 id 都不在 data 里），分类只能退化成
      // 「无 data」判断：按对话分区决定是否接受，而不是静默丢弃或报策略错误。
      expect(
        SyncDataRegistry.allowsChange(conversations, 'composer_drafts', null),
        isTrue,
      );
      expect(
        SyncDataRegistry.allowsChange(notes, 'composer_drafts', null),
        isFalse,
      );
      // 未创建对话的草稿仍然不进任何分区。
      expect(
        SyncDataRegistry.allowsChange(conversations, 'composer_drafts', const {
          'id': 'new',
        }),
        isFalse,
      );
    });

    test('reseed applies a cloud conversation draft', () async {
      const scope = 'https://cloud.example|user-draft';
      await database.activateSyncScope(scope, deviceId: _deviceId);
      await database.acknowledgeSyncOutbox(
        scope,
        await database.loadSyncOutbox(scope),
      );

      final changed = await database.reconcileCurrentCloudProjection(
        scope,
        2,
        1,
        [
          {
            'table': 'composer_drafts',
            'op': 'upsert',
            'recordId': 'conversation-1',
            'data': {
              'id': 'conversation-1',
              'conversationId': 'conversation-1',
              'draft': {
                'segments': [
                  {'type': 'text', 'text': 'cloud draft'},
                ],
                'attachments': <Object?>[],
              },
              'updatedAt': '2026-09-23T00:00:00Z',
            },
          },
        ],
        _tablesForSelection(SyncDataSelection.all),
      );

      expect(changed, contains('composer_drafts'));
      final drafts =
          ((await database.loadDataFile('composer_drafts.json'))?['drafts']
                  as List)
              .cast<Map>();
      expect(drafts.single['id'], 'conversation-1');
    });

    test('incremental remote draft change applies', () async {
      const scope = 'https://cloud.example|user-draft';
      await database.activateSyncScope(scope, deviceId: _deviceId);
      await database.acknowledgeSyncOutbox(
        scope,
        await database.loadSyncOutbox(scope),
      );

      await database.batchIncremental(
        [
          (
            table: 'composer_drafts',
            op: 'upsert',
            data: _draftRecord('conversation-1', 'cloud draft'),
            change: SyncChange(
              seq: 1,
              changeId: 'change-1',
              deviceId: _deviceId,
              clientCreatedAt: DateTime.utc(2026, 9, 23),
              table: 'composer_drafts',
              op: 'upsert',
              recordId: 'conversation-1',
            ),
          ),
        ],
        remote: true,
        scope: scope,
        nextSince: 1,
      );

      final drafts =
          ((await database.loadDataFile('composer_drafts.json'))?['drafts']
                  as List)
              .cast<Map>();
      expect(drafts.single['id'], 'conversation-1');
    });

    test('远端删除对话会一并清掉它的草稿行', () async {
      const scope = 'https://cloud.example|user-draft';
      await database.activateSyncScope(scope, deviceId: _deviceId);
      await database.acknowledgeSyncOutbox(
        scope,
        await database.loadSyncOutbox(scope),
      );
      await database.writeDataFile('composer_drafts.json', {
        'drafts': [_draftRecord('conversation-1', 'draft')],
      });
      await database.acknowledgeSyncOutbox(
        scope,
        await database.loadSyncOutbox(scope),
      );

      await database.batchIncremental(
        [
          (
            table: 'conversations',
            op: 'delete',
            data: {'id': 'conversation-1'},
            change: SyncChange(
              seq: 1,
              changeId: 'change-1',
              deviceId: _deviceId,
              clientCreatedAt: DateTime.utc(2026, 9, 23),
              table: 'conversations',
              op: 'delete',
              recordId: 'conversation-1',
            ),
          ),
        ],
        remote: true,
        scope: scope,
        nextSince: 1,
      );

      // 草稿属于对话：对话被远端删掉后草稿行不能留成孤儿，否则它会一直参与
      // 同步与备份。
      final drafts =
          ((await database.loadDataFile('composer_drafts.json'))?['drafts']
              as List);
      expect(drafts, isEmpty);
    });

    test('clearing a bound draft produces an uploadable delete', () async {
      const scope = 'https://cloud.example|user-draft';
      await database.activateSyncScope(scope, deviceId: _deviceId);
      await database.acknowledgeSyncOutbox(
        scope,
        await database.loadSyncOutbox(scope),
      );

      await database.writeDataFile('composer_drafts.json', {
        'drafts': [_draftRecord('conversation-1', 'draft')],
      });
      await database.acknowledgeSyncOutbox(
        scope,
        await database.loadSyncOutbox(scope),
      );

      await database.writeDataFile('composer_drafts.json', {
        'drafts': <Object?>[],
      });

      final outbox = (await database.loadSyncOutbox(scope))
          .where((entry) => entry.table == 'composer_drafts')
          .toList(growable: false);
      expect(outbox, hasLength(1));
      final deletion = outbox.single;
      expect(deletion.op, 'delete');
      expect(
        SyncDataRegistry.allowsChange(
          const SyncDataSelection({SyncDataCategory.conversations}),
          deletion.table,
          SyncDataRegistry.selectionData(deletion.data, deletion.selectionData),
        ),
        isTrue,
        reason: 'a cleared draft must stay selectable so the delete uploads',
      );
    });
  });
}

/// Mirrors `SyncProvider._tablesForSelection`.
Set<String> _tablesForSelection(SyncDataSelection selection) => {
  for (final table in SyncDataRegistry.syncedTables)
    if (SyncDataRegistry.allowsChange(selection, table, null)) table,
  if (selection.contains(SyncDataCategory.staticResources)) 'resources',
};

Map<String, dynamic> _projectionRecord(String table) => switch (table) {
  'composer_drafts' => {'conversationId': 'conversation-1'},
  'resources' => {'role': 'message_attachment'},
  _ => {'id': 'record-1'},
};

Map<String, dynamic> _draftRecord(String conversationId, String text) => {
  'id': conversationId,
  'conversationId': conversationId,
  'draft': {
    'segments': [
      {'type': 'text', 'text': text},
    ],
    'attachments': <Object?>[],
  },
  'updatedAt': '2026-09-23T00:00:00Z',
};

const _deviceId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
