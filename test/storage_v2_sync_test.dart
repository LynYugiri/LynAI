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
      await database.writeDataFile('tasks.json', {
        'tasks': [_task('t1', 'first')],
      });
      final first = await database.loadSyncOutbox('server|user-a');
      final retry = await database.loadSyncOutbox('server|user-a');

      await database.writeDataFile('tasks.json', {
        'tasks': [_task('t1', 'second', updatedAt: '2026-01-01T00:00:01Z')],
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
        await database.writeDataFile('tasks.json', {
          'tasks': [_task('t1', 'while inactive')],
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
        await database.writeDataFile('tasks.json', {
          'tasks': [_task('t1', 'before')],
        });
        await database.activateSyncScope(scope, deviceId: _deviceId);
        final initial = await database.loadSyncOutbox(scope);
        await database.acknowledgeSyncOutbox(scope, initial);
        await database.deactivateSyncScope(scope);
        await database.close();

        database = StorageV2Database(Directory('${root.path}/storage_v2'));
        await database.writeDataFile('tasks.json', {'tasks': const []});
        await database.close();

        database = StorageV2Database(Directory('${root.path}/storage_v2'));
        await database.activateSyncScope(scope, deviceId: _deviceId);

        final outbox = await database.loadSyncOutbox(scope);
        expect(outbox, hasLength(1));
        expect(outbox.single.recordId, 't1');
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

      await database.writeDataFile('tasks.json', {
        'tasks': [_task('t1', 'active only')],
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
        [
          _remote(
            'calendar_events',
            'event-1',
            _calendarEvent('event-1', 'remote B'),
            seq: 1,
          ),
        ],
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
      await database.writeDataFile('calendar.json', {
        'anniversaries': [_anniversary('anniversary-1', 'local B')],
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
        await database.writeDataFile('conversations.json', {
          'conversations': [_conversation('c1', 'local')],
        });
        await database.batchIncremental(
          [
            _remote(
              'conversations',
              'c1',
              _conversation('c1', 'remote'),
              seq: 6,
            ),
            _remote(
              'conversations',
              'c2',
              _conversation('c2', 'remote-only'),
              seq: 7,
            ),
          ],
          remote: true,
          scope: scope,
          nextSince: 7,
        );

        final data = await database.loadDataFile('conversations.json');
        final conversations = (data?['conversations'] as List).cast<Map>();
        expect(
          conversations.firstWhere((row) => row['id'] == 'c1')['title'],
          'local',
        );
        expect(
          conversations.firstWhere((row) => row['id'] == 'c2')['title'],
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
        final resolved = await database.loadDataFile('conversations.json');
        expect(
          (resolved?['conversations'] as List).singleWhere(
            (row) => row['id'] == 'c1',
          )['title'],
          'remote',
        );
        expect(await database.loadSyncConflicts(scope), isEmpty);
      },
    );

    test('keeping local conflict creates a fresh outbox mutation', () async {
      const scope = 'server|user-a';
      await database.activateSyncScope(scope, deviceId: _deviceId);
      await database.writeDataFile('conversations.json', {
        'conversations': [_conversation('c1', 'local')],
      });
      await database.batchIncremental(
        [_remote('conversations', 'c1', _conversation('c1', 'remote'), seq: 6)],
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

    test(
      'message revisions and planning updatedAt resolve latest-wins',
      () async {
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
            _remote('task_lists', 'l1', _taskList('l1', 'test'), seq: 2),
            _remote('tasks', 't1', _task('t1', 'test'), seq: 3),
            _remote(
              'calendar_events',
              'event-1',
              _calendarEvent('event-1', 'test'),
              seq: 4,
            ),
            _remote(
              'anniversaries',
              'anniversary-1',
              _anniversary('anniversary-1', 'test'),
              seq: 5,
            ),
          ],
          remote: true,
          scope: scope,
          nextSince: 5,
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
            table: 'task_list_entries',
            op: 'upsert',
            data: _taskListEntry('t1', 'l1', updatedAt: '2026-01-01T00:00:00Z'),
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
            _remote(
              'task_list_entries',
              't1',
              _taskListEntry(
                't1',
                'l1',
                sortOrder: 1,
                updatedAt: '2026-01-01T00:00:01Z',
              ),
              seq: 9,
            ),
          ],
          remote: true,
          scope: scope,
          nextSince: 9,
        );

        final conversations = await database.loadDataFile('conversations.json');
        final tasks = await database.loadDataFile('tasks.json');
        expect(
          (conversations?['messages'] as List).single['content'],
          'remote',
        );
        expect((tasks?['entries'] as List).single['sortOrder'], 1);
        expect(await database.loadSyncOutbox(scope), isEmpty);
        expect(await database.loadSyncConflicts(scope), isEmpty);
      },
    );

    test('ack only removes the uploaded mutation version', () async {
      const scope = 'server|user-a';
      await database.activateSyncScope(scope, deviceId: _deviceId);
      await database.writeDataFile('tasks.json', {
        'tasks': [_task('t1', 'one')],
      });
      final uploaded = await database.loadSyncOutbox(scope);
      await database.writeDataFile('tasks.json', {
        'tasks': [_task('t1', 'two', updatedAt: '2026-01-01T00:00:01Z')],
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

Map<String, dynamic> _task(
  String id,
  String title, {
  String updatedAt = '2026-01-01T00:00:00Z',
}) => {
  'id': id,
  'title': title,
  'createdAt': '2026-01-01T00:00:00Z',
  'updatedAt': updatedAt,
};

Map<String, dynamic> _taskList(String id, String title) => {
  'id': id,
  'title': title,
  'sortOrder': 0,
  'createdAt': '2026-01-01T00:00:00Z',
  'updatedAt': '2026-01-01T00:00:00Z',
};

Map<String, dynamic> _taskListEntry(
  String taskId,
  String listId, {
  int sortOrder = 0,
  required String updatedAt,
}) => {
  'id': taskId,
  'taskId': taskId,
  'listId': listId,
  'sortOrder': sortOrder,
  'updatedAt': updatedAt,
};

Map<String, dynamic> _calendarEvent(String id, String title) => {
  'id': id,
  'title': title,
  'timeKind': 'timed',
  'startAt': '2026-07-15T10:00:00.000',
  'endAt': '2026-07-15T11:00:00.000',
  'createdAt': '2026-01-01T00:00:00Z',
  'updatedAt': '2026-01-01T00:00:00Z',
};

Map<String, dynamic> _anniversary(String id, String title) => {
  'id': id,
  'title': title,
  'month': 7,
  'day': 15,
  'recurrence': 'yearly',
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
