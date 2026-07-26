import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/services/remote_apply_coordinator.dart';

void main() {
  test('serializes local remote commits and recovers after failure', () async {
    final coordinator = RemoteApplyCoordinator();
    final firstStarted = Completer<void>();
    final releaseFirst = Completer<void>();
    final calls = <String>[];

    final first = coordinator.run(() async {
      calls.add('first-start');
      firstStarted.complete();
      await releaseFirst.future;
      calls.add('first-end');
      throw StateError('expected');
    });
    await firstStarted.future;
    final second = coordinator.run(() async {
      calls.add('second');
      return 2;
    });

    await Future<void>.delayed(Duration.zero);
    expect(calls, ['first-start']);
    releaseFirst.complete();
    await expectLater(first, throwsStateError);
    expect(await second, 2);
    expect(calls, ['first-start', 'first-end', 'second']);
  });
}
