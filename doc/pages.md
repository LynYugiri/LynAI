# 页面与使用路径

这份文档从用户视角解释页面能做什么，并指出维护时应该看的文件。

## 页面地图

```text
HomePage
├── 功能
│   ├── 功能总览
│   ├── 对话历史
│   ├── 日程表
│   ├── 笔记
│   ├── 待办清单
│   ├── 情景演绎
│   └── 插件
├── 插件市场
├── 对话
├── 社区
└── 设置
    ├── 关于
    ├── 背景
    ├── API
    ├── 主题
    ├── 数据管理
    └── 回收站
```

主 Tab 由 `HomePage` 的 `IndexedStack` 保持状态，顺序由 `AppTab` 枚举定义（feature → market → chat → community → settings）。设置子页、笔记详情、公式编辑和更新日志页面使用命令式 `Navigator.push(MaterialPageRoute)`。

## HomePage

文件：`lib/pages/home_page.dart`

`HomePage` 是根页面，负责三件事：主 Tab 切换、返回键协调、背景图/毛玻璃渲染。

| 行为 | 说明 |
|------|------|
| Tab 保活 | 功能、插件市场、对话、社区、设置五个 Tab 不因切换销毁。 |
| 历史跳转 | 功能页点历史对话后切到对话 Tab，并默认定位到消息末尾。 |
| 角色切换 | 从历史页切换角色时同步角色上下文。 |
| 返回键 | 优先退出局部状态，例如消息选择、笔记详情、非对话 Tab。 |
| 背景图 | 读取 `AppSettings.backgroundImagePath` 并叠加模糊和遮罩。 |
| 双击手势 | 双击功能 Tab 回到仪表盘，双击对话 Tab 新建对话。 |

`AppTab` 枚举把 Tab 索引从魔法数字抽出来，避免 `_currentIndex == 1` 这类硬编码扩散。默认 Tab 和系统返回键兜底目标都是 `AppTab.chat`。

## ChatPage

文件：`lib/pages/chat_page.dart`

`ChatPage` 协调模型选择、附件、语音、文件识别、OCR、工具调用、Agent/Subagent、Agent 工作记忆、流式响应、失败恢复和分享。

打开历史对话只加载该对话自己的设置快照，不把模型、提示词或识别设置写回全局设置。历史请求直接使用快照中的系统提示词正文；即使全局同 ID 提示词后来被编辑，旧会话上下文也保持不变。连续工具调用达到 `ToolCallService.maxToolRounds` 后，页面要求模型基于已有结果结束，并拒绝继续执行工具。

### 输入区

| 控件 | 作用 |
|------|------|
| 模型选择 | 选择当前 Chat 子模型。 |
| 对话设置 | 系统提示词、语音模型、OCR 模型（含 Android 本地 OCR 选项）、文件识别模型和文件识别 prompt。 |
| thinking 开关 | 控制当前请求是否启用思考能力。 |
| OCR 开关 | 控制图片是否先走 OCR；识别结果以 `[图片 OCR 识别结果（来源: …，可能含识别误差）]` 标注替换原图发往模型，原图不再作为多模态附件上传。 |
| 文件识别开关 | 控制非图片文件是否先由 Chat 模型读取；识别结果以 `[文件识别结果（来源: …，可能含识别误差）]` 标注替换原文发往模型，原文件不再作为输入上传。 |
| 附件按钮 | 选择文件、多图、拍照或桌面剪贴板图片。 |
| 语音按钮 | 使用系统语音识别或配置的语音模型。 |

桌面端 `Enter` 发送，`Shift + Enter` 换行。移动端回车默认换行，点击发送按钮发送。移动端只有用户主动点输入框才弹出输入法；从历史打开对话和模型输出结束不会自动唤起键盘。

### 消息区

消息使用 `MarkdownWithLatex` 渲染，支持 Markdown、代码高亮、LaTeX、公式块、代码块复制和单块图片导出。assistant 消息可显示折叠的 thinking 内容。

### 重试与分支

| 功能 | 说明 |
|------|------|
| 重试 assistant 回复 | 保留旧回复并重新请求模型。 |
| 回复版本切换 | 在多个重试结果之间切换正文、附件和思考内容。 |
| 编辑用户消息后重发 | 从当前上下文创建新分支。 |
| 从历史消息继续 | 截取历史上下文并创建新对话。 |

### 分享

对话页可进入多选模式，把选中消息渲染成长图。桌面端优先写入剪贴板，移动端使用系统分享或图库保存。

## FeaturePage

文件：`lib/pages/feature_page.dart` 和 `lib/pages/features/*.dart`

功能页是一个 shell，当前子功能保存在 `AppSettings.lastFeature`。

| 子功能 | 文件 | 用户能做什么 |
|--------|------|--------------|
| 功能总览 | `features/dashboard.dart` | 查看功能入口卡片并快速进入子功能。 |
| 对话历史 | `features/feature_shell.dart` | 搜索历史、按角色分组、删除对话、跳转对话、切换角色。 |
| 日程表 | `features/schedule_page.dart` | 查看月/周/年视图，创建跨天日程或任务类日程。 |
| 笔记 | `features/notes_page.dart`, `features/note_detail_page.dart` | 文件夹、Markdown/LaTeX 编辑、分页、修订时间线、导入导出。 |
| 待办清单 | `features/todo_lists_page.dart` | 多清单、任务勾选、排序、Markdown 导入导出、长图分享。 |
| 情景演绎 | `features/roleplay_page.dart` | 情景模板、多角色线程、导演决策、玩家消息、附件和导出。 |
| 插件 | `features/plugin_feature_page.dart` | WebView 加载插件提供的功能页面，支持跨插件导航和独立 WebView 上下文。 |

## 对话历史

历史页读取 `ConversationProvider.conversations`。搜索匹配标题、消息正文和附件名，支持普通关键词、`re:` 和 `/regex/i` 语法，并高亮命中片段。历史按当前角色和其他角色分组，用户可从历史页切换当前角色。

## 日程表

日程读取 `FeatureProvider.schedules`。月视图适合查日期，周视图适合看时间段，年视图适合快速定位月份。Android 日程变化后会刷新小组件和通知。

## 笔记

笔记支持文件夹、分页、编辑/预览切换、Markdown/LaTeX、修订时间线和 AI 修改建议。保存会生成内容哈希修订；从历史版本打开后，如果内容没有变化，不创建空修订。离开未保存内容时会要求确认。

活动分页有并行修订头时，编辑器显示冲突横幅和工具栏入口，并暂停普通保存。三方解决器在桌面端并排显示共同基线、本地和传入正文，在移动端使用可展开来源卡片；下半区始终提供可编辑合并结果。提交前会检查分页头是否已变化，过期时要求重新加载；超过两个头时按两两合并继续保留其余头。

## 待办清单

待办支持多清单、清单排序、清单内任务排序、Markdown 导入导出和长图分享。

## 情景演绎

情景演绎页面维护情景和线程。情景定义导演、玩家和默认角色；线程保存一次演绎的角色快照和消息历史。导演模型决定下一步由哪个角色发言、是否旁白或是否等待用户。玩家在 AI 运行时继续发送的消息会排队。

可重点手测：创建情景、从情景开新线程、修改线程设置、上传附件、AI 自动轮次、等待用户、导出长图和删除情景。

## PluginMarketPage

文件：`lib/pages/plugin_market_page.dart`

插件市场页是插件全生命周期的入口，包含两个分段：

| 分段 | 功能 |
|------|------|
| 市场 | 从 `MarketService` 分页浏览远端插件目录，查看详情，下载安装。后端未连接时显示空态文案与「从 ZIP 导入」入口。 |
| 已安装 | 列出本地已安装插件，支持卸载和跳转到权限/配置详情。 |

市场分段的远端数据由 `MarketService` 抽象提供。已配置后端时使用 `RemoteMarketService` 请求真实目录，按 `hasMore` 显示「加载更多」，合并下一页时按插件 ID 去重；未连接时使用 `LocalMarketService` 显示空态。

已安装分段直接读取 `PluginProvider.plugins`。每个插件卡片提供「权限与配置」（跳转到 `PluginDetailPage`）和「卸载」（调用 `PluginProvider.uninstall`）两个操作。

## PluginMarketDetailPage

文件：`lib/pages/plugin_market_detail_page.dart`

展示单个 `MarketPluginEntry` 的完整信息：截图、描述、权限清单、SemVer 格式版本和作者。提供安装按钮；下载受市场响应大小边界保护，安装前校验条目 SHA-256（若提供）、唯一根目录 manifest 和插件 ID，随后才交给 `PluginProvider.importZipBytes` 串行安装。后端未连接时安装按钮禁用并显示提示。

## CommunityPage

文件：`lib/pages/community_page.dart`

社区页首次成为当前 Tab 时才加载公开动态，支持分页、下拉刷新、Markdown 正文和最多 9 张显式媒体图片。游客可浏览动态、详情、评论和用户主页；发布、编辑、删除、点赞、收藏、评论、资料修改和置顶会复用 `LoginDialog` 要求登录。收藏页和个人主页从社区 AppBar 进入。社区 Markdown 会移除远程图片语法、危险 scheme 链接和原始 HTML 标签，只加载后端返回的媒体资源。切换后端或账号后会清空旧作用域内容并重新加载。

## PluginManagementPage

文件：`lib/pages/plugin_management_page.dart`

插件管理页负责已安装插件的权限管理、配置和文件编辑。插件的浏览、安装和卸载已迁移到插件市场页（`PluginMarketPage`），本页聚焦于本地配置。

| 行为 | 说明 |
|------|------|
| 浏览插件 | 展示内置和用户安装的插件列表，显示名称、版本、启用状态和权限。 |
| 导入 ZIP | 从文件选择器加载 `.zip` 插件包（离线导入，与市场页的远端安装互补）。 |
| 启用/禁用 | 切换插件启用状态，禁用插件不会触发其工具或函数挂载。 |
| 权限管理 | 查看和修改插件声明的权限，例如网络、文件读写、平台能力。 |
| 代码编辑器 | 打开插件 Lua 入口脚本进行编辑，支持语法高亮和保存。 |
| 工具/函数开关 | 插件目录内的 `tools/` 和 `functions/` 子目录注册了对应能力，可独立开关。 |
| 快照导出 | 生成当前插件状态的压缩包，保存到用户选择的位置。 |
| 配置表单 | 根据 `plugin.json` 中 `config` 定义的 schema 字段渲染配置 UI。 |

登录用户还可从市场提交页选择本地第三方插件并上传 ZIP；客户端在发起请求前执行市场提交大小限制。管理员审核页和“我的提交”页读取后端状态，提交元数据来自本地 `plugin.json` manifest。

设置页入口名称保留「插件管理」，副标题为「权限与配置」。插件入口脚本、工具和函数由 `PluginLuaRuntimeService` 在沙箱中加载执行。

## PluginFeaturePage

文件：`lib/pages/features/plugin_feature_page.dart`

`PluginFeaturePage` 是插件的功能展示页，位于 `FeaturePage` 的功能 Tab 下。它使用 WebView 加载插件提供的 `feature` 页面，每个插件拥有独立的 WebView 上下文。

| 行为 | 说明 |
|------|------|
| WebView 加载 | 从插件目录读取 `feature/` 下的 HTML 入口，通过 InAppWebView 渲染。 |
| 跨插件导航 | 插件可通过 JavaScript 接口跳转到其他插件的功能页。 |
| 上下文隔离 | 每个插件使用独立的 WebView 实例，避免跨插件 JS 污染。 |
| 平台兼容 | 不支持 WebView 的平台显示不支持提示。 |

## SettingsPage

文件：`lib/pages/settings_page.dart`

设置页本身是入口卡片，具体配置由子页面承担。顶部显示 `AccountHeaderCard` 账号卡片：已登录时显示头像、用户名和退出登录按钮；未登录时显示登录按钮，点击后弹出 `LoginDialog`（手机号+密码，可切换注册模式）。后端未连接时登录/注册不可用，并提示先配置后端地址。

| 页面 | 文件 | 说明 |
|------|------|------|
| 关于 | `about_page.dart` | 应用信息、项目链接、许可证和更新日志入口。 |
| 背景 | `background_page.dart` | 背景图、清除背景、模糊开关和强度。 |
| API | `api_models_page.dart` | 模型配置分类、编辑、排序和模型拉取。 |
| 悬浮窗 | `floating_assistant_settings_page.dart` | Android 系统悬浮助手设置。原生面板分为 Chat、Translation、Agent；翻译支持一次翻译和停止滚动后自动翻译，Agent 模式展示运行状态与完整 Plan。 |
| 翻译历史 | `translation_history_page.dart` | 浏览悬浮窗屏幕翻译历史记录（时间/原文/译文/应用包名），长按复制、一键清空。 |
| 主题 | `theme_page.dart` | 预设色、HSV 调色板、浅色/深色/跟随系统。 |
| 回收站 | `recycle_bin_page.dart` | 按功能分类查看已删除项目，支持恢复、永久删除和清空。 |
| 数据管理 | `data_management_page.dart` | 服务端数据同步、备份导出、备份预览、导入和冲突处理。 |

## ApiModelsPage

文件：`lib/pages/api_models_page.dart`

模型配置按用途分类：Chat、OCR、Speech、Image Generation。Chat 配置可以有多个子模型，每个子模型都可以单独设置启用状态、视觉能力、思考能力、工具能力和采样参数。托管 LynAI 配置不可手动修改 endpoint/API key，但可以在本机关闭，或为 `maxTokens`、`temperature`、`topP`、视觉、思考和工具能力设置本机覆盖项。

高级参数支持显式清空。实现上通过 sentinel 区分“不更新”和“清空为 null”。

## DataManagementPage

文件：`lib/pages/data_management_page.dart`

数据管理页通过 `BackupService` 和 `SyncProvider` 工作。storage_v2 创建和升级在启动阶段自动完成。登录并连接服务端后，顶部同步卡片可手动触发增量拉取和本地变更上传；设置页只保留「连接到服务端」入口，不再承载同步弹窗。

| 步骤 | 说明 |
|------|------|
| 选择导出内容 | 可选择设置、对话、笔记、日程、待办、情景演绎。 |
| 导出文件 | 写入 ZIP 到用户选择的位置。 |
| 读取备份 | 选择 ZIP 后解析 manifest、分区 JSON 和资源。 |
| 预览 | 显示分区数量、警告和冲突。 |
| 导入 | 选择模式和冲突动作后写入 Provider。 |

选择 API 配置只导出非秘密模型设置。只有额外启用“加密并包含 API Key”并设置密码，API key 才会进入 Argon2id + XChaCha20-Poly1305 加密备份；设备私钥和登录令牌始终排除。

## MathLive 公式编辑页

文件：`lib/pages/mathlive_formula_editor_page.dart`

可视化公式编辑器使用本地 `assets/mathlive/editor.html`。不支持 WebView 的平台会回退源码模式。WebView 回调可能晚于页面生命周期，因此回调入口必须检查 `mounted`。

## 更新日志页面

文件：`lib/pages/changelog_page.dart`、`lib/widgets/changelog_dialog.dart`

启动后如果发现有未读更新日志，会展示弹窗。用户选择“查看全部”时，弹窗只返回 action，真正跳转由外层页面上下文执行。历史更新日志页面从 asset manifest 读取 `changelogs/*.md`。

## 手测建议

| 页面 | 重点路径 |
|------|----------|
| ChatPage | 普通发送、停止、失败重试、编辑重发、附件重试、语音快速松手、工具调用、Agent Lua、Subagent、移动端自动化。 |
| 悬浮窗 | Android 悬浮权限、无障碍权限、后台气泡；Chat 模式输入/发送/停止/新建对话和语音；Translation 模式手动翻译、自动翻译、停止自动后保留当前译文、清除译文、滚动跟随、停止 600ms 后刷新、横排/CJK 竖排、屏蔽应用和历史；Agent 模式默认切换、完整 Plan、暂停/继续/停止；节点树排除 LynAI 窗口，Agent 手势期间悬浮窗不可触摸。 |
| FeaturePage | Dashboard 跳转、历史搜索、角色切换、跨天日程、笔记未保存确认、待办导入导出。 |
| Roleplay | 情景创建、线程创建、导演/角色生成、玩家消息排队、附件、长图导出。 |
| ApiModelsPage | 添加/删除模型、拖拽排序、获取模型、清空高级参数、子模型能力开关。 |
| DataManagementPage | 普通无密钥 ZIP、密码加密含 API Key 备份、新旧备份读取、冲突导入、附件恢复。 |
| ThemePage | 预设色、HSV 拖动、深浅色切换、重启恢复。 |
## LAN Pairing And Sync

Settings includes a LAN page for discovery, showing a one-time QR code, mobile
camera scanning, desktop QR image import, trusted peer listing, manual sync,
revocation, conflict guidance, and explicit secret-transfer rules. Successful
pairing automatically activates LAN sync and starts the first bidirectional
exchange; if that exchange fails, the page keeps the trusted pairing and reports
partial success with a manual retry path. Windows users are reminded to allow
LynAI through the private-network firewall prompt.
