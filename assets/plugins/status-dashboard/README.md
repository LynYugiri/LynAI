# 状态插件

## 用途

状态是 LynAI 的内置插件，用于展示笔记、待办、对话和系统状态统计，并提供一组插件文件管理工具。

## 文件结构

`plugin.json` 是插件清单，声明权限、Lua 入口、AI tools 和功能页。

`defaults/main.lua` 是 Lua 工具入口。当前插件没有在根目录维护自定义 `main.lua`，运行时会自动回退到 `defaults/main.lua`。

`defaults/status.html` 和 `defaults/status.css` 是功能页的默认模板。用户可以在插件管理页编辑根目录下的 `status.html` 和 `status.css`，未编辑时由系统回退读取 defaults 文件。

`icon.svg` 是插件图标。

## Lua 工具

`status_files` 列出插件目录内文件。

`status_read` 读取指定插件文件。

`status_write` 写入或创建指定可编辑文件。

`status_delete` 删除指定可编辑文件，使其回退到出厂默认内容。

`status_reset` 删除所有自定义文件，恢复出厂默认状态。

`status_fetch` 通过 LynAI 的 HTTP 代理请求外部 API。

## 权限说明

`notes:read` 和 `todos:read` 用于统计笔记与待办数据。

`files:write` 用于插件文件管理工具。

`storage:read` 和 `storage:write` 保留给插件私有存储能力。

`network:access` 用于 `status_fetch`。

`webview:bridge` 允许功能页通过 WebView Bridge 调用 LynAI 函数。

## defaults 机制

运行时读取入口和功能页时，会优先使用插件根目录的用户自定义文件；如果根目录不存在，则回退到 `defaults/` 出厂模板。

这让内置插件可以提供默认实现，同时允许用户编辑部分声明为 `editableFiles` 的文件。

## 维护注意

`plugin.json` 和 Lua 入口属于受保护核心文件，不应通过插件文件编辑器覆盖。需要变更工具行为时，直接维护源码目录中的 `defaults/main.lua`。
