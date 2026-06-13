# 服务层、API 与工具调用

`lib/services/` 负责和外部世界交互：模型 API、工具调用、平台能力、备份文件、storage_v2 和迁移。页面层只传入需要的上下文，服务层不持有 UI 状态。

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

工具返回统一结构：成功为 `{ok: true, ...}`，失败为 `{ok: false, error: ...}`。这样模型可以继续解释错误，而不是让对话直接中断。

### Agent 模型函数

| 函数 | 说明 |
|------|------|
| `model.chat` | 调用已配置 Chat 模型执行 Agent 内部推理。 |
| `model.ocr` | 调用已配置 OCR 模型识别图片文字。 |
| `model.recognizeFile` | 调用已配置视觉 Chat 模型识别图片或文件内容。 |

Agent Lua 可以通过 `lynai.call()` 调用这些函数。手机复杂操作通常先读取 `device.screen.context`，自绘或无障碍信息不足时再调用 `device.screen.screenshot`，并把截图传给 `model.ocr` 或 `model.recognizeFile`。

### 工具调用策略

1. OpenAI 兼容协议在子模型 `supportsTools=true` 且未通过 `extraParams.disableTools=true` 禁用时使用原生 `tools`。
2. 不适合原生工具的协议可以使用 JSON fallback。
3. 启用工具时会注入当前本地时间、时区和 `timezoneOffsetMinutes`。
4. 日程工具解析 ISO-8601 后统一转本地时间。
5. 工具调用循环会把工具阶段和最终回复阶段的 reasoning 合并保存。

### 平台通道

| 通道 | 方法 | 平台 | 说明 |
|------|------|------|------|
| `lynai/native_tools` | `openApp` | Android | 按包名打开应用。 |
| `lynai/native_tools` | `getLocation` | Android | 请求定位并读取最近位置。 |
| `lynai/native_tools` | `saveImageToGallery` | Android | 保存 PNG 到图库。 |
| `lynai/schedule_widget` | `refresh` | Android | 日程变更后刷新小组件。 |
| `lynai/schedule_widget` | `rescheduleNotifications` | Android | 日程变更后重新安排通知。 |
| `lynai/background_service` | start/stop | Android | 长时间生成时控制前台服务。 |
| `lynai/device_control` | snapshot/context/screenshot/tap/swipe/inputText/nodeAction | Android | 通过无障碍读取屏幕、截屏并执行手机操作。 |

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
├── data/*.json
├── notes/...md
└── assets/...
```

| 部分 | 说明 |
|------|------|
| `manifest.json` | 标识存储类型、schema 和布局信息。 |
| `app.db` | 结构化数据权威源。 |
| `data/*.json` | legacy/debug 镜像和导入来源。 |
| `notes/*.md` | 笔记分页正文。 |
| `assets/*` | 资源文件，按类型和哈希路径保存。 |

### 路径安全

所有 storage_v2 相对路径都必须经过 `_file()` 检查。它会拒绝绝对路径、空路径段、`.`、`..`，并检查最终路径仍在 storage_v2 根目录内。

### 资源导入

`importResourceFile()` 会按文件内容计算 SHA-256，相同内容和大小的资源复用同一条记录。缺失文件会记录为 missing resource，避免历史引用直接崩溃。

## StorageMigrationService

文件：`lib/services/storage_migration_service.dart`

负责从 legacy SharedPreferences JSON 迁移到 storage_v2。迁移使用 staging 目录，成功导入数据库后再激活，失败时回滚。

```text
legacy providers
  -> storage_v2_staging/data/*.json
  -> notes/*.md
  -> assets/*
  -> StorageV2Database.importDataFiles()
  -> rename staging to storage_v2
  -> mark migration completed
```

迁移状态写入 SharedPreferences，数据迁移完成后会移除体积较大的 legacy JSON 键。schema 常量以 `StorageMigrationService.currentSchemaVersion` 为准，文档不复制具体数值。

## LegacyResourceMigrationService

文件：`lib/services/legacy_resource_migration_service.dart`

负责把旧 Documents 根目录下的长期资源复制到当前默认应用支持目录，并更新内存和落盘路径。

| 资源 | 更新位置 |
|------|----------|
| 背景图 | `SettingsProvider.replaceSettings()` |
| 普通聊天附件 | `ConversationProvider.replaceConversations()` |
| 情景演绎附件 | `RoleplayProvider.replaceData()` |

迁移只复制，不删除旧文件。单个资源失败会跳过并记录 debug 日志，不阻断应用启动。目标文件已存在且内容一致时直接复用，避免重复副本。

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
assets/backgrounds/...
assets/message_images/...
```

实际写入哪些文件由 `BackupSelection` 决定。`manifest.json` 会记录类型、schema、应用版本、创建时间、分区信息和附件映射。

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

备份只归档应用私有目录中被引用的附件。导入时附件会恢复到当前设备的应用私有目录，并把旧路径替换成新路径。

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
3. 新增备份字段时，更新 manifest 或分区 JSON，并保证旧备份仍能读取。
4. 涉及 API Key、位置、工具写入本地数据的功能，要在 UI 或文档中提示风险。
5. 新增持久资源路径时，使用应用私有目录入口，并考虑备份和旧路径迁移。
6. storage_v2 内部路径必须通过统一安全检查，不能拼接未校验的相对路径。
