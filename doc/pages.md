# 页面与路由

项目使用命令式 `Navigator.push(MaterialPageRoute)`。主界面由 `HomePage` 的底部导航组织，设置和详情页通过 push 进入。

```text
main.dart
  └── HomePage (IndexedStack + BottomNavigationBar)
        ├── Tab 0: FeaturePage
        │     ├── HistoryList
        │     ├── SchedulePage
        │     ├── NotesPage / NoteDetailPage
        │     └── TodoListsPage
        ├── Tab 1: ChatPage
        │     ├── HistoryDrawer
        │     ├── DialogSettingsContent
        │     ├── PromptRoleDialogs
        │     └── ShareConversationImage
        └── Tab 2: SettingsPage
              ├── AboutPage
              ├── BackgroundPage
              ├── ApiModelsPage
              ├── ThemePage
              └── DataManagementPage
```

## HomePage

文件：`lib/pages/home_page.dart`

`HomePage` 是根导航页，默认打开对话 Tab。

| 职责 | 说明 |
|------|------|
| Tab 管理 | 使用 `IndexedStack` 保留功能、对话、设置三个 Tab 的状态 |
| 历史跳转 | 功能页点击对话历史后切到对话 Tab，并传入目标对话 ID |
| 角色切换 | 功能页切换角色后跳到对话 Tab，并递增 `roleChangeSerial` 触发新上下文 |
| 返回键 | 优先交给对话页或功能页处理；非对话 Tab 返回时回到对话 Tab |
| 背景图 | 读取 `AppSettings.backgroundImagePath`，使用 `Stack` 叠加图片、模糊和半透明遮罩 |

背景图片存在性检查结果缓存在状态中，避免每次 build 都同步访问文件系统。

## ChatPage

文件：`lib/pages/chat_page.dart`

`ChatPage` 是聊天运行时的中心，负责把 UI 操作转成模型请求，把流式结果写回 Provider。

### 输入与发送

| 平台 | 行为 |
|------|------|
| 桌面端 | `Enter` 发送，`Shift + Enter` 换行 |
| 移动端 | 回车换行，发送按钮发送 |

底部栏包含模型选择、对话设置、思考开关、OCR 开关、文件识别开关、附件入口、语音/发送按钮。对话设置面板可选择系统提示词、语音模型、OCR 模型、文件识别模型和文件识别提示词。

### 消息渲染

消息使用 `MarkdownWithLatex` 渲染，支持 Markdown、代码高亮、LaTeX、代码块/公式块复制和单块图片导出。assistant 消息可显示可折叠思考过程。最后一条回复如果启用思考但接口没有返回 visible reasoning，会显示说明提示。

### 异步链路

| 操作 | 风险 | 防护 |
|------|------|------|
| 文件/图片选择 | 系统 picker 返回前页面可能销毁 | `mounted` 检查 |
| 拍照 | 相机 Activity 返回晚于页面生命周期 | `mounted` 检查 |
| 剪贴板图片 | 二进制读取和写文件异步 | `mounted` 检查 |
| 录音 | 按下后启动尚未完成就松手 | 启动取消标记，停止并删除临时文件 |
| 流式请求 | 停止、异常、完成三条路径都要收尾 | 取消订阅、保存最后状态、重置 `_streaming` |
| MathLive 回调 | WebView 回调晚于页面关闭 | 回调入口检查 `mounted` |

### 附件

附件来源包括文件选择、多图选择、拍照、桌面剪贴板。附件会复制到应用私有目录，并保存在 `Message.images` 中。带附件消息重试、编辑后重发和历史重试版本切换都会复用原附件。

### 重试和分支

| 功能 | 说明 |
|------|------|
| 重试 assistant 回复 | 保留旧回复到重试历史，重新请求模型 |
| 多版本导航 | `<` / `>` 在重试版本之间切换，同时切换文本、附件和思考内容 |
| 编辑用户消息后重发 | 在当前重试链创建新分支 |
| 从历史消息开始新对话 | 截取历史上下文并创建新分支，附件随原用户消息保留 |

### 长图分享

对话页可进入选择模式，选择多条消息后用 `ScreenshotController.captureFromLongWidget()` 生成长图。桌面端优先写入剪贴板，移动端调用系统分享或保存图库。

## FeaturePage

文件：`lib/pages/feature_page.dart` 和 `lib/pages/features/*.dart`

功能页由 `AppSettings.lastFeature` 决定当前子功能。

| 值 | 子功能 | 说明 |
|----|--------|------|
| `history` | 对话历史 | 按角色分组搜索历史、删除、跳转、切换角色 |
| `schedule` | 日程表 | 月视图、周时间轴、全年总览，支持任务类日程和跨天日程 |
| `notes` | 笔记 | 文件夹、Markdown/LaTeX 编辑、预览、修订、导入导出 |
| `todos` | 待办清单 | 多清单、勾选、拖拽排序、搜索、导入导出、长图分享 |

### 对话历史

历史列表读取 `ConversationProvider.conversations`，按当前角色和其他角色分组。搜索支持标题和内容匹配，高亮命中片段。点击其他角色分组中的对话会先切换角色，再进入对话页。

### 日程表

日程读取 `FeatureProvider.schedules`。月视图显示日期摘要，周视图显示连续时间轴，年视图按月份聚合。跨天日程按覆盖日期区间显示。移动端支持双指缩放，桌面端支持 Ctrl/Command + 滚轮缩放。

Android 端日程变更后会刷新日程小组件并重新安排通知。

### 笔记

笔记读取 `FeatureProvider.notes`、`noteFolders` 和 `noteRevisions`。支持创建文件夹、导入 Markdown、导出 Markdown、导出长图、自动保存、查看修订时间线和按修订还原内容。预览复用 `MarkdownWithLatex`，代码块和块级公式支持复制与单图导出。

### 待办清单

待办读取 `FeatureProvider.todoLists`。清单和清单内任务均可排序，任务可勾选、编辑、删除。支持从 Markdown 任务列表导入，导出为 Markdown 或长图。搜索会匹配清单标题和任务文本。

## SettingsPage

文件：`lib/pages/settings_page.dart`

设置页提供入口卡片，具体配置由子页面处理。

| 页面 | 文件 | 说明 |
|------|------|------|
| About | `about_page.dart` | 应用版本、项目与许可证信息 |
| Background | `background_page.dart` | 背景图、清除背景、模糊开关和强度 |
| API | `api_models_page.dart` | 模型分类入口和模型配置编辑 |
| Theme | `theme_page.dart` | 预设色、HSV 调色板、主题模式 |
| Data Management | `data_management_page.dart` | 备份导出、备份预览、分区导入和冲突处理 |

## ApiModelsPage

文件：`lib/pages/api_models_page.dart`

### 分类

| 分类 | 用途 |
|------|------|
| Chat | 对话、文件识别、多模态、工具调用 |
| OCR | vivo OCR |
| 语音转文字 | vivo 长语音转写 |
| 图片生成 | OpenAI Images 或 vivo 图片生成 |

### EditModelPage

编辑页包含提供商名称、API 类型、Endpoint、API Key/AppKey、AppID、模型名、多子模型列表和高级参数。Chat 配置可以从 Endpoint 拉取模型列表，Ollama 拉取时会清理 `:latest` 后缀。每个子模型可设置启用状态、视觉/思考/工具能力和采样参数。

清空 Max Tokens、Temperature 或 Top P 会真正传入 `null`，由 `ModelConfig.copyWith()` 的 sentinel 语义清除旧值。

## DataManagementPage

文件：`lib/pages/data_management_page.dart`

数据管理页通过 `BackupService` 实现 ZIP 备份。

| 步骤 | 说明 |
|------|------|
| 导出选择 | 可选择设置、对话、笔记、日程、待办；设置可细分 API 配置、外观、对话设置、角色与提示词 |
| 导出文件 | 生成 `lynai-YYYYMMDD-HHMMSS.zip`，包含 manifest、分区 JSON 和私有附件 |
| 读取预览 | 解析 ZIP，显示分区数量、警告和冲突 |
| 导入计划 | 选择合并、只添加或替换分区，并为冲突选择动作 |
| 执行导入 | 恢复附件、写入 Provider、修复模型引用、显示统计 |

选择导出 API 配置时会包含 API Key，页面文案和文档都应提醒用户按敏感文件保存。

## ThemePage

文件：`lib/pages/theme_page.dart`

主题页提供 36 种预设颜色和 HSV 调色板。`baseThemeColor` 记录用户选择的基础色，`themeColor` 是最终用于 `ColorScheme.fromSeed` 的色值。支持浅色、深色、跟随系统三种模式。

## MathLive 公式编辑页

文件：`lib/pages/mathlive_formula_editor_page.dart`

通过本地 `assets/mathlive/editor.html` 提供可视化公式编辑器。不支持 WebView 的平台回退源码模式。WebView 使用 `MathLiveBridge` channel 发送 ready、input、keyboard-visibility 和 error 事件，回调入口必须检查 `mounted`。

## 页面手测矩阵

| 页面 | 重点 |
|------|------|
| `ChatPage` | 发送、停止、失败重试、编辑重发、附件重试、语音快速松手、工具调用 |
| `FeaturePage` | 历史搜索、角色切换、跨天日程、笔记修订、待办导入导出 |
| `ApiModelsPage` | 添加/删除模型、拖拽排序、获取模型、清空高级参数、子模型能力开关 |
| `DataManagementPage` | 含 API Key 备份、旧备份读取、冲突导入、附件恢复、取消文件选择 |
| `ThemePage` | 预设色、HSV 拖动、深浅色切换、重启恢复 |
| `MathLiveFormulaEditorPage` | 快速进入退出、源码模式、WebView 慢加载回调 |
