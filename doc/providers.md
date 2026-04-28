# 状态管理 (Providers)

所有Provider继承`ChangeNotifier`，通过`MultiProvider`在`main.dart`注册。

---

## ConversationProvider
**文件**: `lib/providers/conversation_provider.dart`

**核心数据**:
- `List<Conversation> conversations` - 全部对话(按updateAt倒序)

**核心方法**:
| 方法 | 说明 |
|------|------|
| `loadConversations()` | 从SharedPreferences加载对话数据 |
| `createConversation(String modelId)` | 新建对话，返回对话ID |
| `addMessage(String convId, String role, String content)` | 添加消息到对话 |
| `updateConversationTitle(String convId, String title)` | 更新对话标题 |
| `updateLastMessage(String convId, String content)` | 更新最后一条消息内容(流式更新用) |
| `deleteMessage(String convId, String msgId)` | 删除指定消息 |
| `deleteConversation(String convId)` | 删除对话 |
| `getConversation(String convId)` | 按ID获取对话 |
| `searchConversations(String query)` | 按标题+消息内容搜索，返回匹配的对话列表 |

**持久化**: `_saveConversations()` 在每次变更后序列化为JSON写入SharedPreferences

---

## ModelConfigProvider
**文件**: `lib/providers/model_config_provider.dart`

**核心数据**:
- `List<ModelConfig> models` - 模型配置列表(按priority排序)

**核心方法**:
| 方法 | 说明 |
|------|------|
| `loadModels()` | 从SharedPreferences加载模型配置 |
| `addModel(ModelConfig model)` | 添加模型配置(含高级参数) |
| `updateModel(ModelConfig model)` | 更新模型配置 |
| `deleteModel(String id)` | 删除模型配置 |
| `reorderModel(int oldIndex, int newIndex)` | 拖拽重排后更新priority |
| `generateId()` | 生成UUID |

**持久化**: `_saveModels()` 序列化为JSON写入SharedPreferences

---

## SettingsProvider
**文件**: `lib/providers/settings_provider.dart`

**核心数据**:
- `AppSettings settings` - 当前设置

**核心方法**:
| 方法 | 说明 |
|------|------|
| `loadSettings()` | 从SharedPreferences加载设置 |
| `setThemeColor(Color color)` | 设置主题颜色 |
| `setBackgroundImage(String? path)` | 设置背景图路径 |
| `setBlurEnabled(bool enabled)` | 开关模糊效果 |
| `setBlurAmount(double amount)` | 设置模糊程度 |
| `setSpeechModelId(String? modelId)` | 设置语音转文字模型 |
| `setImageModelId(String? modelId)` | 设置图片转述模型 |
| `setImagePrompt(String prompt)` | 设置图片转述提示词 |

**持久化**: `_saveSettings()` 序列化为JSON写入SharedPreferences
