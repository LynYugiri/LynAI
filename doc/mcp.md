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
4. 最多跟随三次重定向；POST 只允许 307/308。重定向后不再附带 credentials 或 session ID，避免跨 origin 泄漏。
5. 单条 JSON-RPC message、单个 SSE event 和 POST 总响应有独立字节限制。通知 SSE 是长连接，不使用 POST 总响应上限，但每个 event 仍受 message limit。
6. dispose 时若有 session ID，会 best-effort DELETE endpoint。

当前私网判断覆盖字面 localhost、`.local`、常见 IPv4 私网/loopback/link-local 和部分 IPv6 前缀；它不是 DNS 解析后的完整 SSRF 防护。MCP endpoint 是用户本机配置的信任边界，文档不得等同于后端 relay 的解析后 IP 防护。

### stdio

stdio 只在 Linux、macOS、Windows 支持。transport 启动指定 command/arguments，使用逐行 UTF-8 JSON-RPC；credential values 作为显式 environment 注入。Android、iOS 和 Web 使用 stub，设置页禁用 stdio。

当前配置模型包含可选 working directory，但 `AgentMcpServerRecord` 和设置页没有持久化/编辑该字段，默认连接不会设置工作目录。

## 工具桥接

`McpProvider` 初始化 client 后分页读取 tools，并注册到全局 `AgentToolRegistry`。名称格式为：

```text
mcp_<encoded server id>_<encoded tool name>
```

非 ASCII 或名称外字符编码为带十六进制 code unit 的片段。工具 descriptor 来源为 `mcp`，副作用为 `external`，并发策略当前固定为 `parallelSafe`。

远端 `inputSchema` 会递归保留本地 validator 支持的 keyword，删除其他 keyword，并在缺失时补 `type: object` 与空 `properties`。这避免未知 keyword 阻止注册，但也可能弱化远端约束；执行前只按清理后的 schema 校验。MCP `isError=true` 被转换为工具执行失败，成功结果把 content、structuredContent 和 isError 一并返回模型。

Provider 只移除自己仍持有的 registration ID，避免断连误删同名替换项。连接或工具刷新发现名称碰撞时不会覆盖已有工具。主聊天模型请求使用 registry snapshot 生成 schema，但执行时 `ToolCallService` 当前重新读取实时 registry，因此断连或刷新可能让已返回的 tool call 失败。

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
