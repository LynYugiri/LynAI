import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/device_control.dart';
import 'package:lynai/services/device_run_controller.dart';

void main() {
  test('DeviceScreenSnapshot flattens and matches nodes', () {
    final snapshot = DeviceScreenSnapshot.fromJson({
      'platform': 'android',
      'packageName': 'example.app',
      'timestamp': DateTime.now().toIso8601String(),
      'roots': [
        {
          'id': '0',
          'text': 'Root',
          'bounds': {'left': 0, 'top': 0, 'right': 100, 'bottom': 100},
          'children': [
            {
              'id': '0.0',
              'text': '确认支付',
              'className': 'android.widget.Button',
              'clickable': true,
              'bounds': {'left': 1, 'top': 2, 'right': 3, 'bottom': 4},
            },
          ],
        },
      ],
    });

    final query = DeviceNodeQuery(text: '确认', clickable: true);
    final match = snapshot.flatten().firstWhere(query.matches);

    expect(match.id, '0.0');
    expect(match.bounds.bottom, 4);
  });

  test('DeviceRunController pauses and resumes action checkpoints', () async {
    final controller = DeviceRunController.instance;
    controller.reset();
    controller.start(purpose: '测试设备任务');
    controller.pause();

    var resumed = false;
    final waiter = controller.beforeAction('device.tap').then((error) {
      resumed = true;
      expect(error, isNull);
    });

    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(resumed, isFalse);
    controller.resume();
    await waiter;
    expect(controller.snapshot.status, DeviceRunStatus.running);
    controller.complete();
  });

  test(
    'DeviceRunController stops delayed actions and reports status flags',
    () async {
      final controller = DeviceRunController.instance;
      controller.reset();
      controller.start(purpose: '停止测试');
      final waiting = controller.delay(const Duration(seconds: 1));

      await Future<void>.delayed(const Duration(milliseconds: 10));
      controller.stop();
      final interrupted = await waiting;

      expect(interrupted?['ok'], isFalse);
      expect((interrupted?['error'] as Map)['code'], 'user_stopped');
      final status = controller.statusJson();
      expect(status['status'], DeviceRunStatus.stopping.name);
      expect(status['canStop'], isFalse);
      expect(status['actionCount'], greaterThanOrEqualTo(1));
      controller.reset();
    },
  );

  test('DeviceRunController delay does not elapse while paused', () async {
    final controller = DeviceRunController.instance;
    controller.reset();
    controller.start(purpose: '暂停计时测试');
    controller.pause();

    var completed = false;
    final waiting = controller.delay(const Duration(milliseconds: 30)).then((
      _,
    ) {
      completed = true;
    });

    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(completed, isFalse);
    controller.resume();
    await waiting;
    expect(completed, isTrue);
    controller.complete();
  });
}
