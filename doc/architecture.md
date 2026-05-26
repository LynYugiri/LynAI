# 架构概览

LynAI 的架构分为四层：页面层、Provider 状态层、Service 协议层、Model 数据层。页面层不直接持久化数据；Provider 只管理本地状态和落盘；Service 处理外部 API、平台通道和备份文件；Model 保持可序列化、可兼容旧数据。

## 运行时结构

```text
MaterialApp
  └── MultiProvider
        ├── SettingsProvider
        ├── ModelConfigProvider
        ├── FeatureProvider
        └── ConversationProvider
              └── HomePage
                    ├── FeaturePage
                    │     ├── History
                    │     ├── Schedule
                    │     ├── Notes
                    │     └── Todo Lists
                    ├── ChatPage
                    │     ├── ApiService
                    │     ├── ToolCallService
                    │     ├── MarkdownWithLatex
                    │     └── ShareConversationImage
                    └── SettingsPage
                          ├── ApiModelsPage
                          ├── DataManagementPage → BackupService
                          ├── ThemePage
                          ├── BackgroundPage
                          └── AboutPage
```

## 启动流程

1. `main()` 注册四个 Provider。
2. `LynAIApp.initState()` 通过 `Future.microtask()` 调用 `_loadData()`。
3. 并行加载对话、功能数据、模型配置和应用设置。
4. `SettingsProvider.repairMediaModelSelections()` 修复设置中已不存在的模型引用。
5. 根据 `AppSettings.themeColor` 和 `themeMode` 构建 `MaterialApp`。
6. 加载中显示 Splash，失败显示可重试错误页，成功进入 `HomePage`。

## 数据流

```text
用户操作
  → Page 校验输入并组装参数
  → Provider 创建新的不可变模型实例
  → notifyListeners() 立即刷新 UI
  → 保存快照进入串行 Future 队列
  → SharedPreferences(JSON) / 应用私有文件目录
```

串行保存队列是关键约束：UI 更新不等待落盘，但落盘按快照顺序执行，避免连续编辑、拖拽、流式刷新或导入替换时旧状态覆盖新状态。

## 聊天主链路

```text
_send()
  → 复制附件到私有目录
  → 解析当前角色和 ConversationSettings
  → 创建 conversation（如果还没有）
  → addMessage(user)
  → addMessage(assistant, '')
  → 构建 API messages
  → ApiService.sendStreamRequest()
  → updateLastMessage(save:false) 逐 chunk 更新
  → 流结束后处理 toolCalls
  → updateLastMessage(save:true) 保存最终正文和 thinkingContent
```

### 模型选择优先级

1. 当前历史对话绑定的 `modelId`。
2. 对话创建前暂存的 pending model。
3. 草稿 `ConversationSettings.modelId`。
4. `AppSettings.lastChatModelId`。
5. Chat 分类中第一个可用模型。

### 请求上下文

| 上下文 | 来源 |
|--------|------|
| 系统提示词 | 当前角色、选中提示词模板或对话设置快照 |
| Chat 模型 | 当前对话绑定模型或全局最近模型 |
| thinking | 对话设置和当前子模型 `supportsThinking` |
| OCR | `imageOcrEnabled` + OCR 模型 |
| 文件识别 | `imageRecognitionEnabled` + Chat 文件识别模型 + prompt |
| 工具调用 | 当前子模型 `supportsTools` + API 类型 + extraParams |

## 流式生命周期

| 路径 | 处理 |
|------|------|
| 正常完成 | 保存最终正文和累积 reasoning；如果有工具调用则进入工具循环 |
| 用户停止 | 取消 stream subscription，保留已生成正文并写入停止提示 |
| 请求失败 | 保留已收到正文，追加失败原因，清理本轮不存在的旧 thinking |
| 旧流事件 | 通过流 generation 忽略，避免停止/重试后旧事件污染当前消息 |

OpenAI SSE 的 `error` payload 和 Anthropic 的 `type:error` 会作为异常进入失败路径。格式异常的单个 chunk 会跳过，不中断整段回复。

## 附件链路

```text
文件/图片/拍照/剪贴板
  → 写入应用私有目录
  → MessageImage(path, name, size, mimeType)
  → 发送前转成 ChatFileInput
  → 可选 OCR 或文件识别
  → 按协议转换为多模态内容或文本上下文
```

附件策略有两个目的：历史消息不依赖系统临时文件；备份服务可以安全归档私有目录内被引用的附件。重试、编辑重发和历史分支都复用原附件元数据。

## 工具调用链路

```text
模型返回 toolCalls
  → ToolCallService.execute()
  → 读取或修改 FeatureProvider / 平台通道
  → 工具结果作为 tool message 或文本上下文回传模型
  → 模型生成最终自然语言回复
```

原生工具调用仅对 OpenAI 兼容协议启用。其他协议可通过 JSON fallback 触发。启用工具时系统消息会追加本地时间、时区和偏移量；日程工具所有时间统一转为本地时间，避免 UI 与模型理解不一致。

## 功能页架构

`FeaturePage` 是一个轻量 shell，当前子功能由 `AppSettings.lastFeature` 决定。

| 子功能 | 依赖 | 说明 |
|--------|------|------|
| 对话历史 | `ConversationProvider`, `SettingsProvider` | 搜索、按角色分组、跳转历史对话 |
| 日程 | `FeatureProvider.schedules` | 月/周/年视图和本地时区展示 |
| 笔记 | `FeatureProvider.notes/revisions/folders` | Markdown 编辑、修订、文件夹、导入导出 |
| 待办 | `FeatureProvider.todoLists` | 多清单、勾选、排序、导入导出 |

功能页内部子页面通过 Dart `part` 文件拆分，保持共享搜索、导出、格式化和 UI 组件在同一 library 中可访问。

## Markdown/LaTeX 渲染

文件：`lib/widgets/latex_renderer.dart`

| 能力 | 实现 |
|------|------|
| Markdown | `flutter_markdown_plus` |
| LaTeX | `flutter_math_fork`，支持 `$...$`、`$$...$$`、`\(...\)`、`\[...\]` |
| 代码高亮 | `highlight`，One Dark Pro 风格映射 |
| 字体 | 内置 Hurmit Nerd Font 用于代码块和导出图 |
| 保护 | LaTeX 检测跳过 fenced code block，避免误解析代码中的 `$` |
| 导出 | 代码块和公式块可复制源码或导出 PNG |
| 长图 | `wrapCodeBlocks` 让代码块自动换行，避免截图裁剪横向滚动内容 |

解析失败时公式回退为 monospace 原文，不阻塞页面渲染。

## 备份架构

```text
BackupSelection
  → BackupService.exportZip()
  → manifest.json + 分区 JSON + 私有附件

ZIP 文件
  → readZip()
  → BackupArchiveData
  → preview()
  → ImportPlan
  → importArchive()
  → Provider.replace / merge / add
```

备份服务不会盲目复制外部路径，只会归档应用私有目录中被当前数据引用的附件。导入时先恢复附件到当前设备私有目录，再重映射数据中的路径。

## 平台能力

| 能力 | 平台 | 通道/插件 |
|------|------|-----------|
| 打开 App | Android | `lynai/native_tools.openApp` |
| 定位 | Android | `lynai/native_tools.getLocation` |
| 保存图片到图库 | Android | `lynai/native_tools.saveImageToGallery` |
| 日程小组件/通知 | Android | `lynai/schedule_widget` |
| 桌面剪贴板图片 | Linux/macOS/Windows | `super_clipboard` |
| 文件选择 | 多平台 | `file_picker` |
| 图片/拍照 | 移动端为主 | `image_picker` |
| 系统分享 | 多平台 | `share_plus` |

Web 可构建，但浏览器沙箱会限制本地文件、剪贴板、平台通道和后台能力。

## 容错原则

| 场景 | 策略 |
|------|------|
| SharedPreferences 中单条数据损坏 | 跳过坏项，保留其他数据 |
| 旧附件字段 | 兼容 `filePath` 并推导缺失元数据 |
| 模型 ID 悬空 | 回填同类第一个可用模型或清空 |
| 流式 chunk 格式异常 | 跳过坏 chunk |
| 工具参数异常 | 跳过该工具调用，保留正文 |
| 页面销毁后的异步回调 | `mounted` 检查后再更新 UI |

## 发布风险

| 风险 | 说明 | 缓解 |
|------|------|------|
| API Key 泄露 | 备份 API 配置会包含 Key | 明确提示用户按敏感文件处理 |
| 本地工具副作用 | `save_note`、`create_schedule`、`update_schedule` 会写本地数据 | 只在可信模型和对话中启用工具 |
| 位置信息 | `get_location` 会把位置结果发给模型 | Android 权限先授权，后续可加应用内确认 |
| JSON 存储规模 | 大量历史和笔记会增加 SharedPreferences 压力 | 后续可迁移 SQLite 或文件分片 |
| 平台差异 | 分享、剪贴板、图库、WebView 能力不一致 | 发布前按平台手测关键路径 |
