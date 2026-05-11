/// 消息数据模型。
///
/// [content] 始终保存可直接发送给文本模型的内容。即使用户附带了图片，
/// 当前也不会把二进制图片内容塞进这里；图片只通过 [images] 保存为附件，
/// 需要模型理解图片时由 OCR 先把图片转成文本，再追加到 [content]。
class Message {
  final String id;
  final String role; // 'user' 或 'assistant'
  final String content;
  final List<MessageImage> images;
  final String? thinkingContent;
  final DateTime timestamp;

  Message({
    required this.id,
    required this.role,
    required this.content,
    this.images = const [],
    this.thinkingContent,
    required this.timestamp,
  });

  /// 从 JSON Map 创建 Message 实例
  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'] as String,
      role: json['role'] as String,
      content: json['content'] as String,
      images: (json['images'] as List<dynamic>? ?? [])
          .map((e) => MessageImage.fromJson(e as Map<String, dynamic>))
          .toList(),
      thinkingContent: json['thinkingContent'] as String?,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }

  /// 将 Message 转换为 JSON Map，用于持久化存储
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'role': role,
      'content': content,
      if (images.isNotEmpty) 'images': images.map((e) => e.toJson()).toList(),
      if (thinkingContent != null && thinkingContent!.isNotEmpty)
        'thinkingContent': thinkingContent,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}

class MessageImage {
  /// 应用私有目录中的图片路径。
  ///
  /// 不直接保存 image_picker 返回的临时路径，避免系统清理缓存后历史消息无法
  /// 再次渲染图片。
  final String path;
  final String name;
  final int size;

  const MessageImage({
    required this.path,
    required this.name,
    required this.size,
  });

  factory MessageImage.fromJson(Map<String, dynamic> json) {
    return MessageImage(
      path: json['path'] as String,
      name: json['name'] as String? ?? 'image',
      size: json['size'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {'path': path, 'name': name, 'size': size};
}
