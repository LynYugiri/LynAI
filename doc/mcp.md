# MCP

LynAI 当前实现 MCP 客户端的工具子集，把用户配置 server 暴露的 tools 接入统一 Agent 工具注册表。MCP 不经过 LynAI 后端，也不属于云/LAN 同步协议。

## 支持范围

客户端发送协议版本 `2025-06-18`，当前支持：

| 方法或通知 | 行为 |
|------------|------|
| `initialize` | 发送空 capabilities 与 LynAI client info，接受 server 返回的非空 protocolVersion。 |
| `notifications/initialized` | initialize 成功后发送。 |
| `tools/list` | 支持 `nextCursor` 分页、重复 cursor 检测和最大页数。 |
| `tools/call` | 发送 name 与 object arguments，解析 content、structuredContent、isError。 |
| `notifications/tools/list_changed` | 触发重新拉取和注册工具。 |
| `notifications/cancelled` | 本地请求取消或超时后 best-effort 通知 server。 |

当前不支持 resources、prompts、sampling、roots、elicitation、logging 配置、completion、OAuth discovery/authorization、server-initiated requests 或完整 capabilities 使用。initialize 只要求 server 返回 protocolVersion，没有严格验证协商版本等于客户端版本。

## Transport

### Streamable HTTP

HTTP transport 可用于所有具备 HTTP client 的平台。

1. endpoint 默认必须使用 HTTPS，且不能包含 userinfo。
2. HTTP 与私网访问是两个独立的显式开关。
3. POST 接受 JSON response、SSE response、202 或 204；取得 `MCP-Session-Id` 后可启动 GET SSE 通知流。
4. 每次请求及每个重定向 hop 独立解析并校验 DNS；原生 transport 直接连接该次批准的 IP，同时保留原始 Host、TLS SNI 和证书 hostname 校验。最多跟随三次重定向；POST 只允许 307/308。重定向后不再附带 credentials 或 session ID，避免跨 origin 泄漏。
5. 单条 JSON-RPC message、单个 SSE event 和 POST 总响应有独立字节限制。通知 SSE 是长连接，不使用 POST 总响应上限，但每个 event 仍受 message limit。
6. client 在开始 POST 前注册调用取消和 request timeout。取消或超时会终止该次 POST send/response stream；原生 HTTP 为每次请求使用独立 client，因此不会关闭其他并发请求。`notifications/cancelled` 只做独立、限时的 best-effort 发送，不阻塞本地终态。
7. dispose 时若有 session ID，会 best-effort DELETE endpoint。

私网判断同时覆盖字面 host 和解析后的全部地址。HTTP 或私网仍必须由用户分别显式允许；即使允许私网，每个原生连接也只使用该次解析批准的地址，重定向不会复用上一跳的 pin。Web 平台执行相同的 scheme、host 和 DNS 策略校验，但浏览器 transport 不提供指定连接 IP 的能力。

### stdio

stdio 只在 Linux、macOS、Windows 支持。transport 启动指定 command/arguments，使用逐行 UTF-8 JSON-RPC；credential values 作为显式 environment 注入。Android、iOS 和 Web 使用 stub，设置页禁用 stdio。

当前配置模型包含可选 working directory，但 `AgentMcpServerRecord` 和设置页没有持久化/编辑该字段，默认连接不会设置工作目录。

## 工具桥接

`McpProvider` 初始化 client 后分页读取 tools，并注册到全局 `AgentToolRegistry`。Provider 与独立 `McpToolSource` 共用 `AgentToolNameCodec`，以 source、server ID 和远端 tool name 的长度前缀 identity 生成稳定 canonical name。短 identity 使用 `tool_v1_<base64url>`，超长 identity 使用有界 SHA-256 名称；最终名称不超过 64 字符，并避免 server/tool 边界、`.`、字面 `_2e_` 和 Unicode 转义碰撞。

```text
tool_v1_<canonical identity>
```

工具 descriptor 来源为 `mcp`，副作用为 `external`，并发策略当前固定为 `parallelSafe`。

远端 `inputSchema` 由共享 importer 按原样交给 `AgentJsonSchemaValidator` 检查，不删除 keyword、不补默认约束。支持子集内的 schema 原样进入 registry；未知 keyword、非法 pattern、错误类型或其他不兼容约束会显式拒绝。Provider 保留发现到的 tool 并在 server error 中说明该 tool 未注册，其他兼容 tool 仍可用；独立 `McpToolSource` 拒绝该次 refresh，并保留 refresh 前持有的 registrations。MCP `isError=true` 被转换为工具执行失败，成功结果把 content、structuredContent 和 isError 一并返回模型。

Provider 只移除自己仍持有的 registration ID，避免断连误删同名替换项。连接或工具刷新发现名称碰撞时不会覆盖已有工具。每次 Agent Run 由 `ToolCallService.createRunSnapshot()` 捕获 MCP descriptor、handler、并发语义和权限；模型 schema 与工具执行都绑定到该不可变 Run snapshot。后续断连或 refresh 只影响新 Run，不会让旧调用改绑到新 handler；运行时仍会把取消令牌传入已捕获 handler，并忽略取消后晚到的远端结果。

## 持久化与 SecretStore

| 数据 | 存储位置 |
|------|----------|
| server ID、名称、transport、URL/command、arguments、credential 名称、enabled | Drift `mcp_servers` |
| allowHttp、allowPrivateNetwork、enabledTools、credentialTargets | `SecretStore` preferences JSON |
| credential/header/environment values | `SecretStore` 独立 key |
| 连接状态、错误、发现的 tools、client/session | 仅内存 |

`AgentPersistenceRepository` 拒绝带 URL credentials、query 或 fragment 的 server URL，校验环境变量名，并拒绝疑似 secret assignment 或 secret command argument。公开 row 只保存 secret 名称引用。MCP 配置、preferences 和 credentials 都不进入备份、云同步或 LAN 同步；`mcp_servers` 也不会生成 Outbox。

当前 preferences 与 credentials 共用 `SecretStore`，因此逐工具开关和 HTTP/私网许可也被视为设备私有配置。server row 目前没有 delete API；编辑时移除的 credential 名称会删除对应 secret。

## 页面与生命周期

设置页可添加或编辑 server、启用/禁用、连接测试和逐工具开关。应用启动加载 MCP 配置，enabled server 异步连接。Provider dispose 会触发异步断开全部连接；这不是后台 daemon，应用退出后 stdio 子进程和 HTTP session 不应被视为继续运行。

当前没有指数退避自动重连、离线队列或 durable request resume。client/transport failure 会把 server 标记为 failed，用户可测试或重新连接。

## 验证

MCP 改动至少运行：

```bash
flutter test test/services/mcp/mcp_protocol_test.dart
flutter test test/services/mcp/mcp_client_test.dart
flutter test test/services/mcp/mcp_http_transport_test.dart
flutter test test/services/mcp/mcp_stdio_transport_test.dart
flutter test test/services/mcp/mcp_tool_source_test.dart
flutter test test/mcp_provider_test.dart
flutter test test/mcp_settings_page_test.dart
flutter test test/agent_persistence_repository_test.dart
```

涉及组合根或 ChatPage 工具暴露时还需运行相关 widget、工具调用和悬浮聊天测试，并执行完整 `flutter analyze --no-pub`、`flutter test --no-pub`。stdio 平台 wiring 变化必须在目标桌面平台验证进程启动、逐行 framing、环境注入和 dispose。
