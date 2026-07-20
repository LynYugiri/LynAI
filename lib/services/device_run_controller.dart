import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/device_control.dart';

class DeviceRunSnapshot {
  final String? runId;
  final String? conversationId;
  final DeviceRunStatus status;
  final String purpose;
  final String currentStep;
  final String lastAction;
  final DateTime? startedAt;
  final DateTime? updatedAt;
  final String? pauseReason;
  final int actionCount;
  final String? errorCode;
  final String? errorMessage;

  const DeviceRunSnapshot({
    required this.runId,
    this.conversationId,
    required this.status,
    this.purpose = '',
    this.currentStep = '',
    this.lastAction = '',
    this.startedAt,
    this.updatedAt,
    this.pauseReason,
    this.actionCount = 0,
    this.errorCode,
    this.errorMessage,
  });

  static const idle = DeviceRunSnapshot(
    runId: null,
    status: DeviceRunStatus.idle,
  );

  bool get isActive =>
      status == DeviceRunStatus.running || status == DeviceRunStatus.paused;

  bool get canResume => status == DeviceRunStatus.paused;
  bool get canStop => isActive;
}

class DeviceRunController extends ChangeNotifier {
  DeviceRunController._();

  static final DeviceRunController instance = DeviceRunController._();
  static const _uuid = Uuid();

  DeviceRunSnapshot _snapshot = DeviceRunSnapshot.idle;
  Completer<void>? _resumeCompleter;

  DeviceRunSnapshot get snapshot => _snapshot;
  String? get activeRunId => _snapshot.runId;

  String start({required String purpose, String? conversationId}) {
    final runId = _uuid.v4();
    final now = DateTime.now();
    _resumeCompleter = null;
    _snapshot = DeviceRunSnapshot(
      runId: runId,
      conversationId: conversationId,
      status: DeviceRunStatus.running,
      purpose: purpose,
      startedAt: now,
      updatedAt: now,
    );
    notifyListeners();
    return runId;
  }

  void updateStep(String step) {
    if (!_snapshot.isActive) return;
    _snapshot = DeviceRunSnapshot(
      runId: _snapshot.runId,
      conversationId: _snapshot.conversationId,
      status: _snapshot.status,
      purpose: _snapshot.purpose,
      currentStep: step,
      lastAction: _snapshot.lastAction,
      startedAt: _snapshot.startedAt,
      updatedAt: DateTime.now(),
      pauseReason: _snapshot.pauseReason,
      actionCount: _snapshot.actionCount,
    );
    notifyListeners();
  }

  void recordAction(String action) {
    if (!_snapshot.isActive) return;
    _snapshot = DeviceRunSnapshot(
      runId: _snapshot.runId,
      conversationId: _snapshot.conversationId,
      status: _snapshot.status,
      purpose: _snapshot.purpose,
      currentStep: _snapshot.currentStep,
      lastAction: action,
      startedAt: _snapshot.startedAt,
      updatedAt: DateTime.now(),
      pauseReason: _snapshot.pauseReason,
      actionCount: _snapshot.actionCount + 1,
    );
    notifyListeners();
  }

  void pause({String reason = 'user_touch'}) {
    if (_snapshot.status != DeviceRunStatus.running) return;
    _resumeCompleter ??= Completer<void>();
    _snapshot = DeviceRunSnapshot(
      runId: _snapshot.runId,
      conversationId: _snapshot.conversationId,
      status: DeviceRunStatus.paused,
      purpose: _snapshot.purpose,
      currentStep: _snapshot.currentStep,
      lastAction: reason,
      startedAt: _snapshot.startedAt,
      updatedAt: DateTime.now(),
      pauseReason: reason,
      actionCount: _snapshot.actionCount,
    );
    notifyListeners();
  }

  void resume() {
    if (_snapshot.status != DeviceRunStatus.paused) return;
    final completer = _resumeCompleter;
    _resumeCompleter = null;
    _snapshot = DeviceRunSnapshot(
      runId: _snapshot.runId,
      conversationId: _snapshot.conversationId,
      status: DeviceRunStatus.running,
      purpose: _snapshot.purpose,
      currentStep: _snapshot.currentStep,
      lastAction: 'resumed',
      startedAt: _snapshot.startedAt,
      updatedAt: DateTime.now(),
      actionCount: _snapshot.actionCount,
    );
    notifyListeners();
    if (completer != null && !completer.isCompleted) completer.complete();
  }

  void stop() {
    if (!_snapshot.isActive) return;
    _snapshot = DeviceRunSnapshot(
      runId: _snapshot.runId,
      conversationId: _snapshot.conversationId,
      status: DeviceRunStatus.stopping,
      purpose: _snapshot.purpose,
      currentStep: _snapshot.currentStep,
      lastAction: 'stopping',
      startedAt: _snapshot.startedAt,
      updatedAt: DateTime.now(),
      pauseReason: _snapshot.pauseReason,
      actionCount: _snapshot.actionCount,
    );
    final completer = _resumeCompleter;
    _resumeCompleter = null;
    if (completer != null && !completer.isCompleted) completer.complete();
    notifyListeners();
  }

  void complete() {
    _finish(DeviceRunStatus.completed);
  }

  void stopped() {
    _finish(DeviceRunStatus.stopped);
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
    var remaining = duration;
    while (remaining > Duration.zero) {
      final interrupted = await beforeAction('sleep');
      if (interrupted != null) return interrupted;
      final slice = remaining < const Duration(milliseconds: 100)
          ? remaining
          : const Duration(milliseconds: 100);
      if (slice <= Duration.zero) break;
      await Future<void>.delayed(slice);
      remaining -= slice;
    }
    return null;
  }

  Map<String, dynamic> statusJson() {
    return {
      'ok': true,
      'runId': _snapshot.runId,
      'conversationId': _snapshot.conversationId,
      'status': _snapshot.status.name,
      'purpose': _snapshot.purpose,
      'currentStep': _snapshot.currentStep,
      'lastAction': _snapshot.lastAction,
      'canResume': _snapshot.canResume,
      'canStop': _snapshot.canStop,
      'actionCount': _snapshot.actionCount,
      if (_snapshot.pauseReason != null) 'pauseReason': _snapshot.pauseReason,
      if (_snapshot.startedAt != null)
        'startedAt': _snapshot.startedAt!.toIso8601String(),
      if (_snapshot.updatedAt != null)
        'updatedAt': _snapshot.updatedAt!.toIso8601String(),
      if (_snapshot.errorCode != null) 'errorCode': _snapshot.errorCode,
      if (_snapshot.errorMessage != null)
        'errorMessage': _snapshot.errorMessage,
    };
  }

  void _finish(DeviceRunStatus status, {String? code, String? message}) {
    _resumeCompleter = null;
    _snapshot = DeviceRunSnapshot(
      runId: _snapshot.runId,
      conversationId: _snapshot.conversationId,
      status: status,
      purpose: _snapshot.purpose,
      currentStep: _snapshot.currentStep,
      lastAction: _snapshot.lastAction,
      startedAt: _snapshot.startedAt,
      updatedAt: DateTime.now(),
      pauseReason: _snapshot.pauseReason,
      actionCount: _snapshot.actionCount,
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
