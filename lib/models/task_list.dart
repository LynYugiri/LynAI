/// 仅保存清单自身信息的任务清单元数据。
final class TaskList {
  /// 清单唯一标识符。
  final String id;

  /// 清单标题。
  final String title;

  /// 清单间的稳定排序值。
  final int sortOrder;

  /// 创建时间。
  final DateTime createdAt;

  /// 最后更新时间。
  final DateTime updatedAt;

  /// 创建任务清单元数据。
  const TaskList({
    required this.id,
    required this.title,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
  });

  /// 从 JSON 创建任务清单元数据。
  factory TaskList.fromJson(Map<String, dynamic> json) {
    return TaskList(
      id: json['id'] as String,
      title: json['title'] as String,
      sortOrder: json['sortOrder'] as int,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  /// 将任务清单元数据序列化为 JSON。
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'sortOrder': sortOrder,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  /// 创建修改后的任务清单元数据副本。
  TaskList copyWith({
    String? id,
    String? title,
    int? sortOrder,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return TaskList(
      id: id ?? this.id,
      title: title ?? this.title,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// 表示任务在清单中的归属和顺序，不承载任务内容。
final class TaskListEntry {
  /// 所属清单标识符。
  final String taskListId;

  /// 任务标识符。
  final String taskId;

  /// 清单内从零开始的稳定顺序。
  final int position;

  /// 最后更新时间。
  final DateTime updatedAt;

  /// 创建清单条目。
  TaskListEntry({
    required this.taskListId,
    required this.taskId,
    required this.position,
    required this.updatedAt,
  }) {
    if (position < 0) throw ArgumentError.value(position, 'position');
  }

  /// 从 JSON 创建清单条目。
  factory TaskListEntry.fromJson(Map<String, dynamic> json) {
    return TaskListEntry(
      taskListId: json['taskListId'] as String,
      taskId: json['taskId'] as String,
      position: json['position'] as int,
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  /// 将清单条目序列化为 JSON。
  Map<String, dynamic> toJson() => {
    'taskListId': taskListId,
    'taskId': taskId,
    'position': position,
    'updatedAt': updatedAt.toIso8601String(),
  };

  /// 创建修改后的清单条目副本。
  TaskListEntry copyWith({
    String? taskListId,
    String? taskId,
    int? position,
    DateTime? updatedAt,
  }) {
    return TaskListEntry(
      taskListId: taskListId ?? this.taskListId,
      taskId: taskId ?? this.taskId,
      position: position ?? this.position,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
