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
  final String id;                 // UUID
  final String title;              // 对话标题(首条消息截取)
  final List<Message> messages;    // 消息列表
  final String modelId;            // 关联的ModelConfig.id
  final DateTime createdAt;
  final DateTime updatedAt;
}
```

**计算属性**: `preview` getter → 返回最后一条消息内容摘要(限长80字符)

---

## ModelConfig
**文件**: `lib/models/model_config.dart`

```dart
class ModelConfig {
  final String id;              // UUID
  final String name;            // 显示名称
  final String endpoint;        // API端点URL
  final String apiKey;          // API密钥
  final String modelName;       // 模型标识名
  final String apiType;         // "openai" | "ollama" | "anthropic" | "custom"
  final int priority;           // 排序优先级
  final int? maxTokens;         // 最大输出token数 (高级选项)
  final double? temperature;    // 采样温度 0-2 (高级选项)
  final double? topP;           // 核采样参数 0-1 (高级选项)
  final Map<String, dynamic> extraParams; // 额外自定义参数
}
```

**方法**: `copyWith({...})` 创建修改副本

---

## AppSettings
**文件**: `lib/models/app_settings.dart`

```dart
class AppSettings {
  final Color themeColor;            // 主题种子颜色
  final String? backgroundImagePath; // 背景图片路径
  final bool blurEnabled;            // 背景模糊开关
  final double blurAmount;           // 模糊程度 (默认5.0)
  final String? speechModelId;       // 语音转文字模型ID (null=未设置)
  final String? imageModelId;        // 图片转述模型ID (null=未设置)
  final String imagePrompt;          // 图片转述提示词 (默认"Describe this file in Chinese")
}
```

**方法**: `factory defaults()` 返回默认设置, `copyWith({...})`
