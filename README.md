# LynAI

LynAI 是一个本地优先的跨平台 AI 客户端。它把多模型聊天、附件理解、Markdown/LaTeX 渲染、本地工具、笔记、日程、待办、插件系统、情景演绎和备份恢复放在同一个 Flutter 应用里。

项目的核心取向是：界面尽量简单，数据尽量留在本地，外部模型只接收用户明确发送的内容。

## 适合什么

| 场景 | 能力 |
|------|------|
| 多模型聊天 | OpenAI 兼容接口、Ollama、Anthropic，以及自定义 Endpoint。 |
| 带资料对话 | 图片、拍照、剪贴板图片、PDF、文本、表格、Office 文件和压缩包作为上下文。 |
| 长文本阅读 | Markdown、代码高亮、LaTeX、公式编辑、Mermaid 相关渲染能力。 |
| 本地个人管理 | 日程、笔记、待办清单、角色、提示词和模型配置。 |
| 模型使用本地工具 | 查询时间、定位、日程、笔记、待办，或在 Android 打开应用。 |
| 多角色创作 | 情景演绎支持导演、参与角色、玩家消息、演绎对话和长图导出。 |
| 插件扩展 | Lua/WebView 插件系统，支持自定义工具调用、函数导出和内嵌功能页。 |
| 数据管理 | ZIP 备份、分区导入、冲突处理、附件恢复和 storage_v2 升级。 |

## 截图

| 设置 | 对话 |
|------|------|
| ![设置](./images/demo/1.png) | ![对话](./images/demo/2.png) |

## 功能概览

| 模块 | 说明 |
|------|------|
| 对话 | 流式回复、停止生成、重试、编辑重发、回复版本切换、历史继续、长图分享。 |
| 模型管理 | 按 Chat、OCR、Speech、Image Generation 分类；Provider 下可配置多个子模型。 |
| 附件 | 用户选择的长期附件会复制到应用私有目录，避免系统临时文件被清理。 |
| 图片与文件理解 | 图片可走 OCR；文件可由 Chat 模型读取，也可按能力作为多模态或文本上下文发送。 |
| 语音输入 | 可使用系统语音识别，也可配置语音模型做录音转写。 |
| Markdown/LaTeX | Markdown、代码高亮、内联/块级公式、公式编辑、代码块和公式块复制/导出。 |
| 代码高亮 | Tree-sitter 原生结构化语法高亮（16 种语言），支持代码块点击编辑。 |
| 工具调用 | 模型可通过受控工具读取或修改本地日程、笔记和待办，也可调用插件注册的工具。 |
| 插件系统 | Lua 沙箱运行时 + WebView 功能页，支持安装、卸载、快照、代码编辑和权限管理。 |
| 功能页 | Dashboard、对话历史、日程、笔记、待办、情景演绎、插件特性页。 |
| 角色与提示词 | 聊天角色、角色分组、系统提示词模板、角色默认模型和主题色。 |
| 外观 | Material 3、主题色、浅色/深色/跟随系统、背景图和毛玻璃。 |
| 数据管理 | 备份导出、备份预览、分区导入、storage_v2 升级和私有资源恢复。 |

## 平台

Flutter 工程包含 Android、iOS、Linux、macOS、Windows 和 Web 目标。实际能力受插件、权限和平台通道支持影响。

| 平台 | 说明 |
|------|------|
| Android | 支持定位、打开应用、保存图库、日程小组件、通知、前台生成服务、系统长截图。 |
| Linux | 桌面端构建；图片分享优先走剪贴板或文件。 |
| Windows | 桌面端构建；依赖 Flutter Windows 能力。 |
| macOS | 桌面端构建；语音插件需要构建时兼容处理。 |
| iOS | 工程目标存在；能力取决于插件支持和系统权限。 |
| Web | 工程目标存在；浏览器沙箱会限制本地文件、平台通道和后台能力。 |

CI 工作流目前构建 Android、Linux、Windows 和 macOS 产物。

## 快速开始

环境要求以 `pubspec.yaml` 的 Dart SDK 约束和 Flutter stable 为准。

```bash
git clone https://github.com/lynyugiri/lynai.git
cd lynai
flutter pub get
flutter run
```

常用检查：

```bash
flutter analyze
flutter test
```

## 首次配置

进入 `设置 -> API` 添加模型配置。Chat 配置可以使用预设 Endpoint，也可以填写自定义 OpenAI 兼容接口。

| 分类 | 用途 | 关键字段 |
|------|------|----------|
| Chat | 对话、文件识别、多模态输入、工具调用、情景演绎。 | API 类型、Endpoint、API Key、子模型、能力开关、采样参数。 |
| OCR | 图片文字识别。 | OCR Endpoint 和鉴权信息。 |
| Speech | 录音转文字。 | 语音转写 Endpoint 和鉴权信息。 |
| Image Generation | 图片生成。 | 图片生成 Endpoint、API Key 和模型名。 |

一个 Chat Provider 可以包含多个子模型。只有启用的子模型会出现在选择器里；子模型的能力和采样参数优先于 Provider 级设置。

## 插件系统

LynAI 支持 Lua/WebView 插件扩展。每个插件通过 `plugin.json` 声明清单，通过 Lua 脚本注册工具调用和全局函数，通过 HTML/CSS/JS 构建功能页界面。

| 概念 | 说明 |
|------|------|
| 工具 (Tool) | 插件注册的工具可被 AI 模型调用，由 Lua handler 执行逻辑。 |
| 函数 (Function) | 插件注册的全局函数可在 UI 中触发，实现非 AI 调用的功能。 |
| 功能页 | 插件通过 WebView 提供内嵌 HTML 界面，可访问 LynAI 全局 API。 |
| 配置 Schema | 插件可提供 `config.schema.json` 描述配置表单，支持字段校验。 |
| 快照 | 插件源码可保存为快照，方便版本回溯和问题恢复。 |
| 内置插件 | status-dashboard（仪表盘）和 weather-query（天气查询）随应用发布。 |

## 数据与存储

LynAI 本地业务数据统一写入 storage_v2：结构化数据写入 Drift 数据库，笔记分页正文写入 Markdown 文件，资源文件写入应用私有 SHA blob 目录。

| 数据 | 主要负责人 |
|------|------------|
| 对话与附件 | `ConversationProvider`、`ConversationRepository`、`StorageV2Service` |
| 模型配置 | `ModelConfigProvider`、`ModelConfigRepository` |
| 应用设置、角色、提示词 | `SettingsProvider`、`SettingsRepository` |
| 日程、笔记、待办 | `FeatureProvider`、`FeatureRepository` |
| 情景演绎 | `RoleplayProvider`、`RoleplayRepository` |
| 插件 | `PluginProvider`、`PluginRepository`、`PluginLuaRuntimeService` |
| 备份导入导出 | `BackupService` |

附件不会嵌入对话 JSON。页面会先复制到应用私有 SHA blob 目录，再把资源 ID、展示名和 MIME 元数据保存到模型对象中。

## 项目结构

```text
lib/
├── main.dart                  # Provider 注册、启动加载、storage_v2 准备、主题构建
├── models/                    # 可序列化数据契约
├── providers/                 # ChangeNotifier 状态和保存队列
├── repositories/              # storage_v2 持久化
├── services/                  # API、工具、插件运行时、Tree-sitter、备份、存储升级、平台能力
├── pages/                     # 主界面、设置页、功能页、插件管理页和子页面
├── utils/                     # 文件名、分享、SnackBar、更新日志解析等工具
└── widgets/                   # Markdown/LaTeX、插件 WebView、模型选择器等 UI 组件
```

核心边界：页面负责交互，Provider 负责状态，Repository 负责本地持久化，Service 负责协议和数据搬运，Model 只描述数据。

## 文档

详细文档在 `doc/` 目录：

| 文档 | 内容 |
|------|------|
| [文档首页](doc/README.md) | 阅读路线、目录说明、维护规则。 |
| [架构说明](doc/architecture.md) | 分层、启动流程、数据流、存储与备份。 |
| [页面与使用路径](doc/pages.md) | 页面地图、用户路径和手测重点。 |
| [数据模型](doc/models.md) | 模型职责、字段语义和兼容规则。 |
| [状态管理](doc/providers.md) | Provider 分区、保存队列和容错加载。 |
| [服务层](doc/services.md) | API、工具调用、插件运行时、备份、存储升级和平台能力。 |

## CI/CD

GitHub Actions 工作流位于 `.github/workflows/build.yml`。

| 触发 | 行为 |
|------|------|
| push 到主分支 | 构建 Android、Linux、Windows、macOS，并更新 nightly 预发布。 |
| pull request 到主分支 | 构建验证。 |
| tag `v*` | 构建并创建正式 Release。 |

## 许可证

LynAI 使用 [GNU General Public License v3.0](LICENSE) 发布。

随包分发、vendored、本地构建或平台构建时引入的第三方组件见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。应用内“关于 -> 开源许可”页面也会展示项目许可证、本地 third_party 许可证和第三方 notices。
