# 服务层、API 与工具调用

`lib/services/` 负责和外部世界交互：模型 API、工具调用、平台能力、备份文件、storage_v2 和存储升级。页面层只传入需要的上下文，服务层不持有 UI 状态。

## 安全基础

`SecretStore` 抽象敏感字符串存储；生产实现使用 `flutter_secure_storage`，测试使用内存实现。`ModelConfigRepository` 只把非秘密模型 JSON 和稳定 `apiKeySecretRef` 写入数据库，API key 按模型 ID 单独存入 `SecretStore`；首次加载旧版 plaintext `apiKey` 时先写安全存储，再重写数据库，迁移可重复且不会把 key 放入同步 outbox。`DeviceIdentityService` 在首次启动生成 Ed25519 密钥，并以完整公钥 SHA-256 的 52 字符小写、无填充 Base32 作为稳定 `deviceId`；后续启动会校验私钥、公钥和 ID 一致性，损坏时拒绝静默重建。`DeviceRegistrationService` 在真实后端恢复会话、登录或注册成功后，以绑定 challenge、认证用户/session、设备 ID、公钥、显示名称、平台和协议版本的 CBE1 消息完成幂等注册；成功 enrollment 按后端 origin、用户 ID 和 session ID 在进程内缓存，同一键的并发调用复用一个 in-flight Future，失败不会进入缓存。服务端明确返回 `unknown_device` 时会失效缓存并只重新 enrollment、重签一次；`revoked_device` 只失效缓存并返回错误，不会通过普通 enrollment 静默恢复。离线或旧后端不阻塞账号使用。账号 access/refresh token 也保存在 `SecretStore`，并按规范化完整 Base URL（含 path prefix）隔离；SharedPreferences 中只保留同作用域的用户和过期时间元数据。旧 origin-only 会话仅在当前 Base URL 没有 path prefix 时迁移，避免把同源不同路径的凭证错误归属。设备私钥不会写入 SharedPreferences、数据库或备份。

默认后端通过编译环境变量 `LYNAI_BACKEND_URL` 提供；未传入时保持未配置。UI 对所有 HTTP 后端显示明示风险，真实账号和生产数据必须使用可信 HTTPS 后端。

`BackendClient` 为 JSON POST/PUT/PATCH/DELETE、可重放字节请求和内存 multipart 上传提供统一 Bearer token、超时、401 刷新和重放。同步上传保留稳定 body bytes，但通过 `postReplayableBytes()` 在首次发送和 token refresh 后分别重建鉴权与设备签名头，避免使用旧 session 的签名重放。`RemoteCommunityService` 在 `/community` 下实现公开动态、评论、用户资料和媒体读取，以及登录后的发布、互动、收藏、资料修改和置顶操作。社区图片先上传为当前用户拥有的临时 media，再由帖子 JSON 中的有序 `mediaIds` 原子关联；客户端只渲染后端显式返回的媒体，社区 Markdown 会隐藏图片语法、危险 scheme 链接和原始 HTML 标签。

`OutboundNetworkPolicy` 和 `BoundedOutboundHttpClient` 是通用出站网络安全基础。默认只允许无 URL 凭据的 HTTPS 公网目标，请求和每次重定向前都重新检查 host 与 DNS 结果；`dart:io` transport 随后只连接该校验通过的地址列表，按 IPv4 优先、IPv6 次之逐个尝试（每地址 TCP 连接与 HTTPS 握手各 3 秒超时），同时仍使用原始 URI host 生成 HTTP Host，并由连接工厂在该直连 socket 上以原始 hostname 完成 TLS 握手（SNI 与证书校验）。每个 redirect hop 都重新解析、校验和 pin，不复用上一跳地址。HTTP 或私网只能由可信应用配置显式开启。通用客户端限制请求/响应字节数、超时和重定向次数，跨重定向删除 Authorization、proxy authorization 和 API-key header，并通过关闭请求专用 `http.Client` 主动取消进行中的连接。Web/stub 平台保留相同策略校验，但底层浏览器 transport 无法接收应用指定的连接 IP。`McpHttpTransport` 复用相同的 resolver 和 pinned native client factory，为每个请求及 redirect hop 创建独立 pin，同时保留 MCP 的 POST redirect、credential/session header、SSE、错误和大小限制行为。

`WebSearchService` 提供聊天工具使用的双模式搜索基础。模型只能传入规范化的 `WebSearchRequest`（query、1-10 结果数、可选语言和 `day`/`month`/`year` 时间范围），不能传 route、provider、endpoint、header 或 credential。production composition 每次执行从可信 `AppSettings` 读取 route 和客户端首选 provider：client 模式支持固定 HTTPS Tavily endpoint 和用户配置的 SearXNG endpoint；backend 模式使用当前 `BackendClient` 的固定 `/search/web` 路径；auto 模式按首选 client、其余已配置 client、LynAI backend 的顺序回退。主聊天、悬浮聊天和 Subagent 复用同一个 production service，Subagent 不能覆盖策略。客户端 provider 由本地配置判断；后端 provider 还要求当前 access token，并由登录远端激活时无需设备 enrollment 的只读 `/sync/status` 刷新所广告的 `webSearch` capability。正常云同步 status 也持续刷新该缓存，bind/unbind 或后端 scope 变化会先清空，未知、旧后端未广告或刷新失败均按不可用处理。`ToolCallService` 在没有任何候选可用时不注册 `web_search` 工具，系统提示词也不会把 `web_search` 列为可用工具，只会提示始终可用的 `web_fetch` 抓取搜索引擎结果页或已知 URL 检索；已配置时则提示优先使用 `web_search`，需要抓取特定 URL 正文时用 `web_fetch`。Tavily API key 和可选 SearXNG bearer token 只从 `SecretStore` 读取；Tavily 因 key 位于请求 body 而禁止重定向。SearXNG 使用 HTTP 时必须保存显式用户授权，该授权只加入当前配置 endpoint 的精确 origin；Bearer token 仅在此授权存在时可发往该明文 origin，任何 redirect 都不转发 bearer，且跳转到其他 HTTP origin 会被拒绝。异常不包含响应 body 或 secret。

同步服务只上传两个版本化配置投影：单例 `SharedSettingsV1` 和逐 Provider 的 `SyncedModelConfigV1`。前者不包含后端连接、登录/changelog、最近功能、悬浮助手、权限和本地路径；后者仅接受用户明确开启同步的非托管 Provider，并删除 API key、secure-store 引用、URL userinfo 及疑似凭证的嵌套参数。远端写入使用 storage_v2 的现有 Outbox/conflict 事务，存在本地 pending mutation 时不覆盖本地值。

`RemoteSyncService` 对上传和下载响应执行结构校验后才交给 Provider：上传要求 `latestSeq` 合法，ACK 数量与批次一致，并且只能是完整 legacy seq ACK 或不重复且精确覆盖请求 changeId 的 ACK；下载要求 changes 为列表、change 字段和 upsert `data.id` 合法、seq 从 since 起严格递增、changeId 页内不重复，且 `nextSince` 覆盖本页最大 seq。capabilities object 存在时，其已出现字段必须是 boolean；generation/indexRevision/minAvailableSeq 缺失、非法或分页不一致会失败关闭。`generation_mismatch`、`stale_cursor` 和 `future_cursor` 被解析为类型化异常，并严格要求对应 metadata。变更批次大小计算、签名和传输共用 canonical exact-byte encoder，change JSON 不发送本地 `deviceId`。Blob 下载通过 `BackendClient.getBounded()` 使用广告上限，并在安装和 cursor 提交前复验 SHA-256。格式异常不会推进游标或删除 Outbox。`postSignedJson()` 复用同一 enrollment、token refresh、稳定 body bytes 和 Ed25519 重签链路，供 purge 与 operation ACK 使用，管理签名逻辑不散落到页面或 Provider；`replay_conflict` 单独分类，不触发设备 enrollment 失效。

`RemoteCloudDataService` 实现 `/sync/index/status`、按分类 keyset 分页的 `/sync/index/objects`、对象详情、purge preview、签名 purge、pending operations 和签名 ACK。status/usage、对象页、详情 records、preview 和 operation 都严格解析，缺失、错误类型、非法枚举、空 ID、recordCount 不一致或 `data.id` 不匹配均失败关闭。所有对象分页和对象详情都绑定同一个 `expectedIndexRevision`，且响应 revision 必须相等；revision 冲突分类为可进行一次 status/reseed 重试的 projection race，不提交部分缓存。current-projection reseed 遍历固定 revision 下的对象列表与详情，storage 在一个事务中应用远端 upsert、absent-record 删除、pending mutation 保留和 generation/cursor 更新，不改写 blob 内容、transport head 或 physical dataset lineage。`CloudManagementCoordinator` 是 UI 与普通同步共享的窄服务边界，负责 operation 发现、repository 对账、reseed 标记和确定性 ACK，不依赖任一 Provider。管理 API 不实现 Blob 物理 GC。

## ApiService

文件：`lib/services/api_service.dart`

`ApiService` 负责 Chat、流式 Chat、图片 OCR、语音转文字、图片生成、附件内容转换、thinking/reasoning 提取和 tool calls 解析。

### 标准化数据

| 类型 | 说明 |
|------|------|
| `ChatFileInput` | 发送前的附件字节、MIME 和文件名。 |
| `StreamChunk` | 流式增量，包含正文、思考内容、工具调用和结束信号。 |
| `ChatResponse` | 非流式回复，包含正文、思考内容和工具调用。 |

不同协议的请求和返回差异在 `ApiService` 内部消化。页面只处理标准化类型。

OpenAI 兼容和 Anthropic 流使用共享 `SseDecoder`，按空行分隔完整事件，支持任意网络 chunk 边界、LF/CRLF/CR、注释行、`event:` 字段和多行 `data:` 拼接。解析器只把完整 event 的 data 交给协议层，不再假设一行就是一个网络 chunk；OpenAI、Anthropic、Ollama 的 JSON 顶层都必须是 object。畸形 SSE JSON、错误的 choices/delta/tool-call 形状、缺失或非法 tool ID、非 object arguments，以及完成标记前 EOF 都会失败，不再跳过或合成 ID。

`debugSse` 只输出 URI/model、状态码、事件数据长度、正文/思考长度、finish reason、tool 名称和参数数量等元数据。它不打印原始 SSE data、正文 preview、tool arguments、tool call ID、API error body 或非 2xx response body。

`managed=true` 的 LynAI 托管模型走独立 canonical 中转契约：endpoint 为 `BackendClient.backendUrl + '/relay'`，Chat 请求发送到 `/relay/chat`，OCR、语音转文字和图片生成分别使用无版本的 `/relay/ocr`、`/relay/transcribe`、`/relay/images/generations`。鉴权使用用户 JWT，路由字段只发送 `model`，不发送 `providerId` 或 `api_type`。普通 OpenAI/Anthropic/Ollama Provider 仍使用各自 direct 路径和用户填写的凭据；direct Vivo AppID 行为不变。

### 支持协议

| `apiType` | 用途 | 流式格式 |
|-----------|------|----------|
| `openai` | OpenAI 兼容 Chat Completions。 | SSE `data:`。 |
| `custom` | 自定义 OpenAI 兼容接口。 | SSE `data:`。 |
| `ollama` | Ollama `/api/chat`。 | 逐行 JSON。 |
| `anthropic` | Anthropic Messages API。 | SSE `data:`。 |
| `openai_image` | OpenAI Images。 | 非流式 JSON。 |
| `vivo_image` | vivo 图片生成。 | 非流式 JSON。 |

### 请求体约定

| 协议 | 行为 |
|------|------|
| OpenAI 兼容 | 发送 `model`、`messages`、`stream`、`thinking`、采样参数；工具开启时发送 `tools` 和 `tool_choice`。 |
| Ollama | 发送 `model`、`messages`、`stream`、`think`；采样参数进入 `options`。 |
| Anthropic | system 消息提升到顶层 `system`，其余消息写入 `messages`，内容转 Anthropic block。 |
| Managed canonical | 发送 `model`、canonical `messages`、`stream`、`thinking`、采样参数和可选工具；响应统一为 `content`、`reasoning`、`toolCalls`，SSE 增量使用同名字段和 `done`。 |

OpenAI 兼容请求会显式发送 thinking 开关。部分已配置后端依赖 disabled 标记，不要随意删除。

Direct Provider 的 `extraParams` 会合并到请求体，但不会覆盖代码已经设置的核心字段，例如 `model`、`messages`、`stream`，并把 `maxTokens` -> `max_tokens`、`topP` -> `top_p` 等名称规范化。Managed canonical 请求不透传 `extraParams`；客户端只从 active 子模型发送标准 `maxTokens`、`temperature`、`topP`，其余 advanced defaults 由后端模型处理。Vivo LASR 由 active speech 子模型的 `workflow=vivo_lasr` 选择现有 `/relay/speech/*` 流程。

### 附件转换

| 接口能力 | 图片 | 非图片文件 |
|----------|------|------------|
| 支持多模态 | 转成协议要求的 image content。 | 尽量转为文本上下文；部分链路可使用 input file 风格内容。 |
| 不支持多模态 | 文件名、MIME、大小和文本/base64 摘要。 | 文件名、MIME、大小和文本/base64 摘要。 |

OCR 和文件识别是发送前处理。处理结果会替换历史附件并标注来源（`[文件: name (size, mime)]` 仅用于仍作为原始多模态输入发送的附件；`[图片 OCR 识别结果（来源: ...，可能含识别误差）]\n<text>`、`[文件识别结果（来源: ...，可能含识别误差）]\n<text>`、`[文件内容: name]\n<text>` 分别用于 OCR 图片、文件识别、纯文本附件），让模型清楚读出的是识别输出而非原始字节内容并知悉可能存在误差。托管 OCR API 走 `/relay/ocr`；使用 Chat/视觉模型识别文件时走 canonical `/relay/chat`。历史会话持久化的 `Message.content` 仍是用户原文，仅 API 调用时构造的覆盖内容包含上述标注。模型主动调用 `model.ocr` / `model.recognizeFile` 的结果以 tool result 形式返回，不进入用户消息正文故无需标注。

`AgentResourceService` 提供按稳定 resource ID 的受限元数据、文本、OCR/文件识别和资源搜索基础；`AttachmentReadService` 再把稳定 conversation ID、message ID 与 attachment index 解析为 resource ID。两者都不接受调用方路径，不返回路径、hash 或 base64，只允许消息附件/图片 role，并执行 MIME、字节和字符上限。资源搜索暂时复用现有 `loadResources()` 快照并限制扫描与返回数量；数据库尚无索引搜索 API，后续资源规模需要时再增加专用查询。

`AgentToolResultSanitizer` 是 runtime-level 工具结果安全与 Resource offload 边界。`AgentToolExecutionService` 负责 schema 校验、捕获权限授权和调度；独立注入 `AgentLoopRuntime` 的 `SanitizingAgentToolResultProcessor` 在 executor 返回后统一处理所有非取消终态。`sanitize(result, cancellationToken:)` 返回 `AgentToolResultSanitization`，其中 `value` 是唯一可进入持久化和模型上下文的 bounded JSON-safe 值，`resources` 是安全元数据。`AgentToolResultResourceStore` 是存储抽象；`AgentToolResultSanitizer.storageV2(storage)` 使用现有 SHA-addressed Resource/Blob，并写入 local-only `agent_tool_result_local` role。handler、页面和协议适配器不得再次传递原始结果，也不得从 Resource row 暴露 `originalPath`、`relativePath` 或 `sha256`。

对话页 OCR 支持两种引擎：云端 OCR API（如 vivo OCR，需网络和 API key）和本地 OCR（ncnn + PPOCRv5，离线免费，仅 Android）。在对话设置的 OCR 模型列表中，Android 端会显示"本地 OCR (PPOCRv5)"虚拟条目，选中后 `imageModelId` 存为 `ModelConfig.localOcrId` sentinel，OCR 路径自动分发到本地推理。`model.ocr` 函数同样支持该 sentinel，Agent Lua 调用时自动走本地路径。

### 流式错误处理

| 场景 | 行为 |
|------|------|
| 建立连接超时 | 抛出中文异常。 |
| 非 200 响应 | 抛出包含状态码和响应体的异常。 |
| OpenAI SSE `error` | 转成异常进入 ChatPage 失败路径。 |
| Anthropic `type:error` | 转成异常进入失败路径。 |
| 单个坏 chunk | 跳过该 chunk，保留已收到正文。 |
| 工具参数不是 JSON 对象 | 作为协议错误终止该次请求。 |

## ToolCallService

文件：`lib/services/tool_call_service.dart`

`ToolCallService` 把模型请求转成本地动作。生产聊天和 Agent 只接受接口原生 tool calls，不提供非原生 JSON fallback。Run 开始时捕获 immutable model schema/permission snapshot；执行由 `AgentToolExecutionService` 完成 schema 校验、授权和调度，独立注入的 `AgentToolResultProcessor` 负责终态 sanitizer。插件的自定义工具由已捕获 handler 转交给 `PluginLuaRuntimeService` 在 Lua 沙箱中执行；MCP schema 固定但执行查询实时 registry 并在不可用时 fail closed。Run 的身份在首次创建 snapshot 时按该对话的 Agent 模式固定（`runAgentEnabled`），run 中途切换对话 Agent 模式不改变已捕获 snapshot 的身份与权限；非 Agent run 调用原生工具使用 `LynAICallerType.assistantTool`，仍按对话快照域评估权限而不是一律拒绝。`web_search` 仅在 `WebSearchService.isConfigured()` 为真时注册；未配置时不会进入工具列表，系统提示词也不会把它列为可用工具，只会提示始终可用的 `web_fetch` 兜底。`knowledge_search` 仅在注入 `KnowledgeProvider` 时注册，并要求 `storage.read`。检索会先捕获 Provider 列表快照，随后分批扫描并在批次间检查取消和 deadline、让出事件循环；每条正文只扫描有界前缀。

模型多轮控制不再由页面或 `ToolCallService` 自己维护。主对话、悬浮聊天和 Subagent 都由 `AgentLoopRuntime` 驱动；`ToolCallService.executeSequentialCompatibility()` 是具体工具执行适配器，并通过 `AgentToolScheduler(maxConcurrency: 1)` 调用 MCP 等外部 registry 工具。统一运行时、上下文和取消边界见 [Agent Runtime](agent-runtime.md)。

### 工具清单

| 工具 | 副作用 |
|------|--------|
| `get_current_time` | 无，返回当前时间和时区。 |
| `get_current_screen` | 只读。仅在悬浮聊天且用户授权当前页面上下文时暴露，读取 Android 前台页面文本和节点摘要。 |
| `web_fetch` | 发起只读 GET 请求，读取 http/https URL 的响应正文并按长度限制返回。 |
| `knowledge_search` | 只读检索已启用的本地知识库、类别和条目；标题命中优先，最多返回 10 条，参数、正文扫描前缀及 preview/content 均有长度上限，并支持协作取消。 |
| `get_location` | Android 请求定位权限并返回位置。 |
| `open_app` | Android 打开指定包名应用。 |
| `list_tasks` | 只读，列出规范 `Task`，可按文本、完成状态和清单过滤。 |
| `create_task` / `update_task` / `delete_task` | 写入 `TaskProvider`；日期为 `YYYY-MM-DD`，时间为 `HH:mm`。 |
| `list_calendar_events` | 只读，列出规范 `CalendarEvent`。 |
| `create_calendar_event` / `update_calendar_event` / `delete_calendar_event` | 写入 `CalendarProvider`；全天事件使用半开日期区间，定时事件使用 ISO-8601 `start`/`end`。 |
| `list_anniversaries` | 只读，列出规范 `Anniversary`。 |
| `create_anniversary` / `update_anniversary` / `delete_anniversary` | 写入 `CalendarProvider`，支持一次性日期或每年重复月日。 |
| `list_notes` | 只读。 |
| `read_note` | 只读。 |
| `save_note` | 创建、覆盖或追加笔记。 |
| `edit_note` | 对笔记执行直接行级编辑。 |
| `propose_note_edit` | 生成待用户确认的笔记修改建议。 |
| `list_note_pages` | 只读，列出笔记分页。 |
| `save_note_page` | 创建、覆盖、追加或移动笔记分页。 |
| `list_note_folders` | 只读，列出笔记文件夹。 |
| `save_note_folder` | 创建或更新笔记文件夹。 |
| `list_schedules` / `create_schedule` / `update_schedule` | 旧 schedule 工具别名，兼容输入后转写规范任务或日历事件。新提示和新调用应使用 canonical 工具。 |
| `list_task_lists` / `create_task_list` / `update_task_list` / `delete_task_list` | 规范任务清单 CRUD；删除清单只移除归属并保留任务。内部函数前缀为 `taskLists.*`。 |

规范任务、日历事件和纪念日的 create/update 工具共用 `reminders` wire schema：提醒包含可选 `id`、实体对应的 `anchor`、有符号 `offsetMinutes` 和可选 `HH:mm` `dateOnlyTime`。创建或替换列表时缺失的提醒 ID 自动生成；update 省略 `reminders` 保留原列表，显式传入数组则整体替换，空数组清空。list/create/update 结果都会返回提醒 JSON。旧 `list_schedules` 对任务计划时间和事件都采用 `[from, to)` 过滤；旧 `update_schedule` 可在任务与事件之间保留 ID 转换，并先持久化目标后移除来源。
| `list_todo_lists` / `read_todo_list` / `save_todo_list` / `save_todo_item` | 旧 todo 工具别名，以旧形状读写 `TaskProvider`。仅在用户明确操作旧清单契约时使用。 |
| `generate_image` | 调用当前对话的图片生成模型，保存图片并追加到 assistant 消息。 |

工具返回统一结构：成功为 `{ok: true, ...}`，失败为 `{ok: false, error: ...}`。这样模型可以继续解释错误，而不是让对话直接中断。

### Agent 模型函数

| 函数 | 说明 |
|------|------|
| `model.chat` | 调用已配置 Chat 模型执行 Agent 内部推理。 |
| `model.ocr` | 调用已配置 OCR 模型识别图片文字。当 `imageModelId` 为 `localOcrId` sentinel 时走本地 PPOCRv5 推理（仅 Android）。 |
| `model.recognizeFile` | 调用已配置视觉 Chat 模型识别图片或文件内容。 |
| `model.generateImage` | 调用已配置图片生成模型，保存生成结果并返回附件元数据。 |
| `agent.memory.read` | Agent Lua 读取当前对话共享工作记忆。 |
| `agent.memory.update` | Agent Lua 更新当前对话共享工作记忆。 |

Agent Lua 可以通过 `lynai.call()` 调用这些函数，也可以用 `lynai.device.*` 便捷接口编排手机自动化。Lua 源码不做固定长度截断，`lynai.call` 不做固定次数硬限制；设备任务依赖悬浮层和 `DeviceRunController` 的暂停/停止机制中断。手机复杂操作优先使用 `lynai.device.query`、`lynai.device.waitAndClick`、`lynai.device.inputInto`、`lynai.device.scrollUntil` 或底层 `device.screen.query` 查找任务相关节点；确实需要完整结构时再读取 `device.screen.snapshot`。消息应用和 QQ 上下文优先通过 `device.screen.extractMessages` 从无障碍节点读取可见文本，无法读取图片、语音或自绘内容时再调用 `device.screen.screenshot`。截图 base64 只能作为 `model.ocr` 或 `model.recognizeFile` 的输入，回传模型的 tool result 会剥离二进制字段，只保留 OCR/识图文本和截图元数据。

模型来源的 Agent Lua 必须携带不可变 Run 权限快照和取消令牌。同步 `lynai.call()` 预检、异步 command、插件函数调用及 continuation 都使用同一快照；运行期间修改全局新对话默认权限不能扩大或缩小该 Run。调用插件函数还必须同时满足插件安装级启用、插件自身授权和逐函数开关，任一层拒绝都不能执行插件副作用。

### 工具调用策略

1. OpenAI 兼容协议在子模型 `supportsTools=true` 且未通过 `extraParams.disableTools=true` 禁用时使用原生 `tools`。
2. 不支持原生 tools 的协议不暴露生产工具能力，不从 assistant 正文解析 JSON 调用。
3. 启用工具时会注入当前本地时间、时区和 `timezoneOffsetMinutes`。
4. 规范任务使用 `LocalDate`/`LocalTime` 字符串；定时日历事件解析 ISO-8601 并由事件规格保存真实开始/结束，全天事件保持 `[startDate, endDateExclusive)`。
5. 发给模型的 assistant 消息始终带 `reasoning_content: ""`，真实 thinking 只用于 UI/历史展示，不再回传进工具轮次上下文。
6. `generate_image` 只在当前对话开启图片生成时暴露，并追加在 tools 列表末尾。
7. `get_current_screen` 只由悬浮聊天会话显式开启，执行层会再次校验授权，避免未暴露调用绕过工具目录。
8. Agent 模式提供 `read_agent_memory` 和 `update_agent_memory`，用于主 Agent、Subagent 和 Lua 共享当前对话的持久化工作记忆。
9. Agent 模式提供 `run_subagent`，用于把手机自动化、屏幕读取和 OCR/识图等高噪声子任务隔离到独立上下文，主对话只接收最终结构化结果。
10. 主对话和 Subagent 使用同一个 `ToolCallService.maxToolRounds` 上限。最后一轮工具结果后注入“直接给出最终回复”的约束；模型若仍请求工具，则停止执行并返回明确的轮数上限错误。

### 平台通道

| 通道 | 方法 | 平台 | 说明 |
|------|------|------|------|
| `lynai/native_tools` | `openApp` | Android | 按包名打开应用。 |
| `lynai/native_tools` | `queryApps` | Android | 列出已安装且可启动的应用，返回 `{packageName, label}`（按 label 排序，上限 500）；manifest 已声明 `QUERY_ALL_PACKAGES`。Agent 工具 `list_apps` 与 Lua `lynai.device.listApps` 均复用此通道，`open_app` 描述引导先查询包名。 |
| `lynai/native_tools` | `getLocation` | Android | 请求定位并读取最近位置。 |
| `lynai/native_tools` | `saveImageToGallery` | Android | 保存 PNG 到图库。 |
| `lynai/calendar_platform` | `syncProjection` | Android | 持久化版本化的任务/日历完整投影，重新安排非精确通知并刷新小组件；不会请求通知权限。 |
| `lynai/calendar_platform` | `requestNotificationPermission` | Android | 仅在用户明确保存并把任务、事件或纪念日从无提醒改为有提醒时请求通知权限；拒绝或调用失败不影响保存，不由加载或同步流程自动调用。 |
| `lynai/background_service` | start/stop | Android | 长时间生成时控制前台服务。 |
| `lynai/device_control` | snapshot/context/query/screenshot/ocr/tap/swipe/inputText/nodeAction | Android | 通过无障碍读取屏幕、筛选节点、截屏并执行手机操作。节点包含可见性、选中、勾选、长按和可用动作等元数据。`ocr` 使用 ncnn + PPOCRv5 离线识别截图中的文本及位置（支持 17+ 语言和竖排文字）。 |
| `lynai/floating_assistant` | showBubble/hideBubble/configure/updateChatState/updateTranslationState/updateAgentPlan | Android | 系统级悬浮助手。原生面板分为 Chat、Translation、Agent 三种模式，并把发送、停止生成、手动/自动翻译、暂停/继续/停止 Agent 等事件回调给 Dart。 |
| `lynai/screen_translation` | captureAndRecognize/showTranslations/clearTranslations/scrollSceneBy | Android | 屏幕翻译专用通道。Android 原生隐藏悬浮层后截屏并直接运行 PPOCRv5，只把 OCR 文本组和坐标返回 Dart；译文由单个透明 Canvas Window 绘制。 |

读屏类函数 `device.screen.query`、`device.screen.waitText`、`device.screen.readVisibleText`、`device.screen.extractMessages`、`device.node.find`、`device.node.findAll` 和 `device.waitForNode` 需要 `device:screen:read`。动作类函数如 `device.app.open`、`device.app.list`、`device.screen.clickText`、`device.screen.waitAndClick`、`device.screen.inputText`、`device.screen.scrollUntil`、`device.tap`、`device.swipe`、`device.inputText` 和 `device.node.action` 需要 `device:control`。

`CalendarPlatformProjectionService` 使用 `CalendarOccurrenceService` 投影未来 18 个月的小组件发生记录，并把每个显式 `ItemReminder` 展开为独立触发器。日期型锚点采用 `dateOnlyTime`，未设置时默认本地 09:00；已完成任务不产生通知。版本 2 投影为 UTC 定时事件额外保存小组件起止和提醒的 epoch 毫秒，时区变化后仍表示同一绝对时刻；任务、全天事件、纪念日及本地定时事件继续使用本地日期时间。Android 只读取自己的投影 SharedPreferences，开机、日期、时间和时区变化后按上述语义重新建立既有非精确 AlarmManager 闹钟，并兼容读取版本 1 投影。

系统提醒是 Android-only 能力。Dart 在所有平台都保存 `ItemReminder`，但 `CalendarPlatformBridge` 只在 Android 调用原生通道；`ReminderNotificationPermissionService` 仅在用户明确保存、且提醒数从 0 变为非 0 时调用 `requestNotificationPermission`。投影同步、启动加载和远端同步不会自动弹权限框。未授权时数据和闹钟投影仍可更新，但接收器不会展示通知。

### FloatingAssistantService

文件：`lib/services/floating_assistant_service.dart`、`lib/services/floating_chat_session_controller.dart`、`lib/services/floating_translation_controller.dart`、`android/app/src/main/kotlin/com/github/lynyugiri/lynai/FloatingAssistantOverlay.kt`、`ScreenTranslationPipeline.kt`、`TranslationOverlayHost.kt`、`TranslationOverlayView.kt`、`NcnnOcrRecognizer.kt`

Android 悬浮助手由原生 `WindowManager` 渲染系统级气泡和上下文面板。面板分为 Chat、Translation、Agent 三种模式；Agent 新任务开始时默认切到 Agent，之后尊重用户手动切换。`FloatingChatSessionController` 只负责真实 Conversation、聊天流和工具调用；`FloatingTranslationController` 独立负责 OCR 文本组翻译、自动翻译状态、取消代次和翻译历史。Agent 面板把 `DeviceRunSnapshot` 与对应 Conversation 的 `agentPlan` 合并展示。

气泡可拖动并记忆位置；面板 header 可拖动、底部可缩放，位置和尺寸持久化到 `FloatingAssistantSettings`。Chat 模式支持消息、语音、发送和停止生成；Translation 模式提供“翻译”和“自动翻译/停止翻译”，自动模式开启时禁用手动翻译；Agent 模式展示目标、当前动作、暂停原因和完整计划步骤。

翻译只使用本地 OCR，不再回退无障碍节点树。`ScreenTranslationPipeline` 临时隐藏气泡、面板和译文窗口，等待真实渲染帧后通过 Accessibility 截图，Bitmap 直接进入 ncnn/PPOCRv5，不做 PNG/Base64 往返。原生 `OcrTextGrouper` 把明显属于同一视觉行或竖排列的 OCR 块合并为请求内 `g_N` 文本组；Dart 按组 ID 请求 AI 并映射译文。每次手动翻译和自动翻译批次都清除上一批，不维护跨屏缓存。

译文由一个全屏、透明、不可触摸的 `TranslationOverlayView` 统一 Canvas 绘制，不再为每段创建 Window。横排文字按区域宽高换行并拟合字号；目标语言为中文、日文或韩文且 OCR 为竖排时按从上到下、从右到左绘制，拉丁目标语言在自动模式下保持横排。滚动事件只更新整个 scene 的偏移；手动翻译只跟随滚动，自动翻译在停止滚动 600ms 后清除旧批次并重新 OCR+翻译。停止自动翻译会取消晚到结果但保留当前译文；清除译文、锁屏、关闭功能或返回 LynAI 会终止自动模式并清屏。

### Agent Subagent

`run_subagent` 是 Agent 专用工具。它使用当前对话模型和权限创建独立短上下文，允许子任务多轮调用 `execute_lua`、Skill、OCR/识图等工具，但不会把中间屏幕信息写入主对话上下文。Subagent 会接收当前 Agent 工作记忆和计划摘要，完成后会把最终摘要或 `memoryUpdates` 合并回工作记忆。Subagent 禁止递归启动 Subagent，并受共享工具轮数上限约束，最终必须返回 `{ok:true,result:{...}}` 或 `{ok:false,error:{...}}`。

Agent 可通过 `list_plugin_skills` 查看启用 Skill 摘要、`load_plugin_skill` 读取 Markdown 正文，并可在用户要求沉淀或修正流程且已授权 `plugins.skills.files:write` 时调用 `save_plugin_skill` 写回可编辑 Skill。Skill 正文默认路径为 `skills/<name>.md`；`PluginSkillDefinition.editable` 默认 true，若清单显式设为 false 则模型写入会被拒绝。内置 Skill 的出厂正文放在 `defaults/skills/*.md`，用户或模型写入的 `skills/*.md` 作为 overlay 保留，不会被内置插件同步覆盖。

Subagent 适合 QQ/消息应用这类流程：主 Agent 只描述目标，Subagent 负责打开应用、查询屏幕、滚动、OCR 和读取上下文，最后把联系人、最近消息、置信度和摘要返回主 Agent。

### Agent 工作记忆

工作记忆是对话级持久化状态，跟随 `Conversation` 保存和备份。主 Agent 的 system prompt 会注入压缩后的目标、计划和最近记忆；工具和 Lua 可用 `read_agent_memory`、`update_agent_memory`、`agent.memory.read`、`agent.memory.update` 读写。Skill 加载成功和 Subagent 完成会自动写入短记忆，避免重复加载 Skill 或丢失子任务发现。

桌面端图片导出通常写入剪贴板；移动端更偏向图库或系统分享。

## PluginLuaRuntimeService

文件：`lib/services/plugin_lua_runtime_service.dart`

`PluginLuaRuntimeService` 管理 Lua 沙箱运行时，负责加载插件脚本、注册和调用工具/函数、维护延续链和事件通知。模型直接调用插件工具或函数时，`AgentCancellationToken` 会贯穿 VM 指令/时限预算、yield、continuation、同步 host call、延迟 command 和嵌套 LynAI operation；取消或 deadline 获胜后不会继续执行后续 Lua mutation。

### 沙箱执行

插件工具和函数在独立的 Lua 沙箱中执行。沙箱裁剪了不安全的全局函数（如 `os.execute`、`io.popen`），并注入受控 API：

| 注入 API | 说明 |
|----------|------|
| HTTP 请求 | 受权限控制的网络请求能力。 |
| 文件读写 | 限制在插件目录和用户授权路径内的文件操作。 |
| 回收站 | 插件可把自己的业务数据或 editableFiles 文件写入回收站。 |
| 日志 | Debug 日志输出，不会泄露到用户 UI。 |
| JSON | 解析和序列化 JSON。 |
| 设备 | `lynai.device.*` 便捷接口会生成受权限控制的设备命令，用于读屏、等待、点击、输入、滚动和消息提取。 |
| 规范规划 API | `lynai.tasks.*`、`lynai.calendar.*`、`lynai.anniversaries.*` 提供 `list/create/update/delete`。 |
| 旧规划 API | `lynai.todos.*`、`lynai.schedules.*` 继续可用，但只作为兼容适配器。 |

任务 API 复用既有 `todos:read` / `todos:write` 权限；日历事件与纪念日 API 复用 `schedules:read` / `schedules:write` 权限。权限名称为已发布插件契约，不因为领域模型规范化而改名。插件 Lua 的同步 `list` 直接返回结果；写操作通过异步 function command 执行。Agent Lua 同样注入 `lynai.tasks`、`lynai.taskLists`、`lynai.calendar` 和 `lynai.anniversaries` 便捷表，也可通过 `lynai.call('tasks.create', args)` 等完整函数名调用。

### 工具执行

| 步骤 | 说明 |
|------|------|
| 注册工具 | 解析 `plugin.json` 中 `tools` 列表，把 `tool_name` 和 `handler` 注册进运行时。 |
| 执行工具 | `ToolCallService` 识别插件工具后调用 `executePluginTool()`，在沙箱中运行对应 handler。 |
| 参数校验 | 运行前用 JSON Schema 校验参数，不合法参数提前返回错误。 |
| 返回结果 | 工具返回统一结构 `{ok: true, ...}` 或 `{ok: false, error: ...}`。 |

### 函数导出

除了 AI 可调用的工具，插件还可以通过 `plugin.json` 的 `functions` 列表注册内部函数。这些函数不暴露给模型，但可在功能页 WebView 的 JavaScript 桥中调用。

### 延续链

支持工具调用后的异步延续：工具返回 `continuation` 标记后，运行时挂起当前上下文并返回令牌。后续 `resumeContinuation()` 携带模型决策或用户输入继续执行。

### 生命周期

| 阶段 | 行为 |
|------|------|
| 加载 | 插件启用时加载入口脚本，注册工具和函数。 |
| 挂起 | 禁用插件时暂停沙箱，释放运行时资源。 |
| 卸载 | 移除插件时销毁沙箱并清理所有上下文。 |

## LynAIFunctionService

文件：`lib/services/lynai_function_service.dart`

`LynAIFunctionService` 是统一的 AI 函数调用分发层。模型请求中的 function call 经过 `ToolCallService` 识别后，由 `LynAIFunctionService` 路由到对应执行单元。

| 分类 | 路由目标 |
|------|----------|
| 规范任务 | `TaskProvider`，函数名前缀为 `tasks.*`。 |
| 规范日历 | `CalendarProvider`，函数名前缀为 `calendar.*` 和 `anniversaries.*`。 |
| 笔记 | `FeatureProvider` 的笔记、分页、修订方法。 |
| 旧规划兼容 | `todos.*` 和 `schedules.*` 在服务内转换并读写规范 Provider，不再访问旧权威。 |
| 回收站 | `RecycleBinRepository` 与插件安全上下文。 |
| 插件工具 | `PluginLuaRuntimeService` 的 `executePluginTool()`。 |
| 平台能力 | 原生平台通道。 |

`LynAIFunctionService` 本身不实现工具逻辑，它只负责根据工具名查找注册表和参数校验后转发到正确的执行器。新增功能类工具只需在注册表中添加条目，调用方无需改动。

## 互联能力注册表

文件：`lib/services/lynai_capability_registry.dart`

`LynAICapabilityRegistry` 是宿主内置能力与插件对外函数的统一目录，取代此前散落在 `_permissionFor` 中的硬编码权限 switch。每个 `CapabilityMethod` 声明 `method`、`permission`（null 表示免授权）、`isRead` 和 `provider`（host/plugin）。宿主能力由 `registerHostCapabilities` 一次性注册；插件能力随插件启用/禁用动态 `registerPlugin`/`removePlugin`。授权查询统一通过 `lookup`，未注册的 `device.*` 按操控屏幕权限处理。`model.list`/`model.current` 提供 `{provider, model, category}` 身份，`model.chat` 等接受 `provider`+`model`（回退旧 `modelId`/`modelName`）。

插件权限分为免授权与敏感两类，敏感度由 `LynAIPermissionDefinition.pluginAutoGrant` 系统定义，插件不能自证降级：`network:public`（仅 GET 公开只读 HTTPS）自动授予；`plugin.storage.*` 与 `plugin.file.list/read` 属插件沙盒免授权；其余（读写宿主数据、`network:access`、`model.*`、`device.*`、`recycleBin.*`、`webview:bridge`、越界 `files:write`）需用户在权限管理里逐项授权。

## 跨插件调用

插件在 manifest `functions` 中通过 `expose: true` 声明对外函数（可加 `requires` 声明调用方额外权限）。插件还可以在 manifest `dependencies` 中声明依赖插件 ID 与版本约束；该字段可选，不声明即表示没有依赖。启用插件时 `PluginProvider` 会校验已声明的依赖已安装、已启用且版本满足约束，禁用插件时会阻止关闭仍被其他已启用插件依赖的插件。`plugin.call` 是跨插件调用入口：调用方须持有 `plugins.callFunction` 以及目标函数 `requires` 中声明的额外权限，目标函数须 `expose` 且所在插件已启用；若调用方声明了对目标插件的版本约束，运行时会校验目标插件版本。函数内部再调用 `lynai.*` 时以目标插件身份执行，其 `grantedPermissions` 决定可访问的宿主能力，避免权限提升。Lua 侧经 `lynai.plugin.call(pluginId, function, args)` 触发。

## 命令选择器注册表

文件：`lib/services/composer_selector_registry.dart`

`ComposerSelectorRegistry` 是命令面板的选项源目录，承载内置选择器（笔记、笔记页面、待办清单、待办）与插件命令。`ComposerSelector` 声明 `name`、`title`、`description`、可选的 `modelId`（选中后覆盖本次发送模型）以及异步 `load(query, path)`；`load` 返回 `ComposerSelectorItem`（`folder` 用于分层导航，`item` 携带 `ComposerSelectorValue` 稳定类型/ID，不含正文）。插件命令由 `PluginLuaRuntimeService.executeCommandHandler` 在 Lua 沙箱中执行 handler，返回选项数组经 `parsePluginCommandItems` 解析（兼容 `result`/`options`/直接数组，`ok:false` 或结构非法时 fail closed 返回空列表）。

## AccountService

文件：`lib/services/account_service.dart`、`lib/services/remote_account_service.dart`

`AccountService` 是账号系统的抽象，定义注册、登录、登出、当前用户查询和会话恢复能力。前端页面和 Provider 只依赖抽象接口，不绑定具体后端实现。

| 方法 | 说明 |
|------|------|
| `register({username, password, displayName})` | 手机号和密码注册新用户，返回 `AuthSession`。 |
| `login({username, password})` | 手机号和密码登录，返回 `AuthSession`。 |
| `logout()` | 登出当前用户，清理本地凭证。 |
| `getCurrentUser()` | 获取当前登录用户，未登录返回 null。 |
| `loadStoredSession()` | 从本地持久化加载会话状态（启动时调用）。 |
| `AccountSessionRecovery.restoreLocalSession()` | 只恢复本地 token 和缓存用户，不访问网络。 |
| `AccountSessionRecovery.refreshCurrentSession()` | 单独刷新 `/auth/me`，临时失败保留缓存会话。 |
| `isBackendConnected` | 当前服务是否已连接到真实后端。 |

账号服务通过 `RemoteAccountService` 访问配置的后端 `/auth/*` 端点；未配置后端地址时 `AccountProvider` 不创建账号服务，登录/注册返回「未连接后端」。启动时先用 `restoreLocalSession()` 恢复本地 user/token，完成本地同步 scope 绑定后即可进入 Home；`GET /auth/me` 由后台 `refreshCurrentSession()` 更新用户资料和 `isAdmin`。access token 过期时复用 `BackendClient` 的 401-refresh-retry。网络错误、5xx 和 refresh 403 保留缓存会话，只有 refresh 明确返回 401 或刷新后 `/auth/me` 仍返回 401 时清除会话。后端轮换 refresh token 后，新 token pair 会立即覆盖安全存储。显式登出只触发一次可等待的本地 session 解绑；撤销队列记录规范化完整 Base URL，并向原 path prefix 下的 `/auth/revoke` 后台重试。

`RemoteApplyCoordinator` 是云同步和 LAN 同步共享的进程内本地提交门。它不串行网络认证和传输，只保证会修改 storage_v2、插件文件、Provider 内存、模型迁移和平台投影的提交阶段不会交错；前一操作失败后尾链仍可继续执行。

数据模型定义在 `lib/models/account.dart`：`AccountUser` 承载用户可见的展示信息，`AuthToken` 承载后端返回的访问令牌，`AuthSession` 组合两者。

## MarketService

文件：`lib/services/market_service.dart`、`lib/services/local_market_service.dart`、`lib/services/remote_market_service.dart`、`lib/services/market_plugin_package.dart`

`MarketService` 是插件市场的远端目录抽象，定义浏览、详情、下载和更新查询能力。前端页面只依赖抽象接口，不绑定具体后端实现。

| 方法 | 说明 |
|------|------|
| `listPlugins(MarketQuery)` | 按分类、关键词、分页查询市场插件，返回 `MarketQueryResult`。 |
| `getPluginDetail(id)` | 获取指定插件的详情条目。 |
| `downloadPlugin(id)` | 下载指定插件的 ZIP 字节内容，调用方负责交给 `PluginProvider.importZipBytes` 安装。 |
| `getInstalledUpdates()` | 查询当前已安装插件中可更新的条目。 |
| `isBackendConnected` | 当前服务是否已连接到真实后端。页面据此决定显示空态文案还是真实数据。 |

连接后端时使用 `RemoteMarketService` 浏览、下载、提交和检查更新；未连接时回退 `LocalMarketService` 空态，并保留「从 ZIP 导入」入口。目录查询把关键词、分类、页码和 page size 传给后端，并以 `hasMore` 驱动“加载更多”；页面合并后续页时按插件 ID 去重。

市场提交和下载使用不同边界：提交 ZIP 在发起 multipart 请求前限制为 16 MiB；下载通过 `BackendClient.getBounded()` 同时检查 `Content-Length` 和实际流字节，最多读取 32 MiB。这里的数字属于市场网络契约；通用 ZIP 解压仍由 Repository 的独立边界负责。

详情页安装前先校验市场条目中的 ZIP SHA-256（字段存在时）、唯一根目录 `plugin.json` 以及 manifest ID 与市场 ID 一致，再进入 `PluginProvider` 的串行原子安装。市场版本字段使用插件 manifest 的 SemVer 格式；更新查询发送本地已安装的 ID/版本对，版本判定属于后端市场契约，客户端不使用字符串字典序自行判断新旧。

`MarketPluginEntry` 是市场目录条目模型，字段对齐 `PluginManifest` 中用户可见的元数据，但只承载目录信息，不承载本地启用状态或文件路径——那些属于 `InstalledPlugin` 的运行时视图。

## CodeSyntaxService

文件：`lib/services/code_syntax_service.dart`

`CodeSyntaxService` 提供代码高亮能力，采用 tree-sitter 原生 + Dart fallback 双路径策略。

| 路径 | 条件 | 说明 |
|------|------|------|
| tree-sitter 原生 | `TreeSitterNative.isAvailable()` 为 true | 使用 C 语言 tree-sitter 解析库，比纯 Dart 快 10-50 倍。 |
| Dart fallback | 原生不可用时 | 回退到纯 Dart 实现的正则匹配高亮，覆盖主流语言。 |

tree-sitter 原生路径需配合以下文件：

| 文件 | 说明 |
|------|------|
| `lib/services/tree_sitter_native.dart` | 语言注册和高亮入口，管理 tree-sitter 解析器生命周期。 |
| `lib/services/tree_sitter_native_ffi.dart` | Dart FFI 绑定，调用编译好的 C 动态库。 |
| `lib/services/tree_sitter_native_stub.dart` | 不支持原生 FFI 平台（如 Web）的占位实现。 |
| `lib/services/tree_sitter_language_registry.dart` | 语言 scope 到 tree-sitter grammar 的注册映射。

tree-sitter 解析结果会转成 Flutter 的 `TextSpan` 结构，与 fallback 路径输出格式一致，上层渲染层无需感知当前使用哪条路径。

## RoleplayService

文件：`lib/services/roleplay_service.dart`

`RoleplayService` 负责情景演绎中的模型调用和导演决策解析。

| 步骤 | 说明 |
|------|------|
| 构建导演 prompt | 输入情景、角色、历史和玩家队列，让导演决定下一步。 |
| 解析导演输出 | 转成说话、旁白、等待用户或错误状态。 |
| 调用角色模型 | 使用角色系统提示词和线程历史生成台词。 |
| 产出流式 chunk | 页面和 Provider 使用流式内容更新草稿。 |

Roleplay 复用 Chat 模型配置和 `ApiService`，但运行状态由 `RoleplayProvider` 管理。

## StorageV2Service

文件：`lib/services/storage_v2_service.dart`、`storage_v2_database.dart`

storage_v2 是新版本地存储布局。`StorageV2Service` 是读写门面，`StorageV2Database` 是 Drift 数据库。应用级 Provider 共用同一个 `StorageV2Service`，统一数据库生命周期、资源写入队列和同步作用域。

```text
storage_v2/
├── manifest.json
├── app.db
├── notes/...md
└── assets/blobs/{sha256Prefix}/{sha256}
```

| 部分 | 说明 |
|------|------|
| `manifest.json` | 标识存储类型、schema 和布局信息。 |
| `app.db` | 结构化数据权威源。 |
| `notes/*.md` | 笔记分页正文。 |
| `assets/blobs/*` | 资源文件，按 SHA-256 内容寻址保存。 |

Drift 内的 `sync_outbox` 保存尚未确认上传的 cloud 行级变化，`sync_state` 保存各作用域的服务端游标、激活状态和持久化本地 mutation 捕获权。`transport_change_heads` 保存每个逻辑行当前可传播的 upsert/delete head，`transport_change_receipts` 以全局 `changeId` 和 canonical payload hash 去重，`transport_peer_acks` 持久化逐 peer、逐 mutation-version ACK。一次本地逻辑 mutation 只生成一个稳定 `changeId`，复用于 head 和当前 cloud outbox；cloud ingress 更新 head 后可发送给 LAN，但不会回写来源 cloud；LAN ingress 在业务 apply、receipt/source ACK、head 更新和 cloud route 同一事务中提交。未解决 conflict 不进入 forwarding，显式选择远端后保留原 `changeId`，选择本地则产生新的本地 mutation。

物理 dataset ID 同时作为 transport lineage。LAN wire 可选地携带 additive `lineage`；只有 lineage 与当前 dataset 一致的 LAN ingress 才能自动路由到当前 cloud scope。缺失 lineage 的旧 peer 数据仍可本地应用和 LAN 传播，但不会上传 cloud，也不会在后续登录账号时补传；这避免账号 A 的 mutation 进入账号 B 的物理 dataset。首次 LAN 激活会幂等导入旧 `lan:v1` outbox、`sync_applied_changes` 和 SecretStore 中的 LAN applied/ACK IDs，然后删除旧 transport keys。LAN manifest 分页按最终 JSON body 和完整 serialized frame 精确字节数裁切，并在 blob 工作和持久化之前校验允许字段、table/op、`recordId == data.id`、delete 不携带 data 和插件 schema。Outbox 支持稳定排序的 limit/offset 窗口读取，资源可按 ID 集合查询，以便同步先处理记录描述符、需要上传时再读取 Blob。消息附件资源通过 `resources` 行和 SHA Blob 同步；下载文件只写入标准内容寻址路径，不采用远端提供的本地路径。

当前 Drift schema 增加六张仅本机使用的 Agent/MCP 表。`AgentPersistenceRepository` 创建运行图和快照，并通过带预期旧状态的 compare-and-set 完成状态迁移；`RepositoryAgentRunPersistenceLifecycle` 将主对话、悬浮聊天和 Subagent runtime 接到该图，确保工具调用记录在副作用前落库，取消/失败会终结仍活动的子项。启动协调会在 Provider 加载前把 `queued`/`running` 运行及其未完成子项原子标记为 `interrupted`，失败会中止启动，且不会自动重放工具。`mcp_servers` 仅接受公开 transport/command/URL、参数和环境变量名，拒绝凭据 URL、query/fragment 和 secret 参数。后续 generation/full-reseed、云索引缓存、Outbox/conflict 索引及规范任务/日历表沿用各自迁移历史。数据库 schema 版本与 `StorageV2Service.currentLayoutVersion` 是不同概念。

## MCP 服务

文件：`lib/services/mcp/`、`lib/repositories/mcp_repository.dart`

MCP 当前实现是客户端工具桥，不是 LynAI 后端 API。`McpClient` 使用 JSON-RPC 2.0 完成 `initialize`/`notifications/initialized`、分页 `tools/list`、`tools/call`、`notifications/tools/list_changed` 和请求取消通知。请求有超时，取消会先结束本地 pending future，再 best-effort 发送 `notifications/cancelled`；迟到响应找不到 pending ID 时被忽略。

`McpHttpTransport` 实现 Streamable HTTP：POST 可接收 JSON 或 SSE，取得 session ID 后可用 GET SSE 接收通知，dispose 时 best-effort DELETE session。endpoint 默认必须是 HTTPS 和非私网；HTTP 与私网访问分别显式允许。最多跟随三次重定向，POST 只接受 307/308 保持方法，任何重定向后的请求不携带 credential/session header。消息、单个 SSE event 和总响应均有字节上限。

stdio transport 使用逐行 JSON，仅在 Linux、macOS、Windows 可创建；启动进程只收到显式 credential environment。Android、iOS、Web 只支持 HTTP transport UI。

MCP server 公开配置保存在 `mcp_servers`，preferences 与 credentials 保存在 `SecretStore`。远端 tool schema 通过共享 importer 按原样接受 `AgentJsonSchemaValidator` 支持子集校验；任何未知 keyword 或格式错误都会显式禁用/拒绝该工具，不会删除约束或补默认 schema。Provider 与 `McpToolSource` 还共用同一个长度有界、边界安全的 `AgentToolNameCodec` canonical naming。协议和平台范围详见 [MCP](mcp.md)。

运行时的 `tasks.json` 和 `calendar.json` 是 Repository/备份/同步使用的逻辑分区门面，不是 `storage_v2/data/*.json` 镜像文件；结构化权威仍是 `app.db`。任务与日历日常 mutation 通过 `applyLocalRowChanges()` 在一个事务中按行 upsert/delete 并捕获 Outbox，完整 replace 留给备份恢复和远端重载。`tasks.json` 包含 `tasks`、`lists`、`entries`，其中 entry 使用 `listId`、`taskId`、`sortOrder`；`calendar.json` 包含 `events` 和 `anniversaries`，事件使用扁平 `timeKind` 字段，全天结束日期始终为 exclusive。

笔记修订正文同样使用内容寻址 blob。分页出现并行 DAG 头时，`note_page_conflicts` 持久化稳定的本地头、传入头和共同祖先；合并提交必须重新校验完整头集合，避免基于过期冲突覆盖新到达的头。`note_page_tombstones` 中 `revision_id='*'` 表示整个分页删除，具体 ID 表示单个修订删除；应用 tombstone 会同步清理修订、分页头、当前修订引用和失效冲突，后续远端修订或分页头应用必须先检查 tombstone。显式恢复会同步删除对应 tombstone；同一恢复批次必须先应用 tombstone delete，再应用 revision/page-head upsert，而 tombstone upsert 仍在 revision/page-head 后应用以保持删除优先。

### 路径安全

所有 storage_v2 相对路径都必须经过 `_file()` 检查。它会拒绝绝对路径、空路径段、`.`、`..`，并检查最终路径仍在 storage_v2 根目录内。

### 资源导入

`importResourceFile()` 会按文件内容计算 SHA-256，相同内容和大小的资源复用同一条记录。资源 blob 路径固定为 `assets/blobs/{sha256Prefix}/{sha256}`，展示名、MIME 类型和用途保存在资源 metadata 中。

## StorageV2UpgradeService

文件：`lib/services/storage_v2_upgrade_service.dart`

负责启动阶段创建或升级 storage_v2，只处理当前 storage_v2 布局到新版布局的安全升级。

```text
missing storage_v2
  -> create manifest.json
  -> open app.db

storage_v2 schemaVersion < current
  -> copy storage_v2_backup_<timestamp>
  -> copy old resource files into assets/blobs/{prefix}/{sha}
  -> update resources.relativePath
  -> write current manifest
```

升级前会复制整个 storage_v2 目录作为备份。升级失败时恢复备份，避免损坏当前用户数据。

## BackupService

文件：`lib/services/backup_service.dart`

`BackupService` 负责 ZIP 备份导出、读取、预览和导入。schema 常量以 `BackupService.currentSchemaVersion` 为准，并接受 `BackupService.oldestCompatibleSchemaVersion` 起的旧格式。普通 ZIP 永不包含 API key；加密“包含密钥”模式在内层 ZIP 加入独立模型 API-key 分区，再以 `BackupEncryption` 的 Argon2id + XChaCha20-Poly1305 信封认证加密精确 ZIP bytes。设备私钥、账号 token、同步 outbox/state/conflict/baseline/applied-change、transport ledger 和数据库文件不参与备份；读取 ZIP 时也显式拒绝这些内部路径。

### 导出结构

```text
manifest.json
settings.json
model_configs.json
conversations.json
notes/folders.json
notes/notes.json
notes/pages.json
notes/revisions.json
notes/edit_proposals.json
notes/edit_blocks.json
notes/page_contents/{pageId}.md
tasks.json
calendar.json
roleplay_scenarios.json
roleplay_threads.json
resources.json
assets/blobs/{sha256Prefix}/{sha256}
```

实际写入哪些文件由 `BackupSelection` 决定。`manifest.json` 会记录类型、schema、应用版本、创建时间、分区信息和附件映射。被引用的私有附件使用和 storage_v2 资源一致的 SHA blob 路径；多个旧路径引用同一内容时可共享同一个 ZIP 条目。当前导出使用归档内 `asset://` 引用完成恢复映射，不写消息 `legacyPath`、资源 `originalPath` 或设备绝对路径；`settings.storageV2` 只允许背景资源 ID。

### 分区

| 分区 | 内容 |
|------|------|
| `settings` | `AppSettings` 和/或 `ModelConfig`，可细分 API 配置、外观、对话设置、角色与提示词。 |
| `conversations` | 选中的对话和私有附件。 |
| `notes` | 选中笔记、文件夹、分页、分页正文、修订和 AI 修改建议。 |
| `tasks` | 选中的规范任务、任务清单和仍有效的归属条目，写入 `tasks.json`。 |
| `calendar` | 选中的日历事件和纪念日，写入 `calendar.json`。 |
| `roleplay` | 选中的情景和对应演绎线程。 |

### 导入流程

1. `readZip()` 解压并校验 `manifest.json`。
2. 解析各分区 JSON，坏数据记录为 warning。
3. `preview()` 生成分区摘要和冲突列表。
4. 用户选择导入模式和冲突动作。
5. `importArchive()` 恢复私有附件并重映射路径。
6. 按分区应用到 Provider；storage_v2 笔记会恢复分页元数据和 Markdown 正文，修订 blob 只安装所选笔记引用的 SHA-256。
7. 清理最终数据没有引用的临时恢复附件。

当前 canonical 备份 schema 以 `BackupService.currentSchemaVersion` 为准，导出 `tasks.json`/`calendar.json`。读取兼容范围由 `BackupService.oldestCompatibleSchemaVersion` 决定。schema 1-4 走独立的历史迁移读取器，只接受对应版本实际存在的分区、文件名和嵌套/扁平 shape，先清除模型配置中的明文 API key，再把对话、可解释的笔记/分页、日程和待办归一化为当前 `BackupData`；旧 `roleplay_sessions.json` 仅在玩家和历史模型引用可定位时转换为 scenario/thread。记录级缺失或字段损失产生 warning，容器歧义、跨版本载荷和危险 shape 直接拒绝。schema 5-8 使用 `schedules.json` 和 `todo_lists.json`，导入时先按旧清单顺序拆出任务/条目，再转换旧 schedule，以保持与数据库迁移相同的 ID 碰撞结果。当前格式直接解析规范分区。旧文件只在兼容读取时接受，新导出不会重新生成它们。

### 导入模式

| 模式 | 说明 |
|------|------|
| `merge` | 合并导入；遇到冲突按用户选择处理。 |
| `addOnly` | 只添加本地不存在的数据。 |
| `replaceSection` | 清空所选分区后以归档快照完整替换；归档中不存在的本地记录不会保留。 |

### 附件恢复

备份只归档解析符号链接后仍位于应用私有目录中的引用附件。schema 10 的 `archivePath`、资源 `relativePath` 和实际恢复位置统一使用 storage_v2 的 SHA 内容寻址 blob 路径，导入后业务记录可直接读取该文件；旧数字前缀附件路径不再作为新版备份格式支持。manifest 必须声明所有业务文件，schema 5-10 已声明 JSON 的顶层容器损坏时直接拒绝，不会把错误容器降级为空列表。

插件备份复用与插件同步等价的秘密文件过滤，设置和 storage 对 Map/List 递归删除 API key、token、authorization、password、secret 和 credential 等秘密键。任何从备份归档恢复的插件代码都不被信任，恢复状态统一为 disabled + needsReview；伪造内置 ID 不能恢复可执行包，真实内置插件也只接受本机 manifest 声明的可编辑覆盖文件。schema 1-7 中的插件安装载荷一律跳过，不恢复可执行文件及与其身份绑定的设置/storage，并给出要求重新安装审查的 warning。所有 schema 都拒绝 `app.db`/SQLite、sync metadata、secret 和设备私有文件；历史迁移也不会生成或恢复 sync cursor、outbox、ACK、baseline 或设备身份。

导入在安装 note/resource blob、写 Provider 或替换插件目录前，先验证全部所选业务对象、分页正文、修订 blob 和插件包到临时 staging，避免常见后段格式错误造成前面分区部分提交。Provider、数据库和多个文件目录尚未组成跨介质原子事务；进程中断、磁盘 I/O 错误或后续持久化失败仍可能留下已安装的内容寻址 blob 或部分业务提交，未引用恢复资源会在正常退出路径清理。

如果 manifest 引用了某个附件但 ZIP 中缺失该文件，导入会记录 warning，并清除对应背景图或消息附件引用，避免导入后指向另一台设备上的无效路径。

## SystemScrollCaptureService

文件：`lib/services/system_scroll_capture_service.dart`

`SystemScrollCaptureService` 提供跨平台长截图滚动捕获能力，用于将可滚动内容导出为完整长图。

| 平台 | 策略 |
|------|------|
| Android | 使用 AccessibilityService 或系统截图 API 逐帧捕获并拼接。 |
| iOS | 通过 `UIScrollView` 渲染至离屏画布。 |
| 桌面端 | 直接渲染完整 Widget 树到 `RenderRepaintBoundary`，不需要逐帧滚动。 |

| 步骤 | 说明 |
|------|------|
| 启动滚动 | 发送离散滚动增量，逐段捕获内容。 |
| 帧拼接 | 把每段截取内容按重叠区域拼接为完整长图。 |
| 图像后处理 | 裁剪多余区域、去重重叠部分、统一尺寸和编码。 |
| 导出 | 保存为 PNG 或 JPEG 到用户选择的位置。 |

长截图通常用于分享对话历史、笔记全文、待办清单和情景演绎消息。

## ChangelogParser

文件：`lib/utils/changelog_parser.dart`

更新日志作为 Flutter asset 打包在 `changelogs/` 目录。`ChangelogParser` 读取 asset manifest，筛选 Markdown 文件并解析二级标题日期、三级标题分区和列表项。

启动弹窗加载当前包版本对应的 `changelogs/v*.md`。如果版本带 build 或 prerelease 后缀，会先尝试完整版本，再回退到稳定版本号。

## 服务层维护建议

1. 新增 API 协议时，先在 `ApiService` 内转换成现有 `StreamChunk` / `ChatResponse`。
2. 新增工具时，同时更新工具 schema、参数校验、执行逻辑和文档。
3. 新增备份字段时，更新 manifest 或分区 JSON，并同步 bump `BackupService.currentSchemaVersion`。
4. 涉及 API Key、位置、工具写入本地数据的功能，要在 UI 或文档中提示风险。
5. 新增持久资源路径时，使用 storage_v2 资源入口，并考虑备份和 SHA blob 去重。
6. storage_v2 内部路径必须通过统一安全检查，不能拼接未校验的相对路径。
# Plugin Content Sync

Plugin cloud/LAN sync uses the existing incremental sync log and SHA-256 blob API. Ordinary sync allowlists only the sanitized metadata domains `plugin_files`, `plugin_settings`, and `plugin_config`; `plugin_storage` and private plugin secrets remain excluded. The separately authorized LAN secret-transfer channel is limited to model API keys. Rows contain plugin IDs, safe relative paths, sizes, kinds, and blob hashes rather than inline file content or absolute local paths.

Third-party plugins sync sanitized manifest, executable/static source, declared editable files, configuration, and settings. Every package snapshot has a versioned marker containing an explicit `installed` or `deleted` state and an exact path/hash/size allowlist. Third-party content without that marker fails closed; absence of rows is never interpreted as uninstall. Built-in plugins keep their overlay behavior: bundled source is never uploaded, while sanitized user overlays, configuration, and settings are synchronized. `plugin_storage` and all private plugin storage are device-local and never enter cloud or LAN sync. Runtime errors, cache/temp files, local paths, enabled state, granted permissions, and enabled tools/functions/skills/pages are also excluded.

Downloaded third-party executable content is restored only after the receiver verifies the package-manifest version, exact file set, every blob hash and declared size, the `plugin.json` hash and plugin ID, path safety, and aggregate limits. Validation is shared by cloud and LAN metadata paths; the complete package is staged beside the target and atomically renamed into place. New or changed package content starts disabled with no permissions or enabled capabilities, is marked `needsReview`, and cannot be enabled until the user records an explicit local review. Settings/config-only or unrelated sync application preserves the device's existing enabled/review/grant state, and settings/config rows cannot create a missing plugin.

Configuration keys whose names contain `token`, `key`, `password`, or `secret` (case-insensitive, including nested maps) are omitted from cloud and LAN blobs. Existing local values for those keys survive remote config replacement and remain device-local.
## LAN Services

- `LanDeviceProfileService` persists the editable installation display name in
  secure storage. The first value uses the platform hostname when available and a
  stable device-ID suffix fallback otherwise.
- `LanPairingPayloadCodec` signs and verifies canonical versioned QR payloads.
- `LanTlsCertificateService` generates P-256 TLS material, stores PEM only in
  `SecretStore`, requires TLS 1.3, and calculates certificate SPKI pins.
- `LanMdnsService` advertises/discovers `_lynai._tcp` with only protocol version
  and device ID in TXT records.
- `LanSecureTransport` enforces framed message, body, timeout, session ID, and
  monotonic counter limits. Blob descriptors are limited to 64 MiB each and 128
  MiB per session; resource and note files are sent in 384 KiB chunks with size
  and SHA-256 revalidation. Incoming blobs are written one at a time to a bounded
  temporary directory and checked for chunk order, declared size and SHA-256.
  Descriptors not referenced by the change set are rejected; verified files are
  installed only after the complete requested transfer succeeds, and cleanup
  also runs on failure.
- `LanPeerProofService` exchanges mutual Ed25519 identity proofs over pinned TLS.
- `LanSyncCoordinator` pairs, confirms fingerprints, consumes nonces, syncs
  installation-local changes/blobs independently of the active cloud account,
  deduplicates `changeId`, and maintains per-peer acknowledgements. Pairing and
  every sync session exchange the bilateral category selection. Later reductions
  apply locally immediately; additions use a separate TLS + Ed25519 authenticated
  proposal session and become effective only for the subset accepted by the
  other peer. The agreed value is persisted with the peer in `SecretStore`; this
  intentionally does not maintain a separate signed policy ledger. Change
  manifests are filtered in both directions, unauthorized incoming rows fail the
  session, and deterministic pages continue until an empty/final page with exact
  per-page ACK validation. Cloud state remains partitioned by backend origin and
  user ID; LAN peers are not account-scoped.
- `LanSecretTransferService` permits API-key transfer only after explicit opt-in
  and rejects device identity or account-token secret keys. Its idempotent
  `close()` clears grants/requests, closes the request stream, and suppresses
  later events. `LanSyncCoordinator.close()` stops hosting and then closes that
  owned transfer service; `LanMdnsService.dispose()` stops discovery/advertising
  and closes the global peer stream.

Cloud device identities are stored per normalized backend origin and user ID.
Remote sync requires successful enrollment and signed uploads with no unsigned
client fallback. `BackendClient.postReplayableBytes` rebuilds sync signature
headers after an authenticated 401 refresh while replaying the same bytes.
`BackendClient.sendAuthenticatedStreamed` similarly rebuilds streamed and
multipart requests, and all managed relay protocols use that sender.

## CI And Platform Builds

The CI quality gate is `flutter pub get`, `flutter analyze`, then `flutter test`
on Flutter stable. Release jobs run only after that gate: Android builds split
APKs per ABI, Linux creates Debian and Arch packages, Windows creates an x64 ZIP,
and macOS builds separate x64 and arm64 artifacts. Linux builders install the GTK,
WebKit, libsecret, xz, and zstd development/runtime dependencies used by packaging.

The current `speech_to_text` Swift package needs the repository patch script
after `flutter pub get` and before macOS release builds:
`ruby scripts/patch-speech-to-text.rb`. CI performs this step explicitly; local
Apple-platform release builds should use the same order if the pub-cache package
has not already been patched.
# Agent Tool Services

- `AgentToolExecutionService` is the production batch execution boundary for model-originated tools. It validates schemas, authorizes the captured permission snapshot, applies scheduler concurrency semantics, and sanitizes terminal values.
- `WebSearchService` can route to configured client adapters or the authenticated backend endpoint `/search/web`.
- `AttachmentReadService` resolves attachments only through conversation ID, message ID, and attachment index. `AgentResourceService` reads only allowlisted resource roles through stable resource IDs and bounded text/model recognition APIs.
- `AgentUserInteractionBroker` correlates `ask_user` requests to run, turn, invocation, and UI surface. Run/tool cancellation atomically removes that exact request and clears its UI; stopping main or floating chat cancels only that surface, while stale responses cannot resume another tool call.
### Tool And Outbound Security

- `LynAIFunctionContext` requires an explicit `LynAICallIdentity`; trusted host callers must opt into `system` identity rather than receiving it as a default.
- `BoundedOutboundHttpClient` is the shared boundary for Agent/plugin HTTP access. `http.fetch`, `web_fetch`, and built-in weather retrieval enforce SSRF policy, redirect revalidation, bounded request and streamed response sizes, timeout, and cancellation. Generic model-reachable fetch defaults to HTTPS even when a caller injects a client whose policy allows a specific HTTP origin; plaintext fetch requires a separate trusted construction opt-in.
- Agent deletion checks inspect operation semantics as well as function names, so delete flags and replacement-list omissions cannot bypass the current no-delete policy.
- Plugin Skill edits use `plugins.skills.files:write`. Plugin model tools are canonicalized per plugin and captured as immutable run registrations.
## Dataset storage services

`StorageV2Service` owns the dataset registry and active binding generation while
preserving its existing repository facade. It validates registry identities,
dataset metadata, containment, and symlink ownership before use. Legacy
`storage_v2` migration is copy-style, journaled, idempotent, and retains the
source. Each dataset carries its own database and filesystem payload, including
sync Outbox, resources, plugin materialization, attachment staging, Agent graph,
and MCP rows. No transport bridge tables are added yet; the per-dataset database
is the boundary prepared for that phase.

`DatasetSecretStore` namespaces model and MCP secret keys by active dataset.
Account tokens and device identity remain device/bootstrap concerns in the
unscoped protected store. `DeviceSettingsService` persists the backend bootstrap
URL outside account datasets. Backup construction reuses the active storage and
plugin roots, so it exports and restores only the selected dataset.
`DatasetRuntimeBarrier` provides the exclusive physical-dataset switch boundary. `DatasetRuntimeCoordinator` quiesces Agent, MCP, cloud, LAN, resource queues and provider saves before activation, reloads the target, reconciles durable Agent state, and synchronizes the calendar platform projection after both success and rollback. Retired `StorageV2Database` leases reject later operations instead of remaining writable.
# 知识解释

`KnowledgeExplanationService` 使用类别专用模型或聊天模型生成解释。点击 `[[category:text]]` 标注时，已有解释优先本地读取；否则自动生成并保存到类别绑定的知识库。关闭弹窗后晚到结果被忽略。普通文字选区使用相同服务，但由用户决定是否保存。`knowledge.json` 是备份、Repository 和同步使用的逻辑分区；结构化权威仍是 `storage_v2/app.db`。客户端不再持久化或导出知识默认设置，也不再在类别 payload 中写入 `isDefault`。旧云或 LAN 的 `knowledge_settings/global` change 会作为兼容 no-op 被确认并推进各自接收账本；它不属于当前 outbound ordinary table，非 `global` 记录仍拒绝。旧类别 payload 中的 `isDefault` 会被忽略，schema 11/12 备份中的 alias 冲突交由 `KnowledgeProvider` 使用与正常加载相同的确定性规范化处理。
