# LynAI

跨平台 AI 对话应用，支持多种 AI 模型接口，基于 Flutter 开发。

## 功能

- **多模型支持** — OpenAI 兼容、Ollama、Anthropic、自定义 API，支持从 Endpoint 自动获取模型列表
- **流式响应** — SSE 实时逐字渲染，Markdown + LaTeX（`$...$`/`\[...\]`）公式显示
- **思考模式** — 默认开启，可折叠查看推理过程；关闭时显式禁用模型思考
- **语音输入** — 设置语音模型后录音→转写→发送，支持中文
- **图片转述** — 设置图片模型后发送图片自动描述再提问
- **对话管理** — 侧边栏历史记录，搜索、删除、继续对话
- **自定义背景** — 全局背景图片 + 毛玻璃模糊效果
- **主题系统** — 36 种预设颜色 + HSV 调色板自由选色

## 构建

```bash
git clone https://github.com/lynyugiri/lynai.git
cd lynai
flutter pub get
flutter run
```

需要 Flutter SDK ^3.11.5。

## 技术栈

| 类别 | 技术 |
|------|------|
| 框架 | Flutter |
| 状态管理 | Provider + ChangeNotifier |
| HTTP | http |
| 持久化 | SharedPreferences (JSON) |
| Markdown | flutter_markdown |
| 语音 | speech_to_text |
| 分享 | share_plus |

## 许可证

MIT
