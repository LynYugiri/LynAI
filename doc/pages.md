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

### 2. FeaturePage
- **文件**: `lib/pages/feature_page.dart`
- **功能**: 功能集合页，包含对话历史、日程表、笔记。对话历史支持搜索/高亮/角色切换/删除；日程表支持月/周/年视图；笔记支持 Markdown/LaTeX 编辑与导出，预览中的代码块和块级公式支持复制与单图导出。
- **功能切换**: AppBar 左侧入口可在对话历史、日程表、笔记之间切换，最近使用功能保存在 `AppSettings.lastFeature`。
- **对话历史**: 按当前角色和其他角色分组展示；点击其他角色分组会切换角色并进入对话页。
- **日程表**: 月视图支持选中日期查看摘要，周视图以时间轴展示，年视图按月份聚合；新增日程默认使用当前选中日期。
- **笔记**: 支持列表、详情、编辑/预览模式、自动保存、重命名、删除、导出 Markdown、导出图片。

### 3. ChatPage
- **文件**: `lib/pages/chat_page.dart`
- **核心功能**:
  - **输入区**: 多行文本输入框(移动端回车换行, 桌面端Shift+Enter换行/Enter发送)
  - **底部菜单栏**: 模型选择器, 对话设置(语音/OCR/图片识别模型选择+提示词), 思考开关(默认开), 图片识别开关, 附件(+图片), 语音/发送按钮
  - **消息渲染**: Markdown + LaTeX (内联`$...$`/行内WidgetSpan, 块级`$$...$$`/带标签卡片, 支持`\[...\]`和`\(...\)`)，代码块使用 One Dark Pro 风格高亮
  - **思考过程**: 默认折叠, 小字号斜体灰色, 各对话独立保存
  - **操作按钮**: 复制/长图分享/重试(灰色小图标); 无内容或失败时仅显示重试按钮
  - **流式**: SSE逐chunk更新`updateLastMessage()`
  - **停止生成**: 流式回复中发送按钮切换为停止按钮，可取消当前请求并保留已生成内容
  - **语音链路**: 未配置接口时用系统语音识别；配置语音转写接口后录音→转写→回填输入框
  - **图片链路**: 图片选择或剪贴板粘贴→应用私有目录保存→OCR 或多模态图片识别→当前模型回复
  - **长图分享**: 选择多条消息后生成分享长图，分享图支持 Markdown/LaTeX，桌面端可复制到剪贴板；消息内代码块和块级公式可单独复制源码或导出图片
  - **对话设置**: 底部弹出面板, 可设置系统提示词(支持多套模板切换/新增/编辑/删除)、语音/OCR/图片识别模型选择, 自定义图片识别提示词
  - **重试**: 支持编辑用户消息后重试, 多次重试可历史导航(< >)
  - **编辑消息**: 点击用户消息旁的编辑图标可编辑后重发, 点击历史消息可在该位置开始新对话分支
- **状态**: 对话ID, 思考开关(true), 流式标记, 各对话思考Map, 重试历史链

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

### 8. ThemePage
- **文件**: `lib/pages/theme_page.dart`
- **功能**: 36种预设颜色圆点(含樱花粉/薰衣草紫/薄荷绿等), HSV调色板(色相条+饱和度/亮度面板+色相感知的亮度条), 实时预览, 主题模式切换(浅色/深色/跟随系统)

### 9. BackgroundPage
- **文件**: `lib/pages/background_page.dart`
- **功能**: 图片选择(image_picker), 模糊开关, 模糊量滑块(0-20), 实时预览

### 10. AboutPage
- **文件**: `lib/pages/about_page.dart`
- **功能**: 应用信息, 跨平台动态显示当前运行平台(使用`defaultTargetPlatform`, 兼容Web)
