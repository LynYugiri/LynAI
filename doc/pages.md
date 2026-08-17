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
    ├── MCP 服务
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

`ChatPage` 协调模型选择、附件、语音、文件识别、OCR、工具调用、Agent/Subagent、Agent 工作记忆、流式响应、失败恢复和分享。模型 turn 与工具 continuation 统一交给 `AgentLoopRuntime`，页面只订阅 run event 更新草稿并在停止、重试或销毁时取消 handle。停止会等待 runtime 的 bounded terminal result，把跨 turn 聚合的 partial content 与 reasoning 保存到最后一条 assistant 消息；失败提示也保留该聚合内容，而不是只使用当前 turn 的 UI buffer。悬浮聊天采用相同语义。

对话相关组件是独立库而非 `part`：`lib/pages/chat/` 下的 `history_drawer.dart`（历史抽屉）、`dialog_settings_content.dart`（对话设置弹窗）、`prompt_role_dialogs.dart`（系统提示词编辑）、`share_conversation_image.dart`（分享长图渲染）、`command_palette.dart`（命令面板）。长图导出流程在 `chat_image_exporter.dart` 的 `ChatImageExporter` 中（分页、捕获、剪贴板/分享/图库保存），页面只负责选择状态与结果反馈。发送给模型的 API 消息统一由 `lib/services/api_message_builder.dart` 的 `buildApiMessages` 组装，主聊天与悬浮聊天共用，避免两处 wire 语义漂移。

输入区的 Agent 按钮是当前对话或未发送草稿切换 Agent 模式的唯一入口。新草稿从全局“对话权限”读取默认状态，按钮修改后由草稿覆盖该初值；已有对话始终使用自己的 `ConversationSettings.agentEnabled`。当前模型不支持工具调用时 Agent 按钮禁用并提示原因，避免“开了 Agent 但实际不生效”。对话设置弹窗中的“对话权限”直接编辑全局 `AppSettings.agentGrantedPermissions`，与设置页“权限管理”指向同一份数据，修改即时作用于所有对话，不再有“跟随全局/自定义本对话”两态。

Agent 工具轮数上限保存为 `ConversationSettings.maxToolRounds`（新建对话从全局默认复制，默认 24，范围 4–64）。流式过程中状态栏显示“正在调用工具 (第 N/M 轮)”，接近上限时预警；达到上限后模型强制收尾，消息下方提供“继续处理”按钮，点击后从当前 Plan/工作记忆断点继续，开启新一轮 run。

打开历史对话只加载该对话自己的设置快照，不把模型、提示词或识别设置写回全局设置。历史请求直接使用快照中的系统提示词正文；即使全局同 ID 提示词后来被编辑，旧会话上下文也保持不变。连续工具调用达到该对话的 `ConversationSettings.maxToolRounds` 后，页面要求模型基于已有结果结束，并拒绝继续执行工具。

左侧历史抽屉在页面生命周期内保留滚动位置和角色折叠状态。点击“默认”或其他角色标题只折叠/展开该组，点击具体对话才切换到其所属角色；搜索期间临时展开命中分组，清空搜索后恢复原折叠状态。

### 输入区

| 控件 | 作用 |
|------|------|
| 模型选择 | 选择当前 Chat 子模型。 |
| 命令按钮 | 打开命令面板，选取笔记/笔记页面/待办清单/待办或插件命令，生成不可拆分的引用 Chip。 |
| 对话设置 | 系统提示词、语音模型、OCR 模型（含 Android 本地 OCR 选项）、文件识别模型和文件识别 prompt。 |
| thinking 开关 | 控制当前请求是否启用思考能力。 |
| OCR 开关 | 控制图片是否先走 OCR；识别结果以 `[图片 OCR 识别结果（来源: …，可能含识别误差）]` 标注替换原图发往模型，原图不再作为多模态附件上传。 |
| 文件识别开关 | 控制非图片文件是否先由 Chat 模型读取；识别结果以 `[文件识别结果（来源: …，可能含识别误差）]` 标注替换原文发往模型，原文件不再作为输入上传。 |
| 附件按钮 | 选择文件、多图、拍照或桌面剪贴板图片。 |
| 语音按钮 | 使用系统语音识别或配置的语音模型。 |

主聊天和情景演绎共用 composer 键盘策略：桌面端裸 `Enter` 发送、`Shift + Enter` 换行；Android/iOS 裸 `Enter` 换行；所有平台 `Ctrl + Enter` 或 `Meta + Enter` 发送。`Alt + Enter` 和输入法 composing 期间的回车不发送。移动端只有用户主动点输入框才弹出输入法；从历史打开对话和模型输出结束不会自动唤起键盘。桌面端 `Escape` 在焦点不处于输入框时复用 Home/Feature 现有返回处理。

命令面板复用模型选择按钮的浮层样式，首层列出内置选择器（笔记/笔记页面/待办清单/待办）与插件命令，进入后按文件夹分层导航并支持搜索。选中实体产生 `ComposerReference`，通过 `ReferenceComposerController`（`lib/widgets/reference_composer.dart`）渲染为行内不可拆分 Chip：每个 Chip 在文本模型中只占一个私用区码点，退格/删除整体移除，用户无法把光标切入 Chip 内部。发送时气泡显示 `@标题` 占位，模型侧只接收 `<lynai_ref .../>`（type/id 与稳定限定字段，不含标题与正文）。引用随用户消息以 `composerSegments` 持久化，撤回/编辑时还原 Chip；失效引用在编辑时标记为“已失效”。插件命令若声明 `model`，选中后写入 `_pendingModelId` 覆盖本次发送模型。

### 消息区

消息使用 `MarkdownWithLatex` 渲染，支持 Markdown、代码高亮、LaTeX、公式块、代码块复制和单块图片导出。assistant 消息可显示折叠的 thinking 内容。Agent Plan 面板在消息列表与输入区之间常驻：收起态显示进度条和当前步骤，展开态显示每步状态 chip 与摘要，点击步骤可展开完整摘要，“详情”按钮打开底部完整计划视图（`lib/pages/chat/agent_plan_panel.dart`）。

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

功能页是一个 shell，当前子功能保存在 `AppSettings.lastFeature`。`features/` 下每个页面都是独立库（`dashboard.dart`、`feature_shell.dart`、`schedule_page.dart`、`notes_page.dart`、`note_detail_page.dart`、`todo_lists_page.dart`、`roleplay_page.dart`、`knowledge_page.dart`），共享的搜索匹配器、空状态、差异统计、导出常量与插件功能页引用集中在 `features/feature_shared.dart`，不在页面之间复制。

| 子功能 | 文件 | 用户能做什么 |
|--------|------|--------------|
| 功能总览 | `features/dashboard.dart` | 查看功能入口卡片并快速进入子功能。 |
| 对话历史 | `features/feature_shell.dart` | 搜索历史、按角色分组、删除对话、跳转对话、切换角色。 |
| 日历 | `features/schedule_page.dart` | 查看月/日/年发生记录，创建和编辑事件、任务、纪念日及提醒。 |
| 笔记 | `features/notes_page.dart`, `features/note_detail_page.dart` | 文件夹、Markdown/LaTeX 编辑、分页、修订时间线、导入导出。 |
| 任务清单 | `features/todo_lists_page.dart` | 未完成/已完成聚合、可展开自定义清单、任务日期、提醒、排序、Markdown 导入导出和长图分享。 |
| 情景演绎 | `features/roleplay_page.dart` | 情景模板、多角色线程、导演决策、玩家消息、附件和导出。 |
| 知识库 | `features/knowledge_page.dart` | 管理知识库、类别、条目、解释和来源；支持搜索、高亮、多种排序、拖拽自定义顺序、Markdown 预览与 AI 重新生成解释。 |
| 插件 | `features/feature_shared.dart` | 插件功能页引用解析；实际渲染由 `PluginFeatureWebView` 完成，支持跨插件导航和独立 WebView 上下文。 |

## 对话历史

历史页读取 `ConversationProvider.conversations`。搜索匹配标题、消息正文和附件名，支持普通关键词、`re:` 和 `/regex/i` 语法，并高亮命中片段。历史按当前角色和其他角色分组，用户可从历史页切换当前角色。

## 日历

日历页同时读取 `CalendarProvider` 和 `TaskProvider`，通过 `CalendarOccurrence` 统一显示日历事件、任务计划/截止和纪念日。月视图展示月历摘要，日视图提供可横向浏览日期的全天区和 24 小时时间轴，年视图用于快速定位月份。跨日事件按日期区间相交展示；同一任务计划和截止在同一天时显示为合并发生记录。

右上角新增菜单分别创建事件、任务和纪念日。事件支持定时/全天及跨日范围；任务支持计划、截止和完成状态；纪念日支持一次性/每年、来源年份、周年数和闰日回退。点击发生记录会打开其规范来源对象编辑器，而不是修改投影本身。事件、任务和纪念日的多字段编辑器打开时不主动聚焦标题，用户点击具体输入框后才建立文本输入焦点。

事件和纪念日编辑器提供常用提醒偏移。日期型提醒默认当天 09:00。提醒数据跨平台保存，但系统通知、小组件投影和通知权限请求仅 Android 可用；非 Android 页面不应承诺系统级提醒投递。

## 笔记

笔记支持文件夹、分页、编辑/预览切换、Markdown/LaTeX、修订时间线和 AI 修改建议。保存会生成内容哈希修订；从历史版本打开后，如果内容没有变化，不创建空修订。离开未保存内容时会要求确认。

活动分页有并行修订头时，编辑器显示冲突横幅和工具栏入口，并暂停普通保存。三方解决器在桌面端并排显示共同基线、本地和传入正文，在移动端使用可展开来源卡片；下半区始终提供可编辑合并结果。提交前会检查分页头是否已变化，过期时要求重新加载；超过两个头时按两两合并继续保留其余头。

## 任务清单

任务页读取 `TaskProvider`，首页为可同时展开多个的清单卡片，默认全部收起；清单内直接展示完整任务顺序，完成后保留在原清单并显示删除线。顶部提供未完成和已完成聚合入口，按清单归属分组；没有 `TaskListEntry` 的任务显示为“未归入清单”，不再使用收件箱概念。

任务支持清单内快速添加、跨清单标题/备注搜索、计划/截止日期与可选时间、完成状态、移动清单和多个提醒。任务页与日历页共用规范任务编辑器；日历新建任务默认使用当前选中日期作为计划日期。任务提醒只能锚定计划或截止；没有具体时间时编辑器使用当天 09:00。删除清单后任务保留但不再属于清单；清单与清单内任务都可排序。Markdown 导入会转换成规范 `Task`/`TaskListEntry`，导出和长图分享只在页面层格式化数据。

## 情景演绎

情景演绎页面维护情景和线程。情景定义导演、玩家和默认角色；线程保存一次演绎的角色快照和消息历史。导演模型决定下一步由哪个角色发言、是否旁白或是否等待用户。玩家在 AI 运行时继续发送的消息会排队，输入区复用 ChatPage 的跨平台 composer 键盘策略。

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
| 新建插件 | 右上角「+」打开 `PluginCreationPage` 向导，填写 ID/名称/版本/作者/描述并选择模板，创建后进入详情页继续编辑。 |
| 开发状态 | 非内置插件可切换「草稿 / 测试中 / 已定型」：草稿与测试中允许编辑 `plugin.json` 和入口脚本；已定型后核心文件只读。内置插件固定为已定型。 |
| 导入 ZIP | 从文件选择器加载 `.zip` 插件包（离线导入，与市场页的远端安装互补）。 |
| 启用/禁用 | 切换插件启用状态，禁用插件不会触发其工具或函数挂载。 |
| 权限管理 | 查看和修改插件声明的权限以及调用依赖插件对外函数所需的额外权限，例如网络、文件读写、平台能力。 |
| 代码编辑器 | 打开插件 Lua 入口脚本进行编辑，支持语法高亮和保存。非内置插件还会显示 `plugin.json` 和入口脚本，保存 manifest 后自动重载清单。 |
| 工具/函数开关 | 插件目录内的 `tools/` 和 `functions/` 子目录注册了对应能力，可独立开关。 |
| 快照导出 | 生成当前插件状态的压缩包，保存到用户选择的位置。 |
| 配置表单 | 根据 `plugin.json` 中 `config` 定义的 schema 字段渲染配置 UI。 |

插件脚手架模板由 `lib/services/plugin_scaffold_service.dart` 生成，包含空白 Lua、Lua 工具、Skill 和 WebView 功能页四类。新建插件默认禁用，待用户编辑并手动启用；第三方/快照插件允许编辑 `plugin.json` 与入口脚本，内置插件仍保持核心文件只读。

登录用户还可从市场提交页选择本地第三方插件并上传 ZIP；客户端在发起请求前执行市场提交大小限制。管理员审核页和“我的提交”页读取后端状态，提交元数据来自本地 `plugin.json` manifest。

设置页入口名称保留「插件管理」，副标题为「权限与配置」。插件入口脚本、工具和函数由 `PluginLuaRuntimeService` 在沙箱中加载执行。

## PluginStudioPage

文件：`lib/pages/plugin_studio_page.dart`

插件工坊是插件创作的集中入口，宽屏为三栏布局（文件树 / 代码编辑器 / 属性检查器），窄屏退化为卡片列表。

| 行为 | 说明 |
|------|------|
| 文件树 | 使用 `PluginProvider.listDeveloperFiles`，非内置插件显示 `plugin.json` 和入口脚本；只读文件带锁提示。 |
| 代码编辑器 | 复用 `PluginCodeEditingController` 语法高亮，支持保存、自动换行。 |
| 开发状态 | 非内置插件可切换草稿/测试中/已定型；已定型后核心文件只读。 |
| 元数据编辑 | 修改名称、版本、作者、描述并写回 `plugin.json`。 |
| 依赖编辑 | 从已安装插件中添加依赖，或移除已有依赖。 |
| 权限编辑 | 添加/移除 manifest 声明的权限。 |
| 恢复点 | 手动创建恢复点；从历史恢复点还原文件，并在还原前自动保存当前状态。 |

## PluginFeaturePage

文件：`lib/widgets/plugin_feature_webview.dart`（`PluginFeatureWebView`，由 `FeaturePage` 路由）

`PluginFeatureWebView` 是插件的功能展示页，位于 `FeaturePage` 的功能 Tab 下。它使用 WebView 加载插件提供的 `feature` 页面，每个插件拥有独立的 WebView 上下文。功能页引用（`plugin:<pluginId>:<pageId>` 键解析与路由）由 `lib/pages/features/feature_shared.dart` 的 `PluginFeatureRef`/`ResolvedPluginFeature` 承担。

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
| 网页搜索 | `web_search_settings_page.dart` | 管理 client/backend/auto 路由、Tavily/SearXNG 首选项和 SearXNG endpoint；Tavily key 与 SearXNG bearer token 只写入 `SecretStore`。SearXNG HTTP 必须显式勾选精确 origin 明文授权，保存 Bearer token 时再次显示明文确认。 |
| 对话权限 | `agent_defaults_settings_page.dart` | 控制之后创建的主聊天和悬浮聊天是否默认启用 Agent、默认权限以及单次任务最大工具轮数（默认 24）。历史对话不随默认值变化；对话设置弹窗只编辑当前对话权限，Agent 模式由输入区按钮切换。 |
| 悬浮窗 | `floating_assistant_settings_page.dart` | Android 系统悬浮助手设置。原生面板分为 Chat、Translation、Agent；翻译支持一次翻译和停止滚动后自动翻译，Agent 模式展示运行状态与完整 Plan。 |
| 翻译历史 | `translation_history_page.dart` | 浏览悬浮窗屏幕翻译历史记录（时间/原文/译文/应用包名），长按复制、一键清空。 |
| 主题 | `theme_page.dart` | 预设色、HSV 调色板、浅色/深色/跟随系统。 |
| 回收站 | `recycle_bin_page.dart` | 按功能分类查看已删除项目，支持恢复、永久删除和清空。 |
| 数据管理 | `data_management_page.dart` | 本地备份导入导出，以及云端索引、容量、对象详情、双向同步和 purge 管理。 |
| MCP 服务 | `mcp_settings_page.dart` | 添加/编辑 HTTP 或桌面 stdio server，启用连接、测试状态、配置凭据引用与逐工具开关。 |

## McpSettingsPage

文件：`lib/pages/mcp_settings_page.dart`

MCP 设置页展示 server 名称、transport、连接状态、错误和发现的工具。启用 server 后可连接或测试；每个工具可单独开关，开关会立即影响共享 Agent 工具注册表。每个 server 卡片提供删除操作，删除会断开连接、移除注册，并清理 SecretStore 中的偏好和凭据。

HTTP server 录入 endpoint，并可显式允许 HTTP 或私网；默认要求 HTTPS 公网地址。凭据以“本地 secret 名称 -> 实际 header 名称”配置，value 只进入 `SecretStore`。stdio 录入 command、arguments 和环境变量 secret；该选项只在 Linux、macOS、Windows 启用，Android、iOS、Web 页面明确禁用。

当前页面与协议只覆盖 tools。不要在用户说明中承诺 MCP resources、prompts、sampling、roots、OAuth 自动登录或后台常驻可靠重连。

## ApiModelsPage

文件：`lib/pages/api_models_page.dart`

模型配置按用途分类：Chat、OCR、Speech、Image Generation。Chat 配置可以有多个子模型，每个子模型都可以单独设置启用状态、视觉能力、思考能力、工具能力和采样参数。每个分类最多显示一个名为 LynAI 的托管配置，不展示上游 Provider ID；该配置不可手动修改 endpoint/API key，但可以在本机关闭，或为 `maxTokens`、`temperature`、`topP`、视觉、思考和工具能力设置本机覆盖项。刷新操作表示同步 LynAI 模型，而不是同步 Provider。

高级参数支持显式清空。实现上通过 sentinel 区分“不更新”和“清空为 null”。

## DataManagementPage

文件：`lib/pages/data_management_page.dart`

数据管理页顶部使用“本地/云端”分段，默认进入本地。storage_v2 创建和升级在启动阶段自动完成；设置页只保留「连接到服务端」入口。

本地分段保持隐私说明、备份导出、备份读取预览、导入模式和冲突处理。云端分段读取当前账号与连接状态，展示索引 generation/revision、记录与 Blob 容量、分类统计、持久缓存对象和详情；对象详情绑定当前 `indexRevision`，revision 已变化时拒绝显示过期混合结果。刷新失败时继续显示上次成功缓存。索引浏览、对象/分类清理、全部清理和 operation ACK 分别受 `index`、`selectivePurge`、`fullPurge`、`operationAck` capability 门控；不支持的按钮和入口禁用，ACK 不支持时 pending operation 保留。用户可在此执行立即双向同步并处理 `SyncProvider` 冲突；普通同步同样会自动发现管理操作并完成必要 reseed，无需先打开本页。

云端对象、分类和全部数据都先请求 purge preview，再显示记录、历史 change 和 Blob 引用数量。全部清空使用高风险确认，明确说明操作只删除云端；后续 current-projection reseed 会删除本机没有 pending 编辑的远端缺失记录，真实本地 pending 编辑仍会按用户意图重新上传。客户端不提供手动 GC。

| 步骤 | 说明 |
|------|------|
| 选择导出内容 | 可选择设置、对话、笔记、规范任务/清单、日历事件/纪念日、情景演绎和插件；任务与清单、事件与纪念日分别显示可勾选子项，分区全选会覆盖该分区当前可用子项。 |
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
| ChatPage | 普通发送、停止、失败重试、编辑重发、附件重试、语音快速松手、工具调用、Agent Lua、Subagent、移动端自动化；取消后不接收晚到模型/tool result，达到轮数上限只执行强制最终 turn。 |
| MCP 服务 | HTTP/私网许可、credential header 映射、连接测试、tool list change、逐工具开关；桌面 stdio 可用，移动/Web stdio 禁用；断连后 registry 清理。 |
| 悬浮窗 | Android 悬浮权限、无障碍权限、后台气泡；Chat 模式 `Enter` 换行、`Ctrl + Enter` 发送，并在键盘关闭后允许系统返回收起面板；发送/停止/新建对话和语音；Translation 模式手动翻译、自动翻译、停止自动后保留当前译文、清除译文、滚动跟随、停止 600ms 后刷新、横排/CJK 竖排、屏蔽应用和历史；Agent 模式默认切换、完整 Plan、暂停/继续/停止；节点树排除 LynAI 窗口，Agent 手势期间悬浮窗不可触摸。 |
| 日历页 | 月/日/年切换；定时和全天跨日事件；任务计划/截止同日合并；一次性/年度纪念日、来源年份、周年数和 2 月 29 日；编辑/删除后回收站；提醒偏移和日期型 09:00。 |
| 任务页 | 未完成/已完成分组聚合；可展开清单创建、重命名和删除后任务保留；任务排序、移动、完成/恢复并保留在原清单；计划/截止提醒；搜索、Markdown 导入导出和长图。 |
| Android 规划投影 | Android 13+ 新安装确认加载/同步不会自动弹通知权限；在事件、任务或纪念日编辑器中从 0 个提醒变为至少 1 个并明确保存时应请求一次权限。授权后检查小组件和通知；完成任务后不再通知；修改/删除提醒后旧闹钟取消；重启、改日期/时间/时区后重新排程。非 Android 确认数据可保存但无系统通知承诺。 |
| FeaturePage | Dashboard 跳转、历史搜索、角色切换、笔记未保存确认。 |
| Roleplay | 情景创建、线程创建、导演/角色生成、玩家消息排队、附件、长图导出。 |
| ApiModelsPage | 添加/删除模型、拖拽排序、获取模型、清空高级参数、子模型能力开关。 |
| DataManagementPage | 普通无密钥 ZIP、密码加密含 API Key 备份、任务/清单和事件/纪念日的单项勾选与分区全选、canonical `tasks.json`/`calendar.json`、schema 5-8 旧 planning 备份转换、冲突导入、附件恢复。 |
| DataManagementPage 云端 | 按当前设备、后端和账号选择同步分类；默认全选业务数据但关闭静态资源。关闭不会删除云端已有数据，重新开启后通过 reseed 补齐。 |
| ThemePage | 预设色、HSV 拖动、深浅色切换、重启恢复。 |
## LAN Pairing And Sync

Settings includes a LAN page for discovery, showing a one-time QR code, mobile
camera scanning, desktop QR image import, trusted peer listing, manual sync,
revocation, conflict guidance, and explicit secret-transfer rules. Successful
pairing first lets the requester select a category proposal, lets the responder
accept its full set or a subset, and then asks whether to start the
first bidirectional exchange now or later. Trusted peers expose category controls:
reductions apply immediately, while additions require the discovered peer to
approve all or a subset. The page also shows and edits the stable local device
name and provides keep-local/use-peer actions for durable LAN conflicts. Windows users are reminded to allow LynAI through the private-network
firewall prompt.
# 知识库

功能仪表盘中的“知识库”页面提供知识库、标注类别和条目管理。知识库、类别和条目都支持自定义拖拽顺序；条目还可按最近更新、创建时间或标题排序，只有未搜索、未按类别过滤且使用自定义顺序时允许拖拽，避免把过滤结果或派生排序误写为持久顺序。搜索同时匹配标题和正文，标题命中优先并高亮关键词；列表显示类别颜色和正文摘要。

条目编辑器支持 Markdown/LaTeX 编辑与预览切换。详情页展示正文、解释和来源的更新时间；解释可编辑标题和 Markdown 正文、删除，或使用条目标题、正文、所属类别及现有来源元数据重新生成并保存。同一条目生成期间会禁用重复请求，请求返回前若条目或来源关键输入已变化则丢弃旧结果。未分类条目或类别/知识库停用时会明确拒绝重新生成。来源即使为空也保留新增入口，可编辑标题、URL 和备注并删除；URL 只接受和打开 `http`/`https`，详情显示可简化为域名，但复制时保留完整 URL。

类别可配置 alias、自动标注规则、解释提示词和颜色；页面不提供默认知识库、默认类别或“设为默认”操作。固定内置的专有名词知识库和类别显示“内置”，可编辑、启停并独立恢复模板，但不显示删除操作。条目点击仍切换右侧或紧凑详情，不通过 Card elevation、背景色或 `ListTile.selected` 显示选中状态。

## 随记

文件：`lib/pages/features/jottings_page.dart`、`lib/pages/features/jotting_detail_page.dart`、`lib/pages/features/jotting_editor_page.dart`

功能总览新增“随记”入口，`FeaturePage` 以 `lastFeature == 'jottings'` 进入时间线页。时间线页不提供 AppBar 加号或 FAB，创建入口是顶部常驻“记下此刻的想法……”输入条；时间线按日期分组（今天/昨天/日期），保留关键词/正则（`FeatureSearchMatcher`）、标签和日期范围过滤，并在有筛选时提供“清除”。卡片直接渲染 `MarkdownWithLatex` 正文，长内容可展开/收起，标签和时间为元信息；点按进入只读详情页，长按唤起编辑/复制/删除操作。

编辑统一使用全屏 `JottingEditorPage` Route，不替换 `FeaturePage` 的 body：新建与编辑共用该页面，顶部提供“完成”，底部为 Markdown 快捷工具栏（粗体、斜体、标题、列表、任务、引用、行内代码、链接、LaTeX）和标签入口；编辑/预览切换不会丢失光标或正文。保存等待 `JottingProvider` 持久化成功后 pop 并返回时间线，失败时留在编辑器并保留输入。取消/返回根据脏状态确认，无修改时直接返回。阅读态 `JottingDetail` 不再包含编辑器，只在顶部保留一个编辑入口。
