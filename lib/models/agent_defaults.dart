/// Agent 运行可调参数的共享默认值。
///
/// 这些值只描述默认行为；具体运行仍由调用方通过
/// [ConversationSettings] / [ToolCallService] / [AgentLoopRuntime] 传入。
library;

const int defaultAgentMaxToolRounds = 24;
const int minAgentMaxToolRounds = 4;
const int maxAgentMaxToolRounds = 64;
