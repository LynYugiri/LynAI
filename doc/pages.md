# 页面与路由

## 导航结构

```
main.dart
  └── HomePage (IndexedStack + BottomNavigationBar, 3个Tab)
        ├── Tab 0: HistoryPage
        ├── Tab 1: ChatPage (含侧边Drawer历史列表, 对话设置面板)
        └── Tab 2: SettingsPage
              ├── push→ AboutPage (动态显示当前平台)
              ├── push→ BackgroundPage (全局背景+模糊)
              ├── push→ ApiModelsPage
              │     └── push→ EditModelPage (含Endpoint预设/模型获取/多模型管理)
              └── push→ ThemePage (36预设+HSV调色板)
```

路由方式: **命令式** `Navigator.push(MaterialPageRoute)`。

---

## 页面清单

### 1. HomePage
- **文件**: `lib/pages/home_page.dart`
- **功能**: 底部三Tab导航, IndexedStack保持状态。Stack叠加全局背景图+半透明遮罩+可选的BackdropFilter模糊。

### 2. HistoryPage
- **文件**: `lib/pages/history_page.dart`
- **功能**: 历史对话列表, 支持搜索, 搜索结果高亮, 点击继续对话, 长按/按钮删除。

### 3. ChatPage
- **文件**: `lib/pages/chat_page.dart`
- **核心功能**:
  - **输入区**: 模型选择器(点开列表选Provider→子模型), 多行输入, 思考开关(默认开), 附件(+图片), 语音/发送按钮
  - **消息渲染**: Markdown + LaTeX (内联`$...$`/行内WidgetSpan, 块级`$$...$$`/带标签卡片, 支持`\[...\]`和`\(...\)`)
  - **思考过程**: 默认折叠, 小字号斜体灰色, 各对话独立保存
  - **操作按钮**: 复制/截图分享/重试(灰色小图标)
  - **流式**: SSE逐chunk更新`updateLastMessage()`
  - **语音链路**: 录音→语音模型转写→当前模型回复
  - **图片链路**: 图片→图片模型描述→当前模型回复
  - **对话设置**: 底部弹出面板, 可选择语音/图片模型, 自定义图片提示词
- **状态**: 对话ID, 思考开关(true), 流式标记, 各对话思考Map

### 4. SettingsPage
- **文件**: `lib/pages/settings_page.dart`
- **功能**: 4个卡片入口: About, Background, API, Theme

### 5. ApiModelsPage
- **文件**: `lib/pages/api_models_page.dart`
- **功能**: 模型配置列表, 拖拽排序, 点击编辑, FAB添加

### 6. EditModelPage
- **文件**: `lib/pages/api_models_page.dart` (同文件)
- **功能**: 表单字段
  - 提供商名称 / API类型 / Endpoint(点击展开14种预设) / API Key(眼睛切换可见)
  - 获取模型按钮: 从Endpoint拉取模型列表(合并不覆盖)
  - 模型列表: 默认展开, 逐行添加+启用开关+删除, 底部输入框+加号
  - 高级选项(可折叠): Max Tokens / Temperature / Top P

### 7. ThemePage
- **文件**: `lib/pages/theme_page.dart`
- **功能**: 36种预设颜色圆点(含樱花粉/薰衣草紫/薄荷绿等), HSV调色板(色相条+饱和度/亮度面板+亮度条), 实时预览

### 8. BackgroundPage
- **文件**: `lib/pages/background_page.dart`
- **功能**: 图片选择(image_picker), 模糊开关, 模糊量滑块, 实时预览

### 9. AboutPage
- **文件**: `lib/pages/about_page.dart`
- **功能**: 应用信息, 动态显示当前运行平台
