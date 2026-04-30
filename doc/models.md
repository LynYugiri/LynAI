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
  final DateTime timestamp;
}
```

不可变类, 通过构造函数创建新实例进行更新。

---

## Conversation
**文件**: `lib/models/conversation.dart`

```dart
class Conversation {
  final String id;
  final String title;              // 对话标题(首个user消息截取前20字符, 未发送消息时为"新对话 N")
  final List<Message> messages;
  final String modelId;            // 关联的ModelConfig.id
  final DateTime createdAt;
  final DateTime updatedAt;
}
```

**计算属性**: `preview` → 第一条消息内容摘要(限80字符, 去除换行)

不可变类, Provider 中通过创建新 Conversation 实例来更新消息列表。

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
  final String endpoint;          // API端点, 如 "https://api.deepseek.com"
  final String apiKey;
  final String modelName;         // 当前激活的模型名(默认取第一个enabled模型)
  final String apiType;           // "openai" | "ollama" | "anthropic" | "custom"
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
  final String? imageModelId;        // 图片转述模型ID(null=未设置)
  final String imagePrompt;          // 图片转述提示词(默认"Describe this file in Chinese")
  final String systemPrompt;         // 系统提示词(默认"You are a helpful assistant.")
  final String themeMode;            // 主题模式 "light" | "dark" | "system" (默认"system")
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
