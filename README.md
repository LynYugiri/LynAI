# LynAI

LynAI 是一个跨平台 AI 对话客户端，基于 Flutter 开发，支持 OpenAI 兼容接口、Ollama、Anthropic 以及 vivo OCR/长语音转写/图片生成等能力。当前版本：`2.2.2`。

## 截图

| 设置 | 对话 |
|------|------|
| ![设置](./images/demo/1.png) | ![对话](./images/demo/2.png) |

## 核心能力

- **跨平台客户端**：支持 Android、iOS、Linux、macOS、Windows 和 Web 构建。
- **多模型配置**：Chat、OCR、语音转文字、图片生成四类配置独立管理，支持拖拽排序和多子模型启用。
- **多接口协议**：支持 OpenAI 兼容 `/chat/completions`、Ollama `/api/chat`、Anthropic `/messages`，并可通过自定义 Endpoint 接入兼容服务。
- **流式对话**：SSE 或逐行 JSON 实时渲染回复，支持停止生成、重试、编辑后重发和重试版本切换。
- **Markdown 与 LaTeX**：消息和笔记支持 Markdown、Hurmit Nerd Font 代码字体、One Dark Pro 风格多语言代码高亮、内联公式 `$...$`、块级公式 `$$...$$`、`\(...\)`、`\[...\]`，代码块和公式块可复制或单独导出图片。
- **思考过程展示**：支持解析 DeepSeek `reasoning_content`、常见 `reasoning`/`thinking` 字段、Ollama `<think>`、Anthropic thinking delta，并随消息持久化恢复；如果模型或 API 不暴露可见 reasoning，会在消息上明确提示。
- **图片输入**：支持一次选择多张图片和桌面端剪贴板粘贴；图片会复制到应用私有目录，避免历史消息引用临时文件失效。
- **图片理解**：可使用多模态 Chat 模型识图，也可配置 OCR 提取图片文字作为上下文。
- **语音输入**：未配置接口时使用系统语音识别；配置语音模型后使用录音文件调用 vivo 长语音转写。
- **本地工具调用**：模型可调用本地工具获取时间、位置、打开 Android 应用、管理日程和笔记；日程工具统一使用本地时区；不支持原生 tool_calls 的接口可走 JSON fallback。
- **长图分享**：可选择多条对话生成长图，保留 Markdown/LaTeX 排版，桌面端可复制到剪贴板，移动端可分享或保存。
- **功能页**：包含对话历史、日程表和 Markdown 笔记，支持历史搜索、角色分组、日程月/周/年视图、笔记导入导出。
- **角色与提示词**：可为不同角色保存系统提示词、默认模型和主题色，新对话继承当前角色，历史对话保留设置快照。
- **外观定制**：支持 36 种预设主题色、HSV 调色板、浅色/深色/跟随系统，以及图片背景和毛玻璃效果。

## 支持平台

| 平台 | 状态 | 说明 |
|------|------|------|
| Android | 支持 | 额外包含位置、打开应用、保存长图到图库等原生能力 |
| iOS | 支持 | 依赖 Flutter 与插件能力 |
| Linux | 支持 | 桌面端长图可写入系统剪贴板 |
| macOS | 支持 | 桌面端长图可写入系统剪贴板 |
| Windows | 支持 | 桌面端长图可写入系统剪贴板 |
| Web | 可构建 | 部分本地文件、剪贴板和平台工具能力受浏览器限制 |

## 快速开始

环境要求：Flutter SDK `^3.11.5`，Dart SDK 由 Flutter 管理。

```bash
git clone https://github.com/lynyugiri/lynai.git
cd lynai
flutter pub get
flutter run
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

开发验证：

```bash
flutter analyze
flutter test
```

## 首次配置

进入 `设置 -> API`，按类别添加模型或能力配置。

| 类别 | 用途 | 主要字段 |
|------|------|----------|
| Chat | 普通对话、流式回复、多模态图片识别、本地工具调用 | Provider 名称、API 类型、Endpoint、API Key、模型列表 |
| OCR | 图片文字提取 | vivo OCR Endpoint、AppID、AppKey |
| 语音转文字 | 录音文件转写 | vivo 长语音转写 Endpoint、AppID、AppKey、engineid |
| 图片生成 | 文生图或图生图接口 | OpenAI Images 或 vivo 图片生成 Endpoint、API Key、模型名 |

Chat 配置支持 Endpoint 预设，包括 OpenAI、DeepSeek、Anthropic、Google AI、Ollama、OpenRouter、Groq、Together AI、xAI、Moonshot、vivo、智谱、通义千问、SiliconFlow 和自定义接口。

## 使用说明

### 对话

- 桌面端 `Enter` 发送，`Shift + Enter` 换行；移动端回车默认换行。
- 点击底部模型按钮可切换当前对话使用的 Chat 模型。
- 对话设置面板可切换系统提示词、语音模型、OCR 模型、图片识别模型和图片识别提示词。
- 每个对话保存自己的 `ConversationSettings` 快照，切换历史对话时会恢复当时的模型和辅助能力设置。
- 开启图片识别后，发送图片会先调用多模态 Chat 模型识图，再把结果追加给当前对话模型。
- 未开启图片识别但配置了 OCR 时，会先提取图片文字；未配置识别能力时，仅把图片文件名和大小作为上下文。
- 带图片消息重试或编辑后重发时，会复用原消息的图片附件并重新构建图片识别上下文；重试历史切换也会同步恢复对应图片。

### 本地工具

LynAI 在 Chat 模型支持 tool calls 时会传入工具定义；如果接口不支持原生工具调用，系统提示词会要求模型返回 JSON fallback。

工具调用时会把当前设备本地时间、时区名和 `timezoneOffsetMinutes` 注入系统上下文。日程工具解析 ISO-8601 时间后统一转成本地时间保存和返回，避免 `Z` 或带偏移时间在 UI 中错位。模型在工具调用前后返回的思考内容会累积展示在最终回复上。

| 工具 | 说明 |
|------|------|
| `get_current_time` | 获取设备当前时间、时区和 ISO 时间戳 |
| `get_location` | 获取设备最近位置，Android 会请求定位权限 |
| `open_app` | Android 端按包名打开已安装应用 |
| `list_schedules` | 查询本地日程，可按时间范围过滤 |
| `create_schedule` | 创建本地日程 |
| `update_schedule` | 修改本地日程 |
| `list_notes` | 查询本地笔记，可按关键字搜索 |
| `read_note` | 读取单篇笔记完整内容 |
| `save_note` | 创建、覆盖或追加笔记内容 |

### 功能页

底部导航的 `功能` 页由 `lib/pages/feature_page.dart` 实现。

| 功能 | 说明 |
|------|------|
| 对话历史 | 按角色分组展示历史对话，支持标题/内容搜索、关键词高亮、删除和快速跳转 |
| 日程表 | 支持月视图、周时间轴、全年总览，可新增、编辑、删除日程和备注；跨天日程会按日期范围显示 |
| 笔记 | 支持 Markdown/LaTeX 编辑、自动保存、导入 Markdown、导出 Markdown 和导出图片 |

### 长图分享与导出

- 对话页可进入选择模式，选择多条消息后生成分享长图。
- 笔记页可将 Markdown 笔记导出为 `.md` 文件或长图。
- Markdown 中的代码块和块级公式带有标题栏，可复制源码并单独导出 PNG；桌面端写入剪贴板，Android/iOS 保存到图库。
- 长图场景会让 Markdown 代码块自动换行，避免横向滚动内容被截图裁剪。
- 桌面端优先复制 PNG 到系统剪贴板，Android/iOS 保存到图库或调用系统分享。

## 数据存储

应用当前使用 `SharedPreferences` 保存 JSON 数据。

| 数据 | Provider | 存储键 |
|------|----------|--------|
| 对话历史 | `ConversationProvider` | `conversations` |
| 模型配置 | `ModelConfigProvider` | `model_configs` |
| 应用设置 | `SettingsProvider` | `app_settings` |
| 日程 | `FeatureProvider` | `schedule_items` |
| 笔记 | `FeatureProvider` | `notes` |

图片附件不会嵌入 JSON，而是复制到应用私有目录后保存路径和元数据。

## 技术栈

| 类别 | 技术 |
|------|------|
| 框架 | Flutter SDK ^3.11.5 |
| 状态管理 | Provider + ChangeNotifier |
| HTTP | http |
| 持久化 | SharedPreferences(JSON) |
| Markdown | flutter_markdown_plus |
| LaTeX | flutter_math_fork |
| Markdown AST | markdown |
| 代码高亮 | highlight |
| 语音识别 | speech_to_text |
| 录音 | record |
| 图片选择 | image_picker |
| 文件选择 | file_picker |
| 剪贴板 | super_clipboard |
| 分享 | share_plus |
| 截图 | screenshot |
| UI | Material 3, ColorScheme.fromSeed |

## 项目结构

```text
lib/
├── main.dart                  # 应用入口、Provider 注册、主题构建、启动页
├── app_version.dart           # 应用内展示版本号
├── models/                    # 不可变数据模型与 JSON 序列化
├── providers/                 # ChangeNotifier 状态与 SharedPreferences 持久化
├── services/                  # API 请求、本地工具调用适配
├── pages/                     # 页面、导航、功能实现
└── widgets/                   # Markdown/LaTeX 渲染组件
```

## CI/CD

GitHub Actions 工作流位于 `.github/workflows/build.yml`。

| Job | 产物 |
|-----|------|
| Android | split ABI APK |
| Linux | `.deb` 与 Arch `.pkg.tar.zst` |
| Windows | x64 zip |
| macOS | x64 与 arm64 zip |
| Web | 静态站点 zip |

Release 文件统一命名为 `LynAI_<platform>_<version>_<short_sha>_<arch-or-target>.<ext>`，例如 `LynAI_android_2.2.2_abcdef0_arm64-v8a.apk`、`LynAI_web_2.2.2_abcdef0_universal.zip`。

当前 release 产物命名：

| 平台 | 文件名格式 |
|------|------------|
| Android | `LynAI_android_<version>_<short_sha>_<abi>.apk` |
| Debian | `LynAI_debian_<version>_<short_sha>_amd64.deb` |
| Arch Linux | `LynAI_archlinux_<version>_<short_sha>_amd64.pkg.tar.zst` |
| Windows | `LynAI_windows_<version>_<short_sha>_x64.zip` |
| macOS | `LynAI_macos_<version>_<short_sha>_<x64|arm64>.zip` |
| Web | `LynAI_web_<version>_<short_sha>_universal.zip` |

推送到 `main` / `master` 会创建 `nightly` 预发布；推送 `v*` 标签会创建正式 Release。

## 项目文档

- [文档首页](doc/README.md)
- [架构概览](doc/architecture.md)
- [页面与路由](doc/pages.md)
- [数据模型](doc/models.md)
- [状态管理](doc/providers.md)
- [API 服务与工具调用](doc/services.md)

## 许可证

[GNU General Public License v3.0](LICENSE)
