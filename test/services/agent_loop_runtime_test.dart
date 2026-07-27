import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/agent_runtime.dart';
import 'package:lynai/services/agent_loop_runtime.dart';
import 'package:lynai/services/agent_context_builder.dart';
import 'package:lynai/services/agent_persistence_lifecycle.dart';

void main() {
  test('runs model tool continuation with correlated identities', () async {
    final requests = <AgentModelTurnRequest>[];
    AgentTurnIdentity? toolIdentity;
    final events = <AgentRunEvent>[];
    final handle = const AgentLoopRuntime().start(
      runId: 'run-1',
      messages: const [
        {'role': 'user', 'content': 'hello'},
      ],
      maxToolRounds: 3,
      model: (request) async* {
        requests.add(request);
        if (requests.length == 1) {
          yield const AgentModelTextDelta('checking');
          yield AgentModelToolCalls([
            AgentToolInvocation(
              id: 'call-1',
              name: 'lookup',
              arguments: const {'query': 'hello'},
            ),
          ]);
        } else {
          yield const AgentModelReasoningDelta('used tool');
          yield const AgentModelTextDelta('final answer');
        }
        yield const AgentModelStreamCompleted();
      },
      executeTools: (calls, identity, cancellationToken) async {
        toolIdentity = identity;
        expect(cancellationToken.isCancellationRequested, isFalse);
        return [
          AgentToolResult.success(
            invocationId: calls.single.id,
            toolName: calls.single.name,
            value: const {'ok': true, 'result': 'found'},
          ),
        ];
      },
    );
    final subscription = handle.events.listen(events.add);

    final result = await handle.result;
    await subscription.cancel();

    expect(result.status, AgentRunStatus.completed);
    expect(result.content, 'final answer');
    expect(result.reasoning, 'used tool');
    expect(result.toolRounds, 1);
    expect(requests, hasLength(2));
    expect(toolIdentity?.runId, 'run-1');
    expect(toolIdentity?.turnId, requests.first.identity.turnId);
    expect(requests[1].identity.turnId, isNot(requests[0].identity.turnId));
    expect(requests[1].messages, hasLength(3));
    expect(requests[1].messages[1]['role'], 'assistant');
    expect(requests[1].messages[2]['role'], 'tool');
    expect(jsonDecode(requests[1].messages[2]['content'] as String), {
      'ok': true,
      'result': 'found',
    });
    expect(
      events.map((event) => event.kind),
      containsAllInOrder([
        AgentRunEventKind.runStarted,
        AgentRunEventKind.turnStarted,
        AgentRunEventKind.textDelta,
        AgentRunEventKind.toolCalls,
        AgentRunEventKind.toolStarted,
        AgentRunEventKind.turnStarted,
        AgentRunEventKind.reasoningDelta,
        AgentRunEventKind.textDelta,
        AgentRunEventKind.runCompleted,
      ]),
    );
  });

  test('forces a final model turn after the tool round limit', () async {
    final requests = <AgentModelTurnRequest>[];
    var executions = 0;
    final result = await const AgentLoopRuntime()
        .start(
          messages: const [],
          maxToolRounds: 1,
          model: (request) async* {
            requests.add(request);
            if (!request.forceFinalResponse) {
              yield AgentModelToolCalls([
                AgentToolInvocation(id: 'call', name: 'tool'),
              ]);
            } else {
              yield const AgentModelTextDelta('limited final');
            }
            yield const AgentModelStreamCompleted();
          },
          executeTools: (calls, identity, cancellationToken) async {
            executions++;
            return [
              AgentToolResult.success(
                invocationId: calls.single.id,
                toolName: calls.single.name,
              ),
            ];
          },
        )
        .result;

    expect(result.content, 'limited final');
    expect(result.toolRounds, 1);
    expect(executions, 1);
    expect(requests.map((request) => request.forceFinalResponse), [
      false,
      true,
    ]);
    expect(requests.last.messages.last['role'], 'system');
  });

  test('reports tool calls returned by the forced final turn', () async {
    final result = await const AgentLoopRuntime()
        .start(
          messages: const [],
          maxToolRounds: 0,
          model: (request) async* {
            yield AgentModelToolCalls([
              AgentToolInvocation(id: 'late-call', name: 'tool'),
            ]);
            yield const AgentModelStreamCompleted();
          },
          executeTools: (calls, identity, cancellationToken) async => const [],
        )
        .result;

    expect(result.status, AgentRunStatus.completed);
    expect(result.toolRoundLimitReached, isTrue);
  });

  test(
    'cancellation completes without waiting for a late tool result',
    () async {
      final toolCompleter = Completer<List<AgentToolResult>>();
      var modelTurns = 0;
      final handle = const AgentLoopRuntime().start(
        messages: const [],
        maxToolRounds: 3,
        model: (request) async* {
          modelTurns++;
          yield AgentModelToolCalls([
            AgentToolInvocation(id: 'slow', name: 'slow_tool'),
          ]);
          yield const AgentModelStreamCompleted();
        },
        executeTools: (calls, identity, cancellationToken) =>
            toolCompleter.future,
      );
      await handle.events.firstWhere(
        (event) => event.kind == AgentRunEventKind.toolStarted,
      );

      handle.cancel();
      final result = await handle.result.timeout(const Duration(seconds: 1));
      toolCompleter.complete([
        AgentToolResult.success(invocationId: 'slow', toolName: 'slow_tool'),
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(result.status, AgentRunStatus.cancelled);
      expect(modelTurns, 1);
    },
  );

  test('model failure becomes a failed result', () async {
    final result = await const AgentLoopRuntime()
        .start(
          messages: const [],
          maxToolRounds: 1,
          model: (request) async* {
            yield AgentModelStreamFailure(
              StateError('broken'),
              StackTrace.current,
            );
          },
          executeTools: (calls, identity, cancellationToken) async => const [],
        )
        .result;

    expect(result.status, AgentRunStatus.failed);
    expect(result.error, isA<StateError>());
  });

  test('tool persistence failure prevents side effects', () async {
    var executions = 0;
    final result = await const AgentLoopRuntime()
        .start(
          persistence: _FailingToolPersistence(),
          messages: const [],
          maxToolRounds: 1,
          model: (request) async* {
            yield AgentModelToolCalls([
              AgentToolInvocation(id: 'call', name: 'write_tool'),
            ]);
            yield const AgentModelStreamCompleted();
          },
          executeTools: (calls, identity, cancellationToken) async {
            executions++;
            return const [];
          },
        )
        .result;

    expect(result.status, AgentRunStatus.failed);
    expect(result.error, isA<StateError>());
    expect(executions, 0);
  });

  test('retries context overflow once and then opens the circuit', () async {
    var attempts = 0;
    var compactions = 0;
    final result =
        await AgentLoopRuntime(
              contextBuilder: const AgentContextBuilder(
                budget: AgentContextBudget(
                  modelTokenBudget: 100,
                  reservedOutputTokens: 20,
                  charactersPerToken: 2,
                ),
              ),
            )
            .start(
              messages: List.generate(
                8,
                (index) => {
                  'role': 'user',
                  'content': 'old context $index ${'x' * 30}',
                },
              ),
              maxToolRounds: 0,
              compactContext: (request) async {
                compactions++;
                return const AgentCompactionCheckpoint(summary: 'summary');
              },
              isContextOverflow: (error) => error is _ContextOverflow,
              model: (request) async* {
                attempts++;
                yield AgentModelStreamFailure(
                  _ContextOverflow(),
                  StackTrace.current,
                );
              },
              executeTools: (calls, identity, cancellationToken) async =>
                  const [],
            )
            .result;

    expect(result.status, AgentRunStatus.failed);
    expect(result.error, isA<_ContextOverflow>());
    expect(attempts, 2);
    expect(compactions, greaterThanOrEqualTo(1));
  });
}

class _ContextOverflow implements Exception {}

class _FailingToolPersistence implements AgentRunPersistenceLifecycle {
  @override
  Future<void> startRun(
    String runId,
    AgentRunPersistenceMetadata metadata,
  ) async {}

  @override
  Future<void> startTurn(AgentTurnIdentity identity) async {}

  @override
  Future<void> recordAssistantResponse(
    AgentTurnIdentity identity, {
    required String content,
    required String reasoning,
    required List<AgentToolInvocation> toolCalls,
  }) async {
    throw StateError('tool call insert failed');
  }

  @override
  Future<void> startToolCalls(
    AgentTurnIdentity identity,
    List<AgentToolInvocation> toolCalls,
  ) async {}

  @override
  Future<void> completeToolCall(
    AgentTurnIdentity identity,
    AgentToolResult result,
  ) async {}

  @override
  Future<void> completeTurn(AgentTurnIdentity identity) async {}

  @override
  Future<void> completeRun(String runId, AgentRunResult result) async {}
}
