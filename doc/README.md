# LynAI 文档

这组文档写给使用者和维护者。它解释项目的功能边界、数据流、存储策略和代码组织方式，不记录发布版本号或临时 release 状态。

## 阅读路线

| 想了解 | 阅读 |
|--------|------|
| 项目怎么分层、启动怎么跑、数据怎么落盘 | [架构说明](architecture.md) |
| 每个页面在哪里、用户路径是什么 | [页面与使用路径](pages.md) |
| 模型字段、JSON 契约和兼容旧数据 | [数据模型](models.md) |
| Provider 如何加载、通知、保存和容错 | [状态管理](providers.md) |
| API、工具调用、备份、存储升级和平台能力 | [服务层](services.md) |
| 安全同步、设备身份、配对和加密备份的 v1 wire contract | [安全同步与备份协议 v1](protocol-v1.md) |

## 一句话架构

LynAI 是一个 Flutter 本地应用：页面层处理交互，Provider 维护内存状态，Repository 选择本地存储，Service 处理外部协议和数据搬运，Model 定义可序列化契约。

```text
Page
  -> Provider
  -> Repository
  -> storage_v2

Page
  -> Service
  -> 模型 API / 平台通道 / ZIP / 文件系统
```

这个边界要保持清楚。页面不直接写持久化，Service 不持有页面状态，Model 不做网络请求或文件读写。

## 代码目录

```text
lib/
├── main.dart
├── models/
├── providers/
├── repositories/
├── services/
├── pages/
│   ├── chat/
│   ├── features/
│   │   └── plugin_feature_page.dart
│   ├── plugin_management_page.dart
├── utils/
└── widgets/
```

| 目录 | 责任 |
|------|------|
| `models/` | 数据模型、JSON 读写、旧字段兼容。 |
| `providers/` | UI 状态、业务操作入口、可 flush 保存队列、单条容错与分区失败传播。 |
| `repositories/` | 本地持久化，统一读写 storage_v2。 |
| `services/` | API、工具调用、备份、storage_v2 升级、平台能力。 |
| `pages/` | 页面交互、导航、输入处理、渲染组合。 |
| `utils/` | 文件名、分享、提示、更新日志解析等无状态工具。 |
| `widgets/` | 可复用 UI，尤其 Markdown/LaTeX 渲染。 |

## 运行时模块

| 模块 | 入口文件 | 责任 |
|------|----------|------|
| 应用入口 | `lib/main.dart` | 注册 Provider、执行 storage_v2 升级、加载数据、迁移托管模型 ID、检查更新日志。 |
| 主导航 | `lib/pages/home_page.dart` | 五个主 Tab、返回键协调、背景图和状态保活。 |
| 对话 | `lib/pages/chat_page.dart` | 输入、附件、语音、流式请求、工具调用、重试、分享。 |
| 功能页 | `lib/pages/feature_page.dart` | Dashboard、历史、日程、笔记、待办、情景演绎。 |
| 设置 | `lib/pages/settings_page.dart` | 关于、背景、API、主题、数据管理入口。 |
| 数据管理 | `lib/pages/data_management_page.dart` | ZIP 备份、预览、导入和冲突处理。 |
| API 服务 | `lib/services/api_service.dart` | Chat/OCR/Speech/Image 请求、流式解析、附件转换。 |
| 工具调用 | `lib/services/tool_call_service.dart` | 工具 schema、fallback JSON、日程/笔记/待办/平台工具执行。 |
| 备份服务 | `lib/services/backup_service.dart` | manifest、分区 JSON、私有附件归档和恢复。 |
| 存储服务 | `lib/services/storage_v2_service.dart` | storage_v2 根目录、数据库、数据文件、资源文件和安全路径。 |
| 插件运行时 | `lib/services/plugin_lua_runtime_service.dart` | Lua 沙箱执行、工具/函数注册、延续链、权限注入。 |
| 代码语法 | `lib/services/code_syntax_service.dart` | tree-sitter 原生 + Dart fallback 双路径代码高亮。 |
| tree-sitter 原生 | `lib/services/tree_sitter_native.dart` | 语言注册、FFI 绑定解析、语言 grammar 注册映射。 |

## 本地数据分区

| 数据 | Provider | Repository / Service |
|------|----------|----------------------|
| 对话 | `ConversationProvider` | `ConversationRepository` |
| 模型 | `ModelConfigProvider` | `ModelConfigRepository` |
| 设置、角色、提示词 | `SettingsProvider` | `SettingsRepository` |
| 日程、笔记、待办 | `FeatureProvider` | `FeatureRepository` |
| 情景演绎 | `RoleplayProvider` | `RoleplayRepository` |
| 插件 | `PluginProvider` | `PluginRepository` |
| storage_v2 | 多个 Repository 共用 | `StorageV2Service`、`StorageV2Database` |
| 备份 | 多个 Provider 协作 | `BackupService` |

## 文档维护规则

| 改动 | 同步文档 |
|------|----------|
| 新增页面、入口或用户路径 | `pages.md` |
| 新增模型字段、旧字段 fallback 或存储分区 | `models.md`、`providers.md` |
| 修改 Provider 行为、保存队列或容错策略 | `providers.md` |
| 修改 API 协议、工具调用、备份或存储升级 | `services.md`、`architecture.md` |
| 修改整体分层、启动流程或存储权威源 | `architecture.md`、本文件 |

文档不要复制 `pubspec.yaml` 中的应用版本号，也不要把发布号写进 `doc/`。如果必须提到 schema，优先引用代码常量名称，例如 `BackupService.currentSchemaVersion`。

## 开发命令

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

如果依赖已经准备好，可以使用：

```bash
flutter analyze --no-pub
flutter test --no-pub
```

## CI 与平台构建

CI 在 Flutter stable 上先执行质量门禁，再构建 Android split APK、Linux Debian/Arch 包、Windows x64 ZIP，以及 macOS x64/arm64 产物。Linux 构建机需要 GTK、WebKitGTK、libsecret、xz 和 zstd 相关依赖；Android OCR 构建会先获取 ncnn、opencv-mobile 和 PPOCRv5 资源。iOS 工程继续保留，但暂不进入发布构建矩阵。

macOS release 构建在 `flutter pub get` 后、`flutter build` 前必须执行 `ruby scripts/patch-speech-to-text.rb`，修补当前 `speech_to_text` pub-cache Swift package。CI 已包含该步骤，本地 macOS release 构建遇到对应 Swift 包问题时应遵循同一顺序。

- LAN pairing and point-to-point sync are available without a cloud account and
  synchronize the installation-local dataset rather than an individual cloud
  account. Cloud synchronization remains isolated per backend origin and user ID.
  LAN transport uses mDNS, signed QR payloads, TLS 1.3 SPKI pinning, and Ed25519
  device trust.
- Plugin sync includes only sanitized files, settings, and configuration.
  `plugin_storage` and private plugin storage remain device-local and are never
  synchronized through cloud or LAN.
