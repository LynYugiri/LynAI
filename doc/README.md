# LynAI 项目文档

本文档按代码结构解析 LynAI。项目是 Flutter 跨平台应用，核心思路是：UI 页面只编排交互，Provider 负责本地状态与持久化，Service 负责外部 API、工具调用和备份，Model 只描述可序列化数据。当前版本：`v2.2.10`。

## 文档导航

| 文档 | 内容 |
|------|------|
| [架构概览](architecture.md) | 运行时结构、数据流、聊天主链路、附件链路、工具调用、持久化边界 |
| [页面与路由](pages.md) | `HomePage`、`ChatPage`、功能页、设置页和子页面职责 |
| [数据模型](models.md) | 对话、消息、模型配置、设置、笔记、日程、待办、备份模型 |
| [状态管理](providers.md) | 四个 Provider 的数据、方法、保存队列和容错加载策略 |
| [API 服务与工具调用](services.md) | Chat/OCR/语音/图片生成、流式解析、附件转换、本地工具、备份服务 |

## 代码结构

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
├── pages/
│   ├── chat_page.dart
│   ├── feature_page.dart
│   ├── settings_page.dart
│   ├── data_management_page.dart
│   ├── mathlive_formula_editor_page.dart
│   ├── chat/
│   └── features/
├── providers/
│   ├── conversation_provider.dart
│   ├── feature_provider.dart
│   ├── model_config_provider.dart
│   └── settings_provider.dart
├── services/
│   ├── api_service.dart
│   ├── backup_service.dart
│   └── tool_call_service.dart
├── utils/
└── widgets/
    └── latex_renderer.dart
```

## 运行时模块

| 模块 | 文件 | 责任 |
|------|------|------|
| 应用入口 | `lib/main.dart` | 注册 Provider、加载本地数据、修复模型引用、构建主题、显示启动/错误页 |
| 主导航 | `lib/pages/home_page.dart` | 三 Tab `IndexedStack`、根返回键、背景图和毛玻璃遮罩 |
| 对话页 | `lib/pages/chat_page.dart` | 文本输入、流式请求、附件、语音、OCR/文件识别、工具调用、重试、分享、对话设置 |
| 功能页 | `lib/pages/feature_page.dart` | 历史、日程、笔记、待办四个生产力入口 |
| 设置页 | `lib/pages/settings_page.dart` | About、Background、API、Theme、Data Management 入口 |
| API 管理 | `lib/pages/api_models_page.dart` | 分类模型配置、Endpoint 预设、模型拉取、多子模型和高级参数 |
| 数据管理 | `lib/pages/data_management_page.dart` | ZIP 备份导出、读取预览、选择导入、冲突处理 |
| API 服务 | `lib/services/api_service.dart` | Chat/OCR/Speech/Image Generation 请求、流式解析、附件内容转换 |
| 工具调用 | `lib/services/tool_call_service.dart` | 工具 schema、JSON fallback、日程/笔记/平台工具执行 |
| 备份服务 | `lib/services/backup_service.dart` | ZIP manifest、分区 JSON、私有附件归档与恢复、ID 冲突处理 |
| Markdown/LaTeX | `lib/widgets/latex_renderer.dart` | Markdown、LaTeX、代码高亮、代码/公式块复制和图片导出 |

## 核心数据流

```text
用户操作
  → Page 组装参数
  → Provider 更新不可变模型并 notifyListeners()
  → Provider 将当前快照排入串行保存队列
  → SharedPreferences(JSON) 或应用私有文件目录

对话流式请求
  → ChatPage 添加 user/assistant 消息
  → ApiService 返回 Stream<StreamChunk>
  → ConversationProvider.updateLastMessage(save:false) 逐 chunk 刷新
  → 完成/停止/失败后 save:true 落盘
```

## 持久化分区

| 数据 | 负责人 | 存储键 |
|------|--------|--------|
| 对话 | `ConversationProvider` | `conversations` |
| 模型 | `ModelConfigProvider` | `model_configs` |
| 设置 | `SettingsProvider` | `app_settings` |
| 日程 | `FeatureProvider` | `schedule_items` |
| 笔记 | `FeatureProvider` | `notes`, `note_folders`, `note_revisions`, `note_edit_proposals` |
| 待办 | `FeatureProvider` | `todo_lists` |

对话附件不会嵌入 JSON。图片、文件、拍照和剪贴板图片会复制到应用私有目录，再在 `Message.images` 中保存路径和元数据。备份服务只归档应用私有目录内被引用的附件，避免把任意外部文件打包进备份。

## 主要行为边界

| 边界 | 说明 |
|------|------|
| OpenAI 兼容 thinking | 客户端会发送 `thinking: {type: enabled|disabled}`，保持应用内思考开关行为 |
| Anthropic thinking | 不自动注入厂商私有 thinking 参数，需要通过 `extraParams` 明确配置 |
| 原生工具调用 | 仅对 OpenAI 兼容协议启用；Ollama/Anthropic 走 JSON fallback 或普通文本 |
| 数据容错 | 损坏列表项会被跳过，整个模块不会因单条坏数据不可用 |
| API Key 备份 | 选择 API 配置时会导出 API Key，备份文件必须按敏感文件处理 |
| SharedPreferences 容量 | 当前适合个人本地数据；大量长期历史后可考虑迁移 SQLite 或文件分片 |

## 开发命令

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

## 构建命令

```bash
flutter build apk --split-per-abi
flutter build linux
flutter build windows
flutter build macos
flutter build ios
flutter build web
```

## 维护约定

- 修改版本号时同步 `pubspec.yaml`、根 `README.md`、`doc/README.md`。
- 修改模型字段、存储键或导入导出格式时同步 `doc/models.md`、`doc/providers.md`、`doc/services.md`。
- 修改页面入口、导航结构或功能页子功能时同步 `doc/pages.md`。
- 修改聊天链路、附件策略、工具调用或渲染策略时同步 `doc/architecture.md`。
- 提交前至少运行 `flutter analyze`；涉及序列化、备份、模型迁移时运行 `flutter test`。
