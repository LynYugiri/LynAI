# 页面与路由

## 导航结构

```
main.dart
  └── HomePage (IndexedStack + BottomNavigationBar, 3个Tab)
        ├── Tab 0: HistoryPage
        ├── Tab 1: ChatPage (含侧边Drawer历史列表, 对话设置面板)
        └── Tab 2: SettingsPage
              ├── push→ AboutPage (跨平台兼容)
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
- **功能**: 底部三Tab导航, IndexedStack保持状态。Stack叠加全局背景图+半透明遮罩+可选的BackdropFilter模糊。背景图存在性检查结果缓存于状态中，避免重复同步I/O调用。

### 2. HistoryPage
- **文件**: `lib/pages/history_page.dart`
- **功能**: 历史对话列表, 支持搜索, 搜索结果高亮, 点击继续对话, 长按删除。

### 3. ChatPage
- **文件**: `lib/pages/chat_page.dart`
- **核心功能**:
  - **输入区**: 多行文本输入框(移动端回车换行, 桌面端Shift+Enter换行/Enter发送)
  - **底部菜单栏**: 模型选择器, 对话设置(语音/图片模型选择+提示词), 思考开关(默认开), 附件(+图片), 语音/发送按钮
  - **消息渲染**: Markdown + LaTeX (内联`$...$`/行内WidgetSpan, 块级`$$...$$`/带标签卡片, 支持`\[...\]`和`\(...\)`)
  - **思考过程**: 默认折叠, 小字号斜体灰色, 各对话独立保存
  - **操作按钮**: 复制/截图分享/重试(灰色小图标); 无内容或失败时仅显示重试按钮
  - **流式**: SSE逐chunk更新`updateLastMessage()`
  - **语音链路**: 录音(使用系统locale)→语音模型转写→当前模型回复
  - **图片链路**: 图片→(若已配置图片转述模型则先转述)→当前模型回复
     - 未配置图片模型时: 将图片文件名及大小作为文本消息发送给当前模型继续对话
     - 已配置图片模型时: 图片模型先描述, 再将描述文字发送给当前模型
  - **对话设置**: 底部弹出面板, 可设置系统提示词(支持多套模板切换/新增/编辑/删除)、语音/图片模型选择, 自定义图片提示词
  - **重试**: 支持编辑用户消息后重试, 多次重试可历史导航(< >)
  - **编辑消息**: 点击用户消息旁的编辑图标可编辑后重发, 点击历史消息可在该位置开始新对话分支
- **状态**: 对话ID, 思考开关(true), 流式标记, 各对话思考Map, 重试历史链

### 4. SettingsPage
- **文件**: `lib/pages/settings_page.dart`
- **功能**: 4个卡片入口: About, Background, API, Theme

### 5. ApiModelsPage
- **文件**: `lib/pages/api_models_page.dart`
- **功能**: 模型配置列表, 拖拽排序, 点击编辑, FAB添加

### 6. EditModelPage
- **文件**: `lib/pages/api_models_page.dart` (同文件)
- **功能**: 表单字段
  - 提供商名称 / API类型(使用`initialValue`绑定) / Endpoint(点击展开14种预设) / API Key(眼睛切换可见)
  - 获取模型按钮: 从Endpoint拉取模型列表(合并不覆盖已存在模型, Ollama自动去除`:latest`后缀)
  - 模型列表: 逐行添加+启用开关+删除, 底部输入框+加号
  - 高级选项(可折叠): Max Tokens / Temperature / Top P

### 7. ThemePage
- **文件**: `lib/pages/theme_page.dart`
- **功能**: 36种预设颜色圆点(含樱花粉/薰衣草紫/薄荷绿等), HSV调色板(色相条+饱和度/亮度面板+色相感知的亮度条), 实时预览, 主题模式切换(浅色/深色/跟随系统)

### 8. BackgroundPage
- **文件**: `lib/pages/background_page.dart`
- **功能**: 图片选择(image_picker), 模糊开关, 模糊量滑块(0-20), 实时预览

### 9. AboutPage
- **文件**: `lib/pages/about_page.dart`
- **功能**: 应用信息, 跨平台动态显示当前运行平台(使用`defaultTargetPlatform`, 兼容Web)
