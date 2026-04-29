# 数据模型

所有模型均支持 `fromJson()` / `toJson()` JSON序列化。

---

## Message
**文件**: `lib/models/message.dart`

```dart
class Message {
  final String id;       // UUID
  final String role;     // "user" | "assistant"
  final String content;  // 消息文本
  final DateTime timestamp;
}
```

---

## Conversation
**文件**: `lib/models/conversation.dart`

```dart
class Conversation {
  final String id;
  final String title;              // 对话标题(首个user消息截取前20字符)
  final List<Message> messages;
  final String modelId;            // 关联的ModelConfig.id
  final DateTime createdAt;
  final DateTime updatedAt;
}
```

**计算属性**: `preview` → 第一条消息内容摘要(限80字符)

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
  final String endpoint;          // API端点, 如 "https://api.deepseek.com/v1"
  final String apiKey;
  final String modelName;         // 当前激活的模型名
  final String apiType;           // "openai" | "ollama" | "anthropic" | "custom"
  final int priority;
  final List<ModelEntry> models;  // 该提供商下所有模型
  final int? maxTokens;           // 高级选项
  final double? temperature;
  final double? topP;
  final Map<String, dynamic> extraParams;
}
```

**计算属性**: `enabledModelNames` → 所有enabled=true的模型名; `hasMultipleModels` → models.length > 1

---

## AppSettings
**文件**: `lib/models/app_settings.dart`

```dart
class AppSettings {
  final Color themeColor;            // 主题色
  final String? backgroundImagePath; // 背景图路径(null=未设置)
  final bool blurEnabled;            // 模糊开关
  final double blurAmount;           // 模糊程度(默认5.0)
  final String? speechModelId;       // 语音转文字模型ID(null=未设置)
  final String? imageModelId;        // 图片转述模型ID(null=未设置)
  final String imagePrompt;          // 图片转述提示词(默认"Describe this file in Chinese")
}
```
