# 架构概览

## 状态管理架构

```
MaterialApp
  └── MultiProvider
        ├── SettingsProvider    → themeColor, backgroundImage, blur,
        │                         speechModelId, imageModelId, imagePrompt
        ├── ModelConfigProvider → AI模型配置列表 CRUD (含maxTokens等高级参数)
        └── ConversationProvider → 对话列表 CRUD + 搜索 + 消息增量更新
              └── HomePage
                    ├── HistoryPage   (watch ConversationProvider)
                    ├── ChatPage      (watch ConversationProvider, ModelConfigProvider, SettingsProvider)
                    │     ├── MarkdownWithLatex → LatexRenderer
                    │     ├── 语音: speech_to_text → 语音模型 → 当前模型
                    │     └── 图片: image_picker → 图片模型 → 当前模型
                    └── SettingsPage  (watch SettingsProvider, ModelConfigProvider)
```

- 3个Provider在`main.dart`中通过`MultiProvider`注册为全局可用
- 所有Provider继承`ChangeNotifier`
- 数据持久化：每次变更自动写入`SharedPreferences`(JSON序列化)
- 应用启动时各Provider异步加载数据(`_loadData`等待所有加载完成)

## 路由方式

命令式导航：
- `main.dart → HomePage`: MaterialPageRoute 替换
- `ChatPage → SettingsPage`: 通过 `onNavigateToSettings` 回调切换IndexedStack Tab
- `SettingsPage → 子页面`: Navigator.push(MaterialPageRoute)
- Tab切换: `BottomNavigationBar` + `IndexedStack`

## 数据流

```
用户操作 → Provider方法 → 更新数据模型 → notifyListeners() → UI重建
                              ↓
                        save*() 写入 SharedPreferences

流式API: Stream.listen → updateLastMessage() → notifyListeners() → UI逐字更新
```

## 新增模块

### widgets/latex_renderer.dart
- `LatexRenderer` — 工具类，将LaTeX命令映射到Unicode数学字符
  - 块级公式 `$$...$$`: 居中显示的带边框容器
  - 内联公式 `$...$`: 等宽斜体彩色文本
  - 支持：希腊字母、数学符号、上下标、分数(\frac)
- `MarkdownWithLatex` — Widget，自动检测LaTeX内容，有则用LatexRenderer，无则用MarkdownBody

## 全局背景

`HomePage` 支持全局自定义背景：
- 通过 `Stack` 叠加背景图+半透明遮罩
- 毛玻璃效果: `BackdropFilter` + `ImageFilter.blur`
- 通过 `Theme(scaffoldBackgroundColor: transparent)` 传递到所有子页面

## 主题系统

- Material 3 (`useMaterial3: true`)
- `ColorScheme.fromSeed(seedColor: SettingsProvider.settings.themeColor)` 为亮/暗主题生成完整配色
- 主题变更即生效(全局watch SettingsProvider)
