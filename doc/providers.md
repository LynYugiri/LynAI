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
    ChangeNotifierProvider(create: (_) => RecycleBinProvider()),
    ChangeNotifierProvider(create: (_) => RoleplayProvider()),
    ChangeNotifierProvider(create: (_) => SettingsProvider()),
    ChangeNotifierProvider(create: (_) => PluginProvider()),
    ChangeNotifierProvider(create: (_) => AccountProvider()),
  ],
)
```

启动时，应用先确保 storage_v2 已创建或升级，再并行加载各分区数据。

## 共同策略

Provider 的更新策略是：先改内存并通知 UI，再把快照放入保存队列。

```text
用户操作
  -> Provider 修改内存状态
  -> notifyListeners()
  -> 快照进入 Future 保存队列
  -> Repository
  -> storage_v2
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
| `appendImagesToLastAssistantMessage()` | 将生图 tool 生成的图片追加到最后一条 assistant 消息。 |
| `updateAgentPlan()` | 更新当前对话的 Agent 可视化计划。 |
| `updateAgentWorkingMemory()` | 更新当前对话持久化 Agent 工作记忆。 |
| `updateMessageContent()` | 编辑或重试时替换指定消息正文。 |
| `updateMessageImages()` | 重试版本切换时替换附件。 |
| `deleteMessage()` / `deleteConversation()` | 删除消息或对话。 |
| `searchConversations()` | 搜索标题、正文和附件名，返回类型化命中结果和高亮范围。 |
| `repairModelReferences()` | 修复已删除模型留下的对话引用。 |

`updateLastMessage()` 的 `thinkingContent` 有特殊语义：不传表示保留，传字符串表示覆盖，显式传 `null` 表示清空。

流式中间态通常使用 `save:false`，正常完成、停止或失败后再保存最终状态。

删除整条对话会先把对话快照写入回收站，再从历史列表移除；单条消息删除仍视为编辑行为，不进入回收站。

## ModelConfigProvider

文件：`lib/providers/model_config_provider.dart`

负责模型配置列表、分类查询和排序。

| 方法 | 说明 |
|------|------|
| `loadModels()` | 加载模型配置，坏配置跳过。 |
| `replaceModels()` | 备份导入时整体替换模型配置。 |
| `modelsByCategory()` | 获取某个分类的配置。 |
| `enabledModelsByCategory()` | 获取某个分类中至少有一个启用子模型、且未被本机关闭的可调用配置。 |
| `nextPriorityForCategory()` | 新增配置时计算分类内优先级。 |
| `syncLynaiManagedProvider()` | 登录后优先从后端 `/relay/config` 同步托管 LynAI Provider，旧后端回退 `/relay/models`；按 providerId、`api_type`、`category` 分组创建或更新配置。 |
| `removeLynaiManagedProviders()` | 登出或断开后端时移除托管 LynAI Provider。 |
| `setManagedDisabled()` | 在本机启用或关闭托管配置，不改写服务端基线。 |
| `setManagedUserOverride()` / `clearManagedUserOverride()` | 设置或清除托管配置的本机覆盖项。 |
| `addModel()` / `updateModel()` / `deleteModel()` | 增删改配置。 |
| `reorderModel()` / `reorderModelsInCategory()` | 全局或分类内排序。 |

模型排序先按 `category`，再按 `priority`。删除或导入替换模型后，应修复 Settings、Conversation 和 Roleplay 中的模型引用。`managed=true` 的托管 Provider 由同步流程维护，普通编辑和删除入口不会改写它们；托管 ID 形如 `__lynai_relay_<providerId>_<apiType>_<category>__`。

普通 Provider 编辑页提供逐 Provider 的“同步非秘密配置”开关，默认关闭。同步只传 `SyncedModelConfigV1`；安全存储引用和 API key 不会进入 Outbox。远端应用后重新加载模型、再次拉取托管 Relay 基线，并修复 Settings、Conversation 和 Roleplay 的模型引用。

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
| `setImageGenerationModelId()` / `setImageGenerationEnabled()` | 设置图片生成模型和当前默认开关。 |
| `setLastChatModelId()` | 设置新对话默认 Chat 模型。 |
| `addSystemPrompt()` / `updateSystemPrompt()` / `deleteSystemPrompt()` | 管理提示词模板。 |
| `addRole()` / `updateRole()` / `deleteRole()` / `selectRole()` | 管理角色。 |
| 角色分组相关方法 | 管理角色分组和分组内角色关系。 |
| `applyConversationSettings()` | 把历史对话设置快照应用到当前 UI。 |
| `repairMediaModelSelections()` | 修复已删除或不存在的模型引用。 |

`AppSettings.copyWith()` 对可清空字段使用 sentinel。调用者可以明确把字段清空为 `null`。

设置同步使用单例 `SharedSettingsV1` 记录，不同步整个 `app_settings` JSON。远端设置应用是字段投影合并，设备本地字段保持不变。若同一记录存在本地待上传变更，`SyncProvider` 沿用持久化 conflict 队列，先保留本地值，精确 ACK 对应 mutation version 后再应用被阻塞的远端版本，避免静默覆盖。

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
| `saveNoteContent()` | 保存正文并生成内容哈希修订；活动分页有冲突时拒绝普通保存。 |
| `restoreNoteRevision()` | 把历史修订恢复为当前版本。 |
| `getNoteTimeline()` | 获取修订时间线。 |
| `getNoteContentAtRevision()` | 读取已加载 blob 正文或兼容重放旧 delta；缺失 blob 显式失败。 |
| `loadNotePageMergeSession()` | 固定加载冲突的 base/local/incoming 三方正文和预期头集合。 |
| `commitNotePageMerge()` | 校验头集合未过期后提交双父修订；多于两个头时继续逐对合并。 |
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

日程、笔记、笔记分页和待办清单删除前会写入 `RecycleBinProvider`。storage_v2 笔记会同时保存分页元数据和 Markdown 正文，恢复时再写回分页文件。

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

情景和线程分别落盘。删除情景时会删除其线程，并清理相关运行状态。删除情景或线程会先写入回收站；删除情景时，与该情景关联的线程作为同一个回收站快照保存。

## RecycleBinProvider

文件：`lib/providers/recycle_bin_provider.dart`

负责回收站项目的加载、分类、永久删除和清空。回收站项目使用统一的 `RecycleBinItem`，通过 `owner/category/type/payload` 区分内置功能和插件来源。

| 类型 | 行为 |
|------|------|
| 内置功能 | 对话、笔记、笔记分页、日程、待办和情景演绎删除前写入回收站。 |
| 插件数据 | 插件通过 `recycleBin.putData` 写入自己的 opaque JSON，宿主不理解业务结构。 |
| 插件文件 | 插件通过 `recycleBin.putFile` 把 editableFiles 允许的文本文件写入回收站，可恢复回原路径。 |

插件本体删除不进入回收站；插件删除后，其回收站项目会保留但无法恢复，除非重新安装同 ID 插件。

## AccountProvider

文件：`lib/providers/account_provider.dart`

负责账号登录态管理，委托 `AccountService` 完成注册、登录、登出和会话恢复。Provider 只保存内存状态并通知 UI，不直接读写 SharedPreferences——持久化由 service 实现负责。

| 方法 | 说明 |
|------|------|
| `load()` | 启动时在 `BackendClient` 配置完成后从本地持久化恢复会话，未登录时不阻塞。 |
| `login(username, password)` | 手机号和密码登录，成功返回 true 并设置 `user`。 |
| `register(username, password, {displayName})` | 手机号和密码注册新用户，成功后自动登录。 |
| `logout()` | 登出并清除本地凭证。 |
| `clearError()` | 清除最近一次操作的错误信息。 |

| 状态 | 说明 |
|------|------|
| `user` | 当前登录用户，未登录时为 null。 |
| `isLoggedIn` | 是否已登录。 |
| `loading` | 是否正在执行登录/注册/登出。 |
| `error` | 最近一次操作的错误信息。 |
| `isBackendConnected` | 当前使用的账号服务是否已连接真实后端。 |

账号登录通过 `RemoteAccountService` 访问配置的后端；未配置后端地址时登录/注册不可用，`error` 会提示用户先配置后端。

账号恢复、登录、注册和登出会通知 `SyncProvider` 切换作用域。登出请求发送前会先尝试上传持久化 Outbox；失败的记录仍保留在对应账号作用域中，重新登录后可继续同步。

## SyncProvider

文件：`lib/providers/sync_provider.dart`

`SyncProvider` 串行执行自动、手动和生命周期同步。同步游标与待上传变更保存在 Drift 的 `sync_state`、`sync_outbox` 表中，并按“后端地址 + 用户 ID”隔离。`sync_state.captures_local` 持久记录当前本地 mutation 应归属的作用域：账号登出后、下一账号绑定前的编辑仍归原账号；绑定新账号后只转移云账号捕获权，LAN 作用域保持独立并可并行捕获。切换作用域前先 flush Provider 保存队列。每次本地保存立即按这些作用域生成行级 upsert/delete，远端应用永不写入 Outbox。

当前同步覆盖对话、消息、消息附件、附件资源、日程、待办、情景演绎和回收站。资源 Blob 在引用记录之前上传或下载，并在落盘前校验 SHA-256。远端批次应用后会重载相关 Provider，避免旧内存状态覆盖下载结果。

## PluginProvider

文件：`lib/providers/plugin_provider.dart`

负责插件的加载、安装、卸载、启用/禁用、权限管理和配置。

| 方法 | 说明 |
|------|------|
| `loadPlugins()` | 扫描插件目录，解析 `plugin.json`，跳过坏插件。 |
| `installPlugin()` | 解压 ZIP 到插件目录，解析 manifest 并注册到运行时。 |
| `uninstallPlugin()` | 删除插件目录和所有关联上下文。 |
| `uninstall()` | `uninstallPlugin` 的语义别名，供插件市场页使用，表达「从市场视角移除已安装插件」的意图。 |
| `enablePlugin()` / `disablePlugin()` | 启用时加载入口脚本并注册工具/函数；禁用时挂起沙箱并注销注册表。 |
| `syncBuiltinPlugins()` | 将 `assets/plugins/` 下的内置插件同步到插件目录；无权限、无工具、无函数且声明 `lynai.autoEnable=true` 的纯 Skill 内置插件首次同步时会自动启用。 |
| `snapshotPlugins()` | 把当前已安装插件的状态打包为 ZIP 导出。 |
| `togglePluginTool()` / `togglePluginFunction()` | 独立开关某个工具或函数，不影响插件的其他能力。 |
| `updatePluginPermissions()` | 修改用户授予的权限列表。 |
| `updatePluginConfig()` | 根据 `PluginConfigSchema` 更新插件配置字段。 |
| `getPluginFeaturePage()` | 获取插件的功能页 HTML 路径，供 `PluginFeaturePage` 加载。 |

### 运行时状态

`PluginProvider` 维护以下内存状态：

| 状态 | 说明 |
|------|------|
| `installedPlugins` | 所有已安装插件列表，含内置和用户安装。 |
| `enabledPlugins` | 当前启用的插件，其工具注册在 `LynAIFunctionService`。 |
| `activePluginNames` | 工具注册表中活跃的插件名集合。 |
| `pluginConfigs` | 每个插件当前的配置键值对。 |

### 权限模型

插件需在 `plugin.json` 中声明权限，用户安装后可在管理页修改授予范围。实际执行时 `PluginLuaRuntimeService` 会根据授予权限裁剪沙箱 API。内置 `mobile-agent-skills` 是纯 Skill 插件，不声明权限，不执行工具，只为 Agent 提供工作流说明。当前 15 个 skill：`android_accessibility`（无障碍原语）、`messaging`（消息应用通用流程）、`qq`（QQ 自动回复）、`wechat`（微信会话自动化）、`system_settings`（系统设置开关）、`browser_search`（浏览器搜索与信息采集）、`camera_ocr_scan`（拍照与 OCR 扫描）、`contacts_phone`（通讯录与电话）、`clock_alarm`（系统闹钟与倒计时）、`map_navigation`（地图导航）、`media_share`（系统分享与跨应用转发）、`study_problem_solving`（题目解答与错题本沉淀）、`study_research_qa`（开放问题检索综述）、`note_taking`（笔记方法论与新建/编辑/归档）、`note_capture_to_kb`（对话沉淀到知识库）。Skill 正文可编辑性由 `PluginSkillDefinition.editable` 和 `editableFiles/defaultPath` overlay 决定；内置 Skill 的模板放在 `defaults/skills/`，用户/模型写入的 `skills/` 文件会在同步内置插件时保留。

| 权限 | 控制的能力 |
|------|-----------|
| `network` | HTTP 请求能力。启用后沙箱注入 `http.get` 和 `http.post`。 |
| `file_read` | 读取用户授权目录内的文件。 |
| `file_write` | 写入插件目录和用户授权目录。 |
| `platform` | 调用受控的平台能力，如通知和剪贴板。 |

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
5. 修改笔记修订、分页或建议时只清理失效缓存，不能丢弃已加载的内容哈希正文。
6. 资源路径迁移使用 replace 接口，避免绕过保存队列。
# Plugin Sync State

`PluginProvider` emits content-hashed, sanitized plugin snapshots after install, uninstall, editable file changes, settings changes, and config changes when a sync scope is active. Each snapshot has a versioned exact-file manifest and explicit installed/deleted marker; missing rows do not uninstall anything. Private `plugin_storage` changes remain device-local and never trigger cloud or LAN synchronization. It materializes only complete validated packages after durable sync conflict handling and tags restored third-party installations with the exact cloud or LAN scope. A tombstone can delete only a plugin restored by that same scope; unknown legacy provenance is preserved. Trust state is reset only when third-party package content changes; settings/config-only and unrelated remote changes preserve local enabled/review/grant state, and settings/config cannot bootstrap a missing plugin.

`SyncProvider` scopes cloud state and device identity to normalized backend origin
plus user ID. Upload batches are cut from the final encoded JSON UTF-8 body and
never exceed 2 MiB or 500 changes.

`LanSyncProvider` reports pairing and initial synchronization separately. A
trusted pairing remains successful when the automatic first bidirectional sync
fails, and the UI presents that outcome as partial success with a retry path.
## LanSyncProvider

Owns LAN page state: discovered devices, trusted/revoked peers, host/discovery
status, last sync time, and errors. It delegates protocol and storage work to
`LanSyncCoordinator` and `LanPeerRepository`.
