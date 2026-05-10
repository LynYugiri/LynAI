# 状态管理 (Providers)

所有Provider继承`ChangeNotifier`，通过`MultiProvider`在`main.dart`注册。

---

## ConversationProvider
**文件**: `lib/providers/conversation_provider.dart`

**核心数据**: `List<Conversation> conversations` (按updatedAt倒序)

| 方法 | 说明 |
|------|------|
| `loadConversations()` | 从SharedPreferences加载, 加载失败初始化为空列表 |
| `createConversation(settings, {roleId})` | 新建对话并绑定角色ID, 默认角色为 `default` |
| `addMessage(convId, role, content, {images})` | 添加消息和可选图片附件, 首条user消息自动设为标题(截取前20字符), 更新后对话移至列表顶部 |
| `updateLastMessage(convId, content, {save: true})` | 增量更新最后一条消息(用于流式渲染), save参数控制是否立即持久化 |
| `updateMessageContent(convId, msgId, content)` | 更新指定消息内容(用于重试/编辑), 更新后对话移至列表顶部 |
| `updateConversationTitle(convId, title)` | 更新对话标题 |
| `updateConversationModelId(convId, modelId)` | 更新对话绑定的模型ID |
| `updateConversationSettings(convId, settings)` | 更新对话级设置快照 |
| `deleteMessage(convId, msgId)` | 删除指定消息 |
| `deleteConversation(convId)` | 删除对话 |
| `getConversation(convId)` | 按ID获取, 不存在返回null |
| `searchConversations(query)` | 按标题+内容搜索, 返回匹配列表, 每个结果包含conversation对象及匹配位置(matchInTitle/matchContent) |

持久化: 除 `updateLastMessage(save: false)` 外的每次变更自动调用 `_saveConversations()` JSON→SharedPreferences

---

## ModelConfigProvider
**文件**: `lib/providers/model_config_provider.dart`

**核心数据**: `List<ModelConfig> models` (先按 category，再按 priority 升序)

| 方法 | 说明 |
|------|------|
| `loadModels()` | 从SharedPreferences加载, 加载失败初始化为空列表 |
| `modelsByCategory(category)` | 返回指定分类下的模型配置 |
| `nextPriorityForCategory(category)` | 返回指定分类下的新配置优先级 |
| `addModel(config)` | 添加配置(自动按priority排序后持久化) |
| `updateModel(config)` | 按ID查找并更新配置(重新排序) |
| `deleteModel(id)` | 按ID删除配置 |
| `reorderModel(old, new)` | 拖拽重排后更新所有model的priority值(0-based) |
| `reorderModelsInCategory(category, old, new)` | 仅重排指定分类内的模型优先级 |
| `generateId()` | 生成UUID v4 |

---

## SettingsProvider
**文件**: `lib/providers/settings_provider.dart`

**核心数据**: `AppSettings settings`, 加载失败时使用默认值(蓝色主题/系统主题模式)

| 方法 | 说明 |
|------|------|
| `loadSettings()` | 从SharedPreferences加载设置 |
| `setThemeColor(color)` | 主题色(通过ColorScheme.fromSeed生成Material 3配色) |
| `setLastFeature(feature)` | 保存功能页最近打开的子功能(history/schedule/notes) |
| `addRole({name, systemPrompt, modelId, themeColor})` | 添加聊天角色，并同步创建同ID的系统提示词模板 |
| `selectRole(roleId)` | 切换当前角色，同步系统提示词、默认模型和可选主题色 |
| `setThemeMode(mode)` | 主题模式 "light"/"dark"/"system" |
| `setBackgroundImage(path)` | 背景图路径(null=清除) |
| `setBlurEnabled(bool)` | 毛玻璃模糊开关 |
| `setBlurAmount(double)` | 模糊程度(0-20, 默认5.0) |
| `setSpeechModelId(id)` | 语音转文字模型ID(null=未设置, 语音功能不可用) |
| `setImageModelId(id)` | OCR 模型ID(null=未设置) |
| `setImageRecognitionModelId(id)` | 多模态图片识别 Chat 模型ID(null=未设置) |
| `setImageRecognitionEnabled(bool)` | 图片识别开关 |
| `setLastChatModelId(id)` | 新对话默认 Chat 模型ID |
| `setImageRecognitionPrompt(prompt)` | 图片识别提示词 |
| `setSystemPrompt(prompt)` | 全局系统提示词(默认"You are a helpful assistant.") |
| `addSystemPrompt(title, content)` | 添加自定义系统提示词模板 |
| `updateSystemPrompt(id, title, content)` | 更新指定提示词模板 |
| `deleteSystemPrompt(id)` | 删除提示词模板(若当前选中则自动切换) |
| `selectSystemPrompt(id)` | 选择当前使用的提示词模板(null=使用默认systemPrompt) |

| `applyConversationSettings(settings)` | 将当前对话的设置快照同步到全局设置，便于 UI 控件显示当前状态 |

**计算属性**: `themeMode` → String; `themeModeEnum` → ThemeMode枚举; `effectiveSystemPrompt` → 当前生效的提示词内容(优先选中模板, 否则用默认)

---

## FeatureProvider
**文件**: `lib/providers/feature_provider.dart`

**核心数据**: `List<ScheduleItem> schedules`, `List<Note> notes`

| 方法 | 说明 |
|------|------|
| `load()` | 从 SharedPreferences 加载日程和笔记，笔记按 updatedAt 倒序 |
| `addSchedule(title, start, end, {note})` | 新增日程并按开始时间排序 |
| `updateSchedule(schedule)` | 按ID更新日程并重新排序 |
| `deleteSchedule(id)` | 删除指定日程 |
| `addNote(title)` | 新建空笔记，返回笔记ID |
| `getNote(id)` | 按ID获取笔记，不存在返回 null |
| `updateNote(note)` | 更新笔记并按更新时间倒序 |
| `deleteNote(id)` | 删除指定笔记 |

持久化: 日程存储键为 `schedule_items`，笔记存储键为 `notes`，均以 JSON 写入 SharedPreferences。

---

### AppSettings sentinel模式

`copyWith()` 使用 sentinel 对象区分"显式传入null"和"未传入参数":
- 传入 `null` → 将字段值设为 null (如清除图片路径 `setBackgroundImage(null)`)
- 不传入 → 保持原值不变
