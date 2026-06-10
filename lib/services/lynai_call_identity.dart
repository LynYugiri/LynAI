enum LynAICallerType { assistant, agent, lua, plugin }

class LynAICallIdentity {
  final LynAICallerType type;
  final String? conversationId;
  final String? pluginId;
  final String? toolName;
  final LynAICallIdentity? parent;

  const LynAICallIdentity({
    required this.type,
    this.conversationId,
    this.pluginId,
    this.toolName,
    this.parent,
  });

  LynAICallIdentity child({
    required LynAICallerType type,
    String? pluginId,
    String? toolName,
  }) {
    return LynAICallIdentity(
      type: type,
      conversationId: conversationId,
      pluginId: pluginId,
      toolName: toolName,
      parent: this,
    );
  }
}
