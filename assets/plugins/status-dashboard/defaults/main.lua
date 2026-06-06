-- 状态仪表盘工具处理器
-- 每个函数返回 {__lynai_command = 'method', args = {...}} 格式，
-- 由 LynAI 运行时自动执行并将结果返回给 AI。

function status_files(args)
  return {__lynai_function = 'plugin.file.list', args = {}}
end

function status_read(args)
  return {__lynai_function = 'plugin.file.read', args = {path = args.path}}
end

function status_write(args)
  return {__lynai_command = 'plugin.file.write', args = {path = args.path, content = args.content}}
end

function status_delete(args)
  return {__lynai_command = 'plugin.file.delete', args = {path = args.path}}
end

function status_reset(args)
  return {__lynai_command = 'plugin.restore', args = {}}
end

function status_fetch(args)
  return {__lynai_function = 'http.fetch', args = args}
end
