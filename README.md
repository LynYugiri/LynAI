# LynAI

LynAI 是一个本地优先的跨平台 AI 客户端。它把多模型对话、Markdown/LaTeX 渲染、文件和图片理解、语音输入、本地工具、日程、笔记、待办以及完整备份恢复放在同一个 Flutter 应用里。

## 它适合什么场景

LynAI 的目标不是只做一个聊天壳，而是把 AI 对话和本地个人数据连接起来：

- 和 OpenAI 兼容接口、Ollama、Anthropic 等模型对话。
- 把图片、PDF、文本、表格、Office 文件或压缩包放进上下文。
- 用本地工具让模型查询或创建日程、读取或保存笔记。
- 在同一个应用里维护 Markdown 笔记、待办清单和日程。
- 把设置、模型、历史、笔记、待办、日程和私有附件导出为 ZIP 备份。

应用尽量把数据留在本地。对话、设置和功能数据保存在本机；只有你主动发送给模型或工具的内容会离开设备。

## 截图

| 设置 | 对话 |
|------|------|
| ![设置](./images/demo/1.png) | ![对话](./images/demo/2.png) |

## 功能概览

| 模块 | 说明 |
|------|------|
| AI 对话 | OpenAI 兼容接口、Ollama、Anthropic；支持流式回复、停止生成、失败重试、编辑后重发和多版本回复历史。 |
| 模型管理 | 按 Chat、OCR、Speech、Image Generation 分类管理接口；支持 Endpoint 预设、模型拉取、多子模型、视觉/思考/工具能力和采样参数。 |
| 附件输入 | 支持文件、多图、拍照、桌面剪贴板图片；附件会复制到应用私有目录，历史消息和备份可以恢复引用。 |
| 图片与文件理解 | 图片可走 OCR；非图片文件可由 Chat 模型读取，或按模型能力作为多模态附件/文本上下文发送。 |
| 语音输入 | 未配置语音模型时使用系统语音识别；配置语音模型后可录音并调用 vivo 长语音转写。 |
| Markdown/LaTeX | 支持 Markdown、代码高亮、内联/块级 LaTeX、公式编辑、代码块和公式块复制或导出图片。 |
| 本地工具 | 模型可以查询时间、读取定位、打开 Android 应用、查询/创建/修改日程、查询/读取/保存笔记。 |
| 功能页 | 对话历史、日程表、Markdown 笔记、待办清单；支持搜索、导入、导出和长图分享。 |
| 角色与提示词 | 多角色、系统提示词模板、角色默认模型、角色主题色；历史对话保存自己的设置快照。 |
| 外观 | Material 3、预设色、HSV 调色板、浅色/深色/跟随系统、背景图和毛玻璃效果。 |
| 数据管理 | ZIP 备份导出、读取预览、分区导入、冲突处理和私有附件恢复。 |

## 支持平台

| 平台 | 状态 | 注意事项 |
|------|------|----------|
| Android | 支持 | 包含定位、打开应用、图库保存、日程小组件和通知等原生能力。 |
| iOS | 支持 | 文件、分享、相册、录音等能力受系统权限和插件支持影响。 |
| Linux | 支持 | 图片导出优先写入剪贴板。 |
| macOS | 支持 | CI 构建 x64 和 arm64 包。 |
| Windows | 支持 | CI 构建 x64 zip 包。 |
| Web | 可构建 | 浏览器沙箱会限制本地文件、剪贴板、平台通道和后台能力。 |

## 快速开始

环境要求：Flutter stable，Dart SDK 约束为 `^3.11.5`。

```bash
git clone https://github.com/lynyugiri/lynai.git
cd lynai
flutter pub get
flutter run
```

开发时可以先跑一次检查：

```bash
flutter analyze
flutter test
```

## 首次配置

进入 `设置 -> API` 添加模型配置。Chat 配置可以使用 OpenAI、DeepSeek、Anthropic、Google AI、Ollama、OpenRouter、Groq、Together AI、xAI、Moonshot、vivo、智谱、通义千问、SiliconFlow 等预设，也可以填写自定义 OpenAI 兼容 Endpoint。

| 分类 | 用途 | 关键字段 |
|------|------|----------|
| Chat | 对话、文件识别、多模态输入和工具调用。 | Provider 名称、API 类型、Endpoint、API Key、模型列表、能力开关和高级参数。 |
| OCR | 图片文字识别。 | vivo OCR Endpoint、AppID、AppKey。 |
| Speech | 录音转文字。 | vivo 长语音转写 Endpoint、AppID、AppKey、engineid。 |
| Image Generation | 图片生成。 | OpenAI Images 或 vivo 图片生成 Endpoint、API Key、模型名。 |

一个 Chat Provider 可以包含多个子模型。只有启用的子模型会出现在模型选择器里。当前子模型的 `maxTokens`、`temperature`、`topP` 优先级高于 Provider 级参数。

## 使用建议

1. 先添加一个 Chat 模型配置，并确认普通对话可以发送。
2. 如果使用图片或文件，确认当前子模型的视觉能力开关是否符合接口实际能力。
3. 如果需要工具调用，只在可信模型和可信对话中开启工具能力。
4. 如果要备份 API 配置，请把导出的 ZIP 当作敏感文件保存，因为其中会包含 API Key。
5. 大量长期历史、长笔记和多附件会增加本地 JSON 存储体积，建议定期导出备份。

## 数据在哪里

LynAI 主要使用 `SharedPreferences` 保存 JSON 数据，文件类资源保存到应用私有目录并在 JSON 中记录路径。

| 数据 | 负责人 | 存储 |
|------|--------|------|
| 对话历史 | `ConversationProvider` | `conversations` |
| 模型配置 | `ModelConfigProvider` | `model_configs` |
| 应用设置 | `SettingsProvider` | `app_settings` |
| 日程 | `FeatureProvider` | `schedule_items` |
| 笔记 | `FeatureProvider` | `notes`, `note_folders`, `note_revisions`, `note_edit_proposals` |
| 待办 | `FeatureProvider` | `todo_lists` |
| 备份 | `BackupService` | ZIP：`manifest.json`、分区 JSON、`assets/` 私有附件 |

## 项目结构

```text
lib/
├── main.dart                  # Provider 注册、启动加载、主题构建
├── models/                    # 可序列化数据契约
├── providers/                 # ChangeNotifier 状态和本地持久化
├── services/                  # API、工具调用、备份导入导出
├── pages/                     # 主页面、设置页、功能页和子页面
├── utils/                     # 文件名、分享、SnackBar 等工具
└── widgets/                   # Markdown/LaTeX 渲染组件
```

核心边界很简单：页面负责交互，Provider 负责状态和落盘，Service 负责外部协议和数据搬运，Model 只描述可序列化数据。

## 文档

详细文档在 `doc/` 目录：

- [文档首页](doc/README.md)
- [架构说明](doc/architecture.md)
- [页面与使用路径](doc/pages.md)
- [数据模型](doc/models.md)
- [状态管理](doc/providers.md)
- [服务层、API 与工具调用](doc/services.md)

## CI/CD

GitHub Actions 工作流位于 `.github/workflows/build.yml`。

| 触发 | 行为 |
|------|------|
| push 到 `main`/`master` | 构建 Android、Linux、Windows、macOS、Web，并更新 `nightly` 预发布。 |
| pull request 到 `main`/`master` | 构建验证。 |
| tag `v*` | 构建并创建正式 Release。 |

Release 产物命名格式为 `LynAI_<platform>_<version>_<short_sha>_<arch-or-target>.<ext>`。

## 许可证

[GNU General Public License v3.0](LICENSE)
