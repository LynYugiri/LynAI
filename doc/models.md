# 数据模型

`lib/models/` 中的模型都是 Provider 和 Service 之间的稳定数据契约，主要目标是 JSON 序列化、不可变更新和旧数据兼容。

## Conversation 与 Message

### `Message`

文件：`lib/models/message.dart`

```dart
class Message {
  final String id;
  final String role;
  final String content;
  final List<MessageImage> images;
  final String? thinkingContent;
  final DateTime timestamp;
}
```

| 字段 | 说明 |
|------|------|
| `role` | 当前只使用 `user` 和 `assistant` |
| `content` | 可直接发送给文本模型的内容 |
| `images` | 历史字段名，实际表示附件列表，包含图片和非图片文件 |
| `thinkingContent` | assistant 思考内容，可从流式 reasoning、Anthropic thinking、Ollama `<think>` 等来源恢复 |

`MessageImage` 保存 `path`、`name`、`size`、`mimeType`。反序列化兼容旧字段 `filePath`，并可从路径推导文件名和 MIME 类型。附件只保存路径和元数据，不把文件内容嵌入对话 JSON。

### `Conversation`

文件：`lib/models/conversation.dart`

```dart
class Conversation {
  final String id;
  final String title;
  final List<Message> messages;
  final String modelId;
  final ConversationSettings settings;
  final String roleId;
  final DateTime createdAt;
  final DateTime updatedAt;
}
```

`Conversation.fromJson()` 会逐条解析消息，损坏消息会被跳过，避免单条坏消息导致整个对话不可见。

### `ConversationSettings`

```dart
class ConversationSettings {
  final String modelId;
  final bool thinking;
  final String? selectedSystemPromptId;
  final String systemPrompt;
  final String? speechModelId;
  final String? imageModelId;
  final bool imageOcrEnabled;
  final String? imageRecognitionModelId;
  final bool imageRecognitionEnabled;
  final String imageRecognitionPrompt;
}
```

每个历史对话保存自己的设置快照。切回历史对话时，`SettingsProvider.applyConversationSettings()` 会把快照同步给 UI 控件，避免全局设置覆盖历史上下文。

## ModelConfig 与 ModelEntry

文件：`lib/models/model_config.dart`

```dart
class ModelEntry {
  final String name;
  final bool enabled;
  final bool supportsVision;
  final bool supportsThinking;
  final bool supportsTools;
  final int? maxTokens;
  final double? temperature;
  final double? topP;
}

class ModelConfig {
  final String id;
  final String name;
  final String category;
  final String endpoint;
  final String apiKey;
  final String modelName;
  final String apiType;
  final int priority;
  final List<ModelEntry> models;
  final int? maxTokens;
  final double? temperature;
  final double? topP;
  final Map<String, dynamic> extraParams;
}
```

| 常量 | 值 | 用途 |
|------|----|------|
| `ModelConfig.categoryChat` | `chat` | 对话、文件识别、多模态和工具调用 |
| `ModelConfig.categoryOcr` | `ocr` | vivo OCR |
| `ModelConfig.categorySpeech` | `speech` | vivo 长语音转写 |
| `ModelConfig.categoryImageGeneration` | `image_generation` | OpenAI Images 或 vivo 图片生成 |

`modelName` 是当前激活子模型名。`activeEntry` 会优先找到同名 `ModelEntry`，找不到时回退到第一个子模型。请求参数读取 `effectiveMaxTokens`、`effectiveTemperature`、`effectiveTopP`，优先级为当前子模型参数高于提供商级参数。

`supportsVision`、`supportsThinking`、`supportsTools` 由当前激活子模型决定，用于控制多模态内容、思考开关和工具调用。`copyWith()` 对 nullable 参数使用 sentinel，允许把高级参数显式清空为 `null`。

## AppSettings、角色和提示词

文件：`lib/models/app_settings.dart`、`chat_role.dart`、`system_prompt.dart`

```dart
class AppSettings {
  final Color themeColor;
  final Color baseThemeColor;
  final String? backgroundImagePath;
  final bool blurEnabled;
  final double blurAmount;
  final String? speechModelId;
  final String? imageModelId;
  final bool imageOcrEnabled;
  final String? imageRecognitionModelId;
  final bool imageRecognitionEnabled;
  final String? lastChatModelId;
  final String imageRecognitionPrompt;
  final String systemPrompt;
  final List<SystemPrompt> systemPrompts;
  final String? selectedSystemPromptId;
  final String themeMode;
  final List<ChatRole> roles;
  final String currentRoleId;
  final String lastFeature;
}
```

| 字段 | 说明 |
|------|------|
| `themeColor` | 当前 Material 3 seed color |
| `baseThemeColor` | HSV 调色板的基础色 |
| `lastFeature` | 功能页最近入口：`history`、`schedule`、`notes`、`todos` |
| `roles` | 聊天角色，至少包含 `default` |
| `systemPrompts` | 可复用系统提示词模板 |

`AppSettings.fromJson()` 对角色和提示词逐条容错；缺失默认角色时自动补回；`currentRoleId` 指向不存在角色时回退到 `default`。旧字段 `imagePrompt` 会作为 `imageRecognitionPrompt` fallback。

`ChatRole` 保存角色名、系统提示词、默认模型和可选主题色。选择角色时会同步系统提示词、默认模型和主题色，新建对话会绑定当前角色。

## 日程模型

文件：`lib/models/schedule_item.dart`

```dart
class ScheduleItem {
  final String id;
  final String title;
  final DateTime start;
  final DateTime end;
  final String? note;
  final String kind;
}
```

`kind` 区分普通日程和任务类日程。反序列化、工具参数解析和工具返回值都会把时间转为本地时间，避免 `Z` 或显式时区偏移在 UI 中错位。月/周/年视图按日期区间相交展示跨天日程。

## 笔记模型

文件：`lib/models/note.dart`

```dart
class Note {
  final String id;
  final String title;
  final String content;
  final String? currentRevisionId;
  final String? folderId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool wrap;
}
```

| 类型 | 说明 |
|------|------|
| `Note` | 当前笔记内容、当前修订、文件夹引用和自动换行设置 |
| `NoteFolder` | 笔记文件夹 |
| `NoteRevision` | 单次保存的增量修订，包含父修订 ID 和 `NoteTextDelta` |
| `NoteTextDelta` | 通过最长公共前后缀计算出的文本增量，可 apply/revert |
| `NoteEditProposal` | AI 或工具生成的分块修改建议 |
| `NoteEditBlock` | 修改建议中的行级插入/删除块 |

Provider 会维护修订内容缓存和时间线缓存。加载时会修复缺失修订、缺失文件夹引用等可恢复状态。

## 待办模型

文件：`lib/models/todo_list.dart`

```dart
class TodoList {
  final String id;
  final String title;
  final List<TodoItem> items;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class TodoItem {
  final String id;
  final String text;
  final bool done;
}
```

待办清单支持多清单、任务勾选、拖拽排序、Markdown 任务列表导入导出和长图分享。

## 备份模型

文件：`lib/models/backup_models.dart`

| 类型 | 说明 |
|------|------|
| `BackupSection` | 设置、对话、笔记、日程、待办五个备份分区 |
| `BackupSettingsPart` | API 配置、外观、对话设置、角色与提示词四个设置子分区 |
| `BackupSelection` | 用户选择的导出或导入范围，包含分区和具体 ID 集合 |
| `BackupData` | 读取备份后的结构化数据 |
| `BackupArchiveData` | manifest、结构化数据、警告和附件文件内容 |
| `BackupPreview` | 导入前预览信息和冲突列表 |
| `ImportPlan` | 导入模式和冲突处理动作 |
| `ImportResult` | 导入统计：新增、替换、跳过、警告 |

导入模式包括合并询问、只添加新数据、替换所选分类。冲突动作包括保留本地、使用导入、两者保留。
