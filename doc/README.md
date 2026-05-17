# LynAI 项目文档

LynAI 是一个 Flutter 跨平台 AI 对话客户端。项目围绕本地状态、模型配置、对话运行时、功能页数据和平台能力做了清晰拆分。当前版本：`v2.2.10`。

## 文档导航

| 文档 | 内容 |
|------|------|
| [架构概览](architecture.md) | Provider 关系、主数据流、聊天链路、角色上下文、Markdown/LaTeX 渲染 |
| [页面与路由](pages.md) | HomePage、ChatPage、FeaturePage、SettingsPage 及子页面职责 |
| [数据模型](models.md) | Conversation、Message、ModelConfig、AppSettings、Note、ScheduleItem 等 |
| [状态管理](providers.md) | ConversationProvider、ModelConfigProvider、SettingsProvider、FeatureProvider |
| [API 服务与工具调用](services.md) | OpenAI/Ollama/Anthropic/vivo 请求、流式解析、本地工具调用 |

## 项目结构

```text
lib/
├── main.dart
├── models/
│   ├── app_settings.dart
│   ├── chat_role.dart
│   ├── conversation.dart
│   ├── message.dart
│   ├── model_config.dart
│   ├── note.dart
│   ├── schedule_item.dart
│   └── system_prompt.dart
├── pages/
│   ├── about_page.dart
│   ├── api_models_page.dart
│   ├── background_page.dart
│   ├── chat_page.dart
│   ├── feature_page.dart
│   ├── home_page.dart
│   ├── settings_page.dart
│   └── theme_page.dart
├── providers/
│   ├── conversation_provider.dart
│   ├── feature_provider.dart
│   ├── model_config_provider.dart
│   └── settings_provider.dart
├── services/
│   ├── api_service.dart
│   └── tool_call_service.dart
└── widgets/
    └── latex_renderer.dart
```

## 运行时模块

| 模块 | 文件 | 责任 |
|------|------|------|
| 应用入口 | `lib/main.dart` | 注册 Provider、加载持久化数据、构建浅色/深色主题、显示启动/错误页 |
| 主导航 | `lib/pages/home_page.dart` | `IndexedStack` 保持三大 Tab 状态，处理背景图和毛玻璃遮罩 |
| 对话页 | `lib/pages/chat_page.dart` | 消息输入、流式请求、语音、文件/图片附件、工具调用、分享、重试、对话设置 |
| 功能页 | `lib/pages/feature_page.dart` | 对话历史、日程表、笔记、Markdown 导入导出、长图导出 |
| 设置页 | `lib/pages/settings_page.dart` | About、Background、API、Theme 四个入口 |
| API 管理 | `lib/pages/api_models_page.dart` | 四类模型配置、Endpoint 预设、模型拉取、多子模型管理 |
| API 服务 | `lib/services/api_service.dart` | Chat、OCR、语音转写、图片生成、附件内容转换、流式解析、思考内容提取 |
| 工具调用 | `lib/services/tool_call_service.dart` | 本地工具定义、fallback JSON 解析、日程/笔记工具执行、平台通道调用 |
| Markdown/LaTeX | `lib/widgets/latex_renderer.dart` | Markdown 渲染、公式检测、代码围栏隔离、Hurmit Nerd Font 代码字体、One Dark Pro 风格代码高亮、代码/公式块复制与单图导出、长图代码块换行 |

## 状态与持久化

应用使用 `Provider + ChangeNotifier` 管理状态，使用 `SharedPreferences` 保存 JSON。

| Provider | 管理数据 | 存储键 |
|----------|----------|--------|
| `ConversationProvider` | 对话、消息、对话设置快照、搜索结果 | `conversations` |
| `ModelConfigProvider` | Chat/OCR/Speech/Image Generation 模型配置 | `model_configs` |
| `SettingsProvider` | 主题、背景、角色、提示词、默认模型、辅助能力选择 | `app_settings` |
| `FeatureProvider` | 日程、笔记、笔记文件夹、笔记修订、待办 | `schedule_items`, `notes`, `note_folders`, `note_revisions`, `todo_lists` |

消息附件和背景图只保存本地路径；对话附件会复制到应用私有目录，减少临时文件失效风险。

Provider 写入 SharedPreferences 时使用快照串行保存队列。状态变更会立即通知 UI，落盘按调用顺序执行，避免快速连续修改时旧写入覆盖新状态。

### 数据目录与附件

对话附件不会嵌入 JSON。选图、拍照、文件选择和剪贴板图片会先复制到应用私有目录，再把路径、文件名、大小和 MIME 类型写入 `Message.images`。这样历史消息不会依赖系统 picker 返回的临时路径。

| 数据 | 保存方式 |
|------|----------|
| 对话 JSON | `SharedPreferences` 的 `conversations` |
| 附件文件 | 应用文档目录下的 `message_images` 或 `message_attachments` |
| 背景图路径 | `AppSettings.backgroundImagePath` |
| 导出临时文件 | 系统临时目录或用户选择的保存路径 |

旧数据中如果附件只有 `filePath`，会兼容读取为 `path`，并从路径推导文件名和 MIME 类型。

## v2.2.10 发布说明

`v2.2.10` 是发布前稳定性版本，重点修复流式错误处理、数据容错、配置清空和异步 UI 生命周期问题。

| 分类 | 变更 |
|------|------|
| Chat 流式 | OpenAI 兼容与 Anthropic 流式错误会被明确抛出，坏工具参数不会中断整条回复 |
| 思考内容 | `ConversationProvider.updateLastMessage()` 可显式清空 `thinkingContent`，避免旧思考内容污染新回复 |
| 数据模型 | 损坏消息逐条跳过；损坏角色和系统提示词逐条跳过；旧 `filePath` 附件可恢复文件名和 MIME 类型 |
| 模型配置 | `ModelConfig.copyWith()` 支持清空 `maxTokens`、`temperature`、`topP` |
| 设置修复 | 已删除模型引用会同步修复语音、OCR、文件识别和最近聊天模型选择 |
| 页面生命周期 | 录音、附件选择、拍照、剪贴板图片、备份导入导出和 MathLive 回调增加竞态防护 |
| 文档 | README 与 doc 文档同步到 `v2.2.10` |

### 行为边界

- OpenAI 兼容接口仍默认发送 `thinking: {type: enabled|disabled}`，这是当前应用思考开关的既有协议行为。
- Anthropic 不自动注入厂商私有 thinking 请求参数；如供应商需要额外参数，应放入 `ModelConfig.extraParams`。
- 原生工具调用只对 OpenAI 兼容接口启用；Ollama 和 Anthropic 默认走 JSON fallback 或普通文本能力。
- 数据容错策略是“跳过坏项、保留好项”，不会自动修复原始 SharedPreferences 中的坏 JSON 字段；下一次保存相关数据时才会写回当前内存快照。
- 备份导出如果包含 API 配置，会包含模型配置中的 API Key。备份文件应按敏感文件处理。

### 发布检查记录

| 命令 | 结果 |
|------|------|
| `dart format lib test` | 通过 |
| `flutter analyze` | 通过，`No issues found!` |
| `flutter test` | 通过，`All tests passed!` |

### 建议手测矩阵

| 模块 | 场景 |
|------|------|
| Chat | OpenAI 兼容流式、Ollama 流式、Anthropic 流式、服务端错误、停止生成、重试历史切换 |
| 工具调用 | 查询日程、创建日程、保存笔记、工具参数异常、工具循环后的最终回复 |
| 附件 | 多图、拍照、PDF/文本文件、剪贴板图片、带附件消息重试和编辑后重发 |
| 语音 | 无语音模型时系统识别、有语音模型时录音转写、快速按下松开、权限拒绝 |
| 数据 | 旧备份导入、损坏单条消息、损坏角色/提示词、旧 `filePath` 附件 |
| 导出 | 对话长图、笔记长图、代码块 PNG、公式块 PNG、桌面剪贴板和移动端图库 |

## 对话链路

1. 用户输入文本、选择文件/图片、拍照或粘贴图片。
2. `ChatPage` 根据当前角色和对话设置确定 Chat 模型、系统提示词、OCR/文件识别/语音配置。
3. 图片在开启 OCR 时先提取文字；非图片文件在开启文件识别时由所选 Chat 模型读取；未开启对应识别能力的附件会作为多模态内容直传或退化为文本元数据。
4. `ConversationProvider.addMessage()` 保存用户消息和可选附件。
5. `ApiService.sendStreamRequest()` 发起流式请求，并把内容 chunk 与 reasoning chunk 分开返回。
6. `ConversationProvider.updateLastMessage(save: false)` 实时更新 UI，流结束后再持久化。
7. 如果模型返回工具调用，`ToolCallService` 执行本地工具，再把工具结果送回模型生成最终回复。

带附件消息重试或编辑后重发时，`ChatPage` 会复用原消息的 `Message.images` 并重新构建 OCR/文件识别上下文；重试历史导航会同步切换文本、附件和思考内容。

日程工具调用会注入当前设备本地时间、时区和偏移量。`ScheduleItem` 反序列化、工具参数解析和工具返回值都统一转换为本地时间，避免带 `Z` 或显式偏移的 ISO 时间在日历 UI 中错位。

## 模型配置

`ModelConfig.category` 将配置分为四类。

| 分类 | 常量 | 说明 |
|------|------|------|
| Chat | `ModelConfig.categoryChat` | 对话、流式、多模态文件识别、工具调用 |
| OCR | `ModelConfig.categoryOcr` | vivo OCR 请求格式，需 AppID/AppKey |
| Speech | `ModelConfig.categorySpeech` | vivo 长语音转写，含 create/upload/run/progress/result 流程 |
| Image Generation | `ModelConfig.categoryImageGeneration` | OpenAI Images 或 vivo 图片生成 |

每个 Chat 提供商可维护多个 `ModelEntry`，只有 `enabled=true` 的子模型会出现在对话模型选择器中。

## 平台能力

Android 原生通道位于 `android/app/src/main/kotlin/com/github/lynyugiri/lynai/MainActivity.kt`，通道名为 `lynai/native_tools`。

| 方法 | 平台 | 说明 |
|------|------|------|
| `openApp` | Android | 按包名打开已安装应用 |
| `getLocation` | Android | 请求定位权限后读取最近位置 |
| `saveImageToGallery` | Android | 将 PNG 写入 `Pictures/LynAI` |

桌面端长图和代码/公式块图片使用 `super_clipboard` 写入系统剪贴板；移动端通过 `saveImageToGallery` 保存到图库，其他平台回退到系统分享。

## 开发命令

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

常用构建：

```bash
flutter build apk --split-per-abi
flutter build linux
flutter build windows
flutter build macos
flutter build ios
flutter build web
```

## CI/CD

`.github/workflows/build.yml` 会在 push、pull request 和 tag 时运行。

| 触发 | 行为 |
|------|------|
| push 到 `main`/`master` | 构建 Android、Linux、Windows、Web，并更新 `nightly` 预发布 |
| pull request 到 `main`/`master` | 构建验证 |
| tag `v*` | 构建产物并创建正式 GitHub Release |

Release 文件与上传 artifact 统一使用 `LynAI_<platform>_<version>_<short_sha>_<arch-or-target>` 命名；Web 使用 `universal` 作为 target。

## 维护约定

- 修改版本号时同步 `pubspec.yaml`、根 `README.md`、`doc/README.md`。
- 修改模型、Provider 或服务接口时，同步更新 `doc/models.md`、`doc/providers.md`、`doc/services.md`。
- 修改页面导航或功能入口时，同步更新 `doc/pages.md`。
- 涉及聊天主链路、工具调用或渲染策略时，同步更新 `doc/architecture.md`。
- 提交前至少运行 `flutter analyze`；涉及模型序列化时运行 `flutter test`。
