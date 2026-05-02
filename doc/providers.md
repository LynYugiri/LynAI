# 状态管理 (Providers)

所有Provider继承`ChangeNotifier`，通过`MultiProvider`在`main.dart`注册。

---

## ConversationProvider
**文件**: `lib/providers/conversation_provider.dart`

**核心数据**: `List<Conversation> conversations` (按updatedAt倒序)

| 方法 | 说明 |
|------|------|
| `loadConversations()` | 从SharedPreferences加载, 加载失败初始化为空列表 |
| `createConversation(modelId)` | 新建对话, 返回ID, 失败抛出异常 |
| `addMessage(convId, role, content)` | 添加消息, 首条user消息自动设为标题(截取前20字符), 更新后对话移至列表顶部 |
| `updateLastMessage(convId, content, {save: true})` | 增量更新最后一条消息(用于流式渲染), save参数控制是否立即持久化 |
| `updateMessageContent(convId, msgId, content)` | 更新指定消息内容(用于重试/编辑), 更新后对话移至列表顶部 |
| `updateConversationTitle(convId, title)` | 更新对话标题 |
| `updateConversationModelId(convId, modelId)` | 更新对话绑定的模型ID |
| `deleteMessage(convId, msgId)` | 删除指定消息 |
| `deleteConversation(convId)` | 删除对话 |
| `getConversation(convId)` | 按ID获取, 不存在返回null |
| `searchConversations(query)` | 按标题+内容搜索, 返回匹配列表, 每个结果包含conversation对象及匹配位置(matchInTitle/matchContent) |

持久化: 除 `updateLastMessage(save: false)` 外的每次变更自动调用 `_saveConversations()` JSON→SharedPreferences

---

## ModelConfigProvider
**文件**: `lib/providers/model_config_provider.dart`

**核心数据**: `List<ModelConfig> models` (按priority升序, 数字越小优先级越高)

| 方法 | 说明 |
|------|------|
| `loadModels()` | 从SharedPreferences加载, 加载失败初始化为空列表 |
| `addModel(config)` | 添加配置(自动按priority排序后持久化) |
| `updateModel(config)` | 按ID查找并更新配置(重新排序) |
| `deleteModel(id)` | 按ID删除配置 |
| `reorderModel(old, new)` | 拖拽重排后更新所有model的priority值(0-based) |
| `generateId()` | 生成UUID v4 |

---

## SettingsProvider
**文件**: `lib/providers/settings_provider.dart`

**核心数据**: `AppSettings settings`, 加载失败时使用默认值(蓝色主题/系统主题模式)

| 方法 | 说明 |
|------|------|
| `loadSettings()` | 从SharedPreferences加载设置 |
| `setThemeColor(color)` | 主题色(通过ColorScheme.fromSeed生成Material 3配色) |
| `setThemeMode(mode)` | 主题模式 "light"/"dark"/"system" |
| `setBackgroundImage(path)` | 背景图路径(null=清除) |
| `setBlurEnabled(bool)` | 毛玻璃模糊开关 |
| `setBlurAmount(double)` | 模糊程度(0-20, 默认5.0) |
| `setSpeechModelId(id)` | 语音转文字模型ID(null=未设置, 语音功能不可用) |
| `setImageModelId(id)` | 图片转述模型ID(null=未设置, 图片直接作为文本发送) |
| `setImagePrompt(prompt)` | 图片转述提示词(默认"Describe this file in Chinese") |
| `setSystemPrompt(prompt)` | 全局系统提示词(默认"You are a helpful assistant.") |
| `addSystemPrompt(title, content)` | 添加自定义系统提示词模板 |
| `updateSystemPrompt(id, title, content)` | 更新指定提示词模板 |
| `deleteSystemPrompt(id)` | 删除提示词模板(若当前选中则自动切换) |
| `selectSystemPrompt(id)` | 选择当前使用的提示词模板(null=使用默认systemPrompt) |

**计算属性**: `themeMode` → String; `themeModeEnum` → ThemeMode枚举; `effectiveSystemPrompt` → 当前生效的提示词内容(优先选中模板, 否则用默认)

### AppSettings sentinel模式

`copyWith()` 使用 sentinel 对象区分"显式传入null"和"未传入参数":
- 传入 `null` → 将字段值设为 null (如清除图片路径 `setBackgroundImage(null)`)
- 不传入 → 保持原值不变
