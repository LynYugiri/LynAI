# 页面与使用路径

这份文档从用户视角解释每个页面做什么，再指出维护时应该看的文件。

## 页面地图

```text
HomePage
├── 功能
│   ├── 对话历史
│   ├── 日程表
│   ├── 笔记
│   └── 待办清单
├── 对话
└── 设置
    ├── 关于
    ├── 背景
    ├── API
    ├── 主题
    └── 数据管理
```

项目使用命令式 `Navigator.push(MaterialPageRoute)` 打开设置子页和编辑页。主 Tab 由 `HomePage` 的 `IndexedStack` 保持状态。

## HomePage

文件：`lib/pages/home_page.dart`

`HomePage` 是根页面，默认进入对话 Tab。它还负责协调返回键：如果对话页正在选择消息、功能页打开了笔记详情或当前不在对话 Tab，返回键会先处理这些局部状态，而不是直接退出应用。

| 行为 | 说明 |
|------|------|
| Tab 保活 | `IndexedStack` 保留功能、对话、设置三个 Tab 的状态。 |
| 历史跳转 | 功能页点历史对话后切到对话 Tab，并传入对话 ID。 |
| 角色切换 | 从历史页切换角色后进入对话页，并刷新角色上下文。 |
| 背景图 | 读取 `AppSettings.backgroundImagePath`，叠加图片、模糊和半透明遮罩。 |

## ChatPage

文件：`lib/pages/chat_page.dart`

`ChatPage` 是应用最复杂的页面。它不只负责一个输入框，还要协调模型选择、附件、语音、文件识别、OCR、工具调用、流式响应、失败恢复和分享。

### 输入区

| 控件 | 作用 |
|------|------|
| 模型选择 | 选择当前 Chat 子模型。 |
| 对话设置 | 选择系统提示词、语音模型、OCR 模型、文件识别模型和文件识别 prompt。 |
| thinking 开关 | 控制当前请求的思考能力。 |
| OCR 开关 | 控制图片是否先走 OCR。 |
| 文件识别开关 | 控制非图片文件是否先由 Chat 模型读取。 |
| 附件按钮 | 选择文件、多图、拍照或读取桌面剪贴板图片。 |
| 语音按钮 | 系统语音识别或模型语音转写。 |

桌面端 `Enter` 发送，`Shift + Enter` 换行。移动端回车默认换行，点击发送按钮发送。

### 消息区

消息使用 `MarkdownWithLatex` 渲染，支持 Markdown、代码高亮、LaTeX、代码块复制、公式块复制和单块图片导出。assistant 消息可显示折叠的 thinking 内容。

### 重试与分支

| 功能 | 说明 |
|------|------|
| 重试 assistant 回复 | 保留旧回复，重新请求模型。 |
| 回复版本切换 | 在多个重试结果之间切换正文、附件和思考内容。 |
| 编辑用户消息后重发 | 从当前上下文创建新分支。 |
| 从历史消息继续 | 截取历史上下文并创建新对话。 |

### 分享

对话页可以进入多选模式，把选中的消息渲染成长图。桌面端优先写入剪贴板，移动端使用系统分享或保存图库。

## FeaturePage

文件：`lib/pages/feature_page.dart` 和 `lib/pages/features/*.dart`

功能页是一个 shell，当前子功能保存在 `AppSettings.lastFeature`。

| 子功能 | 文件 | 用户能做什么 |
|--------|------|--------------|
| 对话历史 | `features/feature_shell.dart` | 搜索历史、按角色分组、删除对话、跳转对话、切换角色。 |
| 日程表 | `features/schedule_page.dart` | 查看月/周/年视图，创建跨天日程或任务类日程。 |
| 笔记 | `features/notes_page.dart`, `features/note_detail_page.dart` | 文件夹、Markdown/LaTeX 编辑、修订时间线、导入导出。 |
| 待办清单 | `features/todo_lists_page.dart` | 多清单、任务勾选、排序、Markdown 导入导出、长图分享。 |

### 对话历史

历史页读取 `ConversationProvider.conversations`，按当前角色和其他角色分组。搜索会匹配标题和消息正文，并高亮命中片段。

### 日程表

日程读取 `FeatureProvider.schedules`。月视图适合查日期，周视图适合看时间段，年视图适合快速定位月份。Android 日程变化后会刷新小组件和通知。

### 笔记

笔记支持编辑和预览切换。保存会写入修订时间线；从历史版本打开后，如果内容没有变化，不会创建空修订。离开未保存笔记时会要求确认，避免切换页面时丢失编辑内容。

### 待办清单

待办支持清单排序和清单内任务排序。导出会保存 Markdown 文件，长图导出按平台写剪贴板、保存图库或调用分享。

## SettingsPage

文件：`lib/pages/settings_page.dart`

设置页本身只是入口卡片，具体配置由子页面承担。

| 页面 | 文件 | 说明 |
|------|------|------|
| 关于 | `about_page.dart` | 应用版本、项目链接、许可证。 |
| 背景 | `background_page.dart` | 背景图、清除背景、模糊开关和强度。 |
| API | `api_models_page.dart` | 模型配置分类、编辑、排序和模型拉取。 |
| 主题 | `theme_page.dart` | 预设色、HSV 调色板、浅色/深色/跟随系统。 |
| 数据管理 | `data_management_page.dart` | 备份导出、备份预览、导入和冲突处理。 |

## ApiModelsPage

文件：`lib/pages/api_models_page.dart`

模型配置按用途分类：Chat、OCR、语音转文字、图片生成。Chat 配置可以有多个子模型，每个子模型都可以单独设置启用状态、视觉能力、思考能力、工具能力和采样参数。

高级参数 `maxTokens`、`temperature`、`topP` 支持显式清空。实现上通过 sentinel 区分“不更新”和“清空为 null”。

## DataManagementPage

文件：`lib/pages/data_management_page.dart`

数据管理页通过 `BackupService` 处理 ZIP 备份。

| 步骤 | 说明 |
|------|------|
| 选择导出内容 | 可选择设置、对话、笔记、日程、待办；设置可细分 API 配置、外观、对话设置、角色与提示词。 |
| 导出文件 | 保存 `lynai-日期.zip` 到用户选择的位置。 |
| 读取备份 | 选择 ZIP 后解析 manifest 和分区 JSON。 |
| 预览 | 显示分区数量、警告和冲突。 |
| 导入 | 选择模式和冲突动作后写入 Provider。 |

如果选择导出 API 配置，备份会包含 API Key。这个文件应该按敏感文件保存。

## MathLive 公式编辑页

文件：`lib/pages/mathlive_formula_editor_page.dart`

可视化公式编辑器使用本地 `assets/mathlive/editor.html`。不支持 WebView 的平台会回退源码模式。WebView 回调可能晚于页面生命周期，因此回调入口必须检查 `mounted`。

## 手测建议

| 页面 | 重点路径 |
|------|----------|
| ChatPage | 普通发送、停止、失败重试、编辑重发、附件重试、语音快速松手、工具调用。 |
| FeaturePage | 历史搜索、角色切换、跨天日程、笔记未保存确认、待办导入导出。 |
| ApiModelsPage | 添加/删除模型、拖拽排序、获取模型、清空高级参数、子模型能力开关。 |
| DataManagementPage | 含 API Key 备份、旧备份读取、冲突导入、附件恢复、取消文件选择。 |
| ThemePage | 预设色、HSV 拖动、深浅色切换、重启恢复。 |
