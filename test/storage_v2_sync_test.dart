import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/sync_change.dart';
import 'package:lynai/services/storage_v2_database.dart';

void main() {
  group('StorageV2 sync persistence', () {
    late Directory root;
    late StorageV2Database database;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('lynai_sync_storage_');
      database = StorageV2Database(Directory('${root.path}/storage_v2'));
    });

    tearDown(() async {
      await database.close();
      if (await root.exists()) await root.delete(recursive: true);
    });

    test('folds repeated row mutations and keeps scopes isolated', () async {
      await database.activateSyncScope('server|user-a', deviceId: _deviceId);
      await database.writeDataFile('schedules.json', {
        'schedules': [_schedule('s1', 'first')],
      });
      final first = await database.loadSyncOutbox('server|user-a');
      final retry = await database.loadSyncOutbox('server|user-a');

      await database.writeDataFile('schedules.json', {
        'schedules': [_schedule('s1', 'second')],
      });
      final folded = await database.loadSyncOutbox('server|user-a');
      await database.activateSyncScope('server|user-b', deviceId: _deviceId);
      final otherScope = await database.loadSyncOutbox('server|user-b');

      expect(first, hasLength(1));
      expect(retry.single.changeId, first.single.changeId);
      expect(retry.single.clientCreatedAt, first.single.clientCreatedAt);
      expect(folded, hasLength(1));
      expect(folded.single.data?['title'], 'second');
      expect(folded.single.changeId, isNot(first.single.changeId));
      expect(
        folded.single.mutationVersion,
        greaterThan(first.single.mutationVersion),
      );
      expect(otherScope, isEmpty);
    });

    test(
      'inactive initialized scope captures upserts across restart',
      () async {
        const scope = 'server|user-a';
        await database.activateSyncScope(scope, deviceId: _deviceId);
        await database.deactivateSyncScope(scope);
        await database.close();

        database = StorageV2Database(Directory('${root.path}/storage_v2'));
        await database.writeDataFile('schedules.json', {
          'schedules': [_schedule('s1', 'while inactive')],
        });
        await database.close();

        database = StorageV2Database(Directory('${root.path}/storage_v2'));
        await database.activateSyncScope(scope, deviceId: _deviceId);

        final outbox = await database.loadSyncOutbox(scope);
        expect(outbox, hasLength(1));
        expect(outbox.single.op, 'upsert');
        expect(outbox.single.data?['title'], 'while inactive');
      },
    );

    test(
      'inactive initialized scope captures deletes across restart',
      () async {
        const scope = 'server|user-a';
        await database.writeDataFile('schedules.json', {
          'schedules': [_schedule('s1', 'before')],
        });
        await database.activateSyncScope(scope, deviceId: _deviceId);
        final initial = await database.loadSyncOutbox(scope);
        await database.acknowledgeSyncOutbox(scope, initial);
        await database.deactivateSyncScope(scope);
        await database.close();

        database = StorageV2Database(Directory('${root.path}/storage_v2'));
        await database.writeDataFile('schedules.json', {'schedules': const []});
        await database.close();

        database = StorageV2Database(Directory('${root.path}/storage_v2'));
        await database.activateSyncScope(scope, deviceId: _deviceId);

        final outbox = await database.loadSyncOutbox(scope);
        expect(outbox, hasLength(1));
        expect(outbox.single.recordId, 's1');
        expect(outbox.single.op, 'delete');
        expect(outbox.single.data, isNull);
      },
    );

    test('binding another account transfers local capture ownership', () async {
      const inactiveScope = 'server|user-a';
      const activeScope = 'server|user-b';
      await database.activateSyncScope(inactiveScope, deviceId: _deviceId);
      await database.deactivateSyncScope(inactiveScope);
      await database.activateSyncScope(activeScope, deviceId: _deviceId);

      await database.writeDataFile('schedules.json', {
        'schedules': [_schedule('s1', 'active only')],
      });

      expect(await database.loadSyncOutbox(inactiveScope), isEmpty);
      expect(await database.loadSyncOutbox(activeScope), hasLength(1));

      await database.activateSyncScope(inactiveScope, deviceId: _deviceId);
      final caughtUp = await database.loadSyncOutbox(inactiveScope);
      expect(caughtUp, isEmpty);
    });

    test('remote apply under B never enters A outbox', () async {
      const scopeA = 'server|user-a';
      const scopeB = 'server|user-b';
      await database.activateSyncScope(scopeA, deviceId: _deviceId);
      await database.acknowledgeSyncOutbox(
        scopeA,
        await database.loadSyncOutbox(scopeA),
      );
      await database.deactivateSyncScope(scopeA);
      await database.activateSyncScope(scopeB, deviceId: _deviceId);
      await database.batchIncremental(
        [_remote('schedules', 's1', _schedule('s1', 'remote B'), seq: 1)],
        remote: true,
        scope: scopeB,
        nextSince: 1,
      );

      await database.activateSyncScope(scopeA, deviceId: _deviceId);

      expect(await database.loadSyncOutbox(scopeA), isEmpty);
    });

    test('local mutations after B binds belong only to B', () async {
      const scopeA = 'server|user-a';
      const scopeB = 'server|user-b';
      await database.activateSyncScope(scopeA, deviceId: _deviceId);
      await database.acknowledgeSyncOutbox(
        scopeA,
        await database.loadSyncOutbox(scopeA),
      );
      await database.deactivateSyncScope(scopeA);
      await database.activateSyncScope(scopeB, deviceId: _deviceId);
      await database.writeDataFile('schedules.json', {
        'schedules': [_schedule('s1', 'local B')],
      });

      expect(await database.loadSyncOutbox(scopeA), isEmpty);
      expect(
        (await database.loadSyncOutbox(scopeB)).single.data?['title'],
        'local B',
      );
    });

    test(
      'remote conflicts are durable and require explicit resolution',
      () async {
        const scope = 'server|user-a';
        await database.activateSyncScope(scope, deviceId: _deviceId);
        await database.writeDataFile('schedules.json', {
          'schedules': [_schedule('s1', 'local')],
        });
        await database.batchIncremental(
          [
            _remote('schedules', 's1', _schedule('s1', 'remote'), seq: 6),
            _remote('schedules', 's2', _schedule('s2', 'remote-only'), seq: 7),
          ],
          remote: true,
          scope: scope,
          nextSince: 7,
        );

        final data = await database.loadDataFile('schedules.json');
        final schedules = (data?['schedules'] as List).cast<Map>();
        expect(
          schedules.firstWhere((row) => row['id'] == 's1')['title'],
          'local',
        );
        expect(
          schedules.firstWhere((row) => row['id'] == 's2')['title'],
          'remote-only',
        );
        expect(await database.syncSince(scope), 7);
        expect(await database.loadSyncOutbox(scope), isEmpty);
        final conflicts = await database.loadSyncConflicts(scope);
        expect(conflicts, hasLength(1));
        expect(conflicts.single.localData?['title'], 'local');
        expect(conflicts.single.remoteData?['title'], 'remote');

        await database.resolveSyncConflict(
          scope,
          conflicts.single.seq,
          SyncConflictResolution.useRemote,
        );
        final resolved = await database.loadDataFile('schedules.json');
        expect(
          (resolved?['schedules'] as List).singleWhere(
            (row) => row['id'] == 's1',
          )['title'],
          'remote',
        );
        expect(await database.loadSyncConflicts(scope), isEmpty);
      },
    );

    test('keeping local conflict creates a fresh outbox mutation', () async {
      const scope = 'server|user-a';
      await database.activateSyncScope(scope, deviceId: _deviceId);
      await database.writeDataFile('schedules.json', {
        'schedules': [_schedule('s1', 'local')],
      });
      await database.batchIncremental(
        [_remote('schedules', 's1', _schedule('s1', 'remote'), seq: 6)],
        remote: true,
        scope: scope,
        nextSince: 6,
      );
      final conflict = (await database.loadSyncConflicts(scope)).single;

      await database.resolveSyncConflict(
        scope,
        conflict.seq,
        SyncConflictResolution.keepLocal,
      );

      final outbox = await database.loadSyncOutbox(scope);
      expect(outbox, hasLength(1));
      expect(outbox.single.data?['title'], 'local');
    });

    test('message revisions and todo updatedAt resolve latest-wins', () async {
      const scope = 'server|user-a';
      await database.activateSyncScope(scope, deviceId: _deviceId);
      await database.batchIncremental(
        [
          _remote('conversations', 'c1', {
            'id': 'c1',
            'title': 'test',
            'modelId': '',
            'settings': const <String, dynamic>{},
            'roleId': 'default',
            'createdAt': '2026-01-01T00:00:00Z',
            'updatedAt': '2026-01-01T00:00:00Z',
          }, seq: 1),
          _remote('todo_lists', 'l1', {
            'id': 'l1',
            'title': 'test',
            'createdAt': '2026-01-01T00:00:00Z',
            'updatedAt': '2026-01-01T00:00:00Z',
          }, seq: 2),
        ],
        remote: true,
        scope: scope,
        nextSince: 2,
      );
      await database.batchIncremental([
        (
          table: 'messages',
          op: 'upsert',
          data: {
            'id': 'm1',
            'conversationId': 'c1',
            'role': 'user',
            'content': 'local',
            'timestamp': '2026-01-01T00:00:00Z',
            'revision': 1,
            'updatedAt': '2026-01-01T00:00:00Z',
          },
          change: null,
        ),
        (
          table: 'todo_items',
          op: 'upsert',
          data: {
            'id': 't1',
            'listId': 'l1',
            'text': 'local',
            'done': false,
            'sortOrder': 0,
            'updatedAt': '2026-01-01T00:00:00Z',
          },
          change: null,
        ),
      ]);

      await database.batchIncremental(
        [
          _remote('messages', 'm1', {
            'id': 'm1',
            'conversationId': 'c1',
            'role': 'user',
            'content': 'remote',
            'timestamp': '2026-01-01T00:00:00Z',
            'revision': 2,
            'updatedAt': '2026-01-01T00:00:01Z',
          }, seq: 8),
          _remote('todo_items', 't1', {
            'id': 't1',
            'listId': 'l1',
            'text': 'remote',
            'done': true,
            'sortOrder': 0,
            'updatedAt': '2026-01-01T00:00:01Z',
          }, seq: 9),
        ],
        remote: true,
        scope: scope,
        nextSince: 9,
      );

      final conversations = await database.loadDataFile('conversations.json');
      final todos = await database.loadDataFile('todo_lists.json');
      expect((conversations?['messages'] as List).single['content'], 'remote');
      expect((todos?['todoItems'] as List).single['text'], 'remote');
      expect(await database.loadSyncOutbox(scope), isEmpty);
      expect(await database.loadSyncConflicts(scope), isEmpty);
    });

    test('ack only removes the uploaded mutation version', () async {
      const scope = 'server|user-a';
      await database.activateSyncScope(scope, deviceId: _deviceId);
      await database.writeDataFile('schedules.json', {
        'schedules': [_schedule('s1', 'one')],
      });
      final uploaded = await database.loadSyncOutbox(scope);
      await database.writeDataFile('schedules.json', {
        'schedules': [_schedule('s1', 'two')],
      });

      await database.acknowledgeSyncOutbox(scope, uploaded);

      final retained = await database.loadSyncOutbox(scope);
      expect(retained, hasLength(1));
      expect(retained.single.data?['title'], 'two');

      await database.acknowledgeSyncOutbox(scope, [
        SyncOutboxEntry(
          table: retained.single.table,
          recordId: retained.single.recordId,
          op: retained.single.op,
          data: retained.single.data,
          changeId: '${retained.single.changeId}-wrong',
          deviceId: retained.single.deviceId,
          clientCreatedAt: retained.single.clientCreatedAt,
          mutationVersion: retained.single.mutationVersion,
        ),
      ]);
      expect(await database.loadSyncOutbox(scope), hasLength(1));
    });

    test('resources snapshot diff includes roamable content only', () async {
      const scope = 'server|user-a';
      await database.activateSyncScope(scope, deviceId: _deviceId);
      await database.writeDataFile('resources.json', {
        'resources': [
          _resource('attachment', role: 'message_attachment'),
          _resource('image', role: 'message_image'),
          _resource('background', role: 'background'),
          _resource('plugin', role: 'plugin'),
        ],
      });

      final outbox = await database.loadSyncOutbox(scope);

      expect(
        outbox
            .where((entry) => entry.table == 'resources')
            .map((entry) => entry.recordId),
        unorderedEquals(['attachment', 'image', 'background']),
      );
    });

    test('remote resources apply incrementally without outbox echo', () async {
      const scope = 'server|user-a';
      await database.activateSyncScope(scope, deviceId: _deviceId);

      await database.batchIncremental(
        [
          _remote(
            'resources',
            'remote',
            _resource('remote', role: 'message_attachment'),
            seq: 4,
          ),
        ],
        remote: true,
        scope: scope,
        nextSince: 4,
      );

      final data = await database.loadDataFile('resources.json');
      expect(data?['resources'], hasLength(1));
      expect((data?['resources'] as List).single['id'], 'remote');
      expect(await database.loadSyncOutbox(scope), isEmpty);
      expect(await database.syncSince(scope), 4);
    });
  });
}

const _deviceId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

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
    changeId: 'change-$seq',
    deviceId: _deviceId,
    clientCreatedAt: DateTime.utc(2026, 7, 16),
    table: table,
    op: 'upsert',
    recordId: recordId,
    data: data,
  ),
);

Map<String, dynamic> _schedule(String id, String title) => {
  'id': id,
  'title': title,
  'start': '2026-07-15T10:00:00.000',
  'end': '2026-07-15T11:00:00.000',
  'kind': 'schedule',
};

Map<String, dynamic> _resource(String id, {required String role}) => {
  'id': id,
  'kind': 'documents',
  'role': role,
  'originalPath': '',
  'originalName': '$id.txt',
  'relativePath':
      'assets/blobs/aa/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  'mimeType': 'text/plain',
  'size': 3,
  'sha256': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  'missing': false,
};
