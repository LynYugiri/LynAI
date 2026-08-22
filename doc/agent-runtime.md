# Agent Runtime

本文记录当前 Agent 平台的统一执行边界。它描述已实现行为，也明确仍有限制的基础设施。

## 统一入口

`AgentLoopRuntime` 已用于三条模型工具链：

| 调用方 | 模型适配 | 工具执行 |
|--------|----------|----------|
| `ChatPage` | `StreamChunkAgentAdapter` + `ApiService.sendStreamRequest()` | `ToolCallService.executeSequentialCompatibility()` |
| `FloatingChatSessionController` | 同上 | 同上，并按用户授权暴露屏幕上下文工具 |
| `run_subagent` | `StreamChunkAgentAdapter` + `ApiService.sendStreamRequest()` | 独立 `ToolCallService`，禁止递归 Subagent |

页面或 controller 只负责准备消息、模型和工具、订阅事件、显示草稿以及保存最终 Conversation。不得另写一套 tool continuation 或取消循环。

## 执行状态机

```text
start
  -> runStarted
  -> turnStarted
  -> model stream: textDelta / reasoningDelta / toolCalls
  -> turnCompleted
  -> 无 tool calls: completed
  -> 有 tool calls: assistant tool-call message
       -> toolStarted...
       -> tool result messages
       -> next turn
  -> 达到 maxToolRounds: 注入 final instruction，隐藏 tools，再执行一次最终 turn
```

每个 run 有稳定 `runId`，每个模型 turn 有新的 `turnId` 和递增 `turnIndex`。tool executor 收到同一个 `AgentTurnIdentity`，tool result 必须按 invocation ID 与本轮 call 对应。runtime 在写 assistant item、发出 tool 事件或执行副作用前拒绝空白、带首尾空格或重复的 invocation ID。runtime 将 assistant tool call 与 tool result 编码成标准消息，并把真实 reasoning 从后续上下文移除。每个 tool result 完成后 runtime 还会发出 `toolCompleted` 事件，供 UI 清除“正在调用工具”状态。

单次 run 的工具轮数上限来自 `ConversationSettings.maxToolRounds`（默认 24，范围 4-64）。达到上限时 runtime 注入 final instruction、隐藏 tools 并执行一次强制最终 turn；最终 turn 仍返回工具调用时不执行它们，并在完成结果上设置 `toolRoundLimitReached=true`。

达到 `maxToolRounds` 时，不会直接把最后一次工具结果当最终答复。runtime 增加 system 约束，设置 `forceFinalResponse=true`，调用方必须不再发送 tools。如果模型仍返回 tool calls，runtime 不执行它们，并在完成结果上设置 `toolRoundLimitReached=true`。

## 取消与终态

`AgentRunHandle.cancel()` 是幂等取消入口。取消 token 贯穿 context build、hooks、模型 stream 和工具 executor。

1. 模型流取消时订阅立即释放，晚到 chunk 不再 emit。
2. 工具执行通过 `Future.any` 与取消竞争；run 不等待不合作的晚到工具 future。
3. 取消后不追加 tool result、不启动下一 turn，只完成一个 `cancelled` result 和一个 `runCancelled` terminal event。
4. 工具 handler 仍必须主动观察 token；若底层外部操作本身不可取消，它可能在后台结束，但结果不能回到已取消 run。

模型订阅取消和 run persistence 终态写入都有固定收尾超时，失效的上游 stream 或存储实现不能无限阻塞 terminal result。`AgentRunResult.content` 仍表示最后一个完整 turn 的正文；`partialContent` 聚合所有已收到的 turn 正文，包括失败或取消时尚未完成的当前 turn。主聊天和悬浮聊天停止时保存 `partialContent` 与累计 reasoning，失败提示也基于该聚合内容渲染。
5. 模型异常或 stream failure 形成 `failed` result；普通工具异常应由工具层转换为对应 invocation 的 failure result，而不是破坏整个批次。

## 工具注册与 schema

`AgentToolRegistry` 保存 `AgentToolRegistration`，同名重新注册会生成新的 registration ID 和递增工具版本；任意注册表变化都会推进 registry version。

`snapshot()` 返回不可变 map。snapshot 可判断整个 registry 是否变化，也可判断某个 captured registration 是否仍为当前项。schema 在注册时由 `AgentJsonSchemaValidator` 校验，arguments 在调度执行前再次校验。支持的是项目定义的 JSON Schema 子集，包括基础 type/object/array、范围、pattern、enum/const 和 `anyOf`/`oneOf`/`allOf`/`not`；未知 keyword 被拒绝。

`AgentToolScheduler` 支持：

| 策略 | 语义 |
|------|------|
| `parallelSafe` | 在 `maxConcurrency` 内并行。 |
| `exclusive` | 等待既有任务结束，并阻塞后续任务。 |
| `keyed` | 同一 concurrency key 串行，不同 key 可并行；缺少 key 返回失败。 |

结果始终按 invocation 输入顺序返回，而不是完成顺序。当前 `ToolCallService` 兼容路径整体按顺序执行，并对单个 MCP 工具使用 `maxConcurrency: 1`，所以通用 scheduler 的并行能力尚未用于主聊天批次。

MCP 工具发给模型的 descriptor/schema 在 Run 开始时固定；执行时按 canonical name 查询实时 registry。server 在模型返回 tool call 前断开、禁用或刷新时，旧 schema 不会改写，但调用会 fail closed；它不会调用已释放连接，也不会悄悄绑定非 MCP 的同名 registration。插件和内置工具仍执行各自捕获的 handler。

Run 同时固定权限快照。后续模型 turn、Agent Lua 同步预检、异步插件函数执行和 Lua continuation 都沿用该快照，不重新读取全局设置。运行期间修改全局权限不能扩大或缩小进行中的 Run；模型来源 Agent Lua 缺少快照或取消令牌时继续 fail closed。插件函数还要通过插件自身的安装级授权，因此最终能力是 Run 权限与实时插件可用性的交集。

## 上下文预算

`AgentContextBuilder` 当前使用 JSON 字符数除以 `charactersPerToken` 估算 token，不调用具体模型 tokenizer。默认预算保留输出空间，并分别限制单个 tool result 与 compaction checkpoint。

构建过程会移除 reasoning 字段，只保留完整的 assistant tool-call/tool-result 配对，截断过大的 tool result，从新到旧选择可容纳单元，并尽量保留 system 消息。调用方提供 compactor 时，被丢弃消息可压缩为 bounded system checkpoint。

模型返回 context overflow 时，runtime 最多强制压缩重试一次；第二次 overflow 直接失败。`ApiService` 会把常见上下文超限错误包装为 `AgentContextOverflowException`，主对话、悬浮聊天和 Subagent 都通过类型判断触发这次重试。生产调用方现在注入了 `ModelContextCompactor`：它用当前 Chat 模型（关闭 thinking/tools）把被裁消息压缩为有界 checkpoint；compactor 失败、超时或返回空摘要时回退到现有截断策略，不使 run 失败。

上下文预算按模型生效值 `ModelConfig.effectiveContextWindow` 构造，来源优先级为用户本地覆盖 > 托管 `/relay/config` 下发 > 从模型 endpoint 拉取 > 默认 262144（`defaultAgentContextWindow`，256k）。估算仍是字符数近似，不是精确 tokenizer。

## Tool Result Sanitization Foundation

`AgentToolResultProcessor` 与 durable persistence 是独立依赖。`AgentLoopRuntime` 在 executor 返回后、任何 tool result 持久化或 model message 之前统一处理整批结果，并再次校验 invocation correlation。生产组合根单独提供 storage_v2-backed `SanitizingAgentToolResultProcessor`，主聊天、悬浮聊天和 Subagent 都显式注入；因此无 persistence 的运行也可以安全清洗，而只注入 persistence 不会隐式改变工具结果。executor 只返回原始终态结果，避免重复处理。

服务递归规范化任意值，限制 JSON 深度、总 entry、单字符串字符数、inline JSON 字节数和 offload 字节数；非有限数字、循环和不支持的运行时对象会转换为 JSON-safe 标记。凭证式字段按 key 删除，Unix、Windows drive 和 UNC 绝对路径在 inline 内容、preview 和落盘文本中替换。小 JSON 保持 inline；大文本、`Uint8List`、可信 byte list 和有界可验证 base64 通过 storage_v2 私有 Resource/Blob 保存，并只返回 preview 与 `{id, mimeType, size, role}`，不返回 path、hash 或原始 base64。

offload role 固定为 `agent_tool_result_local`。该 role 不在 cloud/LAN 的 roamable resource allowlist 中，且普通备份只收集被选中业务资产引用的资源，因此结果资源保持 local-only。内容按 SHA-256 Blob 去重；取消或失败时 sanitizer best-effort 删除本次新建的 row，并在没有其他引用时清理 Blob。底层不可取消写入仍可能完成后再进入清理阶段。

## Lifecycle Hooks

支持 `beforeModelRequest`、`afterModelResponse`、`beforeToolCall`、`afterToolCall`、`beforeCompaction`、`afterRun`。hooks 是观测回调：

1. 默认超时 2 秒。
2. 普通异常与超时被隔离，不使 run 失败。
3. 取消可中断 run 内 hook；`afterRun` 即使 run 已取消仍 best-effort 调用。
4. hook context 是只读数据，没有返回值，不能改写请求、工具参数或结果。
5. 当前产品调用方没有安装 lifecycle hooks；持久化由 runtime 的独立 persistence lifecycle 完成，hooks 仍不是 telemetry 或审计扩展已启用的承诺。

## Durable Run Graph

Drift 提供 `runs`、`turns`、`items`、`tool_calls`、`snapshots`，由 `AgentPersistenceRepository` 管理。父子关系分别为 run -> turn -> item -> tool call，snapshot 可关联 run 和可选 turn。

新 run 必须是 `queued`，新 turn/item/tool call 必须是 `pending`。Repository 只允许定义好的前向迁移，并把 expected old status 放进 SQL `WHERE` 做 compare-and-set；陈旧 writer 返回 false，非法反向迁移直接抛错。终态写入 `completed_at`，tool call 可同时写 result。

启动在 Provider 加载前执行 `reconcileAfterRestart()`。只要 run graph 中任一层仍是 active 状态，整个相关图的未完成节点和 run 会在一个事务内标记为 `failed/interrupted`；不会创建 snapshot，也不会恢复模型 stream、重放 tool call 或自动继续。

这些表严格本机：不生成 sync Outbox，不进入普通或加密备份，也没有后端 API。主对话、悬浮聊天和 Subagent 会在模型执行前创建 run，逐 turn 写入 assistant item，并在工具副作用前写入 tool call，随后记录终态结果和 run 终态。聚焦测试可不注入 persistence lifecycle，因此该图仍不是所有直接构造 runtime 的完整审计日志；它也不保存用户输入的完整消息快照。Subagent 父子关系因 schema 没有 parent run 列而写入 `parent_run` snapshot metadata。

## 验证

Agent Runtime 改动至少运行：

```bash
flutter test test/services/agent_cancellation_test.dart
flutter test test/services/agent_context_builder_test.dart
flutter test test/services/agent_json_schema_test.dart
flutter test test/services/agent_lifecycle_hooks_test.dart
flutter test test/services/agent_loop_runtime_test.dart
flutter test test/services/agent_tool_registry_test.dart
flutter test test/services/agent_tool_scheduler_test.dart
flutter test test/agent_persistence_repository_test.dart
flutter test test/storage_v2_agent_schema_test.dart
flutter test test/agent_persistence_exclusion_test.dart
flutter test test/agent_tool_result_sanitizer_test.dart
```

修改 Drift table 或注解时先运行 `dart run build_runner build --delete-conflicting-outputs`，不得手改 `lib/services/storage_v2_database.g.dart`。随后执行完整 `flutter analyze --no-pub` 和 `flutter test --no-pub`。
## Permission Policy Snapshot

Every durable Agent run is created together with exactly one insert-only
`permission_policy` snapshot. Run and policy insertion share one SQLite
transaction, and a partial unique index enforces one policy per run. A child run
with `parentRunId` inherits the stored parent policy instead of consulting
current global settings. The separate `parent_run` snapshot remains the source
of parent run, turn, and tool-call correlation metadata.

Permission checks can consume an immutable `AgentPermissionSnapshot`; when it
is supplied it takes precedence over mutable application settings.
# Production Tool Snapshot

- Main chat, floating chat, and Subagent compose model-visible built-in, Agent, plugin, and MCP tools into one immutable run snapshot before the first model turn.
- Exposure and dispatch both use the conversation `AgentPermissionSnapshot`; denied tools are omitted and execution rechecks the captured requirements.
- Tool-call batches execute through `AgentToolExecutionService` and `AgentToolScheduler`. `ToolCallService.executeSequentialCompatibility` remains only for legacy tests/adapters and has no production caller.
- Tool results are sanitized before they enter durable tool-call rows or model continuation messages. Large or binary values are offloaded to local-only resources.
- Subagents receive a filtered child snapshot, inherit the parent cancellation token, cannot expose `ask_user`, and cannot recurse beyond the configured depth policy. Parent cancellation prevents late memory or trace merges.
- The public foundation catalog contains `ask_user`, `web_search`, `knowledge_search`, `read_attachment`, and `resource`, with optional tools omitted when their service/provider is not injected. `web_search` is registered only when at least one candidate adapter reports `isConfigured()`: client adapters require their local provider configuration, while the backend adapter requires an access token and a cached `webSearch` capability advertised by authenticated `/sync/status`. Capability refresh is independent of device enrollment, is repeated during normal sync, and is reset before account/backend scope transitions; absent or invalid capability data fails closed. The system prompt is built with the same configuration flag: unconfigured `web_search` is not named as an available tool, and the prompt only suggests the always-available `web_fetch` for reading known URLs or search-engine result pages; when configured, the prompt may direct retrieval through `web_search` with `web_fetch` for specific URLs. `knowledge_search` is registered only when `KnowledgeProvider` is available, requires `storage.read`, and searches immutable snapshots of enabled local knowledge bases, categories, and entries with bounded arguments, per-entry scan text, and results. Its batched scan cooperatively checks cancellation and the tool deadline between event-loop yields. `resource.operation` is one of `metadata`, `search`, `read`, or `recognize`; execution performs cross-field validation before dispatch. Attachment and resource metadata/search/read/recognition are restricted to resources referenced by the active conversation, so an ID from another conversation resolves as not found.
## Tool Security Boundaries

- Model-visible plugin tools use `AgentToolNameCodec` canonical names scoped by plugin ID. A run snapshot captures the plugin, raw handler name, and validated schema together; later manifest refreshes do not retarget an in-flight run. Canonical-name collisions fail registration explicitly.
- Production snapshot handlers call concrete built-in, LynAI function, plugin, or captured external handlers directly. They do not re-enter `ToolCallService.execute`, rediscover a plugin by raw model name, or re-snapshot an external registry.
- Model-reachable LynAI function calls require an explicit caller identity. Only explicit trusted host code may use `LynAICallerType.system`; missing or assistant identity fails permission checks closed. Non-Agent runs call native tools with `LynAICallerType.assistantTool`, which is evaluated against the captured conversation permission snapshot just like an Agent call — it is not a blanket rejection.
- Delete policy is semantic: all model-driven callers (Agent, `assistantTool`, and Lua) are rejected before mutation for delete functions, note page/folder and todo-item `delete=true`, and todo replacement lists that omit existing item IDs. This covers `tasks.delete`, `taskLists.delete`, `todos.deleteList`, `notes.delete`, `calendar.delete`, `anniversaries.delete`, `schedules.delete`, `plugin.file.delete`, `recycleBin.deleteForever`, and `plugin.restore`.
- `save_plugin_skill` requires the dedicated `plugins.skills.files:write` permission rather than notes or broad file-write permission.
- `http.fetch` and `web_fetch` use `BoundedOutboundHttpClient`, including destination and redirect revalidation, URL credential rejection, public-network defaults, request/streamed-response byte limits, timeout, and active cancellation.
All main chat, floating chat and Subagent `AgentLoopRuntime` handles are registered with the active physical-dataset barrier. A dataset switch cancels these runs and awaits their terminal result before changing storage, and no new dataset-bound run is admitted until reload and platform projection finish.

## 随记工具

`ToolCallService` 在注入 `JottingProvider` 且权限允许时注册三个随记工具：

- `search_jottings`：按 `query`/`tags`/`date_from`/`date_to`/`limit` 检索随记，返回 id、时间、标签和内容摘要；至少需要 query、tags 或日期范围之一。执行中分批检查取消与 deadline。
- `read_jotting`：按 id 读取单条随记全文。
- `save_jotting`：为用户新建一条随记，只新增不修改已有内容，内容上限 50000 字符。

权限：`search_jottings`/`read_jotting` 需要 `jottings:read`，`save_jotting` 需要 `jottings:write`，两者均加入默认 Agent 权限。
