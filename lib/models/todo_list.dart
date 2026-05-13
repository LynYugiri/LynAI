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

  TodoList copyWith({String? title, List<TodoItem>? items}) {
    return TodoList(
      id: id,
      title: title ?? this.title,
      items: items ?? this.items,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}

class TodoItem {
  final String id;
  final String text;
  final bool done;

  const TodoItem({required this.id, required this.text, this.done = false});

  factory TodoItem.fromJson(Map<String, dynamic> json) {
    return TodoItem(
      id: json['id'] as String,
      text: json['text'] as String? ?? '',
      done: json['done'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'text': text, 'done': done};
  }

  TodoItem copyWith({String? text, bool? done}) {
    return TodoItem(id: id, text: text ?? this.text, done: done ?? this.done);
  }
}
