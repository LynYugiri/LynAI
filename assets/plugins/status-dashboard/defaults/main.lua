-- 状态工具处理器。
--
-- 本文件位于 defaults/ 目录，是状态内置插件的出厂 Lua 入口。
-- 如果插件根目录不存在 main.lua，PluginLuaRuntimeService 会自动回退读取
-- defaults/main.lua。这样用户可以编辑 HTML/CSS 功能页，而不会覆盖核心工具。
--
-- 每个函数都对应 plugin.json 中 tools 声明的 handler。模型调用工具时，
-- ToolCallService 会找到同名插件工具，再由 PluginLuaRuntimeService 调用这里的
-- Lua 全局函数。
--
-- 返回值约定：
-- __lynai_function 表示请求 LynAI 执行一个通用函数，适合读操作和 HTTP 请求。
-- __lynai_command 与 __lynai_function 当前同样由 Dart 延迟执行，语义上用于写操作。
-- args 是传给 LynAI function 的参数表。

function status_files(args)
  -- 列出插件目录文件。这里隐藏 defaults/ 出厂模板，方便模型只关注用户可见文件。
  return {__lynai_function = 'plugin.file.list', args = {}}
end

function status_read(args)
  -- 读取指定插件文件。路径安全和可读性检查由 Dart 端插件仓储统一处理。
  return {__lynai_function = 'plugin.file.read', args = {path = args.path}}
end

function status_write(args)
  -- 写入插件可编辑文件。非 editableFiles 声明的文件会被 Dart 端拒绝。
  return {__lynai_command = 'plugin.file.write', args = {path = args.path, content = args.content}}
end

function status_delete(args)
  -- 删除根目录中的自定义文件，使对应资源回退到 defaults/ 出厂模板。
  return {__lynai_command = 'plugin.file.delete', args = {path = args.path}}
end

function status_reset(args)
  -- 清理所有自定义文件，恢复插件出厂状态。
  return {__lynai_command = 'plugin.restore', args = {}}
end

function status_fetch(args)
  -- 通过 LynAI 的 http.fetch 代理访问外部 API。需要 network:access 权限。
  return {__lynai_function = 'http.fetch', args = args}
end
