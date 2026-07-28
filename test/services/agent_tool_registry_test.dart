import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/agent_runtime.dart';
import 'package:lynai/services/agent_cancellation.dart';
import 'package:lynai/services/agent_tool_registry.dart';
import 'package:lynai/services/lynai_permission_definitions.dart';

void main() {
  AgentToolDescriptor descriptor(String name) => AgentToolDescriptor(
    name: name,
    description: 'test',
    source: AgentToolSource.runtime,
    sideEffect: AgentToolSideEffect.none,
    concurrency: AgentToolConcurrency.parallelSafe,
  );

  test('snapshot is immutable and detects replaced registrations', () async {
    final registry = AgentToolRegistry();
    registry.register(descriptor('echo'), (invocation, token) async => 'v1');
    final snapshot = registry.snapshot();
    final captured = snapshot['echo']!;

    registry.register(descriptor('echo'), (invocation, token) async => 'v2');

    expect(snapshot.isStaleAgainst(registry), isTrue);
    expect(snapshot.isRegistrationCurrent(registry, 'echo'), isFalse);
    expect(snapshot['echo'], same(captured));
    expect(captured.version, 1);
    expect(registry.registration('echo')!.version, 2);
    expect(
      captured.registrationId,
      isNot(registry.registration('echo')!.registrationId),
    );
    expect(
      await captured.handler(
        AgentToolInvocation(id: 'call', name: 'echo'),
        AgentToolExecutionContext(
          identity: const AgentToolExecutionIdentity(
            runId: 'run',
            turnId: 'turn',
            turnIndex: 0,
            invocationId: 'call',
            toolName: 'echo',
          ),
          permissionSnapshot: AgentPermissionSnapshot(permissions: const []),
          cancellationToken: AgentCancellationSource().token,
          snapshot: snapshot,
          deadline: DateTime.now().add(const Duration(seconds: 1)),
        ),
      ),
      'v1',
    );
  });

  test(
    'unrelated registry changes stale the snapshot without replacing entries',
    () {
      final registry = AgentToolRegistry();
      registry.register(descriptor('first'), (invocation, token) async => null);
      final snapshot = registry.snapshot();

      registry.register(
        descriptor('second'),
        (invocation, token) async => null,
      );

      expect(snapshot.isStaleAgainst(registry), isTrue);
      expect(snapshot.isRegistrationCurrent(registry, 'first'), isTrue);
      expect(snapshot['second'], isNull);
    },
  );

  test('registration rejects malformed or unsupported parameter schemas', () {
    final registry = AgentToolRegistry();
    expect(
      () => registry.register(
        AgentToolDescriptor(
          name: 'bad',
          description: 'bad',
          source: AgentToolSource.runtime,
          sideEffect: AgentToolSideEffect.none,
          concurrency: AgentToolConcurrency.parallelSafe,
          parameters: const {'type': 'object', 'definitions': {}},
        ),
        (invocation, token) async => null,
      ),
      throwsArgumentError,
    );
  });

  test('complete registration spec is captured immutably', () {
    final registry = AgentToolRegistry();
    final permissions = <String>['notes:read'];
    final registration = registry.registerSpec(
      AgentToolRegistrationSpec(
        descriptor: descriptor('read_notes'),
        permissionRequirements: AgentToolPermissionRequirements(
          permissions: permissions,
        ),
        semantics: const AgentToolSemantics(
          operation: AgentToolOperation.read,
          risk: AgentToolRisk.elevated,
          resultPolicy: AgentToolResultPolicy.redactValue,
          timeout: Duration(seconds: 2),
        ),
      ),
      (invocation, context) async => null,
    );
    permissions.add('notes:write');

    expect(registration.spec.permissionRequirements.permissions, [
      'notes:read',
    ]);
    expect(registration.spec.semantics.operation, AgentToolOperation.read);
    expect(registration.spec.semantics.risk, AgentToolRisk.elevated);
    expect(
      registration.spec.semantics.resultPolicy,
      AgentToolResultPolicy.redactValue,
    );
    expect(registration.spec.semantics.timeout, const Duration(seconds: 2));
  });

  test('keyed spec requires a host-side key resolver', () {
    final registry = AgentToolRegistry();
    expect(
      () => registry.registerSpec(
        AgentToolRegistrationSpec(
          descriptor: AgentToolDescriptor(
            name: 'keyed',
            description: 'test',
            source: AgentToolSource.runtime,
            sideEffect: AgentToolSideEffect.write,
            concurrency: AgentToolConcurrency.keyed,
          ),
        ),
        (invocation, context) async => null,
      ),
      throwsArgumentError,
    );
  });
}
