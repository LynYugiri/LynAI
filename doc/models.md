# 数据模型

`lib/models/` 是项目的数据契约层。模型负责表达业务数据、JSON 读写和旧字段兼容，不负责页面交互、网络请求或本地持久化。

## 设计原则

1. 模型只描述数据。
2. `fromJson()` 要兼容旧字段、缺失字段和可恢复的坏数据。
3. `toJson()` 尽量不写空值或默认值。
4. 可清空字段的 `copyWith()` 使用 sentinel，区分“不更新”和“更新为 null”。
5. 字段改名时保留旧字段 fallback，避免历史数据整体失效。

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

`ConversationSettings` 保存发送对话所需的模型、系统提示词、OCR、文件识别、图片生成和语音配置。历史对话必须保存自己的设置快照，否则全局设置改变后旧对话上下文也会变化。

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
| `apiType` | 协议类型，例如 OpenAI 兼容、Ollama、Anthropic。 |
| `priority` | 分类内排序。 |
| `models` | 子模型列表。 |
| `extraParams` | 用户自定义请求参数。 |
| `managed` | 是否由 LynAI 后端托管同步。托管配置用于内置 LynAI 中转 Provider，endpoint/API key 不由用户手动维护。 |

`ModelEntry` 是子模型。子模型可以独立设置启用状态、视觉能力、thinking 能力、工具能力和采样参数。

登录后端后，`ModelConfigProvider` 会按 `/relay/models` 返回的 `api_type` 自动同步 `managed=true` 的 LynAI Chat Provider。托管 Provider 的 endpoint 派生自 `BackendClient.backendUrl + '/relay'`，请求时由 `ApiService` 使用用户 JWT 鉴权并在 JSON body 中注入 `api_type`。

Agent 可通过 `model.chat` 调用 Chat 模型，通过 `model.ocr` 调用 OCR 分类模型，通过 `model.recognizeFile` 调用开启视觉能力的 Chat 模型，通过 `model.generateImage` 调用图片生成模型。`model.recognizeFile` 依赖 `supportsVision=true` 的子模型。

`ModelConfig.localOcrId`（`'__local_ppocrv5__'`）是内置本地 OCR 的保留 sentinel ID。当 `imageModelId` 等于此值时，OCR 路径跳过云端 API，直接调用 Android 端 ncnn + PPOCRv5 本地推理（离线、免费、支持 17+ 语言和竖排文字）。该 ID 不对应持久化的 `ModelConfig`，仅在对话设置 UI 中作为虚拟条目显示（仅 Android）。

OCR 悬浮翻译流水线使用一个未单独建模型的轻量块字典（`FloatingChatSessionController.normalizeOcrBlock` 产出）。Native OCR (`ocr_jni.cpp::objects_to_json`) 输出的字段：`text`（合成后的文字）、`bounds{left,top,right,bottom}`（AABB，原始 screenshot px）、`orientation`（0=横排，1=竖排）、`boxW/boxH`（PPOCRv5 检测阶段 `RotatedRect.size` 经 `enlarge_ratio = kEnlargeRatio = 1.95` 反算还原后的文本框宽/高，screenshot px）、`fontSize`（按 orientation 选出的字形方向像素高度，与 boxW/boxH 同源）、`angle`（rrect 角度，整数度）、`prob`（置信度）。Kotlin `NcnnOcrRecognizer.parseJson` 与 Dart `normalizeOcrBlock` 均透传这些字段；`id` 由 Dart 端按 `originalText|l,t,r,b`（~8px 容差）哈希生成，与 `fontSize/boxW/boxH/angle` 无关，保证跨帧稳定。

请求参数优先级：子模型参数高于 Provider 参数，高于接口默认值。

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

`ChatRole` 保存角色名、系统提示词、默认模型和可选主题色。`ChatRoleGroup` 保存角色分组，分组里的角色 ID 会在加载时过滤掉不存在的角色。

## ScheduleItem

文件：`lib/models/schedule_item.dart`

`ScheduleItem` 同时表示普通日程和任务类日程。

| 字段 | 说明 |
|------|------|
| `id` | 日程 ID。 |
| `title` | 标题。 |
| `start` / `end` | 本地时间。 |
| `note` | 可选备注。 |
| `kind` | `schedule` 或 `task`。 |

时间读写都会转成本地时间，避免 API 或工具传入带时区字符串后在 UI 上错位。月/周/年视图按日期区间相交展示跨天日程。

## Note、修订、分页和修改建议

文件：`lib/models/note.dart`

笔记模型分成几类：

| 类型 | 说明 |
|------|------|
| `Note` | 标题、兼容正文、当前修订 ID、当前分页 ID、文件夹引用和自动换行设置。 |
| `NoteFolder` | 文件夹，只保存标题和创建时间。 |
| `NoteRevision` | 时间线节点，保存父修订 ID、分页 ID、保存时间和 delta。 |
| `NoteTextDelta` | 两个版本之间的文本增量。 |
| `NoteEditProposal` | AI 或工具生成的修改建议。 |
| `NoteEditBlock` | 修改建议中的行级块。 |

修订链是树，不是线性历史。用户可以从历史版本另开分支。Provider 负责重放 delta、缓存内容、清理不可达状态和修复缺失修订。

storage_v2 下，笔记分页元数据由存储层的 `StorageV2NotePage` 表达，分页正文写入 Markdown 文件。`Note.content` 保留兼容意义，不能把它当成 storage_v2 下唯一正文来源。

## TodoList 与 TodoItem

文件：`lib/models/todo_list.dart`

`TodoList` 保存清单标题、任务列表和时间戳。`TodoItem` 保存任务文本和完成状态。Markdown 导入导出、长图分享和拖拽排序在页面层完成，模型层只保存结果数据。

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
| `BackupSection` | 可备份分区：设置、对话、笔记、日程、待办、情景演绎。 |
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
| `ScheduleItem` | 缺失 `kind` 时作为普通日程。 |
| `Note` | 缺失 `wrap` 时默认自动换行。 |
| `RoleplayMessage` | 附件兼容旧字段 `images`。 |

新增字段时应优先提供默认值或 fallback，而不是强制旧 JSON 必须包含新字段。
