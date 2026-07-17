import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/utils/flush_tasks.dart';

void main() {
  test(
    'attempts every flush and does not continue to upload after failures',
    () async {
      final attempted = <String>[];
      var uploaded = false;

      Future<void> flushThenUpload() async {
        await flushAllTasks([
          (
            name: 'conversations',
            flush: () async {
              attempted.add('conversations');
              throw StateError('conversation save failed');
            },
          ),
          (
            name: 'features',
            flush: () async {
              attempted.add('features');
            },
          ),
          (
            name: 'settings',
            flush: () async {
              attempted.add('settings');
              throw StateError('settings save failed');
            },
          ),
        ]);
        uploaded = true;
      }

      await expectLater(
        flushThenUpload(),
        throwsA(
          isA<FlushTasksException>().having(
            (error) => error.failures.map((failure) => failure.name),
            'failed task names',
            ['conversations', 'settings'],
          ),
        ),
      );
      expect(attempted, ['conversations', 'features', 'settings']);
      expect(uploaded, isFalse);
    },
  );
}
