# LynAI 文档

这份文档写给两类人：想把 LynAI 用明白的人，以及需要继续维护这套代码的人。它不假设读者已经读过源码，会先解释功能和数据流，再指向具体文件。

当前版本：`v2.2.10`

## 从哪里开始读

| 你想了解 | 推荐文档 |
|----------|----------|
| 项目整体怎么分层、数据怎么流动 | [架构说明](architecture.md) |
| 每个页面能做什么、用户路径是什么 | [页面与使用路径](pages.md) |
| JSON 数据长什么样、哪些字段需要兼容旧版本 | [数据模型](models.md) |
| Provider 如何加载、保存、容错和通知 UI | [状态管理](providers.md) |
| API 请求、工具调用、备份导入导出如何工作 | [服务层、API 与工具调用](services.md) |

## 一句话架构

LynAI 是一个 Flutter 本地应用：页面层处理交互，Provider 保存本地状态，Service 处理外部协议和数据搬运，Model 定义可序列化的数据契约。

```text
Page
  → Provider
  → SharedPreferences / 私有文件目录

Page
  → Service
  → 外部 API / 平台通道 / ZIP 文件
```

这个边界很重要。页面不应该直接写本地存储，Service 不应该直接持有 UI 状态，Model 不应该混入业务流程。

## 代码目录

```text
lib/
├── main.dart
├── models/
│   ├── app_settings.dart
│   ├── backup_models.dart
│   ├── chat_role.dart
│   ├── conversation.dart
│   ├── message.dart
│   ├── model_config.dart
│   ├── note.dart
│   ├── schedule_item.dart
│   ├── system_prompt.dart
│   └── todo_list.dart
├── providers/
│   ├── conversation_provider.dart
│   ├── feature_provider.dart
│   ├── model_config_provider.dart
│   └── settings_provider.dart
├── services/
│   ├── api_service.dart
│   ├── backup_service.dart
│   └── tool_call_service.dart
├── pages/
│   ├── chat_page.dart
│   ├── feature_page.dart
│   ├── settings_page.dart
│   ├── data_management_page.dart
│   ├── api_models_page.dart
│   ├── chat/
│   └── features/
├── utils/
└── widgets/
    └── latex_renderer.dart
```

## 运行时模块

| 模块 | 文件 | 责任 |
|------|------|------|
| 应用入口 | `lib/main.dart` | 注册 Provider、加载持久化数据、修复悬空模型引用、构建主题。 |
| 主导航 | `lib/pages/home_page.dart` | 三个 Tab、返回键协调、背景图和毛玻璃遮罩。 |
| 对话页 | `lib/pages/chat_page.dart` | 输入、附件、语音、流式请求、工具调用、重试、分享。 |
| 功能页 | `lib/pages/feature_page.dart` | 历史、日程、笔记、待办四个入口。 |
| 设置页 | `lib/pages/settings_page.dart` | About、Background、API、Theme、Data Management 入口。 |
| API 管理 | `lib/pages/api_models_page.dart` | Provider 配置、子模型、Endpoint 预设、高级参数。 |
| 数据管理 | `lib/pages/data_management_page.dart` | ZIP 备份导出、读取预览、导入选择和冲突处理。 |
| API 服务 | `lib/services/api_service.dart` | Chat/OCR/Speech/Image 请求、流式解析、附件转换。 |
| 工具调用 | `lib/services/tool_call_service.dart` | 工具 schema、fallback JSON、日程/笔记/平台工具执行。 |
| 备份服务 | `lib/services/backup_service.dart` | manifest、分区 JSON、私有附件归档和恢复、ID 冲突处理。 |
| Markdown/LaTeX | `lib/widgets/latex_renderer.dart` | Markdown、LaTeX、代码高亮、代码/公式块复制和图片导出。 |

## 本地数据分区

| 数据 | Provider | 存储键 |
|------|----------|--------|
| 对话 | `ConversationProvider` | `conversations` |
| 模型 | `ModelConfigProvider` | `model_configs` |
| 设置 | `SettingsProvider` | `app_settings` |
| 日程 | `FeatureProvider` | `schedule_items` |
| 笔记 | `FeatureProvider` | `notes`, `note_folders`, `note_revisions`, `note_edit_proposals` |
| 待办 | `FeatureProvider` | `todo_lists` |

附件不嵌入 JSON。页面会先把用户选择的图片、文件、拍照结果或剪贴板图片复制到应用私有目录，再把路径和元数据放进 `Message.images`。

## 注释与文档约定

代码注释统一遵循三条规则：

1. 公开类、公开方法、稳定数据契约使用 Dart 文档注释 `///`。
2. 方法内部只用普通 `//` 解释非显然约束，例如兼容旧数据、平台差异、协议特殊字段或必须保留的行为。
3. 不注释显而易见的赋值、简单 getter、UI 文案拼装；这类注释会比代码更难维护。

文档维护约定：

| 改动 | 需要同步 |
|------|----------|
| 修改版本号 | `pubspec.yaml`、根 `README.md`、`doc/README.md`。 |
| 修改模型字段或存储键 | `doc/models.md`、`doc/providers.md`、备份相关内容。 |
| 修改聊天链路、附件策略或工具调用 | `doc/architecture.md`、`doc/services.md`。 |
| 修改页面入口或用户路径 | `doc/pages.md`。 |
| 修改备份格式或导入策略 | `doc/services.md`、`doc/models.md`。 |

## 开发命令

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

如果依赖已经存在、只想验证代码，可以使用：

```bash
flutter analyze --no-pub
flutter test --no-pub
```

平台构建细节由 CI 工作流和 Flutter 官方命令负责；文档只记录项目结构和需要注意的运行时差异。
