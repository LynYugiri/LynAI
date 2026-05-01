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
                    │     └── Image: image_picker → (图片模型) → 当前模型
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

### 键盘交互
- **桌面端** (Linux/Windows/macOS): `Enter` 发送消息, `Shift+Enter` 换行。通过 `Focus.onKeyEvent` 拦截键盘事件实现。
- **移动端** (Android/iOS): 回车键默认换行，`textInputAction: TextInputAction.newline`。

### 普通文本
1. `_send()` → 添加user消息
2. `_getModel()` 获取当前模型(优先对话绑定的模型, 其次pendingModelId, 否则列表中第一个)
3. `_convId ??= cp.createConversation()` 确保对话已创建
4. `_buildApiMessages()` 构建包含系统提示词的历史消息列表
5. `_doStream()` → `ApiService.sendStreamRequest()` 发起流式请求
6. `stream.listen` → `updateLastMessage()` 逐字更新
7. 流完成时保存思考内容到 `_thinkMap`, 支持重试导航

### 语音
1. 设置语音模型 → 按钮显示麦克风图标
2. 点击 → `speech_to_text` 录音(使用系统locale)
3. `_processSpeech()` → 语音模型转写修正
4. 用修正文字+当前模型流式发送

### 图片
1. 点击附件(+) → `image_picker` 选图
2. 添加 `[图片: filename (size)]` 用户消息
3. **已配置图片转述模型**: 图片模型用 `imagePrompt` 描述图片 → 描述文字发送给当前模型
4. **未配置图片转述模型**: 直接将图片文件名作为文本消息发送给当前模型继续对话

### 重试与历史导航
- `_retry()`: 重新生成当前回复, 保留原回复到重试历史
- `<` `>` 导航: 在多次重试版本间切换, 同时切换对应的思考内容
- `_sendRetry()`: 编辑用户消息后重发, 在重试链中创建分支
- `_editStartNewConversation()`: 从历史消息处编辑并开始新的对话分支

---

## LatexRenderer

`lib/widgets/latex_renderer.dart` — 纯 Dart LaTeX→Unicode 转换器

- **`_normalize()`**: `\[...\]`→`$$...$$`, `\(...\)`→`$...$`
- **`_convertLatex()`**: 希腊字母/数学符号/上下标/分数 Unicode 映射
- **`MarkdownWithLatex`**: 自动检测→有LaTeX走自定义渲染，无LaTeX走`MarkdownBody`
- 内联渲染: `Text.rich` + `WidgetSpan` 保持文本流
- 块级渲染: 带"公式"标签+`functions`图标的卡片容器

## 空安全与容错

- `_getModel()` 返回 `ModelConfig?` 类型，所有调用处均做空值检查
- `_findModelById()` 辅助方法用 try-catch 安全查找模型，替代 `cast<ModelConfig?>()` 模式
- `_doSend()` 在调用前检查 `_convId` 是否为null
- 流式请求完成和出错时分别处理，确保 `_streaming` 状态正确重置
- 图片选择/上传过程中的 `mounted` 检查，防止Widget销毁后操作Context

## 流式请求生命周期

```
_send() → addMessage(user) → addMessage(assistant, '') → _doSend()
  → _doStream() → ApiService.sendStreamRequest()
    → stream.listen(
        onData: updateLastMessage(convId, buf, save: false) → notifyListeners()
        isDone: updateLastMessage(convId, buf, save: true) → save to _thinkMap
        onError: updateLastMessage(convId, error, save: true) → setState(_streaming = false)
        onDone: setState(_streaming = false) [兜底]
      )
```

## 模型查找逻辑

`_getModel(mp)` 按优先级查找当前对话使用的模型:
1. 对话绑定的 `modelId` (优先)
2. `pendingModelId` (对话创建前暂存)
3. 列表中第一个模型 (兜底)
