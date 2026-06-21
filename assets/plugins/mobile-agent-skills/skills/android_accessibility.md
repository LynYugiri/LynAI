# Android 无障碍自动化

当任务需要读取 Android 屏幕、点击控件、输入文本、滚动页面或调用 OCR/识图时使用。

## 原则

- 优先使用 `device.screen.query` 或 `device.node.findAll` 查找任务相关节点。
- 需要完整结构时再读取 `device.screen.snapshot`，不要默认把完整 snapshot 返回给主模型。
- 节点 `id` 只在当前无障碍快照缓存中有效；获取节点后应尽快执行 `device.node.action`，不要在点击前刷新屏幕。
- 优先使用 `device.node.action`，必要时才使用坐标 `device.tap` 或 `device.swipe`。
- 页面切换后重新读取屏幕并确认 `packageName`、标题或关键文案。
- 截图只作为 OCR/识图输入，最终返回给模型的是 OCR 文本、识图描述或结构化结论，不返回 base64。
- 读屏、查节点、等待节点属于屏幕读取；点击、输入、返回、打开应用属于设备控制。缺权限时按错误提示请求用户授权。
- Lua 可以写清晰的多步流程和循环，不要为了节省长度牺牲判断、错误处理和返回结构。

## 常用调用

```lua
local ctx = lynai.call("device.screen.query", { text = "发送", clickable = true, limit = 5 })
if not ctx.ok then return ctx end
```

```lua
local function first_node(result)
  if not result.ok then return nil, result end
  local nodes = result.result and result.result.nodes or {}
  return nodes[1], nil
end

local function click_node(node)
  if not node then
    return { ok = false, error = { code = "node_not_found", message = "未找到可点击节点" } }
  end
  return lynai.call("device.node.action", {
    nodeId = node.targetNodeId or node.id,
    action = "click"
  })
end
```

```lua
local shot = lynai.call("device.screen.screenshot", {})
if shot.ok then
  local ocr = lynai.call("model.ocr", {
    files = {{ dataBase64 = shot.result.dataBase64, mimeType = shot.result.mimeType, name = "screen.png" }}
  })
end
```

## 返回约定

- 返回 `ok`、`phase`、`summary`、少量候选节点和必要文本。
- 不返回完整截图、完整 base64、无关节点树。
- 不确定时返回结构化错误，不盲目点击或发送。
- 被用户停止时直接返回工具给出的 `user_stopped` 错误，不要继续重试。
