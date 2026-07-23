import 'dart:async';

import 'package:flutter/foundation.dart';

import '../providers/calendar_provider.dart';
import '../providers/task_provider.dart';
import 'calendar_platform_bridge.dart';
import 'calendar_platform_projection_service.dart';

/// 串行合并两个 Provider 的持久化完成信号，避免并发覆盖原生完整投影。
final class CalendarPlatformProjectionCoordinator {
  CalendarPlatformProjectionCoordinator({
    required this.tasks,
    required this.calendar,
    required this.bridge,
    this.projectionService = const CalendarPlatformProjectionService(),
  });

  final TaskProvider tasks;
  final CalendarProvider calendar;
  final CalendarPlatformBridge bridge;
  final CalendarPlatformProjectionService projectionService;

  Future<void> _queue = Future.value();
  bool _attached = false;

  void attach() {
    if (_attached) return;
    _attached = true;
    tasks.onSnapshotPersisted = _onSnapshotPersisted;
    calendar.onSnapshotPersisted = _onSnapshotPersisted;
  }

  void _onSnapshotPersisted() {
    unawaited(syncAfterPersistence());
  }

  Future<void> syncAfterPersistence() {
    final operation = _queue.then((_) async {
      await Future.wait([
        tasks.flushPendingSaves(),
        calendar.flushPendingSaves(),
      ]);
      final projection = projectionService.build(
        tasks: tasks.tasks,
        events: calendar.events,
        anniversaries: calendar.anniversaries,
      );
      await bridge.syncProjection(projection);
    });
    _queue = operation.catchError((Object error) {
      debugPrint('同步 Android 日历投影失败: $error');
    });
    return operation;
  }

  void dispose() {
    if (!_attached) return;
    tasks.onSnapshotPersisted = null;
    calendar.onSnapshotPersisted = null;
    _attached = false;
  }
}
