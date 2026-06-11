import 'dart:io';

import 'package:flutter/services.dart';

import '../models/device_control.dart';
import 'device_run_controller.dart';

abstract class DeviceControlBackend {
  Future<Map<String, dynamic>> execute(String name, Map<String, dynamic> args);
}

class DeviceControlService {
  DeviceControlService._();

  static final DeviceControlService instance = DeviceControlService._();

  DeviceControlBackend? _backend;

  DeviceControlBackend get backend {
    return _backend ??= (Platform.isAndroid
        ? AndroidDeviceControlBackend()
        : UnsupportedDeviceControlBackend());
  }

  Future<Map<String, dynamic>> execute(
    String name,
    Map<String, dynamic> args,
  ) async {
    final run = DeviceRunController.instance;
    if (name == 'device.service.status') return run.statusJson();
    if (name == 'device.sleep') return _sleep(args);
    if (name == 'device.node.find') return _findNode(args);
    if (name == 'device.waitForNode') return _waitForNode(args);
    final interrupted = await run.beforeAction(name);
    if (interrupted != null) return interrupted;
    final result = await backend.execute(name, args);
    if (result['ok'] == false) return result;
    return {'ok': true, ...result};
  }

  Future<Map<String, dynamic>> _sleep(Map<String, dynamic> args) async {
    final ms = (_intArg(args['ms']) ?? 0).clamp(0, 600000).toInt();
    final interrupted = await DeviceRunController.instance.delay(
      Duration(milliseconds: ms),
    );
    return interrupted ?? {'ok': true, 'ms': ms};
  }

  Map<String, dynamic> _findNode(Map<String, dynamic> args) {
    final rawSnapshot = args['snapshot'];
    if (rawSnapshot is! Map) {
      return _error('invalid_arguments', 'device.node.find 需要 snapshot');
    }
    final snapshot = DeviceScreenSnapshot.fromJson(
      Map<String, dynamic>.from(rawSnapshot),
    );
    final query = DeviceNodeQuery.fromJson(args);
    for (final node in snapshot.flatten()) {
      if (query.matches(node)) {
        return {'ok': true, 'result': node.toJson()};
      }
    }
    return _error('node_not_found', '未找到匹配节点');
  }

  Future<Map<String, dynamic>> _waitForNode(Map<String, dynamic> args) async {
    final timeoutMs = (_intArg(args['timeoutMs']) ?? 5000)
        .clamp(100, 600000)
        .toInt();
    final intervalMs = (_intArg(args['intervalMs']) ?? 300)
        .clamp(50, 10000)
        .toInt();
    final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));
    while (DateTime.now().isBefore(deadline)) {
      final interrupted = await DeviceRunController.instance.beforeAction(
        'device.waitForNode',
      );
      if (interrupted != null) return interrupted;
      final snapshot = await backend.execute(
        'device.screen.snapshot',
        const {},
      );
      final rawResult = snapshot['result'];
      if (snapshot['ok'] != false && rawResult is Map) {
        final found = _findNode({
          ...args,
          'snapshot': Map<String, dynamic>.from(rawResult),
        });
        if (found['ok'] == true) return found;
      }
      final sleepInterrupted = await DeviceRunController.instance.delay(
        Duration(milliseconds: intervalMs),
      );
      if (sleepInterrupted != null) return sleepInterrupted;
    }
    return _error('node_timeout', '等待节点超时');
  }

  static int? _intArg(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw.trim());
    return null;
  }

  static Map<String, dynamic> _error(String code, String message) => {
    'ok': false,
    'error': {'code': code, 'message': message},
  };
}

class AndroidDeviceControlBackend implements DeviceControlBackend {
  static const _channel = MethodChannel('lynai/device_control');
  static const _events = EventChannel('lynai/device_events');

  AndroidDeviceControlBackend() {
    _events.receiveBroadcastStream().listen(_handleEvent);
  }

  @override
  Future<Map<String, dynamic>> execute(
    String name,
    Map<String, dynamic> args,
  ) async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        _nativeMethod(name),
        args,
      );
      return result ?? {'ok': false, 'error': '平台无返回'};
    } on PlatformException catch (e) {
      return {
        'ok': false,
        'error': {'code': e.code, 'message': e.message ?? e.toString()},
      };
    }
  }

  void _handleEvent(Object? event) {
    if (event is! Map) return;
    final type = event['type']?.toString();
    if (type == 'user_touch') {
      DeviceRunController.instance.pause(reason: 'user_touch');
    }
  }

  String _nativeMethod(String name) {
    return switch (name) {
      'device.screen.snapshot' => 'snapshot',
      'device.screen.context' => 'context',
      'device.screen.screenshot' => 'screenshot',
      'device.tap' => 'tap',
      'device.tapRepeat' => 'tapRepeat',
      'device.swipe' => 'swipe',
      'device.pressBack' => 'pressBack',
      'device.inputText' => 'inputText',
      'device.node.action' => 'nodeAction',
      'device.service.openSettings' => 'openSettings',
      _ => name,
    };
  }
}

class UnsupportedDeviceControlBackend implements DeviceControlBackend {
  @override
  Future<Map<String, dynamic>> execute(
    String name,
    Map<String, dynamic> args,
  ) async {
    return {
      'ok': false,
      'error': {'code': 'unsupported_platform', 'message': '当前平台暂不支持 $name'},
    };
  }
}
