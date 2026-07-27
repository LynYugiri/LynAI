import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/agent_runtime.dart';
import 'package:lynai/services/agent_cancellation.dart';
import 'package:lynai/services/agent_tool_registry.dart';

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
        AgentCancellationSource().token,
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
}
