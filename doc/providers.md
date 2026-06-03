# 状态管理

LynAI 使用 `Provider + ChangeNotifier`。Provider 是 UI 状态和业务操作入口，Repository 是持久化边界。

## 注册

Provider 在 `main.dart` 中注册：

```dart
MultiProvider(
  providers: [
    ChangeNotifierProvider(create: (_) => ConversationProvider()),
    ChangeNotifierProvider(create: (_) => FeatureProvider()),
    ChangeNotifierProvider(create: (_) => ModelConfigProvider()),
    ChangeNotifierProvider(create: (_) => RoleplayProvider()),
    ChangeNotifierProvider(create: (_) => SettingsProvider()),
  ],
)
```

启动时，应用先检查 storage_v2 迁移状态，再并行加载各分区数据。

## 共同策略

Provider 的更新策略是：先改内存并通知 UI，再把快照放入保存队列。

```text
用户操作
  -> Provider 修改内存状态
  -> notifyListeners()
  -> 快照进入 Future 保存队列
  -> Repository
  -> storage_v2 或 legacy SharedPreferences
```

这样 UI 反馈更快，连续操作也不会让旧异步写入覆盖新状态。保存失败通常记录到 `debugPrint`，不会阻止 UI 显示内存中的最新状态。

## ConversationProvider

文件：`lib/providers/conversation_provider.dart`

负责对话列表、消息增删改、流式中间态、搜索和模型引用修复。

| 方法 | 说明 |
|------|------|
| `loadConversations()` | 加载对话，坏对话跳过。 |
| `replaceConversations()` | 备份导入或路径迁移时整体替换对话列表。 |
| `createConversation()` | 创建新对话并绑定角色和设置快照。 |
| `createConversationWithMessages()` | 从已有消息创建新对话。 |
| `addMessage()` | 添加 user 或 assistant 消息。 |
| `updateLastMessage()` | 流式刷新最后一条 assistant 消息。 |
| `updateMessageContent()` | 编辑或重试时替换指定消息正文。 |
| `updateMessageImages()` | 重试版本切换时替换附件。 |
| `deleteMessage()` / `deleteConversation()` | 删除消息或对话。 |
| `searchConversations()` | 搜索标题和正文。 |
| `repairModelReferences()` | 修复已删除模型留下的对话引用。 |

`updateLastMessage()` 的 `thinkingContent` 有特殊语义：不传表示保留，传字符串表示覆盖，显式传 `null` 表示清空。

流式中间态通常使用 `save:false`，正常完成、停止或失败后再保存最终状态。

## ModelConfigProvider

文件：`lib/providers/model_config_provider.dart`

负责模型配置列表、分类查询和排序。

| 方法 | 说明 |
|------|------|
| `loadModels()` | 加载模型配置，坏配置跳过。 |
| `replaceModels()` | 备份导入时整体替换模型配置。 |
| `modelsByCategory()` | 获取某个分类的配置。 |
| `nextPriorityForCategory()` | 新增配置时计算分类内优先级。 |
| `addModel()` / `updateModel()` / `deleteModel()` | 增删改配置。 |
| `reorderModel()` / `reorderModelsInCategory()` | 全局或分类内排序。 |

模型排序先按 `category`，再按 `priority`。删除或导入替换模型后，应修复 Settings、Conversation 和 Roleplay 中的模型引用。

## SettingsProvider

文件：`lib/providers/settings_provider.dart`

负责应用级设置、角色、角色分组、系统提示词和最近使用模型。

| 方法 | 说明 |
|------|------|
| `loadSettings()` | 加载设置，顶层损坏时回退默认设置。 |
| `replaceSettings()` | 备份导入或资源迁移时整体替换设置。 |
| `setThemeColor()` / `setThemeMode()` | 修改主题。 |
| `setBackgroundImage()` | 设置或清除背景图。 |
| `setLastFeature()` | 记住功能页入口。 |
| `setSpeechModelId()` / `setImageModelId()` | 设置语音和 OCR 模型。 |
| `setImageRecognitionModelId()` | 设置文件识别模型。 |
| `setLastChatModelId()` | 设置新对话默认 Chat 模型。 |
| `addSystemPrompt()` / `updateSystemPrompt()` / `deleteSystemPrompt()` | 管理提示词模板。 |
| `addRole()` / `updateRole()` / `deleteRole()` / `selectRole()` | 管理角色。 |
| 角色分组相关方法 | 管理角色分组和分组内角色关系。 |
| `applyConversationSettings()` | 把历史对话设置快照应用到当前 UI。 |
| `repairMediaModelSelections()` | 修复已删除或不存在的模型引用。 |

`AppSettings.copyWith()` 对可清空字段使用 sentinel。调用者可以明确把字段清空为 `null`。

## FeatureProvider

文件：`lib/providers/feature_provider.dart`

负责日程、笔记、笔记分页、笔记文件夹、修订、AI 修改建议和待办清单。

| 分区 | Getter / 入口 | 存储含义 |
|------|---------------|----------|
| 日程 | `schedules` | 普通日程和任务类日程。 |
| 笔记 | `notes` | 笔记元数据和兼容正文。 |
| 笔记分页 | `pagesByNoteId`, `activePageIds` | storage_v2 下的分页元数据和当前活动分页。 |
| 文件夹 | `noteFolders` | 笔记文件夹。 |
| 修订 | `noteRevisions` | delta 修订树。 |
| 修改建议 | `getNoteEditProposal()` | AI 行级修改建议。 |
| 待办 | `todoLists` | 待办清单和任务。 |

### 日程

| 方法 | 说明 |
|------|------|
| `addSchedule()` | 新增普通日程或任务类日程。 |
| `updateSchedule()` | 修改日程。 |
| `deleteSchedule()` | 删除日程。 |
| `getSchedule()` | 按 ID 查询。 |

日程变更后 Android 会通过平台通道刷新小组件并重新安排通知。其他平台直接跳过。

### 笔记

| 方法 | 说明 |
|------|------|
| `addNote()` | 新建空笔记。 |
| `addNoteWithContent()` | 创建带内容的笔记并写入初始修订。 |
| `saveNoteContent()` | 保存正文并生成 delta 修订。 |
| `restoreNoteRevision()` | 把历史修订恢复为当前版本。 |
| `getNoteTimeline()` | 获取修订时间线。 |
| `getNoteContentAtRevision()` | 重放 delta 得到某个版本正文。 |
| `deleteNote()` | 删除笔记、分页、修订和修改建议。 |
| 文件夹方法 | 管理文件夹。 |
| 分页方法 | 创建、切换、保存、删除和重命名分页。 |

加载后会执行归一化：补齐缺失修订、清理不存在文件夹引用、清理不再适用的修改建议、刷新缓存。

### 待办

| 方法 | 说明 |
|------|------|
| `addTodoList()` | 新建清单。 |
| `updateTodoList()` | 修改标题或任务。 |
| `deleteTodoList()` | 删除清单。 |
| `reorderTodoLists()` | 清单排序。 |

清单内任务排序、Markdown 导入导出和长图分享在页面层完成。

## RoleplayProvider

文件：`lib/providers/roleplay_provider.dart`

负责情景演绎的情景、线程、运行状态、当前说话人、草稿和玩家排队消息。

| 状态 | 说明 |
|------|------|
| `scenarios` | 情景模板列表，带置顶和更新时间排序。 |
| `threads` | 演绎线程列表。 |
| `runState` | idle、directing、speaking、waitingUser、error。 |
| `activeThreadId` | 当前运行线程。 |
| `activeSpeakerName` | 当前 AI 说话人。 |
| `draftContent` | 流式生成中的草稿。 |
| `pendingPlayerMessages()` | AI 运行中排队的玩家消息。 |

| 方法 | 说明 |
|------|------|
| `loadSessions()` | 加载情景和线程。 |
| `replaceData()` | 备份导入或路径迁移时替换情景/线程。 |
| `createScenario()` / `updateScenario()` / `deleteScenario()` | 管理情景。 |
| `createThread()` / `deleteThread()` / `renameThread()` | 管理演绎线程。 |
| `updateThreadSettings()` | 修改线程导演、角色和自动轮次。 |
| `appendDraftAsCharacterMessage()` | 把生成草稿写入角色消息。 |
| 玩家消息方法 | 添加、排队、消费玩家消息。 |
| `repairModelReferences()` | 修复导演和角色绑定的模型引用。 |

情景和线程分别落盘。删除情景时会删除其线程，并清理相关运行状态。

## 容错加载

| 数据 | 行为 |
|------|------|
| 对话 | 坏对话跳过，坏消息跳过。 |
| 模型 | 坏配置跳过；顶层损坏时模型列表置空。 |
| 设置 | 坏角色、坏分组、坏提示词跳过；顶层损坏时使用默认设置。 |
| 日程/笔记/待办 | 单条坏记录跳过；顶层损坏时对应分区置空。 |
| 情景演绎 | 坏情景或坏线程跳过。 |
| 附件 | 兼容旧 `filePath`，并从路径推导文件名和 MIME。 |

## 修改 Provider 时要注意

1. 修改内存列表后要保存对应分区。
2. 影响 UI 的修改要 `notifyListeners()`。
3. 批量导入应尽量等待保存队列完成。
4. 删除模型后要修复设置、对话和情景演绎中的模型引用。
5. 修改笔记修订、分页或建议时要清理相关缓存。
6. 资源路径迁移使用 replace 接口，避免绕过保存队列。
