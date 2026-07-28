import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/agent_runtime.dart';
import 'package:lynai/services/agent_loop_runtime.dart';
import 'package:lynai/services/dataset_runtime_barrier.dart';

void main() {
  test('quiesce cancels Agent work and blocks the next generation', () async {
    final barrier = DatasetRuntimeBarrier();
    final modelStarted = Completer<void>();
    final run = const AgentLoopRuntime().start(
      messages: const [
        {'role': 'user', 'content': 'wait'},
      ],
      maxToolRounds: 1,
      datasetBarrier: barrier,
      model: (_) async* {
        modelStarted.complete();
        await Completer<void>().future;
      },
      executeTools: (_, _, _) async => const <AgentToolResult>[],
    );
    await modelStarted.future;

    final quiesce = barrier.quiesce();
    final nextStarted = Completer<void>();
    final next = barrier.run((_) async => nextStarted.complete());
    await quiesce;

    expect((await run.result).isCancelled, isTrue);
    expect(nextStarted.isCompleted, isFalse);
    barrier.reopen();
    await next;
    expect(nextStarted.isCompleted, isTrue);
  });
}
