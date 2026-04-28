# 页面与路由

## 导航结构

```
main.dart
  └── HomePage (IndexedStack + BottomNavigationBar, 3个Tab)
        ├── Tab 0: HistoryPage
        ├── Tab 1: ChatPage (含侧边Drawer历史列表)
        │     └── 按钮跳转→ Tab 2 (设置)
        └── Tab 2: SettingsPage
              ├── push→ AboutPage
              ├── push→ BackgroundPage
              ├── push→ ApiModelsPage
              │     └── push→ EditModelPage (全屏编辑表单，含高级选项)
              └── push→ ThemePage
```

路由方式：**命令式** `Navigator.push(MaterialPageRoute)`，无命名路由。ChatPage可通过"设置"按钮切到Tab 2。

---

## 页面清单

### 1. LynAIApp / _SplashScreen
- **文件**: `lib/main.dart`
- **功能**: 应用入口，初始化Provider加载持久化数据，显示启动页(Logo+加载动画)，完成后跳转HomePage。
- **关键点**: MultiProvider 注册3个Provider；`_loadData()` 等待各Provider加载完成。

### 2. HomePage
- **文件**: `lib/pages/home_page.dart`
- **功能**: 主页框架，底部三Tab导航(历史/对话/设置)，IndexedStack保持页面状态。支持全局背景图片（Stack+Image+Blur覆盖）。
- **关键点**: Scaffold透明背景，通过Theme包装传递 `scaffoldBackgroundColor: transparent`；`onNavigateToSettings` 回调从ChatPage切到设置Tab。
- **依赖Provider**: SettingsProvider

### 3. HistoryPage
- **文件**: `lib/pages/history_page.dart`
- **功能**: 历史对话列表，支持搜索(按标题和内容)，搜索结果高亮(黄色背景)，点击继续对话，长按删除。
- **核心方法**: `_buildHighlightedText()` 实现搜索高亮
- **依赖Provider**: ConversationProvider

### 4. ChatPage
- **文件**: `lib/pages/chat_page.dart`
- **功能**: 核心AI对话界面。
  - **输入区**: 模型选择器（点展开列表，▲▼箭头切换）、多行输入框、思考模式开关（默认开启，关闭时API显式传递禁用参数）、附件菜单(+)、语音/发送按钮
  - **消息渲染**: Markdown + LaTeX（`$...$`内联公式、`$$...$$`块级公式，支持Unicode映射），用户/AI气泡区分
  - **思考过程**: 默认折叠，保留每次对话的思考内容
  - **操作按钮**: AI消息下方显示 复制/分享(截图)/重试 小按钮
  - **侧边Drawer**: 搜索历史对话，支持删除(按钮/长按)
  - **流式响应**: SSE流式接收，实时逐字更新
  - **语音输入**: 设置语音模型后，录音→语音模型转写→发送给当前对话模型
  - **图片转述**: 设置图片模型后，图片→图片模型描述→发送给当前对话模型
- **状态**: 对话ID、思考开关(默认true)、思考折叠(default false)、流式中状态、各对话思考内容Map
- **依赖Provider**: ConversationProvider, ModelConfigProvider, SettingsProvider

### 5. SettingsPage
- **文件**: `lib/pages/settings_page.dart`
- **功能**: 设置中心，分两组：
  - **基本设置**: 关于、背景、API、主题
  - **功能模型配置**: 语音转文字模型(选择/清除)、图片文件转述模型(选择/清除)、图片转述提示词(自定义)
- **依赖Provider**: SettingsProvider, ModelConfigProvider

### 6. AboutPage
- **文件**: `lib/pages/about_page.dart`
- **功能**: 应用信息展示：名称、版本(1.0.0)、描述、技术栈列表。**平台字段动态显示**（Android/iOS/macOS/Linux/Windows）。

### 7. BackgroundPage
- **文件**: `lib/pages/background_page.dart`
- **功能**: 背景图片选择(image_picker从相册)、模糊效果开关(BackdropFilter+ImageFilter.blur)、模糊程度滑块。背景应用于整个App。

### 8. ApiModelsPage
- **文件**: `lib/pages/api_models_page.dart`
- **功能**: AI模型配置列表，支持拖拽排序(ReorderableListView)、点击编辑、FAB添加。
- **子页面**: EditModelPage (含高级选项)
- **依赖Provider**: ModelConfigProvider

### 9. EditModelPage (ApiModelsPage 内部类)
- **文件**: `lib/pages/api_models_page.dart` (同文件)
- **功能**: 添加/编辑模型配置的表单。字段：
  - 模型名称、API类型(OpenAI/Ollama/Anthropic/Custom)
  - API端点URL、API密钥(带眼睛图标可见性切换)、模型标识名
  - **高级选项**(可折叠): Max Tokens、Temperature、Top P
- **模式**: 编辑 vs 新建

### 10. ThemePage
- **文件**: `lib/pages/theme_page.dart`
- **功能**: 主题颜色选择器。15种预设Material颜色 + 自定义HSL色相滑块。实时预览。
- **依赖Provider**: SettingsProvider
