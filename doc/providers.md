# 状态管理

LynAI 使用 `Provider + ChangeNotifier`。Provider 是 UI 状态和业务操作入口，Repository 是持久化边界。

## 注册

Provider 在 `main.dart` 中注册：

```dart
MultiProvider(
  providers: [
    ChangeNotifierProvider(create: (_) => ConversationProvider()),
    ChangeNotifierProvider(create: (_) => FeatureProvider()),
    ChangeNotifierProvider(create: (_) => CalendarProvider()),
    ChangeNotifierProvider(create: (_) => TaskProvider()),
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

Provider 的更新策略是：先改内存并通知 UI，再把持久化操作放入保存队列。

```text
用户操作
  -> Provider 修改内存状态
  -> notifyListeners()
  -> 行级变更或完整替换进入 Future 保存队列
  -> Repository
  -> storage_v2
```

这样 UI 反馈更快，连续操作也不会让旧异步写入覆盖新状态。保存失败会记录到 `debugPrint`，并由当前操作或 `flushPendingSaves()` 观察；串行尾链会恢复，后续保存仍可继续。聚合 flush 会尝试所有 Provider 并汇总失败，调用方不能在任一保存失败后继续上传或应用远端状态。

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

对话保存有短 debounce，但 `flushPendingSaves()` 会立即提交尚未入队的最新快照并等待真实 Repository 写入。加载分区失败时保留当前对话列表并向调用方传播。

删除整条对话会先把对话快照写入回收站，再从历史列表移除；单条消息删除仍视为编辑行为，不进入回收站。

## TaskProvider

文件：`lib/providers/task_provider.dart`

`TaskProvider` 是 `tasks.json` 分区中 `Task`、`TaskList` 和 `TaskListEntry` 的唯一内存所有者，三类数据共享一条串行保存队列。UI、规范工具、旧 todo 兼容 API、同步和备份都通过该 Provider 读写任务数据；`FeatureProvider` 不再拥有待办数据。

| 能力 | 行为 |
|------|------|
| `load()` / `replaceAll()` | 加载或整体替换任务、清单和归属快照；替换时过滤悬空条目并按 `sortOrder` 排列清单。 |
| 任务 CRUD | 支持计划/截止时间、提醒、完成/取消完成和可选清单归属。 |
| 清单 CRUD | 清单元数据和清单间排序独立于任务。 |
| `moveTask()` / 排序 | 一个任务最多一个归属条目；移动到 `null` 后进入收件箱/未归类。 |
| 查询 | `tasksForList`、`unlistedTasks`、`todayTasks`、`overdueTasks`。 |
| `flushPendingSaves()` | 等待 `tasks.json` 的真实 Repository 写入完成。 |

删除任务会把任务及其可选清单条目写入回收站；删除清单只回收清单与条目，任务实体保留为未归类任务。日常任务、清单和归属变更按受影响行写入同一事务；导入或整体替换才使用完整分区替换。Provider 仍先通知内存变化，再通过共享串行队列持久化。

## CalendarProvider

文件：`lib/providers/calendar_provider.dart`

`CalendarProvider` 是 `calendar.json` 中 `CalendarEvent` 和 `Anniversary` 的唯一内存权威；`FeatureProvider` 不再拥有日程数据。它提供事件和纪念日 CRUD、回收站恢复、完整快照替换，以及基于调用方任务集合的范围发生记录查询。

`occurrencesInRange()` 委托 `CalendarOccurrenceService` 生成只读 `CalendarOccurrence`，不会把发生记录反向保存。删除事件或纪念日会先形成对应回收站 payload；加载时单条损坏记录由 Repository 跳过，顶层失败继续向调用方传播。

`CalendarProvider` 的事件和纪念日 CRUD 按受影响行写入；完整替换只用于导入、恢复或重载。`TaskProvider` 与 `CalendarProvider` 在持久化成功后只通知 `CalendarPlatformProjectionCoordinator`。协调器等待两个保存队列并串行生成一份 Android 完整投影，避免两个 Provider 并发覆盖小组件和通知状态；启动、备份恢复和相关远端同步重载完成后也会显式同步一次。

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
| `syncLynaiManagedProvider()` | 登录后只从后端 `/relay/config` 同步 `schemaVersion: 3` 的托管 Provider；按 `providerId + category` 分组创建或更新配置。 |
| `takeManagedModelIdMigrations()` | 一次性返回并清空最近同步精确匹配到的旧托管模型 ID 到新 ID 映射。 |
| `removeLynaiManagedProviders()` | 登出或断开后端时移除托管 LynAI Provider。 |
| `setManagedDisabled()` | 在本机启用或关闭托管配置，不改写服务端基线。 |
| `setManagedUserOverride()` / `clearManagedUserOverride()` | 设置或清除托管配置的本机覆盖项。 |
| `addModel()` / `updateModel()` / `deleteModel()` | 增删改配置。 |
| `reorderModelsInCategory()` | 调整分类内排序。 |

模型排序先按 `category`，再按 `priority`。`managed=true` 的托管 Provider 由同步流程维护，普通编辑和删除入口不会改写它们；托管 ID 形如 `__lynai_relay_<providerId>_<category>__`。从旧 ID 迁移时保留本地排序、当前模型、禁用状态和用户覆盖，并用持久化的 peek/ack pending 映射精确更新 Settings、Conversation、Roleplay 和插件 model 字段。所有分区保存成功后才 ack；未登录、401 或任一保存失败都保留映射供重试。插件递归迁移只遍历 config schema 明确声明的 `type=model` 字段。

普通 Provider 编辑页提供逐 Provider 的“同步非秘密配置”开关，默认关闭。同步只传 `SyncedModelConfigV1`；安全存储引用和 API key 不会进入 Outbox。远端应用后重新加载模型、再次拉取托管 Relay 基线，并按 Settings、Conversation、Roleplay 的固定顺序应用和持久化精确 ID 映射。

## SettingsProvider

文件：`lib/providers/settings_provider.dart`

负责应用级设置、角色、角色分组、系统提示词和最近使用模型。

| 方法 | 说明 |
|------|------|
| `loadSettings()` | 加载设置；分区失败保留当前内存并向启动流程传播。 |
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
| `repairMediaModelSelections()` | 修复已删除或不存在的模型引用。 |

`AppSettings.copyWith()` 对可清空字段使用 sentinel。调用者可以明确把字段清空为 `null`。

设置同步使用单例 `SharedSettingsV1` 记录，不同步整个 `app_settings` JSON。远端设置应用是字段投影合并，设备本地字段保持不变。若同一记录存在本地待上传变更，`SyncProvider` 沿用持久化 conflict 队列，先保留本地值，精确 ACK 对应 mutation version 后再应用被阻塞的远端版本，避免静默覆盖。

系统提示词选择会同时更新当前全局提示词正文。创建或编辑对话时，该正文复制到 `ConversationSettings`；打开历史对话只读取其快照，不再调用 SettingsProvider 覆盖全局设置。

## FeatureProvider

文件：`lib/providers/feature_provider.dart`

负责笔记、笔记分页、笔记文件夹、修订和 AI 修改建议。

| 分区 | Getter / 入口 | 存储含义 |
|------|---------------|----------|
| 笔记 | `notes` | 笔记元数据和兼容正文。 |
| 笔记分页 | `pagesByNoteId`, `activePageIds` | storage_v2 下的分页元数据和当前活动分页。 |
| 文件夹 | `noteFolders` | 笔记文件夹。 |
| 修订 | `noteRevisions` | delta 修订树。 |
| 修改建议 | `getNoteEditProposal()` | AI 行级修改建议。 |

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

加载后会执行归一化：补齐缺失修订、清理不存在文件夹引用、清理不再适用的修改建议、刷新缓存。笔记文件夹、元数据、分页、修订、删除 tombstone、冲突和修改建议通过同一个真实串行写入队列持久化，`flushPendingSaves()` 会等待该聚合写入。

笔记和笔记分页删除前会写入 `RecycleBinProvider`。storage_v2 笔记会同时保存分页元数据和 Markdown 正文，恢复时再写回分页文件；分页或整笔记删除会为每个被移除修订创建 tombstone，并额外写入 `revisionId='*'` 的分页 tombstone；单独删除 revision branch 时会为每个带 page ID 的修订创建精确 tombstone，旧版无 page ID 修订仍只执行本地兼容删除。普通保存不会清空已有 tombstone；显式恢复同一分页时才移除对应分页 tombstone并产生可同步的 tombstone delete。

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
| 内置功能 | 对话、笔记、笔记分页、规范任务、任务清单、日历事件、纪念日和情景演绎删除前写入回收站。旧 `ScheduleItem`/`TodoList` payload 仅在恢复时转换。 |
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

`SyncProvider` 串行执行自动、手动和生命周期同步。同步游标与待上传变更保存在 Drift 的 `sync_state`、`sync_outbox` 表中，并按“后端地址 + 用户 ID”隔离。`sync_state.captures_local` 持久记录当前本地 mutation 应归属的作用域：账号登出后、下一账号绑定前的编辑仍归原账号；绑定新账号后只转移云账号捕获权，LAN 作用域保持独立并可并行捕获。切换作用域前先 flush Provider 保存队列。每次本地保存立即按这些作用域生成行级 upsert/delete，远端应用永不写入 Outbox。后端或账号作用域变化会推进 generation；已排队或正在等待网络的旧 generation 在写游标、ACK 或刷新 Provider 前退出，避免旧作用域结果落到新作用域。

当前同步覆盖对话、消息、消息附件、附件资源、`tasks`/`task_lists`/`task_list_entries`、`calendar_events`/`anniversaries`、笔记、情景演绎和回收站。下载页会校验 change 必填字段、操作类型、`data.id`、页内严格递增 seq、重复 changeId 和 nextSince；上传只有在 legacy 整批 ACK 或精确匹配当前批次的 changeId/mutation version ACK 通过校验后才删除 Outbox。Outbox 以 256 行窗口读取，Blob 先收集描述符，确认远端缺失后才读取本地字节。资源 Blob 在引用记录之前上传或下载，并校验大小与 SHA-256。

每次同步累积 `changedTables`，远端应用前只 flush 可能冲突的 Provider，完成后只重载受影响 Provider、插件或 Android 规划投影。涉及笔记表时，分页 Markdown materialization 在整次云同步结束时执行一次，而不是每个下载页执行；冲突解决仍按受影响表单独刷新。

## PluginProvider

文件：`lib/providers/plugin_provider.dart`

负责插件的加载、安装、卸载、启用/禁用、权限管理和配置。

同一插件 ID 的安装、删除、权限/能力切换、配置、设置和文件写入都进入该 ID 的串行 mutation 队列。远端 materialization 批次全局串行，不同插件可在批次内部并行，但仍与各自本地 mutation 互斥；已安装插件列表的持久化另有全局保存尾链，避免并发快照后写覆盖。队列即使某次操作失败也会恢复，后续操作仍可执行。

| 方法 | 说明 |
|------|------|
| `load()` | 加载已安装插件状态。 |
| `importZipBytes()` / `importDirectory()` | 校验 manifest 后安装插件；同 ID 安装与其他 mutation 串行。 |
| `deletePlugin()` / `uninstall()` | 删除可卸载插件、关联数据和同步删除标记。 |
| `setEnabled()` / `setGrantedPermissions()` | 修改插件启用和授权状态。 |
| `setToolEnabled()` / `setFunctionEnabled()` / `setSkillEnabled()` | 独立开关插件能力。 |
| `importBuiltIn()` / `syncBuiltIn()` | 导入或同步内置插件；安全的纯 Skill 插件可按 manifest 自动启用。 |
| `createSnapshot()` / `restoreSnapshotToSource()` | 创建独立快照或把快照内容恢复到来源插件。 |
| `updateSetting()` / `saveConfig()` | 更新插件设置或配置，并生成允许的同步投影。 |
| `writeEditableFile()` / `writeFileBytes()` | 在 editableFiles 边界内写入插件文件。 |
| `applyRemoteSync()` | 串行 materialize 已验证的云端或 LAN 插件包。 |

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
| 模型 | 坏配置跳过；分区加载失败保留当前列表并向调用方传播。 |
| 设置 | 坏角色、坏分组、坏提示词跳过；分区加载失败保留当前设置并向调用方传播。 |
| 日程/笔记/待办 | 单条坏记录跳过；任一顶层分区读取失败时保留当前 Feature 状态并向调用方传播。 |
| 情景演绎 | 坏情景或坏线程跳过；分区读取失败保留当前状态并向调用方传播。 |
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
plus user ID. It reads the persistent Outbox in 256-row windows, lazily opens
referenced blobs, and cuts each upload batch from the final encoded JSON UTF-8
body without exceeding the server-advertised change-count and byte limits.

`LanSyncProvider` reports pairing and initial synchronization separately. A
trusted pairing remains successful when the automatic first bidirectional sync
fails, and the UI presents that outcome as partial success with a retry path.
## LanSyncProvider

Owns LAN page state: discovered devices, trusted/revoked peers, host/discovery
status, last sync time, and errors. It delegates protocol and storage work to
`LanSyncCoordinator` and `LanPeerRepository`. Disposal is ownership-aware:
subscriptions stop updating disposed state, the provider closes its coordinator,
the coordinator stops hosting and closes its per-instance secret-transfer stream,
while the globally provided mDNS service is disposed by Provider registration.
