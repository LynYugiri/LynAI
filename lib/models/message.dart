/// 消息数据模型。
///
/// [content] 始终保存可直接发送给文本模型的内容。附件只通过 [images]
/// 字段保存路径和元数据；字段名保留为 images 是为了兼容已持久化的旧对话。
class Message {
  /// 消息唯一标识符。
  final String id;

  /// 消息角色，'user' 或 'assistant'。
  final String role;

  /// 消息文本内容。
  final String content;

  /// 消息附带的图片和文件列表。
  final List<MessageImage> images;

  /// assistant 消息的思考过程内容。
  final String? thinkingContent;

  /// 消息时间戳。
  final DateTime timestamp;

  /// 创建一个消息实例。
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
          .whereType<Map>()
          .map((e) => MessageImage.fromJson(Map<String, dynamic>.from(e)))
          .where((e) => e.path.isNotEmpty)
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

/// 消息附带的图片或文件元数据。
///
/// 不直接保存 picker 返回的临时路径，避免系统清理缓存后历史消息无法再次渲染。
class MessageImage {
  /// 应用私有目录中的附件路径。
  final String path;

  /// 附件文件名。
  final String name;

  /// 附件文件大小（字节）。
  final int size;

  /// 附件的 MIME 类型。
  final String mimeType;

  /// 创建一个消息附件实例。
  const MessageImage({
    required this.path,
    required this.name,
    required this.size,
    this.mimeType = 'application/octet-stream',
  });

  /// 判断该附件是否为图片类型。
  bool get isImage => mimeType.startsWith('image/');

  /// 从 JSON 数据创建 [MessageImage] 实例。
  factory MessageImage.fromJson(Map<String, dynamic> json) {
    final path = json['path'] as String? ?? json['filePath'] as String? ?? '';
    final name = json['name'] as String? ?? _nameFromPath(path);
    return MessageImage(
      path: path,
      name: name,
      size: (json['size'] as num?)?.toInt() ?? 0,
      mimeType: json['mimeType'] as String? ?? _mimeTypeFromName(name),
    );
  }

  /// 将当前实例序列化为 JSON Map。
  Map<String, dynamic> toJson() => {
    'path': path,
    'name': name,
    'size': size,
    'mimeType': mimeType,
  };

  /// 根据文件名后缀推断 MIME 类型。
  static String _mimeTypeFromName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.txt') || lower.endsWith('.md')) return 'text/plain';
    if (lower.endsWith('.json')) return 'application/json';
    if (lower.endsWith('.csv')) return 'text/csv';
    return 'application/octet-stream';
  }

  /// 从文件路径中提取文件名。
  static String _nameFromPath(String path) {
    final normalized = path.replaceAll('\\', '/');
    final slash = normalized.lastIndexOf('/');
    final name = slash == -1 ? normalized : normalized.substring(slash + 1);
    return name.isEmpty ? 'file' : name;
  }
}
