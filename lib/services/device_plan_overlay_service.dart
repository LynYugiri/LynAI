import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

import 'device_run_controller.dart';

class DevicePlanOverlayService with WidgetsBindingObserver {
  DevicePlanOverlayService._();

  static final DevicePlanOverlayService instance = DevicePlanOverlayService._();
  static const _channel = MethodChannel('lynai/device_overlay');

  bool _started = false;
  bool _foreground = true;

  void start() {
    if (_started || !Platform.isAndroid) return;
    _started = true;
    _channel.setMethodCallHandler(_handleOverlayCall);
    WidgetsBinding.instance.addObserver(this);
    DeviceRunController.instance.addListener(_syncOverlay);
  }

  void dispose() {
    if (!_started) return;
    _started = false;
    _channel.setMethodCallHandler(null);
    WidgetsBinding.instance.removeObserver(this);
    DeviceRunController.instance.removeListener(_syncOverlay);
    unawaited(_hide());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncOverlay();
  }

  void _syncOverlay() {
    final run = DeviceRunController.instance.snapshot;
    if (!_foreground && run.isActive) {
      unawaited(
        _channel.invokeMethod<void>('show', {
          'title': 'LynAI Agent Plan',
          'status': run.status.name,
          'purpose': run.purpose,
          'currentStep': run.currentStep,
          'lastAction': run.lastAction,
          'canResume': run.canResume,
          'canStop': run.canStop,
          'pauseReason': run.pauseReason,
        }),
      );
      return;
    }
    unawaited(_hide());
  }

  Future<dynamic> _handleOverlayCall(MethodCall call) async {
    switch (call.method) {
      case 'resume':
        DeviceRunController.instance.resume();
        return {'ok': true};
      case 'stop':
        DeviceRunController.instance.stop();
        return {'ok': true};
      default:
        throw MissingPluginException(
          'Unknown device overlay call: ${call.method}',
        );
    }
  }

  Future<void> _hide() async {
    try {
      await _channel.invokeMethod<void>('hide');
    } catch (_) {}
  }
}
