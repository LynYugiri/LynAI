/// 对话中由 AI 创建插件草稿的持久化记录。
///
/// 插件本身由 [PluginProvider] 持久化，这里只保存对话与插件之间的产物
/// 关系，用于在消息流中渲染插件草稿卡片。卡片展示时仍应从
/// `PluginProvider.pluginById` 读取最新插件状态，避免两处状态分叉。
class ConversationPluginArtifact {
  /// 插件 ID。
  final String pluginId;

  /// 创建插件时对应的 assistant 消息 ID；为空时卡片放在消息流末尾。
  final String assistantMessageId;

  /// 创建时间。
  final DateTime createdAt;

  /// `create_plugin` 一次调用写入了哪些文件。
  final List<String> writtenFiles;

  const ConversationPluginArtifact({
    required this.pluginId,
    this.assistantMessageId = '',
    required this.createdAt,
    this.writtenFiles = const [],
  });

  factory ConversationPluginArtifact.fromJson(Map<String, dynamic> json) {
    return ConversationPluginArtifact(
      pluginId: json['pluginId'] as String? ?? '',
      assistantMessageId: json['assistantMessageId'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      writtenFiles: (json['writtenFiles'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .where((item) => item.isNotEmpty)
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() => {
    'pluginId': pluginId,
    if (assistantMessageId.isNotEmpty) 'assistantMessageId': assistantMessageId,
    'createdAt': createdAt.toIso8601String(),
    if (writtenFiles.isNotEmpty) 'writtenFiles': writtenFiles,
  };
}
