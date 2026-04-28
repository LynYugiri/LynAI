/// 消息数据模型
///
/// 表示对话中的单条消息，包含角色和内容。
/// [role] 可以是 'user'（用户）或 'assistant'（AI助手）
/// [content] 是消息的文本内容
/// [timestamp] 记录消息发送的时间
class Message {
  final String id;
  final String role; // 'user' 或 'assistant'
  final String content;
  final DateTime timestamp;

  Message({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
  });

  /// 从 JSON Map 创建 Message 实例
  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'] as String,
      role: json['role'] as String,
      content: json['content'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }

  /// 将 Message 转换为 JSON Map，用于持久化存储
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'role': role,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}

