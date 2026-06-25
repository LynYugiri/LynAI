# 服务层、API 与工具调用

`lib/services/` 负责和外部世界交互：模型 API、工具调用、平台能力、备份文件、storage_v2 和存储升级。页面层只传入需要的上下文，服务层不持有 UI 状态。

## ApiService

文件：`lib/services/api_service.dart`

`ApiService` 负责 Chat、流式 Chat、图片 OCR、语音转文字、图片生成、附件内容转换、thinking/reasoning 提取和 tool calls 解析。

### 标准化数据

| 类型 | 说明 |
|------|------|
| `ChatFileInput` | 发送前的附件字节、MIME 和文件名。 |
| `StreamChunk` | 流式增量，包含正文、思考内容、工具调用和结束信号。 |
| `ChatResponse` | 非流式回复，包含正文、思考内容和工具调用。 |

不同协议的请求和返回差异在 `ApiService` 内部消化。页面只处理标准化类型。

### 支持协议

| `apiType` | 用途 | 流式格式 |
|-----------|------|----------|
| `openai` | OpenAI 兼容 Chat Completions。 | SSE `data:`。 |
| `custom` | 自定义 OpenAI 兼容接口。 | SSE `data:`。 |
| `ollama` | Ollama `/api/chat`。 | 逐行 JSON。 |
| `anthropic` | Anthropic Messages API。 | SSE `data:`。 |
| `openai_image` | OpenAI Images。 | 非流式 JSON。 |
| `vivo_image` | vivo 图片生成。 | 非流式 JSON。 |

### 请求体约定

| 协议 | 行为 |
|------|------|
| OpenAI 兼容 | 发送 `model`、`messages`、`stream`、`thinking`、采样参数；工具开启时发送 `tools` 和 `tool_choice`。 |
| Ollama | 发送 `model`、`messages`、`stream`、`think`；采样参数进入 `options`。 |
| Anthropic | system 消息提升到顶层 `system`，其余消息写入 `messages`，内容转 Anthropic block。 |

OpenAI 兼容请求会显式发送 thinking 开关。部分已配置后端依赖 disabled 标记，不要随意删除。

`extraParams` 会合并到请求体，但不会覆盖代码已经设置的核心字段，例如 `model`、`messages`、`stream`。

### 附件转换

| 接口能力 | 图片 | 非图片文件 |
|----------|------|------------|
| 支持多模态 | 转成协议要求的 image content。 | 尽量转为文本上下文；部分链路可使用 input file 风格内容。 |
| 不支持多模态 | 文件名、MIME、大小和文本/base64 摘要。 | 文件名、MIME、大小和文本/base64 摘要。 |

OCR 和文件识别是发送前处理。处理结果会拼进用户上下文，而不是替换历史附件。

对话页 OCR 支持两种引擎：云端 OCR API（如 vivo OCR，需网络和 API key）和本地 OCR（ncnn + PPOCRv5，离线免费，仅 Android）。在对话设置的 OCR 模型列表中，Android 端会显示"本地 OCR (PPOCRv5)"虚拟条目，选中后 `imageModelId` 存为 `ModelConfig.localOcrId` sentinel，OCR 路径自动分发到本地推理。`model.ocr` 函数同样支持该 sentinel，Agent Lua 调用时自动走本地路径。

### 流式错误处理

| 场景 | 行为 |
|------|------|
| 建立连接超时 | 抛出中文异常。 |
| 非 200 响应 | 抛出包含状态码和响应体的异常。 |
| OpenAI SSE `error` | 转成异常进入 ChatPage 失败路径。 |
| Anthropic `type:error` | 转成异常进入失败路径。 |
| 单个坏 chunk | 跳过该 chunk，保留已收到正文。 |
| 工具参数不是 JSON 对象 | 跳过该工具调用。 |

## ToolCallService

文件：`lib/services/tool_call_service.dart`

`ToolCallService` 把模型请求转成本地动作。它定义工具 schema，解析 fallback JSON，校验参数，并调用 Provider 或平台通道。插件的自定义工具由 `ToolCallService` 识别后转交给 `PluginLuaRuntimeService` 在 Lua 沙箱中执行。

### 工具清单

| 工具 | 副作用 |
|------|--------|
| `get_current_time` | 无，返回当前时间和时区。 |
| `get_current_screen` | 只读。仅在悬浮聊天且用户授权当前页面上下文时暴露，读取 Android 前台页面文本和节点摘要。 |
| `web_fetch` | 发起只读 GET 请求，读取 http/https URL 的响应正文并按长度限制返回。 |
| `get_location` | Android 请求定位权限并返回位置。 |
| `open_app` | Android 打开指定包名应用。 |
| `list_schedules` | 只读。 |
| `create_schedule` | 写入本地日程。 |
| `update_schedule` | 修改本地日程。 |
| `list_notes` | 只读。 |
| `read_note` | 只读。 |
| `save_note` | 创建、覆盖或追加笔记。 |
| `edit_note` | 对笔记执行直接行级编辑。 |
| `propose_note_edit` | 生成待用户确认的笔记修改建议。 |
| `list_note_pages` | 只读，列出笔记分页。 |
| `save_note_page` | 创建、覆盖、追加或移动笔记分页。 |
| `list_note_folders` | 只读，列出笔记文件夹。 |
| `save_note_folder` | 创建或更新笔记文件夹。 |
| `list_todo_lists` | 只读，列出待办清单。 |
| `read_todo_list` | 只读，读取清单任务。 |
| `save_todo_list` | 创建或更新待办清单。 |
| `save_todo_item` | 创建、更新或勾选任务。 |
| `generate_image` | 调用当前对话的图片生成模型，保存图片并追加到 assistant 消息。 |

工具返回统一结构：成功为 `{ok: true, ...}`，失败为 `{ok: false, error: ...}`。这样模型可以继续解释错误，而不是让对话直接中断。

### Agent 模型函数

| 函数 | 说明 |
|------|------|
| `model.chat` | 调用已配置 Chat 模型执行 Agent 内部推理。 |
| `model.ocr` | 调用已配置 OCR 模型识别图片文字。当 `imageModelId` 为 `localOcrId` sentinel 时走本地 PPOCRv5 推理（仅 Android）。 |
| `model.recognizeFile` | 调用已配置视觉 Chat 模型识别图片或文件内容。 |
| `model.generateImage` | 调用已配置图片生成模型，保存生成结果并返回附件元数据。 |
| `agent.memory.read` | Agent Lua 读取当前对话共享工作记忆。 |
| `agent.memory.update` | Agent Lua 更新当前对话共享工作记忆。 |

Agent Lua 可以通过 `lynai.call()` 调用这些函数，也可以用 `lynai.device.*` 便捷接口编排手机自动化。Lua 源码不做固定长度截断，`lynai.call` 不做固定次数硬限制；设备任务依赖悬浮层和 `DeviceRunController` 的暂停/停止机制中断。手机复杂操作优先使用 `lynai.device.query`、`lynai.device.waitAndClick`、`lynai.device.inputInto`、`lynai.device.scrollUntil` 或底层 `device.screen.query` 查找任务相关节点；确实需要完整结构时再读取 `device.screen.snapshot`。消息应用和 QQ 上下文优先通过 `device.screen.extractMessages` 从无障碍节点读取可见文本，无法读取图片、语音或自绘内容时再调用 `device.screen.screenshot`。截图 base64 只能作为 `model.ocr` 或 `model.recognizeFile` 的输入，回传模型的 tool result 会剥离二进制字段，只保留 OCR/识图文本和截图元数据。

### 工具调用策略

1. OpenAI 兼容协议在子模型 `supportsTools=true` 且未通过 `extraParams.disableTools=true` 禁用时使用原生 `tools`。
2. 不适合原生工具的协议可以使用 JSON fallback。
3. 启用工具时会注入当前本地时间、时区和 `timezoneOffsetMinutes`。
4. 日程工具解析 ISO-8601 后统一转本地时间。
5. 发给模型的 assistant 消息始终带 `reasoning_content: ""`，真实 thinking 只用于 UI/历史展示，不再回传进工具轮次上下文。
6. `generate_image` 只在当前对话开启图片生成时暴露，并追加在 tools 列表末尾。
7. `get_current_screen` 只由悬浮聊天会话显式开启，执行层会再次校验授权，避免模型通过 fallback JSON 绕过工具暴露条件。
8. Agent 模式提供 `read_agent_memory` 和 `update_agent_memory`，用于主 Agent、Subagent 和 Lua 共享当前对话的持久化工作记忆。
9. Agent 模式提供 `run_subagent`，用于把手机自动化、屏幕读取和 OCR/识图等高噪声子任务隔离到独立上下文，主对话只接收最终结构化结果。

### 平台通道

| 通道 | 方法 | 平台 | 说明 |
|------|------|------|------|
| `lynai/native_tools` | `openApp` | Android | 按包名打开应用。 |
| `lynai/native_tools` | `getLocation` | Android | 请求定位并读取最近位置。 |
| `lynai/native_tools` | `saveImageToGallery` | Android | 保存 PNG 到图库。 |
| `lynai/schedule_widget` | `refresh` | Android | 日程变更后刷新小组件。 |
| `lynai/schedule_widget` | `rescheduleNotifications` | Android | 日程变更后重新安排通知。 |
| `lynai/background_service` | start/stop | Android | 长时间生成时控制前台服务。 |
| `lynai/device_control` | snapshot/context/query/screenshot/ocr/tap/swipe/inputText/nodeAction | Android | 通过无障碍读取屏幕、筛选节点、截屏并执行手机操作。节点包含可见性、选中、勾选、长按和可用动作等元数据。`ocr` 使用 ncnn + PPOCRv5 离线识别截图中的文本及位置（支持 17+ 语言和竖排文字）。 |
| `lynai/floating_assistant` | showBubble/hideBubble/configure/updateChatState/updateAgentPlan/updateTranslationOverlay/clearTranslationOverlay | Android | 系统级悬浮聊天窗，接收 Dart 聊天状态、发送用户输入、语音填充输入框、触发翻译和 Agent 控制。支持气泡/面板拖动、面板缩放、位置持久化、气泡状态指示（脉冲动画）、消息长按复制、新建对话。 |

读屏类函数 `device.screen.query`、`device.screen.waitText`、`device.screen.readVisibleText`、`device.screen.extractMessages`、`device.node.find`、`device.node.findAll` 和 `device.waitForNode` 需要 `device:screen:read`。动作类函数如 `device.app.open`、`device.screen.clickText`、`device.screen.waitAndClick`、`device.screen.inputText`、`device.screen.scrollUntil`、`device.tap`、`device.swipe`、`device.inputText` 和 `device.node.action` 需要 `device:control`。

### FloatingAssistantService

文件：`lib/services/floating_assistant_service.dart`、`lib/services/floating_chat_session_controller.dart`、`android/app/src/main/kotlin/com/github/lynyugiri/lynai/FloatingAssistantOverlay.kt`、`android/app/src/main/kotlin/com/github/lynyugiri/lynai/TranslationOverlayManager.kt`、`android/app/src/main/kotlin/com/github/lynyugiri/lynai/NcnnOcrRecognizer.kt`

Android 悬浮助手由原生 `WindowManager` 渲染系统级气泡和聊天卡片，Dart 侧 `FloatingChatSessionController` 负责创建真实 Conversation、流式请求、工具调用、翻译当前屏幕文本和状态回推。悬浮窗只在后台显示或 Agent 运行时显示；展开后可以直接聊天，语音按钮使用 Android 系统语音识别把结果填入输入框。Agent 计划并入同一个悬浮窗，只有运行/暂停状态才显示控制，暂停时显示继续，运行或暂停时显示停止。

气泡可拖动（垂直边界限制）并记忆位置；面板 header 可拖动、右下角可缩放，位置和尺寸持久化到 `FloatingAssistantSettings`。气泡根据状态变色并脉冲动画：蓝色空闲、橙色 Agent 运行、绿色翻译中、红色录音中。面板消息和译文长按可复制到剪贴板。

翻译功能支持多目标语言、源语言检测（已是目标语言则原样返回）、app 上下文附带。文本来源优先使用 on-device OCR（ncnn + PPOCRv5，支持 17+ 语言和竖排文字，离线工作），OCR 无法识别时降级到无障碍快照节点。批量翻译流式输出，结果通过 `TranslationOverlayManager` 在屏幕原位渲染覆盖层（触摸穿透），支持 light/dark/stroke 样式和不透明度。用户滚动目标 app 时，无障碍 `TYPE_VIEW_SCROLLED` 事件实时驱动覆盖层跟随（含横向滚动和 fling 节流），滚动停止 500ms 后自动增量翻译新内容。翻译历史缓存到 SharedPreferences，最近 20 条可在面板查看。

### Agent Subagent

`run_subagent` 是 Agent 专用工具。它使用当前对话模型和权限创建独立短上下文，允许子任务多轮调用 `execute_lua`、Skill、OCR/识图等工具，但不会把中间屏幕信息写入主对话上下文。Subagent 会接收当前 Agent 工作记忆和计划摘要，完成后会把最终摘要或 `memoryUpdates` 合并回工作记忆。Subagent 禁止递归启动 Subagent，不设置固定工具轮数上限，最终必须返回 `{ok:true,result:{...}}` 或 `{ok:false,error:{...}}`。

Subagent 适合 QQ/消息应用这类流程：主 Agent 只描述目标，Subagent 负责打开应用、查询屏幕、滚动、OCR 和读取上下文，最后把联系人、最近消息、置信度和摘要返回主 Agent。

### Agent 工作记忆

工作记忆是对话级持久化状态，跟随 `Conversation` 保存和备份。主 Agent 的 system prompt 会注入压缩后的目标、计划和最近记忆；工具和 Lua 可用 `read_agent_memory`、`update_agent_memory`、`agent.memory.read`、`agent.memory.update` 读写。Skill 加载成功和 Subagent 完成会自动写入短记忆，避免重复加载 Skill 或丢失子任务发现。

桌面端图片导出通常写入剪贴板；移动端更偏向图库或系统分享。

## PluginLuaRuntimeService

文件：`lib/services/plugin_lua_runtime_service.dart`

`PluginLuaRuntimeService` 管理 Lua 沙箱运行时，负责加载插件脚本、注册和调用工具/函数、维护延续链和事件通知。

### 沙箱执行

插件工具和函数在独立的 Lua 沙箱中执行。沙箱裁剪了不安全的全局函数（如 `os.execute`、`io.popen`），并注入受控 API：

| 注入 API | 说明 |
|----------|------|
| HTTP 请求 | 受权限控制的网络请求能力。 |
| 文件读写 | 限制在插件目录和用户授权路径内的文件操作。 |
| 回收站 | 插件可把自己的业务数据或 editableFiles 文件写入回收站。 |
| 日志 | Debug 日志输出，不会泄露到用户 UI。 |
| JSON | 解析和序列化 JSON。 |
| 设备 | `lynai.device.*` 便捷接口会生成受权限控制的设备命令，用于读屏、等待、点击、输入、滚动和消息提取。 |

### 工具执行

| 步骤 | 说明 |
|------|------|
| 注册工具 | 解析 `plugin.json` 中 `tools` 列表，把 `tool_name` 和 `handler` 注册进运行时。 |
| 执行工具 | `ToolCallService` 识别插件工具后调用 `executePluginTool()`，在沙箱中运行对应 handler。 |
| 参数校验 | 运行前用 JSON Schema 校验参数，不合法参数提前返回错误。 |
| 返回结果 | 工具返回统一结构 `{ok: true, ...}` 或 `{ok: false, error: ...}`。 |

### 函数导出

除了 AI 可调用的工具，插件还可以通过 `plugin.json` 的 `functions` 列表注册内部函数。这些函数不暴露给模型，但可在功能页 WebView 的 JavaScript 桥中调用。

### 延续链

支持工具调用后的异步延续：工具返回 `continuation` 标记后，运行时挂起当前上下文并返回令牌。后续 `resumeContinuation()` 携带模型决策或用户输入继续执行。

### 生命周期

| 阶段 | 行为 |
|------|------|
| 加载 | 插件启用时加载入口脚本，注册工具和函数。 |
| 挂起 | 禁用插件时暂停沙箱，释放运行时资源。 |
| 卸载 | 移除插件时销毁沙箱并清理所有上下文。 |

## LynAIFunctionService

文件：`lib/services/lynai_function_service.dart`

`LynAIFunctionService` 是统一的 AI 函数调用分发层。模型请求中的 function call 经过 `ToolCallService` 识别后，由 `LynAIFunctionService` 路由到对应执行单元。

| 分类 | 路由目标 |
|------|----------|
| 日程 | `FeatureProvider` 的日程方法。 |
| 笔记 | `FeatureProvider` 的笔记、分页、修订方法。 |
| 待办 | `FeatureProvider` 的待办清单方法。 |
| 回收站 | `RecycleBinRepository` 与插件安全上下文。 |
| 插件工具 | `PluginLuaRuntimeService` 的 `executePluginTool()`。 |
| 平台能力 | 原生平台通道。 |

`LynAIFunctionService` 本身不实现工具逻辑，它只负责根据工具名查找注册表和参数校验后转发到正确的执行器。新增功能类工具只需在注册表中添加条目，调用方无需改动。

## CodeSyntaxService

文件：`lib/services/code_syntax_service.dart`

`CodeSyntaxService` 提供代码高亮能力，采用 tree-sitter 原生 + Dart fallback 双路径策略。

| 路径 | 条件 | 说明 |
|------|------|------|
| tree-sitter 原生 | `TreeSitterNative.isAvailable()` 为 true | 使用 C 语言 tree-sitter 解析库，比纯 Dart 快 10-50 倍。 |
| Dart fallback | 原生不可用时 | 回退到纯 Dart 实现的正则匹配高亮，覆盖主流语言。 |

tree-sitter 原生路径需配合以下文件：

| 文件 | 说明 |
|------|------|
| `lib/services/tree_sitter_native.dart` | 语言注册和高亮入口，管理 tree-sitter 解析器生命周期。 |
| `lib/services/tree_sitter_native_ffi.dart` | Dart FFI 绑定，调用编译好的 C 动态库。 |
| `lib/services/tree_sitter_native_stub.dart` | 不支持原生 FFI 平台（如 Web）的占位实现。 |
| `lib/services/tree_sitter_language_registry.dart` | 语言 scope 到 tree-sitter grammar 的注册映射。

tree-sitter 解析结果会转成 Flutter 的 `TextSpan` 结构，与 fallback 路径输出格式一致，上层渲染层无需感知当前使用哪条路径。

## RoleplayService

文件：`lib/services/roleplay_service.dart`

`RoleplayService` 负责情景演绎中的模型调用和导演决策解析。

| 步骤 | 说明 |
|------|------|
| 构建导演 prompt | 输入情景、角色、历史和玩家队列，让导演决定下一步。 |
| 解析导演输出 | 转成说话、旁白、等待用户或错误状态。 |
| 调用角色模型 | 使用角色系统提示词和线程历史生成台词。 |
| 产出流式 chunk | 页面和 Provider 使用流式内容更新草稿。 |

Roleplay 复用 Chat 模型配置和 `ApiService`，但运行状态由 `RoleplayProvider` 管理。

## StorageV2Service

文件：`lib/services/storage_v2_service.dart`、`storage_v2_database.dart`

storage_v2 是新版本地存储布局。`StorageV2Service` 是读写门面，`StorageV2Database` 是 Drift 数据库。

```text
storage_v2/
├── manifest.json
├── app.db
├── notes/...md
└── assets/blobs/{sha256Prefix}/{sha256}
```

| 部分 | 说明 |
|------|------|
| `manifest.json` | 标识存储类型、schema 和布局信息。 |
| `app.db` | 结构化数据权威源。 |
| `notes/*.md` | 笔记分页正文。 |
| `assets/blobs/*` | 资源文件，按 SHA-256 内容寻址保存。 |

### 路径安全

所有 storage_v2 相对路径都必须经过 `_file()` 检查。它会拒绝绝对路径、空路径段、`.`、`..`，并检查最终路径仍在 storage_v2 根目录内。

### 资源导入

`importResourceFile()` 会按文件内容计算 SHA-256，相同内容和大小的资源复用同一条记录。资源 blob 路径固定为 `assets/blobs/{sha256Prefix}/{sha256}`，展示名、MIME 类型和用途保存在资源 metadata 中。

## StorageV2UpgradeService

文件：`lib/services/storage_v2_upgrade_service.dart`

负责启动阶段创建或升级 storage_v2，只处理当前 storage_v2 布局到新版布局的安全升级。

```text
missing storage_v2
  -> create manifest.json
  -> open app.db

storage_v2 schemaVersion < current
  -> copy storage_v2_backup_<timestamp>
  -> copy old resource files into assets/blobs/{prefix}/{sha}
  -> update resources.relativePath
  -> write current manifest
```

升级前会复制整个 storage_v2 目录作为备份。升级失败时恢复备份，避免损坏当前用户数据。

## BackupService

文件：`lib/services/backup_service.dart`

`BackupService` 负责 ZIP 备份导出、读取、预览和导入。schema 常量以 `BackupService.currentSchemaVersion` 为准。

### 导出结构

```text
manifest.json
settings.json
model_configs.json
conversations.json
notes/folders.json
notes/notes.json
notes/pages.json
notes/revisions.json
notes/edit_proposals.json
notes/edit_blocks.json
notes/page_contents/{pageId}.md
schedules.json
todo_lists.json
roleplay_scenarios.json
roleplay_threads.json
resources.json
assets/blobs/{sha256Prefix}/{sha256}
```

实际写入哪些文件由 `BackupSelection` 决定。`manifest.json` 会记录类型、schema、应用版本、创建时间、分区信息和附件映射。被引用的私有附件使用和 storage_v2 资源一致的 SHA blob 路径；多个旧路径引用同一内容时可共享同一个 ZIP 条目。

### 分区

| 分区 | 内容 |
|------|------|
| `settings` | `AppSettings` 和/或 `ModelConfig`，可细分 API 配置、外观、对话设置、角色与提示词。 |
| `conversations` | 选中的对话和私有附件。 |
| `notes` | 选中笔记、文件夹、分页、分页正文、修订和 AI 修改建议。 |
| `schedules` | 选中日程。 |
| `todoLists` | 选中待办清单。 |
| `roleplay` | 选中的情景和对应演绎线程。 |

### 导入流程

1. `readZip()` 解压并校验 `manifest.json`。
2. 解析各分区 JSON，坏数据记录为 warning。
3. `preview()` 生成分区摘要和冲突列表。
4. 用户选择导入模式和冲突动作。
5. `importArchive()` 恢复私有附件并重映射路径。
6. 按分区应用到 Provider；storage_v2 笔记会恢复分页元数据和 Markdown 正文。
7. 清理最终数据没有引用的临时恢复附件。

### 导入模式

| 模式 | 说明 |
|------|------|
| `merge` | 合并导入；遇到冲突按用户选择处理。 |
| `addOnly` | 只添加本地不存在的数据。 |
| `replaceSection` | 对冲突项执行替换语义，非冲突项仍按分区导入。 |

### 附件恢复

备份只归档应用私有目录中被引用的附件。导入时附件会按 manifest 的 `archivePath` 读取并恢复为 storage_v2 blob，再把业务记录指向对应资源。旧数字前缀附件路径不再作为新版备份格式支持。

如果 manifest 引用了某个附件但 ZIP 中缺失该文件，导入会记录 warning，并清除对应背景图或消息附件引用，避免导入后指向另一台设备上的无效路径。

## SystemScrollCaptureService

文件：`lib/services/system_scroll_capture_service.dart`

`SystemScrollCaptureService` 提供跨平台长截图滚动捕获能力，用于将可滚动内容导出为完整长图。

| 平台 | 策略 |
|------|------|
| Android | 使用 AccessibilityService 或系统截图 API 逐帧捕获并拼接。 |
| iOS | 通过 `UIScrollView` 渲染至离屏画布。 |
| 桌面端 | 直接渲染完整 Widget 树到 `RenderRepaintBoundary`，不需要逐帧滚动。 |

| 步骤 | 说明 |
|------|------|
| 启动滚动 | 发送离散滚动增量，逐段捕获内容。 |
| 帧拼接 | 把每段截取内容按重叠区域拼接为完整长图。 |
| 图像后处理 | 裁剪多余区域、去重重叠部分、统一尺寸和编码。 |
| 导出 | 保存为 PNG 或 JPEG 到用户选择的位置。 |

长截图通常用于分享对话历史、笔记全文、待办清单和情景演绎消息。

## ChangelogParser

文件：`lib/utils/changelog_parser.dart`

更新日志作为 Flutter asset 打包在 `changelogs/` 目录。`ChangelogParser` 读取 asset manifest，筛选 Markdown 文件并解析二级标题日期、三级标题分区和列表项。

启动弹窗加载当前包版本对应的 `changelogs/v*.md`。如果版本带 build 或 prerelease 后缀，会先尝试完整版本，再回退到稳定版本号。

## 服务层维护建议

1. 新增 API 协议时，先在 `ApiService` 内转换成现有 `StreamChunk` / `ChatResponse`。
2. 新增工具时，同时更新工具 schema、参数校验、执行逻辑和文档。
3. 新增备份字段时，更新 manifest 或分区 JSON，并同步 bump `BackupService.currentSchemaVersion`。
4. 涉及 API Key、位置、工具写入本地数据的功能，要在 UI 或文档中提示风险。
5. 新增持久资源路径时，使用 storage_v2 资源入口，并考虑备份和 SHA blob 去重。
6. storage_v2 内部路径必须通过统一安全检查，不能拼接未校验的相对路径。
