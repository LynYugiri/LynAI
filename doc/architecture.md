# 架构概览

## 状态管理

```
MaterialApp
  └── MultiProvider
        ├── SettingsProvider    → 主题/背景/角色/功能页状态/默认模型/系统提示词/语音/OCR/文件识别
        ├── ModelConfigProvider → 分类模型配置 CRUD(Chat/OCR/Speech/Image Generation)
        ├── FeatureProvider     → 日程/笔记 CRUD
        └── ConversationProvider → 对话CRUD+搜索
              └── HomePage
                    ├── FeaturePage
                    ├── ChatPage
                    │     ├── MarkdownWithLatex → flutter_markdown_plus + flutter_math_fork + highlight
                    │     ├── Voice: speech_to_text 或 record → 语音转写接口
                    │     ├── Attachments: file_picker / image_picker / clipboard → OCR、文件识别或直传 → 当前模型
                    │     ├── Tools: ToolCallService → 时间/位置/应用/日程/笔记
                    │     └── Share: screenshot 长图 → 剪贴板/系统分享
                    └── SettingsPage
                          ├── AboutPage
                          ├── BackgroundPage
                          ├── ApiModelsPage
                          │     └── EditModelPage(分类配置/Endpoint预设/获取模型/多模型)
                          └── ThemePage(36预设+HSV调色板)
```

## 数据流

```
用户操作 → Provider方法 → 更新模型 → notifyListeners() → UI重建
                              ↓
                        save*() → SharedPreferences(JSON)

流式: Stream.listen → updateLastMessage() → notifyListeners() → UI逐字更新
```

### 持久化写入原则

Provider 层优先保证 UI 状态立即更新，然后把不可变快照加入串行保存队列。这样可以避免用户连续输入、拖拽排序、切换模型时旧的异步写入覆盖新的状态。

| Provider | 快照内容 | 写入策略 |
|----------|----------|----------|
| `ConversationProvider` | 当前对话列表 | 普通变更入队保存；流式中间态 `save:false` 只更新 UI，结束或失败后落盘 |
| `SettingsProvider` | 当前 `AppSettings` | 每次设置变更保存一个快照；模型引用修复后也会保存 |
| `ModelConfigProvider` | 当前模型配置列表 | 添加、编辑、删除、重排后保存 |
| `FeatureProvider` | 日程、笔记、文件夹、待办等分区 | 各分区按功能保存，导入替换时按选择分区覆盖 |

### 容错加载原则

发布版的数据加载策略是“尽可能保留可用数据”。对话、设置、模型、日程和笔记都可能来自旧版本、手动编辑的备份或损坏的 SharedPreferences，因此加载时优先跳过坏项，而不是让整个模块不可用。

| 数据 | 容错行为 |
|------|----------|
| 对话 | 对话关键字段损坏时跳过该对话；单条消息损坏时只跳过该消息 |
| 设置 | 角色和系统提示词逐条解析，坏项跳过；默认角色缺失时补回默认角色 |
| 附件 | 兼容旧 `filePath` 字段，并从路径推导缺失的文件名和 MIME 类型 |
| 模型引用 | 语音、OCR、文件识别和最近聊天模型 ID 不存在时回填同类第一个可用配置或清空 |

容错不会直接修改原始存储；只有用户后续触发保存或 Provider 执行修复保存时，当前内存状态才会写回。

## 功能页

`FeaturePage` 是底部导航第一个 Tab，承载轻量生产力功能：

- 对话历史：读取 `ConversationProvider.conversations`，按 `Conversation.roleId` 分组，搜索由 `ConversationProvider.searchConversations()` 提供。
- 日程表：读取 `FeatureProvider.schedules`，按日期范围过滤后渲染月/周/年视图。
- 笔记：读取 `FeatureProvider.notes`，编辑时使用防抖自动保存，预览使用 `MarkdownWithLatex`。
- 最近功能：`SettingsProvider.setLastFeature()` 持久化到 `AppSettings.lastFeature`。

## 角色上下文

`ChatRole` 保存角色名称、系统提示词、可选默认模型和可选主题色。选择角色时：

- `SettingsProvider.selectRole()` 更新当前角色、系统提示词、默认 Chat 模型和主题色。
- 新建对话时 `ChatPage` 使用当前角色生成 `ConversationSettings` 快照。
- 历史对话仍使用创建时保存的 `roleId` 和设置快照，切回历史对话时恢复对应配置。

## 全局背景

`HomePage`: Stack(背景图, BackdropFilter模糊, 半透明遮罩, Scaffold(transparent))

---

## ChatPage 消息链路

### 键盘交互
- **桌面端** (Linux/Windows/macOS): `Enter` 发送消息, `Shift+Enter` 换行。通过 `Focus.onKeyEvent` 拦截键盘事件实现。
- **移动端** (Android/iOS): 回车键默认换行，`textInputAction: TextInputAction.newline`。

### 普通文本
1. `_send()` → 添加user消息
2. `_getModel()` 获取当前 Chat 模型(优先对话绑定，其次 pending/draft/lastChatModelId，再兜底首个 Chat 模型)
3. `_convId ??= cp.createConversation()` 确保对话已创建
4. `_buildApiMessages()` 构建包含系统提示词的历史消息列表
5. `_doStream()` → `ApiService.sendStreamRequest()` 发起流式请求
6. `stream.listen` → `updateLastMessage()` 逐字更新
7. 流完成时保存思考内容到 `Message.thinkingContent` 并同步 `_thinkMap`, 支持历史恢复和重试导航；再次请求时会把 assistant 的 `thinkingContent` 回填为 `reasoning_content`

### 流式错误与收尾

流式请求有三个收尾路径：正常完成、用户停止、异常失败。三者都必须更新最后一条 assistant 消息并结束 `_streaming` 状态。

| 路径 | 行为 |
|------|------|
| 正常完成 | 使用最终 `buf` 和累积 `thinkBuf` 更新最后一条消息，`save:true` 持久化 |
| 用户停止 | 取消订阅并在最后一条 assistant 消息后追加“已停止生成”或填入停止提示 |
| 异常失败 | 保留已有正文并追加失败原因；如果本轮没有 thinking，显式清空旧 `thinkingContent` |

OpenAI 兼容 SSE 中的 `error` payload 和 Anthropic 的 `type:error` 会作为异常进入失败路径。格式异常的单个 chunk 会跳过，避免服务端偶发空行或非 JSON 事件中断整段回复。

### 本地工具调用
- `ToolCallService.openAITools()` 定义工具 schema, OpenAI 兼容接口可通过原生 `tools` 调用。
- 不支持原生 tool calls 的接口会通过系统提示词要求模型返回 JSON fallback。
- 工具覆盖时间、位置、打开 Android 应用、查询/创建/修改日程、查询/读取/保存笔记。
- 工具结果会重新送回模型生成最终自然语言回复。
- 工具调用阶段和最终回复阶段返回的 reasoning 会累积保存到最终 assistant 消息，重试历史切换时也会同步恢复。

### 语音
1. 未配置语音转写接口时，使用系统 `speech_to_text` 把识别结果写入输入框
2. 已配置语音转写接口时，使用 `record` 录制 m4a 临时文件
3. `_processRecordedSpeech()` → `ApiService.transcribeAudio()` 调用 vivo 长语音转写流程
4. 转写文本只回填输入框，不自动发送，用户可先修正

语音按钮使用长按交互。已配置语音模型时，按下会异步申请权限和启动录音；如果用户在启动完成前松手，启动请求会被取消，避免录音在后台继续运行。页面销毁时也会停止系统语音识别和录音器。

### 附件
1. 点击附件(+) 可选择文件、选择图片；移动端可拍照，桌面端可通过 `Ctrl/Cmd + V` 粘贴图片
2. 附件会复制到应用私有目录，并作为 `Message.images` 附件持久化，字段包含路径、文件名、大小和 MIME 类型
3. **已开启 OCR**: 图片先调用 OCR 模型提取文字，再把识别结果拼入本轮用户上下文
4. **已开启文件识别**: 非图片文件先调用选中的 Chat 模型读取附件，再把识别结果拼入本轮用户上下文
5. **未开启对应识别能力**: 附件会随请求直传给支持多模态内容的模型；在不支持文件输入的接口上退化为文件名、MIME 类型、大小或 base64 文本上下文
6. 重试、失败后重试和编辑用户消息后重发都会复用原消息附件，并重新执行 OCR 或文件识别上下文构建

附件处理包含多个异步文件操作：读取 picker 结果、复制到应用目录、计算文件大小、读取剪贴板二进制内容。每个最终 `setState()` 前都要检查 `mounted`，因为文件选择器、相机或系统剪贴板可能在用户离开页面后才返回结果。

### 长图分享
1. 点击消息操作中的分享按钮进入选择模式
2. 选中消息后，`_ShareConversationImage` 生成分享专用布局
3. 使用 `ScreenshotController.captureFromLongWidget()` 捕获长内容，较多消息时降低 pixelRatio
4. 桌面端写入系统剪贴板，移动端交给 `share_plus` 分享；也可保存到本地

### 重试与历史导航
- `_retry()`: 重新生成当前回复, 保留原回复到重试历史
- `<` `>` 导航: 在多次重试版本间切换, 同时切换对应的用户文本、附件和思考内容
- `_sendRetry()`: 编辑用户消息后重发, 在重试链中创建分支
- `_editStartNewConversation()`: 从历史消息处编辑并开始新的对话分支；如果原用户消息带附件，新分支会保留附件并重建 OCR/文件识别上下文

### 日程与时区
- `ToolCallService.currentTimeContext()` 会把当前设备本地时间、时区名和 `timezoneOffsetMinutes` 注入启用工具的系统消息。
- `get_current_time` 返回 `iso`、`localIso`、`timezone` 和 `timezoneOffsetMinutes`，供模型解析“今天/明天/几点”等相对时间。
- `create_schedule`、`update_schedule` 和 `list_schedules` 解析 ISO-8601 参数后统一转本地时间，返回日程时也输出本地 ISO，保证工具结果和日历 UI 一致。
- 日历周视图和年视图按日期区间相交判断日程，跨天日程会显示在覆盖到的日期内。

---

## LatexRenderer

`lib/widgets/latex_renderer.dart` — 使用 `flutter_markdown_plus`、`flutter_math_fork` 和 `highlight` 渲染 Markdown、代码块与数学公式

- **引擎**: `flutter_math_fork` — 原生 Flutter Canvas 渲染，支持完整 TeX 数学语法
- **块级公式**: `Math.tex(formula, mathStyle: MathStyle.display)`，居中卡片容器
- **内联公式**: `Math.tex(formula, mathStyle: MathStyle.text)`，通过 `WidgetSpan` 嵌入文本流
- **渲染能力**: 分数（上下堆叠+水平分数线）、根号（包围表达式）、积分/求和（上下限）、矩阵、括号自动缩放等
- **解析失败**: 回退到 monospace 原文显示，不阻塞 UI
- **智能检测**: `hasLatexContent()` 自动区分 `$...$` 数学公式与普通文本中的 `$` 符号
- **代码围栏保护**: LaTeX 检测和归一化跳过 fenced code block，避免代码块中的 `$`、`\(...\)`、`\[...\]` 被误解析
- **代码字体**: 代码块和导出图行号使用内置 `Hurmit Nerd Font` 字体资源，保证跨平台等宽和 Nerd Font 符号显示一致
- **语法高亮**: 代码块读取 fenced code block 的语言标记，使用 `highlight` 按语言解析，未标注时自动识别，并映射到 One Dark Pro 风格颜色
- **块操作**: 代码块和块级公式统一通过 `_ExportableBlock` 提供标题栏、源码复制和单块 PNG 导出
- **导出路径**: 桌面端写入系统剪贴板，Android/iOS 调用 `saveImageToGallery` 保存到图库，其他平台回退到临时文件分享
- **长图代码块**: `wrapCodeBlocks` 可在分享/导出场景让代码块自动换行，避免横向滚动内容被截图裁剪
- **`MarkdownWithLatex`**: 自动检测→走 TeX 渲染，否则走 `MarkdownBody`；支持传入 `textStyle`、`selectable` 和 `wrapCodeBlocks` 供消息、预览与分享长图使用

## 空安全与容错

- `_getModel()` 返回 `ModelConfig?` 类型，所有调用处均做空值检查
- `_findModelById()` 辅助方法用 try-catch 安全查找模型，替代 `cast<ModelConfig?>()` 模式
- `_doSend()` 在调用前检查 `_convId` 是否为null
- 流式请求完成和出错时分别处理，确保 `_streaming` 状态正确重置
- 图片选择/上传过程中的 `mounted` 检查，防止Widget销毁后操作Context
- `updateLastMessage()` 使用 sentinel 区分“未传入 thinkingContent”和“显式清空 thinkingContent”
- `ModelConfig.copyWith()` 对 nullable 高级参数也使用 sentinel，允许用户清空采样参数
- `Conversation.fromJson()` 对消息逐条容错，避免单条损坏消息拖垮整个对话
- `AppSettings.fromJson()` 对角色和提示词逐条容错，避免设置整体回退默认值

## 流式请求生命周期

```
_send() → addMessage(user) → addMessage(assistant, '') → _doSend()
  → _doStream() → ApiService.sendStreamRequest()
    → stream.listen(
        onData: updateLastMessage(convId, buf, save: false) → notifyListeners()
        isDone: updateLastMessage(convId, buf, thinkingContent: think, save: true) → 持久化思考过程并同步 _thinkMap
        onError: updateLastMessage(convId, error, save: true) → setState(_streaming = false)
        onDone: setState(_streaming = false) [兜底]
      )
```

## 模型查找逻辑

`_getModel(mp)` 按优先级查找当前对话使用的 Chat 模型:
1. 对话绑定的 `modelId` (优先)
2. `pendingModelId` (对话创建前暂存)
3. 草稿对话设置中的 `modelId`
4. 全局 `lastChatModelId`
5. Chat 分类列表中第一个模型 (兜底)

## API 参数策略

- OpenAI 兼容接口发送 `thinking: {type: enabled|disabled}` 显式控制思考能力
- Ollama 使用 `think` 布尔值控制思考能力
- Anthropic 保持标准 `/messages` 字段，额外能力由 `extraParams` 显式覆盖或补充
- `extraParams` 不覆盖代码已经设置的关键字段，因此不能用它替换 `model`、`messages`、`stream` 等核心请求结构
- OpenAI 兼容工具调用仅在模型 `supportsTools=true` 且未设置 `extraParams.disableTools=true` 时启用
- Ollama 和 Anthropic 不走原生 tool calls，避免协议不完整导致工具消息格式错误

## 发布风险清单

这些风险不是当前版本阻断项，但发布前应理解边界。

| 风险 | 说明 | 缓解 |
|------|------|------|
| API Key 备份 | 选择导出 API 配置时，模型配置会包含 API Key | 备份文件按敏感文件保存，不公开分享 |
| 写工具副作用 | `save_note`、`create_schedule`、`update_schedule` 会修改本地数据 | 仅在可信对话中启用工具，后续可加用户确认 |
| 精确位置 | `get_location` 会把位置作为工具结果发给模型 | Android 系统权限会先授权，后续可加应用内二次确认 |
| SharedPreferences 容量 | 大量对话、笔记和修订仍存 JSON | 发布后可考虑迁移到 SQLite 或文件分片 |
| 平台能力差异 | Web、桌面、移动端剪贴板/图库/分享行为不同 | 发布前按平台手测导出和分享 |
