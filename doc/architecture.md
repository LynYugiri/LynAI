# 架构说明

LynAI 的架构目标是让页面、状态、存储、协议和数据模型各做各的事。功能可以增加，但边界不应该模糊：Page 处理交互，Provider 维护状态，Repository 读写本地数据，Service 处理外部能力，Model 只描述数据。

## 分层

```text
用户操作
  -> Page：展示界面、收集输入、处理生命周期
  -> Provider：更新内存状态、通知 UI、排队持久化变更
  -> Repository：读写 storage_v2
  -> Model：不可变数据和 JSON 契约

外部能力
  -> Service：模型 API、工具调用、备份、平台通道、storage_v2 升级
```

| 层 | 典型文件 | 禁止事项 |
|----|----------|----------|
| Page | `chat_page.dart`, `feature_page.dart`, `settings_page.dart` | 不直接写持久化，不把 API 协议散落到 UI。 |
| Provider | `providers/*.dart` | 不展示 UI，不直接读写 storage_v2。 |
| Repository | `repositories/*.dart` | 不通知 UI，不持有页面状态。 |
| Service | `api_service.dart`, `backup_service.dart`, `tool_call_service.dart` | 不依赖 `BuildContext`，不保存页面生命周期状态。 |
| Model | `models/*.dart` | 不做网络请求，不读写文件或数据库。 |

## 启动流程

```text
main()
  -> 注册 SecretStore / DeviceIdentityService / DeviceRegistrationService
  -> 注册 ConversationProvider
  -> 注册 FeatureProvider
  -> 注册 CalendarProvider / TaskProvider
  -> 注册 ModelConfigProvider
  -> 注册 PluginProvider
  -> 注册 AccountProvider
  -> 注册 RecycleBinProvider
  -> 注册 RoleplayProvider
  -> 注册 SettingsProvider
  -> 注册 AgentToolRegistry / PersistentMcpRepository / McpProvider
  -> StorageV2UpgradeService.ensureReady()
  -> AgentPersistenceRepository.reconcileAfterRestart()
  -> 并行加载对话、笔记、规范任务、规范日历、插件、回收站、情景演绎、模型、设置和 MCP 配置
  -> 根据设置配置 BackendClient
  -> 初始化并校验设备 Ed25519 身份
  -> 从安全存储恢复本地账号令牌、缓存用户并绑定本地同步作用域
  -> 应用待处理的本地托管模型 ID 迁移
  -> 构建 MaterialApp / HomePage
  -> 后台刷新账号、注册设备并执行云端双向同步
  -> 后台同步托管模型和内置插件
  -> 后台合并任务与日历快照并同步 Android 平台投影
  -> 本地维护完成后开放 LAN hosting
  -> 检查更新日志
```

启动加载由 `LynAIApp` 控制。启动页只等待 storage_v2、本地 Provider、后端配置、本地缓存会话和同步作用域准备完成；Settings、Conversation、Roleplay、Plugin 与 Models 全部加载后，先恢复并应用持久化的旧托管模型 ID 引用迁移，再初始化账号和进入正常使用。模型加载会先把旧 Provider-scoped managed 配置按 category 合并成当前目标配置，因此离线备份迁移不会产生悬空引用。分区级加载失败会保留 Provider 原有内存状态、向上抛出并显示可重试错误页，不再把失败误写成空列表或默认设置。可独立解析的单条损坏数据仍会被跳过。账号令牌按规范化完整 Base URL（含 path prefix）保存在 `SecretStore`，SharedPreferences 只保留同作用域的用户元数据。缓存 user/token 和本地云作用域恢复完成后即可进入 Home，避免把 `/auth/me`、设备注册、Blob 传输或完整双向同步放在启动关键路径。进入 Home 后后台刷新用户和管理员状态；临时网络或服务端错误不清除缓存会话，明确 401 才解绑当前会话。设备注册、自动云同步、托管模型、内置插件和 Android 平台投影均为后台维护，失败通过各 Provider 状态或日志暴露，不会退回启动错误页。LAN hosting 先记录生命周期期望，只有本地维护完成后才开放，避免入站写入与首次加载交错。

云同步与 LAN 同步使用共享的远端提交协调器串行修改本地权威数据。协调区覆盖受影响 Provider flush、storage_v2 apply、插件和笔记 materialization、Provider reload、LynAI 模型刷新及平台投影；网络传输仍使用各自队列。会被远端重载的 Provider 使用 mutation generation 丢弃晚到的旧 repository 读取，防止用户在后台同步期间的本地编辑被陈旧 load 覆盖。

共享设置和用户 Provider 配置使用独立逻辑同步域：`shared_settings/app-settings` 保存 `SharedSettingsV1` 投影，`synced_model_configs/<providerId>` 保存用户明确选择同步的 `SyncedModelConfigV1`。本地保存先生成投影 diff，再写持久化 Outbox；远端应用仍经过同一按记录 conflict 队列。应用完成后重新加载各 Provider，并从 `/relay/config` 刷新 schema v4 的 LynAI 托管模型。背景图只同步 storage_v2 resource ID 与 content-addressed blob，不同步设备路径。

## 主界面结构

```text
HomePage (NavigationBar, 5 tabs)
├── FeaturePage (功能)
│   ├── Dashboard
│   ├── History
│   ├── Calendar
│   ├── Notes
│   ├── Tasks
│   └── Roleplay
├── PluginMarketPage (插件市场)
├── ChatPage (对话)
├── CommunityPage (社区)
└── SettingsPage (设置)
    ├── AboutPage
    ├── BackgroundPage
    ├── ApiModelsPage
    ├── ThemePage
    ├── DataManagementPage
    ├── McpSettingsPage
    └── PluginManagementPage
```

`HomePage` 使用 `IndexedStack` 保留五个主 Tab 的状态，Tab 顺序由 `AppTab` 枚举定义（feature → market → chat → community → settings）。对话生成中、功能页打开笔记详情、或设置页返回时，不会因为 Tab 切换销毁状态。`AppTab.chat` 是默认 Tab 和系统返回键的兜底目标。

社区使用页面局部远程状态：`CommunityPage -> CommunityService -> BackendClient -> /community API`。它首次成为当前 Tab 时才加载，并按规范化后端作用域和账号 ID 隔离状态。社区内容由后端持久化，不属于本地 `storage_v2`，不会进入备份、云同步或局域网同步。

## 对话链路

一次普通发送大致经过这些步骤：

1. `ChatPage` 读取输入框、附件、当前角色、对话设置和模型配置。
2. 附件复制到应用私有目录，形成 `MessageImage` 元数据。
3. 如果没有当前对话，`ConversationProvider.createConversation()` 创建对话并保存设置快照。
4. 添加 user 消息，再添加空 assistant 消息作为流式占位。
5. `ApiService.sendStreamRequest()` 由 `StreamChunkAgentAdapter` 转成统一 Agent 流事件。
6. `AgentLoopRuntime` 消费模型 turn；每个正文/思考 delta 刷新最后一条 assistant 消息。
7. 如有工具调用，runtime 把执行交给 `ToolCallService`；插件工具由 `PluginLuaRuntimeService` 执行，MCP 工具由共享 `AgentToolRegistry` 转发。
8. Agent 可通过 `read_agent_memory` / `update_agent_memory` 维护对话级工作记忆，并通过 `run_subagent` 把高噪声子任务放入独立上下文，主对话只接收最终结构化结果。
9. 保存最终正文、思考内容、工具结果或失败状态。

```text
Input + Attachments
  -> ChatPage
  -> ConversationProvider
  -> ApiService Stream<StreamChunk>
  -> StreamChunkAgentAdapter
  -> AgentLoopRuntime
  -> ConversationProvider.updateLastMessage()
  -> ToolCallService（可选）
  -> 保存最终消息
```

历史对话保存自己的 `ConversationSettings`，其中系统提示词保存选中当时的正文，而不只保存模板 ID。打开历史对话或继续发送时不会把该快照写回全局设置，也不会按当前同 ID 模板重新解析；全局模型、提示词或文件识别设置变化不会悄悄改变旧对话上下文。

当选中的模型配置是 LynAI 托管模型时，`ApiService` 使用独立的 canonical request/response/SSE 编解码，请求目标固定为后端 `/relay/chat`，并由 `BackendClient` 当前 JWT 做鉴权。服务端按 body 中的 `model` 路由；客户端不读取任何上游 Provider 标识或 API 类型，也不选择 OpenAI/Anthropic/Ollama parser。ChatPage、浮窗和 Subagent 仍共享 `ApiService` 标准化输出，managed 工具能力只看模型 capability，direct 工具限制保持原行为。

主对话、Android 悬浮聊天和 `run_subagent` 已统一使用 `AgentLoopRuntime`，共享 turn identity、tool round、强制最终回复、取消和 durable lifecycle。当前对话级 `AgentPlan`、`AgentWorkingMemory` 与 trace 继续随 Conversation 保存；本机 durable run graph 独立记录 run、turn、assistant item、tool call 和终态 tool result，工具记录失败时不会开始副作用。聚焦测试可省略持久化注入，重启只清算未完成图而不重放。详细边界见 [Agent Runtime](agent-runtime.md)。

## 情景演绎链路

情景演绎把一个可复用情景和多条演绎对话分开管理。

```text
RoleplayScenario
  -> RoleplayThread
  -> Director 判断下一步
  -> Character 生成台词 / Narrator 旁白 / WaitUser 等待用户
  -> RoleplayProvider 保存线程消息
```

| 组件 | 责任 |
|------|------|
| `RoleplayScenario` | 情景模板、默认导演、默认玩家、默认角色和分组。 |
| `RoleplayThread` | 某次演绎的角色快照、消息、设置和更新时间。 |
| `RoleplayService` | 调用导演模型和角色模型，解析下一步动作。 |
| `RoleplayProvider` | 情景/线程状态、运行状态、玩家排队消息和落盘。 |

玩家在 AI 运行中继续发送的消息会进入线程级队列，避免并发写入破坏演绎顺序。

## 附件和资源

长期资源必须先复制到应用私有目录，再把路径写入模型。

```text
Picker / Camera / Clipboard / Backup Restore
  -> 应用私有临时文件
  -> Repository
  -> StorageV2Service.importResourceFile()
  -> assets/blobs/{sha256Prefix}/{sha256}
```

storage_v2 中的资源注册表使用 content-addressed blob 路径。对话附件保存时，Repository 会通过 `StorageV2Service.importResourceFile()` 写入资源表并在消息附件表中保存资源 ID。

## 工具调用链路

工具调用让模型访问受控的本地能力。生产聊天和 Agent 只通过模型接口的原生 `tools` / `tool_calls` 暴露与接收调用，不解析正文 JSON fallback。

```text
模型返回 tool calls
   -> ToolCallService / LynAIFunctionService / PluginLuaRuntimeService
   -> TaskProvider / CalendarProvider / FeatureProvider / 平台通道
  -> 工具结果回传模型
  -> 模型生成最终回复
```

规范工具使用 `tasks.*`、`calendar.*` 和 `anniversaries.*` 读取或修改 `TaskProvider`/`CalendarProvider`；`todos.*` 和 `schedules.*` 只是已发布兼容别名，仍写入规范 Provider。权限 ID 继续复用 `todos:*` 和 `schedules:*`，避免破坏插件授权。工具也可修改笔记或调用 Android 平台能力，应只在可信模型和可信对话中启用。

动态工具统一注册到 `AgentToolRegistry`。MCP Provider、插件工具与 tool source 共用 `AgentToolNameCodec`，按 source、server/plugin ID 和远端工具名生成长度有界的 `tool_v1_*` canonical name。`ToolCallService.createRunSnapshot()` 在 Run 开始时捕获 descriptor、并发语义和权限快照。内置与插件 handler 固定在 snapshot；MCP 只固定模型 schema，执行时查询实时 registry，断连或禁用后 fail closed，避免调用已释放连接。MCP 细节见 [MCP](mcp.md)。

权限为全局单源（`AppSettings.agentGrantedPermissions`），对话不再保存独立权限快照。宿主能力与插件对外函数统一由 `LynAICapabilityRegistry` 声明权限与读/写性质；插件权限按 `pluginAutoGrant` 分为免授权（如 `network:public`、插件沙盒）与敏感（需在“权限管理”逐项授权），插件可通过 `functions.expose` + `plugin.call` 互相调用，被调函数以自身插件身份执行，避免权限提升。详见 [services](services.md)。

模型来源的终态工具结果统一经过 `AgentToolExecutionService` 的 runtime-level sanitizer，再进入持久化和模型上下文。sanitizer 负责 bounded JSON、安全元数据和 Resource/Blob offload；页面、插件和 MCP handler 不各自承担最终结果清洗，也不得绕过该运行时边界传递原始二进制或本地路径。

## 任务与日历链路

任务内容、清单元数据和归属关系分离；未完成/已完成只是页面和工具按 `completedAt` 计算的聚合，不是持久化清单。任务页与日历页使用同一规范任务编辑边界；日历事件、纪念日和发生记录也分离。页面、工具、备份和同步只能修改 canonical source models，不能把 `CalendarOccurrence` 或 Android 投影当成反向写入源。

```text
TaskProvider                 CalendarProvider
  ├── Task                     ├── CalendarEvent
  ├── TaskList                 └── Anniversary
  └── TaskListEntry                    │
           └──────────────┬────────────┘
                          v
             CalendarOccurrenceService
                          v
          CalendarOccurrence（只读 UI 投影）
```

`TaskRepository` 和 `CalendarRepository` 分别暴露 `tasks.json`/`calendar.json` 逻辑分区；底层 `StorageV2Service` 将这些分区映射到 `app.db` 的规范表。日常 CRUD、移动和排序按受影响行组成事务写入，完整替换接口用于 Provider 的整体替换、备份恢复和远端重载。Provider 仍遵守先内存通知、后串行保存。两边任一持久化操作成功后，`CalendarPlatformProjectionCoordinator` 等待两个队列，再生成一份合并 Android 投影，防止任务和日历并发保存互相覆盖原生状态。

`ScheduleItem`、`TodoList` 和 `TodoItem` 不出现在上述当前链路中。它们只由数据库迁移、旧备份、旧回收站和旧 API 适配器读取，再通过 `LegacyCalendarConversionService` 转换。

## Android 悬浮助手

悬浮助手保持三个独立运行边界：`FloatingChatSessionController` 管理聊天流，`FloatingTranslationController` 管理屏幕翻译批次，`DeviceRunController` 管理 Agent 设备任务。原生 `FloatingAssistantOverlay` 只负责悬浮球和 Chat/Translation/Agent 三模式面板。

屏幕翻译走 `ScreenTranslationPipeline`：原生暂时隐藏 LynAI 窗口、Accessibility 截图、Bitmap 直接进入 PPOCRv5、视觉文本分组、Dart 调模型翻译、单个透明 `TranslationOverlayView` Canvas 原位绘制。翻译不读取无障碍节点树，也不维护跨屏缓存；当前 scene 随滚动平移，自动模式在停止滚动 600ms 后重新处理当前屏幕。

Agent 页面理解仍使用无障碍节点树，但选择最上层外部应用窗口并排除 LynAI 自身窗口。注入手势期间气泡和面板临时不可触摸；用户操作悬浮窗本身不会被误判为接管目标应用。

Agent 手机自动化优先用 `lynai.device.*`、`device.screen.query` 和 `device.node.findAll` 精确筛选节点，同一应用内的确定性多步骤操作优先合并到一次 `execute_lua` 中线性编排。读屏、消息提取和节点查询只需要 `device:screen:read`，点击、输入、滚动、打开应用等动作需要 `device:control`。QQ/消息应用上下文优先从无障碍节点提取可见文本，截图 base64 只作为 OCR/识图输入，模型可见 tool result 会剥离二进制内容。内置 `mobile-agent-skills` 共 15 个 Skill，覆盖 Android 无障碍原语、消息应用通用流程、QQ/微信会话、系统设置、浏览器搜索、相机 OCR 扫描、通讯录与电话、时钟闹钟、地图导航、系统分享、解题与研究、笔记方法论、对话沉淀到知识库等场景。学习与笔记类 Skill 不走 `execute_lua`，直接由主模型调用 `notes.*`/`todos.*`/`schedules.*`/`http.fetch`/`model.ocr` 等函数。发给模型的 assistant 历史消息固定携带空 `reasoning_content`，避免真实 thinking 污染后续工具上下文。主对话和 Subagent 共用 `ToolCallService.maxToolRounds` 边界；到达边界时先要求模型基于现有结果结束，再拒绝继续执行工具，设备任务仍可通过暂停/停止机制提前中断。

## 持久化策略

Provider 的共同策略是“先更新 UI，再排队持久化”。

```text
Provider mutation
  -> 修改内存中的不可变模型列表
  -> notifyListeners()
  -> 行级变更或完整替换进入 Future 队列
  -> Repository
  -> storage_v2
```

这样用户操作立即反馈，连续操作也不会因为异步保存乱序覆盖新状态。当前保存失败会由发起操作或 `flushPendingSaves()` 暴露，同时恢复内部串行尾链，使后续保存仍能继续；失败不回滚已经显示给用户的内存状态。远端应用和同步作用域切换会先聚合 flush 相关 Provider，尝试完每一项后统一报告失败，任何失败都会阻止继续上传或覆盖本地状态。应用进入 inactive/paused/detached 或销毁时，关键保存与 Outbox 上传使用同一个进行中的 flush Future，重叠生命周期通知不会并发启动重复收尾。

## storage_v2

storage_v2 是新版持久化布局，由 `StorageV2Service` 和 Drift 数据库驱动。

```text
storage_v2/
├── manifest.json
├── app.db
├── notes/...            # 笔记分页正文
└── assets/blobs/...     # SHA 内容寻址资源
```

| 部分 | 说明 |
|------|------|
| `app.db` | 结构化数据权威源。 |
| `notes/*.md` | 笔记分页正文文件。 |
| `assets/blobs/*` | 背景、图片、文档、音视频等资源，路径为 `assets/blobs/{sha256Prefix}/{sha256}`。 |

Repository 只读写 storage_v2。启动阶段由 `StorageV2UpgradeService` 创建或升级 storage_v2，运行时不再从旧 JSON 恢复业务数据。

当前 Drift schema 包含本机 Agent 运行时表 `runs`、`turns`、`items`、`tool_calls`、`snapshots`、`mcp_servers`，以及 dataset-local transport ledger 表 `transport_change_heads`、`transport_change_receipts`、`transport_peer_acks`。这些表不属于逻辑数据分区、备份、云同步或 LAN 同步；启动时会把未完成运行图原子标记为 `interrupted` 失败，不自动重放。transport ledger 持久化当前行 head、全局 change receipt 和逐 LAN peer ACK，使云/LAN 桥接、去重与重启恢复不依赖有界 SecretStore 列表。MCP 表只保存公开连接配置和环境变量名，不保存 header、环境变量值或其他凭据。后续同步索引和规范任务/日历迁移沿用各自版本历史；数据库 schema 版本仅描述 `app.db` 内部结构，不得与目录布局常量 `StorageV2Service.currentLayoutVersion` 混用。

`tasks.json`/`calendar.json` 是 Repository、备份和同步的逻辑分区名称，不是在 `storage_v2/data/` 下维护的镜像。结构化唯一权威仍是 `app.db`。

## 笔记时间线

笔记支持修订树。当前内容与历史版本通过 delta 关联。

```text
Note.currentRevisionId
  -> NoteRevision
  -> parentRevisionId
  -> ...
```

storage_v2 下笔记正文按分页保存为 Markdown 文件；分页元数据、修订、AI 修改建议、行级编辑块和删除 tombstone 保存到数据库。分页 tombstone 的 `revisionId='*'` 表示整个分页已删除，具体 revision ID 表示单个修订已删除；远端分页头、修订或冲突应用不得复活被 tombstone 覆盖的状态。旧单正文笔记仍通过兼容路径读取。

## 备份架构

普通备份是 ZIP 文件，由 manifest、非秘密分区 JSON、笔记分页正文、资源表和私有附件组成。模型 API key 不在数据库、普通 ZIP 或云同步中；模型 JSON 只保存 `apiKeySecretRef`，运行时由 `SecretStore` 注入。

```text
backup.zip
├── manifest.json
├── settings.json
├── model_configs.json
├── conversations.json
├── notes/
│   ├── folders.json
│   ├── notes.json
│   ├── pages.json
│   ├── revisions.json
│   ├── edit_proposals.json
│   ├── edit_blocks.json
│   └── page_contents/
├── tasks.json
├── calendar.json
├── roleplay_scenarios.json
├── roleplay_threads.json
├── plugins.json
├── resources.json
└── assets/blobs/{sha256Prefix}/{sha256}
```

导入时先读取 ZIP，生成预览和冲突列表。用户确认导入计划后，服务先对全部所选业务对象和插件包完成无持久写的校验/staging，再恢复 blob、重映射资源引用、处理 ID 冲突并调用 Provider 替换或合并数据；这降低后段格式错误导致部分提交的风险，但尚不是覆盖 Provider、数据库和文件系统的跨介质原子事务。`replaceSection` 对单项 selection 只替换选中 ID，不删除同分区未选中的任务、清单、事件或纪念日。`BackupService.currentSchemaVersion` 写入规范 `tasks.json`/`calendar.json`；兼容读取 schema 5-8 的 `schedules.json`/`todo_lists.json` 时，会按与数据库迁移相同的顺序转换和处理任务 ID 碰撞。ZIP 内附件使用和 storage_v2 一致的 SHA blob 路径，备份不再兼容旧数字前缀格式。加密备份先验证 Argon2id/XChaCha20-Poly1305 信封，再解析内层 ZIP；只有该路径可以恢复模型 API-key 分区。

## Android 任务与日历投影

Android 原生层不读取 Dart Provider、数据库表或旧 JSON。`CalendarPlatformProjectionService` 从 canonical source models 生成未来窗口内的 widget occurrences 和每个 `ItemReminder` 的 trigger；`CalendarPlatformBridge` 通过 `lynai/calendar_platform` 一次性提交完整版本化投影到原生 SharedPreferences。

```text
TaskProvider + CalendarProvider
  -> 等待两个保存队列
  -> CalendarPlatformProjectionService
  -> MethodChannel syncProjection
  -> CalendarProjectionStore
  -> ScheduleWidgetProvider.refresh()
  -> ScheduleNotificationReceiver.reschedule()
```

原生通知使用非精确 `AlarmManager.setAndAllowWhileIdle`，稳定 trigger ID 用于取消旧 `PendingIntent`。开机、日期、时间和时区变化会从同一投影重排闹钟；小组件也在日期/时间/时区变化时刷新。已完成任务不生成通知 trigger。Android 13+ 通知权限只能由明确用户操作请求，投影同步不自动请求权限。Dart 的提醒模型可跨平台保存，但系统级提醒、小组件和原生重排目前仅 Android 支持。

## 更新日志

更新日志文件位于 `changelogs/`，由 `ChangelogParser` 读取 asset manifest 后解析 Markdown。启动时会比较 `AppSettings.lastSeenChangelogVersion` 和 `PackageInfo.version`，需要展示时打开弹窗。弹窗只返回用户操作，页面跳转由外层有效 context 执行。

## 容错原则

| 场景 | 策略 |
|------|------|
| 单条持久化数据损坏 | 跳过坏项，保留其他数据。 |
| 分区或顶层结构加载失败 | 保留当前 Provider 内存并向启动/重载流程传播，显示可重试错误，不把失败解释成空数据。 |
| 模型 ID 指向已删除配置 | 自动回填同类第一个可用模型或清空。 |
| 流式 chunk 格式异常 | 跳过坏 chunk，不中断已收到正文。 |
| 工具参数异常 | 工具返回结构化错误，不破坏对话。 |
| 旧 schedule/todo 数据 | 只在兼容边界解析并转换为 canonical task/calendar 模型，不恢复旧运行时权威。 |
| 页面销毁后的异步回调 | 检查 `mounted` 后再更新 UI。 |

## 维护底线

| 行为 | 原因 |
|------|------|
| `Message.images` 仍表示附件列表 | 字段名为兼容旧数据保留。 |
| OpenAI 兼容请求显式发送 thinking 开关 | 部分后端依赖 disabled 标记。 |
| 普通备份和云同步不包含 API Key | API key 只在本机 `SecretStore`；完整密钥恢复必须使用密码加密备份。 |
| storage_v2 路径必须通过安全检查 | 避免相对路径逃逸到应用目录外。 |
| 备份 ZIP 不直接打包 `app.db` | 保留分区导入、冲突处理和跨平台恢复能力。 |
| `ScheduleItem` / `TodoList` 不是当前权威 | 只允许用于旧数据库、旧备份、旧回收站和旧工具兼容。 |
| 系统提醒仅 Android | 其他平台保存提醒数据，但没有原生 widget/AlarmManager 投递。 |
## LAN Pairing And Sync

LAN sync is not scoped to a cloud account and runs beside cloud sync. It
synchronizes the installation's local dataset even when the user switches or
signs out of cloud accounts; the UI must not describe LAN peers as account-
isolated. Cloud cursors and outboxes remain isolated by normalized backend
origin plus stable user ID. `LanSyncCoordinator`
owns the TLS session lifecycle, while pairing payloads, Ed25519 identity proofs,
certificate/SPKI binding, mDNS discovery, framed transport, peer persistence,
and storage adaptation remain separate services/repositories. Each local mutation
creates one stable head in the dataset-local transport ledger and reuses its
`changeId` in the active cloud Outbox. LAN peers read unacknowledged ledger heads;
their acknowledgements never advance the cloud sequence cursor or remove cloud
delivery state.

Pairing activates the LAN scope, negotiates a bilateral data-category subset,
and returns without automatically syncing so the user can choose now or later.
The agreed selection is stored with each trusted peer in `SecretStore`. Every
authenticated sync validates the same selection and filters outgoing and incoming
rows; static resources can be disabled while retaining message-attachment
metadata. Reductions reconcile on the next authenticated connection, while
additions require an explicit authenticated proposal accepted by the peer. LAN
changes are transferred in bounded deterministic pages with exact page ACKs.
Cloud identities are separate
from the LAN identity and are keyed by normalized backend origin plus user ID.
Cloud uploads require enrollment and Ed25519 signing. Signed sync byte requests
keep replayable body bytes but rebuild authentication and signature headers after
an access-token refresh, so a 401 retry is signed against the refreshed session.
Managed relay requests use one replayable authenticated streamed sender for a
single refresh-and-retry on 401, including multipart uploads and streaming model
responses.

Cloud sync serializes operations but invalidates queued work with a generation
when the backend or account scope changes. Download pages and upload ACKs are
validated before cursor or Outbox state advances. Applied table names are
accumulated for the synchronization run so only affected Provider save queues are
flushed and reloaded; note Markdown materialization runs once at the end when a
note table changed. Outbox reads use 256-row windows, and referenced resource and
note blobs are loaded only when the remote side still needs an upload.

Cloud and LAN share the versioned `SyncDataSelection` category registry. Cloud
selection is local to one device/account scope; LAN selection is bilateral per
trusted peer. Message attachment metadata belongs to conversations, while original
attachment/background bytes require the additional static-resource category.
Expanded OCR/file text is persisted as hidden message model context, so a device
without the original file retains the model-visible conversation semantics and a
visible unavailable attachment placeholder.

Cloud data management is a separate read/model boundary layered on the same
account scope: `DataManagementPage -> CloudDataProvider -> CloudDataService` for
remote index and management APIs, and `CloudDataRepository -> storage_v2` for
durable cache and pending operation state. Index refreshes stage a complete
status plus all category pages before replacing scope-local cache, so partial
network failure leaves the previous snapshot readable. Purge never edits local
domain rows directly. Its pending operation is persisted first, then the manual
sync path marks the existing `SyncProvider` scope for full reseed; only a
successful reseed/upload is followed by signed operation ACK. Blob GC remains a
server concern and has no manual client action.

Plugin synchronization is limited to sanitized files, settings, and configuration.
Cloud and LAN use the same package validator. A schema-versioned package marker
records explicit installed/deleted state plus the exact allowed path/hash/size
set; third-party packages without it fail closed, and missing metadata never
means uninstall. Built-ins remain local trusted packages and synchronize only
their editable overlays. Package-content changes reset local execution trust,
while settings/config-only and unrelated sync preserve it. `plugin_storage` and
other private plugin storage are device-local and are never copied through cloud
or LAN sync.
## Physical datasets

`StorageV2Service` is a stable process-wide facade over one active physical
dataset. The application-support root contains `datasets/registry.json`; each
dataset has immutable `dataset.json` ownership metadata and its own
`storage_v2/app.db`, blobs, notes, plugin tree, attachment staging, Agent run
graph, and MCP rows. `local` is permanent. Account datasets are selected by the
full SHA-256 of normalized backend origin plus the opaque user ID.

Startup copy-migrates the retained legacy `storage_v2/` tree into `datasets/local`
using `migration.json`. Account changes flush providers in a fixed order,
activate and validate the target, then reload the same provider instances before
the account user is published. Activation failure restores and reloads the
previous dataset. Old dataset database handles remain valid until service close,
so in-flight operations cannot be rebound to a new path.

The backend bootstrap URL is device-level SharedPreferences state, not account
data, allowing session lookup and dataset selection before account data loads.
Physical dataset activation is protected by a shared runtime barrier. It stops admitting dataset-bound Agent work, cancels and awaits main/floating/Subagent runs, quiesces cloud/LAN synchronization, plugin filesystem mutations and resource mutations, disconnects MCP publication, flushes providers, then changes the storage binding. Reload and Android calendar projection complete before the barrier reopens; rollback follows the same reload and projection path. LAN hosting is suspended without changing its lifecycle preference and resumes to the prior desired state after either success or rollback. Database handles and admitted plugin mutations are generation-bound and fail closed after retirement.
