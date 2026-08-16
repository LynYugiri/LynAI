# 数据模型

`lib/models/` 是项目的数据契约层。模型负责表达业务数据、JSON 读写和旧字段兼容，不负责页面交互、网络请求或本地持久化。

## 设计原则

1. 模型只描述数据。
2. `fromJson()` 要兼容旧字段、缺失字段和可恢复的坏数据。
3. `toJson()` 尽量不写空值或默认值。
4. 可清空字段的 `copyWith()` 使用 sentinel，区分“不更新”和“更新为 null”。
5. 字段改名时保留旧字段 fallback，避免历史数据整体失效。

## Community

文件：`lib/models/community.dart`

`CommunityUser`、`CommunityMedia`、`CommunityPost` 和 `CommunityComment` 描述远端社区数据；`CommunityPageResult` 表达分页结果。解析同时容忍常见 camelCase/snake_case 字段和字符串/整数 ID，模型不负责网络或页面状态。

## Web Search

文件：`lib/models/web_search.dart`

`WebSearchRequest` 是 provider 无关的公开输入，只包含定长 query、1-10 的结果上限、可选 BCP 47 风格语言标签和 `day`/`month`/`year` 时间范围，不包含 URL、header 或 credential。`WebSearchRoute` 区分 `client`、`backend` 和 `auto`，`WebSearchClientProvider` 只允许已实现的 Tavily/SearXNG 选择。`WebSearchResult` 统一标题、HTTP(S) URL、摘要、可选 score 和发布时间；`WebSearchResponse` 记录实际使用的 provider/route 和规范化结果。provider endpoint 和 secret 属于服务层可信配置，不进入这些模型。

`AppSettings` 保存全局生效的 `agentEnabledByDefault`、权限列表、网页搜索 route、客户端首选 provider、非秘密 SearXNG endpoint，以及默认关闭的 SearXNG HTTP 精确-origin 明文授权。权限是全局单源：主聊天、悬浮聊天运行时的生效权限快照都实时读取这里，设置页“权限管理”和对话设置弹窗编辑的是同一份数据，修改即时作用于所有对话。Tavily key 和 SearXNG bearer token 不属于 `AppSettings`。

## Message 与附件

文件：`lib/models/message.dart`

`Message` 是对话中的一条消息。

| 字段 | 说明 |
|------|------|
| `id` | 消息 ID。 |
| `role` | 常用值为 `user` 或 `assistant`。 |
| `content` | 聊天气泡显示的用户原文或 assistant 正文。 |
| `modelContextContent` | 可选的隐藏文本上下文，保存 OCR、文件识别和可读文本附件展开结果；后续模型请求和同步优先使用，不直接显示。 |
| `images` | 历史字段名，实际表示附件列表。 |
| `thinkingContent` | assistant 的思考内容。 |
| `composerSegments` | 用户消息的编辑器片段（文本与引用交错），用于撤回/编辑时还原引用 Chip；旧消息或纯文本消息为空。 |
| `timestamp` | 消息创建时间。 |

`MessageImage` 保存附件路径、文件名、大小和 MIME 类型。它可以表示图片、PDF、文本、Office 文件或压缩包。字段名 `images` 为兼容旧数据保留。

附件只保存路径和元数据，不把文件内容写入消息 JSON。附件路径为空或本地文件丢失时，附件记录仍保留并由页面显示不可用占位。页面层负责把用户选择的文件复制到应用私有目录。

## 类型化引用

文件：`lib/models/composer_reference.dart`

`ComposerReference` 是命令面板选中的类型化引用，仅携带 `type`（`note`/`note_page`/`task`/`task_list`/`plugin_resource`/`plugin_skill`）、稳定 `id`、本地显示标题与 `qualifiers`。`ComposerReferenceCodec` 唯一负责生成/解析 `<lynai_ref type="..." id="..." .../>`：发送给模型的正文只包含 type/id 与稳定限定字段，不含标题或正文。`ComposerSegment` 区分 `ComposerTextSegment` 与 `ComposerReferenceSegment`，`encodeComposerSegments`/`decodeComposerSegments` 负责消息持久化的序列化。

## Conversation 与设置快照

文件：`lib/models/conversation.dart`

`Conversation` 保存完整对话。

| 字段 | 说明 |
|------|------|
| `id` | 对话 ID。 |
| `title` | 对话标题，通常由第一条用户消息生成。 |
| `messages` | 消息列表。 |
| `modelId` | 当前对话绑定的 Chat 模型 ID。 |
| `settings` | 对话设置快照。 |
| `agentPlan` | 当前 Agent 可视化计划。 |
| `agentWorkingMemory` | 当前对话持久化 Agent 工作记忆，保存目标、关键事实、决策、已加载 Skill 和子任务结果。 |
| `roleId` | 当前角色 ID，用于历史分组。 |
| `createdAt` / `updatedAt` | 创建和更新时间。 |

`ConversationSettings` 保存发送对话所需的模型、系统提示词、OCR、文件识别、图片生成、语音和 Agent 模式。`selectedSystemPromptId` 只保留来源标识，`systemPrompt` 保存选择当时的实际正文；发送历史对话时必须直接使用该正文，不能按当前全局模板重新解析。历史对话也不能反向覆盖全局设置。

权限由 `AppSettings.agentGrantedPermissions` 全局单源管理，`ConversationSettings` 不再保存权限字段（旧的 `agentPermissionsOverride`/`agentGrantedPermissions`/`permissionSnapshotVersion` 在 `fromJson` 时被忽略）。运行时生效快照统一实时读取全局设置，对话设置弹窗与设置页“权限管理”编辑的是同一份全局数据。`LynAIPermissionDefinition` 增加 `pluginAutoGrant` 标记区分插件免授权权限（如 `network:public`）与敏感权限（需用户在权限管理里逐项授权）。

反序列化时坏消息、坏 Agent 计划或坏工作记忆会被跳过；如果整条对话结构损坏，则由 Provider 跳过该对话。

`AgentWorkingMemory` 位于 `lib/models/agent_working_memory.dart`。记忆条目使用 `kind` 区分 `fact`、`decision`、`subagent_result`、`skill_loaded`、`blocker`、`artifact` 和普通 `note`，并限制为短文本，避免把长屏幕快照或二进制内容写入对话上下文。

## Agent Runtime 与持久化记录

文件：`lib/models/agent_runtime.dart`、`lib/models/agent_persistence.dart`、`lib/models/mcp_config.dart`

`AgentRunStatus`、`AgentTurnStatus`、`AgentItemStatus` 和 `AgentToolCallStatus` 描述 run graph 状态。新记录只能从 `queued` 或 `pending` 开始，终态为 `completed`、`failed` 或 `cancelled`；合法迁移由 Repository 校验，数据库更新使用 compare-and-set 防止陈旧写入覆盖终态。

`AgentToolDescriptor` 描述名称、来源、副作用、并发策略和 JSON Schema 参数；`AgentToolInvocation` 携带稳定 call ID、名称、不可变参数和可选 concurrency key；`AgentToolResult` 明确区分 success、failure、cancelled。`AgentModelStreamEvent` 把正文、思考、tool calls、完成和失败标准化，供 direct、managed、流式和非流式 adapter 共用。

`AgentRunRecord`、`AgentTurnRecord`、`AgentItemRecord`、`AgentToolCallRecord` 和 `AgentSnapshotRecord` 是本机 durable run graph 的存储契约。它们不等于 Conversation 中的 `AgentPlan`、`AgentWorkingMemory` 或 trace，也不是备份、云同步、LAN 同步或后端 wire contract。注入 persistence lifecycle 的 `AgentLoopRuntime` 会写入这些记录；未注入时仍可用于聚焦测试。Subagent 的 parent run/turn/tool call 因当前 schema 没有专用关系列而保存在 `parent_run` snapshot metadata。

`AgentMcpServerRecord` 只包含公开连接配置：ID、名称、transport、command 或 URL、stdio 参数、凭据名称引用、启用状态和时间戳。它不包含环境变量值、HTTP header value、credential target、HTTP/私网许可或逐工具开关；这些值由 `SecretStore` 保存。`McpServerConfig` 是连接时构造的运行时配置，包含超时、消息/响应字节上限以及 HTTP 安全开关。

## ModelConfig 与 ModelEntry

文件：`lib/models/model_config.dart`

`ModelConfig` 表示一个模型提供商或接口配置。

| 字段 | 说明 |
|------|------|
| `category` | 用途：`chat`、`ocr`、`speech`、`image_generation`。 |
| `endpoint` | 接口地址或基础地址。 |
| `apiKey` | API Key、AppKey 或其他鉴权信息。 |
| `modelName` | 当前激活的模型名。 |
| `apiType` | 非托管 Provider 的协议类型，例如 OpenAI 兼容、Ollama、Anthropic；托管配置不持久化此字段。 |
| `priority` | 分类内排序。 |
| `models` | 子模型列表。 |
| `extraParams` | 用户自定义请求参数。 |
| `managed` | 是否由 LynAI 后端托管同步。托管配置用于内置 LynAI 中转 Provider，endpoint/API key 不由用户手动维护。 |
| `disabledByUser` | 用户是否在本机关闭该托管配置。关闭后该配置不会被实际模型选择逻辑使用，但仍会继续接收服务端基线同步。 |
| `userOverrides` | 用户对托管配置的本机覆盖项，优先级高于服务端下发值；当前覆盖 `maxTokens`、`temperature`、`topP`、`supportsVision`、`supportsThinking` 和 `supportsTools`。 |
| `cloudSyncEnabled` | 用户是否明确允许同步此非托管 Provider 的非秘密配置，默认 false。托管 Provider 始终由服务端维护，不进入该同步域。 |

`ModelEntry` 是子模型。子模型可以独立设置启用状态、视觉能力、thinking 能力、工具能力、采样参数和 managed workflow。schema 4 下发的 Vivo LASR workflow 保存在对应 speech 子模型上，不提升到配置级。

登录后端后，`ModelConfigProvider` 只从 `/relay/config` 读取 `schemaVersion: 4` 的平铺模型列表，按规范化 `category` 创建一个名为 `LynAI` 的托管配置，ID 形如 `__lynai_relay_<category>__`；schema v3 wire 响应不受支持。托管 endpoint 派生自 `BackendClient.backendUrl + '/relay'`，请求时由 `ApiService` 使用用户 JWT 鉴权，并只发送 `model`。同步会先完整构建下一份托管集合再替换；离线、请求失败或响应无效时保留当前托管数据。相同 category ID 已存在时保留分类内排序、当前模型、本机禁用状态和用户覆盖。旧客户端或备份中持久化的 Provider-scoped 托管 ID 会在本地按 category 合并为当前 ID，保存待处理映射，并迁移设置、对话、情景演绎和插件配置中的精确引用；该本地兼容不恢复 schema v3 网络协议。

Agent 可通过 `model.chat` 调用 Chat 模型，通过 `model.ocr` 调用 OCR 分类模型，通过 `model.recognizeFile` 调用开启视觉能力的 Chat 模型，通过 `model.generateImage` 调用图片生成模型。`model.recognizeFile` 依赖 `supportsVision=true` 的子模型。

`ModelConfig.localOcrId`（`'__local_ppocrv5__'`）是内置本地 OCR 的保留 sentinel ID。当 `imageModelId` 等于此值时，OCR 路径跳过云端 API，直接调用 Android 端 ncnn + PPOCRv5 本地推理（离线、免费、支持 17+ 语言和竖排文字）。该 ID 不对应持久化的 `ModelConfig`，仅在对话设置 UI 中作为虚拟条目显示（仅 Android）。

OCR 悬浮翻译使用请求内轻量文本组。Native OCR 输出 `text`、识别用 `recognitionPolygon/recognitionBounds`、显示用 `polygon/displayBounds`、`orientation`、浮点 `angle`、`fontSize`、`confidence` 以及兼容字段 `bounds/boxW/boxH/prob`。Android `OcrTextGrouper` 按几何关系把 OCR 行合为 `g_N` 文本组，Dart `FloatingTranslationController` 只按组 ID 映射 AI 译文；这些 ID 不用于跨屏缓存。

请求参数优先级：托管配置的 `userOverrides` 高于子模型参数，高于 Provider 参数，高于接口默认值。

## AppSettings、角色和提示词

文件：`lib/models/app_settings.dart`、`chat_role.dart`、`system_prompt.dart`

`AppSettings` 保存跨页面设置。

| 类别 | 字段 |
|------|------|
| 外观 | `themeColor`, `baseThemeColor`, `themeMode`, `backgroundImagePath`, `blurEnabled`, `blurAmount` |
| 模型选择 | `speechModelId`, `imageModelId`, `imageRecognitionModelId`, `imageGenerationModelId`, `lastChatModelId` |
| 图片/文件识别/生成 | `imageOcrEnabled`, `imageRecognitionEnabled`, `imageGenerationEnabled`, `imageRecognitionPrompt` |
| 提示词 | `systemPrompt`, `systemPrompts`, `selectedSystemPromptId` |
| 角色 | `roles`, `roleGroups`, `currentRoleId` |
| 功能页 | `lastFeature` |
| 悬浮助手 | `floatingAssistant`，包含 Android 悬浮聊天、按需读屏、语音输入、翻译入口（多目标语言、源语言检测、覆盖层样式、屏蔽应用包名 `blockedPackages`、专用翻译模型 `translationModelId` 缺省时跟随当前聊天模型）、Agent Plan 显示、气泡/面板位置尺寸持久化（`bubbleX/Y`、`panelX/Y`、`panelWidth/Height`）。`screenContextMode` 仅保留 `manual`/`disabled` 两档，旧的 `ask` 取值在反序列化时回退为 `manual`。 |
| 更新日志 | `lastSeenChangelogVersion` |

`AppSettings.fromJson()` 会跳过坏角色、坏角色分组和坏提示词。缺失默认角色时自动补回；当前角色不存在时回退到默认角色。

云同步不序列化整个 `AppSettings`。`SharedSettingsV1` 是显式版本化投影，只包含主题颜色/模式、背景资源引用、模糊设置、模型选择和识别/生成开关、提示词、角色与角色分组。后端 URL/配置标记、登录与更新日志标记、最近功能页、悬浮助手行为和位置、Agent/系统权限及本地路径均为设备本地字段，远端应用时保留。

`SyncedModelConfigV1` 是逐 Provider 的版本化非秘密投影。仅 `managed=false && cloudSyncEnabled=true` 的用户配置进入 Outbox；`apiKey`、`apiKeySecretRef` 和名称疑似 secret/token/password/credential/authorization 的 `extraParams` 字段不会进入云 payload。Ollama、loopback 和 LAN endpoint 默认仍是设备本地，只有用户明确打开该 Provider 的同步开关才会同步。

`ChatRole` 保存角色名、系统提示词、默认模型和可选主题色。`ChatRoleGroup` 保存角色分组，分组里的角色 ID 会在加载时过滤掉不存在的角色。

## 任务与任务清单

文件：`lib/models/task.dart`、`task_list.dart`、`local_date.dart`、`local_time.dart`、`item_reminder.dart`

`Task` 是任务内容的规范领域对象，独立于清单归属。任务可同时具有计划日期/时间和截止日期/时间；时间只有在对应日期存在时才合法。`completedAt != null` 表示已完成；无截止时间的任务在截止日期结束后才算逾期。

| 字段 | 说明 |
|------|------|
| `id` / `title` / `note` | 稳定 ID、标题和可选备注。 |
| `plannedDate` / `plannedTime` | 可选计划日期与分钟精度本地时间。 |
| `dueDate` / `dueTime` | 可选截止日期与分钟精度本地时间。 |
| `completedAt` | 完成时间；空值表示未完成。 |
| `reminders` | 依附计划或截止锚点的 `ItemReminder` 列表。 |
| `createdAt` / `updatedAt` | 创建和更新时间。 |

`TaskList` 只保存清单元数据和清单间排序，不嵌入任务。`TaskListEntry` 单独表达一个任务的清单归属和清单内位置；`taskId` 是主身份，因此一个任务至多属于一个清单。删除清单不会删除任务实体，任务会成为未归入清单的任务，并按完成状态进入页面聚合视图。

| 类型 | 核心字段 | 语义 |
|------|----------|------|
| `TaskList` | `id`, `title`, `sortOrder`, timestamps | 清单自身信息。 |
| `TaskListEntry` | `taskListId`, `taskId`, `position`, `updatedAt` | 任务与清单的关系和顺序。 |

`LocalDate` 是无时区公历日期，严格使用 `YYYY-MM-DD`；`LocalTime` 是无日期、无时区的分钟精度时间，严格使用 `HH:mm`。日期加减按日历日而不是固定 24 小时处理，组合为 `DateTime` 时才采用设备本地时区。

## 日历事件、纪念日与发生记录

文件：`lib/models/calendar_event.dart`、`anniversary.dart`、`calendar_occurrence.dart`

`CalendarEvent` 使用 sealed `CalendarEventSpec` 区分两种互斥时间规格：

| 规格 | 语义 |
|------|------|
| `TimedCalendarEventSpec` | 精确 `start`/`end`，结束必须晚于开始。 |
| `AllDayCalendarEventSpec` | 本地日期半开区间 `[startDate, endDateExclusive)`；单日事件的结束日期是开始日期下一天。 |

`Anniversary` 使用 sealed `AnniversarySpec` 区分一次性完整日期和每年重复的月日。年度纪念日可保存 `sourceYear` 并显示周年数；没有来源年份时不能启用 `showYearCount`。2 月 29 日的年度纪念日在非闰年投影到 2 月 28 日。

`CalendarOccurrence` 不是持久化权威，而是 `CalendarOccurrenceService` 从事件、任务计划/截止日期和纪念日生成的只读扁平投影。`kind` 可为 `event`、`taskPlanned`、`taskDue`、`taskPlannedAndDue` 或 `anniversary`；同一任务的计划和截止在同一天时合并为一个发生记录。发生记录包含稳定 `occurrenceId`、来源 ID、日期/时间、跨日结束日期以及任务完成/逾期状态。

## ItemReminder

`ItemReminder` 表示相对业务锚点的提醒，不是独立日程。`offsetMinutes` 为有符号分钟数，负数表示提前、正数表示延后；日期型锚点可用 `dateOnlyTime` 指定当天本地触发时间。

| 锚点 | 可用于 |
|------|--------|
| `eventStart` | 日历事件开始。 |
| `taskPlanned` | 任务计划日期/时间。 |
| `taskDue` | 任务截止日期/时间。 |
| `anniversaryDate` | 纪念日发生日期。 |

定时事件或已有计划/截止时间的任务提醒不能再设置 `dateOnlyTime`。模型校验提醒锚点与宿主类型匹配，并拒绝完全相同的重复提醒。系统级提醒投递目前仅由 Android 平台投影实现；其他平台仍会保存和展示提醒数据。

## Note、修订、分页和修改建议

文件：`lib/models/note.dart`

笔记模型分成几类：

| 类型 | 说明 |
|------|------|
| `Note` | 标题、兼容正文、当前修订 ID、当前分页 ID、文件夹引用和自动换行设置。 |
| `NoteFolder` | 文件夹，只保存标题和创建时间。 |
| `NoteRevision` | 不可变 DAG 节点，保存零到两个父修订 ID、分页 ID、设备 ID、内容 blob 哈希和创建时间。 |
| `NoteTextDelta` | 两个版本之间的文本增量。 |
| `NotePageHeads` | 分页当前可达头集合和选中的物化头。 |
| `NotePageConflict` | 未解决冲突的稳定本地/传入头、完整头集合和共同祖先。 |
| `NoteRevisionContent` | 已加载正文或显式缺失状态，避免把缺失 blob 当成空正文。 |
| `NoteEditProposal` | AI 或工具生成的修改建议。 |
| `NoteEditBlock` | 修改建议中的行级块。 |

修订链是树，不是线性历史。用户可以从历史版本另开分支。Provider 负责重放 delta、缓存内容、清理不可达状态和修复缺失修订。

storage_v2 下，笔记分页元数据由存储层的 `StorageV2NotePage` 表达，当前分页正文写入 Markdown 文件，历史修订正文写入 SHA-256 blob。`Note.content` 保留兼容意义，不能把它当成 storage_v2 下唯一正文来源。内容哈希修订必须解析为已加载正文或显式缺失状态，不能静默返回空字符串。

分页删除标记属于 storage_v2 同步布局，不是 `models/` 业务对象。每条记录包含 page ID、revision ID 和创建时间；revision ID 为 `*` 时覆盖整个分页，为具体 ID 时只覆盖对应修订。Provider 加载时据此过滤修订、分页头和冲突，普通保存必须原样保留既有标记。

## 旧规划模型兼容

文件：`lib/models/schedule_item.dart`、`todo_list.dart`、`lib/services/legacy_calendar_conversion_service.dart`

`ScheduleItem`、`TodoList` 和 `TodoItem` 不再是当前任务/日历权威，只用于旧数据库、旧备份、回收站项目和旧工具/Lua API 的导入兼容。`LegacyCalendarConversionService` 将旧普通日程转换为 `CalendarEvent`，将旧任务日程和待办项转换为 `Task`，并把旧嵌入式清单拆成 `TaskList`、`Task`、`TaskListEntry`。新代码不得继续向旧模型建立新的持久化边界。

## Roleplay 模型

文件：`lib/models/roleplay.dart`

情景演绎模型把“可复用情景”和“某次演绎线程”分开。

| 类型 | 说明 |
|------|------|
| `RoleplayScenario` | 情景模板、描述、导演、默认玩家、默认角色、默认分组和自动轮次。 |
| `RoleplayThread` | 某次演绎的情景快照、参与者、分组、消息和更新时间。 |
| `RoleplayDirector` | 导演名、导演系统提示词和模型选择。 |
| `RoleplayParticipant` | 角色名、描述、系统提示词、模型选择、主题色和分组。 |
| `RoleplayParticipantGroup` | 线程或情景内的角色分组。 |
| `RoleplayMessage` | 演绎消息，含说话人、内容、消息类型、附件和时间。 |
| `RoleplayModelSelection` | 角色或导演绑定的模型 ID 和展示名。 |

`RoleplayMessageKind` 区分玩家、AI 角色、系统和旁白。线程保存的是角色快照，后续全局角色配置变化不会自动改写已有线程。

## 插件模型

文件：`lib/models/plugin_models.dart`

插件系统使用以下模型描述插件能力、状态和配置。

`MarketPluginEntry` 与本地 `InstalledPlugin` 分离，保存市场 ID、展示元数据、SemVer 格式版本、下载信息、可选 ZIP SHA-256、分类和审核状态。`MarketQuery` 保存关键词、分类、从 1 开始的页码和 page size；`MarketQueryResult.hasMore` 是页面继续分页的唯一信号。SHA-256 是 ZIP 整体完整性值，不是插件同步内容清单的 package version；客户端下载后校验 manifest ID，但版本新旧判断由市场后端负责。

### PluginToolDefinition

插件目录内 `tools/` 子目录中的 Lua 脚本会注册为 AI 可调用的工具。

| 字段 | 类型 | 说明 |
|------|------|------|
| `name` | `String` | 工具名，模型通过此名称引用工具。 |
| `description` | `String` | 工具描述，写入工具的 schema 供模型理解。 |
| `handler` | `String` | 入口 Lua 函数名，沙箱中 `call(handler, params)`。 |
| `parameters` | `Map<String, dynamic>` | JSON Schema 格式的参数定义，用于校验和提示模型。 |

### PluginFunctionDefinition

与工具不同，函数不暴露给模型，仅用于功能页 WebView 的 JavaScript 桥调用。

| 字段 | 类型 | 说明 |
|------|------|------|
| `name` | `String` | 函数名。 |
| `title` | `String` | 显示名称。 |
| `handler` | `String` | 入口 Lua 函数名。 |

### PluginManifest

`plugin.json` 是每个插件的描述文件，位于插件根目录。

| 字段 | 类型 | 说明 |
|------|------|------|
| `name` | `String` | 插件唯一标识名。 |
| `version` | `String` | 语义版本号。 |
| `dependencies` | `Map<String, String>` | 可选，依赖插件 ID 到版本约束的映射（如 `">=1.0.0"`、`"^2.0.0"`、`"*"`）；不声明即没有依赖。启用插件时要求已声明依赖安装、启用且版本满足约束；运行时会校验已声明依赖的版本。 |
| `entry` | `String` | Lua 入口脚本相对于插件目录的路径。 |
| `tools` | `List<PluginToolDefinition>` | 注册给 AI 模型调用的工具列表。 |
| `skills` | `List<PluginSkillDefinition>` | Agent 可按需加载的 Markdown 工作流说明；`editable` 默认 true，允许用户和模型通过插件文件 overlay 修改 `skills/<name>.md`。 |
| `functions` | `List<PluginFunctionDefinition>` | 注册给功能页 WebView 的内部函数列表。 |
| `commands` | `List<PluginCommandDefinition>` | 命令面板选项源：`handler` 是返回面板选项的 Lua 函数，`model` 可指定选中后本次发送覆盖的模型 ID。 |
| `feature` | `String?` | 可选功能页 HTML 入口路径。没有则功能页入口不可见。 |
| `permissions` | `List<String>` | 声明的权限列表，例如 `network`、`file_read`、`file_write`。 |
| `config` | `PluginConfigSchema?` | 可选配置表单 schema，插件管理页据此渲染配置 UI。 |

### InstalledPlugin

`InstalledPlugin` 是插件运行时的安装状态对象，由 `PluginProvider` 管理。

| 字段 | 类型 | 说明 |
|------|------|------|
| `path` | `String` | 插件在应用支持目录中的安装路径。 |
| `manifest` | `PluginManifest` | 插件的 `plugin.json` 解析结果。 |
| `enabled` | `bool` | 是否启用。禁用的插件不加载脚本、不注册工具和函数。 |
| `devState` | `PluginDevState` | 创作状态：`draft` / `testing` / `active`。草稿与测试中允许编辑核心文件；已定型后核心文件只读，仅 overlay 可写。 |
| `enabledSkills` | `List<String>` | 当前启用的 Skill 名称；纯 Skill 内置插件可在首次同步时自动启用。 |
| `permissions` | `List<String>` | 用户实际授予的权限。可能少于 `manifest.permissions` 声明。 |

### PluginConfigSchema / PluginConfigFieldDefinition

`PluginConfigSchema` 定义插件的配置表单结构，由 `PluginConfigFieldDefinition` 列表组成。

| 字段 | 类型 | 说明 |
|------|------|------|
| `key` | `String` | 配置项键名，写入插件配置 JSON。 |
| `type` | `String` | 字段类型：`text`、`number`、`toggle`、`select`、`secret`。 |
| `label` | `String` | 字段展示标签。 |
| `default` | `dynamic` | 默认值。 |
| `required` | `bool` | 是否必填。 |
| `validation` | `Map<String, dynamic>?` | 可选的校验规则，例如 `min`/`max`、正则 `pattern`、`options` 列表。 |

## Changelog 模型

文件：`lib/models/changelog_entry.dart`

`ChangelogEntry` 表示一个版本的更新日志，包含版本字符串、日期和多个 `ChangelogSection`。解析逻辑在 `ChangelogParser`，模型只表达解析结果。

## 备份模型

文件：`lib/models/backup_models.dart`

备份模型描述用户选择、读取结果、预览和导入计划。

| 类型 | 说明 |
|------|------|
| `BackupSection` | 可备份分区：设置、对话、笔记、规范任务、规范日历、情景演绎和插件。 |
| `BackupSettingsPart` | 设置内部细分：API、外观、对话设置、角色与提示词。 |
| `BackupSelection` | 用户选择的分区和具体条目。 |
| `BackupData` | 读取 ZIP 后得到的结构化数据。 |
| `BackupArchiveData` | manifest、警告、数据、资源和附件文件。 |
| `BackupPreview` | 导入前预览。 |
| `ImportPlan` | 导入模式、选择和冲突动作。 |
| `ImportResult` | 新增、覆盖、跳过统计。 |

备份模型不直接读写文件。实际 ZIP 处理在 `BackupService`。

## storage_v2 辅助模型

storage_v2 的数据库行、笔记分页和资源注册表定义在 `lib/services/storage_v2_service.dart` 和 `storage_v2_database.dart`。这些类型靠近存储层，不放在 `models/`，因为它们描述的是持久化布局，不是 UI 直接操作的业务对象。

## 兼容旧数据

| 位置 | 兼容行为 |
|------|----------|
| `MessageImage` | 兼容旧字段 `filePath`。 |
| `ConversationSettings` | 旧字段 `imagePrompt` 可作为 `imageRecognitionPrompt` fallback。 |
| `AppSettings` | 缺失默认角色时补回，坏角色/分组/提示词跳过。 |
| `ScheduleItem` / `TodoList` | 只在旧数据库、旧备份、旧回收站或旧 API 输入中解析，再转换为规范任务/日历模型。`ScheduleItem` 缺失 `kind` 时按旧普通日程处理。 |
| `Note` | 缺失 `wrap` 时默认自动换行。 |
| `RoleplayMessage` | 附件兼容旧字段 `images`。 |

新增字段时应优先提供默认值或 fallback，而不是强制旧 JSON 必须包含新字段。
# Plugin Review Metadata

`InstalledPlugin.needsReview` records that third-party executable content arrived from another device and still requires explicit local review. `InstalledPlugin.syncOriginScope` records the exact cloud-account or LAN scope that created the local installation. A validated package tombstone may remove only an installation with the same scope provenance; missing or legacy provenance fails closed. `syncedOrigin` remains serialization compatibility metadata and is not sufficient to authorize deletion. None of these fields grants permissions or enables capabilities.
## LAN Models

- `LanPeer` stores the trusted Ed25519 device identity, pinned TLS SPKI,
  display metadata, trust time, acknowledgement metadata, revocation state, and
  the bilateral `SyncDataSelection`. Legacy records default to the ordinary
  non-static categories.
- `LanPairingSession` stores a short-lived, atomically consumed pairing nonce.
- `LanPairingPayload` is the versioned QR contract containing device ID/public
  key, signed SPKI binding, addresses, port, expiry, and one-time nonce.
## Conversation Permission Snapshots

`ConversationSettings` serializes an explicit permission snapshot version and
the complete Agent permission list, including an empty list. New conversations
copy the current global defaults. Conversations written before the version
field existed are marked as legacy while decoding and receive the then-current
global defaults once during startup migration; later global changes do not
rewrite that conversation snapshot.
## PhysicalDatasetIdentity

`PhysicalDatasetIdentity` distinguishes the permanent local dataset from an
account dataset. Account identity uses normalized backend origin and the opaque
backend user ID; the directory ID is the complete SHA-256 hex digest, with no
truncation. Dataset metadata repeats and validates this identity to fail closed
on directory or registry ownership mismatch.
# 知识库与标注

知识库数据由 `KnowledgeBase`、`KnowledgeCategory`、`KnowledgeEntry`、`KnowledgeSource` 和 `KnowledgeExplanation` 组成。类别使用全局唯一的稳定 `alias`，配置标注规则、解释提示词、颜色、自动标注状态及目标知识库；模型不再包含 `isDefault`，客户端也没有用户可配置的默认知识库或默认类别。固定 ID 的内置“专有名词知识库”和“专有名词”类别使用 `proper_noun` alias，首次加载或完整替换后幂等补齐，已有内置行不覆盖用户修改；alias 冲突时保留内置 alias，并按稳定类别 ID 确定性重命名冲突项。聊天和情景演绎角色回复只使用 `[[category:text]]`，不接受管道分隔的 Wiki 链接语法；未知 alias 仅在该内置类别及其知识库启用且类别开启自动标注时回落。内置行可编辑和停用、不可删除，恢复模板时保留启用状态、排序、创建时间及所有用户条目、来源和解释。用户点击标注后自动解释，成功结果保存为知识条目、来源和解释；普通选区释义由用户决定是否保存。记忆卡片尚无持久化契约，因此知识页面不展示未实现入口。

## Jotting 随记

文件：`lib/models/jotting.dart`

`Jotting` 描述一条时间序列随记：`id`、`content`（Markdown 原文）、`tags`（归一化小写标签）、`createdAt`、`updatedAt`。标签通过 `Jotting.normalizeTags` 归一化：trim、小写、去重、丢弃空标签，单个标签最长 32 字符，每条最多 20 个标签。`toJson()` 使用 UTC ISO-8601 时间；`fromJson()` 对缺失或非 List 的 `tags` 视为空列表。

## 回收站类型

文件：`lib/models/recycle_bin_item.dart`

新增 `RecycleBinItemTypes.jotting` 与 `RecycleBinCategories.jottings`，随记删除后进入回收站，payload 保存完整 `jotting` JSON。
