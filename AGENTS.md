# LynAI Flutter 协作说明

## 验证

- 基础门禁：`flutter pub get`、`flutter analyze`、`flutter test`、`android/gradlew app:testDebugUnitTest`。
- 修改 Drift 表后运行 `dart run build_runner build --delete-conflicting-outputs`；`lib/services/storage_v2_database.g.dart` 必须提交且禁止手改。
- Agent/MCP 变化至少覆盖 loop continuation、取消、context budget、schema、snapshot、scheduler、durable graph、MCP transport 和 SecretStore 排除测试。

## Agent Runtime

- 主聊天、悬浮聊天和 Subagent 的模型多轮工具循环统一走 `AgentLoopRuntime`，不得在 Page、Controller 或具体工具中重建 continuation、轮数上限、强制最终 turn 或取消语义。
- 取消后 run 只产生一个 terminal result，不等待晚到工具结果，不继续下一 turn，也不把迟到结果追加回上下文。每个 tool invocation 必须得到对应终态结果。
- `AgentContextBuilder` 使用字符数近似 token、保留最新用户输入、移除历史 reasoning、限制 tool result，并最多执行一次 context-overflow 压缩重试；不要把它描述为精确 tokenizer。
- lifecycle hooks 默认超时、异常隔离且只读，不能修改请求、工具参数、结果、权限或 snapshot；持久化正确性不得依赖 hooks。

## 工具与持久化

- 工具 schema 注册时和执行前都必须通过 `AgentJsonSchemaValidator` 支持子集校验。插件或 MCP 的不兼容 schema 必须显式失败或禁用，不能静默放宽关键约束。
- `AgentToolRegistry.snapshot()` 是模型 turn 的不可变目录快照。动态注册、插件更新、MCP 刷新或断连不得把旧调用悄悄绑定到新实现。
- Agent 工具调用必须携带 Agent 身份及 run/turn/toolCall correlation；不得通过 `LynAICallerType.system` 绕过 Agent 权限。
- Drift 的 `runs`、`turns`、`items`、`tool_calls`、`snapshots` 仅记录本机 durable run graph，并经 `AgentPersistenceRepository` CAS 迁移。它们不进入普通/加密备份、云同步或 LAN 同步；重启只对账为 interrupted，不自动重放。
- `storage_v2/app.db` 是结构化数据权威源。长期附件和大工具结果使用现有私有 Resource/Blob 机制，不在模型上下文或运行记录中保存原始 base64。

## MCP

- 当前只实现 initialize/initialized、分页 `tools/list`、`tools/call`、`notifications/tools/list_changed` 和取消通知；不要宣称 resources、prompts、sampling、roots、elicitation、OAuth 或完整 MCP 已实现。
- Streamable HTTP 默认要求 HTTPS 和公网；HTTP 或私网必须分别显式允许。禁止 URL 凭据和跨 origin 转发敏感 header，并在请求及重定向前执行 host/DNS 校验。
- stdio 只在 Linux、macOS、Windows 可用，使用 `Process.start(..., runInShell: false)`、显式参数和隔离环境；Android、iOS、Web 不得展示为可用。
- MCP credential value 只进入 `SecretStore`。Drift 仅保存公开 transport、URL/command、参数、环境变量名和启用状态；Secret 不得进入日志、备份或同步。
- MCP 工具进入共享 `AgentToolRegistry`，连接、刷新、禁用或断开时只移除自己持有的 registration，并防止旧连接竞态重新发布工具。

## 文档

- Agent loop、取消、上下文、hooks、run graph 或工具注册变化更新 `doc/agent-runtime.md`。
- MCP transport、协议范围、凭据、平台门控或设置页变化更新 `doc/mcp.md`。
- canonical relay tool/reasoning/SSE 变化同步更新 `doc/protocol-v1.md` 和后端 README。
