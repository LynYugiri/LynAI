import 'package:uuid/uuid.dart';

class RecycleBinItemTypes {
  static const conversation = 'conversation';
  static const note = 'note';
  static const notePage = 'notePage';
  static const schedule = 'schedule';
  static const calendarEvent = 'calendarEvent';
  static const anniversary = 'anniversary';
  static const task = 'task';
  static const taskList = 'taskList';
  static const todoList = 'todoList';
  static const roleplayScenario = 'roleplayScenario';
  static const roleplayThread = 'roleplayThread';
  static const pluginData = 'plugin.data';
  static const pluginFile = 'plugin.file';
}

class RecycleBinOwners {
  static const core = 'core';

  static String plugin(String pluginId) => 'plugin:$pluginId';

  static String? pluginId(String owner) {
    const prefix = 'plugin:';
    if (!owner.startsWith(prefix)) return null;
    final id = owner.substring(prefix.length).trim();
    return id.isEmpty ? null : id;
  }
}

class RecycleBinCategories {
  static const conversations = 'conversations';
  static const notes = 'notes';
  static const schedules = 'schedules';
  static const calendar = 'calendar';
  static const todos = 'todos';
  static const roleplay = 'roleplay';

  static String plugin(String pluginId, String category) {
    final safeCategory = category.trim().isEmpty ? 'data' : category.trim();
    return 'plugin:$pluginId:$safeCategory';
  }

  static String pluginFiles(String pluginId) => plugin(pluginId, 'files');
}

class RecycleBinItem {
  RecycleBinItem({
    String? id,
    required this.owner,
    required this.category,
    required this.type,
    required this.title,
    this.preview = '',
    DateTime? deletedAt,
    this.payload = const {},
  }) : id = id ?? const Uuid().v4(),
       deletedAt = deletedAt ?? DateTime.now();

  final String id;
  final String owner;
  final String category;
  final String type;
  final String title;
  final String preview;
  final DateTime deletedAt;
  final Map<String, dynamic> payload;

  factory RecycleBinItem.fromJson(Map<String, dynamic> json) {
    return RecycleBinItem(
      id: json['id'] as String? ?? '',
      owner: json['owner'] as String? ?? RecycleBinOwners.core,
      category: json['category'] as String? ?? '',
      type: json['type'] as String? ?? '',
      title: json['title'] as String? ?? '',
      preview: json['preview'] as String? ?? '',
      deletedAt:
          DateTime.tryParse(json['deletedAt'] as String? ?? '') ??
          DateTime.now(),
      payload: Map<String, dynamic>.from(json['payload'] as Map? ?? const {}),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'owner': owner,
    'category': category,
    'type': type,
    'title': title,
    if (preview.isNotEmpty) 'preview': preview,
    'deletedAt': deletedAt.toIso8601String(),
    'payload': payload,
  };
}

class RecycleBinCategorySummary {
  const RecycleBinCategorySummary({
    required this.id,
    required this.title,
    required this.group,
    required this.count,
  });

  final String id;
  final String title;
  final String group;
  final int count;
}
