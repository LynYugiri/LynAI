import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/agent_runtime.dart';
import 'package:lynai/services/agent_cancellation.dart';
import 'package:lynai/services/agent_tool_registry.dart';
import 'package:lynai/services/agent_tool_scheduler.dart';

void main() {
  AgentToolDescriptor descriptor(
    String name,
    AgentToolConcurrency concurrency,
  ) => AgentToolDescriptor(
    name: name,
    description: 'test tool',
    source: AgentToolSource.runtime,
    sideEffect: AgentToolSideEffect.none,
    concurrency: concurrency,
    parameters: const {
      'type': 'object',
      'properties': {
        'value': {'type': 'integer'},
      },
      'required': ['value'],
      'additionalProperties': false,
    },
  );

  AgentToolInvocation call(String id, String name, int value, {String? key}) =>
      AgentToolInvocation(
        id: id,
        name: name,
        arguments: {'value': value},
        concurrencyKey: key,
      );

  test('parallel-safe tools overlap up to bounded concurrency', () async {
    final registry = AgentToolRegistry();
    final release = Completer<void>();
    final twoStarted = Completer<void>();
    var active = 0;
    var maxActive = 0;
    registry.register(
      descriptor('parallel', AgentToolConcurrency.parallelSafe),
      (invocation, token) async {
        active++;
        maxActive = active > maxActive ? active : maxActive;
        if (active == 2 && !twoStarted.isCompleted) twoStarted.complete();
        await release.future;
        active--;
        return invocation.arguments['value'];
      },
    );
    final future = AgentToolScheduler(maxConcurrency: 2).execute(
      registry.snapshot(),
      [
        call('one', 'parallel', 1),
        call('two', 'parallel', 2),
        call('three', 'parallel', 3),
      ],
    );

    await twoStarted.future;
    expect(active, 2);
    release.complete();
    final results = await future;

    expect(maxActive, 2);
    expect(results.map((result) => result.value), [1, 2, 3]);
  });

  test(
    'exclusive tool waits for prior work and blocks following work',
    () async {
      final registry = AgentToolRegistry();
      final firstRelease = Completer<void>();
      final exclusiveRelease = Completer<void>();
      final firstStarted = Completer<void>();
      final exclusiveStarted = Completer<void>();
      final thirdStarted = Completer<void>();
      var active = 0;
      registry.register(
        descriptor('parallel', AgentToolConcurrency.parallelSafe),
        (invocation, token) async {
          active++;
          if (invocation.id == 'first') {
            firstStarted.complete();
            await firstRelease.future;
          } else {
            thirdStarted.complete();
          }
          active--;
          return invocation.id;
        },
      );
      registry.register(
        descriptor('exclusive', AgentToolConcurrency.exclusive),
        (invocation, token) async {
          expect(active, 0);
          active++;
          exclusiveStarted.complete();
          await exclusiveRelease.future;
          active--;
          return invocation.id;
        },
      );
      final future = AgentToolScheduler(maxConcurrency: 3)
          .execute(registry.snapshot(), [
            call('first', 'parallel', 1),
            call('middle', 'exclusive', 2),
            call('third', 'parallel', 3),
          ]);

      await firstStarted.future;
      expect(exclusiveStarted.isCompleted, isFalse);
      expect(thirdStarted.isCompleted, isFalse);
      firstRelease.complete();
      await exclusiveStarted.future;
      expect(thirdStarted.isCompleted, isFalse);
      exclusiveRelease.complete();
      await thirdStarted.future;
      final results = await future;

      expect(results.map((result) => result.invocationId), [
        'first',
        'middle',
        'third',
      ]);
    },
  );

  test(
    'keyed tools serialize the same key while different keys overlap',
    () async {
      final registry = AgentToolRegistry();
      final releaseA1 = Completer<void>();
      final a1Started = Completer<void>();
      final a2Started = Completer<void>();
      final b1Started = Completer<void>();
      final activeKeys = <String>{};
      registry.register(descriptor('keyed', AgentToolConcurrency.keyed), (
        invocation,
        token,
      ) async {
        final key = invocation.concurrencyKey!;
        expect(activeKeys.add(key), isTrue);
        if (invocation.id == 'a1') {
          a1Started.complete();
          await releaseA1.future;
        } else if (invocation.id == 'a2') {
          a2Started.complete();
        } else {
          b1Started.complete();
        }
        activeKeys.remove(key);
        return invocation.id;
      });
      final future = AgentToolScheduler(maxConcurrency: 3)
          .execute(registry.snapshot(), [
            call('a1', 'keyed', 1, key: 'a'),
            call('a2', 'keyed', 2, key: 'a'),
            call('b1', 'keyed', 3, key: 'b'),
          ]);

      await Future.wait([a1Started.future, b1Started.future]);
      expect(a2Started.isCompleted, isFalse);
      releaseA1.complete();
      await a2Started.future;
      final results = await future;

      expect(results.map((result) => result.invocationId), ['a1', 'a2', 'b1']);
    },
  );

  test('returns results in invocation order, not completion order', () async {
    final registry = AgentToolRegistry();
    final releases = List.generate(3, (_) => Completer<void>());
    registry.register(
      descriptor('parallel', AgentToolConcurrency.parallelSafe),
      (invocation, token) async {
        final value = invocation.arguments['value'] as int;
        await releases[value - 1].future;
        return value;
      },
    );
    final future = AgentToolScheduler(maxConcurrency: 3).execute(
      registry.snapshot(),
      [
        call('one', 'parallel', 1),
        call('two', 'parallel', 2),
        call('three', 'parallel', 3),
      ],
    );

    await Future<void>.delayed(Duration.zero);
    releases[2].complete();
    releases[1].complete();
    releases[0].complete();
    final results = await future;

    expect(results.map((result) => result.invocationId), [
      'one',
      'two',
      'three',
    ]);
    expect(results.map((result) => result.value), [1, 2, 3]);
  });

  test(
    'validates arguments and observes cancellation before dispatch',
    () async {
      final registry = AgentToolRegistry();
      var executions = 0;
      registry.register(
        descriptor('parallel', AgentToolConcurrency.parallelSafe),
        (invocation, token) async {
          executions++;
          return null;
        },
      );
      final cancellation = AgentCancellationSource()..cancel();
      final results = await AgentToolScheduler().execute(registry.snapshot(), [
        AgentToolInvocation(
          id: 'invalid',
          name: 'parallel',
          arguments: const {'value': 'wrong'},
        ),
        call('cancelled', 'parallel', 2),
      ], cancellationToken: cancellation.token);

      expect(executions, 0);
      expect(results[0].errorCode, 'cancelled');
      expect(results[1].errorCode, 'cancelled');
    },
  );
}
