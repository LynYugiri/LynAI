import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/sync_change.dart';
import 'package:lynai/services/storage_v2_database.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  group('Storage v15 planning schema', () {
    late Directory root;
    late Directory storageRoot;
    late StorageV2Database storage;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('lynai_planning_v15_');
      storageRoot = Directory('${root.path}/storage_v2');
      await storageRoot.create(recursive: true);
      storage = StorageV2Database(storageRoot);
    });

    tearDown(() async {
      await storage.close();
      if (await root.exists()) await root.delete(recursive: true);
    });

    test(
      'migrates v14 planning and forces canonical sync rebaseline',
      () async {
        await storage.loadDataFile('tasks.json');
        await storage.close();
        storage = StorageV2Database(storageRoot);
        final raw = sqlite3.open('${storageRoot.path}/app.db');
        try {
          raw.execute('''
DROP TABLE task_list_entries;
DROP TABLE task_lists;
DROP TABLE tasks;
DROP TABLE calendar_events;
DROP TABLE anniversaries;
CREATE TABLE schedules (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  start_time TEXT NOT NULL,
  end_time TEXT NOT NULL,
  note TEXT,
  kind TEXT NOT NULL
);
CREATE TABLE todo_lists (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE TABLE todo_items (
  id TEXT PRIMARY KEY,
  list_id TEXT NOT NULL,
  text TEXT NOT NULL,
  done INTEGER NOT NULL,
  sort_order INTEGER NOT NULL,
  updated_at TEXT NOT NULL DEFAULT ''
);
INSERT INTO todo_lists VALUES (
  'list-1', 'Inbox', '2026-07-01T08:00:00.000', '2026-07-02T09:00:00.000'
);
INSERT INTO todo_items VALUES ('shared', 'list-1', 'Done', 1, 0, '');
INSERT INTO todo_items VALUES (
  'todo-2', 'list-1', 'Open', 0, 1, '2026-07-03T10:00:00.000'
);
INSERT INTO schedules VALUES (
  'shared', 'Scheduled task', '2026-07-04T11:30:00.000',
  '2026-07-04T11:31:00.000', 'task note', 'task'
);
INSERT INTO schedules VALUES (
  'event-1', 'Meeting', '2026-07-05T12:00:00.000',
  '2026-07-05T13:00:00.000', 'event note', ''
);
INSERT INTO sync_outbox VALUES (
  'scope', 'schedules', 'event-1', 'upsert', NULL, 'c1', 'd', 'now', 1, 'now'
);
INSERT INTO sync_outbox VALUES (
  'scope', 'conversations', 'conversation-1', 'delete', NULL,
  'unrelated-change', 'device-before', '2026-07-01T00:00:00Z', 3,
  '2026-07-01T00:00:00Z'
);
INSERT INTO sync_conflicts VALUES (
  'scope', 1, 'todo_items', 'shared', 'upsert', NULL, 'c2', 'd', 'now', NULL,
  'upsert', NULL, 'c3', 1
);
INSERT INTO sync_conflicts VALUES (
  'scope', 2, 'conversations', 'conversation-2', 'delete', NULL,
  'unrelated-remote', 'remote-device', 'before', NULL,
  'upsert', '{}', 'unrelated-local', 2
);
INSERT INTO sync_scope_baselines VALUES (
  'scope', 'todo_lists', 'list-1', '{}'
);
INSERT INTO sync_scope_baselines VALUES (
  'scope', 'conversations', 'conversation-1', '{}'
);
INSERT INTO sync_state VALUES (
  'scope', 47, 1, 1, 1, 'device-before', 'before'
);
PRAGMA user_version = 14;
''');
        } finally {
          raw.close();
        }

        final tasks = await storage.loadDataFile('tasks.json');
        final calendar = await storage.loadDataFile('calendar.json');

        expect((tasks?['lists'] as List).single['sortOrder'], 0);
        final migratedTasks = (tasks?['tasks'] as List).cast<Map>();
        final done = migratedTasks.singleWhere((row) => row['id'] == 'shared');
        expect(done['completedAt'], '2026-07-02T09:00:00.000');
        expect(done['updatedAt'], '2026-07-02T09:00:00.000');
        final scheduled = migratedTasks.singleWhere(
          (row) => row['id'] == 'legacy-schedule-task-shared',
        );
        expect(scheduled['plannedDate'], '2026-07-04');
        expect(scheduled['plannedTime'], '11:30');
        expect(scheduled['note'], 'task note');
        expect((tasks?['entries'] as List), hasLength(2));

        final event = (calendar?['events'] as List).single as Map;
        expect(event['id'], 'event-1');
        expect(event['timeKind'], 'timed');
        expect(event['startAt'], '2026-07-05T12:00:00.000');
        expect(event['note'], 'event note');
        expect(event['reminders'], isEmpty);

        final migrated = sqlite3.open('${storageRoot.path}/app.db');
        try {
          expect(migrated.userVersion, 15);
          final tables = migrated
              .select("SELECT name FROM sqlite_master WHERE type = 'table'")
              .map((row) => row['name'])
              .toSet();
          expect(
            tables,
            containsAll(['tasks', 'task_lists', 'task_list_entries']),
          );
          expect(tables, containsAll(['calendar_events', 'anniversaries']));
          expect(tables, isNot(contains('schedules')));
          expect(tables, isNot(contains('todo_lists')));
          expect(tables, isNot(contains('todo_items')));
          final state = migrated
              .select("SELECT * FROM sync_state WHERE scope = 'scope'")
              .single;
          expect(state['since'], 47);
          expect(state['initialized'], 0);
          expect(state['active'], 1);
          expect(state['captures_local'], 1);
          expect(state['device_id'], 'device-before');
          final outbox = migrated.select('SELECT * FROM sync_outbox');
          expect(outbox, hasLength(1));
          expect(outbox.single['table_name'], 'conversations');
          expect(outbox.single['change_id'], 'unrelated-change');
          final conflicts = migrated.select('SELECT * FROM sync_conflicts');
          expect(conflicts, hasLength(1));
          expect(conflicts.single['table_name'], 'conversations');
          expect(conflicts.single['change_id'], 'unrelated-remote');
          final baselines = migrated.select(
            'SELECT * FROM sync_scope_baselines',
          );
          expect(baselines, hasLength(1));
          expect(baselines.single['table_name'], 'conversations');
        } finally {
          migrated.close();
        }

        await storage.activateSyncScope('scope', deviceId: 'device-after');

        expect(await storage.syncSince('scope'), 47);
        final outbox = await storage.loadSyncOutbox('scope');
        expect(
          outbox.map((entry) => '${entry.table}:${entry.recordId}'),
          containsAll({
            'tasks:shared',
            'tasks:todo-2',
            'tasks:legacy-schedule-task-shared',
            'task_lists:list-1',
            'task_list_entries:shared',
            'task_list_entries:todo-2',
            'calendar_events:event-1',
            'conversations:conversation-1',
          }),
        );
        expect(
          outbox.where(
            (entry) =>
                entry.table == 'conversations' &&
                entry.recordId == 'conversation-1',
          ),
          hasLength(1),
        );
        expect(outbox.any((entry) => entry.table == 'schedules'), isFalse);
        expect(outbox.any((entry) => entry.table == 'todo_lists'), isFalse);
        expect(outbox.any((entry) => entry.table == 'todo_items'), isFalse);
      },
    );

    test(
      'rejects incoming legacy planning operations with upgrade error',
      () async {
        for (final table in ['schedules', 'todo_lists', 'todo_items']) {
          final data = {'id': 'legacy-row'};
          await expectLater(
            storage.batchIncremental(
              [
                (
                  table: table,
                  op: 'upsert',
                  data: data,
                  change: SyncChange(
                    seq: 1,
                    changeId: 'legacy-$table',
                    deviceId: 'old-device',
                    clientCreatedAt: DateTime.utc(2026, 7, 22),
                    table: table,
                    op: 'upsert',
                    recordId: 'legacy-row',
                    data: data,
                  ),
                ),
              ],
              remote: true,
              scope: 'scope',
              nextSince: 1,
            ),
            throwsA(
              isA<StateError>().having(
                (error) => error.message,
                'message',
                allOf(
                  contains('sync schema upgrade required'),
                  contains(table),
                  isNot(contains('unsupported remote sync table')),
                ),
              ),
            ),
          );
          expect(await storage.syncSince('scope'), 0);
        }
      },
    );

    test('round-trips full partitions and incremental rows', () async {
      await storage.writeDataFile('tasks.json', {
        'tasks': [
          {
            'id': 'task-1',
            'title': 'Plan',
            'note': 'note',
            'plannedDate': '2026-08-01',
            'plannedTime': '09:15',
            'dueDate': '2026-08-02',
            'dueTime': '18:00',
            'reminders': [
              {'minutesBefore': 15},
            ],
            'createdAt': '2026-07-22T08:00:00.000',
            'updatedAt': '2026-07-22T08:00:00.000',
          },
        ],
        'lists': [
          {
            'id': 'list-1',
            'title': 'Inbox',
            'sortOrder': 2,
            'createdAt': '2026-07-22T08:00:00.000',
            'updatedAt': '2026-07-22T08:00:00.000',
          },
        ],
        'entries': [
          {
            'id': 'task-1',
            'taskId': 'task-1',
            'listId': 'list-1',
            'sortOrder': 0,
            'updatedAt': '2026-07-22T08:00:00.000',
          },
        ],
      });
      await storage.writeDataFile('calendar.json', {
        'events': [
          {
            'id': 'event-1',
            'title': 'Timed',
            'timeKind': 'timed',
            'startAt': '2026-08-01T10:00:00.000',
            'endAt': '2026-08-01T11:00:00.000',
            'reminders': const [],
            'createdAt': '2026-07-22T08:00:00.000',
            'updatedAt': '2026-07-22T08:00:00.000',
          },
        ],
        'anniversaries': [
          {
            'id': 'anniversary-1',
            'title': 'Launch',
            'month': 8,
            'day': 2,
            'year': 2020,
            'recurrence': 'yearly',
            'showYearCount': true,
            'reminders': const [],
            'createdAt': '2026-07-22T08:00:00.000',
            'updatedAt': '2026-07-22T08:00:00.000',
          },
        ],
      });

      await storage.batchIncremental([
        (
          table: 'tasks',
          op: 'upsert',
          data: {
            'id': 'task-1',
            'title': 'Updated plan',
            'createdAt': '2026-07-22T08:00:00.000',
            'updatedAt': '2026-07-22T09:00:00.000',
          },
          change: null,
        ),
        (
          table: 'anniversaries',
          op: 'delete',
          data: {'id': 'anniversary-1'},
          change: null,
        ),
      ]);

      final tasks = await storage.loadDataFile('tasks.json');
      final calendar = await storage.loadDataFile('calendar.json');
      expect((tasks?['tasks'] as List).single['title'], 'Updated plan');
      expect((tasks?['lists'] as List).single['sortOrder'], 2);
      expect((tasks?['entries'] as List).single['taskId'], 'task-1');
      expect((calendar?['events'] as List).single['timeKind'], 'timed');
      expect(calendar?['anniversaries'], isEmpty);
      expect(await storage.loadDataFile('schedules.json'), isNull);
      expect(await storage.loadDataFile('todo_lists.json'), isNull);
    });
  });
}
