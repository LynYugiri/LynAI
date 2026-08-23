import 'package:flutter/foundation.dart';

import '../models/scheduled_task.dart';
import '../services/storage_v2_service.dart';

final class ScheduledTaskLoadResult {
  const ScheduledTaskLoadResult({required this.tasks});

  final List<ScheduledTask> tasks;
}

/// 定时任务分区持久化边界。
///
/// `scheduled_tasks.json` 是设备本地的自动化数据，使用 storage_v2 通用
/// 数据文件保存；它没有同步表映射，因此不进入云同步或 LAN 同步。
class ScheduledTaskRepository {
  factory ScheduledTaskRepository({StorageV2Service? storageV2}) {
    return ScheduledTaskRepository._(storageV2 ?? StorageV2Service());
  }

  ScheduledTaskRepository._(this._storageV2);

  static const _fileName = 'scheduled_tasks.json';

  final StorageV2Service _storageV2;

  Future<ScheduledTaskLoadResult> load() async {
    final data = await _storageV2.loadDataFile(_fileName);
    final rawTasks = data['tasks'];
    if (rawTasks != null && rawTasks is! List) {
      throw const FormatException('scheduled_tasks.json tasks 必须是列表');
    }
    final tasks = <ScheduledTask>[];
    for (final item in rawTasks as List<dynamic>? ?? const []) {
      try {
        if (item is! Map) continue;
        tasks.add(ScheduledTask.fromJson(Map<String, dynamic>.from(item)));
      } catch (error) {
        debugPrint('跳过损坏的定时任务: $error');
      }
    }
    return ScheduledTaskLoadResult(tasks: tasks);
  }

  /// 用完整任务快照替换分区。
  Future<void> replace(Iterable<ScheduledTask> tasks) {
    return _storageV2.writeDataFile(_fileName, {
      'tasks': tasks.map((task) => task.toJson()).toList(),
    });
  }
}
