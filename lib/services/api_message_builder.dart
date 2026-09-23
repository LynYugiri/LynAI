import '../models/conversation.dart';
import '../models/message.dart';
import '../models/plugin.dart';
import '../models/workspace.dart';
import 'tool_call_service.dart';

/// 组装发送给模型的 API 消息列表。
///
/// 主聊天与悬浮聊天共用此实现，避免两处 wire 语义漂移：
/// - system 段按固定顺序拼装：用户 systemPrompt、Agent 工具提示词、
///   时间上下文、注解提示词与调用方注入的附加提示词；
/// - `/压缩` 产生的上下文检查点只改这一份发送副本：被覆盖的消息换成一条
///   system 摘要，[Conversation.messages] 本身一条都不删；
/// - 会话引用池不进上下文，只在 system 段末尾追加一句「可用工具查询」的提示；
/// - 空内容 assistant 消息跳过；assistant 消息追加空 `reasoning_content`；
/// - 内容优先使用 `modelContextContent`，命中 [lastUserContentOverride]
///   的最后一条用户消息替换为 override 内容。
List<Map<String, dynamic>> buildApiMessages(
  Conversation conv,
  List<InstalledPlugin> plugins, {
  Object? lastUserContentOverride,
  bool enableTools = false,
  bool webSearchConfigured = false,
  Workspace? workspace,
  bool workspaceReadAllowed = false,
  bool workspaceWriteAllowed = false,
  bool workspaceFileAvailable = false,
  String annotationPrompt = '',
  String extraSystemPrompt = '',
  String roleMemoryBlock = '',
  String memoryNudge = '',
  bool roleMemoryAvailable = false,
  bool referencePoolAvailable = false,
  bool conversationsReadAvailable = false,
}) {
  final msgs = <Map<String, dynamic>>[];
  final promptContent = conv.settings.systemPrompt;
  final nativePrompt = ToolCallService.nativeSystemPromptFor(
    webSearchConfigured: webSearchConfigured,
    conversationsReadAvailable: conversationsReadAvailable,
  );
  final toolPrompt = conv.settings.agentEnabled
      ? '$nativePrompt\n\n${ToolCallService.agentSystemPromptWithSkills(plugins, webSearchConfigured: webSearchConfigured)}'
      : nativePrompt;
  final agentContext = conv.settings.agentEnabled
      ? ToolCallService.agentContextPrompt(conv)
      : '';
  final workspacePrompt = conv.settings.agentEnabled
      ? ToolCallService.pluginWorkspacePrompt(conv.pluginWorkspaceId, plugins)
      : '';
  final localWorkspacePrompt = conv.settings.agentEnabled
      ? ToolCallService.workspaceSystemPrompt(
          workspace,
          readAllowed: workspaceReadAllowed,
          writeAllowed: workspaceWriteAllowed,
          fileAvailable: workspaceFileAvailable,
        )
      : '';
  final fullToolPrompt = <String>[
    toolPrompt,
    if (agentContext.isNotEmpty) agentContext,
    if (workspacePrompt.isNotEmpty) workspacePrompt,
    if (localWorkspacePrompt.isNotEmpty) localWorkspacePrompt,
    if (extraSystemPrompt.isNotEmpty) extraSystemPrompt,
  ].join('\n\n');
  final systemParts = <String>[
    if (promptContent.isNotEmpty) promptContent,
    if (enableTools) fullToolPrompt,
    if (enableTools && roleMemoryAvailable) ToolCallService.memorySystemPrompt,
    if (enableTools) ToolCallService.currentTimeContext(),
    if (annotationPrompt.isNotEmpty) annotationPrompt,
    if (roleMemoryBlock.isNotEmpty) roleMemoryBlock,
    if (enableTools && memoryNudge.isNotEmpty) memoryNudge,
    // 放在 system 段最后：池子清单不占预算，也不该被当成对话历史的一部分。
    if (enableTools && referencePoolAvailable && !conv.referencePool.isEmpty)
      ToolCallService.referencePoolSystemPrompt,
  ];
  if (systemParts.isNotEmpty) {
    msgs.add({'role': 'system', 'content': systemParts.join('\n\n')});
  }
  // 覆盖集合与现存消息对不上（撤回/分支/远端同步改写过 ID）时按失效处理，
  // 不能拿一份描述已不存在历史的摘要去顶替上下文。
  final alive = {for (final message in conv.messages) message.id};
  final stored = conv.contextCheckpoint;
  final checkpoint = stored != null &&
          stored.coveredMessageIds.any(alive.contains)
      ? stored
      : null;
  final covered = checkpoint == null
      ? const <String>{}
      : checkpoint.coveredMessageIds.where(alive.contains).toSet();
  final checkpointMessage = checkpoint == null || checkpoint.isEmpty
      ? null
      : {
          'role': 'system',
          'content': 'Context checkpoint:\n${checkpoint.summary.trim()}',
        };
  final lastUserIndex = lastUserContentOverride == null
      ? -1
      : conv.messages.lastIndexWhere((m) => m.role == 'user');
  var checkpointInserted = false;
  for (var i = 0; i < conv.messages.length; i++) {
    final m = conv.messages[i];
    if (covered.contains(m.id)) {
      // 被覆盖的整段历史换成一条摘要，只在首次出现的位置插入一次。
      if (!checkpointInserted && checkpointMessage != null) {
        msgs.add(checkpointMessage);
        checkpointInserted = true;
      }
      continue;
    }
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

/// `/压缩` 之后应标记为「已被上下文检查点覆盖」的消息 ID，按原始顺序返回。
///
/// 摘要只包含上下文里最新用户消息**之前**的部分，所以这里必须用与
/// [buildApiMessages] 相同的过滤规则把那段上下文映射回原始消息：已被现有
/// 检查点顶替的消息不会再进入上下文，空 assistant 占位也不发送。
///
/// 不能用「API 消息条数」做算术：条数里既少了空 assistant 占位、又多了那条摘要，
/// 得到的前缀会把摘要从未包含过的消息（最新用户消息及其后的回复）也标记成已覆盖，
/// 下一次请求就只剩摘要、丢掉用户刚问的问题。
List<String> coveredMessageIdsForCompaction(Conversation conv) {
  final alive = {for (final message in conv.messages) message.id};
  final stored = conv.contextCheckpoint;
  final alreadyCovered = <String>{
    if (stored != null)
      for (final id in stored.coveredMessageIds)
        if (alive.contains(id)) id,
  };
  // 仍然会进入上下文的消息：已覆盖的不再出现，空 assistant 占位也不发送。
  final surviving = <Message>[
    for (final message in conv.messages)
      if (!alreadyCovered.contains(message.id) &&
          !(message.role == 'assistant' && message.content.isEmpty))
        message,
  ];
  final lastUserIndex = surviving.lastIndexWhere(
    (message) => message.role == 'user',
  );
  final newlyCovered = <String>{
    for (final message in surviving.take(
      lastUserIndex < 0 ? surviving.length : lastUserIndex,
    ))
      message.id,
  };
  if (alreadyCovered.isEmpty && newlyCovered.isEmpty) return const [];
  return [
    for (final message in conv.messages)
      if (alreadyCovered.contains(message.id) ||
          newlyCovered.contains(message.id))
        message.id,
  ];
}
