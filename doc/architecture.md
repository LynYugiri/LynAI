# 架构概览

## 状态管理

```
MaterialApp
  └── MultiProvider
        ├── SettingsProvider    → 主题/背景/默认模型/系统提示词/语音/OCR/图片识别
        ├── ModelConfigProvider → 分类模型配置 CRUD(Chat/OCR/Speech/Image Generation)
        └── ConversationProvider → 对话CRUD+搜索
              └── HomePage
                    ├── HistoryPage
                    ├── ChatPage
                    │     ├── MarkdownWithLatex → flutter_markdown_plus + flutter_math_fork
                    │     ├── Voice: speech_to_text 或 record → 语音转写接口
                    │     ├── Image: image_picker / clipboard → OCR 或多模态识图 → 当前模型
                    │     └── Share: screenshot 长图 → 剪贴板/系统分享
                    └── SettingsPage
                          ├── AboutPage
                          ├── BackgroundPage
                          ├── ApiModelsPage
                          │     └── EditModelPage(分类配置/Endpoint预设/获取模型/多模型)
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
2. `_getModel()` 获取当前 Chat 模型(优先对话绑定，其次 pending/draft/lastChatModelId，再兜底首个 Chat 模型)
3. `_convId ??= cp.createConversation()` 确保对话已创建
4. `_buildApiMessages()` 构建包含系统提示词的历史消息列表
5. `_doStream()` → `ApiService.sendStreamRequest()` 发起流式请求
6. `stream.listen` → `updateLastMessage()` 逐字更新
7. 流完成时保存思考内容到 `_thinkMap`, 支持重试导航

### 语音
1. 未配置语音转写接口时，使用系统 `speech_to_text` 把识别结果写入输入框
2. 已配置语音转写接口时，使用 `record` 录制 m4a 临时文件
3. `_processRecordedSpeech()` → `ApiService.transcribeAudio()` 调用 vivo 长语音转写流程
4. 转写文本只回填输入框，不自动发送，用户可先修正

### 图片
1. 点击附件(+) 选择图片，或桌面端通过 `Ctrl/Cmd + V` 粘贴图片
2. 图片会复制到应用私有目录，并作为 `Message.images` 附件持久化
3. **已开启图片识别**: 选中的多模态 Chat 模型先识图，再把识别结果拼入本轮用户上下文
4. **未开启图片识别但配置 OCR**: OCR 提取文字并拼入用户上下文
5. **未配置识别能力**: 仅把图片文件名和大小作为文本上下文发送

### 长图分享
1. 点击消息操作中的分享按钮进入选择模式
2. 选中消息后，`_ShareConversationImage` 生成分享专用布局
3. 使用 `ScreenshotController.captureFromLongWidget()` 捕获长内容，较多消息时降低 pixelRatio
4. 桌面端写入系统剪贴板，移动端交给 `share_plus` 分享；也可保存到本地

### 重试与历史导航
- `_retry()`: 重新生成当前回复, 保留原回复到重试历史
- `<` `>` 导航: 在多次重试版本间切换, 同时切换对应的思考内容
- `_sendRetry()`: 编辑用户消息后重发, 在重试链中创建分支
- `_editStartNewConversation()`: 从历史消息处编辑并开始新的对话分支

---

## LatexRenderer

`lib/widgets/latex_renderer.dart` — 使用 `flutter_markdown_plus` 和 `flutter_math_fork` 渲染 Markdown 与数学公式

- **引擎**: `flutter_math_fork` — 原生 Flutter Canvas 渲染，支持完整 TeX 数学语法
- **块级公式**: `Math.tex(formula, mathStyle: MathStyle.display)`，居中卡片容器
- **内联公式**: `Math.tex(formula, mathStyle: MathStyle.text)`，通过 `WidgetSpan` 嵌入文本流
- **渲染能力**: 分数（上下堆叠+水平分数线）、根号（包围表达式）、积分/求和（上下限）、矩阵、括号自动缩放等
- **解析失败**: 回退到 monospace 原文显示，不阻塞 UI
- **智能检测**: `hasLatexContent()` 自动区分 `$...$` 数学公式与普通文本中的 `$` 符号
- **`MarkdownWithLatex`**: 自动检测→走 TeX 渲染，否则走 `MarkdownBody`；支持传入 `textStyle` 供分享长图使用

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

`_getModel(mp)` 按优先级查找当前对话使用的 Chat 模型:
1. 对话绑定的 `modelId` (优先)
2. `pendingModelId` (对话创建前暂存)
3. 草稿对话设置中的 `modelId`
4. 全局 `lastChatModelId`
5. Chat 分类列表中第一个模型 (兜底)

## API 参数策略

- OpenAI 兼容接口发送 `thinking: {type: enabled|disabled}` 显式控制思考能力
- Ollama 使用 `think` 布尔值控制思考能力
- Anthropic 保持标准 `/messages` 字段，额外能力由 `extraParams` 显式覆盖或补充
