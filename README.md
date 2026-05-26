# LynAI

LynAI 是一个基于 Flutter 的跨平台 AI 对话与本地生产力客户端。它把多模型对话、Markdown/LaTeX 渲染、文件与图片理解、语音输入、本地工具调用、日程、笔记、待办和备份恢复放在同一个本地优先的应用中。当前版本：`v2.2.10`。

## 截图

| 设置 | 对话 |
|------|------|
| ![设置](./images/demo/1.png) | ![对话](./images/demo/2.png) |

## 功能总览

| 模块 | 能力 |
|------|------|
| AI 对话 | OpenAI 兼容接口、Ollama、Anthropic；流式回复；停止生成；失败重试；编辑后重发；多版本重试历史 |
| 模型管理 | Chat、OCR、语音转文字、图片生成四类配置；Endpoint 预设；模型拉取；多子模型；视觉/思考/工具能力开关；子模型级采样参数 |
| Markdown/LaTeX | Markdown、代码高亮、Hurmit Nerd Font、内联/块级 LaTeX、代码块和公式块复制或单独导出图片 |
| 附件输入 | 文件、多图、拍照、桌面剪贴板图片；附件复制到应用私有目录并随历史消息恢复 |
| 图片与文件理解 | 图片可走 vivo OCR；PDF、文本、表格、Office、压缩包等可由 Chat 模型识别或作为多模态附件直传/退化为文本上下文 |
| 语音输入 | 无接口时使用系统语音识别；配置语音模型后录音并调用 vivo 长语音转写 |
| 本地工具 | 时间、位置、打开 Android 应用、查询/创建/修改日程、查询/读取/保存笔记 |
| 功能页 | 按角色管理对话历史；日程月/周/年视图；Markdown 笔记；待办清单；搜索、导入、导出、长图分享 |
| 角色与提示词 | 多角色、系统提示词模板、角色默认模型、角色主题色；历史对话保留设置快照 |
| 外观 | Material 3、36 种预设色、HSV 调色板、浅色/深色/跟随系统、全局背景图和毛玻璃 |
| 数据管理 | ZIP 备份导出/读取预览/按分区导入/冲突处理；支持对话、设置、模型、日程、笔记、待办和私有附件恢复 |

## 支持平台

| 平台 | 状态 | 说明 |
|------|------|------|
| Android | 支持 | 额外包含定位、打开应用、图库保存、日程小组件/通知等原生能力 |
| iOS | 支持 | 依赖 Flutter 与插件能力，分享/相册/录音需系统权限 |
| Linux | 支持 | 长图、代码块和公式块图片可写入剪贴板 |
| macOS | 支持 | CI 同时构建 x64 与 arm64 包 |
| Windows | 支持 | CI 构建 x64 zip 包 |
| Web | 可构建 | 文件、剪贴板、本地工具和平台能力受浏览器限制 |

## 快速开始

环境要求：Flutter stable，项目 Dart SDK 约束为 `^3.11.5`。

```bash
git clone https://github.com/lynyugiri/lynai.git
cd lynai
flutter pub get
flutter run
```

常用验证命令：

```bash
flutter analyze
flutter test
```

常用构建命令：

```bash
flutter build apk --split-per-abi
flutter build linux
flutter build windows
flutter build macos
flutter build ios
flutter build web
```

## 首次配置

进入 `设置 -> API` 添加模型配置。Chat 配置可使用 OpenAI、DeepSeek、Anthropic、Google AI、Ollama、OpenRouter、Groq、Together AI、xAI、Moonshot、vivo、智谱、通义千问、SiliconFlow 等预设，也可填写自定义 OpenAI 兼容 Endpoint。

| 类别 | 用途 | 关键字段 |
|------|------|----------|
| Chat | 对话、文件识别、多模态输入、本地工具调用 | Provider 名称、API 类型、Endpoint、API Key、模型列表、能力开关、高级参数 |
| OCR | 图片文字提取 | vivo OCR Endpoint、AppID、AppKey |
| Speech | 录音转文字 | vivo 长语音转写 Endpoint、AppID、AppKey、engineid |
| Image Generation | 图片生成 | OpenAI Images 或 vivo 图片生成 Endpoint、API Key、模型名 |

Chat 提供商下可以维护多个 `ModelEntry`。只有启用的子模型会出现在对话模型选择器中；当前激活子模型的 `maxTokens`、`temperature`、`topP` 优先于提供商级参数。

## 对话链路

1. 用户输入文本，并可附加文件、图片、相机照片或剪贴板图片。
2. `ChatPage` 根据当前角色、当前对话快照和全局设置选择 Chat、OCR、语音和文件识别模型。
3. 图片在 OCR 开启时先提取文字；非图片文件在文件识别开启时先由选中的 Chat 模型读取。
4. 附件未启用预处理时，会按接口能力直传为多模态内容，或退化为文件名、大小、MIME、base64/文本上下文。
5. `ApiService.sendStreamRequest()` 发起流式请求，把正文 chunk、reasoning chunk 和最终 tool calls 分开返回。
6. `ConversationProvider.updateLastMessage(save: false)` 实时刷新 UI，流结束或失败后再落盘。
7. 如果模型返回工具调用，`ToolCallService` 执行本地工具，再把结果回传模型生成最终自然语言回复。

重试、编辑后重发和从历史消息创建分支都会保留原用户消息附件，并重新构建 OCR/文件识别上下文。

## 本地工具

OpenAI 兼容模型在 `supportsTools=true` 且未禁用工具时使用原生 `tools`；不支持原生工具的接口可通过 JSON fallback 调用。启用工具时，系统上下文会注入当前本地时间、时区和 `timezoneOffsetMinutes`，日程时间统一转为本地时间保存与返回。

| 工具 | 说明 |
|------|------|
| `get_current_time` | 返回设备当前时间、时区、ISO 时间戳和偏移 |
| `get_location` | Android 请求定位权限后读取最近位置 |
| `open_app` | Android 按包名打开已安装应用 |
| `list_schedules` | 查询本地日程，可按时间区间过滤 |
| `create_schedule` | 创建本地日程 |
| `update_schedule` | 修改本地日程 |
| `list_notes` | 查询笔记，可按关键字搜索 |
| `read_note` | 读取单篇笔记完整内容 |
| `save_note` | 创建、覆盖或追加笔记内容 |

## 功能页

底部导航包含 `功能 / 对话 / 设置` 三个主 Tab，`HomePage` 使用 `IndexedStack` 保持页面状态。

| 功能 | 说明 |
|------|------|
| 对话历史 | 按当前角色和其他角色分组，支持标题/内容搜索、关键词高亮、删除、跳转和角色切换 |
| 日程表 | 月视图、周时间轴、全年总览；支持跨天日程、任务类日程、本地时区显示、Android 小组件/通知刷新 |
| 笔记 | Markdown/LaTeX 编辑与预览、文件夹、自动保存、修订时间线、导入 Markdown、导出 Markdown/长图 |
| 待办清单 | 多清单、任务勾选、拖拽排序、搜索、Markdown 任务列表导入导出、长图分享 |

## 数据与备份

应用主要使用 `SharedPreferences` 保存 JSON 数据。对话附件、背景图等文件类资源只保存路径；对话附件会先复制到应用私有目录，避免引用系统临时文件。

| 数据 | Provider/Service | 存储键或文件 |
|------|------------------|--------------|
| 对话历史 | `ConversationProvider` | `conversations` |
| 模型配置 | `ModelConfigProvider` | `model_configs` |
| 应用设置 | `SettingsProvider` | `app_settings` |
| 日程 | `FeatureProvider` | `schedule_items` |
| 笔记 | `FeatureProvider` | `notes`, `note_folders`, `note_revisions`, `note_edit_proposals` |
| 待办 | `FeatureProvider` | `todo_lists` |
| 备份 | `BackupService` | ZIP：`manifest.json` + 分区 JSON + 私有附件 assets |

备份导出可按分区选择数据，也可细分设置中的 API 配置、外观、对话设置、角色与提示词。导出 API 配置会包含 API Key，备份文件应按敏感文件处理。

## 技术栈

| 类别 | 技术 |
|------|------|
| 框架 | Flutter / Dart |
| 状态管理 | Provider + ChangeNotifier |
| 持久化 | SharedPreferences(JSON) + 应用私有文件目录 |
| HTTP | http |
| Markdown | flutter_markdown_plus + markdown |
| LaTeX | flutter_math_fork，另有 MathLive WebView 公式编辑页 |
| 代码高亮 | highlight |
| 语音 | speech_to_text, record |
| 文件/图片 | file_picker, image_picker, path_provider |
| 截图与分享 | screenshot, share_plus, super_clipboard |
| 备份 | archive ZIP |
| 应用信息 | package_info_plus |
| WebView | webview_all |

## 项目结构

```text
lib/
├── main.dart                  # Provider 注册、持久化加载、主题和启动页
├── models/                    # JSON 模型：对话、消息、配置、设置、笔记、日程、待办、备份
├── providers/                 # ChangeNotifier 状态和 SharedPreferences 持久化
├── services/                  # API、工具调用、备份导入导出
├── pages/                     # 主页面、设置页、功能页、对话页和子功能实现
├── utils/                     # 文件名、分享、SnackBar 等工具
└── widgets/                   # Markdown/LaTeX 渲染组件
```

## CI/CD

GitHub Actions 工作流位于 `.github/workflows/build.yml`。

| 触发 | 行为 |
|------|------|
| push 到 `main`/`master` | 构建 Android、Linux、Windows、macOS、Web，并更新 `nightly` 预发布 |
| pull request 到 `main`/`master` | 构建验证 |
| tag `v*` | 构建并创建正式 Release |

Release 产物命名为 `LynAI_<platform>_<version>_<short_sha>_<arch-or-target>.<ext>`，例如 `LynAI_android_2.2.10_abcdef0_arm64-v8a.apk`、`LynAI_web_2.2.10_abcdef0_universal.zip`。

## 文档

- [文档首页](doc/README.md)
- [架构概览](doc/architecture.md)
- [页面与路由](doc/pages.md)
- [数据模型](doc/models.md)
- [状态管理](doc/providers.md)
- [API 服务与工具调用](doc/services.md)

## 许可证

[GNU General Public License v3.0](LICENSE)
