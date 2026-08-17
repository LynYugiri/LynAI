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
    ChangeNotifierProvider(create: (_) => CloudDataProvider()),
    ChangeNotifierProvider(create: (_) => McpProvider()),
  ],
)
```

启动时，应用先确保 storage_v2 已创建或升级，再并行加载各分区数据。

## McpProvider

文件：`lib/providers/mcp_provider.dart`

`McpProvider` 是 MCP 设置页和动态工具注册的内存入口。它加载公开 server rows 与 `SecretStore` preferences，维护 `disconnected`、`connecting`、`connected`、`failed` 状态；启用的 server 在启动加载后异步连接，不阻塞其他 Provider 加载完成。

| 能力 | 行为 |
|------|------|
| `load()` | 断开旧连接，加载 server 与 preferences，并后台连接 enabled server。 |
| `saveServer()` | 先断开旧连接，再分别保存公开配置、preferences 和 credential values；启用时重新连接。 |
| `connect()` / `disconnect()` | 创建或释放 client、订阅状态/工具变化，并注册或移除当前连接持有的工具。 |
| `setToolEnabled()` | 把逐工具开关写入 `SecretStore` preferences，并同步共享 registry。 |
| `testConnection()` | 断开后重新连接，以最终连接状态作为结果。 |

MCP 工具通过共享 `AgentToolNameCodec` 把 source、server ID 和远端名称编码为最长 64 字符的 `tool_v1_*` canonical name，来源标为 `mcp`、副作用标为 `external`、当前并发策略为 `parallelSafe`。原始 `inputSchema` 必须完整通过 `AgentJsonSchemaValidator`；Provider 会保留但不注册不兼容工具，并把具体 schema issue 写入 server error，不会通过删除 keyword 静默放宽约束。server 通知 `notifications/tools/list_changed` 时 Provider 重新拉取工具；名称冲突会记录错误而不覆盖非本连接持有的 registration。断开连接只移除 registration ID 仍与本连接一致的项，避免删除后来替换的工具。

公开 server row 在 Drift；credential value、credential target、HTTP/私网许可和 enabled tool map 在 `SecretStore`。当前实现没有删除 server 的 Repository/API，也没有 MCP resources、prompts 或 sampling 状态。

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

串行队列由 `SerializedSaveQueue` mixin（`providers/serialized_save_queue.dart`）统一提供：`enqueueSave(saver)` 入队并返回原始操作（保留错误传播），`flushPendingSaves()` 先执行 `onBeforeFlush()` 钩子再等待队尾，`pendingSaveQueue` 等待已吞错尾链。已接入该 mixin 的 Provider：conversation、calendar、model_config、roleplay、settings、task；`ConversationProvider` 通过覆写 `onBeforeFlush()` 在 flush 前强制排空 500ms 防抖快照。`KnowledgeProvider` 因类型化 `_runMutation<T>`、失败回滚快照与静默吞错语义保留自己的实现，不接入 mixin。

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
| `moveTask()` / 排序 | 一个任务最多一个归属条目；移动到 `null` 后成为未归入清单的任务。 |
| 查询 | `tasksForList`、`unlistedTasks`、`todayTasks`、`overdueTasks`。 |
| `flushPendingSaves()` | 等待 `tasks.json` 的真实 Repository 写入完成。 |

删除任务会把任务及其可选清单条目写入回收站；删除清单只回收清单与条目，任务实体保留为未归入清单的任务。`unfinishedTasks` 和 `completedTasks` 是按 `completedAt` 计算的内存聚合，不是持久化清单。日常任务、清单和归属变更按受影响行写入同一事务；导入或整体替换才使用完整分区替换。Provider 仍先通知内存变化，再通过共享串行队列持久化。

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
| `peekManagedModelIdMigrations()` / `ackManagedModelIdMigrations()` | 读取并在所有引用持久化成功后确认旧托管模型 ID 到 category ID 的持久迁移。 |
| `syncLynaiManagedModels()` | 登录后从后端 `/relay/config` 同步 `schemaVersion: 4` 平铺模型，并按规范化 category 创建或更新一个 LynAI 配置。 |
| `removeLynaiManagedModels()` | 登出或断开后端时移除托管 LynAI 模型配置。 |
| `setManagedDisabled()` | 在本机启用或关闭托管配置，不改写服务端基线。 |
| `setManagedUserOverride()` / `clearManagedUserOverride()` | 设置或清除托管配置的本机覆盖项。 |
| `addModel()` / `updateModel()` / `deleteModel()` | 增删改配置。 |
| `reorderModelsInCategory()` | 调整分类内排序。 |

加载本地模型或导入 API 配置时，Provider 会把同一规范化 category 下的旧 Provider-scoped 托管配置原子合并为 `__lynai_relay_<category>__`，合并去重后的离线模型列表并保存 pending 映射。迁移协调器串行更新 Settings、Conversation、Roleplay 与 Plugin 引用，全部持久化成功后才 ACK；启动、远端应用、密钥导入、手动刷新、后端变更和备份导入都会执行该流程。网络同步仍只接受 relay schema v4。

模型排序先按 `category`，再按 `priority`。`managed=true` 的托管配置由同步流程维护，普通编辑和删除入口不会改写它们；托管 ID 形如 `__lynai_relay_<category>__`。同步先构建完整下一集合，再一次性替换当前托管数据；离线、请求失败和无效响应不会清空现有数据。相同 ID 更新时保留本地排序、当前模型、禁用状态和用户覆盖。

普通 Provider 编辑页提供逐 Provider 的“同步非秘密配置”开关，默认关闭。同步只传 `SyncedModelConfigV1`；安全存储引用和 API key 不会进入 Outbox。远端应用后重新加载模型并再次拉取托管 Relay 基线。

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
| `restoreLocalSession()` | 只从本地持久化恢复 token 和缓存用户，并等待本地同步作用域绑定，不请求后端。 |
| `refreshCurrentSession()` | 在后台通过 `/auth/me` 刷新当前缓存用户；临时错误保留缓存会话。 |
| `activateCurrentSession()` | 在后台执行设备注册和当前 session 的远端激活任务。 |
| `load()` | 兼容入口，依次执行本地恢复、远端刷新和激活。启动组合根不使用它阻塞首屏。 |
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

账号本地恢复、登录、注册和登出会等待物理 dataset 与 `SyncProvider`/`CloudDataProvider` 本地作用域切换，保证进入可编辑 UI 或关闭登录框前数据归属已经确定。登出、明确会话失效或后端切换只有在本地 dataset 激活成功后才发布未登录状态；激活失败时保留原认证 publication 并展示阻塞错误，绝不让未登录 UI 继续读取上一账号 dataset。设备注册、自动云同步和托管模型网络刷新不属于登录成功条件，在本地作用域绑定后后台执行。显式登出本地优先，等待作用域解绑但不等待网络撤销或 Outbox 上传；失败的 Outbox 仍保留在对应账号作用域中，重新登录后可继续同步。

## SyncProvider

文件：`lib/providers/sync_provider.dart`

`SyncProvider` 串行执行自动、手动和生命周期同步，并与 LAN 共用 `RemoteApplyCoordinator` 串行本地提交阶段。每次普通自动或手动同步先通过共享 `CloudManagementCoordinator` 发现 pending management operation；发现后持久化并强制 reseed，完整同步成功且 scope/generation 仍匹配时才 ACK。支持 index 时 reseed 不再把全部本地行重建成 Outbox，而是在固定 `indexRevision` 下读取 current projection：远端缺失且没有本地 pending mutation 的行按 absent-record 语义删除，真实 pending upsert/delete 保留原 mutation identity；随后原子写入最新 generation 和 `minAvailableSeq` cursor，再恢复增量同步。多个 operation 以最高 generation 为完成条件，旧 operation 不会阻塞最新 generation。类型化 generation/stale/future cursor 冲突或 index revision 竞态只允许重新 status/reseed 一次。同步游标与待上传变更保存在 Drift 的 `sync_state`、`sync_outbox` 表中，并按“后端地址 + 用户 ID”隔离。`sync_state.captures_local` 持久记录当前本地 mutation 应归属的作用域：账号登出后、下一账号绑定前的编辑仍归原账号；绑定新账号后只转移云账号捕获权，LAN 作用域保持独立并可并行捕获。切换作用域前先 flush Provider 保存队列。每次本地保存立即按这些作用域生成行级 upsert/delete，远端应用永不写入 Outbox。后端或账号作用域变化会推进 generation；已排队或正在等待网络的旧 generation 在写游标、ACK 或刷新 Provider 前退出，避免旧作用域结果落到新作用域。

每个云 scope 在本机 `sync_policies` 中保存用户选择的数据分类。缺失策略默认启用全部业务分类但关闭静态资源。上传在读取 Blob 前过滤 Outbox；下载在准备远端操作和下载 Blob 前过滤 change，同时仍推进全局 cursor。重新开启分类会标记 full reseed，关闭分类不删除本机或云端已有数据。静态资源关闭时仍同步消息附件元数据和 `modelContextContent`，但不传对话附件、图片或背景 Blob。

当前同步覆盖对话、消息、消息附件、附件资源、`tasks`/`task_lists`/`task_list_entries`、`calendar_events`/`anniversaries`、笔记、情景演绎和回收站。下载页会校验 change 必填字段、操作类型、`data.id`、页内严格递增 seq、重复 changeId 和 nextSince；上传只有在 legacy 整批 ACK 或精确匹配当前批次的 changeId/mutation version ACK 通过校验后才删除 Outbox。Outbox 以 256 行窗口读取，Blob 先收集描述符，确认远端缺失后才读取本地字节。资源 Blob 在引用记录之前上传或下载，并校验大小与 SHA-256。

每次同步累积 `changedTables`，远端应用前只 flush 可能冲突的 Provider，完成后只重载受影响 Provider、插件或 Android 规划投影。涉及笔记表时，分页 Markdown materialization 在整次云同步结束时执行一次，而不是每个下载页执行；冲突解决仍按受影响表单独刷新。

## CloudDataProvider

文件：`lib/providers/cloud_data_provider.dart`

`CloudDataProvider` 是数据管理页的云端管理状态入口。它按规范化后端 origin 和用户 ID 绑定 scope，从 `CloudDataRepository` 先恢复索引状态、分类统计、对象列表和 pending management operation 缓存，再通过 `CloudDataService` 刷新真实后端。刷新只有在 status 和全部分类对象页都成功后才原子替换缓存；网络或 revision 冲突不会清空旧缓存。Provider 分别暴露 index 浏览、selective purge、full purge 和 operation ACK 能力，页面和调用入口都执行独立门控；ACK capability 缺失时不会发 ACK，也不会从持久化状态清除 operation。

purge 先由页面请求 preview 并确认，Provider 提交签名写后立即持久化返回的 operation，再刷新索引。UI 手动同步与普通自动/手动同步复用 `CloudManagementCoordinator`，不互相读取 Provider，避免循环依赖。ACK ID 由 scope、operation 和 generation 确定性生成；同步或 ACK 中途失败时 task 保留，下次同步继续处理。重新绑定账号会立即清除旧操作的 loading 状态，旧异步结果不能让页面永久停留在加载中。

## PluginProvider

文件：`lib/providers/plugin_provider.dart`

负责插件的加载、安装、卸载、启用/禁用、权限管理和配置。

同一插件 ID 的安装、删除、权限/能力切换、配置、设置和文件写入都进入该 ID 的串行 mutation 队列。所有插件文件系统导入、安装、卸载、快照和远端 materialization 还必须持有 `DatasetRuntimeBarrier` 捕获的 generation；物理 dataset 切换会等待已接纳 mutation 完成并拒绝跨 generation 发布。远端 materialization 批次全局串行，不同插件可在批次内部并行，但仍与各自本地 mutation 互斥；已安装插件列表的持久化另有全局保存尾链，避免并发快照后写覆盖。队列即使某次操作失败也会恢复，后续操作仍可执行。

| 方法 | 说明 |
|------|------|
| `load()` | 加载已安装插件状态。 |
| `importZipBytes()` / `importDirectory()` | 校验 manifest 后安装插件；同 ID 安装与其他 mutation 串行。 |
| `deletePlugin()` / `uninstall()` | 删除可卸载插件、关联数据和同步删除标记。 |
| `setEnabled()` / `setGrantedPermissions()` | 修改插件启用和授权状态；启用时校验依赖已安装、启用且版本满足约束，禁用时阻止关闭仍被依赖的插件。 |
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

插件需在 `plugin.json` 中声明权限，用户安装后可在管理页修改授予范围；管理页的权限区还会列出调用依赖插件 `expose` 函数时其 `requires` 声明的额外权限。实际执行时 `PluginLuaRuntimeService` 会根据授予权限裁剪沙箱 API。内置 `mobile-agent-skills` 是纯 Skill 插件，不声明权限，不执行工具，只为 Agent 提供工作流说明。当前 14 个 skill：`android_accessibility`（无障碍原语）、`messaging`（消息应用通用流程）、`qq`（QQ 自动回复）、`wechat`（微信会话自动化）、`system_settings`（系统设置开关）、`camera_ocr_scan`（拍照与 OCR 扫描）、`contacts_phone`（通讯录与电话）、`clock_alarm`（系统闹钟与倒计时）、`map_navigation`（地图导航）、`media_share`（系统分享与跨应用转发）、`study_problem_solving`（题目解答与错题本沉淀）、`study_research_qa`（开放问题检索综述）、`note_taking`（笔记方法论与新建/编辑/归档）、`note_capture_to_kb`（对话沉淀到知识库）。Skill 正文可编辑性由 `PluginSkillDefinition.editable` 和 `editableFiles/defaultPath` overlay 决定；内置 Skill 的模板放在 `defaults/skills/`，用户/模型写入的 `skills/` 文件会在同步内置插件时保留。

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

`LanSyncProvider` reports pairing separately from synchronization. Pairing
returns the trusted peer and discovered endpoint so the UI can ask whether to
sync now or later. It also persists immediate policy reductions and coordinates
authenticated, peer-approved additions.
## LanSyncProvider

Owns LAN page state: discovered devices, trusted/revoked peers, host/discovery
status, stable editable local device name, per-peer sync selection, last sync time, and errors. The foreground lifecycle starts trusted-peer hosting and background lifecycle stops it. It delegates protocol and storage work to
`LanSyncCoordinator` and `LanPeerRepository`. Disposal is ownership-aware:
subscriptions stop updating disposed state, the provider closes its coordinator,
the coordinator stops hosting and closes its per-instance secret-transfer stream,
while the globally provided mDNS service is disposed by Provider registration.
LAN conflicts are loaded from the `lan:v1` scope and resolved through the same storage conflict engine used by cloud sync.
## Conversation Permission Migration

Startup loads `SettingsProvider` before `ConversationProvider`. Permissions are a
global single source in `AppSettings.agentGrantedPermissions`; `ConversationSettings`
no longer carries permission fields (legacy `agentPermissionsOverride`/
`agentGrantedPermissions`/`permissionSnapshotVersion` are ignored on load), and
the previous conversation permission migration has been removed. `SettingsProvider`
exposes `updateAgentDefaults` for both the settings page and the conversation
settings sheet to edit the same global list.
## Account dataset binding

`AccountProvider` invokes dataset activation before publishing a restored,
logged-in, or newly registered user. Logout, refresh invalidation, and backend
scope changes activate the permanent local dataset before clearing the published
user. The runtime coordinator flushes conversations, features, calendar,
roleplay, tasks, settings, models, then plugins, and reloads providers in the
same deterministic sequence after a successful switch. Failed target activation
rolls back to the previous dataset and leaves the target user unpublished.
`AccountProvider.reconfigureBackend` is the coordinated backend configuration entry point. It awaits device/settings persistence, activates the local dataset and unbinds session-scoped sync state, then changes `BackendClient`; callers must await it before running backend-dependent model synchronization. Session invalidation callbacks are generation-checked so an older refresh rejection cannot clear a newer login.
# KnowledgeProvider

`KnowledgeProvider` 是知识库、类别、条目、来源和解释的唯一内存所有者。公开写操作串行执行，每次先捕获完整内存快照，再更新内存、通知 UI 并持久化；持久化失败时恢复快照、再次通知并向调用方抛出错误，因而单次 mutation 不会留下只存在于内存的状态。它在 `load()` 和 `replaceAll()` 后幂等补齐固定 ID 的内置专有名词知识库及类别，并确定性修复内置类别父 ID、alias 冲突、无效类别引用和悬空或跨库子记录；机械修复保留原 `updatedAt`，加载修复以完整规范化快照原子持久化，失败时恢复加载前内存。Provider 还提供 alias 查询、固定内置 annotation fallback、聊天标注 prompt 快照、内置模板恢复、行级 CRUD、完整分区替换及 `flushPendingSaves()`。Repository/Provider 不再读写知识默认设置；旧 storage 键可由底层暂时兼容。删除普通知识库时会显式删除全部子行，以便云和 LAN 同步生成完整 tombstone，而不只依赖 SQLite cascade；内置知识库和类别拒绝删除。

## JottingProvider

文件：`lib/providers/jotting_provider.dart`

`JottingProvider` 是随记的唯一内存所有者，`ChangeNotifier with SerializedSaveQueue`。它持有按 `createdAt DESC, id` 排序的 `List<Jotting>`，提供 `add/update/delete/restorePayload` 与 `search/onThisDay/tagCounts`。变更先更新内存并通知 UI，再 `enqueueSave` 全量快照到 `jottings.json`；`load()` 使用 mutation generation 防竞态。删除先写入 `RecycleBinRepository`，再从内存移除。`add`/`update` 持久化失败时会回滚内存中的乐观状态并重新抛出，页面依赖该语义保留编辑内容。
