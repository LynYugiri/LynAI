# 页面与路由

## 导航结构

```
main.dart
  └── HomePage (IndexedStack + BottomNavigationBar, 3个Tab)
        ├── Tab 0: FeaturePage
        ├── Tab 1: ChatPage (含侧边Drawer历史列表, 对话设置面板)
        └── Tab 2: SettingsPage
              ├── push→ AboutPage (跨平台兼容)
              ├── push→ BackgroundPage (全局背景+模糊)
              ├── push→ ApiModelsPage
              │     └── ApiCategoryPage → EditModelPage (分类配置/Endpoint预设/模型获取/多模型管理)
              └── push→ ThemePage (36预设+HSV调色板)
```

路由方式: **命令式** `Navigator.push(MaterialPageRoute)`。

---

## 页面清单

### 1. HomePage
- **文件**: `lib/pages/home_page.dart`
- **功能**: 底部三Tab导航, IndexedStack保持状态。Stack叠加全局背景图+半透明遮罩+可选的BackdropFilter模糊。背景图存在性检查结果缓存于状态中，避免重复同步I/O调用。
- **Tab**: 功能 / 对话 / 设置。功能页切换角色时会跳转到对话页并触发新对话上下文刷新。
- **状态保持**: `IndexedStack` 保留三个主 Tab 的滚动、输入和选择状态，切换页面不会重建整个对话页。
- **背景策略**: 背景图路径来自 `AppSettings.backgroundImagePath`；文件不存在时回退纯色主题背景，避免同步读取异常影响首屏。

### 2. FeaturePage
- **文件**: `lib/pages/feature_page.dart`
- **功能**: 功能集合页，包含对话历史、日程表、笔记。对话历史支持搜索/高亮/角色切换/删除；日程表支持月/周/年视图、跨天日程和本地时区显示；笔记支持 Markdown/LaTeX 编辑与导出，预览中的代码块和块级公式支持复制与单图导出。
- **功能切换**: AppBar 左侧入口可在对话历史、日程表、笔记之间切换，最近使用功能保存在 `AppSettings.lastFeature`。
- **对话历史**: 按当前角色和其他角色分组展示；点击其他角色分组会切换角色并进入对话页。
- **日程表**: 月视图支持选中日期查看摘要，周时间轴顶部日期在纵向滚动时保持可见，横向滚动按连续日期衔接前后周，移动端可双指缩放，桌面端可 Ctrl/Command + 滚轮缩放，纵向下滑会自然收起月/日/年菜单、上滑再展开，并按当天可见区间截断跨天日程；年视图按月份聚合并用可换行气泡展示日程；新增日程默认使用当前选中日期。
- **笔记**: 支持列表、详情、编辑/预览模式、自动保存、重命名、删除、导出 Markdown、导出图片。
- **导出图片**: 笔记和待办导出会通过 `ScreenshotController.captureFromLongWidget()` 捕获长图，Markdown 预览复用 `MarkdownWithLatex`，代码块会在长图模式下自动换行。
- **生命周期注意**: 新建、导入、导出等操作包含文件选择和磁盘写入，异步返回后必须检查 `mounted` 再更新 UI。

### 3. ChatPage
- **文件**: `lib/pages/chat_page.dart`
- **核心功能**:
  - **输入区**: 多行文本输入框(移动端回车换行, 桌面端Shift+Enter换行/Enter发送)
  - **底部菜单栏**: 模型选择器, 对话设置(语音/OCR/文件识别模型选择+提示词), 思考开关(默认开), OCR 开关, 文件识别开关, 附件(文件/图片/拍照), 语音/发送按钮
  - **消息渲染**: Markdown + LaTeX (内联`$...$`/行内WidgetSpan, 块级`$$...$$`/带标签卡片, 支持`\[...\]`和`\(...\)`)，代码块使用 Hurmit Nerd Font 与 One Dark Pro 风格高亮
  - **思考过程**: 默认折叠, 小字号斜体灰色, 各对话独立保存；最后一条回复在模型不返回可见 reasoning 时显示说明提示
  - **操作按钮**: 复制/长图分享/重试(灰色小图标); 无内容或失败时仅显示重试按钮
- **流式**: SSE逐chunk更新`updateLastMessage()`
- **流式错误**: 服务端错误会显示在最后一条 assistant 消息中；已有正文会保留，旧思考内容会按本轮结果清空或覆盖
  - **停止生成**: 流式回复中发送按钮切换为停止按钮，可取消当前请求并保留已生成内容
  - **语音链路**: 未配置接口时用系统语音识别；配置语音转写接口后录音→转写→回填输入框
  - **附件链路**: 文件选择、多图选择、移动端拍照或桌面端剪贴板粘贴→应用私有目录保存→OCR/文件识别或直传多模态内容→当前模型回复
  - **长图分享**: 选择多条消息后生成分享长图，分享图支持 Markdown/LaTeX，桌面端可复制到剪贴板；消息内代码块和块级公式可单独复制源码或导出图片
  - **对话设置**: 底部弹出面板, 可设置系统提示词(支持多套模板切换/新增/编辑/删除)、语音/OCR/文件识别模型选择, 自定义文件识别提示词
  - **重试**: 支持编辑用户消息后重试, 多次重试可历史导航(< >)，带附件消息会保留附件并重新构建识别上下文
  - **编辑消息**: 点击用户消息旁的编辑图标可编辑后重发, 点击历史消息可在该位置开始新对话分支；附件会随新分支保留
- **状态**: 对话ID, 思考开关(true), 流式标记, 各对话思考Map, 重试历史链

#### ChatPage 异步边界

| 操作 | 异步来源 | 防护要求 |
|------|----------|----------|
| 多图选择 | `image_picker.pickMultiImage()`、文件复制、文件大小读取 | 返回后检查 `mounted`，失败时显示 SnackBar |
| 文件选择 | `file_picker.pickFiles()`、复制到私有目录 | 每个文件复制后仍可能离开页面，最终 `setState` 前检查 `mounted` |
| 拍照 | 相机 Activity/系统页面 | 用户返回或拒绝权限时安全退出 |
| 剪贴板图片 | `super_clipboard` 异步读取二进制 | 写入文件后检查 `mounted` 再加入附件列表 |
| 语音录音 | 权限检查、临时目录、录音器启动 | 使用 request generation 取消快速松手后的过期启动 |
| 流式请求 | HTTP stream subscription | 通过 `_streamGen` 忽略旧流事件，停止生成会取消订阅 |

#### 录音状态机

```text
idle
  ├─ 长按且未配置语音模型 → system speech listening → 松手/完成 → idle
  └─ 长按且已配置语音模型 → starting recorder
        ├─ 松手发生在 start 前 → cancel token 生效 → stop/delete temp → idle
        └─ start 成功 → recording → 松手 → transcribing → idle
```

录音文本只回填输入框，不会自动发送，避免语音识别错误直接进入对话。

### 4. SettingsPage
- **文件**: `lib/pages/settings_page.dart`
- **功能**: 4个卡片入口: About, Background, API, Theme

### 5. ApiModelsPage
- **文件**: `lib/pages/api_models_page.dart`
- **功能**: 展示 Chat、OCR、语音转文字、图片生成四类模型配置入口

### 6. ApiCategoryPage
- **文件**: `lib/pages/api_models_page.dart` (同文件)
- **功能**: 分类内模型配置列表, 拖拽排序, 点击编辑, FAB添加

### 7. EditModelPage
- **文件**: `lib/pages/api_models_page.dart` (同文件)
- **功能**: 表单字段
  - 提供商名称 / API类型 / Endpoint(点击展开对应分类预设) / API Key 或 AppKey(眼睛切换可见)
  - OCR/语音分类额外填写 AppID，并使用固定接口模型名
  - Chat 获取模型按钮: 从 Endpoint 拉取模型列表(合并不覆盖已存在模型, Ollama自动去除`:latest`后缀)
  - 模型列表: 逐行添加+启用开关+删除, 底部输入框+加号
  - 高级选项(可折叠): Max Tokens / Temperature / Top P
- **高级参数清空**: 清空 Max Tokens / Temperature / Top P 后会传入 `null`，`ModelConfig.copyWith()` 使用 sentinel 保证旧值被真正清除。
- **多子模型能力**: 每个 `ModelEntry` 可单独维护视觉、思考、工具和采样参数；当前激活子模型参数优先于提供商级参数。

### 7.1 DataManagementPage
- **文件**: `lib/pages/data_management_page.dart`
- **功能**: 备份导出、备份读取预览、按分区导入、冲突处理。
- **导出内容**: 可选择对话、设置、模型配置、日程、笔记、待办等数据。选择模型配置时会包含 API Key，导出的 zip 应按敏感文件处理。
- **导入流程**: 先读取 zip 得到 `BackupArchive`，再根据用户勾选生成 `BackupSelection` 和 `ImportPlan`。导入完成后会清空预览状态并显示新增/覆盖/跳过数量。
- **生命周期注意**: 文件选择、zip 解析、导入执行和系统分享都可能在页面关闭后返回，所有 UI 更新前需要 `mounted` 防护。

### 8. ThemePage
- **文件**: `lib/pages/theme_page.dart`
- **功能**: 36种预设颜色圆点(含樱花粉/薰衣草紫/薄荷绿等), HSV调色板(色相条+饱和度/亮度面板+色相感知的亮度条), 实时预览, 主题模式切换(浅色/深色/跟随系统)
- **主题数据**: `themeColor` 是当前实际 seed color，`baseThemeColor` 用于记录用户选中的基础色，HSV 调整时同步生成 Material 3 `ColorScheme.fromSeed`。

### 9. BackgroundPage
- **文件**: `lib/pages/background_page.dart`
- **功能**: 图片选择(image_picker), 模糊开关, 模糊量滑块(0-20), 实时预览

### 10. AboutPage
- **文件**: `lib/pages/about_page.dart`
- **功能**: 应用信息, 跨平台动态显示当前运行平台(使用`defaultTargetPlatform`, 兼容Web)

### 11. MathLiveFormulaEditorPage
- **文件**: `lib/pages/mathlive_formula_editor_page.dart`
- **功能**: 使用本地 `assets/mathlive/editor.html` 提供可视化公式编辑器，不支持 WebView 的平台回退到源码模式。
- **通信**: WebView 通过 `MathLiveBridge` JavaScript channel 发送 `ready`、`input`、`keyboard-visibility` 和 `error` 事件。
- **生命周期注意**: bridge 回调入口会检查 `mounted`，防止用户快速关闭页面后 WebView 继续触发 `setState`。

## 页面发布检查

| 页面 | 重点手测 |
|------|----------|
| `ChatPage` | 发送、停止、失败重试、编辑后重发、附件重试、长按录音快速松手 |
| `FeaturePage` | 历史搜索、角色切换、跨天日程、笔记自动保存、长图导出 |
| `ApiModelsPage` | 添加/删除模型、清空高级参数、拖拽排序、获取模型列表 |
| `DataManagementPage` | 导出含 API Key 的备份、读取旧备份、冲突导入、取消文件选择 |
| `MathLiveFormulaEditorPage` | 快速进入退出、源码模式、WebView ready 慢加载 |
| `ThemePage` | 预设色、HSV 拖动、深浅色切换、重启后恢复 |
