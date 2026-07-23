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

## Message 与附件

文件：`lib/models/message.dart`

`Message` 是对话中的一条消息。

| 字段 | 说明 |
|------|------|
| `id` | 消息 ID。 |
| `role` | 常用值为 `user` 或 `assistant`。 |
| `content` | 可渲染、可发送给文本模型的正文。 |
| `images` | 历史字段名，实际表示附件列表。 |
| `thinkingContent` | assistant 的思考内容。 |
| `timestamp` | 消息创建时间。 |

`MessageImage` 保存附件路径、文件名、大小和 MIME 类型。它可以表示图片、PDF、文本、Office 文件或压缩包。字段名 `images` 为兼容旧数据保留。

附件只保存路径和元数据，不把文件内容写入消息 JSON。页面层负责把用户选择的文件复制到应用私有目录。

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

`ConversationSettings` 保存发送对话所需的模型、系统提示词、OCR、文件识别、图片生成和语音配置。`selectedSystemPromptId` 只保留来源标识，`systemPrompt` 保存选择当时的实际正文；发送历史对话时必须直接使用该正文快照，不能按当前全局模板重新解析。历史对话也不能反向覆盖全局设置。

反序列化时坏消息、坏 Agent 计划或坏工作记忆会被跳过；如果整条对话结构损坏，则由 Provider 跳过该对话。

`AgentWorkingMemory` 位于 `lib/models/agent_working_memory.dart`。记忆条目使用 `kind` 区分 `fact`、`decision`、`subagent_result`、`skill_loaded`、`blocker`、`artifact` 和普通 `note`，并限制为短文本，避免把长屏幕快照或二进制内容写入对话上下文。

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

`ModelEntry` 是子模型。子模型可以独立设置启用状态、视觉能力、thinking 能力、工具能力、采样参数和 managed workflow。schema 3 下发的 Vivo LASR workflow 保存在对应 speech 子模型上，不提升到 Provider 级。

登录后端后，`ModelConfigProvider` 只从 `/relay/config` 读取 `schemaVersion: 3` 的 provider -> models 配置，按 `providerId + category` 创建稳定的托管分组。托管 Provider 的 endpoint 派生自 `BackendClient.backendUrl + '/relay'`，请求时由 `ApiService` 使用用户 JWT 鉴权，并发送 `providerId + model`。旧 managed 分组在本地加载时即可按 provider/category 规范化 ID，并生成精确 `oldId -> newId` pending 映射；该映射随模型配置持久化，Settings、Conversation、Roleplay 和插件配置全部保存成功后才确认删除，失败可在下次入口重试。未登录和 401 不删除本地 managed 配置或 pending 映射。旧 `relayProtocolVersion` 字段读取时自然忽略。

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

`TaskList` 只保存清单元数据和清单间排序，不嵌入任务。`TaskListEntry` 单独表达一个任务的清单归属和清单内位置；`taskId` 是主身份，因此一个任务至多属于一个清单。删除清单不会删除任务实体，任务会成为未归类任务。

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
| `entry` | `String` | Lua 入口脚本相对于插件目录的路径。 |
| `tools` | `List<PluginToolDefinition>` | 注册给 AI 模型调用的工具列表。 |
| `skills` | `List<PluginSkillDefinition>` | Agent 可按需加载的 Markdown 工作流说明；`editable` 默认 true，允许用户和模型通过插件文件 overlay 修改 `skills/<name>.md`。 |
| `functions` | `List<PluginFunctionDefinition>` | 注册给功能页 WebView 的内部函数列表。 |
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
  display metadata, trust time, acknowledgement metadata, and revocation state.
- `LanPairingSession` stores a short-lived, atomically consumed pairing nonce.
- `LanPairingPayload` is the versioned QR contract containing device ID/public
  key, signed SPKI binding, addresses, port, expiry, and one-time nonce.
