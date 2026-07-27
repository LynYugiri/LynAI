# Agent Runtime

本文记录当前 Agent 平台的统一执行边界。它描述已实现行为，也明确仍有限制的基础设施。

## 统一入口

`AgentLoopRuntime` 已用于三条模型工具链：

| 调用方 | 模型适配 | 工具执行 |
|--------|----------|----------|
| `ChatPage` | `StreamChunkAgentAdapter` + `ApiService.sendStreamRequest()` | `ToolCallService.executeSequentialCompatibility()` |
| `FloatingChatSessionController` | 同上 | 同上，并按用户授权暴露屏幕上下文工具 |
| `run_subagent` | 非流式 `ChatResponse` 手工映射为 Agent stream event | 独立 `ToolCallService`，禁止递归 Subagent |

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

每个 run 有稳定 `runId`，每个模型 turn 有新的 `turnId` 和递增 `turnIndex`。tool executor 收到同一个 `AgentTurnIdentity`，tool result 必须按 invocation ID 与本轮 call 对应。runtime 将 assistant tool call 与 tool result 编码成标准消息，并把真实 reasoning 从后续上下文移除。

达到 `maxToolRounds` 时，不会直接把最后一次工具结果当最终答复。runtime 增加 system 约束，设置 `forceFinalResponse=true`，调用方必须不再发送 tools。如果模型仍返回 tool calls，runtime 不执行它们，并在完成结果上设置 `toolRoundLimitReached=true`。

## 取消与终态

`AgentRunHandle.cancel()` 是幂等取消入口。取消 token 贯穿 context build、hooks、模型 stream 和工具 executor。

1. 模型流取消时订阅立即释放，晚到 chunk 不再 emit。
2. 工具执行通过 `Future.any` 与取消竞争；run 不等待不合作的晚到工具 future。
3. 取消后不追加 tool result、不启动下一 turn，只完成一个 `cancelled` result 和一个 `runCancelled` terminal event。
4. 工具 handler 仍必须主动观察 token；若底层外部操作本身不可取消，它可能在后台结束，但结果不能回到已取消 run。
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

MCP 工具 schema 与 handler 在模型请求前取同一个 snapshot。server 在模型返回 tool call 前断开或刷新不会把旧调用绑定到新 handler；snapshot 中已经捕获的调用仍按原 registration 执行，新一轮模型请求才读取更新后的 registry。

## 上下文预算

`AgentContextBuilder` 当前使用 JSON 字符数除以 `charactersPerToken` 估算 token，不调用具体模型 tokenizer。默认预算保留输出空间，并分别限制单个 tool result 与 compaction checkpoint。

构建过程会移除 reasoning 字段，只保留完整的 assistant tool-call/tool-result 配对，截断过大的 tool result，从新到旧选择可容纳单元，并尽量保留 system 消息。调用方提供 compactor 时，被丢弃消息可压缩为 bounded system checkpoint。

模型返回 context overflow 时，runtime 最多强制压缩重试一次；第二次 overflow 直接失败。当前主对话、悬浮聊天和 Subagent 没有传入 compactor，也没有按具体模型配置调整预算，因此通常使用默认字符估算和裁剪，不应描述为精确 token 管理或持久化摘要系统。

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
```

修改 Drift table 或注解时先运行 `dart run build_runner build --delete-conflicting-outputs`，不得手改 `lib/services/storage_v2_database.g.dart`。随后执行完整 `flutter analyze --no-pub` 和 `flutter test --no-pub`。
