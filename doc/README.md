# LynAI 项目文档

LynAI 是一个 Flutter 跨平台 AI 对话客户端。项目围绕本地状态、模型配置、对话运行时、功能页数据和平台能力做了清晰拆分。当前版本：`2.2.2`。

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
├── app_version.dart
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
| 对话页 | `lib/pages/chat_page.dart` | 消息输入、流式请求、语音、图片、工具调用、分享、重试、对话设置 |
| 功能页 | `lib/pages/feature_page.dart` | 对话历史、日程表、笔记、Markdown 导入导出、长图导出 |
| 设置页 | `lib/pages/settings_page.dart` | About、Background、API、Theme 四个入口 |
| API 管理 | `lib/pages/api_models_page.dart` | 四类模型配置、Endpoint 预设、模型拉取、多子模型管理 |
| API 服务 | `lib/services/api_service.dart` | Chat、OCR、语音转写、图片生成、流式解析、思考内容提取 |
| 工具调用 | `lib/services/tool_call_service.dart` | 本地工具定义、fallback JSON 解析、日程/笔记工具执行、平台通道调用 |
| Markdown/LaTeX | `lib/widgets/latex_renderer.dart` | Markdown 渲染、公式检测、代码围栏隔离、Hurmit Nerd Font 代码字体、One Dark Pro 风格代码高亮、代码/公式块复制与单图导出、长图代码块换行 |

## 状态与持久化

应用使用 `Provider + ChangeNotifier` 管理状态，使用 `SharedPreferences` 保存 JSON。

| Provider | 管理数据 | 存储键 |
|----------|----------|--------|
| `ConversationProvider` | 对话、消息、对话设置快照、搜索结果 | `conversations` |
| `ModelConfigProvider` | Chat/OCR/Speech/Image Generation 模型配置 | `model_configs` |
| `SettingsProvider` | 主题、背景、角色、提示词、默认模型、辅助能力选择 | `app_settings` |
| `FeatureProvider` | 日程、笔记 | `schedule_items`, `notes` |

图片附件和背景图只保存本地路径；对话图片会复制到应用私有目录，减少临时文件失效风险。

## 对话链路

1. 用户输入文本、选择图片或粘贴图片。
2. `ChatPage` 根据当前角色和对话设置确定 Chat 模型、系统提示词、OCR/图片识别/语音配置。
3. 如果有图片，优先执行多模态图片识别；否则在配置 OCR 时执行 OCR；最终把识别文本拼入用户上下文。
4. `ConversationProvider.addMessage()` 保存用户消息和可选图片附件。
5. `ApiService.sendStreamRequest()` 发起流式请求，并把内容 chunk 与 reasoning chunk 分开返回。
6. `ConversationProvider.updateLastMessage(save: false)` 实时更新 UI，流结束后再持久化。
7. 如果模型返回工具调用，`ToolCallService` 执行本地工具，再把工具结果送回模型生成最终回复。

图片消息重试或编辑后重发时，`ChatPage` 会复用原消息的 `Message.images` 并重新构建图片识别上下文；重试历史导航会同步切换文本、图片和思考内容。

日程工具调用会注入当前设备本地时间、时区和偏移量。`ScheduleItem` 反序列化、工具参数解析和工具返回值都统一转换为本地时间，避免带 `Z` 或显式偏移的 ISO 时间在日历 UI 中错位。

## 模型配置

`ModelConfig.category` 将配置分为四类。

| 分类 | 常量 | 说明 |
|------|------|------|
| Chat | `ModelConfig.categoryChat` | 对话、流式、多模态识图、工具调用 |
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

- 修改版本号时同步 `pubspec.yaml`、`lib/app_version.dart`、根 `README.md`、`doc/README.md`。
- 修改模型、Provider 或服务接口时，同步更新 `doc/models.md`、`doc/providers.md`、`doc/services.md`。
- 修改页面导航或功能入口时，同步更新 `doc/pages.md`。
- 涉及聊天主链路、工具调用或渲染策略时，同步更新 `doc/architecture.md`。
- 提交前至少运行 `flutter analyze`；涉及模型序列化时运行 `flutter test`。
