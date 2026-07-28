import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/agent_persistence.dart';
import 'package:lynai/models/agent_runtime.dart';
import 'package:lynai/repositories/agent_persistence_repository.dart';
import 'package:lynai/services/storage_v2_service.dart';
import 'package:lynai/services/storage_v2_upgrade_service.dart';
import 'package:lynai/services/lynai_permission_definitions.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  group('Agent persistence repository', () {
    late Directory root;
    late StorageV2Service storage;
    late AgentPersistenceRepository repository;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('lynai_agent_persistence_');
      storage = StorageV2Service(rootDirectory: root);
      await StorageV2UpgradeService(storageV2: storage).ensureReady();
      repository = AgentPersistenceRepository(storage);
    });

    tearDown(() async {
      await storage.close();
      if (await root.exists()) await root.delete(recursive: true);
    });

    test('compare-and-set transitions reject stale writers', () async {
      final createdAt = DateTime.utc(2026, 7, 27, 10);
      await repository.createRun(
        AgentRunRecord(
          id: 'run',
          status: AgentRunStatus.queued,
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
      );

      expect(
        await repository.transitionRun(
          'run',
          from: AgentRunStatus.queued,
          to: AgentRunStatus.running,
          at: createdAt.add(const Duration(seconds: 1)),
        ),
        isTrue,
      );
      expect(
        await repository.transitionRun(
          'run',
          from: AgentRunStatus.queued,
          to: AgentRunStatus.cancelled,
          at: createdAt.add(const Duration(seconds: 2)),
        ),
        isFalse,
      );
      expect(
        () => repository.transitionRun(
          'run',
          from: AgentRunStatus.running,
          to: AgentRunStatus.queued,
          at: createdAt,
        ),
        throwsStateError,
      );
    });

    test(
      'run creation atomically inserts one immutable permission policy',
      () async {
        final createdAt = DateTime.utc(2026, 7, 28, 10);
        final policy = AgentPermissionSnapshot(
          permissions: const [LynAIPermissions.notesRead],
        );
        await repository.createRun(
          AgentRunRecord(
            id: 'run-policy',
            status: AgentRunStatus.queued,
            createdAt: createdAt,
            updatedAt: createdAt,
          ),
          permissionPolicy: policy,
        );

        await storage.close();
        final db = sqlite3.open('${root.path}/storage_v2/app.db');
        try {
          final rows = db.select(
            "SELECT * FROM snapshots WHERE run_id = 'run-policy' "
            "AND kind = 'permission_policy'",
          );
          expect(rows, hasLength(1));
          expect(
            rows.single['data_json'],
            contains(LynAIPermissions.notesRead),
          );
          expect(
            () => db.execute(
              "INSERT INTO snapshots(id, run_id, kind, data_json, created_at) "
              "VALUES ('duplicate', 'run-policy', 'permission_policy', '{}', '')",
            ),
            throwsA(isA<SqliteException>()),
          );
        } finally {
          db.close();
        }
      },
    );

    test('child run retains the parent permission policy', () async {
      final createdAt = DateTime.utc(2026, 7, 28, 11);
      await repository.createRun(
        AgentRunRecord(
          id: 'parent',
          status: AgentRunStatus.queued,
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
        permissionPolicy: AgentPermissionSnapshot(
          permissions: const [LynAIPermissions.todosRead],
        ),
      );
      await repository.createRun(
        AgentRunRecord(
          id: 'child',
          status: AgentRunStatus.queued,
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
        parentRunId: 'parent',
        permissionPolicy: AgentPermissionSnapshot(permissions: const []),
      );

      await storage.close();
      final db = sqlite3.open('${root.path}/storage_v2/app.db');
      try {
        final policies = db.select(
          "SELECT run_id, data_json FROM snapshots "
          "WHERE kind = 'permission_policy' ORDER BY run_id",
        );
        expect(policies, hasLength(2));
        expect(policies[0]['data_json'], policies[1]['data_json']);
      } finally {
        db.close();
      }
    });

    test('restart reconciliation fails active graph without replay', () async {
      final createdAt = DateTime.utc(2026, 7, 27, 11);
      final interruptedAt = createdAt.add(const Duration(minutes: 1));
      await repository.createRun(
        AgentRunRecord(
          id: 'run',
          status: AgentRunStatus.queued,
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
      );
      await repository.createTurn(
        AgentTurnRecord(
          id: 'turn',
          runId: 'run',
          index: 0,
          status: AgentTurnStatus.pending,
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
      );
      await repository.createItem(
        AgentItemRecord(
          id: 'item',
          turnId: 'turn',
          index: 0,
          kind: AgentItemKind.toolCall,
          status: AgentItemStatus.pending,
          payload: const {'name': 'lookup'},
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
      );
      await repository.createToolCall(
        AgentToolCallRecord(
          id: 'call',
          itemId: 'item',
          toolName: 'lookup',
          arguments: const {'query': 'local'},
          status: AgentToolCallStatus.pending,
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
      );
      expect(
        await repository.transitionRun(
          'run',
          from: AgentRunStatus.queued,
          to: AgentRunStatus.running,
          at: createdAt,
        ),
        isTrue,
      );
      expect(
        await repository.transitionTurn(
          'turn',
          from: AgentTurnStatus.pending,
          to: AgentTurnStatus.running,
          at: createdAt,
        ),
        isTrue,
      );
      expect(
        await repository.transitionItem(
          'item',
          from: AgentItemStatus.pending,
          to: AgentItemStatus.running,
          at: createdAt,
        ),
        isTrue,
      );
      expect(
        await repository.transitionToolCall(
          'call',
          from: AgentToolCallStatus.pending,
          to: AgentToolCallStatus.running,
          at: createdAt,
        ),
        isTrue,
      );

      final result = await repository.reconcileAfterRestart(at: interruptedAt);
      expect(result.runIds, ['run']);
      expect(result.turnCount, 1);
      expect(result.itemCount, 1);
      expect(result.toolCallCount, 1);
      expect(
        await repository.reconcileAfterRestart(
          at: interruptedAt.add(const Duration(seconds: 1)),
        ),
        isA<AgentRestartReconciliation>().having(
          (value) => value.changed,
          'changed',
          isFalse,
        ),
      );

      await storage.close();
      final db = sqlite3.open('${root.path}/storage_v2/app.db');
      try {
        for (final table in ['runs', 'turns', 'items', 'tool_calls']) {
          final row = db.select('SELECT * FROM $table').single;
          expect(row['status'], 'failed', reason: table);
          expect(row['error_code'], 'interrupted', reason: table);
          expect(row['completed_at'], interruptedAt.toIso8601String());
        }
        expect(
          db.select("SELECT * FROM snapshots WHERE kind = 'permission_policy'"),
          hasLength(1),
        );
      } finally {
        db.close();
      }
    });

    test(
      'restart reconciliation fails inconsistent active descendants',
      () async {
        final createdAt = DateTime.utc(2026, 7, 27, 11, 30);
        await repository.createRun(
          AgentRunRecord(
            id: 'run',
            status: AgentRunStatus.queued,
            createdAt: createdAt,
            updatedAt: createdAt,
          ),
        );
        await repository.createTurn(
          AgentTurnRecord(
            id: 'turn',
            runId: 'run',
            index: 0,
            status: AgentTurnStatus.pending,
            createdAt: createdAt,
            updatedAt: createdAt,
          ),
        );
        expect(
          await repository.transitionRun(
            'run',
            from: AgentRunStatus.queued,
            to: AgentRunStatus.cancelled,
            at: createdAt,
          ),
          isTrue,
        );

        final result = await repository.reconcileAfterRestart(at: createdAt);
        expect(result.runIds, ['run']);
        expect(result.turnCount, 1);

        await storage.close();
        final db = sqlite3.open('${root.path}/storage_v2/app.db');
        try {
          expect(
            db.select('SELECT status FROM runs').single['status'],
            'cancelled',
          );
          expect(
            db.select('SELECT status FROM turns').single['status'],
            'failed',
          );
        } finally {
          db.close();
        }
      },
    );

    test('MCP persistence accepts public config and rejects secrets', () async {
      final now = DateTime.utc(2026, 7, 27, 12);
      final server = AgentMcpServerRecord(
        id: 'docs',
        name: 'Docs',
        transport: 'http',
        url: 'https://mcp.example.test/rpc',
        environmentNames: const ['MCP_API_KEY'],
        enabled: true,
        createdAt: now,
        updatedAt: now,
      );
      await repository.saveMcpServer(server);
      expect((await repository.loadMcpServers()).single.url, server.url);

      await expectLater(
        repository.saveMcpServer(
          AgentMcpServerRecord(
            id: 'bad-url',
            name: 'Bad',
            transport: 'http',
            url: 'https://user:password@mcp.example.test/rpc',
            enabled: true,
            createdAt: now,
            updatedAt: now,
          ),
        ),
        throwsArgumentError,
      );
      await expectLater(
        repository.saveMcpServer(
          AgentMcpServerRecord(
            id: 'bad-arg',
            name: 'Bad',
            transport: 'stdio',
            command: 'server',
            arguments: const ['--api-key=plaintext'],
            enabled: true,
            createdAt: now,
            updatedAt: now,
          ),
        ),
        throwsArgumentError,
      );
    });
  });
}
