# LynAI Flutter 协作说明

## 验证

- 基础门禁：`flutter pub get`、`flutter analyze`、`flutter test`、`android/gradlew app:testDebugUnitTest`。
- 依赖已就绪时可用 `flutter analyze --no-pub` 和 `flutter test --no-pub`。
- 聚焦测试：`flutter test test/<name>_test.dart`；单个 case 追加 `--plain-name '<完整测试名>'`。
- 涉及 Android/Kotlin、MethodChannel、平台投影、悬浮窗或原生 OCR wiring 时，至少追加 `android/gradlew app:testDebugUnitTest`。
- 修改 Drift 表后运行 `dart run build_runner build --delete-conflicting-outputs`；`lib/services/storage_v2_database.g.dart` 必须提交且禁止手改。
- Agent/MCP 变化至少覆盖 loop continuation、取消、context budget、schema、snapshot、scheduler、durable graph、MCP transport 和 SecretStore 排除测试。

## Agent Runtime

- 主聊天、悬浮聊天和 Subagent 的模型多轮工具循环统一走 `AgentLoopRuntime`，不得在 Page、Controller 或具体工具中重建 continuation、轮数上限、强制最终 turn 或取消语义。
- 取消后 run 只产生一个 terminal result，不等待晚到工具结果，不继续下一 turn，也不把迟到结果追加回上下文。每个 tool invocation 必须得到对应终态结果。
- 单次 run 的工具轮数上限来自 `ConversationSettings.maxToolRounds`，共享默认值在 `lib/models/agent_defaults.dart`（默认 24，范围 4–64）；`ToolCallService.runMaxToolRounds` 必须落在同一范围内。达到上限后 runtime 注入 final instruction、隐藏 tools 并执行一次强制最终 turn；最终 turn 仍返回工具调用时不执行，并在完成结果上设置 `toolRoundLimitReached=true`。每个 tool result 完成后 runtime 发出 `toolCompleted` 事件供 UI 清除“正在调用工具”状态。
- `AgentContextBuilder` 使用字符数近似 token、保留最新用户输入、移除历史 reasoning、限制 tool result，并最多执行一次 context-overflow 压缩重试；不要把它描述为精确 tokenizer。生产调用方现在注入 `ModelContextCompactor`（`lib/services/model_context_compactor.dart`）：用当前 Chat 模型关闭 thinking/tools 压缩被裁剪历史；任何异常、超时或空摘要都回退到现有截断策略。
- `ApiService` 将常见上下文超限错误包装为 `AgentContextOverflowException`，runtime 按类型触发压缩重试而不是匹配字符串。上下文预算按 `ModelConfig.effectiveContextWindow`（用户本地覆盖 > 托管 `/relay/config` > endpoint 拉取 > 默认）构造。
- lifecycle hooks 默认超时、异常隔离且只读，不能修改请求、工具参数、结果、权限或 snapshot；持久化正确性不得依赖 hooks。

## 工具与持久化

- 工具 schema 注册时和执行前都必须通过 `AgentJsonSchemaValidator` 支持子集校验。插件或 MCP 的不兼容 schema 必须显式失败或禁用，不能静默放宽关键约束。
- `AgentToolRegistry.snapshot()` 是模型 turn 的不可变目录快照。动态注册、插件更新、MCP 刷新或断连不得把旧调用悄悄绑定到新实现。
- Agent 工具调用必须携带 Agent 身份及 run/turn/toolCall correlation；不得通过 `LynAICallerType.system` 绕过 Agent 权限。
- 内置 `knowledge_search` 是 `ToolCallService` 的本地只读工具，只在注入 `KnowledgeProvider` 且 run snapshot 具有 `storage:read` 时注册。它必须只检索启用的库、类别和条目，保持查询/schema、扫描正文、结果数量及返回正文边界，并在分批扫描间检查取消和 deadline；不得改成不可取消的同步全表扫描，也不得自动把完整知识库注入每轮上下文。
- Drift 的 `runs`、`turns`、`items`、`tool_calls`、`snapshots` 仅记录本机 durable run graph，并经 `AgentPersistenceRepository` CAS 迁移。它们不进入普通/加密备份、云同步或 LAN 同步；重启只对账为 interrupted，不自动重放。
- `storage_v2/app.db` 是结构化数据权威源。长期附件和大工具结果使用现有私有 Resource/Blob 机制，不在模型上下文或运行记录中保存原始 base64。

## 知识库

- `KnowledgeProvider` 是知识库、类别、条目、来源和解释的唯一内存所有者。它因类型化 mutation、完整快照回滚和调用方错误传播语义保留独立串行队列，不接入通用 `SerializedSaveQueue`。
- `KnowledgeRepository` 可跳过列表内单条损坏记录；顶层集合字段缺失或 `null` 可视为空，但存在且不是列表时必须失败，禁止把结构损坏误判为空数据后由 `load()` 规范化回写。
- 类别 alias 全局唯一且符合模型正则；内置专有名词库和类别固定 ID、不可删除。完整加载或替换后的 alias 冲突、跨库引用和悬空子记录继续由 Provider 确定性规范化。
- 知识页支持库、类别和条目的自定义顺序。`ReorderableListView` 的删除前插入槽位必须在 Page 边界转换成 Provider 使用的删除后目标索引；搜索、过滤或派生排序时不得允许条目拖拽。
- 解释生成和自动保存必须防止晚到结果覆盖用户后续编辑。页面生成期间按条目去重并在写入前复核条目、类别、来源和原解释快照；释义弹窗保存期间禁止切换类别，类别被停用或删除时在当前保存终态后再切换。
- 来源只允许打开和保存 `http`/`https` URL；复制来源时保留完整 URL，而显示层可仅展示 host。知识条目、解释和来源正文继续使用共享 `MarkdownWithLatex`，不要另建 Markdown 渲染路径。

## MCP

- 当前只实现 initialize/initialized、分页 `tools/list`、`tools/call`、`notifications/tools/list_changed` 和取消通知；不要宣称 resources、prompts、sampling、roots、elicitation、OAuth 或完整 MCP 已实现。
- Streamable HTTP 默认要求 HTTPS 和公网；HTTP 或私网必须分别显式允许。禁止 URL 凭据和跨 origin 转发敏感 header，并在请求及重定向前执行 host/DNS 校验。
- stdio 只在 Linux、macOS、Windows 可用，使用 `Process.start(..., runInShell: false)`、显式参数和隔离环境；Android、iOS、Web 不得展示为可用。
- MCP credential value 只进入 `SecretStore`。Drift 仅保存公开 transport、URL/command、参数、环境变量名和启用状态；Secret 不得进入日志、备份或同步。
- MCP 工具进入共享 `AgentToolRegistry`，连接、刷新、禁用或断开时只移除自己持有的 registration，并防止旧连接竞态重新发布工具。

## 文档

- Agent loop、取消、上下文、hooks、run graph 或工具注册变化更新 `doc/agent-runtime.md`。
- MCP transport、协议范围、凭据、平台门控或设置页变化更新 `doc/mcp.md`。
- 知识模型、Provider/Repository 语义、知识页用户路径或 `knowledge_search` 行为变化分别同步检查 `doc/models.md`、`doc/providers.md`、`doc/services.md`、`doc/pages.md` 和 `doc/agent-runtime.md`。
- 对话页 Agent 按钮可用性、Agent Plan 面板、工具轮数上限 UI 或“继续处理”路径变化更新 `doc/pages.md`。
- canonical relay tool/reasoning/SSE 变化同步更新 `doc/protocol-v1.md` 和后端 README。
