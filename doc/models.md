# 数据模型

所有模型均支持 `fromJson()` / `toJson()` JSON序列化。

---

## Message
**文件**: `lib/models/message.dart`

```dart
class Message {
  final String id;       // UUID v4
  final String role;     // "user" | "assistant"
  final String content;  // 消息文本
  final List<MessageImage> images; // 图片附件，保存应用私有目录路径
  final String? thinkingContent;   // assistant 思考过程，可持久化恢复
  final DateTime timestamp;
}
```

不可变类, 通过构造函数创建新实例进行更新。`thinkingContent` 用于保存流式和工具调用返回的 reasoning，切换历史对话或重试版本后仍可显示。

### MessageImage

```dart
class MessageImage {
  final String path; // 应用私有目录中的图片路径
  final String name; // 原始或安全化后的文件名
  final int size;    // 文件大小，单位 byte
}
```

图片附件不嵌入 JSON，只保存路径和元数据。选图或粘贴图片时会先复制到应用私有目录，降低历史消息图片丢失概率。重试历史会记录对应用户消息的图片列表，切换重试版本时同步恢复。

---

## Conversation
**文件**: `lib/models/conversation.dart`

```dart
class Conversation {
  final String id;
  final String title;              // 对话标题(首个user消息截取前20字符, 未发送消息时为"新对话 N")
  final List<Message> messages;
  final String modelId;            // 关联的ModelConfig.id
  final ConversationSettings settings; // 对话级设置快照
  final String roleId;             // 关联的ChatRole.id
  final DateTime createdAt;
  final DateTime updatedAt;
}
```

**计算属性**: `preview` → 第一条消息内容摘要(限80字符, 去除换行)

不可变类, Provider 中通过创建新 Conversation 实例来更新消息列表。

### ConversationSettings

```dart
class ConversationSettings {
  final String modelId;
  final bool thinking;
  final String? selectedSystemPromptId;
  final String systemPrompt;
  final String? speechModelId;
  final String? imageModelId;
  final String? imageRecognitionModelId;
  final bool imageRecognitionEnabled;
  final String imageRecognitionPrompt;
}
```

每个对话保存自己的模型和辅助能力设置。切换历史对话时，应用会恢复该对话的设置快照。

### ChatRole
**文件**: `lib/models/chat_role.dart`

```dart
class ChatRole {
  final String id;
  final String name;
  final String systemPrompt;
  final String? modelId;
  final Color? themeColor;
}
```

角色用于隔离不同使用场景。新建对话会绑定当前角色ID，并继承该角色的系统提示词、可选默认模型和可选主题色。默认角色ID为 `default`。

---

## ModelConfig & ModelEntry
**文件**: `lib/models/model_config.dart`

```dart
class ModelEntry {
  final String name;     // 模型名称, 如 "deepseek-chat"
  final bool enabled;    // 是否启用(对话中可选)
}

class ModelConfig {
  final String id;
  final String name;              // 提供商显示名, 如 "DeepSeek"
  final String category;          // "chat" | "ocr" | "speech" | "image_generation"
  final String endpoint;          // API端点, 如 "https://api.deepseek.com"
  final String apiKey;
  final String modelName;         // 当前激活的模型名(默认取第一个enabled模型)
  final String apiType;           // openai/ollama/anthropic/custom/openai_image/vivo_image 等
  final int priority;             // 优先级别(数字越小优先级越高)
  final List<ModelEntry> models;  // 该提供商下所有模型(默认为含modelName的单元素列表)
  final int? maxTokens;           // 高级选项: 最大token数
  final double? temperature;      // 高级选项: 温度参数
  final double? topP;             // 高级选项: Top P
  final Map<String, dynamic> extraParams;  // 额外API参数, 不会覆盖已设置的字段
}
```

**计算属性**:
- `enabledModelNames` → 所有 enabled=true 的模型名称列表
- `hasMultipleModels` → models.length > 1

**分类常量**:
- `ModelConfig.categoryChat` → 对话模型
- `ModelConfig.categoryOcr` → OCR 接口
- `ModelConfig.categorySpeech` → 语音转文字接口
- `ModelConfig.categoryImageGeneration` → 图片生成接口

**构造器**: 若未传入 `models`, 自动创建含 `modelName` 的单元素列表(默认enabled)。`extraParams` 默认为空Map。

**copyWith()**: 支持所有字段的可选覆盖, 用于不可变更新。

**JSON**: `temperature` 和 `topP` 在JSON中作为num类型处理(支持int和double), `priority` 为int, `models` 数组的每个元素含name和enabled。

---

## AppSettings
**文件**: `lib/models/app_settings.dart`

```dart
class AppSettings {
  final Color themeColor;            // 主题色(默认Colors.blue)
  final String? backgroundImagePath; // 背景图路径(null=未设置)
  final bool blurEnabled;            // 模糊开关(默认false)
  final double blurAmount;           // 模糊程度(默认5.0, 范围0-20)
  final String? speechModelId;       // 语音转文字模型ID(null=未设置)
  final String? imageModelId;        // OCR模型ID(null=未设置)
  final String? imageRecognitionModelId; // 多模态图片识别模型ID(null=未设置)
  final bool imageRecognitionEnabled;    // 是否启用图片识别模型
  final String? lastChatModelId;         // 新对话默认使用的 Chat 模型ID
  final String imageRecognitionPrompt;   // 图片识别提示词
  final String systemPrompt;         // 系统提示词(默认"You are a helpful assistant.")
  final List<SystemPrompt> systemPrompts;       // 自定义系统提示词模板列表(默认[])
  final String? selectedSystemPromptId;         // 当前选中的提示词模板ID(null=使用默认systemPrompt)
  final String themeMode;            // 主题模式 "light" | "dark" | "system" (默认"system")
  final List<ChatRole> roles;        // 聊天角色列表，至少包含默认角色
  final String currentRoleId;        // 当前选中的角色ID
  final String lastFeature;          // 功能页最近使用入口: history/schedule/notes
}
```

**方法**: 
- `AppSettings.defaults()` → 工厂构造器, 创建默认设置(蓝色主题)
- `copyWith()` → 支持 sentinel 模式: 可区分"显式传入null"(设为null)与"未传入"(保持原值)
  - `backgroundImagePath`, `speechModelId`, `imageModelId` 使用 sentinel 模式
  - 其余字段使用标准 null-check 覆盖

**JSON持久化**:
- `themeColor` 序列化为 int (ARGB32), 反序列化 `Color(json['themeColor'] as int)`
- nullable 字段仅在非 null 时才写入 JSON (节省存储空间)
- `blurAmount` 反序列化兼容 int/double 两种类型

---

## ScheduleItem
**文件**: `lib/models/schedule_item.dart`

```dart
class ScheduleItem {
  final String id;
  final String title;
  final DateTime start;
  final DateTime end;
  final String? note;
}
```

用于功能页日程表。Provider 按 `start` 升序排序；跨天日程在月视图、周视图和年视图中会出现在覆盖到的日期内。JSON 读写统一转本地时间，避免工具调用或旧数据中的 `Z`/时区偏移导致显示错位。

---

## Note
**文件**: `lib/models/note.dart`

```dart
class Note {
  final String id;
  final String title;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool wrap;
}
```

用于功能页笔记。内容支持 Markdown/LaTeX 渲染，编辑时自动保存；`wrap` 控制自动换行开关。

---

## SystemPrompt
**文件**: `lib/models/system_prompt.dart`

```dart
class SystemPrompt {
  final String id;       // UUID v4
  final String title;    // 提示词标题
  final String content;  // 提示词内容
}
```

`copyWith()` 支持 title 和 content 的可选覆盖。用于管理多套可切换的系统提示词模板。
