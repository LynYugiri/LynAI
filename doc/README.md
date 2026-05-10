# LynAI 项目文档

> 跨平台 AI 对话应用，支持多种 AI 模型接口，基于 Flutter 开发。当前版本：`2.2.0`。

## 技术栈

| 类别 | 技术 |
|------|------|
| 框架 | Flutter SDK ^3.11.5 |
| 状态管理 | Provider + ChangeNotifier |
| 路由 | Navigator.push (命令式) |
| HTTP | http ^1.2.2 |
| 持久化 | SharedPreferences (JSON) |
| 图片选择 | image_picker ^1.1.2 |
| Markdown | flutter_markdown_plus ^1.0.7 |
| 语音识别 | speech_to_text ^7.3.0 |
| 分享 | share_plus ^12.0.2 |
| 截图 | screenshot ^3.0.0 |
| CI/CD | GitHub Actions (Linux/Android/Windows) |
| UI | Material 3, ColorScheme.fromSeed |

## 目录结构

```
lib/
├── main.dart              # 应用入口、启动页、主题配置
├── models/
│   ├── message.dart       # 消息模型
│   ├── conversation.dart  # 对话模型
│   ├── model_config.dart  # AI模型配置(含ModelEntry多模型)
│   ├── app_settings.dart  # 应用设置(主题/背景/角色/功能页状态)
│   ├── chat_role.dart     # 聊天角色(提示词/模型/主题色)
│   ├── note.dart          # 笔记模型
│   ├── schedule_item.dart # 日程模型
│   └── system_prompt.dart # 系统提示词模板
├── pages/
│   ├── home_page.dart     # 主页(底部导航,全局背景)
│   ├── feature_page.dart  # 功能页(历史/日程/笔记)
│   ├── chat_page.dart     # 聊天页(流式/LaTeX/语音/图片)
│   ├── settings_page.dart # 设置页(4入口)
│   ├── about_page.dart    # 关于页(动态平台)
│   ├── background_page.dart # 背景设置(图片+模糊)
│   ├── api_models_page.dart # API模型管理(Endpoint预设/多模型/获取)
│   └── theme_page.dart    # 主题设置(36预设+HSV调色板)
├── providers/
│   ├── feature_provider.dart       # 功能页数据(日程/笔记)
│   ├── conversation_provider.dart  # 对话CRUD+搜索+增量更新
│   ├── model_config_provider.dart  # 模型配置CRUD+排序
│   └── settings_provider.dart      # 设置管理
├── services/
│   └── api_service.dart   # API服务(流式/非流式,4种接口类型)
└── widgets/
    └── latex_renderer.dart # LaTeX解析渲染($...$ / \[...\])
```

## 包名

Android/iOS/macOS/Linux 统一使用 `com.github.lynyugiri.lynai`

## 文档导航

- [页面与路由](pages.md)
- [架构概览](architecture.md)
- [数据模型](models.md)
- [状态管理](providers.md)
- [API服务](services.md)

## CI/CD

GitHub Actions 自动构建 (.github/workflows/build.yml):

| 平台 | 架构 | Runner |
|------|------|--------|
| Android APK | arm64-v8a, armeabi-v7a, x86_64 | ubuntu-latest |
| Linux | x86_64 | ubuntu-latest |
| Windows | x86_64 | windows-latest |
