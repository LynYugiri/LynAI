import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/agent_runtime.dart';
import 'package:lynai/repositories/agent_persistence_repository.dart';
import 'package:lynai/services/agent_loop_runtime.dart';
import 'package:lynai/services/agent_persistence_lifecycle.dart';
import 'package:lynai/services/storage_v2_service.dart';
import 'package:lynai/services/storage_v2_upgrade_service.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  group('Agent runtime durable graph', () {
    late Directory root;
    late StorageV2Service storage;
    late AgentPersistenceRepository repository;
    late RepositoryAgentRunPersistenceLifecycle persistence;

    setUp(() async {
      root = await Directory.systemTemp.createTemp(
        'lynai_agent_runtime_graph_',
      );
      storage = StorageV2Service(rootDirectory: root);
      await StorageV2UpgradeService(storageV2: storage).ensureReady();
      repository = AgentPersistenceRepository(storage);
      persistence = RepositoryAgentRunPersistenceLifecycle(repository);
    });

    tearDown(() async {
      await storage.close();
      if (await root.exists()) await root.delete(recursive: true);
    });

    test('records a completed text run and assistant item', () async {
      final result = await const AgentLoopRuntime()
          .start(
            runId: 'text-run',
            persistence: persistence,
            persistenceMetadata: const AgentRunPersistenceMetadata(
              conversationId: 'conversation',
              parentRunId: 'parent-run',
              parentTurnId: 'parent-turn',
              parentToolCallId: 'parent-call',
            ),
            messages: const [
              {'role': 'user', 'content': 'hello'},
            ],
            maxToolRounds: 0,
            model: (request) async* {
              yield const AgentModelTextDelta('answer');
              yield const AgentModelStreamCompleted();
            },
            executeTools: (calls, identity, cancellation) async => const [],
          )
          .result;

      expect(result.status, AgentRunStatus.completed);
      final db = await _openRaw(storage, root);
      try {
        final run = db.select('SELECT * FROM runs').single;
        expect(run['id'], 'text-run');
        expect(run['conversation_id'], 'conversation');
        expect(run['status'], 'completed');
        expect(
          db.select('SELECT status FROM turns').single['status'],
          'completed',
        );
        final item = db.select('SELECT * FROM items').single;
        expect(item['kind'], 'message');
        expect(item['status'], 'completed');
        expect(jsonDecode(item['payload_json'] as String), {
          'role': 'assistant',
          'content': 'answer',
        });
        final snapshot = db.select('SELECT * FROM snapshots').single;
        expect(snapshot['kind'], 'parent_run');
        expect(jsonDecode(snapshot['data_json'] as String), {
          'runId': 'parent-run',
          'turnId': 'parent-turn',
          'toolCallId': 'parent-call',
        });
      } finally {
        db.close();
      }
    });

    test('records tool calls before execution and terminal results', () async {
      var executions = 0;
      final result = await const AgentLoopRuntime()
          .start(
            runId: 'tool-run',
            persistence: persistence,
            messages: const [],
            maxToolRounds: 2,
            model: (request) async* {
              if (request.identity.turnIndex == 0) {
                yield AgentModelToolCalls([
                  AgentToolInvocation(
                    id: 'model-call',
                    name: 'lookup',
                    arguments: const {'query': 'hello'},
                  ),
                ]);
              } else {
                yield const AgentModelTextDelta('done');
              }
              yield const AgentModelStreamCompleted();
            },
            executeTools: (calls, identity, cancellation) async {
              executions++;
              final db = sqlite3.open('${root.path}/storage_v2/app.db');
              try {
                final row = db.select('SELECT * FROM tool_calls').single;
                expect(row['status'], 'running');
                expect(row['tool_name'], 'lookup');
              } finally {
                db.close();
              }
              return [
                AgentToolResult.success(
                  invocationId: calls.single.id,
                  toolName: calls.single.name,
                  value: const {'found': true},
                ),
              ];
            },
          )
          .result;

      expect(result.status, AgentRunStatus.completed);
      expect(executions, 1);
      final db = await _openRaw(storage, root);
      try {
        expect(
          db.select('SELECT status FROM runs').single['status'],
          'completed',
        );
        expect(db.select('SELECT * FROM turns'), hasLength(2));
        final call = db.select('SELECT * FROM tool_calls').single;
        expect(call['status'], 'completed');
        expect(jsonDecode(call['result_json'] as String), {
          'invocationId': 'model-call',
          'toolName': 'lookup',
          'status': 'success',
          'value': {'found': true},
        });
        expect(
          db
              .select('SELECT kind FROM items ORDER BY item_index')
              .map((row) => row['kind']),
          containsAll(['toolCall', 'toolResult', 'message']),
        );
      } finally {
        db.close();
      }
    });

    test('cancellation terminalizes the active durable graph once', () async {
      final model = StreamController<AgentModelStreamEvent>();
      final modelStarted = Completer<void>();
      final handle = const AgentLoopRuntime().start(
        runId: 'cancelled-run',
        persistence: persistence,
        messages: const [],
        maxToolRounds: 1,
        model: (request) {
          if (!modelStarted.isCompleted) modelStarted.complete();
          return model.stream;
        },
        executeTools: (calls, identity, cancellation) async => const [],
      );
      await modelStarted.future;
      handle.cancel();
      final result = await handle.result;
      await model.close();

      expect(result.status, AgentRunStatus.cancelled);
      final reconciled = await repository.reconcileAfterRestart();
      expect(reconciled.changed, isFalse);
      final db = await _openRaw(storage, root);
      try {
        expect(
          db.select('SELECT status FROM runs').single['status'],
          'cancelled',
        );
        expect(
          db.select('SELECT status FROM turns').single['status'],
          'cancelled',
        );
      } finally {
        db.close();
      }
    });

    test(
      'restart reconciliation interrupts but does not replay an active graph',
      () async {
        await persistence.startRun(
          'interrupted-run',
          const AgentRunPersistenceMetadata(),
        );
        await persistence.startTurn(
          const AgentTurnIdentity(
            runId: 'interrupted-run',
            turnId: 'interrupted-turn',
            turnIndex: 0,
          ),
        );

        final reconciled = await repository.reconcileAfterRestart();
        expect(reconciled.runIds, ['interrupted-run']);
        final db = await _openRaw(storage, root);
        try {
          expect(
            db.select('SELECT status FROM runs').single['status'],
            'failed',
          );
          final turn = db.select('SELECT * FROM turns').single;
          expect(turn['status'], 'failed');
          expect(turn['error_code'], 'interrupted');
        } finally {
          db.close();
        }
      },
    );
  });
}

Future<Database> _openRaw(StorageV2Service storage, Directory root) async {
  await storage.close();
  return sqlite3.open('${root.path}/storage_v2/app.db');
}
