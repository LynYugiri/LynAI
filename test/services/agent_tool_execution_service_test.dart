import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/agent_runtime.dart';
import 'package:lynai/services/agent_cancellation.dart';
import 'package:lynai/services/agent_tool_execution_service.dart';
import 'package:lynai/services/agent_tool_registry.dart';
import 'package:lynai/services/agent_tool_scheduler.dart';
import 'package:lynai/services/lynai_permission_definitions.dart';

void main() {
  AgentToolDescriptor descriptor(
    String name, {
    AgentToolConcurrency concurrency = AgentToolConcurrency.parallelSafe,
  }) => AgentToolDescriptor(
    name: name,
    description: 'test',
    source: AgentToolSource.runtime,
    sideEffect: AgentToolSideEffect.read,
    concurrency: concurrency,
    parameters: const {
      'type': 'object',
      'properties': {
        'resource': {'type': 'string'},
      },
      'required': ['resource'],
      'additionalProperties': false,
    },
  );

  AgentToolExecutionRequest request(
    AgentToolSnapshot snapshot,
    List<AgentToolInvocation> calls, {
    AgentPermissionSnapshot? permissions,
    AgentCancellationToken? cancellationToken,
  }) {
    final source = AgentCancellationSource();
    return AgentToolExecutionRequest(
      snapshot: snapshot,
      invocations: calls,
      turnIdentity: const AgentTurnIdentity(
        runId: 'run-1',
        turnId: 'turn-1',
        turnIndex: 2,
      ),
      conversationId: 'conversation-1',
      permissionSnapshot:
          permissions ?? AgentPermissionSnapshot(permissions: const []),
      cancellationToken: cancellationToken ?? source.token,
    );
  }

  test(
    'resolves only the captured snapshot and passes immutable context',
    () async {
      final registry = AgentToolRegistry();
      late AgentToolExecutionContext capturedContext;
      registry.registerSpec(
        AgentToolRegistrationSpec(descriptor: descriptor('lookup')),
        (invocation, context) async {
          capturedContext = context;
          return 'v1';
        },
      );
      final snapshot = registry.snapshot();
      registry.registerSpec(
        AgentToolRegistrationSpec(descriptor: descriptor('lookup')),
        (invocation, context) async => 'v2',
      );
      final permissions = AgentPermissionSnapshot(permissions: const ['read']);
      final results = await AgentToolExecutionService().execute(
        request(snapshot, [
          AgentToolInvocation(
            id: 'call-1',
            name: 'lookup',
            arguments: const {'resource': 'a'},
          ),
        ], permissions: permissions),
      );

      expect(results.single.value, 'v1');
      expect(capturedContext.snapshot, same(snapshot));
      expect(capturedContext.permissionSnapshot, same(permissions));
      expect(capturedContext.identity.runId, 'run-1');
      expect(capturedContext.identity.turnId, 'turn-1');
      expect(capturedContext.identity.turnIndex, 2);
      expect(capturedContext.identity.invocationId, 'call-1');
      expect(capturedContext.identity.conversationId, 'conversation-1');
    },
  );

  test('captured executor is an AgentLoopRuntime-compatible adapter', () async {
    final registry = AgentToolRegistry();
    registry.registerSpec(
      AgentToolRegistrationSpec(descriptor: descriptor('lookup')),
      (invocation, context) async => context.identity.runId,
    );
    final cancellation = AgentCancellationSource();
    final executor = AgentToolExecutionService().capturedExecutor(
      snapshot: registry.snapshot(),
      permissionSnapshot: AgentPermissionSnapshot(permissions: const []),
    );
    final results = await executor(
      [
        AgentToolInvocation(
          id: 'call',
          name: 'lookup',
          arguments: const {'resource': 'a'},
        ),
      ],
      const AgentTurnIdentity(
        runId: 'run-adapter',
        turnId: 'turn-adapter',
        turnIndex: 0,
      ),
      cancellation.token,
    );

    expect(results.single.value, 'run-adapter');
  });

  test(
    'validates then authorizes immediately before handler dispatch',
    () async {
      final registry = AgentToolRegistry();
      var authorizations = 0;
      var executions = 0;
      registry.registerSpec(
        AgentToolRegistrationSpec(
          descriptor: descriptor('protected'),
          permissionRequirements: AgentToolPermissionRequirements(
            permissions: const ['notes:read'],
          ),
        ),
        (invocation, context) async {
          executions++;
          return null;
        },
      );
      final service = AgentToolExecutionService(
        authorizer: (registration, context) {
          authorizations++;
          return registration.spec.permissionRequirements.allows(
            context.permissionSnapshot.permissions,
          );
        },
      );
      final results = await service.execute(
        request(registry.snapshot(), [
          AgentToolInvocation(
            id: 'invalid',
            name: 'protected',
            arguments: const {'resource': 1},
          ),
          AgentToolInvocation(
            id: 'denied',
            name: 'protected',
            arguments: const {'resource': 'a'},
          ),
        ]),
      );

      expect(results.map((result) => result.errorCode), [
        'invalid_arguments',
        'permission_denied',
      ]);
      expect(authorizations, 1);
      expect(executions, 0);
    },
  );

  test(
    'derives keyed concurrency from registration, not invocation field',
    () async {
      final registry = AgentToolRegistry();
      final release = Completer<void>();
      final twoStarted = Completer<void>();
      var active = 0;
      var maxActive = 0;
      registry.registerSpec(
        AgentToolRegistrationSpec(
          descriptor: descriptor(
            'keyed',
            concurrency: AgentToolConcurrency.keyed,
          ),
        ),
        (invocation, context) async {
          active++;
          maxActive = active > maxActive ? active : maxActive;
          if (active == 2) twoStarted.complete();
          await release.future;
          active--;
          return invocation.id;
        },
        concurrencyKeyResolver: (invocation, identity) =>
            invocation.arguments['resource']! as String,
      );
      final future =
          AgentToolExecutionService(
            scheduler: AgentToolScheduler(maxConcurrency: 3),
          ).execute(
            request(registry.snapshot(), [
              AgentToolInvocation(
                id: 'a1',
                name: 'keyed',
                arguments: const {'resource': 'a'},
                concurrencyKey: 'model-1',
              ),
              AgentToolInvocation(
                id: 'a2',
                name: 'keyed',
                arguments: const {'resource': 'a'},
                concurrencyKey: 'model-2',
              ),
              AgentToolInvocation(
                id: 'b1',
                name: 'keyed',
                arguments: const {'resource': 'b'},
                concurrencyKey: 'model-1',
              ),
            ]),
          );

      await twoStarted.future;
      expect(maxActive, 2);
      release.complete();
      final results = await future;
      expect(results.map((result) => result.invocationId), ['a1', 'a2', 'b1']);
    },
  );

  test('deadline and cancellation detach non-cooperative late work', () async {
    final registry = AgentToolRegistry();
    final late = Completer<Object?>();
    registry.registerSpec(
      AgentToolRegistrationSpec(
        descriptor: descriptor('slow'),
        semantics: const AgentToolSemantics(
          timeout: Duration(milliseconds: 20),
        ),
      ),
      (invocation, context) => late.future,
    );
    final deadlineResult = await AgentToolExecutionService()
        .execute(
          request(registry.snapshot(), [
            AgentToolInvocation(
              id: 'deadline',
              name: 'slow',
              arguments: const {'resource': 'a'},
            ),
          ]),
        )
        .timeout(const Duration(seconds: 1));
    expect(deadlineResult.single.errorCode, 'deadline_exceeded');

    final cancellation = AgentCancellationSource();
    final future = AgentToolExecutionService().execute(
      request(registry.snapshot(), [
        AgentToolInvocation(
          id: 'cancelled',
          name: 'slow',
          arguments: const {'resource': 'b'},
        ),
      ], cancellationToken: cancellation.token),
    );
    await Future<void>.delayed(Duration.zero);
    cancellation.cancel();
    final cancelledResult = await future.timeout(const Duration(seconds: 1));
    expect(cancelledResult.single.status, AgentToolResultStatus.cancelled);
    late.complete('too late');
  });

  test('sanitizes errors and applies result policy in input order', () async {
    final registry = AgentToolRegistry();
    registry.registerSpec(
      AgentToolRegistrationSpec(descriptor: descriptor('failure')),
      (invocation, context) async => throw StateError('secret-token'),
    );
    registry.registerSpec(
      AgentToolRegistrationSpec(
        descriptor: descriptor('redacted'),
        semantics: const AgentToolSemantics(
          resultPolicy: AgentToolResultPolicy.redactValue,
        ),
      ),
      (invocation, context) async => const {'secret': 'value'},
    );
    final results =
        await AgentToolExecutionService(
          scheduler: AgentToolScheduler(maxConcurrency: 2),
        ).execute(
          request(registry.snapshot(), [
            AgentToolInvocation(
              id: 'first',
              name: 'failure',
              arguments: const {'resource': 'a'},
            ),
            AgentToolInvocation(
              id: 'second',
              name: 'redacted',
              arguments: const {'resource': 'b'},
            ),
          ]),
        );

    expect(results.map((result) => result.invocationId), ['first', 'second']);
    expect(results.first.errorMessage, 'Tool execution failed');
    expect(results.first.errorMessage, isNot(contains('secret-token')));
    expect(results.last.value, {'redacted': true});
  });
}
