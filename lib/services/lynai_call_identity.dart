enum LynAICallerType {
  assistant,
  agent,
  agentLua,
  lua,
  plugin,
  pluginWebview,
  system,
}

class LynAICallIdentity {
  final LynAICallerType type;
  final String? conversationId;
  final String? runId;
  final String? turnId;
  final String? toolCallId;
  final String? pluginId;
  final String? toolName;
  final LynAICallIdentity? parent;

  const LynAICallIdentity({
    required this.type,
    this.conversationId,
    this.runId,
    this.turnId,
    this.toolCallId,
    this.pluginId,
    this.toolName,
    this.parent,
  });

  LynAICallIdentity child({
    required LynAICallerType type,
    String? runId,
    String? turnId,
    String? toolCallId,
    String? pluginId,
    String? toolName,
  }) {
    return LynAICallIdentity(
      type: type,
      conversationId: conversationId,
      runId: runId ?? this.runId,
      turnId: turnId ?? this.turnId,
      toolCallId: toolCallId ?? this.toolCallId,
      pluginId: pluginId,
      toolName: toolName,
      parent: this,
    );
  }
}
