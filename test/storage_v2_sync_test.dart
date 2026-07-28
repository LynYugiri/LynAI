import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/sync_change.dart';
import 'package:lynai/services/storage_v2_database.dart';
import 'package:sqlite3/sqlite3.dart';

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

    test('loads bounded outbox windows in dependency order', () async {
      const scope = 'server|user-a';
      await database.activateSyncScope(scope, deviceId: _deviceId);
      await database.batchIncremental([
        (table: 'tasks', op: 'upsert', data: _task('t1', 'task'), change: null),
        (
          table: 'task_lists',
          op: 'upsert',
          data: _taskList('l1', 'list'),
          change: null,
        ),
        (
          table: 'task_list_entries',
          op: 'upsert',
          data: _taskListEntry('t1', 'l1', updatedAt: '2026-01-01T00:00:00Z'),
          change: null,
        ),
      ]);

      final first = await database.loadSyncOutbox(scope, limit: 2);
      final second = await database.loadSyncOutbox(scope, limit: 2, offset: 2);

      expect(first.map((entry) => entry.table), ['tasks', 'task_lists']);
      expect(second.map((entry) => entry.table), ['task_list_entries']);
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

    test('recycle-bin delete preserves local selection metadata', () async {
      const scope = 'server|user-a';
      await database.writeDataFile('recycle_bin.json', {
        'items': [
          {
            'id': 'recycle-1',
            'owner': 'core',
            'category': 'conversations',
            'type': 'conversation',
            'title': 'deleted chat',
            'deletedAt': '2026-01-01T00:00:00Z',
            'payload': const <String, dynamic>{},
          },
        ],
      });
      await database.activateSyncScope(scope, deviceId: _deviceId);
      await database.acknowledgeSyncOutbox(
        scope,
        await database.loadSyncOutbox(scope),
      );

      await database.writeDataFile('recycle_bin.json', {'items': const []});

      final outbox = await database.loadSyncOutbox(scope);
      expect(outbox, hasLength(1));
      expect(outbox.single.table, 'recycle_bin');
      expect(outbox.single.op, 'delete');
      expect(outbox.single.data, isNull);
      expect(outbox.single.selectionData, {
        'id': 'recycle-1',
        'owner': 'core',
        'category': 'conversations',
        'type': 'conversation',
        'title': 'deleted chat',
        'preview': '',
        'deletedAt': '2026-01-01T00:00:00Z',
        'payload': const <String, dynamic>{},
      });
    });

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

    test('full reseed resets cloud metadata and rebuilds canonical outbox', () async {
      const scope = 'https://cloud.example|user-a';
      await database.writeDataFile('tasks.json', {
        'tasks': [_task('t1', 'snapshot')],
      });
      await database.activateSyncScope(scope, deviceId: _deviceId);
      await database.updateSyncSince(scope, 12);
      await database.batchIncremental(
        [
          _remote(
            'tasks',
            't1',
            _task('t1', 'remote'),
            seq: 13,
            changeId: 'remote-before-reseed',
          ),
        ],
        remote: true,
        scope: scope,
        nextSince: 13,
      );
      expect(await database.loadSyncConflicts(scope), hasLength(1));
      await database.close();
      final raw = sqlite3.open('${root.path}/storage_v2/app.db');
      try {
        raw.execute(
          "INSERT INTO cloud_index_states(scope, generation, status_json, updated_at) VALUES (?, 2, '{}', 'before')",
          [scope],
        );
        raw.execute(
          "INSERT INTO cloud_index_objects(scope, category, object_id, content_hash, object_json, updated_at) VALUES (?, 'tasks', 't1', 'hash', '{}', 'before')",
          [scope],
        );
        raw.execute(
          "INSERT INTO cloud_index_category_stats VALUES (?, 'tasks', 1, 'before')",
          [scope],
        );
        raw.execute(
          "INSERT INTO cloud_reseed_tasks(scope, operation_id, generation, status, operation_json, created_at, updated_at) VALUES (?, 'operation-1', 2, 'pending', ?, 'before', 'before')",
          [
            scope,
            '{"id":"operation-1","kind":"full","selectorType":"all","generation":2,"indexRevision":2,"createdAt":"2026-07-24T00:00:00Z"}',
          ],
        );
      } finally {
        raw.close();
      }

      await database.resetCloudSyncScope(scope, 3);
      final reset = await database.syncScopeState(scope);
      expect(reset.since, 0);
      expect(reset.generation, 3);
      expect(reset.fullReseedRequired, isTrue);
      expect(await database.loadSyncOutbox(scope), isEmpty);
      expect(await database.loadSyncConflicts(scope), isEmpty);

      await database.prepareFullSyncSnapshot(scope, 3);
      final prepared = await database.syncScopeState(scope);
      final outbox = await database.loadSyncOutbox(scope);
      expect(prepared.since, 0);
      expect(prepared.generation, 3);
      expect(prepared.fullReseedRequired, isFalse);
      expect(
        outbox.where((entry) => entry.table == 'tasks').single.recordId,
        't1',
      );
      expect(
        ((await database.loadDataFile('tasks.json'))?['tasks'] as List)
            .single['title'],
        'snapshot',
      );
      await database.close();
      final verified = sqlite3.open('${root.path}/storage_v2/app.db');
      try {
        final state = verified.select(
          'SELECT active, captures_local FROM sync_state WHERE scope = ?',
          [scope],
        ).single;
        expect(state['active'], 1);
        expect(state['captures_local'], 1);
        expect(
          verified.select(
            'SELECT * FROM sync_applied_changes WHERE scope = ?',
            [scope],
          ),
          isEmpty,
        );
        for (final table in [
          'cloud_index_states',
          'cloud_index_objects',
          'cloud_index_category_stats',
        ]) {
          expect(
            verified.select('SELECT * FROM $table WHERE scope = ?', [scope]),
            isEmpty,
          );
        }
        expect(
          verified.select(
            'SELECT operation_id FROM cloud_reseed_tasks WHERE scope = ?',
            [scope],
          ).single['operation_id'],
          'operation-1',
        );
      } finally {
        verified.close();
      }
    });

    test(
      'full reseed preserves deletes and blocks remote resurrection',
      () async {
        const scope = 'https://cloud.example|user-delete';
        await database.writeDataFile('tasks.json', {
          'tasks': [_task('deleted-task', 'local')],
        });
        await database.activateSyncScope(scope, deviceId: _deviceId);
        await database.writeDataFile('tasks.json', {'tasks': <Object>[]});
        expect((await database.loadSyncOutbox(scope)).single.op, 'delete');

        await database.resetCloudSyncScope(scope, 2);
        await database.prepareFullSyncSnapshot(scope, 2);
        final outbox = await database.loadSyncOutbox(scope);
        expect(outbox, hasLength(1));
        expect(outbox.single.op, 'delete');
        expect(outbox.single.recordId, 'deleted-task');

        await database.batchIncremental(
          [
            _remote(
              'tasks',
              'deleted-task',
              _task('deleted-task', 'stale remote'),
              seq: 1,
              changeId: 'stale-upsert',
            ),
          ],
          remote: true,
          scope: scope,
          nextSince: 1,
        );
        expect((await database.loadDataFile('tasks.json'))?['tasks'], isEmpty);
        expect((await database.loadSyncOutbox(scope)).single.op, 'delete');
      },
    );

    test(
      'current projection reseed removes purged clean rows and keeps pending edits',
      () async {
        const scope = 'https://cloud.example|user-projection';
        await database.writeDataFile('tasks.json', {
          'tasks': [
            _task('purged', 'purged'),
            _task('remote', 'old remote'),
            _task('pending', 'before edit'),
          ],
        });
        await database.activateSyncScope(scope, deviceId: _deviceId);
        final initial = await database.loadSyncOutbox(scope);
        await database.acknowledgeSyncOutbox(scope, initial);
        await database.writeDataFile('tasks.json', {
          'tasks': [
            _task('purged', 'purged'),
            _task('remote', 'old remote'),
            _task('pending', 'local edit'),
          ],
        });

        final changed = await database.reconcileCurrentCloudProjection(
          scope,
          2,
          9,
          [
            {
              'table': 'tasks',
              'op': 'upsert',
              'recordId': 'remote',
              'data': _task('remote', 'new remote'),
            },
            {
              'table': 'tasks',
              'op': 'upsert',
              'recordId': 'pending',
              'data': _task('pending', 'remote stale'),
            },
          ],
          {'tasks'},
        );

        final tasks =
            ((await database.loadDataFile('tasks.json'))?['tasks'] as List)
                .cast<Map>();
        expect(
          tasks.map((row) => row['id']),
          unorderedEquals(['remote', 'pending']),
        );
        expect(
          tasks.singleWhere((row) => row['id'] == 'remote')['title'],
          'new remote',
        );
        expect(
          tasks.singleWhere((row) => row['id'] == 'pending')['title'],
          'local edit',
        );
        final outbox = await database.loadSyncOutbox(scope);
        expect(outbox.map((entry) => entry.recordId), ['pending']);
        final state = await database.syncScopeState(scope);
        expect(state.generation, 2);
        expect(state.since, 9);
        expect(state.fullReseedRequired, isFalse);
        expect(changed, {'tasks'});
      },
    );

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

    test('change ids are global and payload reuse fails atomically', () async {
      const scopeA = 'https://a.example|user';
      const scopeB = 'https://b.example|user';
      await database.batchIncremental(
        [
          _remote(
            'tasks',
            'task-1',
            _task('task-1', 'scope A'),
            seq: 1,
            changeId: 'shared-change',
          ),
        ],
        remote: true,
        scope: scopeA,
        nextSince: 1,
      );
      await expectLater(
        database.batchIncremental(
          [
            _remote(
              'tasks',
              'task-1',
              _task('task-1', 'scope B', updatedAt: '2026-01-01T00:00:01Z'),
              seq: 1,
              changeId: 'shared-change',
            ),
          ],
          remote: true,
          scope: scopeB,
          nextSince: 1,
        ),
        throwsStateError,
      );

      final tasks = await database.loadDataFile('tasks.json');
      expect((tasks?['tasks'] as List).single['title'], 'scope A');
      expect(await database.syncSince(scopeB), 0);
      await database.close();
      final raw = sqlite3.open('${root.path}/storage_v2/app.db');
      try {
        final applied = raw.select(
          "SELECT scope FROM sync_applied_changes WHERE change_id = 'shared-change'",
        );
        expect(applied.map((row) => row['scope']), [scopeA]);
      } finally {
        raw.close();
      }
    });

    test('v16 to v17 preserves LAN state and resets cloud state', () async {
      final storageRoot = Directory('${root.path}/storage_v2');
      await storageRoot.create(recursive: true);
      final raw = sqlite3.open('${storageRoot.path}/app.db');
      try {
        raw.execute('''
CREATE TABLE storage_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
INSERT INTO storage_meta VALUES ('business.sentinel', 'unchanged');
CREATE TABLE sync_state (
  scope TEXT PRIMARY KEY,
  since INTEGER NOT NULL DEFAULT 0,
  initialized INTEGER NOT NULL DEFAULT 0,
  active INTEGER NOT NULL DEFAULT 0,
  captures_local INTEGER NOT NULL DEFAULT 0,
  device_id TEXT NOT NULL DEFAULT '',
  updated_at TEXT NOT NULL
);
CREATE TABLE sync_outbox (
  scope TEXT NOT NULL,
  table_name TEXT NOT NULL,
  record_id TEXT NOT NULL,
  op TEXT NOT NULL,
  data_json TEXT,
  change_id TEXT NOT NULL,
  device_id TEXT NOT NULL,
  client_created_at TEXT NOT NULL,
  mutation_version INTEGER NOT NULL,
  updated_at TEXT NOT NULL,
  PRIMARY KEY (scope, table_name, record_id)
);
CREATE TABLE sync_conflicts (
  scope TEXT NOT NULL,
  seq INTEGER NOT NULL,
  table_name TEXT NOT NULL,
  record_id TEXT NOT NULL,
  op TEXT NOT NULL,
  data_json TEXT,
  change_id TEXT NOT NULL,
  device_id TEXT NOT NULL,
  client_created_at TEXT NOT NULL,
  created_at TEXT,
  local_op TEXT NOT NULL,
  local_data_json TEXT,
  local_change_id TEXT NOT NULL,
  local_mutation_version INTEGER NOT NULL,
  PRIMARY KEY (scope, seq)
);
CREATE TABLE sync_applied_changes (
  change_id TEXT PRIMARY KEY,
  source TEXT NOT NULL,
  applied_at TEXT NOT NULL
);
INSERT INTO sync_state VALUES ('lan:v1', 8, 1, 1, 1, 'lan-device', 'before');
INSERT INTO sync_state VALUES (
  'https://cloud.example|user', 27, 1, 1, 1, 'cloud-device', 'before'
);
INSERT INTO sync_outbox VALUES (
  'lan:v1', 'tasks', 'lan-task', 'upsert', '{}', 'lan-outbox',
  'lan-device', 'before', 1, 'before'
);
INSERT INTO sync_outbox VALUES (
  'https://cloud.example|user', 'tasks', 'cloud-task', 'upsert', '{}',
  'cloud-outbox', 'cloud-device', 'before', 1, 'before'
);
INSERT INTO sync_outbox VALUES (
  'https://cloud.example|user', 'tasks', 'cloud-deleted', 'delete', NULL,
  'cloud-delete', 'cloud-device', 'before', 1, 'before'
);
INSERT INTO sync_conflicts VALUES (
  'lan:v1', 1, 'tasks', 'lan-task', 'upsert', '{}', 'lan-conflict',
  'remote', 'before', NULL, 'upsert', '{}', 'local', 1
);
INSERT INTO sync_conflicts VALUES (
  'https://cloud.example|user', 2, 'tasks', 'cloud-task', 'upsert', '{}',
  'cloud-conflict', 'remote', 'before', NULL, 'upsert', '{}', 'local', 1
);
INSERT INTO sync_applied_changes VALUES ('lan-applied', 'lan', 'before');
INSERT INTO sync_applied_changes VALUES ('cloud-applied', 'cloud', 'before');
PRAGMA user_version = 16;
''');
      } finally {
        raw.close();
      }

      await database.loadDataFile('tasks.json');
      await database.close();
      final migrated = sqlite3.open('${storageRoot.path}/app.db');
      try {
        expect(migrated.userVersion, 24);
        expect(
          migrated
              .select(
                "SELECT value FROM storage_meta WHERE key = 'business.sentinel'",
              )
              .single['value'],
          'unchanged',
        );
        final states = {
          for (final row in migrated.select('SELECT * FROM sync_state'))
            row['scope'] as String: row,
        };
        final lan = states['lan:v1']!;
        expect(lan['since'], 8);
        expect(lan['initialized'], 1);
        expect(lan['active'], 1);
        expect(lan['captures_local'], 1);
        expect(lan['device_id'], 'lan-device');
        expect(lan['generation'], 0);
        expect(lan['full_reseed_required'], 0);
        final cloud = states['https://cloud.example|user']!;
        expect(cloud['since'], 0);
        expect(cloud['initialized'], 0);
        expect(cloud['active'], 1);
        expect(cloud['captures_local'], 1);
        expect(cloud['device_id'], 'cloud-device');
        expect(cloud['generation'], 0);
        expect(cloud['full_reseed_required'], 1);

        final outbox = migrated.select(
          'SELECT scope, op, record_id FROM sync_outbox ORDER BY scope',
        );
        expect(outbox, hasLength(1));
        expect(outbox.single['scope'], 'https://cloud.example|user');
        expect(outbox.single['op'], 'delete');
        expect(
          migrated
              .select(
                "SELECT change_id FROM transport_change_heads WHERE record_id = 'lan-task'",
              )
              .single['change_id'],
          'lan-outbox',
        );
        expect(
          migrated.select('SELECT scope FROM sync_conflicts').single['scope'],
          'lan:v1',
        );
        final applied = migrated.select('SELECT * FROM sync_applied_changes');
        expect(applied, hasLength(1));
        expect(applied.single['scope'], 'lan:v1');
        expect(applied.single['change_id'], 'lan-applied');
        expect(
          migrated
              .select("SELECT name FROM sqlite_master WHERE type = 'table'")
              .map((row) => row['name']),
          containsAll({
            'cloud_index_states',
            'cloud_index_objects',
            'cloud_index_category_stats',
            'cloud_reseed_tasks',
          }),
        );
      } finally {
        migrated.close();
      }
    });
  });
}

const _deviceId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

SyncRemoteOperation _remote(
  String table,
  String recordId,
  Map<String, dynamic> data, {
  required int seq,
  String? changeId,
}) => (
  table: table,
  op: 'upsert',
  data: data,
  change: SyncChange(
    seq: seq,
    changeId: changeId ?? 'change-$seq',
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
