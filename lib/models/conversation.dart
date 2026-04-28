import 'message.dart';

/// 对话数据模型
///
/// 代表一次完整的对话会话。
/// [id] 唯一标识一个对话
/// [title] 对话的摘要标题，用于在历史列表中展示
/// [messages] 对话中的所有消息列表
/// [modelId] 本次对话使用的 AI 模型ID
/// [createdAt] 对话创建时间
/// [updatedAt] 对话最后更新时间
class Conversation {
  final String id;
  final String title;
  final List<Message> messages;
  final String modelId;
  final DateTime createdAt;
  final DateTime updatedAt;

  Conversation({
    required this.id,
    required this.title,
    required this.messages,
    required this.modelId,
    required this.createdAt,
    required this.updatedAt,
  });

  /// 获取对话开头的一部分内容，用于在历史列表中预览
  String get preview {
    if (messages.isEmpty) return '';
    final firstMsg = messages.first.content;
    return firstMsg.length > 80 ? '${firstMsg.substring(0, 80)}...' : firstMsg;
  }

  /// 从 JSON Map 创建 Conversation 实例
  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      id: json['id'] as String,
      title: json['title'] as String,
      messages: (json['messages'] as List<dynamic>)
          .map((m) => Message.fromJson(m as Map<String, dynamic>))
          .toList(),
      modelId: json['modelId'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  /// 将 Conversation 转换为 JSON Map，用于持久化存储
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'messages': messages.map((m) => m.toJson()).toList(),
      'modelId': modelId,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}

