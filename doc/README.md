# LynAI 项目文档索引

> AI对话应用，支持多种AI模型接口，基于Flutter开发。

## 技术栈

| 类别 | 技术 |
|------|------|
| 框架 | Flutter SDK ^3.11.5 |
| 状态管理 | Provider + ChangeNotifier |
| 路由 | Navigator.push (命令式) |
| HTTP | http ^1.2.2 |
| 持久化 | SharedPreferences (JSON) |
| 图片选择 | image_picker ^1.1.2 |
| Markdown | flutter_markdown ^0.7.7 |
| 语音识别 | speech_to_text ^7.3.0 |
| 分享 | share_plus ^13.1.0 |
| 截图 | screenshot ^3.0.0 |
| UI | Material 3, ColorScheme.fromSeed |

## 目录结构

```
lib/
├── main.dart              # 应用入口、启动页、主题配置
├── models/                # 数据模型
│   ├── message.dart
│   ├── conversation.dart
│   ├── model_config.dart
│   └── app_settings.dart
├── pages/                 # 页面/界面
│   ├── home_page.dart     # 主页 (底部导航，全局背景)
│   ├── history_page.dart  # 历史对话页
│   ├── chat_page.dart     # 聊天页 (流式、Markdown/LaTeX、语音)
│   ├── settings_page.dart # 设置页 (含语音/图片模型配置)
│   ├── about_page.dart    # 关于页 (动态平台显示)
│   ├── background_page.dart # 背景设置页
│   ├── api_models_page.dart # API模型管理页 (高级选项)
│   └── theme_page.dart    # 主题设置页
├── providers/             # 状态管理
│   ├── conversation_provider.dart
│   ├── model_config_provider.dart
│   └── settings_provider.dart
├── services/              # API服务
│   └── api_service.dart   # 流式/非流式，OpenAI/Ollama/Anthropic/Custom
└── widgets/               # 自定义组件
    └── latex_renderer.dart # LaTeX 公式解析与渲染
```

## 文档导航

- [页面与路由](pages.md) - 所有页面界面及导航结构
- [架构概览](architecture.md) - 状态管理、路由、数据流
- [数据模型](models.md) - Message, Conversation, ModelConfig, AppSettings
- [状态管理](providers.md) - Provider 及核心方法
- [API服务](services.md) - ApiService 接口说明
