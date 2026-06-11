import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/device_control.dart';

class DeviceRunSnapshot {
  final String? runId;
  final DeviceRunStatus status;
  final String purpose;
  final String currentStep;
  final String lastAction;
  final String? errorCode;
  final String? errorMessage;

  const DeviceRunSnapshot({
    required this.runId,
    required this.status,
    this.purpose = '',
    this.currentStep = '',
    this.lastAction = '',
    this.errorCode,
    this.errorMessage,
  });

  static const idle = DeviceRunSnapshot(
    runId: null,
    status: DeviceRunStatus.idle,
  );

  bool get isActive =>
      status == DeviceRunStatus.running || status == DeviceRunStatus.paused;
}

class DeviceRunController extends ChangeNotifier {
  DeviceRunController._();

  static final DeviceRunController instance = DeviceRunController._();
  static const _uuid = Uuid();

  DeviceRunSnapshot _snapshot = DeviceRunSnapshot.idle;
  Completer<void>? _resumeCompleter;

  DeviceRunSnapshot get snapshot => _snapshot;
  String? get activeRunId => _snapshot.runId;

  String start({required String purpose}) {
    final runId = _uuid.v4();
    _resumeCompleter = null;
    _snapshot = DeviceRunSnapshot(
      runId: runId,
      status: DeviceRunStatus.running,
      purpose: purpose,
    );
    notifyListeners();
    return runId;
  }

  void updateStep(String step) {
    if (!_snapshot.isActive) return;
    _snapshot = DeviceRunSnapshot(
      runId: _snapshot.runId,
      status: _snapshot.status,
      purpose: _snapshot.purpose,
      currentStep: step,
      lastAction: _snapshot.lastAction,
    );
    notifyListeners();
  }

  void recordAction(String action) {
    if (!_snapshot.isActive) return;
    _snapshot = DeviceRunSnapshot(
      runId: _snapshot.runId,
      status: _snapshot.status,
      purpose: _snapshot.purpose,
      currentStep: _snapshot.currentStep,
      lastAction: action,
    );
    notifyListeners();
  }

  void pause({String reason = 'user_touch'}) {
    if (_snapshot.status != DeviceRunStatus.running) return;
    _resumeCompleter ??= Completer<void>();
    _snapshot = DeviceRunSnapshot(
      runId: _snapshot.runId,
      status: DeviceRunStatus.paused,
      purpose: _snapshot.purpose,
      currentStep: _snapshot.currentStep,
      lastAction: reason,
    );
    notifyListeners();
  }

  void resume() {
    if (_snapshot.status != DeviceRunStatus.paused) return;
    final completer = _resumeCompleter;
    _resumeCompleter = null;
    _snapshot = DeviceRunSnapshot(
      runId: _snapshot.runId,
      status: DeviceRunStatus.running,
      purpose: _snapshot.purpose,
      currentStep: _snapshot.currentStep,
      lastAction: 'resumed',
    );
    notifyListeners();
    if (completer != null && !completer.isCompleted) completer.complete();
  }

  void stop() {
    if (!_snapshot.isActive) return;
    _snapshot = DeviceRunSnapshot(
      runId: _snapshot.runId,
      status: DeviceRunStatus.stopping,
      purpose: _snapshot.purpose,
      currentStep: _snapshot.currentStep,
      lastAction: 'stopping',
    );
    final completer = _resumeCompleter;
    _resumeCompleter = null;
    if (completer != null && !completer.isCompleted) completer.complete();
    notifyListeners();
  }

  void complete() {
    _finish(DeviceRunStatus.completed);
  }

  void fail(String code, String message) {
    _finish(DeviceRunStatus.failed, code: code, message: message);
  }

  void reset() {
    _resumeCompleter = null;
    _snapshot = DeviceRunSnapshot.idle;
    notifyListeners();
  }

  Future<Map<String, dynamic>?> beforeAction(String action) async {
    if (_snapshot.status == DeviceRunStatus.idle) return null;
    if (_snapshot.status == DeviceRunStatus.stopping) {
      return _stoppedError();
    }
    recordAction(action);
    final completer = _resumeCompleter;
    if (_snapshot.status == DeviceRunStatus.paused && completer != null) {
      await completer.future;
    }
    if (_snapshot.status == DeviceRunStatus.stopping) return _stoppedError();
    return null;
  }

  Future<Map<String, dynamic>?> delay(Duration duration) async {
    final deadline = DateTime.now().add(duration);
    while (DateTime.now().isBefore(deadline)) {
      final interrupted = await beforeAction('sleep');
      if (interrupted != null) return interrupted;
      final remaining = deadline.difference(DateTime.now());
      final slice = remaining < const Duration(milliseconds: 100)
          ? remaining
          : const Duration(milliseconds: 100);
      if (slice > Duration.zero) await Future<void>.delayed(slice);
    }
    return null;
  }

  Map<String, dynamic> statusJson() {
    return {
      'ok': true,
      'runId': _snapshot.runId,
      'status': _snapshot.status.name,
      'purpose': _snapshot.purpose,
      'currentStep': _snapshot.currentStep,
      'lastAction': _snapshot.lastAction,
      if (_snapshot.errorCode != null) 'errorCode': _snapshot.errorCode,
      if (_snapshot.errorMessage != null)
        'errorMessage': _snapshot.errorMessage,
    };
  }

  void _finish(DeviceRunStatus status, {String? code, String? message}) {
    _resumeCompleter = null;
    _snapshot = DeviceRunSnapshot(
      runId: _snapshot.runId,
      status: status,
      purpose: _snapshot.purpose,
      currentStep: _snapshot.currentStep,
      lastAction: _snapshot.lastAction,
      errorCode: code,
      errorMessage: message,
    );
    notifyListeners();
  }

  static Map<String, dynamic> _stoppedError() => {
    'ok': false,
    'error': {'code': 'user_stopped', 'message': '用户已停止设备任务'},
  };
}
