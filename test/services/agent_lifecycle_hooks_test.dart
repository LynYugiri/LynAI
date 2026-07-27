import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/agent_runtime.dart';
import 'package:lynai/services/agent_cancellation.dart';
import 'package:lynai/services/agent_lifecycle_hooks.dart';
import 'package:lynai/services/agent_loop_runtime.dart';

void main() {
  test('runs hooks in lifecycle order and isolates failures', () async {
    final order = <String>[];
    var turns = 0;
    final result = await const AgentLoopRuntime()
        .start(
          messages: const [],
          maxToolRounds: 1,
          hooks: AgentLifecycleHooks(
            beforeModelRequest: (_) => order.add('beforeModel'),
            afterModelResponse: (_) {
              order.add('afterModel');
              throw StateError('isolated');
            },
            beforeToolCall: (_) => order.add('beforeTool'),
            afterToolCall: (_) => order.add('afterTool'),
            afterRun: (_) => order.add('afterRun'),
          ),
          model: (request) async* {
            if (turns++ == 0) {
              yield AgentModelToolCalls([
                AgentToolInvocation(id: 'call', name: 'tool'),
              ]);
            } else {
              yield const AgentModelTextDelta('done');
            }
            yield const AgentModelStreamCompleted();
          },
          executeTools: (calls, identity, cancellationToken) async => [
            AgentToolResult.success(invocationId: 'call', toolName: 'tool'),
          ],
        )
        .result;

    expect(result.isSuccess, isTrue);
    expect(order, [
      'beforeModel',
      'afterModel',
      'beforeTool',
      'afterTool',
      'beforeModel',
      'afterModel',
      'afterRun',
    ]);
  });

  test('hook timeout does not delay or fail the run', () async {
    final stopwatch = Stopwatch()..start();
    final result = await const AgentLoopRuntime()
        .start(
          messages: const [],
          maxToolRounds: 0,
          hooks: AgentLifecycleHooks(
            timeout: Duration(milliseconds: 20),
            beforeModelRequest: (_) => Completer<void>().future,
          ),
          model: (request) async* {
            yield const AgentModelTextDelta('done');
            yield const AgentModelStreamCompleted();
          },
          executeTools: (calls, identity, cancellationToken) async => const [],
        )
        .result
        .timeout(const Duration(seconds: 1));
    stopwatch.stop();

    expect(result.isSuccess, isTrue);
    expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 500)));
  });

  test(
    'cancellation aborts an in-flight hook and still calls afterRun',
    () async {
      final entered = Completer<void>();
      final afterRun = Completer<AgentRunStatus>();
      final handle = const AgentLoopRuntime().start(
        messages: const [],
        maxToolRounds: 0,
        hooks: AgentLifecycleHooks(
          timeout: Duration(seconds: 30),
          beforeModelRequest: (_) {
            entered.complete();
            return Completer<void>().future;
          },
          afterRun: (context) => afterRun.complete(context.result.status),
        ),
        model: (request) async* {
          yield const AgentModelStreamCompleted();
        },
        executeTools: (calls, identity, cancellationToken) async => const [],
      );
      await entered.future;
      handle.cancel();

      final result = await handle.result.timeout(const Duration(seconds: 1));
      expect(result.status, AgentRunStatus.cancelled);
      expect(await afterRun.future, AgentRunStatus.cancelled);
    },
  );

  test(
    'hook runner propagates cancellation but isolates hook errors',
    () async {
      final source = AgentCancellationSource();
      final runner = AgentLifecycleHookRunner(
        const AgentLifecycleHooks(timeout: Duration(milliseconds: 20)),
      );
      await runner.invoke<Object>(
        (_) => throw StateError('ignored'),
        Object(),
        source.token,
      );
      source.cancel();
      expect(
        () => runner.invoke<Object>((_) {}, Object(), source.token),
        throwsA(isA<AgentCancellationException>()),
      );
    },
  );
}
