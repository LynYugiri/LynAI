/// 一个待办清单。
///
/// 清单负责组织任务顺序；单个任务只保存文本和完成状态。页面层处理 Markdown
/// 导入导出、拖拽排序和长图分享。
class TodoList {
  final String id;
  final String title;
  final List<TodoItem> items;
  final DateTime createdAt;
  final DateTime updatedAt;

  const TodoList({
    required this.id,
    required this.title,
    required this.items,
    required this.createdAt,
    required this.updatedAt,
  });

  factory TodoList.fromJson(Map<String, dynamic> json) {
    return TodoList(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      items: (json['items'] as List<dynamic>? ?? [])
          .map((e) => TodoItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'items': items.map((e) => e.toJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  TodoList copyWith({String? id, String? title, List<TodoItem>? items}) {
    return TodoList(
      id: id ?? this.id,
      title: title ?? this.title,
      items: items ?? this.items,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}

/// 待办清单中的一个任务项。
class TodoItem {
  final String id;
  final String text;
  final bool done;
  final DateTime? updatedAt;

  const TodoItem({
    required this.id,
    required this.text,
    this.done = false,
    this.updatedAt,
  });

  factory TodoItem.fromJson(Map<String, dynamic> json) {
    return TodoItem(
      id: json['id'] as String,
      text: json['text'] as String? ?? '',
      done: json['done'] as bool? ?? false,
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'done': done,
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
    };
  }

  TodoItem copyWith({String? id, String? text, bool? done}) {
    return TodoItem(
      id: id ?? this.id,
      text: text ?? this.text,
      done: done ?? this.done,
      updatedAt: DateTime.now(),
    );
  }
}
