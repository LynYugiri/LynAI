# 架构说明

LynAI 的架构目标是让页面、状态、存储、协议和数据模型各做各的事。功能可以增加，但边界不应该模糊：Page 处理交互，Provider 维护状态，Repository 读写本地数据，Service 处理外部能力，Model 只描述数据。

## 分层

```text
用户操作
  -> Page：展示界面、收集输入、处理生命周期
  -> Provider：更新内存状态、通知 UI、排队保存快照
  -> Repository：读写 storage_v2
  -> Model：不可变数据和 JSON 契约

外部能力
  -> Service：模型 API、工具调用、备份、平台通道、storage_v2 升级
```

| 层 | 典型文件 | 禁止事项 |
|----|----------|----------|
| Page | `chat_page.dart`, `feature_page.dart`, `settings_page.dart` | 不直接写持久化，不把 API 协议散落到 UI。 |
| Provider | `providers/*.dart` | 不展示 UI，不直接读写 storage_v2。 |
| Repository | `repositories/*.dart` | 不通知 UI，不持有页面状态。 |
| Service | `api_service.dart`, `backup_service.dart`, `tool_call_service.dart` | 不依赖 `BuildContext`，不保存页面生命周期状态。 |
| Model | `models/*.dart` | 不做网络请求，不读写文件或数据库。 |

## 启动流程

```text
main()
  -> 注册 ConversationProvider
  -> 注册 FeatureProvider
  -> 注册 ModelConfigProvider
  -> 注册 PluginProvider
  -> 注册 AccountProvider
  -> 注册 RecycleBinProvider
  -> 注册 RoleplayProvider
  -> 注册 SettingsProvider
  -> StorageV2UpgradeService.ensureReady()
  -> 并行加载对话、功能数据、插件、回收站、情景演绎、模型、设置
  -> 修复悬空模型引用
  -> 根据设置配置 BackendClient
  -> 恢复账号会话并加载同步序号
  -> 同步内置插件
  -> 构建 MaterialApp / HomePage
  -> 检查更新日志
```

启动加载由 `LynAIApp` 控制。加载中显示启动页；失败显示可重试错误页。Provider 会尽量跳过单条损坏数据，让应用仍可进入主界面。`AccountProvider.load()` 在 `BackendClient` 按保存的后端地址配置完成后从本地持久化恢复登录会话，未登录时不阻塞启动。

## 主界面结构

```text
HomePage (NavigationBar, 5 tabs)
├── FeaturePage (功能)
│   ├── Dashboard
│   ├── History
│   ├── Schedule
│   ├── Notes
│   ├── Todo Lists
│   └── Roleplay
├── PluginMarketPage (插件市场)
├── ChatPage (对话)
├── CommunityPage (社区)
└── SettingsPage (设置)
    ├── AboutPage
    ├── BackgroundPage
    ├── ApiModelsPage
    ├── ThemePage
    ├── DataManagementPage
    └── PluginManagementPage
```

`HomePage` 使用 `IndexedStack` 保留五个主 Tab 的状态，Tab 顺序由 `AppTab` 枚举定义（feature → market → chat → community → settings）。对话生成中、功能页打开笔记详情、或设置页返回时，不会因为 Tab 切换销毁状态。`AppTab.chat` 是默认 Tab 和系统返回键的兜底目标。

## 对话链路

一次普通发送大致经过这些步骤：

1. `ChatPage` 读取输入框、附件、当前角色、对话设置和模型配置。
2. 附件复制到应用私有目录，形成 `MessageImage` 元数据。
3. 如果没有当前对话，`ConversationProvider.createConversation()` 创建对话并保存设置快照。
4. 添加 user 消息，再添加空 assistant 消息作为流式占位。
5. `ApiService.sendStreamRequest()` 发起请求。
6. 每个 `StreamChunk` 到达时刷新最后一条 assistant 消息。
7. 如有工具调用，进入 `ToolCallService` 循环；插件工具由 `PluginLuaRuntimeService` 执行。
8. Agent 可通过 `read_agent_memory` / `update_agent_memory` 维护对话级工作记忆，并通过 `run_subagent` 把高噪声子任务放入独立上下文，主对话只接收最终结构化结果。
9. 保存最终正文、思考内容、工具结果或失败状态。

```text
Input + Attachments
  -> ChatPage
  -> ConversationProvider
  -> ApiService Stream<StreamChunk>
  -> ConversationProvider.updateLastMessage()
  -> ToolCallService（可选）
  -> 保存最终消息
```

历史对话保存自己的 `ConversationSettings`。全局设置变化不会悄悄改变旧对话的模型、提示词或文件识别上下文。

## 情景演绎链路

情景演绎把一个可复用情景和多条演绎对话分开管理。

```text
RoleplayScenario
  -> RoleplayThread
  -> Director 判断下一步
  -> Character 生成台词 / Narrator 旁白 / WaitUser 等待用户
  -> RoleplayProvider 保存线程消息
```

| 组件 | 责任 |
|------|------|
| `RoleplayScenario` | 情景模板、默认导演、默认玩家、默认角色和分组。 |
| `RoleplayThread` | 某次演绎的角色快照、消息、设置和更新时间。 |
| `RoleplayService` | 调用导演模型和角色模型，解析下一步动作。 |
| `RoleplayProvider` | 情景/线程状态、运行状态、玩家排队消息和落盘。 |

玩家在 AI 运行中继续发送的消息会进入线程级队列，避免并发写入破坏演绎顺序。

## 附件和资源

长期资源必须先复制到应用私有目录，再把路径写入模型。

```text
Picker / Camera / Clipboard / Backup Restore
  -> 应用私有临时文件
  -> Repository
  -> StorageV2Service.importResourceFile()
  -> assets/blobs/{sha256Prefix}/{sha256}
```

storage_v2 中的资源注册表使用 content-addressed blob 路径。对话附件保存时，Repository 会通过 `StorageV2Service.importResourceFile()` 写入资源表并在消息附件表中保存资源 ID。

## 工具调用链路

工具调用让模型访问受控的本地能力。OpenAI 兼容协议可以走原生 `tools`，其他协议可走 JSON fallback。

```text
模型返回 tool calls
   -> ToolCallService / PluginLuaRuntimeService
   -> FeatureProvider / Provider / 平台通道
  -> 工具结果回传模型
  -> 模型生成最终回复
```

工具可读取或修改日程、笔记、待办，也可以调用 Android 平台能力。工具能力应只在可信模型和可信对话中启用。

Agent 手机自动化优先用 `lynai.device.*`、`device.screen.query` 和 `device.node.findAll` 精确筛选节点，同一应用内的确定性多步骤操作优先合并到一次 `execute_lua` 中线性编排。读屏、消息提取和节点查询只需要 `device:screen:read`，点击、输入、滚动、打开应用等动作需要 `device:control`。QQ/消息应用上下文优先从无障碍节点提取可见文本，截图 base64 只作为 OCR/识图输入，模型可见 tool result 会剥离二进制内容。发给模型的 assistant 历史消息固定携带空 `reasoning_content`，避免真实 thinking 污染后续工具上下文。Agent Lua 和 Subagent 不设置固定工具轮数上限，设备任务通过暂停/停止机制收敛。

## 持久化策略

Provider 的共同策略是“先更新 UI，再保存快照”。

```text
Provider mutation
  -> 修改内存中的不可变模型列表
  -> notifyListeners()
  -> 保存快照进入 Future 队列
  -> Repository
  -> storage_v2
```

这样用户操作立即反馈，连续操作也不会因为异步保存乱序覆盖新状态。保存失败通常记录到 `debugPrint`，不回滚已经显示给用户的内存状态。

## storage_v2

storage_v2 是新版持久化布局，由 `StorageV2Service` 和 Drift 数据库驱动。

```text
storage_v2/
├── manifest.json
├── app.db
├── notes/...            # 笔记分页正文
└── assets/blobs/...     # SHA 内容寻址资源
```

| 部分 | 说明 |
|------|------|
| `app.db` | 结构化数据权威源。 |
| `notes/*.md` | 笔记分页正文文件。 |
| `assets/blobs/*` | 背景、图片、文档、音视频等资源，路径为 `assets/blobs/{sha256Prefix}/{sha256}`。 |

Repository 只读写 storage_v2。启动阶段由 `StorageV2UpgradeService` 创建或升级 storage_v2，运行时不再从旧 JSON 恢复业务数据。

## 笔记时间线

笔记支持修订树。当前内容与历史版本通过 delta 关联。

```text
Note.currentRevisionId
  -> NoteRevision
  -> parentRevisionId
  -> ...
```

storage_v2 下笔记正文按分页保存为 Markdown 文件；分页元数据、修订、AI 修改建议和行级编辑块保存到数据库。旧单正文笔记仍通过兼容路径读取。

## 备份架构

备份是 ZIP 文件，由 manifest、分区 JSON、笔记分页正文、资源表和私有附件组成。

```text
backup.zip
├── manifest.json
├── settings.json
├── model_configs.json
├── conversations.json
├── notes/
│   ├── folders.json
│   ├── notes.json
│   ├── pages.json
│   ├── revisions.json
│   ├── edit_proposals.json
│   ├── edit_blocks.json
│   └── page_contents/
├── schedules.json
├── todo_lists.json
├── roleplay_scenarios.json
├── roleplay_threads.json
├── plugins.json
├── resources.json
└── assets/blobs/{sha256Prefix}/{sha256}
```

导入时先读取 ZIP，生成预览和冲突列表。用户确认导入计划后，服务恢复 blob、重映射资源引用、处理 ID 冲突，再调用 Provider 替换或合并数据。ZIP 内附件使用和 storage_v2 一致的 SHA blob 路径，备份不再兼容旧数字前缀格式。

## 更新日志

更新日志文件位于 `changelogs/`，由 `ChangelogParser` 读取 asset manifest 后解析 Markdown。启动时会比较 `AppSettings.lastSeenChangelogVersion` 和 `PackageInfo.version`，需要展示时打开弹窗。弹窗只返回用户操作，页面跳转由外层有效 context 执行。

## 容错原则

| 场景 | 策略 |
|------|------|
| 单条持久化数据损坏 | 跳过坏项，保留其他数据。 |
| 顶层 JSON 损坏 | 对应分区回退为空或默认值，保证应用可启动。 |
| 模型 ID 指向已删除配置 | 自动回填同类第一个可用模型或清空。 |
| 流式 chunk 格式异常 | 跳过坏 chunk，不中断已收到正文。 |
| 工具参数异常 | 工具返回结构化错误，不破坏对话。 |
| 页面销毁后的异步回调 | 检查 `mounted` 后再更新 UI。 |

## 维护底线

| 行为 | 原因 |
|------|------|
| `Message.images` 仍表示附件列表 | 字段名为兼容旧数据保留。 |
| OpenAI 兼容请求显式发送 thinking 开关 | 部分后端依赖 disabled 标记。 |
| 备份 API 配置会包含 API Key | 完整恢复需要，但备份文件必须按敏感文件处理。 |
| storage_v2 路径必须通过安全检查 | 避免相对路径逃逸到应用目录外。 |
| 备份 ZIP 不直接打包 `app.db` | 保留分区导入、冲突处理和跨平台恢复能力。 |
