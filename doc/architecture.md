# 架构说明

LynAI 的架构目标是让页面、状态、存储、协议和数据模型各做各的事。项目功能很多，但核心边界保持稳定：页面收集用户意图，Provider 维护本地状态，Repository 负责本地持久化，Service 和外部世界打交道，Model 只定义数据。

## 分层

```text
用户操作
  → Page：展示界面、收集输入、处理生命周期
  → Provider：更新内存状态、通知 UI、排队保存快照
  → Repository：读取/写入 storage_v2 或 legacy JSON
  → Model：不可变数据和 JSON 契约

外部能力
  → Service：API 协议、工具调用、备份文件、平台通道
```

| 层 | 典型文件 | 不能做什么 |
|----|----------|------------|
| Page | `chat_page.dart`, `feature_page.dart` | 不直接写 SharedPreferences，不把 API 协议散落到 UI。 |
| Provider | `providers/*.dart` | 不展示 UI，不直接读写 SharedPreferences 或 storage_v2。 |
| Repository | `repositories/*.dart` | 不通知 UI，不持有页面状态。 |
| Service | `api_service.dart`, `tool_call_service.dart`, `backup_service.dart` | 不持有页面状态，不依赖 BuildContext。 |
| Model | `models/*.dart` | 不做网络请求，不读写本地存储。 |

## 启动流程

```text
main()
  → MultiProvider 注册四个 Provider
  → LynAIApp.initState()
  → 并行加载本地数据
  → 修复设置中的悬空模型引用
  → 构建 MaterialApp
  → HomePage
```

启动加载由 `LynAIApp` 控制。加载中显示启动页，失败显示可重试错误页。Provider 会尽量跳过单条损坏数据，让应用仍然可进入主界面。

## 主界面结构

```text
HomePage
├── FeaturePage
│   ├── History
│   ├── Schedule
│   ├── Notes
│   └── Todo Lists
├── ChatPage
└── SettingsPage
    ├── AboutPage
    ├── BackgroundPage
    ├── ApiModelsPage
    ├── ThemePage
    └── DataManagementPage
```

`HomePage` 使用 `IndexedStack` 保留三个主 Tab 的状态。对话页正在生成、功能页打开笔记详情或设置页切换回来时，页面状态不会因为 Tab 切换被销毁。

## 对话链路

一次普通发送大致经过这些步骤：

1. `ChatPage` 读取输入框、附件、当前角色、当前对话设置和模型配置。
2. 附件复制到应用私有目录，并转换成 `MessageImage` 元数据。
3. 如果还没有对话，`ConversationProvider.createConversation()` 创建对话。
4. 添加 user 消息，再添加一个空 assistant 消息作为流式占位。
5. `ApiService.sendStreamRequest()` 发起请求。
6. 每个 `StreamChunk` 到达时，`ConversationProvider.updateLastMessage(save:false)` 刷新 UI。
7. 流结束后，如果存在工具调用，进入工具调用循环。
8. 最终正文、思考内容和工具结果保存到最后一条 assistant 消息。

```text
Input + Attachments
  → ChatPage
  → ConversationProvider
  → ApiService Stream<StreamChunk>
  → ConversationProvider.updateLastMessage()
  → ToolCallService（可选）
  → 保存最终消息
```

## 模型选择优先级

聊天模型来源可能有多个。实际发送时按下面顺序选择：

1. 当前历史对话绑定的模型。
2. 新对话创建前暂存的 pending model。
3. 对话设置面板中的模型。
4. `AppSettings.lastChatModelId`。
5. Chat 分类中第一个可用模型。

历史对话保存自己的 `ConversationSettings`，避免用户后来切换全局设置后改变旧对话上下文。

## 附件策略

附件进入模型前会先复制到应用私有目录。这样做有三个原因：

1. 系统 picker 返回的临时路径可能随时被清理。
2. 历史消息需要在重启后继续显示附件。
3. 备份服务只归档应用私有目录内被引用的文件，避免把任意外部路径打进备份。

```text
文件 / 图片 / 拍照 / 剪贴板
  → 应用私有目录
  → MessageImage(path, name, size, mimeType)
  → ChatFileInput(bytes, mimeType, name)
  → 多模态内容或文本上下文
```

如果模型不支持视觉，图片和文件会退化为文件名、MIME、大小、文本或 base64 摘要上下文。

## 工具调用链路

工具调用让模型访问受控的本地能力。OpenAI 兼容协议可以使用原生 `tools`，其他协议可以使用 JSON fallback。

```text
模型返回 toolCalls
  → ToolCallService.execute()
  → FeatureProvider / 平台通道
  → 工具结果回传模型
  → 模型生成最终自然语言回复
```

工具调用有副作用，例如创建日程、更新日程或保存笔记。只有在可信模型和可信对话中才应该开启工具能力。

## 持久化策略

Provider 的共同策略是“先更新 UI，再排队保存快照”。这样用户操作会立即反馈，而连续操作不会因为异步保存乱序覆盖新状态。

```text
Provider mutation
  → 修改内存中的不可变模型列表
  → notifyListeners()
  → 保存当前快照进入 Future 队列
  → storage_v2 或 SharedPreferences(JSON)
```

旧数据仍可从 SharedPreferences(JSON) 读取；完成新版存储迁移后，`storage_v2` 是权威源：`app.db` 保存结构化数据，`notes/*.md` 保存笔记分页正文，`assets/*` 保存资源文件，`data/*.json` 只是诊断和兼容镜像。Provider 是 UI 缓存，不是迁移和备份的最终真相源。

`FeatureProvider` 因为管理多个分区，所以日程、笔记、修订、文件夹、修改建议和待办各有独立保存队列。storage_v2 激活后，笔记当前编辑页会同步到对应 Markdown 分页文件，分页元数据和修订链写入数据库。

## 笔记时间线

笔记当前内容保存在 `Note.content`。历史版本不保存整篇正文，而是保存 `NoteRevision` 和 `NoteTextDelta`。

```text
Note.currentRevisionId
  → NoteRevision
  → parentRevisionId
  → ...
```

修订是树，不是单链表。用户可以从历史版本另开分支。Provider 会缓存修订内容和时间线，避免每次渲染都从头重放 delta。

## 备份架构

备份是 ZIP 文件，内部包含 manifest、分区 JSON、storage_v2 笔记分页正文和私有附件。

```text
lynai-YYYYMMDD-HHMMSS.zip
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
│   └── page_contents/
├── schedules.json
├── todo_lists.json
└── assets/
```

导入时先读取 ZIP，生成预览和冲突列表。用户确认导入计划后，服务会恢复附件、重映射路径、处理 ID 冲突，再调用 Provider 替换或合并数据。storage_v2 笔记导入会恢复分页元数据、分页 Markdown 正文、修订的 `pageId` 和 AI 修改建议，避免多分页笔记退化成单个 `content` 字段。

## 容错原则

| 场景 | 策略 |
|------|------|
| 单条持久化数据损坏 | 跳过坏项，保留其他数据。 |
| 顶层 JSON 损坏 | 对应分区回退为空或默认值，保证应用可启动。 |
| 模型 ID 指向已删除配置 | 自动回填同分类第一个可用模型或清空。 |
| 流式 chunk 格式异常 | 跳过坏 chunk，不中断已收到正文。 |
| 工具参数异常 | 工具返回结构化错误，不让异常直接破坏对话。 |
| 页面销毁后的异步回调 | 检查 `mounted` 后再更新 UI。 |

## 需要谨慎维护的行为

| 行为 | 原因 |
|------|------|
| OpenAI 兼容请求总是发送 `thinking: {type: enabled|disabled}` | 部分已配置后端依赖显式 disabled 标记，不能自动删掉。 |
| `Message.images` 实际表示附件列表 | 字段名为兼容旧数据保留。 |
| 备份 API 配置会包含 API Key | 这是完整恢复所需行为，但备份文件必须按敏感文件处理。 |
| 工具调用可修改本地数据 | 工具能力应由用户在可信上下文中开启。 |
| storage_v2 是新版权威源 | `app.db`、Markdown 分页文件和资源文件必须作为一个整体维护；`data/*.json` 只是可再生成镜像。 |
