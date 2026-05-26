# 状态管理

项目使用 `Provider + ChangeNotifier`。四个 Provider 在 `main.dart` 中注册，启动时并行加载本地数据。

```dart
MultiProvider(
  providers: [
    ChangeNotifierProvider(create: (_) => ConversationProvider()),
    ChangeNotifierProvider(create: (_) => FeatureProvider()),
    ChangeNotifierProvider(create: (_) => ModelConfigProvider()),
    ChangeNotifierProvider(create: (_) => SettingsProvider()),
  ],
)
```

Provider 的共同策略是：先更新内存状态并通知 UI，再把不可变快照加入串行保存队列，避免连续操作时旧异步写入覆盖新状态。

## ConversationProvider

文件：`lib/providers/conversation_provider.dart`

核心数据：`List<Conversation> conversations`，按 `updatedAt` 倒序。

| 方法 | 说明 |
|------|------|
| `loadConversations()` | 从 `conversations` 加载对话，坏对话跳过，坏消息由模型层跳过 |
| `createConversation(settings, {roleId})` | 创建新对话，绑定角色和设置快照 |
| `addMessage(convId, role, content, {images, thinkingContent})` | 添加消息和附件，首条 user 消息会生成标题 |
| `updateLastMessage(convId, content, {thinkingContent, save})` | 流式刷新最后一条 assistant 消息，可保存或清空思考内容 |
| `updateMessageContent(convId, msgId, content)` | 编辑或重试时替换指定消息文本 |
| `updateMessageImages(convId, msgId, images)` | 重试版本切换时替换指定消息附件 |
| `updateConversationTitle(convId, title)` | 修改标题 |
| `updateConversationModelId(convId, modelId)` | 修改对话绑定模型 |
| `updateConversationSettings(convId, settings)` | 修改对话级设置快照 |
| `deleteMessage(convId, msgId)` | 删除指定消息 |
| `deleteConversation(convId)` | 删除对话 |
| `searchConversations(query)` | 搜索标题和消息内容，返回匹配位置摘要 |

`updateLastMessage()` 的 `thinkingContent` 使用 sentinel 语义。

| 调用 | 行为 |
|------|------|
| 不传 `thinkingContent` | 保留原思考内容 |
| `thinkingContent: '...'` | 覆盖为新思考内容 |
| `thinkingContent: null` | 显式清空思考内容 |

流式中间态通常使用 `save:false`，正常完成、停止或失败后再使用 `save:true` 持久化最终状态。

## ModelConfigProvider

文件：`lib/providers/model_config_provider.dart`

核心数据：`List<ModelConfig> models`，按分类和优先级排序。

| 方法 | 说明 |
|------|------|
| `loadModels()` | 从 `model_configs` 加载，失败时置空 |
| `modelsByCategory(category)` | 返回指定分类配置 |
| `nextPriorityForCategory(category)` | 计算分类内新增配置优先级 |
| `addModel(config)` | 添加配置并排序保存 |
| `updateModel(config)` | 按 ID 更新配置并排序保存 |
| `deleteModel(id)` | 删除配置 |
| `reorderModel(old, new)` | 全局重排并重写 priority |
| `reorderModelsInCategory(category, old, new)` | 分类内拖拽重排 |
| `generateId()` | 生成 UUID v4 |

模型删除或导入替换后，`main.dart` 和数据管理页会调用 `SettingsProvider.repairMediaModelSelections()` 修复设置中的悬空模型 ID。

## SettingsProvider

文件：`lib/providers/settings_provider.dart`

核心数据：`AppSettings settings`。

| 方法 | 说明 |
|------|------|
| `loadSettings()` | 加载 `app_settings`，失败时使用默认设置 |
| `setThemeColor(color)` | 设置当前主题色 |
| `setThemeMode(mode)` | `light`、`dark`、`system` |
| `setBackgroundImage(path)` | 设置或清除背景图 |
| `setBlurEnabled(bool)` | 开关背景模糊 |
| `setBlurAmount(double)` | 设置模糊强度 |
| `setLastFeature(feature)` | 保存功能页入口：`history`、`schedule`、`notes`、`todos` |
| `setSpeechModelId(id)` | 设置语音模型 |
| `setImageModelId(id)` | 设置 OCR 模型 |
| `setImageOcrEnabled(bool)` | 开关 OCR |
| `setImageRecognitionModelId(id)` | 设置文件识别 Chat 模型 |
| `setImageRecognitionEnabled(bool)` | 开关文件识别 |
| `setLastChatModelId(id)` | 新对话默认 Chat 模型 |
| `setImageRecognitionPrompt(prompt)` | 文件识别提示词 |
| `setSystemPrompt(prompt)` | 默认系统提示词 |
| `addSystemPrompt(title, content)` | 新增提示词模板 |
| `updateSystemPrompt(id, title, content)` | 更新提示词；如果绑定角色则同步角色 |
| `deleteSystemPrompt(id)` | 删除提示词；如果绑定角色则删除角色避免悬挂引用 |
| `selectSystemPrompt(id)` | 选择模板或回退默认提示词 |
| `addRole(...)` | 新增角色，并同步创建同 ID 提示词模板 |
| `selectRole(roleId)` | 切换角色并同步系统提示词、默认模型和主题色 |
| `applyConversationSettings(settings)` | 把历史对话设置快照同步到 UI |
| `repairMediaModelSelections(models)` | 修复已删除或不存在的模型引用 |

计算属性包括 `themeModeEnum` 和 `effectiveSystemPrompt`。`AppSettings.copyWith()` 对可清空字段使用 sentinel，避免 `null` 被误认为“不更新”。

## FeatureProvider

文件：`lib/providers/feature_provider.dart`

核心数据：日程、笔记、笔记修订、笔记文件夹、笔记修改建议、待办清单。

| 数据 | Getter | 存储键 |
|------|--------|--------|
| 日程 | `schedules` | `schedule_items` |
| 笔记 | `notes` | `notes` |
| 笔记文件夹 | `noteFolders` | `note_folders` |
| 笔记修订 | `noteRevisions` | `note_revisions` |
| 笔记修改建议 | `getNoteEditProposal()` | `note_edit_proposals` |
| 待办清单 | `todoLists` | `todo_lists` |

### 日程方法

| 方法 | 说明 |
|------|------|
| `addSchedule(title, start, end, {note, kind})` | 新增日程或任务类日程 |
| `updateSchedule(schedule)` | 更新日程 |
| `deleteSchedule(id)` | 删除日程 |
| `getSchedule(id)` | 按 ID 获取日程 |

日程保存后 Android 会通过 `lynai/schedule_widget` 通道刷新小组件并重新安排通知；其他平台直接跳过。

### 笔记方法

| 方法 | 说明 |
|------|------|
| `addNote(title, {folderId})` | 新建空笔记 |
| `addNoteWithContent(title, content, {folderId})` | 带初始内容创建笔记，并创建初始修订 |
| `getNote(id)` | 按 ID 获取笔记 |
| `updateNote(note)` | 更新笔记并写入修订 |
| `deleteNote(id)` | 删除笔记及相关修订/建议 |
| `addNoteFolder(title)` | 新建文件夹 |
| `updateNoteFolder(folder)` | 更新文件夹 |
| `deleteNoteFolder(id)` | 删除文件夹并清理笔记引用 |
| `getNoteTimeline(noteId)` | 获取笔记修订时间线 |
| `getNoteContentAtRevision(noteId, revisionId)` | 还原某个修订版本内容 |

加载后会执行引用归一化：补齐缺失修订、移除指向不存在文件夹的引用，并清理不可用的修改建议。

### 待办方法

| 方法 | 说明 |
|------|------|
| `addTodoList(title, items)` | 新建清单 |
| `updateTodoList(list)` | 更新清单标题或条目 |
| `deleteTodoList(id)` | 删除清单 |
| `reorderTodoLists(oldIndex, newIndex)` | 清单排序 |

待办页面还会在 UI 层处理清单内任务排序、勾选、导入导出和长图分享。

## 容错加载策略

| 数据 | 行为 |
|------|------|
| 对话 | 坏对话跳过，坏消息跳过 |
| 设置 | 坏角色/提示词跳过，默认角色缺失时补回 |
| 模型 | 加载失败置空，不影响应用启动 |
| 日程/笔记/待办 | 单条坏记录跳过，整体失败时该功能分区置空 |
| 附件 | 兼容旧 `filePath`，并推导缺失名称/MIME |
| 模型引用 | 删除或导入后修复语音、OCR、文件识别和最近 Chat 模型 ID |
