import '../models/conversation.dart';
import '../models/plugin.dart';
import 'tool_call_service.dart';

/// 组装发送给模型的 API 消息列表。
///
/// 主聊天与悬浮聊天共用此实现，避免两处 wire 语义漂移：
/// - system 段按固定顺序拼装：用户 systemPrompt、Agent 工具提示词、
///   时间上下文、注解提示词与调用方注入的附加提示词；
/// - 空内容 assistant 消息跳过；assistant 消息追加空 `reasoning_content`；
/// - 内容优先使用 `modelContextContent`，命中 [lastUserContentOverride]
///   的最后一条用户消息替换为 override 内容。
List<Map<String, dynamic>> buildApiMessages(
  Conversation conv,
  List<InstalledPlugin> plugins, {
  Object? lastUserContentOverride,
  bool enableTools = false,
  bool webSearchConfigured = false,
  String annotationPrompt = '',
  String extraSystemPrompt = '',
}) {
  final msgs = <Map<String, dynamic>>[];
  final promptContent = conv.settings.systemPrompt;
  final nativePrompt = ToolCallService.nativeSystemPromptFor(
    webSearchConfigured: webSearchConfigured,
  );
  final toolPrompt = conv.settings.agentEnabled
      ? '$nativePrompt\n\n${ToolCallService.agentSystemPromptWithSkills(plugins, webSearchConfigured: webSearchConfigured)}'
      : nativePrompt;
  final agentContext = conv.settings.agentEnabled
      ? ToolCallService.agentContextPrompt(conv)
      : '';
  final fullToolPrompt = <String>[
    toolPrompt,
    if (agentContext.isNotEmpty) agentContext,
    if (extraSystemPrompt.isNotEmpty) extraSystemPrompt,
  ].join('\n\n');
  final systemParts = <String>[
    if (promptContent.isNotEmpty) promptContent,
    if (enableTools) fullToolPrompt,
    if (enableTools) ToolCallService.currentTimeContext(),
    if (annotationPrompt.isNotEmpty) annotationPrompt,
  ];
  if (systemParts.isNotEmpty) {
    msgs.add({'role': 'system', 'content': systemParts.join('\n\n')});
  }
  final lastUserIndex = lastUserContentOverride == null
      ? -1
      : conv.messages.lastIndexWhere((m) => m.role == 'user');
  for (var i = 0; i < conv.messages.length; i++) {
    final m = conv.messages[i];
    if (m.role == 'assistant' && m.content.isEmpty) continue;
    msgs.add({
      'role': m.role,
      'content': i == lastUserIndex
          ? lastUserContentOverride
          : (m.modelContextContent ?? m.content),
      if (m.role == 'assistant') 'reasoning_content': '',
    });
  }
  return msgs;
}
