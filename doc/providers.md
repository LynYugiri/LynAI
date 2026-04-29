# 状态管理 (Providers)

所有Provider继承`ChangeNotifier`，通过`MultiProvider`在`main.dart`注册。

---

## ConversationProvider
**文件**: `lib/providers/conversation_provider.dart`

**核心数据**: `List<Conversation> conversations` (按updateAt倒序)

| 方法 | 说明 |
|------|------|
| `loadConversations()` | 从SharedPreferences加载 |
| `createConversation(modelId)` | 新建对话, 返回ID |
| `addMessage(convId, role, content)` | 添加消息, 首条user消息自动设为标题 |
| `updateLastMessage(convId, content)` | 增量更新最后一条消息(流式渲染) |
| `deleteMessage(convId, msgId)` | 删除指定消息 |
| `updateConversationTitle(convId, title)` | 更新对话标题 |
| `deleteConversation(convId)` | 删除对话 |
| `getConversation(convId)` | 按ID获取 |
| `searchConversations(query)` | 按标题+内容搜索, 返回匹配列表+片段 |

持久化: 每次变更 `_saveConversations()` JSON→SharedPreferences

---

## ModelConfigProvider
**文件**: `lib/providers/model_config_provider.dart`

**核心数据**: `List<ModelConfig> models` (按priority升序)

| 方法 | 说明 |
|------|------|
| `loadModels()` | 从SharedPreferences加载 |
| `addModel(config)` | 添加配置(排序后持久化) |
| `updateModel(config)` | 更新配置 |
| `deleteModel(id)` | 删除配置 |
| `reorderModel(old, new)` | 拖拽重排后更新所有priority |
| `generateId()` | 生成UUID |

---

## SettingsProvider
**文件**: `lib/providers/settings_provider.dart`

**核心数据**: `AppSettings settings`

| 方法 | 说明 |
|------|------|
| `loadSettings()` | 加载设置 |
| `setThemeColor(color)` | 主题色 |
| `setBackgroundImage(path)` | 背景图(null=清除) |
| `setBlurEnabled(bool)` | 模糊开关 |
| `setBlurAmount(double)` | 模糊量 |
| `setSpeechModelId(id)` | 语音模型ID |
| `setImageModelId(id)` | 图片模型ID |
| `setImagePrompt(prompt)` | 图片提示词 |
