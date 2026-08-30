/// Agent 运行可调参数的共享默认值。
///
/// 这些值只描述默认行为；具体运行仍由调用方通过
/// [ConversationSettings] / [ToolCallService] / [AgentLoopRuntime] 传入。
library;

const int defaultAgentMaxToolRounds = 24;
const int minAgentMaxToolRounds = 4;
const int maxAgentMaxToolRounds = 64;

/// 是否默认启用对话上下文自动压缩与预算截断。
///
/// 关闭后 `AgentContextBuilder` 不压缩、不按预算裁剪历史，上下文超限时
/// 直接由模型/服务返回错误，不再自动重试。
const bool defaultContextCompressionEnabled = true;

/// 模型上下文窗口未知时的默认输入预算（256k token）。
///
/// 仅在 `ModelConfig.effectiveContextWindow` 各来源都为空时生效。
const int defaultAgentContextWindow = 262144;
