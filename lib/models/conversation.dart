import 'message.dart';

class ConversationSettings {
  final String modelId;
  final bool thinking;
  final String? selectedSystemPromptId;
  final String systemPrompt;
  final String? speechModelId;
  final String? imageModelId;
  final bool imageOcrEnabled;
  final String? imageRecognitionModelId;
  final bool imageRecognitionEnabled;
  final String imageRecognitionPrompt;

  ConversationSettings({
    required this.modelId,
    this.thinking = true,
    this.selectedSystemPromptId,
    this.systemPrompt = 'You are a helpful assistant.',
    this.speechModelId,
    this.imageModelId,
    this.imageOcrEnabled = false,
    this.imageRecognitionModelId,
    this.imageRecognitionEnabled = false,
    this.imageRecognitionPrompt = '请根据下面的文件内容或识别结果回答。',
  });

  static const _sentinel = Object();

  ConversationSettings copyWith({
    String? modelId,
    bool? thinking,
    Object? selectedSystemPromptId = _sentinel,
    String? systemPrompt,
    Object? speechModelId = _sentinel,
    Object? imageModelId = _sentinel,
    bool? imageOcrEnabled,
    Object? imageRecognitionModelId = _sentinel,
    bool? imageRecognitionEnabled,
    String? imageRecognitionPrompt,
  }) {
    return ConversationSettings(
      modelId: modelId ?? this.modelId,
      thinking: thinking ?? this.thinking,
      selectedSystemPromptId: identical(selectedSystemPromptId, _sentinel)
          ? this.selectedSystemPromptId
          : selectedSystemPromptId as String?,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      speechModelId: identical(speechModelId, _sentinel)
          ? this.speechModelId
          : speechModelId as String?,
      imageModelId: identical(imageModelId, _sentinel)
          ? this.imageModelId
          : imageModelId as String?,
      imageOcrEnabled: imageOcrEnabled ?? this.imageOcrEnabled,
      imageRecognitionModelId: identical(imageRecognitionModelId, _sentinel)
          ? this.imageRecognitionModelId
          : imageRecognitionModelId as String?,
      imageRecognitionEnabled:
          imageRecognitionEnabled ?? this.imageRecognitionEnabled,
      imageRecognitionPrompt:
          imageRecognitionPrompt ?? this.imageRecognitionPrompt,
    );
  }

  factory ConversationSettings.fromJson(
    Map<String, dynamic> json, {
    String fallbackModelId = '',
  }) {
    return ConversationSettings(
      modelId: json['modelId'] as String? ?? fallbackModelId,
      thinking: json['thinking'] as bool? ?? true,
      selectedSystemPromptId: json['selectedSystemPromptId'] as String?,
      systemPrompt:
          json['systemPrompt'] as String? ?? 'You are a helpful assistant.',
      speechModelId: json['speechModelId'] as String?,
      imageModelId: json['imageModelId'] as String?,
      imageOcrEnabled: json['imageOcrEnabled'] as bool? ?? false,
      imageRecognitionModelId: json['imageRecognitionModelId'] as String?,
      imageRecognitionEnabled:
          json['imageRecognitionEnabled'] as bool? ?? false,
      imageRecognitionPrompt:
          json['imageRecognitionPrompt'] as String? ??
          json['imagePrompt'] as String? ??
          '请根据下面的文件内容或识别结果回答。',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'modelId': modelId,
      'thinking': thinking,
      if (selectedSystemPromptId != null)
        'selectedSystemPromptId': selectedSystemPromptId,
      'systemPrompt': systemPrompt,
      if (speechModelId != null) 'speechModelId': speechModelId,
      if (imageModelId != null) 'imageModelId': imageModelId,
      'imageOcrEnabled': imageOcrEnabled,
      if (imageRecognitionModelId != null)
        'imageRecognitionModelId': imageRecognitionModelId,
      'imageRecognitionEnabled': imageRecognitionEnabled,
      'imageRecognitionPrompt': imageRecognitionPrompt,
    };
  }
}

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
  final ConversationSettings settings;
  final String roleId;
  final DateTime createdAt;
  final DateTime updatedAt;

  Conversation({
    required this.id,
    required this.title,
    required this.messages,
    required this.modelId,
    ConversationSettings? settings,
    this.roleId = 'default',
    required this.createdAt,
    required this.updatedAt,
  }) : settings = settings ?? ConversationSettings(modelId: modelId);

  /// 获取对话开头的一部分内容，用于在历史列表中预览
  String get preview {
    if (messages.isEmpty) return '';
    final first = messages.first;
    final raw = first.content;
    final clean = raw.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    if (clean.isEmpty && first.images.isNotEmpty) {
      final firstName = first.images.first.name;
      final suffix = first.images.length > 1
          ? ' 等 ${first.images.length} 个附件'
          : '';
      return '[附件] $firstName$suffix';
    }
    return clean.length > 80 ? '${clean.substring(0, 80)}...' : clean;
  }

  /// 从 JSON Map 创建 Conversation 实例
  factory Conversation.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    final title = json['title'] as String?;
    final modelId = json['modelId'] as String?;
    final createdAt = DateTime.tryParse(json['createdAt'] as String? ?? '');
    final updatedAt = DateTime.tryParse(json['updatedAt'] as String? ?? '');
    if (id == null ||
        id.isEmpty ||
        title == null ||
        modelId == null ||
        createdAt == null ||
        updatedAt == null) {
      throw const FormatException('Malformed conversation');
    }
    return Conversation(
      id: id,
      title: title,
      messages: (json['messages'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((m) => Message.fromJson(Map<String, dynamic>.from(m)))
          .toList(),
      modelId: modelId,
      settings: json['settings'] != null
          ? ConversationSettings.fromJson(
              json['settings'] as Map<String, dynamic>,
              fallbackModelId: modelId,
            )
          : ConversationSettings(modelId: modelId),
      roleId: json['roleId'] as String? ?? 'default',
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  /// 将 Conversation 转换为 JSON Map，用于持久化存储
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'messages': messages.map((m) => m.toJson()).toList(),
      'modelId': modelId,
      'settings': settings.toJson(),
      'roleId': roleId,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}
