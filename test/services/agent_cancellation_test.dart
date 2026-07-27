import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/services/agent_cancellation.dart';

void main() {
  test(
    'parent cancellation propagates the structured reason to children',
    () async {
      final parent = AgentCancellationSource();
      final child = parent.createChild();
      final grandchild = child.createChild();
      const reason = AgentCancellationReason(
        code: 'user_stop',
        message: 'User stopped the run',
      );

      expect(parent.cancel(reason), isTrue);
      expect(parent.cancel(), isFalse);
      expect(await child.token.whenCancelled, same(reason));
      expect(await grandchild.token.whenCancelled, same(reason));
      expect(grandchild.token.reason, same(reason));
      expect(
        grandchild.token.throwIfCancellationRequested,
        throwsA(
          isA<AgentCancellationException>().having(
            (error) => error.reason,
            'reason',
            same(reason),
          ),
        ),
      );
    },
  );

  test('child cancellation does not cancel its parent', () {
    final parent = AgentCancellationSource();
    final child = parent.createChild();

    child.cancel(
      const AgentCancellationReason(code: 'child_done', message: 'Child done'),
    );

    expect(child.token.isCancellationRequested, isTrue);
    expect(parent.token.isCancellationRequested, isFalse);
  });
}
