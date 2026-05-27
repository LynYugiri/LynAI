# 数据模型

`lib/models/` 是项目的数据契约层。这里的类应该保持可序列化、可兼容旧数据，并尽量避免混入页面逻辑或网络逻辑。

## 设计原则

1. 模型只描述数据，不主动读写本地存储。
2. `fromJson()` 必须考虑旧字段、缺失字段和可恢复的坏数据。
3. `toJson()` 不写入空值或默认值，减少本地 JSON 体积。
4. `copyWith()` 对可清空字段使用 sentinel，区分“不更新”和“更新为 null”。

## Message 与附件

文件：`lib/models/message.dart`

`Message` 是对话中的一条消息。

| 字段 | 说明 |
|------|------|
| `id` | 消息 ID。 |
| `role` | 当前使用 `user` 或 `assistant`。 |
| `content` | 可直接发给文本模型或渲染的正文。 |
| `images` | 历史字段名，实际表示附件列表。 |
| `thinkingContent` | assistant 的可见思考内容。 |
| `timestamp` | 消息创建时间。 |

`MessageImage` 保存附件路径、文件名、大小和 MIME 类型。字段名叫 `images` 是为了兼容旧数据；现在它既可以表示图片，也可以表示 PDF、文本、Office 文件或压缩包。

附件只保存路径和元数据，不把文件内容写进对话 JSON。页面层会把附件复制到应用私有目录，避免历史消息引用系统临时文件。

## Conversation 与设置快照

文件：`lib/models/conversation.dart`

`Conversation` 保存完整对话。

| 字段 | 说明 |
|------|------|
| `title` | 对话标题，通常由第一条用户消息生成。 |
| `messages` | 消息列表。 |
| `modelId` | 当前对话绑定的模型配置 ID。 |
| `settings` | 对话设置快照。 |
| `roleId` | 当前角色 ID，用于历史分组。 |
| `createdAt` / `updatedAt` | 创建和更新时间。 |

`ConversationSettings` 保存发送对话所需的模型、系统提示词、OCR、文件识别和语音配置。历史对话必须保存自己的设置快照，否则全局设置改变后旧对话上下文也会被改变。

反序列化时，坏消息会被跳过；如果整条对话结构损坏，则由 Provider 跳过该对话。

## ModelConfig 与 ModelEntry

文件：`lib/models/model_config.dart`

`ModelConfig` 表示一个模型提供商或一个接口配置。

| 字段 | 说明 |
|------|------|
| `category` | 用途：`chat`、`ocr`、`speech`、`image_generation`。 |
| `endpoint` | 接口地址或基础地址。 |
| `apiKey` | 密钥或 AppKey。 |
| `modelName` | 当前激活的子模型名。 |
| `apiType` | 协议类型，例如 `openai`、`ollama`、`anthropic`。 |
| `priority` | 分类内排序。 |
| `models` | 子模型列表。 |
| `extraParams` | 用户自定义请求参数。 |

`ModelEntry` 是子模型。子模型可以独立设置是否启用、是否支持视觉、是否支持 thinking、是否支持工具，以及采样参数。

请求参数优先级为：子模型参数高于 Provider 参数，高于接口默认值。

## AppSettings、角色和提示词

文件：`lib/models/app_settings.dart`、`chat_role.dart`、`system_prompt.dart`

`AppSettings` 保存跨页面设置。

| 类别 | 字段 |
|------|------|
| 外观 | `themeColor`, `baseThemeColor`, `themeMode`, `backgroundImagePath`, `blurEnabled`, `blurAmount` |
| 模型选择 | `speechModelId`, `imageModelId`, `imageRecognitionModelId`, `lastChatModelId` |
| 图片/文件识别 | `imageOcrEnabled`, `imageRecognitionEnabled`, `imageRecognitionPrompt` |
| 提示词 | `systemPrompt`, `systemPrompts`, `selectedSystemPromptId` |
| 角色 | `roles`, `currentRoleId` |
| 功能页 | `lastFeature` |

`AppSettings.fromJson()` 会跳过坏角色和坏提示词，缺失默认角色时自动补回。如果当前角色不存在，会回退到 `default`。

`ChatRole` 保存角色名、系统提示词、默认模型和可选主题色。选择角色时，设置页会同步系统提示词、默认模型和主题色。

## ScheduleItem

文件：`lib/models/schedule_item.dart`

`ScheduleItem` 同时表示普通日程和任务类日程。

| 字段 | 说明 |
|------|------|
| `title` | 标题。 |
| `start` / `end` | 本地时间。 |
| `note` | 可选备注。 |
| `kind` | `schedule` 或 `task`。 |

时间读写都会转成本地时间，避免 API 或工具传入带时区字符串后在 UI 上错位。月/周/年视图按日期区间相交展示跨天日程。

## Note、修订和修改建议

文件：`lib/models/note.dart`

笔记模型分成几个部分：

| 类型 | 说明 |
|------|------|
| `Note` | 当前标题、当前正文、当前修订 ID、文件夹引用和自动换行设置。 |
| `NoteFolder` | 文件夹，只保存标题和创建时间。 |
| `NoteRevision` | 时间线节点，保存父修订 ID、保存时间、摘要和 delta。 |
| `NoteTextDelta` | 两个版本之间的文本增量。 |
| `NoteEditProposal` | AI 或工具生成的修改建议。 |
| `NoteEditBlock` | 修改建议中的行级块。 |

修订链是树，不是线性历史。用户可以从历史版本另开分支。Provider 负责重放 delta、缓存内容、清理不可达状态和修复缺失修订。

`NoteTextDelta` 通过最长公共前后缀生成。它能从父版本 apply 到子版本，也能从子版本 revert 回父版本。

## TodoList 与 TodoItem

文件：`lib/models/todo_list.dart`

`TodoList` 保存清单标题、任务列表和时间戳。`TodoItem` 保存任务文本和完成状态。

待办清单的 Markdown 导入导出、长图分享和拖拽排序都在页面层完成，模型层只保存结果数据。

## 备份模型

文件：`lib/models/backup_models.dart`

备份相关模型描述用户选择、读取结果、预览和导入计划。

| 类型 | 说明 |
|------|------|
| `BackupSection` | 可备份分区：设置、对话、笔记、日程、待办。 |
| `BackupSettingsPart` | 设置内部的细分选择。 |
| `BackupSelection` | 用户选择的分区和具体条目。 |
| `BackupData` | 读取 ZIP 后得到的结构化数据。 |
| `BackupArchiveData` | manifest、警告、数据和附件文件。 |
| `BackupPreview` | 导入前预览。 |
| `ImportPlan` | 导入模式、选择和冲突动作。 |
| `ImportResult` | 新增、覆盖、跳过统计。 |

备份模型只描述计划和数据，不直接读写文件。实际 ZIP 处理在 `BackupService`。

## 兼容旧数据的注意事项

| 位置 | 兼容行为 |
|------|----------|
| `MessageImage` | 兼容旧字段 `filePath`。 |
| `ConversationSettings` | 旧字段 `imagePrompt` 可作为 `imageRecognitionPrompt` fallback。 |
| `AppSettings` | 缺失默认角色时补回，坏角色/提示词跳过。 |
| `ScheduleItem` | 缺失 `kind` 时作为普通日程。 |
| `Note` | 缺失 `wrap` 时默认自动换行。 |

新增字段时应优先给出默认值，而不是强制旧 JSON 必须包含新字段。
