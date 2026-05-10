# LynAI

跨平台 AI 对话客户端，基于 Flutter 开发，支持 OpenAI / Ollama / Anthropic 等多种 API，覆盖 Android、iOS、Linux、macOS、Windows 平台。当前版本：`2.2.0`。

## 截图

| 设置 | 对话 |
|------|------|
| ![设置](./images/demo/1.png) | ![对话](./images/demo/2.png) |

## 功能

- **分类模型管理** — Chat、OCR、语音转文字、图片生成四类配置独立管理，可拖拽排序
- **多提供商支持** — OpenAI 兼容接口、Ollama、Anthropic、vivo 相关能力，可自定义 Endpoint
- **多子模型切换** — 每个提供商下可维护多个子模型，聊天中快速切换
- **流式对话** — SSE 实时逐字渲染，聊天体验流畅
- **Markdown + LaTeX** — 支持代码块、公式渲染 (内联 `$...$` / 块级 `$$...$$`)
- **思考过程** — 支持 DeepSeek 等推理模型的思考链展示
- **语音输入** — 可使用系统语音识别，或配置 vivo 长语音转写接口
- **图片理解** — 支持 OCR 文字识别，也可用多模态 Chat 模型进行图片识别
- **图片生成接口** — 可配置 OpenAI Images 或 vivo 原生图片生成接口
- **长图分享** — 选择多条聊天记录生成长图，支持 Markdown/LaTeX 渲染，桌面端可复制到剪贴板
- **功能页** — 集中管理对话历史、日程表和笔记，支持快速切换
- **历史搜索** — 按标题 / 内容搜索历史对话，支持角色分组、角色切换和关键词高亮
- **角色管理** — 为不同角色保存系统提示词、默认模型和主题色，新对话自动继承角色设置
- **日程表** — 支持月历、周时间轴、全年总览，新建日程默认使用当前选中日期
- **笔记** — 支持 Markdown/LaTeX 编辑、自动保存、重命名、导出 Markdown 和导出图片
- **主题定制** — 36 种预设色 + HSV 调色板自由组合
- **背景自定义** — 支持图片背景 + 毛玻璃效果
- **跨会话设置** — 每个对话保存模型、思考开关、系统提示词、语音/OCR/图片识别设置快照

## 支持平台

| 平台 | 状态 |
|------|------|
| Android | ✅ |
| iOS | ✅ |
| Linux | ✅ |
| macOS | ✅ |
| Windows | ✅ |

## 键盘快捷键 (桌面端)

| 操作 | 快捷键 |
|------|--------|
| 发送消息 | `Enter` |
| 换行 | `Shift + Enter` |

> 移动端回车键默认换行。

## 构建

```bash
git clone https://github.com/lynyugiri/lynai.git
cd lynai
flutter pub get
flutter run
```

平台构建:

```bash
flutter build apk --split-per-abi    # Android
flutter build linux                  # Linux
flutter build windows                # Windows
flutter build macos                  # macOS
flutter build ios                    # iOS (需 macOS)
```

需要 Flutter SDK ^3.11.5。

## 模型配置说明

进入 `设置 -> API` 后按类别添加配置：

| 类别 | 用途 | 说明 |
|------|------|------|
| Chat | 普通对话、流式回复、多模态图片识别 | 支持 OpenAI 兼容、Ollama、Anthropic、自定义接口 |
| OCR | 图片中文字提取 | 当前内置 vivo OCR 请求格式，需填写 AppID 与 AppKey |
| 语音转文字 | 录音文件转写 | 当前内置 vivo 长语音转写流程，需填写 AppID 与 AppKey |
| 图片生成 | 文生图/图生图接口配置 | 支持 OpenAI Images 格式和 vivo 原生接口 |

对话页底部的 `对话设置` 会把当前对话的模型、系统提示词、语音/OCR/图片识别设置保存为快照。切换历史对话时，会恢复该对话自己的设置。

## 聊天与分享

- 桌面端输入框支持 `Enter` 发送、`Shift + Enter` 换行，并支持 `Ctrl/Cmd + V` 粘贴图片。
- 选择图片后即使没有输入文字也可以直接发送；流式回复过程中可点击停止按钮中断生成。
- 图片附件会复制到应用私有目录，避免系统清理临时文件后历史消息丢图。
- 开启“图片识别”后，发送图片前会先用选中的多模态 Chat 模型识别图片，并把识别文本追加给当前对话模型。
- 未开启图片识别但配置了 OCR 时，会先提取图片文字；未配置 OCR 时，仅把图片文件名和大小作为上下文发送。
- 长图分享使用长内容截图，选中较多消息时会自动降低像素比以减少内存压力。

## 功能页

底部导航的 `功能` 页由 `lib/pages/feature_page.dart` 实现，包含三个入口：

| 功能 | 说明 |
|------|------|
| 对话历史 | 按角色分组展示历史对话，支持标题/内容搜索、关键词高亮、长按删除，点击后回到对应对话 |
| 日程表 | 提供月历、周时间轴、全年总览；支持新增、编辑、删除日程和备注 |
| 笔记 | 支持 Markdown/LaTeX 预览、自动保存、自动换行开关、导出 Markdown、导出图片 |

角色切换会同步影响新对话的系统提示词、默认模型和可选主题色；已创建的对话会保留自己的设置快照。

## 开发验证

```bash
flutter analyze
flutter test
```

`flutter analyze` 用于静态检查 Dart/Flutter 代码，`flutter test` 运行项目测试。提交前建议至少执行这两项。

## 技术栈

| 类别 | 技术 |
|------|------|
| 框架 | Flutter SDK ^3.11.5 |
| 状态管理 | Provider + ChangeNotifier |
| HTTP | http |
| 持久化 | SharedPreferences (JSON) |
| Markdown | flutter_markdown_plus |
| LaTeX | flutter_math_fork |
| 语音识别 | speech_to_text |
| 录音 | record |
| 图片选择 | image_picker |
| 剪贴板 | super_clipboard |
| 分享 | share_plus |
| 截图 | screenshot |
| UI | Material 3, ColorScheme.fromSeed |

## CI/CD

GitHub Actions 自动构建 (`.github/workflows/build.yml`):

| 平台 | 架构 | Runner |
|------|------|--------|
| Android APK | arm64-v8a, armeabi-v7a, x86_64 | ubuntu-latest |
| Linux | x86_64 | ubuntu-latest |
| Windows | x86_64 | windows-latest |

## 项目文档

- [页面与路由](doc/pages.md)
- [架构概览](doc/architecture.md)
- [数据模型](doc/models.md)
- [状态管理](doc/providers.md)
- [API 服务](doc/services.md)

## 许可证

[GNU General Public License v3.0](LICENSE)
