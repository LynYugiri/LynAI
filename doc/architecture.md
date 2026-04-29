# 架构概览

## 状态管理

```
MaterialApp
  └── MultiProvider
        ├── SettingsProvider    → 主题/背景/语音模型/图片模型
        ├── ModelConfigProvider → AI模型配置 CRUD(含多模型ModelEntry)
        └── ConversationProvider → 对话CRUD+搜索
              └── HomePage
                    ├── HistoryPage
                    ├── ChatPage
                    │     ├── MarkdownWithLatex → LatexRenderer(Unicode映射)
                    │     ├── Voice: speech_to_text → 语音模型 → 当前模型
                    │     └── Image: image_picker → 图片模型 → 当前模型
                    └── SettingsPage
                          ├── AboutPage
                          ├── BackgroundPage
                          ├── ApiModelsPage
                          │     └── EditModelPage(Endpoint预设/获取模型/多模型)
                          └── ThemePage(36预设+HSV调色板)
```

## 数据流

```
用户操作 → Provider方法 → 更新模型 → notifyListeners() → UI重建
                              ↓
                        save*() → SharedPreferences(JSON)

流式: Stream.listen → updateLastMessage() → notifyListeners() → UI逐字更新
```

## 全局背景

`HomePage`: Stack(背景图, BackdropFilter模糊, 半透明遮罩, Scaffold(transparent))

---

## ChatPage 消息链路

### 普通文本
1. `_send()` → 添加user消息
2. 构建历史消息列表
3. `_doStream()` → `ApiService.sendStreamRequest()`
4. `stream.listen` → `updateLastMessage()` 逐字更新

### 语音
1. 设置语音模型 → 按钮显示麦克风图标
2. 点击 → speech_to_text 录音
3. `_processSpeech()` → 语音模型转写修正
4. 用修正文字+当前模型发送

### 图片
1. 设置图片模型 → +
2. image_picker 选图
3. 图片模型用 `imagePrompt` 描述图片
4. 描述文字+当前模型发送

---

## LatexRenderer

`lib/widgets/latex_renderer.dart` — 纯 Dart LaTeX→Unicode 转换器

- **`_normalize()`**: `\[...\]`→`$$...$$`, `\(...\)`→`$...$`
- **`_convertLatex()`**: 希腊字母/数学符号/上下标/分数 Unicode 映射
- **`MarkdownWithLatex`**: 自动检测→有LaTeX走自定义渲染，无LaTeX走`MarkdownBody`
- 内联渲染: `Text.rich` + `WidgetSpan` 保持文本流
- 块级渲染: 带"公式"标签+`functions`图标的卡片容器
