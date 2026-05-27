# 状态管理

LynAI 使用 `Provider + ChangeNotifier`。四个 Provider 在 `main.dart` 注册，启动时并行加载本地数据。

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

## 共同策略

Provider 的更新策略是：先更新内存状态并通知 UI，再把当前快照放入保存队列。

```text
用户操作
  → Provider 修改内存状态
  → notifyListeners()
  → 快照进入 Future 保存队列
  → SharedPreferences(JSON)
```

这样 UI 反馈更快，连续操作也不会让旧异步写入覆盖新状态。保存失败目前记录到 `debugPrint`，不会阻止 UI 更新。

## ConversationProvider

文件：`lib/providers/conversation_provider.dart`

负责对话列表、消息增删改、流式中间态和搜索。

| 方法 | 说明 |
|------|------|
| `loadConversations()` | 加载 `conversations`，坏对话跳过。 |
| `replaceConversations()` | 备份导入时整体替换对话列表。 |
| `createConversation()` | 创建新对话并绑定角色和设置快照。 |
| `addMessage()` | 添加 user 或 assistant 消息。 |
| `updateLastMessage()` | 流式刷新最后一条 assistant 消息。 |
| `updateMessageContent()` | 编辑或重试时替换指定消息正文。 |
| `updateMessageImages()` | 重试版本切换时替换附件。 |
| `deleteMessage()` | 删除单条消息。 |
| `deleteConversation()` | 删除对话。 |
| `searchConversations()` | 搜索标题和正文。 |

`updateLastMessage()` 的 `thinkingContent` 有特殊语义：

| 调用方式 | 行为 |
|----------|------|
| 不传 | 保留原思考内容。 |
| 传字符串 | 覆盖思考内容。 |
| 显式传 `null` | 清空思考内容。 |

流式中间态通常使用 `save:false`。正常完成、停止或失败后再用 `save:true` 保存最终状态。

## ModelConfigProvider

文件：`lib/providers/model_config_provider.dart`

负责模型配置列表、分类查询和排序。

| 方法 | 说明 |
|------|------|
| `loadModels()` | 加载 `model_configs`，坏配置跳过。 |
| `replaceModels()` | 备份导入时整体替换模型配置。 |
| `modelsByCategory()` | 获取某个分类的配置。 |
| `nextPriorityForCategory()` | 新增配置时计算分类内优先级。 |
| `addModel()` | 添加配置。 |
| `updateModel()` | 按 ID 更新配置。 |
| `deleteModel()` | 删除配置。 |
| `reorderModel()` | 全局重排。 |
| `reorderModelsInCategory()` | 分类内重排。 |

模型排序先按 `category`，再按 `priority`。删除或导入替换模型后，应调用 `SettingsProvider.repairMediaModelSelections()` 修复设置里的悬空模型 ID。

## SettingsProvider

文件：`lib/providers/settings_provider.dart`

负责应用级设置、角色、系统提示词和最近使用模型。

| 方法 | 说明 |
|------|------|
| `loadSettings()` | 加载 `app_settings`，顶层损坏时回退默认设置。 |
| `replaceSettings()` | 备份导入时整体替换设置。 |
| `setThemeColor()` / `setThemeMode()` | 修改主题。 |
| `setBackgroundImage()` | 设置或清除背景图。 |
| `setLastFeature()` | 记住功能页入口。 |
| `setSpeechModelId()` / `setImageModelId()` | 设置语音和 OCR 模型。 |
| `setImageRecognitionModelId()` | 设置文件识别模型。 |
| `setLastChatModelId()` | 设置新对话默认 Chat 模型。 |
| `addSystemPrompt()` / `updateSystemPrompt()` / `deleteSystemPrompt()` | 管理提示词模板。 |
| `addRole()` / `updateRole()` / `deleteRole()` / `selectRole()` | 管理角色。 |
| `applyConversationSettings()` | 把历史对话设置快照应用到当前 UI。 |
| `repairMediaModelSelections()` | 修复已删除或不存在的模型引用。 |

`AppSettings.copyWith()` 对可清空字段使用 sentinel。调用者可以明确把字段清空为 `null`，而不是只能“不更新”。

## FeatureProvider

文件：`lib/providers/feature_provider.dart`

负责日程、笔记、笔记文件夹、修订、AI 修改建议和待办清单。

| 分区 | Getter | 存储键 |
|------|--------|--------|
| 日程 | `schedules` | `schedule_items` |
| 笔记 | `notes` | `notes` |
| 文件夹 | `noteFolders` | `note_folders` |
| 修订 | `noteRevisions` | `note_revisions` |
| 修改建议 | `getNoteEditProposal()` | `note_edit_proposals` |
| 待办 | `todoLists` | `todo_lists` |

### 日程

| 方法 | 说明 |
|------|------|
| `addSchedule()` | 新增普通日程或任务类日程。 |
| `updateSchedule()` | 修改日程。 |
| `deleteSchedule()` | 删除日程。 |
| `getSchedule()` | 按 ID 查询。 |

日程变更后 Android 会通过 `lynai/schedule_widget` 平台通道刷新小组件并重新安排通知。其他平台直接跳过。

### 笔记

| 方法 | 说明 |
|------|------|
| `addNote()` | 新建空笔记。 |
| `addNoteWithContent()` | 创建带内容的笔记并写入初始修订。 |
| `saveNoteContent()` | 保存正文并生成 delta 修订。 |
| `restoreNoteRevision()` | 把历史修订恢复为当前版本。 |
| `getNoteTimeline()` | 获取修订时间线。 |
| `getNoteContentAtRevision()` | 重放 delta 得到某个版本的正文。 |
| `deleteNote()` | 删除笔记、修订和修改建议。 |
| `addNoteFolder()` / `updateNoteFolder()` / `deleteNoteFolder()` | 管理文件夹。 |

加载后会执行归一化：补齐缺失修订、清理不存在文件夹引用、清理不再适用的修改建议、刷新缓存。

### 待办

| 方法 | 说明 |
|------|------|
| `addTodoList()` | 新建清单。 |
| `updateTodoList()` | 修改标题或任务。 |
| `deleteTodoList()` | 删除清单。 |
| `reorderTodoLists()` | 清单排序。 |

清单内任务排序、Markdown 导入导出和长图分享在页面层完成。

## 容错加载

| 数据 | 行为 |
|------|------|
| 对话 | 坏对话跳过，坏消息跳过。 |
| 模型 | 坏配置跳过；顶层损坏时模型列表置空。 |
| 设置 | 坏角色/提示词跳过；顶层损坏时使用默认设置。 |
| 日程/笔记/待办 | 单条坏记录跳过；顶层损坏时对应分区置空。 |
| 附件 | 兼容旧 `filePath`，并从路径推导文件名和 MIME。 |

## 修改 Provider 时要注意

1. 修改内存列表后要保存对应分区。
2. 影响 UI 的修改要 `notifyListeners()`。
3. 批量导入应尽量等待保存队列完成后再通知 UI。
4. 删除模型后要修复设置中的模型引用。
5. 修改笔记修订时要清理修订内容缓存和时间线缓存。
