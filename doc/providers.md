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
| `addMessage(convId, role, content, {images, thinkingContent})` | 添加消息、可选附件和可选思考过程, 首条user消息自动设为标题(截取前20字符), 更新后对话移至列表顶部 |
| `updateLastMessage(convId, content, {thinkingContent, save: true})` | 增量更新最后一条消息(用于流式渲染), 可同步写入思考过程, save参数控制是否立即持久化 |
| `updateMessageContent(convId, msgId, content)` | 更新指定消息内容(用于重试/编辑), 更新后对话移至列表顶部 |
| `updateMessageImages(convId, msgId, images)` | 更新指定消息附件(用于重试历史切换), 更新后对话移至列表顶部 |
| `updateConversationTitle(convId, title)` | 更新对话标题 |
| `updateConversationModelId(convId, modelId)` | 更新对话绑定的模型ID |
| `updateConversationSettings(convId, settings)` | 更新对话级设置快照 |
| `deleteMessage(convId, msgId)` | 删除指定消息 |
| `deleteConversation(convId)` | 删除对话 |
| `getConversation(convId)` | 按ID获取, 不存在返回null |
| `searchConversations(query)` | 按标题+内容搜索, 返回匹配列表, 每个结果包含conversation对象及匹配位置(matchInTitle/matchContent) |

`updateLastMessage()` 的 `thinkingContent` 参数使用 sentinel 语义。

| 调用方式 | 结果 |
|----------|------|
| 不传 `thinkingContent` | 保留最后一条消息已有的思考内容 |
| `thinkingContent: '...'` | 覆盖为新的思考内容 |
| `thinkingContent: null` | 显式清空思考内容 |

持久化: 除 `updateLastMessage(save: false)` 外的每次变更会把当次快照加入串行保存队列，按调用顺序写入 SharedPreferences，避免快速连续修改时旧写入覆盖新状态。

加载容错: `loadConversations()` 会跳过损坏对话；`Conversation.fromJson()` 会跳过损坏消息，因此单条坏消息不会导致整段对话丢失。

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
| `setImageOcrEnabled(bool)` | OCR 识别开关 |
| `setImageRecognitionModelId(id)` | 文件识别 Chat 模型ID(null=未设置) |
| `setImageRecognitionEnabled(bool)` | 文件识别开关 |
| `setLastChatModelId(id)` | 新对话默认 Chat 模型ID |
| `setImageRecognitionPrompt(prompt)` | 文件识别提示词 |
| `setSystemPrompt(prompt)` | 全局系统提示词(默认"You are a helpful assistant.") |
| `addSystemPrompt(title, content)` | 添加自定义系统提示词模板 |
| `updateSystemPrompt(id, title, content)` | 更新指定提示词模板；如果该ID绑定角色，同步更新角色名称和提示词 |
| `deleteSystemPrompt(id)` | 删除提示词模板；如果该ID绑定角色，改为删除对应角色，避免悬挂引用 |
| `selectSystemPrompt(id)` | 选择当前使用的提示词模板(null=使用默认systemPrompt) |
| `repairMediaModelSelections(models)` | 修复语音、OCR、文件识别和最近聊天模型中已删除或不存在的配置引用 |

| `applyConversationSettings(settings)` | 将当前对话的设置快照同步到全局设置，便于 UI 控件显示当前状态 |

**计算属性**: `themeMode` → String; `themeModeEnum` → ThemeMode枚举; `effectiveSystemPrompt` → 当前生效的提示词内容(优先选中模板, 否则用默认)

Settings、Conversation、ModelConfig 和 Feature 数据都会按快照进入串行保存队列。UI 状态仍立即更新，持久化按队列顺序异步落盘，保证最后一次修改最终写入。

### 设置加载容错

`AppSettings.fromJson()` 对角色和系统提示词采用逐条解析策略。

| 数据 | 容错策略 |
|------|----------|
| `systemPrompts` | 单条损坏时跳过，并保留其他可用提示词 |
| `roles` | 单条损坏时跳过；默认角色缺失时自动补回 |
| `currentRoleId` | 指向不存在角色时回退到 `default` |
| 旧字段 | `imagePrompt` 会迁移读取为 `imageRecognitionPrompt` |

### 模型引用修复

模型配置删除、导入或替换后，设置里保存的 ID 可能变成悬空引用。`repairMediaModelSelections()` 会按分类修复这些字段。

| 字段 | 分类 | 修复结果 |
|------|------|----------|
| `speechModelId` | Speech | 保留有效 ID，否则回填第一个 Speech 配置或清空 |
| `imageModelId` | OCR | 保留有效 ID，否则回填第一个 OCR 配置或清空 |
| `imageRecognitionModelId` | Chat | 保留有效 ID，否则回填第一个 Chat 配置或清空 |
| `lastChatModelId` | Chat | 保留有效 ID，否则回填第一个 Chat 配置或清空 |

---

## FeatureProvider
**文件**: `lib/providers/feature_provider.dart`

**核心数据**: `List<ScheduleItem> schedules`, `List<Note> notes`，以及笔记文件夹、笔记修订、待办列表等功能数据。

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

持久化: 日程存储键为 `schedule_items`，笔记存储键为 `notes`，均以 JSON 写入 SharedPreferences。新版还会维护笔记修订、文件夹和待办列表等分区键。

加载时会对单条日程、笔记、文件夹、修订和待办做容错解析。损坏条目会跳过，并通过 `debugPrint` 输出原因。笔记加载后会执行引用归一化，修复缺失修订、缺失文件夹引用等可恢复状态。

---

### AppSettings sentinel模式

`copyWith()` 使用 sentinel 对象区分"显式传入null"和"未传入参数":
- 传入 `null` → 将字段值设为 null (如清除图片路径 `setBackgroundImage(null)`)
- 不传入 → 保持原值不变

同样的模式也用于 `ModelEntry.copyWith()`、`ModelConfig.copyWith()` 和 `ConversationProvider.updateLastMessage()` 中的 nullable 字段。凡是 UI 需要“清空已有值”的字段，都不应使用普通 `??` copyWith 写法。
