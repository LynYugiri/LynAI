import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/services/device_control_service.dart';
import 'package:lynai/services/device_run_controller.dart';

void main() {
  late _FakeDeviceBackend backend;

  setUp(() {
    backend = _FakeDeviceBackend();
    DeviceControlService.instance.setBackendForTesting(backend);
  });

  tearDown(() {
    DeviceControlService.instance.setBackendForTesting(null);
  });

  test('screen query supports exact, list and action filters', () async {
    backend.snapshot = _snapshot({
      'children': [
        _node('send', text: '发送', clickable: true, actions: ['click']),
        _node('cancel', text: '取消'),
      ],
    });

    final result = await DeviceControlService.instance.execute(
      'device.screen.query',
      {
        'textExact': '发送',
        'textAny': ['忽略', '发送'],
        'action': 'click',
      },
    );

    expect(result['ok'], isTrue);
    final nodes = (result['result'] as Map)['nodes'] as List;
    expect(nodes, hasLength(1));
    expect((nodes.single as Map)['id'], 'send');
  });

  test('clickText clicks targetable ancestor', () async {
    backend.snapshot = _snapshot({
      'clickable': true,
      'children': [_node('label', text: '发送')],
    });

    final result = await DeviceControlService.instance.execute(
      'device.screen.clickText',
      {'text': '发送'},
    );

    expect(result['ok'], isTrue);
    expect(backend.calls.last.name, 'device.node.action');
    expect(backend.calls.last.args['nodeId'], '0');
  });

  test('waitAndClick waits for node then clicks it', () async {
    backend.snapshot = _snapshot({
      'children': [_node('send', text: '发送', clickable: true)],
    });

    final result = await DeviceControlService.instance.execute(
      'device.screen.waitAndClick',
      {'textExact': '发送', 'timeoutMs': 100},
    );

    expect(result['ok'], isTrue);
    expect(backend.calls.last.name, 'device.node.action');
    expect(backend.calls.last.args['nodeId'], 'send');
  });

  test('inputText finds editable node and inputs text', () async {
    backend.snapshot = _snapshot({
      'children': [
        _node('input', editable: true, actions: ['focus', 'setText']),
      ],
    });

    final result = await DeviceControlService.instance.execute(
      'device.screen.inputText',
      {'text': 'hello'},
    );

    expect(result['ok'], isTrue);
    expect(
      backend.calls.map((call) => call.name),
      contains('device.inputText'),
    );
    expect(backend.calls.last.args['nodeId'], 'input');
    expect(backend.calls.last.args['text'], 'hello');
  });

  test('extractMessages returns visible QQ text nodes without OCR', () async {
    backend.snapshot = _snapshot({
      'packageName': 'com.tencent.mobileqq',
      'children': [
        _node('m1', text: '今晚几点？', bounds: _bounds(top: 200)),
        _node('m2', text: '八点', bounds: _bounds(left: 700, top: 260)),
      ],
    }, packageName: 'com.tencent.mobileqq');

    final result = await DeviceControlService.instance.execute(
      'device.screen.extractMessages',
      {'packageName': 'com.tencent.mobileqq'},
    );

    expect(result['ok'], isTrue);
    final messages = (result['result'] as Map)['messages'] as List;
    expect(messages.map((item) => (item as Map)['text']), contains('今晚几点？'));
    expect(messages.map((item) => (item as Map)['text']), contains('八点'));
  });

  test('read helpers respect stopped device run', () async {
    DeviceRunController.instance.start(purpose: 'stop read helpers');
    DeviceRunController.instance.stop();
    try {
      final result = await DeviceControlService.instance.execute(
        'device.screen.extractMessages',
        const {},
      );

      expect(result['ok'], isFalse);
      expect((result['error'] as Map)['code'], 'user_stopped');
      expect(
        backend.calls.where((call) => call.name == 'device.screen.snapshot'),
        isEmpty,
      );
    } finally {
      DeviceRunController.instance.reset();
    }
  });
}

class _FakeDeviceBackend implements DeviceControlBackend {
  Map<String, dynamic> snapshot = _snapshot({});
  final calls = <_BackendCall>[];

  @override
  Future<Map<String, dynamic>> execute(
    String name,
    Map<String, dynamic> args,
  ) async {
    calls.add(_BackendCall(name, args));
    if (name == 'device.screen.snapshot') return snapshot;
    return {'ok': true, 'name': name, 'args': args};
  }
}

class _BackendCall {
  final String name;
  final Map<String, dynamic> args;

  const _BackendCall(this.name, this.args);
}

Map<String, dynamic> _snapshot(
  Map<String, dynamic> root, {
  String packageName = 'com.example',
}) {
  return {
    'ok': true,
    'result': {
      'platform': 'android',
      'packageName': packageName,
      'timestamp': DateTime(2026).toIso8601String(),
      'roots': [
        {
          ..._node('0', packageName: packageName),
          ...root,
          'id': root['id'] ?? '0',
          'packageName': root['packageName'] ?? packageName,
        },
      ],
    },
  };
}

Map<String, dynamic> _node(
  String id, {
  String text = '',
  String packageName = 'com.example',
  bool clickable = false,
  bool editable = false,
  Map<String, dynamic>? bounds,
  List<String> actions = const [],
  List<Map<String, dynamic>> children = const [],
}) {
  return {
    'id': id,
    'text': text,
    'packageName': packageName,
    'bounds': bounds ?? _bounds(),
    'clickable': clickable,
    'editable': editable,
    'enabled': true,
    'visibleToUser': true,
    'actions': actions,
    'children': children,
  };
}

Map<String, dynamic> _bounds({double left = 0, double top = 0}) {
  return {'left': left, 'top': top, 'right': left + 100, 'bottom': top + 40};
}
