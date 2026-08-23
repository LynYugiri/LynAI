import 'dart:async';

import 'package:lynai/services/on_device_llm_service.dart';

class FakeOnDeviceLlmMethodCall {
  const FakeOnDeviceLlmMethodCall(this.method, [this.arguments = const {}]);

  final String method;
  final Map<String, dynamic> arguments;
}

class FakeOnDeviceLlmBackend implements OnDeviceLlmBackend {
  FakeOnDeviceLlmBackend({Map<String, dynamic>? status})
    : status = status ?? validatedStatus;

  Map<String, dynamic> status;
  final List<FakeOnDeviceLlmMethodCall> calls = [];
  final StreamController<Map<String, dynamic>> eventController =
      StreamController<Map<String, dynamic>>.broadcast(sync: true);

  static final Map<String, dynamic> readyStatus = {
    'ok': true,
    'state': 'ready',
    'busy': false,
    'supportedAbi': true,
    'apiLevel': 31,
    'storagePermission': true,
    'modelPath': '/sdcard/1225',
    'resolvedConfigPath': '/sdcard/1225/bluelm_mtk_llm_config.json',
    'modelVersion': 'BlueLM-3.0-3B',
    'missingFiles': <String>[],
    'lastErrorCode': null,
    'lastError': null,
  };

  static final Map<String, dynamic> validatedStatus = {
    ...readyStatus,
    'state': 'validated',
  };

  static Map<String, dynamic> statusWith(String state, {String? error}) {
    return {...readyStatus, 'state': state, 'lastError': error};
  }

  @override
  Future<Map<String, dynamic>> invoke(
    String method, [
    Map<String, dynamic> arguments = const {},
  ]) async {
    calls.add(FakeOnDeviceLlmMethodCall(method, arguments));
    switch (method) {
      case 'getStatus':
      case 'refreshStatus':
      case 'setModelPath':
        return status;
      case 'init':
        status = {...readyStatus};
        return status;
      case 'generate':
        return {'ok': true, 'started': true};
      case 'interrupt':
      case 'release':
        return {'ok': true};
      case 'requestStoragePermission':
        return {'ok': true, 'granted': status['storagePermission'] == true};
    }
    return {'ok': true};
  }

  void emit(Map<String, dynamic> event) {
    eventController.add(event);
  }

  @override
  Stream<Map<String, dynamic>> get events => eventController.stream;

  @override
  void dispose() {
    eventController.close();
  }
}
